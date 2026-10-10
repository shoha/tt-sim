extends GutTest

## The GM's Events pane in play (EventsPane, PlayEvents): it lists the play brushes only, only
## the GM's side of a table that takes live edits may arm one, a pick arms GameMap's brush
## over the table's live editor and its tile again or Esc puts it away, a stroke through that
## brush goes into the live history and Ctrl+Z's undo takes it back, and a token standing
## where the ground rose is set down on it once the edit settles (LiveEditGround).
##
## The table is a real LevelPlayController and GameMap (wired as Root wires them, as in
## test_dressed_play_load) playing a flat authored level saved under Paths.LEVELS_DIR (the GUT
## run's own data root), removed after each test.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const TOASTS_SCENE := preload("res://scenes/ui/toast_container.tscn")
const FOLDER := "_gm_events_gut"
const MAP_CELLS := 8
const LOAD_TIMEOUT := 30.0
const SETTLE_FRAMES := 600
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
## Where the brush raises the ground, and the token stands.
const RAISE_AT := Vector3(2.0, 0.0, 1.0)

var _controller: LevelPlayController
var _game_map: GameMap
var _pane: EventsPane
var _events: PlayEvents


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))
	_controller = LevelPlayController.new()
	add_child_autofree(_controller)
	_game_map = GAME_MAP_SCENE.instantiate()
	_with_scene(func() -> void: add_child_autofree(_game_map))
	_controller.setup(_game_map)
	_game_map.setup(_controller)


func after_each() -> void:
	UIManager.clear_tool_hints()
	var folder := Paths.get_level_folder(FOLDER)
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder.trim_suffix("/"))


## DragAndDrop3D and DraggingObject3D await the current scene's ready signal, and GUT's
## runner has no current scene: a stand-in whose ready has already fired lets that wait sit.
func _with_scene(add: Callable) -> void:
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add.call()
	get_tree().current_scene = null
	stand_in.free()


## A flat authored level of `cells` a side played on the table, with its live edits started.
func _play(cells: int = MAP_CELLS) -> void:
	var doc := MapDocument.create_flat(Vector2i(cells, cells), "grass", "gm", 5)
	assert_eq(MapDocumentIO.write(doc, Paths.get_level_map_document_path(FOLDER)), OK)
	var level := LevelData.new()
	level.level_name = FOLDER
	level.level_folder = FOLDER
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	_controller.play_level(level)
	assert_true(await wait_for_signal(_controller.level_loading_completed, LOAD_TIMEOUT))
	var frames := 0
	while _controller.live_edits == null and frames < SETTLE_FRAMES:
		await get_tree().process_frame
		frames += 1
	assert_not_null(_controller.live_edits, "the table's live edits started")
	_pane = EventsPane.new()
	add_child_autofree(_pane)
	_events = PlayEvents.new()
	add_child_autofree(_events)
	_events.setup(_controller, _pane)


## Frames until the live edits are sent and the ground follower has caught up.
func _settle() -> void:
	var ground := _controller.live_edits.get_node("LiveEditGround") as LiveEditGround
	var frames := 0
	while frames < SETTLE_FRAMES and not (_controller.live_edits.is_settled() and ground.is_idle()):
		await get_tree().process_frame
		frames += 1
	assert_lt(frames, SETTLE_FRAMES, "settled within %d frames" % SETTLE_FRAMES)


## A held drag of the play brush along `points` (world XZ), as the render driver drives it.
func _drag(brush: BrushTool, points: Array[Vector3]) -> void:
	brush.pointer = _game_map.camera_node.unproject_position(points[0])
	brush.has_pointer = true
	await get_tree().process_frame
	brush.pressed = true
	brush.press_pending = true
	# Headless frames are short: each point is held for real time, so the dwell builds.
	for point in points:
		var until := Time.get_ticks_msec() + 300
		while Time.get_ticks_msec() < until:
			brush.pointer = _game_map.camera_node.unproject_position(point)
			await get_tree().process_frame
	brush.pressed = false
	brush.finish_gesture()


func _height_at(xz: Vector3) -> float:
	return _controller.live_edits.editor.ground_height_at(xz)


## The pane's shown parts in order (name, visible), and which tiles are on.
func _shown(pane: EventsPane) -> Array:
	var out := []
	for child in pane.get_children():
		out.append([child.name, (child as Control).visible])
	for id in pane.preset_ids():
		out.append([id, pane.preset_field.tiles.is_on(id)])
	var options := pane.get_node("EventsOptions")
	for child in options.get_children():
		out.append([child.name, (child as Control).visible])
	return out


