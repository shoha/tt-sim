extends GutTest

## The Structure tool (card S4): StructurePlacement (plans, size clamps, the ground a lot may
## stand on, the nearest legal spot), the editor's lot, re-roll and pick calls, StructureBrush's
## state machine (the eased ghost, a click, a drag, the turn, the re-roll, the removal, the
## cancel), the palette pane, the registration, the live edit a peer applies, and a save and
## reload of what the gesture laid. Summary: docs/systems/structures.md "The tool".

const SAVE_PATH := "user://test_structure_tool.ttmap"
const COTTAGE := "core:cottage"
const TOWNHOUSE := "core:townhouse"

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _nodes() -> AuthoredStructures:
	return _map.get_node(AuthoredStructures.NODE_NAME) as AuthoredStructures


func _row(ref: String = COTTAGE) -> Dictionary:
	return LibraryStructureStore.structure(ref)


func _brush(ref: String = COTTAGE) -> StructureBrush:
	var brush := StructureBrush.new()
	brush.pick(ref)
	return brush


## A river down the line x = `x`, `half` metres either side, over flat ground (so it is wet).
func _river(x: float, half: float) -> void:
	var line := PackedVector2Array([Vector2(x, -14), Vector2(x, 14)])
	var widths := PackedFloat32Array([half, half])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, 1.0))
	for k in _doc.heights.size():
		_doc.heights[k] = 0.0


## The ground rising `rise` metres per metre of x.
func _slope(rise: float) -> void:
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			heights[_doc.sample_index(x, z)] = rise * _doc.sample_to_world(Vector2(x, z)).x
	_doc.heights = heights


# --- plans and sizes ---------------------------------------------------------------------


func test_a_lot_is_a_valid_plan_with_its_front_facing_the_camera() -> void:
	var plan := StructurePlacement.rect_plan(Vector2(2, 1), Vector2(6, 4), 0.0)
	assert_eq(ProcgenPlan.problems(plan), [] as Array[String], "wound and sized as the rules want")
	assert_gt(ProcgenPlan.outward(plan, 0).y, 0.99, "edge 0 (the door) faces +Z at turn 0")
	assert_eq(ProcgenPlan.edge_middle(plan, 0), Vector2(2, 3))
	var turned := StructurePlacement.rect_plan(Vector2(2, 1), Vector2(6, 4), deg_to_rad(90.0))
	assert_eq(ProcgenPlan.problems(turned), [] as Array[String])
	assert_gt(
		absf(ProcgenPlan.outward(turned, 0).x), 0.99, "a quarter turn faces the door sideways"
	)


func test_sizes_clamp_to_the_recipes_range_instead_of_failing() -> void:
	var row := _row(COTTAGE)
	var small := StructurePlacement.clamp_size(Vector2(0.2, 0.2), row)
	assert_eq(small, Vector2(row.min_side_m, row.min_side_m), "no smaller than the least side")
	var wide := StructurePlacement.clamp_size(Vector2(80, 3), row)
	assert_eq(wide.x, float(row.max_side_m), "no wider than the largest side")
	var huge := StructurePlacement.clamp_size(Vector2(60, 60), row)
	assert_lte(huge.x * huge.y, float(row.max_area_m2) + 0.01, "and not over the area")
	assert_almost_eq(huge.x, huge.y, 0.001, "the shape is kept while the area comes down")
	assert_eq(StructurePlacement.default_size(row), Vector2(6, 4), "the recipe's own default")


func test_a_dragged_rectangle_follows_the_corners_until_the_clamp() -> void:
	var row := _row(COTTAGE)
	var made := StructurePlacement.corner_plan(Vector2(0, 0), Vector2(8, 5), 0.0, row)
	assert_eq(made.size, Vector2(8, 5))
	assert_eq(made.centre, Vector2(4, 2.5))
	assert_eq(ProcgenPlan.problems(made.plan), [] as Array[String])
	var backwards := StructurePlacement.corner_plan(Vector2(0, 0), Vector2(-8, -5), 0.0, row)
	assert_eq(backwards.size, Vector2(8, 5), "the opposite corner may be dragged any way")
	assert_eq(backwards.centre, Vector2(-4, -2.5))
	var past := StructurePlacement.corner_plan(Vector2(0, 0), Vector2(40, 5), 0.0, row)
	assert_eq(past.size.x, float(row.max_side_m), "held past the largest size it grows no more")


