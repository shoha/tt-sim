extends GutTest

## PaintedBackdrop: the curated moods by environment preset, the slow cross-fade between
## them, Reduce motion holding the drift, and the title's and the room's words on paper of
## their own, never on the painting.

const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
## A saved level with no folder on disk, so the title shows its captions.
const LEVEL := {
	"path": "user://x/_backdrop_words/",
	"folder": "_backdrop_words",
	"is_folder_based": true,
	"name": "Mossy Hollow",
	"token_count": 3,
	"modified_at": 1,
	"environment_preset": "",
	"thumbnail": "",
}


func _backdrop() -> PaintedBackdrop:
	var backdrop := PaintedBackdrop.new()
	add_child_autofree(backdrop)
	return backdrop


func _param(backdrop: PaintedBackdrop, param: StringName) -> Variant:
	return (backdrop.material as ShaderMaterial).get_shader_parameter(param)


func test_presets_map_onto_the_six_moods() -> void:
	assert_eq(PaintedBackdrop.mood_of(""), PaintedBackdrop.Mood.MORNING, "no map, no preset")
	assert_eq(PaintedBackdrop.mood_of("forest"), PaintedBackdrop.Mood.MORNING)
	assert_eq(PaintedBackdrop.mood_of("outdoor_day"), PaintedBackdrop.Mood.MIDDAY)
	assert_eq(PaintedBackdrop.mood_of("outdoor_sunset"), PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(PaintedBackdrop.mood_of("hell"), PaintedBackdrop.Mood.DUSK)
	assert_eq(PaintedBackdrop.mood_of("outdoor_overcast"), PaintedBackdrop.Mood.OVERCAST)
	assert_eq(PaintedBackdrop.mood_of("outdoor_night"), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.mood_of("cave"), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.mood_of("no_such_preset"), PaintedBackdrop.Mood.MORNING)


## Every preset the picker offers paints a mood the shader knows.
func test_every_preset_paints_a_known_mood() -> void:
	for group: String in EnvironmentPresets.PRESET_GROUPS:
		for preset: String in EnvironmentPresets.PRESET_GROUPS[group]:
			var mood := PaintedBackdrop.mood_of(preset)
			assert_between(int(mood), 0, PaintedBackdrop.Mood.size() - 1, preset)


func test_the_first_mood_shows_at_once_and_a_change_fades() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(backdrop.blend(), 1.0)
	var golden: Vector3 = BackdropPaint.look_of(PaintedBackdrop.Mood.GOLDEN_HOUR).sky_low
	assert_eq(_param(backdrop, &"sky_low"), golden)
	backdrop.show_mood(PaintedBackdrop.Mood.NIGHT)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.last_mood, PaintedBackdrop.Mood.NIGHT)
	assert_lt(backdrop.blend(), 0.1, "fading, not cut")
	await wait_seconds(PaintedBackdrop.FADE_S + 0.2)
	assert_eq(backdrop.blend(), 1.0)
	var night: Vector3 = BackdropPaint.look_of(PaintedBackdrop.Mood.NIGHT).sky_low
	assert_eq(_param(backdrop, &"sky_low"), night)
	assert_eq((_param(backdrop, &"sun_look") as Vector2).y, 1.0, "the moon")
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A new mood part way through a fade starts from what is on screen: the colours do not jump.
func test_an_interrupted_fade_starts_from_what_is_on_screen() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.MORNING)
	backdrop.show_mood(PaintedBackdrop.Mood.DUSK)
	backdrop._set_blend(0.5)
	var shown: Vector3 = _param(backdrop, &"sky_top")
	var sun: Vector4 = _param(backdrop, &"sun_at")
	backdrop.show_mood(PaintedBackdrop.Mood.OVERCAST)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.OVERCAST)
	assert_almost_eq(_param(backdrop, &"sky_top") as Vector3, shown, Vector3.ONE * 0.002)
	assert_almost_eq(_param(backdrop, &"sun_at") as Vector4, sun, Vector4.ONE * 0.002)
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A change of light is one picture changing: every colour keeps its saturation through the
## mix (OKLCH), the hills between golden hour and night pass through rose and violet rather
## than khaki, and the one disc moves and shrinks from sun to moon.
func test_a_change_of_light_keeps_its_saturation_and_moves_one_disc() -> void:
	for a in PaintedBackdrop.Mood.size():
		for b in PaintedBackdrop.Mood.size():
			var from := BackdropPaint.look_of(a)
			var to := BackdropPaint.look_of(b)
			for k: float in [0.25, 0.37, 0.5, 0.75]:
				var mixed := BackdropPaint.mix_looks(from, to, k)
				# About as saturated as the greyer end, short of what the screen can show at
				# that lightness (a mix in RGB dipped to grey part way: golden hour to night's
				# sky held a third of the chroma).
				for key: String in ["sky_top", "sky_low", "far_col", "near_col", "meadow_col"]:
					var want := minf(_chroma(from[key]), _chroma(to[key]))
					var what := "%s %d -> %d at %.2f" % [key, a, b, k]
					assert_gte(_chroma(mixed[key]), want * 0.75, what)
	var golden := BackdropPaint.look_of(PaintedBackdrop.Mood.GOLDEN_HOUR)
	var night := BackdropPaint.look_of(PaintedBackdrop.Mood.NIGHT)
	var composition := BackdropPaint.compose(0.3, Vector2(1920, 1080), null)
	var sun := BackdropPaint.sun_of(BackdropPaint.mix_looks(golden, night, 0.5), composition)
	assert_between(sun.z, night.sun_r, golden.sun_r, "the disc shrinks toward the moon's")
	assert_between(sun.y, golden.sun_y, night.sun_y, "and rises")