func test_the_pane_lists_the_play_brushes_only() -> void:
	var pane := EventsPane.new()
	add_child_autofree(pane)
	var ids: Array[StringName] = []
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		ids.append(tool.id)
		assert_true(pane.tool_field.tiles.has_tile(tool.id), "%s has a tile" % tool.id)
	assert_eq(pane.tool_ids(), ids)
	assert_false(pane.tool_field.tiles.has_tile(PlaceTool.ID), "Place is authoring's alone")
	for id in [SculptTool.ID, PaintTool.ID, BiomeTool.ID, ThinTool.ID, WaterTool.ID, BridgeTool.ID]:
		assert_true(id in ids, "%s is a play brush" % id)


func test_only_the_gm_side_of_a_document_table_may_change_the_map() -> void:
	var doc := MapDocument.create_flat(Vector2i(2, 2), "", "v", 1)
	var gm_side := LiveEdits.new()
	var client := LiveEdits.new()
	client.sends = false
	assert_eq(PlayEvents.refusal_for(false, doc, gm_side), PlayEvents.NOT_GM, "a player")
	assert_eq(PlayEvents.refusal_for(true, null, null), LiveEdits.NO_DOCUMENT, "a Blender map")
	assert_eq(PlayEvents.refusal_for(true, doc, null), PlayEvents.NOT_READY, "still setting out")
	assert_eq(PlayEvents.refusal_for(true, doc, client), PlayEvents.NOT_HOST, "a client's side")
	assert_eq(PlayEvents.refusal_for(true, doc, gm_side), "", "the GM's side")
	gm_side.free()
	client.free()


func test_each_brush_leads_the_hint_bar_and_ends_on_size_undo_and_its_name() -> void:
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		var hints := PlayEvents.hints_for(tool.id)
		assert_lte(hints.size(), 5, "%s: at most five keys beside Help, one line" % tool.id)
		assert_eq(hints[0]["key"], "Left-drag")
		assert_eq(hints[-3]["key"], PlayEvents.SIZE_KEY, "%s: the size key in one slot" % tool.id)
		assert_eq(hints[-2]["action"], "Undo")
		assert_eq(hints[-1]["action"], "Put away " + tool.label, "Esc names the brush")
		for hint in hints:
			assert_false(hint["key"].begins_with("Shift+scroll"), "no Shift size key: Sculpt's Smooth")
	assert_eq(PlayEvents.hints_for(SculptTool.ID, HeightBrush.TIER)[0]["action"], "Tier")


func test_a_large_edit_toast_says_what_was_done_on_one_line() -> void:
	assert_eq(PlayEvents.done_phrase("Clear"), "Cleared")
	assert_eq(PlayEvents.done_phrase("Thin"), "Thinned")
	assert_eq(PlayEvents.done_phrase("Raise"), "Raised")
	assert_eq(PlayEvents.done_phrase("Carve river"), "Carved river")
	assert_eq(PlayEvents.done_phrase("Remove planks"), "Removed planks")
	assert_eq(PlayEvents.UNDO_TOAST % "Cleared", "Cleared for everyone at the table")
	var toasts: ToastContainer = TOASTS_SCENE.instantiate()
	add_child_autofree(toasts)
	var text := PlayEvents.UNDO_TOAST % PlayEvents.done_phrase("Erase water")
	toasts.show_toast(text, ToastContainer.ToastType.INFO, 30.0, "Undo", func(): pass, "arrow-back-up")
	await wait_process_frames(2)
	var toast := toasts.toast_vbox.get_child(0) as Control
	var label := toast.get_child(0).get_child(1) as Label
	assert_eq(
		label.get_line_count(),
		1,
		"'%s' beside Undo on one line (toast %.1f, label %.1f)" % [text, toast.size.x, label.size.x]
	)
	assert_lte(toast.size.x, ToastContainer.ACTION_MAX_WIDTH)


func test_a_large_edit_offers_undo() -> void:
	assert_false(PlayEvents.is_large({"bytes": 100}), "a dab")
	assert_true(PlayEvents.is_large({"bytes": PlayEvents.LARGE_EDIT_BYTES}), "a big stroke")
	var water := WaterEditor.new()
	assert_true(PlayEvents.is_large({"redo": water.apply_edit.bind({}, true)}), "a river")
	var crossings := CrossingEditor.new()
	assert_true(PlayEvents.is_large({"redo": crossings.apply_list.bind([])}), "a crossing")