# --- the ground ---------------------------------------------------------------------------


func test_flat_dry_ground_takes_a_lot_and_a_bank_or_water_does_not() -> void:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	assert_eq(StructurePlacement.ground_problem(_doc, plan), "")
	_slope(0.2)
	assert_eq(StructurePlacement.ground_problem(_doc, plan), "", "a gentle slope is fine")
	_slope(0.8)
	assert_eq(StructurePlacement.ground_problem(_doc, plan), StructurePlacement.STEEP)
	_slope(0.0)
	_river(0.0, 2.0)
	assert_eq(StructurePlacement.ground_problem(_doc, plan), StructurePlacement.WATER)
	var far := StructurePlacement.rect_plan(Vector2(9, 0), Vector2(6, 4), 0.0)
	assert_eq(StructurePlacement.ground_problem(_doc, far), "", "dry beside the river")
	var off := StructurePlacement.rect_plan(Vector2(400, 0), Vector2(6, 4), 0.0)
	assert_eq(StructurePlacement.ground_problem(_doc, off), StructurePlacement.OFF_MAP)


func test_the_nearest_legal_spot_eases_a_lot_off_the_water() -> void:
	_river(0.0, 1.0)
	var spot := StructurePlacement.nearest_legal(_doc, Vector2(0, 0), Vector2(6, 4), 0.0)
	assert_eq(spot.problem, "", "a dry spot was found")
	assert_true(spot.moved)
	assert_eq(StructurePlacement.ground_problem(_doc, spot.plan), "")
	assert_gt(absf(spot.centre.x), 3.0 + 1.0, "clear of the river")
	assert_lt(spot.centre.distance_to(Vector2.ZERO), StructurePlacement.REACH_M + 0.01)
	var here := StructurePlacement.nearest_legal(_doc, Vector2(9, 0), Vector2(6, 4), 0.0)
	assert_false(here.moved, "a legal spot stays where it is wanted")
	assert_eq(here.centre, Vector2(9, 0))


func test_a_lot_with_no_legal_spot_in_reach_keeps_the_reason() -> void:
	_slope(0.9)
	var spot := StructurePlacement.nearest_legal(_doc, Vector2(0, 0), Vector2(6, 4), 0.0)
	assert_eq(spot.problem, StructurePlacement.STEEP)
	assert_false(spot.moved)


func test_a_lot_stands_clear_of_a_building_already_there() -> void:
	_doc.structures.append(
		Structure.make(
			1, COTTAGE, StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0), 5
		)
	)
	var plan := StructurePlacement.rect_plan(Vector2(1, 0), Vector2(6, 4), 0.0)
	assert_eq(StructurePlacement.lot_problem(_doc, plan), StructurePlacement.OCCUPIED)
	var spot := StructurePlacement.nearest_legal(_doc, Vector2(1, 0), Vector2(6, 4), 0.0)
	assert_true(spot.moved)
	assert_eq(StructurePlacement.lot_problem(_doc, spot.plan), "")
	assert_eq(StructurePlacement.structure_at(_doc, Vector2(1, 1)), 1)
	assert_eq(StructurePlacement.structure_at(_doc, Vector2(9, 9)), -1)


# --- the editor ---------------------------------------------------------------------------


