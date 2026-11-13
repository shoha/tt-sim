extends GutTest

## The painted look's sheet (PainterSheet, painter/sheets/core.sheet, docs/systems/painter.md): the
## shipped sheet passes its lint, the lint rejects what it must, the resolver returns a keyframe's
## own tones at its elevation, holds the ends, and blends smoothly in between.

## The largest OKLab change any role may make over one STEP_DEG of sun elevation: about one
## just-noticeable difference, so dragging the time of day never shows a jump. A keyframe pair far
## apart in colour over a short span would need more and fails here.
const MAX_STEP_DELTA := 0.02
const STEP_DEG := 0.25

const _MINIMAL_KEY := (
	"sun: oklch(0.9 0.02 90); sky: oklch(0.8 0.08 238); horizon: oklch(0.9 0.04 215);"
	+ " ambient: oklch(0.9 0.04 222); haze: oklch(0.9 0.03 228); ground: var(--meadow);"
	+ " leaf: oklch(0.6 0.1 138); bark: oklch(0.5 0.07 55); stone: oklch(0.7 0.03 80);"
	+ " path: oklch(0.8 0.06 80); roof-clay: oklch(0.55 0.13 33); roof-slate: oklch(0.5 0.04 255);"
	+ " roof-shingle: oklch(0.5 0.06 45); roof-turf: oklch(0.58 0.1 135);"
	+ " roof-thatch: oklch(0.71 0.085 84); sun-energy: 1.0; ambient-energy: 0.5;"
)


func before_each() -> void:
	PainterSheet.clear_cache()


func _sheet(summer_keys: String, extra: String = "") -> String:
	var text := ":world { --meadow: oklch(0.72 0.135 131); %s }\n" % _defaults()
	text += "@mood summer { %s }\n" % summer_keys
	for mood: String in PainterSheet.MOODS:
		if mood != "summer":
			text += "@mood %s { %s }\n" % [mood, _three_keys()]
	return text + extra


## A sheet-wide default for every DEFAULT_ROLES and DEFAULT_NUMBERS entry.
func _defaults() -> String:
	var text := ""
	for role: String in PainterSheet.DEFAULT_ROLES:
		text += "%s: oklch(0.6 0.05 100); " % role
	for prop: String in PainterSheet.DEFAULT_NUMBERS:
		text += "%s: 0.5; " % prop
	return text


func _three_keys() -> String:
	return (
		"@key night -8 { %s } @key low 6 { %s } @key high 60 { %s }"
		% [_MINIMAL_KEY, _MINIMAL_KEY, _MINIMAL_KEY]
	)


func test_the_core_sheet_passes_its_lint_and_has_every_mood() -> void:
	var text := FileAccess.get_file_as_string("res://painter/sheets/core.sheet")
	var errors := PainterSheet.lint(PainterSheet.parse(text))
	assert_eq(errors, PackedStringArray(), "core.sheet lints clean")
	var sheet := PainterSheet.load_sheet("core")
	for mood: String in PainterSheet.MOODS:
		assert_true(sheet.has(mood), "core.sheet has %s" % mood)
		assert_eq((sheet[mood] as Array).size(), 3, "%s has all three keyframes" % mood)
	assert_eq(PainterSheet.HIGH_ONLY, [] as Array[String], "no mood is on the allow-list")


func test_a_default_comes_from_the_keyframe_then_the_mood_then_the_sheet() -> void:
	var keys := _three_keys().replace(
		"@key high 60 { ", "@key high 60 { keep-grass: 0.9; floor: oklch(0.3 0.05 100); "
	)
	var mood_world := ":world { keep-flower: 0.2; } "
	var text := _sheet(keys).replace("@mood summer { ", "@mood summer { " + mood_world)
	var parsed := PainterSheet.parse(text)
	assert_eq(PainterSheet.lint(parsed), PackedStringArray())
	var sheet := PainterSheet.compile(parsed)
	assert_almost_eq(PainterSheet.number(sheet, "summer", "keep-grass", 60.0), 0.9, 1e-6)
	assert_almost_eq(PainterSheet.number(sheet, "summer", "keep-grass", -8.0), 0.5, 1e-6)
	assert_almost_eq(PainterSheet.number(sheet, "summer", "keep-flower", -8.0), 0.2, 1e-6)
	assert_almost_eq(PainterSheet.tone_lch(sheet, "summer", "floor", 60.0).x, 0.3, 1e-6)
	assert_almost_eq(PainterSheet.tone_lch(sheet, "dusk", "floor", 60.0).x, 0.6, 1e-6)


func test_the_lint_rejects_an_unknown_or_missing_default() -> void:
	var text := _sheet(_three_keys()).replace("keep-grass: 0.5;", "keep-grass: 0.5; keep-moss: 1;")
	var errors := PainterSheet.lint(PainterSheet.parse(text))
	assert_true(Array(errors).has(":world: unknown default keep-moss"))
	errors = PainterSheet.lint(PainterSheet.parse(_sheet(_three_keys()).replace("cut: 0.5;", "")))
	assert_true(Array(errors).any(func(e: String) -> bool: return e.ends_with("missing cut")))


func test_a_minimal_sheet_lints_clean() -> void:
	assert_eq(PainterSheet.lint(PainterSheet.parse(_sheet(_three_keys()))), PackedStringArray())