func test_a_pick_arms_the_board_brush_and_esc_or_the_tile_puts_it_away() -> void:
	await _play()
	_events.pick(SculptTool.ID)
	var brush := _game_map.get_brush_tool()
	assert_not_null(brush, "the play brush is made")
	assert_true(brush.is_active(), "armed on the board")
	assert_eq(brush.tool.id, SculptTool.ID)
	assert_same(brush.editor, _controller.live_edits.editor, "over the table's live editor")
	assert_eq(_events.armed, SculptTool.ID)
	assert_true(_pane.tool_field.tiles.is_on(SculptTool.ID), "its tile is pressed")
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_events._unhandled_input(esc)
	assert_false(brush.is_active(), "Esc puts it away")
	assert_false(brush.fade_held_only, "GameMap's brush is authoring's again")
	assert_eq(_events.armed, &"")
	assert_false(_pane.tool_field.tiles.is_on(SculptTool.ID), "its tile is up")
	_events._on_tool_toggled(ThinTool.ID, true)
	assert_true(brush.is_active(), "a tile arms its brush")
	_events._on_tool_toggled(ThinTool.ID, false)
	assert_false(brush.is_active(), "its tile again puts it away")
	_events.pick(BiomeTool.ID)
	assert_false(brush.is_active(), "Biome waits for a biome")
	assert_eq(_events.picked, BiomeTool.ID)
	var biome := String(PaletteLibrary.biomes()[0]["id"])
	_events._on_biome_selected(biome)
	assert_true(brush.is_active(), "a picked biome arms it")
	assert_eq(BiomeTool.of(brush).biome_id, biome)


