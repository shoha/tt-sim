extends GutTest

## PaintedBackdrop: the curated moods by environment preset, each a luminous sky gradient with
## no scenery, the cross-fade between them, and the title's and the room's words on paper of
## their own, never on the sky.

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
## The stops of a look, top to horizon.
const STOPS: Array[String] = ["sky_top", "sky_mid", "sky_low"]


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


## The backdrop is a sky gradient and nothing else (UI_TASTE verdict 2026-10-10): the shader
## takes its three stops and a lean, no sun, clouds, hills or poplars.
func test_the_backdrop_paints_a_gradient_and_no_scenery() -> void:
	var names: Array[String] = []
	for uniform: Dictionary in PaintedBackdrop.SHADER.get_shader_uniform_list():
		names.append(String(uniform.name))
	names.sort()
	assert_eq(names, ["low_lch", "mid_lch", "tilt", "top_lch"] as Array[String])
	for mood in PaintedBackdrop.Mood.size():
		var look := BackdropPaint.look_of(mood)
		assert_eq(look.keys().size(), STOPS.size(), "mood %d: its stops only" % mood)
		var near := Vector3.ONE * 0.002
		assert_almost_eq(BackdropPaint.colour_at(look, 0.0), look.sky_low, near, "horizon at the foot")
		assert_almost_eq(BackdropPaint.colour_at(look, 1.0), look.sky_top, near, "top at the head")


## Every mood's sky is luminous all the way down: no stretch of its gradient greys (a straight
## mix of a blue top and a warm horizon is grey, so the middle stop is curated), and the top
## and the horizon differ enough to read as a gradient rather than a flat fill.
func test_every_mood_is_a_luminous_gradient() -> void:
	for mood in PaintedBackdrop.Mood.size():
		var look := BackdropPaint.look_of(mood)
		for i in 11:
			var t := i / 10.0
			var sky := BackdropPaint.to_oklch(BackdropPaint.colour_at(look, t))
			assert_gte(sky.y, 0.025, "mood %d at %.1f: colour, not grey" % [mood, t])
			assert_gte(sky.x, 0.38, "mood %d at %.1f: luminous, not murky" % [mood, t])
		var top := BackdropPaint.to_oklch(look.sky_top)
		var low := BackdropPaint.to_oklch(look.sky_low)
		assert_gte(absf(top.x - low.x), 0.05, "mood %d: a gradient, not a flat fill" % mood)


func test_the_first_mood_shows_at_once_and_a_change_fades() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(backdrop.blend(), 1.0)
	assert_eq(_param(backdrop, &"low_lch"), _stop(PaintedBackdrop.Mood.GOLDEN_HOUR, "low_lch"))
	backdrop.show_mood(PaintedBackdrop.Mood.NIGHT)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.last_mood, PaintedBackdrop.Mood.NIGHT)
	assert_lt(backdrop.blend(), 0.1, "fading, not cut")
	await wait_seconds(PaintedBackdrop.FADE_S + 0.2)
	assert_eq(backdrop.blend(), 1.0)
	assert_eq(_param(backdrop, &"low_lch"), _stop(PaintedBackdrop.Mood.NIGHT, "low_lch"))
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A new mood part way through a fade starts from what is on screen: the colours do not jump.
func test_an_interrupted_fade_starts_from_what_is_on_screen() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.MORNING)
	backdrop.show_mood(PaintedBackdrop.Mood.DUSK)
	backdrop._set_blend(0.5)
	var shown: Vector3 = _param(backdrop, &"top_lch")
	var mid: Vector3 = _param(backdrop, &"mid_lch")
	backdrop.show_mood(PaintedBackdrop.Mood.OVERCAST)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.OVERCAST)
	assert_almost_eq(_param(backdrop, &"top_lch") as Vector3, shown, Vector3.ONE * 0.002)
	assert_almost_eq(_param(backdrop, &"mid_lch") as Vector3, mid, Vector3.ONE * 0.002)
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A map's key is kept with its mood (for a map load that follows), and a second map in the
## same mood shows the same sky without a fade.
func test_a_map_keeps_its_key_and_its_moods_sky() -> void:
	var backdrop := _backdrop()
	backdrop.show_map("forest", "willow_green", true)
	backdrop.show_map("forest", "mossy_hollow")
	assert_eq(backdrop.key(), "mossy_hollow")
	assert_eq(PaintedBackdrop.last_key, "mossy_hollow")
	assert_eq(backdrop.blend(), 1.0, "the same mood: nothing to fade")
	assert_eq(_param(backdrop, &"top_lch"), _stop(PaintedBackdrop.Mood.MORNING, "top_lch"))
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING
	PaintedBackdrop.last_key = ""


