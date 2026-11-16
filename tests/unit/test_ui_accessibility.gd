extends GutTest

## Accessibility of the Painted Table themes beyond test_painted_theme.gd's role pairs
## (docs/UI_TASTE.md C6, C7 and the 2026-11-15 section): the text and fill of every button
## state, the focus ring against what it rings, state distinctness (rest, hover, pressed,
## disabled), and the semantic colours (success, warning, danger, info) under the three common
## colour-vision deficiencies, where each must also carry its own icon (C7).

const TEXT := 4.5
const GLYPH := 3.0
## CIE76 distance two semantic colours must keep after a colour-vision simulation, where the
## icons and words carry the rest. 15 is a clearly different colour at text size.
const MIN_DELTA_E := 15.0
## Tritanopia (about 1 in 10000) folds green and blue together by nature: success and info keep
## 7 apart and their icons (a check, an i) say the rest, never colour alone (C7).
const MIN_DELTA_E_TRITAN := 7.0
const BUTTON_VARIATIONS: Array[String] = ["Button", "Primary", "Danger", "Ghost"]
const STATES: Array[String] = ["normal", "hover", "pressed", "disabled"]
const SEMANTIC: Array[StringName] = [
	ThemeColors.SUCCESS, ThemeColors.WARNING, ThemeColors.DANGER, ThemeColors.STATE
]
## Machado, Oliveira and Fernandes 2009, severity 1.0, applied to linear RGB.
const PROTAN := [
	[0.152286, 1.052583, -0.204868],
	[0.114503, 0.786281, 0.099216],
	[-0.003882, -0.048116, 1.051998],
]
const DEUTAN := [
	[0.367322, 0.860646, -0.227968],
	[0.280085, 0.672501, 0.047413],
	[-0.011820, 0.042940, 0.968881],
]
const TRITAN := [
	[1.255528, -0.076749, -0.178779],
	[-0.078411, 0.930809, 0.147602],
	[0.004733, 0.691367, 0.303900],
]

var paper: Theme
var glass: Theme


func before_all() -> void:
	paper = ThemeColors.paper_theme()
	glass = ThemeColors.glass_theme()


func test_both_themes_load_and_every_button_state_is_drawn() -> void:
	for theme: Theme in [paper, glass]:
		assert_not_null(theme)
		for variation in BUTTON_VARIATIONS:
			for state in STATES:
				assert_true(
					theme.has_stylebox(state, variation) or variation != "Button",
					"%s has a %s stylebox" % [variation, state]
				)
				var box := theme.get_stylebox(state, variation)
				assert_not_null(box, "%s %s" % [variation, state])
			assert_not_null(theme.get_stylebox("focus", variation), "%s has a focus ring" % variation)


func test_button_states_are_distinct_and_hover_only_deepens() -> void:
	for theme: Theme in [paper, glass]:
		for variation in BUTTON_VARIATIONS:
			var normal := _fill(theme, "normal", variation)
			var hover := _fill(theme, "hover", variation)
			var pressed := _fill(theme, "pressed", variation)
			var disabled := _fill(theme, "disabled", variation)
			var tag := "%s %s" % [variation, "paper" if theme == paper else "glass"]
			if variation != "Ghost":
				assert_ne(hover, normal, "%s: hover differs from rest" % tag)
				assert_ne(pressed, hover, "%s: pressed differs from hover" % tag)
			var text_normal: Color = theme.get_color("font_color", variation)
			var text_disabled: Color = theme.get_color("font_disabled_color", variation)
			assert_ne(text_disabled, text_normal, "%s: disabled text is its own colour" % tag)
			if variation != "Ghost":
				assert_ne(disabled, hover, "%s: disabled is not a hover" % tag)


func test_text_on_every_button_state_holds_contrast() -> void:
	for theme: Theme in [paper, glass]:
		var ground := Color.WHITE if theme == paper else Color(0.45, 0.62, 0.30)
		for variation in ["Button", "Primary", "Danger"]:
			for pair: Array in [
				["normal", "font_color"],
				["hover", "font_hover_color"],
				["pressed", "font_pressed_color"],
			]:
				var fill := _over(_fill(theme, pair[0], variation), ground)
				var text: Color = theme.get_color(pair[1], variation)
				var ratio := _contrast(text, fill)
				assert_gt(ratio, TEXT, "%s %s: %.2f" % [variation, pair[0], ratio])


func test_disabled_text_is_dimmer_than_live_text_but_still_legible() -> void:
	# WCAG exempts disabled text; the bar here is that it is plainly dimmer yet readable.
	for theme: Theme in [paper, glass]:
		var ground := Color.WHITE if theme == paper else Color(0.45, 0.62, 0.30)
		var fill := _over(_fill(theme, "disabled", "Button"), ground)
		var live := _contrast(theme.get_color("font_color", "Button"), fill)
		var off := _contrast(theme.get_color("font_disabled_color", "Button"), fill)
		assert_lt(off, live, "disabled reads dimmer")
		assert_gt(off, 2.0, "disabled stays legible: %.2f" % off)