func test_the_editor_makes_a_lot_and_refuses_what_it_cannot() -> void:
	var editor := _editor()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var lot := editor.structures.lot(COTTAGE, plan, 77)
	assert_not_null(lot)
	assert_eq(lot.seed_value, 77)
	assert_eq(lot.recipe, COTTAGE)
	assert_null(editor.structures.lot("core:no_such_house", plan, 1))
	assert_eq(editor.structures.last_refusal, StructureEditor.REFUSED_UNKNOWN)
	var sliver := PackedVector2Array(
		[Vector2(0, 0), Vector2(6, 0), Vector2(6, 0.1), Vector2(0, 0.1)]
	)
	assert_null(editor.structures.lot(COTTAGE, sliver, 1))
	assert_eq(editor.structures.last_refusal, StructureEditor.REFUSED_INVALID)
	assert_eq(_doc.structures.size(), 0, "planning changes nothing")


func test_laying_rerolling_and_removing_are_one_history_entry_each() -> void:
	var editor := _editor()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var id := editor.structures.add(editor.structures.lot(COTTAGE, plan, 100))
	assert_eq(id, 1)
	var undo_after_add := _history.undo_count()
	assert_true(editor.structures.reroll(id))
	assert_eq(_history.undo_count(), undo_after_add + 1)
	assert_eq(_doc.structure(id).seed_value, StructureEditor.next_seed(100))
	assert_false(editor.structures.reroll(99))
	_history.undo()
	assert_eq(_doc.structure(id).seed_value, 100, "an undo draws it as it was")
	assert_true(editor.structures.remove(id))
	_history.undo()
	assert_eq(_doc.structures.size(), 1)
	assert_eq(editor.structures.structure_at(Vector3(0, 0, 0)), 1)


# --- the gesture --------------------------------------------------------------------------


func test_a_click_drops_the_default_lot_and_takes_the_next_seed() -> void:
	var editor := _editor()
	var brush := _brush()
	var first := brush.seed_value
	brush.begin(Vector3(2.2, 0, 1.1))
	brush.track(editor, Vector3(2.2, 0, 1.1), 0.0)
	assert_not_null(brush.preview)
	assert_eq(brush.finish(editor), 1)
	var laid := _doc.structure(1)
	assert_eq(laid.seed_value, first, "drawn with the seed that was showing")
	assert_eq(brush.seed_value, StructureEditor.next_seed(first), "the next lot is another")
	assert_eq(laid.bounds().size, Vector2(6, 4), "at the recipe's default size")
	assert_eq(laid.bounds().get_center(), Vector2(2.0, 1.0), "centred on the 0.5 m grid")
	assert_eq(laid.style, CrossingPlacement.style_at(_doc, Vector2(2, 1)))
	_history.undo()
	assert_true(_doc.structures.is_empty(), "one undo takes it back")


func test_a_drag_sizes_the_lot_and_the_size_clamps() -> void:
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3(-4, 0, -3))
	brush.track(editor, Vector3(4, 0, 3), 0.0)
	assert_eq(brush.ghost_size, Vector2(8, 6))
	assert_eq(brush.finish(editor), 1)
	assert_eq(_doc.structure(1).bounds().size, Vector2(8, 6))
	var row := _row(COTTAGE)
	brush.begin(Vector3(-12, 0, -12))
	brush.track(editor, Vector3(-10.5, 0, -10.8), 0.0)
	assert_eq(brush.ghost_size, Vector2(row.min_side_m, row.min_side_m), "a small drag clamps up")
	brush.cancel(null)
	assert_false(brush.drawing, "a cancel drops the lot")
	assert_eq(_doc.structures.size(), 1, "and lays nothing")


func test_the_bracket_keys_scale_the_size_a_click_lays_within_the_range() -> void:
	var editor := _editor()
	var brush := _brush()
	var tool := BrushTool.new()
	add_child_autofree(tool)
	var before := brush.default_size(editor)
	brush.step(tool, 3)
	assert_gt(brush.default_size(editor).x, before.x, "bigger")
	brush.step(tool, 100)
	assert_eq(brush.size_scale, StructureBrush.SIZE_SCALE_RANGE.y, "within the range")
	assert_lte(brush.default_size(editor).x, float(_row().max_side_m), "and the recipe's limit")
	brush.step(tool, -300)
	assert_eq(brush.size_scale, StructureBrush.SIZE_SCALE_RANGE.x)
	assert_gte(brush.default_size(editor).x, float(_row().min_side_m))
	brush.size_scale = 1.5
	brush.begin(Vector3.ZERO)
	brush.track(editor, Vector3.ZERO, 0.0)
	brush.finish(editor)
	assert_eq(_doc.structure(1).bounds().size, Vector2(9, 6), "a click lays the scaled size")