## The shader's `stop` uniform for `mood` at rest.
func _stop(mood: int, stop: String) -> Vector3:
	return BackdropPaint.uniforms(BackdropPaint.look_of(mood))[stop]


## A change of light keeps its saturation: every stop holds about as much chroma through the
## mix (OKLCH) as the greyer end (a mix in RGB dipped to grey part way: golden hour to night's
## sky held a third of the chroma).
func test_a_change_of_light_keeps_its_saturation() -> void:
	for a in PaintedBackdrop.Mood.size():
		for b in PaintedBackdrop.Mood.size():
			var from := BackdropPaint.look_of(a)
			var to := BackdropPaint.look_of(b)
			for k: float in [0.25, 0.37, 0.5, 0.75]:
				var mixed := BackdropPaint.mix_looks(from, to, k)
				for key: String in STOPS:
					var want := minf(_chroma(from[key]), _chroma(to[key]))
					var what := "%s %d -> %d at %.2f" % [key, a, b, k]
					assert_gte(_chroma(mixed[key]), want * 0.75, what)


## One route round the hue circle for the whole sky: half way through any change of light, two
## stops that start in neighbouring hues and end in neighbouring hues have turned the same way
## round, so the top and the horizon never pass through opposite hues.
func test_a_change_of_light_turns_the_sky_one_way() -> void:
	var near := deg_to_rad(50.0)
	for a in PaintedBackdrop.Mood.size():
		for b in PaintedBackdrop.Mood.size():
			var from := BackdropPaint.look_of(a)
			var to := BackdropPaint.look_of(b)
			var mixed := BackdropPaint.mix_looks(from, to, 0.5)
			for one: String in STOPS:
				for two: String in STOPS:
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


func _chroma(color: Vector3) -> float:
	return BackdropPaint.to_oklch(color).y


## Whether both ends have a hue worth turning (a near-grey end has none).
func _colourful(one: Vector3, two: Vector3) -> bool:
	return minf(_chroma(one), _chroma(two)) > 0.04


## How far the hue turned from `from` to `to`, signed, the short way (radians).
func _turn(from: Vector3, to: Vector3) -> float:
	var up := fposmod(BackdropPaint.to_oklch(to).z - BackdropPaint.to_oklch(from).z, TAU)
	return up if up <= PI else up - TAU


## No word stands straight on the sky: every word the title and the room show (a label's, a
## button's) sits on opaque paper, a control's own fill or a placeholder's gradient, and reads
## 4.5:1 or better on it, in every mood. The mood changes only the backdrop, so it never reaches
## a word's ground.
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
				assert_ne(ground.a, 0.0, "%s stands on paper, not the sky" % what)
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
	var label := control as Label
	if label and label.label_settings:
		return label.label_settings.font_color
	return control.get_theme_color(&"font_color")


## The opaque fill under `control`'s words: its own (a button's state, a panel's), the Play
## together card's wash under a face's words, a placeholder's gradient where its initial stands
## (its middle), else the nearest ancestor's. Transparent (alpha 0) when nothing but the sky is
## under them.
func _ground(control: Control) -> Color:
	var node: Node = control
	while node is Control:
		if node is PlayTogetherCard:
			var wash := (node as PlayTogetherCard).wash_under(control)
			if wash.a >= 1.0:
				return wash
		if node is MapPlaceholder:
			var look := BackdropPaint.look_of((node as MapPlaceholder).mood())
			var sky := BackdropPaint.colour_at(look, 0.5)
			return Color(sky.x, sky.y, sky.z)
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
	return MapPlaceholder.contrast(a, b)


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