func test_a_live_raise_undoes_through_the_live_history_and_regrounds_a_token() -> void:
	await _play()
	var token := AvatarTokenFactory.create(RECIPE, "Scout")
	_with_scene(func() -> void: _game_map.drag_and_drop_node.add_child(token))
	token.rigid_body.global_position = RAISE_AT + Vector3(0.0, 3.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	TokenGrounding.reground(token, TokenGrounding.cast_top(_game_map))
	var before := token.rigid_body.global_position.y
	assert_almost_eq(before, 0.0, 0.05, "the token stands on the flat ground")
	var regrounded := []
	var ground := _controller.live_edits.get_node("LiveEditGround") as LiveEditGround
	ground.regrounded.connect(func(moved: int) -> void: regrounded.append(moved))

	_events.pick(SculptTool.ID)
	var brush := _game_map.get_brush_tool()
	assert_true(brush.fade_held_only, "in play the canopy opens only under a held press")
	var strokes := [0]
	_events.stroke_started.connect(func() -> void: strokes[0] += 1)
	await _drag(brush, [RAISE_AT, RAISE_AT + Vector3(0.5, 0.0, 0.0), RAISE_AT])
	assert_eq(strokes[0], 1, "the press told the drawer to step aside")
	await _settle()
	var raised := _height_at(RAISE_AT)
	assert_gt(raised, 0.2, "the brush raised the ground")
	assert_eq(_controller.live_edits.op_log.size(), 1, "one op logged")
	assert_true(_controller.live_edits.history.can_undo(), "into the live history")
	# One small mound (3.8 KB measured) is no large edit: Ctrl+Z on the hint bar, no toast.
	var stack: Array = _controller.live_edits.history.get("_undo")
	assert_false(PlayEvents.is_large(stack.back()), "a small mound offers no undo toast")
	assert_false(regrounded.is_empty(), "the follower set the tokens down")
	var rest := TokenGrounding.resting_position(token, TokenGrounding.cast_top(_game_map))
	assert_almost_eq(token.rigid_body.global_position.y, rest.y, 0.05, "on its new ground")
	assert_gt(token.rigid_body.global_position.y, before + 0.1, "lifted with the ground")

	var ctrl_z := InputEventAction.new()
	ctrl_z.action = &"ui_undo"
	ctrl_z.pressed = true
	_events._unhandled_input(ctrl_z)
	await _settle()
	assert_almost_eq(_height_at(RAISE_AT), 0.0, 0.01, "undone")
	assert_eq(_controller.live_edits.op_log.size(), 2, "the undo went out as an op")
	assert_almost_eq(token.rigid_body.global_position.y, before, 0.05, "back down with it")


func test_the_presets_stand_above_the_brushes_and_lead_their_hints() -> void:
	var pane := EventsPane.new()
	add_child_autofree(pane)
	assert_eq(pane.preset_ids(), [EventPresets.COLLAPSE, EventPresets.TOPPLE])
	for id in pane.preset_ids():
		assert_true(pane.preset_field.tiles.has_tile(id), "%s has a tile" % id)
		assert_false(pane.tool_field.tiles.has_tile(id), "%s is no brush" % id)
	assert_lt(pane.preset_field.get_index(), pane.tool_field.get_index(), "above Brushes")
	assert_eq(pane.preset_field.caption, EventPresets.HEADING, "the one-shot events' own heading")
	assert_null(ToolRegistry.find(EventPresets.COLLAPSE), "no map tool: authoring never lists it")
	# The tiles say what the pills say, so make (the Bridge brush) and break read apart.
	assert_eq(EventPresets.find(EventPresets.COLLAPSE).label, CollapseMode.DROP)
	assert_eq(EventPresets.find(EventPresets.TOPPLE).label, ToppleMode.TEXT)
	for preset in EventPresets.all():
		assert_not_null(IconButton.load_icon(preset.icon), "%s has its own icon" % preset.id)
		for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
			assert_ne(preset.icon, tool.icon, "%s does not repeat %s's picture" % [preset.id, tool.id])
	var collapse := PlayEvents.hints_for(EventPresets.COLLAPSE)
	assert_eq(collapse[0], {"key": "Click", "action": "Drop bridge"})
	assert_eq(collapse[-1], {"key": "Esc", "action": "Put away"}, "the first key names it")
	assert_false(collapse.any(func(h: Dictionary) -> bool: return h.key == PlayEvents.SIZE_KEY))
	var topple := PlayEvents.hints_for(EventPresets.TOPPLE)
	assert_lte(topple.size(), 5, "one line beside Help")
	assert_eq(topple[0], {"key": "Click", "action": "Topple trees"})
	assert_eq(topple[1], {"key": "Drag", "action": "Wider stand"})
	assert_eq(topple[-3]["key"], PlayEvents.SIZE_KEY, "Topple's ring has a size")
	for kind in [TerrainEvent.Kind.BRIDGE_COLLAPSE, TerrainEvent.Kind.FOREST_FALL]:
		assert_true(PlayEvents.PRESET_DONE.has(kind), "every preset has its toast")


func test_a_picked_tools_controls_stand_under_its_own_field() -> void:
	var pane := EventsPane.new()
	add_child_autofree(pane)
	var holder := pane.get_node("EventsOptions") as Control
	var advanced := pane.get_node("EventsAdvanced") as Control
	pane.show_tool(EventPresets.TOPPLE)
	assert_true(pane.preset_field.tiles.is_on(EventPresets.TOPPLE))
	assert_eq(holder.get_index(), pane.preset_field.get_index() + 1, "the line under the presets")
	assert_eq(advanced.get_index(), holder.get_index() + 1, "Advanced under the line")
	assert_lt(advanced.get_index(), pane.tool_field.get_index(), "both above Brushes")
	assert_true(advanced.visible, "Topple's size")
	var strength := advanced.find_child("EventsBrushStrength", true, false) as Control
	assert_false(strength.visible, "an event has no strength")
	pane.show_tool(SculptTool.ID)
	assert_eq(holder.get_index(), pane.tool_field.get_index() + 1, "a brush's under Brushes")
	assert_true(strength.visible)


func test_a_preset_put_away_leaves_the_pane_as_fresh() -> void:
	await _play()
	var fresh := _shown(_pane)
	_events.pick(EventPresets.TOPPLE)
	assert_ne(_shown(_pane), fresh, "a picked preset shows its line and size")
	_events.put_away()
	assert_eq(_events.picked, &"", "a put-away preset is forgotten")
	assert_eq(_shown(_pane), fresh, "the put-away pane equals the fresh one")
	_events.pick(EventPresets.TOPPLE)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	_events._unhandled_input(esc)
	assert_eq(_shown(_pane), fresh, "Esc too")
	# A brush keeps its controls: their picks arm it again.
	_events.pick(SculptTool.ID)
	_events.put_away()
	assert_eq(_events.picked, SculptTool.ID)


func test_a_preset_stays_armed_after_it_fires_until_no_bridge_is_left() -> void:
	# test_terrain_events's river and plank bridge, on a flat map of its size, and a second
	# bridge downstream.
	await _play(24)
	var editor := _controller.live_edits.editor
	var river := PackedVector2Array([Vector2(8, -20), Vector2(9, 0), Vector2(10, 20)])
	assert_gt(editor.water.carve_river(river, PackedFloat32Array([1.4]), WaterBody.Depth.WAIST), 0)
	# The live editor computes water off the main thread: land it before laying the bridges.
	editor.water.finish_work()
	for z: float in [0.0, 8.0]:
		var at := 9.0 + z / 20.0
		var id := editor.crossings.place(
			Crossing.Kind.PLANK, Vector3(at - 4.0, 0, z), Vector3(at + 4.0, 0, z)
		)
		assert_gt(id, 0, "a plank bridge at z %.0f" % z)
	editor.finish_height_work()
	_events.refresh()
	_events.pick(EventPresets.COLLAPSE)
	var brush := _game_map.get_brush_tool()
	assert_true(brush.is_active(), "Drop bridge is out")
	for left in [1, 0]:
		var bridge := editor.document.crossings[0]
		var middle := (bridge.start + bridge.end) * 0.5
		brush.hit = editor.to_world(Vector3(middle.x, 0.0, middle.y))
		brush.mode.press(brush)
		assert_eq(_controller.live_edits.events.active_count(), 1, "the click started the drop")
		# Stepped as test_terrain_events steps it: into the fall, then to its end.
		_controller.live_edits.events.advance(0.6)
		_controller.live_edits.events.advance(
			TerrainEvent.bridge_collapse(bridge.id, middle, 1).duration_s
		)
		await _settle()
		assert_eq(editor.document.crossings.size(), left, "the bridge fell")
		if left > 0:
			assert_eq(_events.armed, EventPresets.COLLAPSE, "still armed for the next bridge")
			assert_true(brush.is_active(), "still out on the board")
			assert_true(_pane.preset_field.tiles.is_on(EventPresets.COLLAPSE))
	assert_eq(_events.armed, &"", "with no bridge left it puts itself away")
	assert_eq(_events.picked, &"")
	assert_false(brush.is_active())
	var tile := _pane.preset_field.tiles.get_node(String(EventPresets.COLLAPSE)) as Button
	assert_true(tile.disabled, "Drop bridge is off on a map without a bridge")
	assert_eq(tile.tooltip_text, EventPresets.NO_BRIDGE_TOOLTIP, "and its tooltip says why")
	_pane.preset_field.tiles.call("_fit_columns")
	assert_eq(tile.tooltip_text, EventPresets.NO_BRIDGE_TOOLTIP, "kept through a refit (a resize)")


func test_a_preset_arms_the_board_and_a_map_without_a_bridge_refuses_collapse() -> void:
	await _play()
	assert_false(_events.available()[EventPresets.COLLAPSE], "a flat map has no bridge")
	assert_true(_events.available()[EventPresets.TOPPLE])
	_events.pick(EventPresets.TOPPLE)
	var brush := _game_map.get_brush_tool()
	assert_true(brush.is_active(), "Topple is out on the board")
	assert_true(brush.mode is ToppleMode)
	assert_eq(brush.min_stroke_seconds, PlayEvents.PLAY_CLICK_SECONDS)
	var fired := []
	(brush.mode as ToppleMode).fired.connect(func(event: TerrainEvent) -> void: fired.append(event))
	brush.hit = RAISE_AT
	brush.mode.press(brush)
	brush.mode.end(brush)
	assert_eq(fired.size(), 1, "a click fires a forest fall")
	assert_eq((fired[0] as TerrainEvent).kind, TerrainEvent.Kind.FOREST_FALL)
	assert_almost_eq((fired[0] as TerrainEvent).radius_m, brush.get_radius(), 0.01)
	_events.put_away()
	assert_eq(brush.min_stroke_seconds, 0.0, "authoring's click again")


func test_a_quick_click_in_play_shows_on_the_board() -> void:
	await _play()
	_events.pick(SculptTool.ID)
	var brush := _game_map.get_brush_tool()
	brush.set_radius(BrushTool.DEFAULT_RADIUS)
	brush.pointer = _game_map.camera_node.unproject_position(RAISE_AT)
	brush.has_pointer = true
	await get_tree().process_frame
	# Pressed and released within one frame: BrushTool resolves the click at once.
	brush.pressed = true
	brush.press_pending = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = brush.pointer
	brush.handle_input(release)
	await _settle()
	var raised := _height_at(RAISE_AT)
	assert_gt(raised, 0.12, "one click raises a mound a GM can see (%.3f m)" % raised)