## One route round the hue circle for the land, and one for the sky: half way through any
## change of light, two of the land's colours (or two of the sky's) that start in neighbouring
## hues and end in neighbouring hues have turned the same way round (an orange hill on a teal
## meadow had turned two ways from olive to blue).
func test_a_change_of_light_turns_the_land_one_way() -> void:
	var land := BackdropPaint.LAND_COLOURS
	var sky: Array[String] = ["sky_top", "sky_low", "sun_glow", "cloud_lit", "cloud_shade"]
	var near := deg_to_rad(50.0)
	for a in PaintedBackdrop.Mood.size():
		for b in PaintedBackdrop.Mood.size():
			var from := BackdropPaint.look_of(a)
			var to := BackdropPaint.look_of(b)
			var mixed := BackdropPaint.mix_looks(from, to, 0.5)
			for group: Array[String] in [land, sky]:
				for one: String in group:
					for two: String in group:
						var turns := [_turn(from[one], mixed[one]), _turn(from[two], mixed[two])]
						var colourful := [one, two].all(
							func(key: String) -> bool: return _colourful(from[key], to[key])
						)
						var moved := absf(turns[0]) > deg_to_rad(15.0) and absf(turns[1]) > deg_to_rad(15.0)
						var neighbours := (
							absf(_turn(from[one], from[two])) < near and absf(_turn(to[one], to[two])) < near
						)
						if colourful and moved and neighbours:
							var what := "%s and %s, %d -> %d: %s" % [one, two, a, b, turns]
							assert_eq(signf(turns[0]), signf(turns[1]), what)


## A low sun keeps low: with the largest open sky in a strip along the top and a smaller band
## low over the hills, golden hour and dusk stand their sun in the low band, smaller, while
## morning's stands in the strip.
func test_a_low_sun_keeps_low_and_shrinks() -> void:
	var size := Vector2(1280, 720)
	var paper: Array[Rect2] = [Rect2(24, 24, 380, 672), Rect2(428, 200, 828, 200)]
	var layout := BackdropLayout.new(size, paper)
	var composition := BackdropPaint.compose(0.4, size, layout)
	var morning := BackdropPaint.sun_of(BackdropPaint.look_of(0), composition)
	assert_gt(morning.y, 0.6, "morning's sun in the strip along the top")
	for mood: int in [PaintedBackdrop.Mood.GOLDEN_HOUR, PaintedBackdrop.Mood.DUSK]:
		var look := BackdropPaint.look_of(mood)
		var sun := BackdropPaint.sun_of(look, composition)
		assert_lt(sun.y, 0.45, "mood %d: low over the hills" % mood)
		assert_lt(sun.z, look.sun_r, "mood %d: smaller to fit" % mood)
		var disc := Rect2(sun.x - sun.z, sun.y - sun.z, sun.z * 2.0, sun.z * 2.0)
		assert_true(layout.is_open(_pixels(disc, size)), "mood %d: in open sky" % mood)
	# With cards over all the low sky, a low sun sets behind them at its own place, its glow
	# round their edges, rather than climbing to the strip along the top.
	var full: Array[Rect2] = [Rect2(24, 24, 380, 672), Rect2(428, 60, 828, 640)]
	var crowded := BackdropPaint.compose(0.4, size, BackdropLayout.new(size, full))
	var golden := BackdropPaint.look_of(PaintedBackdrop.Mood.GOLDEN_HOUR)
	var setting := BackdropPaint.sun_of(golden, crowded)
	assert_almost_eq(setting.y, float(golden.sun_y), 0.001, "low, behind the cards")
	var high := BackdropPaint.sun_of(BackdropPaint.look_of(0), crowded)
	assert_gt(high.y, 0.9, "morning's still in the strip along the top")