func test_the_turn_rotates_the_lot_in_notches_and_quarters() -> void:
	var editor := _editor()
	var brush := _brush()
	var tool := BrushTool.new()
	add_child_autofree(tool)
	assert_true(brush.rotates())
	brush.rotate(tool, 1)
	assert_almost_eq(brush.yaw, deg_to_rad(15.0), 1e-5)
	brush.rotate(tool, 6)
	assert_almost_eq(brush.yaw, deg_to_rad(105.0), 1e-5)
	brush.rotate(tool, -8)
	assert_almost_eq(brush.yaw, TAU - deg_to_rad(15.0), 1e-5, "and round the other way")
	brush.yaw = deg_to_rad(30.0)
	brush.begin(Vector3.ZERO)
	brush.track(editor, Vector3.ZERO, 0.0)
	brush.finish(editor)
	var plan := _doc.structure(1).footprint
	assert_eq(ProcgenPlan.problems(plan), [] as Array[String])
	var along := (plan[1] - plan[0]).angle()
	assert_almost_eq(wrapf(along - PI, -PI, PI), deg_to_rad(30.0), 0.01, "laid at the turn shown")


func test_q_e_and_r_belong_to_the_brush_and_a_right_click_removes_the_building() -> void:
	var brush := StructureBrush.new()
	assert_true(brush.rotates())
	assert_true(brush.rerolls())
	assert_true(brush.picks, "RMB and Delete remove the target")
	assert_eq(BrushTool.decide(_key(KEY_E), brush.picks, false, false), BrushTool.Action.TURN_RIGHT)
	assert_eq(BrushTool.decide(_key(KEY_R), brush.picks, false, false), BrushTool.Action.REROLL)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_eq(
		BrushTool.decide(right, brush.picks, false, true),
		BrushTool.Action.REMOVE,
		"over a building"
	)
	assert_eq(
		BrushTool.decide(right, brush.picks, false, false),
		BrushTool.Action.DESELECT,
		"over bare ground it puts the brush down"
	)
	assert_eq(BrushTool.decide(_key(KEY_DELETE), brush.picks, false, true), BrushTool.Action.REMOVE)


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


func test_removing_and_rerolling_act_on_the_building_under_the_pointer() -> void:
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3.ZERO)
	brush.track(editor, Vector3.ZERO, 0.0)
	brush.finish(editor)
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	tool.hit = Vector3(0.5, 0, 0.5)
	brush.track(editor, tool.hit, 0.0)
	assert_true(brush.has_target(), "the building under the pointer is the target")
	var seed_before := _doc.structure(1).seed_value
	brush.reroll(tool)
	assert_ne(_doc.structure(1).seed_value, seed_before, "R redraws the one under the pointer")
	brush.remove_target(tool)
	assert_true(_doc.structures.is_empty())
	brush.track(editor, Vector3(9, 0, 9), 0.0)
	assert_false(brush.has_target())
	var next := brush.seed_value
	brush.reroll(tool)
	assert_ne(brush.seed_value, next, "over bare ground R draws the next lot afresh")
	assert_false(brush.erase_at(editor, Vector3(9, 0, 9)))
	assert_eq(brush.message(), StructureBrush.NOTHING)


func test_a_ctrl_press_removes_and_a_plain_press_begins_a_lot() -> void:
	var editor := _editor()
	var brush := _brush()
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	tool.hit = Vector3.ZERO
	assert_false(brush.press(tool), "a lot is not a dab stroke")
	assert_true(brush.took_press(), "but it is a gesture of its own")
	brush.track(editor, Vector3.ZERO, 0.0)
	brush.end(tool)
	assert_eq(_doc.structures.size(), 1, "the release laid it")
	tool.press_ctrl = true
	brush.press(tool)
	assert_false(brush.took_press())
	assert_true(_doc.structures.is_empty(), "Ctrl and a press removed it")


