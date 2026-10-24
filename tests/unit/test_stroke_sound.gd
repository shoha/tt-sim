extends GutTest

## StrokeSound, the authoring brush's sounds: the distance-to-ticks throttle (pure), what a
## drag, a tap, a cancel and a silent tool are heard as, that every sound it names is a
## recorded shot on the SFX bus, and the queue's take choice for a shot with several takes.

const FAMILIES: Array[StringName] = [&"plant", &"prop", &"water", &"paint", &"sculpt"]
const MOMENTS: Array[String] = ["start", "tick", "settle"]

var _heard: Array[StringName] = []


func _recording_sound() -> StrokeSound:
	_heard.clear()
	var sound := StrokeSound.new()
	sound.player = func(sound_name: StringName) -> void: _heard.append(sound_name)
	return sound


func _editor() -> AuthoringEditor:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_birch", "v", 11)
	var root := MapSourceLoader.create_authored_root(doc)
	if root.get_node_or_null(MapSourceLoader.PROPS_NODE) == null:
		var props := AuthoredScatter.create()
		props.name = MapSourceLoader.PROPS_NODE
		props.budget = 1_000_000_000
		root.add_child(props)
	add_child_autofree(root)
	return AuthoringEditor.create(doc, root, AuthoringHistory.new())


## A press at `at` whose ground point is known, as BrushTool's next frame starts it.
func _press(brush: BrushTool, at: Vector3) -> void:
	brush.pressed = true
	brush.press_pending = true
	brush.hit = at
	brush._start_gesture(0.0)


func test_ticks_are_whole_spacings_of_distance() -> void:
	assert_eq(StrokeSound.ticks_for(0.0, 3.0), 0)
	assert_eq(StrokeSound.ticks_for(2.99, 3.0), 0, "under one spacing: none")
	assert_eq(StrokeSound.ticks_for(3.0, 3.0), 1)
	assert_eq(StrokeSound.ticks_for(9.6, 3.0), 3)
	assert_eq(StrokeSound.ticks_for(-1.0, 3.0), 0)
	assert_eq(StrokeSound.ticks_for(5.0, 0.0), 0, "no spacing, no ticks")
	assert_almost_eq(StrokeSound.carry(9.6, 3.0), 0.6, 1e-5)
	assert_almost_eq(StrokeSound.carry(2.5, 3.0), 2.5, 1e-5)


func test_spacing_follows_the_brush_but_never_chatters() -> void:
	assert_almost_eq(StrokeSound.spacing_m(4.0), 3.0, 1e-5, "default brush: 3 m")
	assert_almost_eq(StrokeSound.spacing_m(1.0), StrokeSound.MIN_SPACING_M, 1e-5)
	assert_almost_eq(StrokeSound.spacing_m(12.0), 9.0, 1e-5)


func test_a_drag_starts_ticks_by_distance_and_settles() -> void:
	var sound := _recording_sound()
	sound.begin(&"biome", 4.0)
	# One second at 9.6 m/s in 60 frames: 9.6 m, three spacings of 3 m.
	for i in 60:
		sound.moved(0.16, 1.0 / 60.0)
	sound.end()
	assert_eq(_heard.count(&"plant_start"), 1)
	assert_eq(_heard.count(&"plant_tick"), 3)
	assert_eq(_heard.back(), &"plant_settle")
	assert_eq(_heard.size(), 5)


func test_a_fast_frame_ticks_once_and_drops_the_rest() -> void:
	var sound := _recording_sound()
	sound.begin(&"water", 4.0)
	sound.moved(20.0, 0.1)
	assert_eq(_heard, [&"water_start", &"water_tick"] as Array[StringName])
	# The frame's five other whole spacings are dropped; 2 m of the last is carried.
	sound.moved(0.5, 0.016)
	assert_eq(_heard.size(), 2, "2.5 m carried: under one spacing")
	sound.moved(0.5, 0.016)
	assert_eq(_heard.size(), 3, "3 m carried: the next tick")


func test_holding_still_is_silent_until_the_release() -> void:
	var sound := _recording_sound()
	sound.begin(&"sculpt", 4.0)
	for i in 120:
		sound.moved(0.0, 1.0 / 60.0)
	sound.end()
	assert_eq(_heard, [&"sculpt_start", &"sculpt_settle"] as Array[StringName])


func test_a_tap_is_heard_once_and_a_cancel_never_settles() -> void:
	var sound := _recording_sound()
	sound.begin(&"place", 4.0)
	sound.end()
	assert_eq(_heard, [&"prop_start"] as Array[StringName], "a click: its start alone")
	assert_false(StrokeSound.settles(0.1, 0.5, 3.0))
	assert_true(StrokeSound.settles(0.3, 0.0, 3.0))
	assert_true(StrokeSound.settles(0.1, 3.0, 3.0))
	sound = _recording_sound()
	sound.begin(&"paint", 4.0)
	for i in 60:
		sound.moved(0.1, 1.0 / 60.0)
	sound.cancel()
	sound.end()
	assert_false(_heard.has(&"paint_settle"))