func test_the_lint_rejects_an_unknown_role() -> void:
	var keys := _three_keys().replace("sun-energy: 1.0;", "sun-energy: 1.0; glitter: 2;")
	var errors := PainterSheet.lint(PainterSheet.parse(_sheet(keys)))
	assert_true(Array(errors).any(func(e: String) -> bool: return e.contains("unknown role glitter")))


func test_the_lint_rejects_an_unknown_mood() -> void:
	var extra := "@mood spring { @key high 30 { %s } }" % _MINIMAL_KEY
	var errors := PainterSheet.lint(PainterSheet.parse(_sheet(_three_keys(), extra)))
	assert_true(Array(errors).any(func(e: String) -> bool: return e.contains("unknown mood: spring")))


func test_the_lint_rejects_a_missing_keyframe() -> void:
	var keys := "@key low 6 { %s } @key high 60 { %s }" % [_MINIMAL_KEY, _MINIMAL_KEY]
	var errors := PainterSheet.lint(PainterSheet.parse(_sheet(keys)))
	assert_true(
		Array(errors).any(func(e: String) -> bool: return e == "summer: missing keyframe night")
	)
	assert_false(
		Array(errors).any(func(e: String) -> bool: return e.begins_with("dusk:")),
		"dusk has all three"
	)


func test_the_lint_rejects_a_missing_role_mood_and_misordered_keys() -> void:
	var keys := _three_keys().replace("stone: oklch(0.7 0.03 80);", "").replace("low 6", "low 80")
	var errors := PainterSheet.lint(PainterSheet.parse(_sheet(keys)))
	assert_true(Array(errors).any(func(e: String) -> bool: return e.contains("missing role stone")))
	assert_true(Array(errors).any(func(e: String) -> bool: return e.contains("is not above")))
	var no_winter := _sheet(_three_keys()).replace("@mood winter", "@mood spring")
	errors = PainterSheet.lint(PainterSheet.parse(no_winter))
	assert_true(Array(errors).has("missing mood: winter"))


func test_a_keyframe_resolves_to_its_own_tones_and_the_ends_hold() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var frames: Array = sheet["summer"]
	for frame: Dictionary in frames:
		var at: float = frame["elevation"]
		var want: Vector3 = frame["lch"]["sun"]
		assert_almost_eq(PainterSheet.tone_lch(sheet, "summer", "sun", at), want, Vector3.ONE * 1e-5)
	var night: Vector3 = frames[0]["lch"]["ambient"]
	var high: Vector3 = frames[2]["lch"]["ambient"]
	var tiny := Vector3.ONE * 1e-5
	assert_almost_eq(PainterSheet.tone_lch(sheet, "summer", "ambient", -60.0), night, tiny)
	assert_almost_eq(PainterSheet.tone_lch(sheet, "summer", "ambient", 89.0), high, tiny)
	var dusk_a := PainterSheet.tone(sheet, "dusk", "sun", 70.0)
	var dusk_b := PainterSheet.tone(sheet, "dusk", "sun", 24.0)
	assert_true(dusk_a.is_equal_approx(dusk_b), "a mood holds its high keyframe above it")


func test_tones_change_smoothly_across_the_sun_elevation() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var worst := 0.0
	var worst_at := ""
	for mood: String in PainterSheet.MOODS:
		for role: String in PainterSheet.COLOR_ROLES:
			var last := PainterSheet.oklab_of(PainterSheet.tone_lch(sheet, mood, role, -20.0))
			var e := -20.0 + STEP_DEG
			while e <= 90.0:
				var now := PainterSheet.oklab_of(PainterSheet.tone_lch(sheet, mood, role, e))
				var delta := now.distance_to(last)
				if delta > worst:
					worst = delta
					worst_at = "%s %s at %.2f" % [mood, role, e]
				last = now
				e += STEP_DEG
		for prop: String in PainterSheet.NUMBER_PROPS:
			var a := PainterSheet.number(sheet, mood, prop, 5.0)
			var b := PainterSheet.number(sheet, mood, prop, 5.0 + STEP_DEG)
			assert_lt(absf(b - a), 0.05, "%s %s moves smoothly" % [mood, prop])
	gut.p("largest step: %.4f OKLab (%s)" % [worst, worst_at])
	assert_lt(
		worst,
		MAX_STEP_DELTA,
		"no jump over %s per %s degrees (worst: %s)" % [MAX_STEP_DELTA, STEP_DEG, worst_at]
	)


func test_hue_blends_the_short_way_and_grey_takes_the_other_hue() -> void:
	var a := Vector3(0.7, 0.1, 350.0)
	var b := Vector3(0.7, 0.1, 30.0)
	assert_almost_eq(PainterSheet.lerp_lch(a, b, 0.5).z, 10.0, 1e-4)
	var grey := Vector3(0.7, 0.0, 200.0)
	assert_almost_eq(PainterSheet.lerp_lch(grey, b, 0.5).z, 30.0, 1e-4)


func test_colours_parse_and_round_trip() -> void:
	var lch := PainterSheet.parse_color("oklch(72% 0.135 131)")
	assert_almost_eq(lch, Vector3(0.72, 0.135, 131.0), Vector3.ONE * 1e-5)
	var color := PainterSheet.color_of_lch(lch)
	var back := PainterSheet.lch_of_color(color)
	assert_almost_eq(back.x, 0.72, 0.005)
	assert_almost_eq(back.z, 131.0, 1.0)
	assert_eq(PainterSheet.parse_color("blue").x, -1.0, "not a colour")
	assert_almost_eq(PainterSheet.parse_color("#ffffff").x, 1.0, 1e-3)