func test_the_ghost_eases_to_dry_ground_and_slides_rather_than_jumping() -> void:
	_river(0.0, 1.0)
	var editor := _editor()
	var brush := _brush()
	brush.track(editor, Vector3(9, 0, 0), 0.0)
	assert_eq(brush.ghost_centre, Vector2(9, 0), "the first frame puts the ghost at its spot")
	assert_false(brush.eased)
	brush.track(editor, Vector3(0, 0, 0), 0.016)
	assert_true(brush.eased, "the pointer is over the river, so the lot settles elsewhere")
	assert_eq(brush.problem, "")
	assert_ne(brush.target_centre, Vector2(0, 0))
	var start := brush.ghost_centre
	assert_gt(start.distance_to(brush.target_centre), 0.1, "not there yet after one frame")
	assert_lt(start.distance_to(Vector2(9, 0)), 3.0, "it has begun to slide")
	for k in 60:
		brush.track(editor, Vector3(0, 0, 0), 0.016)
	assert_eq(brush.ghost_centre, brush.target_centre, "and arrives")
	assert_eq(StructurePlacement.ground_problem(_doc, brush.ghost_plan()), "")


func test_a_release_where_nothing_fits_lays_nothing_and_says_why() -> void:
	_slope(0.9)
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3.ZERO)
	brush.track(editor, Vector3.ZERO, 0.0)
	assert_null(brush.preview)
	assert_eq(brush.finish(editor), -1)
	assert_eq(brush.message(), StructureBrush.STEEP_TEXT)
	assert_true(_doc.structures.is_empty())
	var seed_after := brush.seed_value
	assert_eq(seed_after, 4242, "a lot that was not laid does not use up its seed")


func test_a_second_lot_dropped_on_the_first_settles_beside_it() -> void:
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3.ZERO)
	brush.track(editor, Vector3.ZERO, 0.0)
	brush.finish(editor)
	brush.begin(Vector3(1, 0, 0))
	brush.track(editor, Vector3(1, 0, 0), 0.0)
	assert_true(brush.eased)
	assert_eq(brush.finish(editor), 2)
	assert_eq(StructurePlacement.occupied(_doc, _doc.structure(2).footprint, 2), "")


func test_the_readout_names_the_building_and_its_sides_in_the_levels_units() -> void:
	assert_eq(StructureBrush.readout("Cottage", 6.0, 4.0, 1.5, 5.0, "ft"), "Cottage  20 x 13 ft")
	assert_eq(StructureBrush.refusal_text(StructurePlacement.WATER), StructureBrush.WATER_TEXT)
	assert_eq(
		StructureBrush.refusal_text(String(StructureEditor.REFUSED_FULL)), StructureBrush.FULL_TEXT
	)
	assert_eq(StructureBrush.refusal_text(""), "")
	var scaled := StructureBrush.scaled_row(_row(COTTAGE), 2.0)
	assert_eq(scaled.max_side_m, float(_row(COTTAGE).max_side_m) / 2.0)
	assert_eq(scaled.default_size_m, [3.0, 2.0], "world sizes become document metres")


# --- the tool ------------------------------------------------------------------------------


func test_the_tool_is_registered_with_a_pane_a_brush_and_help() -> void:
	var tool := ToolRegistry.find(StructureTool.ID)
	assert_not_null(tool)
	assert_true(tool.exists_in(ToolDescriptor.AUTHORING))
	assert_true(tool.exists_in(ToolDescriptor.PLAY), "and by the GM in play")
	assert_eq(tool.brush_mode, StructureBrush)
	assert_true(tool.unavailable_tooltip != "")
	assert_gt(tool.help_rows().size(), 4, "the keys and the mouse have rows")
	assert_true(ResourceLoader.exists("res://assets/icons/ui/%s.svg" % tool.icon))
	assert_true(tool.works_on(_editor()))
	assert_false("building" in Wall.KIND_NAMES, "the Wall tool lost its Building (card S8)")
	for tile in WallToolPane.KIND_TILES:
		assert_true(int(tile.kind) < Wall.KIND_NAMES.size())