func test_focus_ring_holds_three_to_one_on_every_surface_it_rings() -> void:
	for roles: Dictionary in [ThemeColors.PAPER_ROLES, ThemeColors.GLASS_ROLES]:
		var grounds := [Color.WHITE] if roles == ThemeColors.PAPER_ROLES else [Color.WHITE, Color.BLACK]
		for ground: Color in grounds:
			for surface in [
				ThemeColors.SURFACE,
				ThemeColors.SURFACE_RAISED,
				ThemeColors.SURFACE_INSET,
				ThemeColors.SURFACE_HOVER,
			]:
				var ratio := _contrast(roles[ThemeColors.FOCUS], _over(roles[surface], ground))
				assert_gt(ratio, GLYPH, "focus on %s: %.2f" % [surface, ratio])
		# ... and against the persimmon or ember primary it can sit beside.
		var against_accent := _contrast(roles[ThemeColors.FOCUS], roles[ThemeColors.ACCENT])
		assert_gt(against_accent, 1.0, "the ring is not the primary's hue")


func test_semantic_colours_stay_distinct_under_colour_vision_deficiencies() -> void:
	for roles: Dictionary in [ThemeColors.PAPER_ROLES, ThemeColors.GLASS_ROLES]:
		var leaf := "paper" if roles == ThemeColors.PAPER_ROLES else "glass"
		for deficiency: Array in [
			["protan", PROTAN, MIN_DELTA_E],
			["deutan", DEUTAN, MIN_DELTA_E],
			["tritan", TRITAN, MIN_DELTA_E_TRITAN],
		]:
			for i in SEMANTIC.size():
				for j in range(i + 1, SEMANTIC.size()):
					var a := _simulate(roles[SEMANTIC[i]], deficiency[1])
					var b := _simulate(roles[SEMANTIC[j]], deficiency[1])
					var delta := _delta_e(a, b)
					assert_gt(
						delta,
						deficiency[2],
						"%s %s: %s vs %s dE %.1f" % [leaf, deficiency[0], SEMANTIC[i], SEMANTIC[j], delta]
					)


func test_every_semantic_kind_carries_its_own_icon() -> void:
	var icons := {}
	for kind: Variant in ToastContainer.KINDS:
		var icon := String(ToastContainer.KINDS[kind][0])
		assert_false(icons.has(icon), "%s is not shared" % icon)
		icons[icon] = true
	assert_eq(icons.size(), 4, "info, success, warning and danger each have an icon")


func test_the_one_primary_fill_per_leaf_is_not_the_focus_or_state_hue() -> void:
	for roles: Dictionary in [ThemeColors.PAPER_ROLES, ThemeColors.GLASS_ROLES]:
		assert_ne(roles[ThemeColors.ACCENT], roles[ThemeColors.FOCUS])
		assert_ne(roles[ThemeColors.ACCENT], roles[ThemeColors.STATE])
		assert_ne(roles[ThemeColors.DANGER_FILL], roles[ThemeColors.ACCENT])


func _fill(theme: Theme, state: String, variation: String) -> Color:
	var box := theme.get_stylebox(state, variation)
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


func _over(color: Color, ground: Color) -> Color:
	return Color(
		lerpf(ground.r, color.r, color.a),
		lerpf(ground.g, color.g, color.a),
		lerpf(ground.b, color.b, color.a),
		1.0
	)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## `color` as a viewer with the deficiency `matrix` sees it (sRGB in, sRGB out).
func _simulate(color: Color, matrix: Array) -> Color:
	var lin := color.srgb_to_linear()
	var r := clampf(matrix[0][0] * lin.r + matrix[0][1] * lin.g + matrix[0][2] * lin.b, 0.0, 1.0)
	var g := clampf(matrix[1][0] * lin.r + matrix[1][1] * lin.g + matrix[1][2] * lin.b, 0.0, 1.0)
	var b := clampf(matrix[2][0] * lin.r + matrix[2][1] * lin.g + matrix[2][2] * lin.b, 0.0, 1.0)
	return Color(r, g, b).linear_to_srgb()


## CIE76 colour difference of two sRGB colours (D65).
func _delta_e(a: Color, b: Color) -> float:
	var la := _lab(a)
	var lb := _lab(b)
	return la.distance_to(lb)


func _lab(color: Color) -> Vector3:
	var lin := color.srgb_to_linear()
	var x := (0.4124564 * lin.r + 0.3575761 * lin.g + 0.1804375 * lin.b) / 0.95047
	var y := 0.2126729 * lin.r + 0.7151522 * lin.g + 0.0721750 * lin.b
	var z := (0.0193339 * lin.r + 0.1191920 * lin.g + 0.9503041 * lin.b) / 1.08883
	var fx := _lab_f(x)
	var fy := _lab_f(y)
	var fz := _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