## The sun or moon stands in the sky the paper leaves open, and every cloud and poplar clear of
## it: here a column sheet on the left and a row of cards across the top right.
func test_the_painting_makes_way_for_the_paper() -> void:
	var size := Vector2(1280, 720)
	var paper: Array[Rect2] = [Rect2(24, 24, 380, 672), Rect2(428, 24, 828, 300)]
	var layout := BackdropLayout.new(size, paper)
	for seed: float in [0.05, 0.31, 0.62, 0.9]:
		var composition := BackdropPaint.compose(seed, size, layout)
		for mood in PaintedBackdrop.Mood.size():
			var sun := BackdropPaint.sun_of(BackdropPaint.look_of(mood), composition)
			var disc := Rect2(sun.x - sun.z, sun.y - sun.z, sun.z * 2.0, sun.z * 2.0)
			assert_true(layout.is_open(_pixels(disc, size)), "seed %.2f mood %d sun" % [seed, mood])
		# A whole cloud in open sky, crown and all (a crown behind the cards left a lozenge).
		for cloud: Vector4 in composition.clouds:
			if cloud.z > 0.0:
				var z := cloud.z
				var whole := Rect2(cloud.x - 0.85 * z, cloud.y - 0.14 * z, 1.8 * z, 0.76 * z)
				assert_true(layout.is_open(_pixels(whole, size)), "seed %.2f cloud %s" % [seed, cloud])
		for tree: Vector4 in composition.poplars:
			if tree.y > 0.0:
				var foot := BackdropPaint.near_line(tree.x, size.x / size.y, composition.ridges.z)
				var rect := Rect2(tree.x - tree.z, foot, tree.z * 2.0, tree.y)
				assert_true(layout.is_open(_pixels(rect, size)), "seed %.2f poplar" % seed)


## Two maps in the same mood get their own land and weather; the same map always the same.
func test_each_map_draws_its_own_sky() -> void:
	var backdrop := _backdrop()
	backdrop.show_map("forest", "willow_green", true)
	var ridges: Vector4 = _param(backdrop, &"ridges")
	var cloud: Vector4 = _param(backdrop, &"cloud0")
	backdrop.show_map("forest", "mossy_hollow", true)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.MORNING)
	assert_ne(_param(backdrop, &"ridges"), ridges)
	assert_ne(_param(backdrop, &"cloud0"), cloud)
	backdrop.show_map("forest", "willow_green", true)
	assert_eq(_param(backdrop, &"ridges"), ridges)
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING
	PaintedBackdrop.last_key = ""


func test_drift_follows_reduce_motion() -> void:
	var backdrop := _backdrop()
	var expected := 0.0 if UiMotion.reduced() else 1.0
	assert_eq(_param(backdrop, &"drift"), expected)
	backdrop.hold_drift(true)
	assert_eq(_param(backdrop, &"drift"), 0.0, "held")


func _chroma(color: Vector3) -> float:
	return BackdropPaint.to_oklch(color).y


## Whether both ends have a hue worth turning (a near-grey end has none).
func _colourful(one: Vector3, two: Vector3) -> bool:
	return minf(_chroma(one), _chroma(two)) > 0.04


## How far the hue turned from `from` to `to`, signed, the short way (radians).
func _turn(from: Vector3, to: Vector3) -> float:
	var up := fposmod(BackdropPaint.to_oklch(to).z - BackdropPaint.to_oklch(from).z, TAU)
	return up if up <= PI else up - TAU