func test_fire_and_unknown_tools_are_silent() -> void:
	var sound := _recording_sound()
	for tool_id in [&"fire", &"", &"no_such_tool"]:
		sound.begin(tool_id, 4.0)
		sound.moved(10.0, 0.5)
		sound.end()
	assert_eq(_heard.size(), 0)
	assert_eq(StrokeSound.family_of(&"thin_clear"), &"plant")
	assert_eq(StrokeSound.family_of(&"bridge"), &"prop")


## A gesture a mode takes itself (BrushMode.took_press) is heard as a stroke is: a Place press
## that places a prop knocks once (a tap), one that places nothing (no species picked) is
## silent, and a river's line starts, ticks by distance and settles on its release. The sound
## once began only for dab strokes, so Place, Bridge and River were silent in the game.
func test_gestures_a_mode_takes_itself_are_heard() -> void:
	var editor := _editor()
	var radius_was := BrushTool.session_radius
	var brush := BrushTool.new()
	add_child_autofree(brush)
	brush.editor = editor
	# Place beds its prop with a downward ray in the brush's world.
	var world := SubViewport.new()
	add_child_autofree(world)
	brush._world_viewport = world
	brush.sound = _recording_sound()
	brush.use_tool(ToolRegistry.find(PlaceTool.ID))
	brush.set_radius(4.0)
	_press(brush, Vector3(2, 0, 2))
	brush.finish_gesture()
	assert_eq(_heard.size(), 0, "no species picked: nothing placed, nothing heard")
	PlaceTool.of(brush).rule = editor.species_rule("temperate_forest_summer_s1", "boulder")
	var edits := editor.history.undo_count()
	_press(brush, Vector3(2, 0, 2))
	brush.finish_gesture()
	assert_eq(editor.history.undo_count(), edits + 1, "the press placed a boulder")
	assert_eq(_heard, [&"prop_start"] as Array[StringName], "a placed prop: its knock alone")
	_heard.clear()
	brush.use_tool(ToolRegistry.find(WaterTool.ID))
	brush.set_radius(4.0)
	_press(brush, Vector3(-6, 0, 0))
	for k in 13:
		brush.hit = Vector3(-6 + k, 0, 0)
		brush.mode.frame(brush)
		brush.follow_sound(0.1)
	brush.finish_gesture()
	assert_eq(_heard.front(), &"water_start")
	assert_eq(_heard.count(&"water_tick"), 4, "12 m of line at a 3 m spacing")
	assert_eq(_heard.back(), &"water_settle")
	assert_eq(_heard.size(), 6)
	BrushTool.session_radius = radius_was


func test_every_sound_is_a_recorded_shot_on_sfx() -> void:
	var names: Array[StringName] = [&"undo", &"redo"]
	for family in FAMILIES:
		for moment in MOMENTS:
			names.append(StringName("%s_%s" % [family, moment]))
	for sound_name in names:
		var entry := AudioManager.sound_entry(sound_name)
		assert_false(entry.is_empty(), "%s is in the manifest" % sound_name)
		assert_eq(str(entry.get("bus", "")), AudioManager.BUS_SFX, sound_name)
		assert_false(bool(entry.get("loop", true)), sound_name)
		var takes: Array = entry.get("takes", [])
		assert_gte(takes.size(), 3, "%s has three or more takes" % sound_name)
		for path in takes:
			assert_true(ResourceLoader.exists(path), path)
		if str(sound_name).ends_with("_tick"):
			assert_gte(float(entry.get("cooldown_s", 0.0)), 0.1, sound_name)


func test_a_take_never_plays_twice_running_and_every_take_comes_up() -> void:
	assert_eq(SoundRequestQueue.pick_take(1, 0, 0.9), 0)
	assert_eq(SoundRequestQueue.pick_take(3, 1, 0.0), 0)
	assert_eq(SoundRequestQueue.pick_take(3, 1, 0.99), 2)
	assert_eq(SoundRequestQueue.pick_take(3, -1, 0.99), 2)
	var seen := {}
	var last := -1
	for i in 40:
		var take := SoundRequestQueue.pick_take(4, last, fposmod(i * 0.618, 1.0))
		assert_ne(take, last)
		seen[take] = true
		last = take
	assert_eq(seen.size(), 4)


func test_flush_plays_the_takes_gain_and_base_pitch() -> void:
	var entry := {
		"bus": "SFX",
		"path": "res://a.wav",
		"takes": ["res://a.wav", "res://b.wav"],
		"take_gains_db": [0.0, 4.0],
		"volume_db": -10.0,
		"pitch_jitter": 0.0,
		"gain_jitter_db": 0.0,
		"pitch_scale": 0.5,
		"cooldown_s": 0.0,
		"priority": 10,
	}
	var queue := SoundRequestQueue.new({&"shot": entry})
	var last := -1
	for i in 6:
		queue.request(&"shot", float(i))
		var played: Dictionary = queue.flush(float(i))[0]
		assert_ne(int(played["take"]), last, "alternates between its two takes")
		last = int(played["take"])
		assert_eq(played["path"], entry["takes"][last])
		assert_almost_eq(float(played["volume_db"]), -10.0 + 4.0 * last, 1e-4)
		assert_almost_eq(float(played["pitch_scale"]), 0.5, 1e-4)