func test_the_pane_lists_the_librarys_buildings_by_family_with_pictures() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var served := LibraryStructureStore.structures()
	assert_eq(pane.refs().size(), served.size(), "a tile per structure")
	assert_gt(pane.family_fields.size(), 1, "grouped by family")
	var families := {}
	for field in pane.family_fields:
		families[field.caption.get_slice(" (", 0)] = true
	assert_true(families.has("Cottage") and families.has("Townhouse"), "%s" % [families.keys()])
	assert_eq(pane.family_fields[0].caption.get_slice(" (", 0), "Cottage", "cottages come first")
	for row in served:
		var texture := StructureThumbnail.of(row, StructureToolPane.THUMB_PX)
		assert_eq(texture.get_width(), StructureToolPane.THUMB_PX)
	assert_eq(pane.picked_ref(), pane.refs()[0], "the first is preselected")
	watch_signals(pane)
	pane.family_fields[1].tiles.selection_changed.emit(StringName(COTTAGE))
	assert_signal_emitted_with_parameters(pane, "structure_selected", [COTTAGE])
	pane.select_ref(TOWNHOUSE)
	assert_signal_emit_count(pane, "structure_selected", 1, "select_ref is silent")
	assert_eq(pane.picked_ref(), TOWNHOUSE)
	pane.reroll_button.pressed.emit()
	assert_signal_emitted(pane, "reroll_requested")


func test_a_pick_in_the_pane_reaches_the_brush_and_the_first_pick_is_the_panes() -> void:
	var tool := ToolRegistry.find(StructureTool.ID)
	var brush := tool.brush_mode.new() as StructureBrush
	assert_eq(brush.ref, "")
	assert_false(brush.row().is_empty(), "with no pick the brush takes the first served")
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	assert_eq(pane.picked_ref(), pane.refs()[0], "the pane preselects its first tile")
	var fresh := tool.brush_mode.new() as StructureBrush
	StructureTool.sync_pick(fresh, pane)
	assert_eq(fresh.ref, pane.picked_ref(), "a fresh brush follows the pane")
	pane.select_ref(TOWNHOUSE)
	StructureTool.sync_pick(brush, pane)
	assert_eq(pane.picked_ref(), brush.ref, "a brush with a pick of its own is shown on the pane")


func test_the_events_pane_carries_the_tool_for_the_gm() -> void:
	var pane := EventsPane.new()
	add_child_autofree(pane)
	assert_not_null(pane.structure_pane, "the GM's pane has the building tiles")
	assert_false(pane.structure_pane.get_node("StructureHeader").visible, "the tile above names it")
	watch_signals(pane)
	pane.structure_pane.structure_selected.emit(TOWNHOUSE)
	assert_signal_emitted_with_parameters(pane, "structure_selected", [TOWNHOUSE])
	var hints := PlayEvents.hints_for(StructureTool.ID)
	assert_gt(hints.size(), 3, "keys for the hint bar")


# --- what a peer and a reload see ------------------------------------------------------------


func test_a_building_laid_by_gesture_reaches_a_peer_and_survives_a_save() -> void:
	var host := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var brush := _brush(TOWNHOUSE)
	brush.begin(Vector3(-3, 0, -3))
	brush.track(host, Vector3(4, 0, 2), 0.0)
	assert_eq(brush.finish(host), 1)
	assert_eq(entries.size(), 1)
	var op := LiveEditCodec.op_of(entries[0], host)
	assert_eq(op.kind, "structures")
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
	assert_eq(decoded.problem, "")
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer_doc.structures.size(), 1)
	assert_true(peer_doc.structures[0].same_as(_doc.structures[0]), "the same record")
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(read.structures.size(), 1)
	assert_true(read.structures[0].same_as(_doc.structures[0]), "and the same after a reload")
	_nodes().flush()
	assert_not_null(_nodes().get_structure_node(1), "the host shows it")