## A rect in heights (y up from the foot) as pixels.
func _pixels(rect: Rect2, size: Vector2) -> Rect2:
	return Rect2(
		rect.position.x * size.y, (1.0 - rect.end.y) * size.y, rect.size.x * size.y, rect.size.y * size.y
	)


## No word stands straight on the painting: every word the title and the room show (a label's,
## a button's) sits on opaque paper or a control's own fill, and reads 4.5:1 or better on it,
## in every mood. The mood changes only the painting, so it never reaches a word's ground.
func test_every_word_on_the_title_and_the_room_reads_in_every_mood() -> void:
	var host := SubViewport.new()
	host.size = Vector2i(1280, 720)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child_autofree(host)
	var title := TITLE_SCENE.instantiate() as TitleScreen
	title.level_provider = func() -> Array[Dictionary]: return [LEVEL.duplicate()]
	host.add_child(title)
	var room := RoomScreen.new()
	room.connect_network = false
	host.add_child(room)
	room.panel.set_code("ABCD-EFGH")
	room.panel.show_session(_room_summary(), "enet-1", true)
	room.panel.select("hollow")
	await wait_process_frames(3)
	for mood: int in PaintedBackdrop.Mood.values():
		for screen: Node in [title, room]:
			var backdrop: PaintedBackdrop = screen.get("backdrop")
			backdrop.show_mood(mood as PaintedBackdrop.Mood, true)
			var words := _words(screen)
			assert_gt(words.size(), 5, "%s shows its words" % screen.name)
			for control: Control in words:
				var ground := _ground(control)
				var what := "%s %s, mood %d" % [screen.name, screen.get_path_to(control), mood]
				assert_ne(ground.a, 0.0, "%s stands on paper, not the painting" % what)
				if ground.a > 0.0:
					var ratio := _contrast(_ink(control), ground)
					assert_gte(ratio, 4.5, "%s: %.2f:1" % [what, ratio])
	title.free()
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## The labels and buttons under `screen` that show words.
func _words(screen: Node) -> Array[Control]:
	var words: Array[Control] = []
	for control: Control in screen.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		var label := control as Label
		var button := control as Button
		if (label and label.text.strip_edges() != "") or (button and button.text != ""):
			words.append(control)
	return words


## The colour a control's words are drawn in.
func _ink(control: Control) -> Color:
	var button := control as Button
	if button and button.disabled:
		return button.get_theme_color(&"font_disabled_color")
	if button and button.button_pressed:
		return button.get_theme_color(&"font_pressed_color")
	return control.get_theme_color(&"font_color")


## The opaque fill under `control`'s words: its own (a button's state, a panel's), the Play
## together card's wash under a face's words, else the nearest ancestor's. Transparent (alpha 0)
## when nothing but the painting is under them.
func _ground(control: Control) -> Color:
	var node: Node = control
	while node is Control:
		if node is PlayTogetherCard:
			var wash := (node as PlayTogetherCard).wash_under(control)
			if wash.a >= 1.0:
				return wash
		var fill := _fill(node as Control)
		if fill.a >= 1.0:
			return fill
		node = node.get_parent()
	return Color(0, 0, 0, 0)


func _fill(control: Control) -> Color:
	var style: StyleBox = null
	if control is Button:
		var button := control as Button
		var state := &"pressed" if button.button_pressed else &"normal"
		style = button.get_theme_stylebox(&"disabled" if button.disabled else state)
	elif control is PanelContainer or control is Panel:
		style = control.get_theme_stylebox(&"panel")
	var flat := style as StyleBoxFlat
	if flat == null or not flat.draw_center:
		return Color(0, 0, 0, 0)
	return flat.bg_color


## WCAG 2.x contrast ratio of two opaque colours.
func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## A GM's room (SessionChannel.summary()'s shape): two players, a shelf of two maps.
func _room_summary() -> Dictionary:
	var shelf := []
	for spec in [["hollow", "Mossy Hollow"], ["mill", "Old Mill"]]:
		shelf.append({"folder": spec[0], "map_path": "", "hashes": {}, "name": spec[1]})
	return {
		"open": true,
		"table": "",
		"shelf": shelf,
		"players":
		{
			"enet-1": {"name": "Marigold", "peer_id": 1},
			"enet-2": {"name": "Wren", "peer_id": 2},
		},
		"holdings": {"enet-1": ["hollow", "mill"], "enet-2": ["hollow"]},
	}
