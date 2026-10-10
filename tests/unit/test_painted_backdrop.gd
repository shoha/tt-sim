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


func test_the_first_mood_shows_at_once_and_a_change_cross_fades() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.GOLDEN_HOUR)
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.GOLDEN_HOUR))
	assert_eq(_param(backdrop, &"blend"), 1.0)
	backdrop.show_mood(PaintedBackdrop.Mood.NIGHT)
	assert_eq(backdrop.mood(), PaintedBackdrop.Mood.NIGHT)
	assert_eq(PaintedBackdrop.last_mood, PaintedBackdrop.Mood.NIGHT)
	assert_eq(_param(backdrop, &"mood_from"), int(PaintedBackdrop.Mood.GOLDEN_HOUR))
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.NIGHT))
	assert_lt(float(_param(backdrop, &"blend")), 0.1, "fading, not cut")
	await wait_seconds(PaintedBackdrop.FADE_S + 0.2)
	assert_eq(_param(backdrop, &"blend"), 1.0)
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


## A new mood part way through a fade starts from the mood that dominated the picture.
func test_an_interrupted_fade_starts_from_what_dominated() -> void:
	var backdrop := _backdrop()
	backdrop.show_mood(PaintedBackdrop.Mood.MORNING)
	backdrop.show_mood(PaintedBackdrop.Mood.DUSK)
	backdrop.show_mood(PaintedBackdrop.Mood.OVERCAST)
	assert_eq(_param(backdrop, &"mood_from"), int(PaintedBackdrop.Mood.MORNING))
	assert_eq(_param(backdrop, &"mood_to"), int(PaintedBackdrop.Mood.OVERCAST))
	PaintedBackdrop.last_mood = PaintedBackdrop.Mood.MORNING


func test_drift_follows_reduce_motion() -> void:
	var backdrop := _backdrop()
	var expected := 0.0 if UiMotion.reduced() else 1.0
	assert_eq(_param(backdrop, &"drift"), expected)


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


## The opaque fill under `control`'s words: its own (a button's state, a panel's), else the
## nearest ancestor's. Transparent (alpha 0) when nothing but the painting is under them.
func _ground(control: Control) -> Color:
	var node: Node = control
	while node is Control:
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
