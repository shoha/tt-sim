extends GutTest

## The Bridge tool (P4b-2): BridgeBrush's gesture (a line planned live, placed on release,
## refused with a reason in plain words, Ctrl erase), BrushTool's Bridge mode, and the rule
## crossings follow when a later edit changes their banks or water (CrossingEditor.follow):
## re-anchored keeping the id, or removed when their water is gone, inside the history entry
## of the edit that caused it.

const RIVER_LEVEL := -0.2
const BED := -1.0
const A := BrushTool.Action
## Ground shapes shared with the water tests (the tier band, P4c-5).
const Fixtures := preload("res://tests/unit/water_fixtures.gd")

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[_doc.sample_index(x, z)] = BED
	_doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	MapSourceLoader.add_authored_crossings(_map, _doc, true)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _bridge(editor: AuthoringEditor) -> int:
	return editor.crossings.place(Crossing.Kind.PLANK, Vector3(0, 0, -1), Vector3(0, 0, 1))


# --- BridgeBrush, pure -----------------------------------------------------------------


func test_every_refusal_has_plain_words() -> void:
	for reason in [
		CrossingPlacement.REFUSED_SHORT,
		CrossingPlacement.REFUSED_NO_WATER,
		CrossingPlacement.REFUSED_NO_BANK,
		CrossingPlacement.REFUSED_FALL,
		CrossingPlacement.REFUSED_DEEP,
		CrossingPlacement.REFUSED_LONG,
		CrossingEditor.REFUSED_FULL,
		CrossingEditor.REFUSED_INVALID,
	]:
		assert_ne(BridgeBrush.refusal_text(reason, 1.524, 5.0, "ft"), "", String(reason))
	var long := BridgeBrush.refusal_text(CrossingPlacement.REFUSED_LONG, 1.524, 5.0, "ft")
	assert_string_contains(long, "79 ft", "the span limit in the level's units")
	assert_eq(BridgeBrush.refusal_text(&"", 1.524, 5.0, "ft"), "")


func test_width_steps_within_the_kind_s_range() -> void:
	var plank := Crossing.Kind.PLANK
	var stones := Crossing.Kind.STONES
	assert_gt(BridgeBrush.stepped_width(1.5, 1, plank), 1.5)
	assert_lt(BridgeBrush.stepped_width(1.5, -1, plank), 1.5)
	assert_eq(BridgeBrush.stepped_width(1.5, 40, plank), Crossing.MAX_WIDTH_M[plank])
	assert_eq(BridgeBrush.stepped_width(1.0, -40, stones), Crossing.MIN_WIDTH_M[stones])
	var brush := BridgeBrush.new()
	brush.kind = stones
	brush.step_width(3)
	assert_gt(brush.width(), Crossing.DEFAULT_WIDTH_M[stones], "stones wider")
	assert_eq(brush.widths[plank], Crossing.DEFAULT_WIDTH_M[plank], "planks untouched")


func test_readout_names_the_kind_and_its_span_or_width() -> void:
	assert_eq(
		BridgeBrush.readout(Crossing.Kind.PLANK, 6.1, 1.5, 1.524, 5.0, "ft"), "Plank bridge  20 ft"
	)
	assert_eq(
		BridgeBrush.readout(Crossing.Kind.STONES, 0.0, 1.524, 1.524, 5.0, "ft"),
		"Stepping stones  5 ft wide"
	)


func test_labels_and_widths_cover_every_kind() -> void:
	# P4d-3: a Ctrl hover over an arch or a ford indexes the labels by the crossing's kind.
	assert_eq(BridgeBrush.KIND_LABELS.size(), Crossing.Kind.size())
	var brush := BridgeBrush.new()
	assert_eq(brush.widths.size(), Crossing.Kind.size())
	for kind in Crossing.Kind.values():
		assert_ne(BridgeBrush.kind_label(kind), "", Crossing.KIND_NAMES[kind])
		assert_eq(brush.widths[kind], Crossing.DEFAULT_WIDTH_M[kind], Crossing.KIND_NAMES[kind])
	assert_eq(BridgeBrush.kind_label(Crossing.Kind.ARCH), "Stone arch")
	assert_eq(BridgeBrush.kind_label(Crossing.Kind.FORD), "Ford")
	assert_eq(
		BridgeBrush.readout(Crossing.Kind.FORD, 0.0, 2.5, 1.524, 5.0, "ft"), "Ford  8 ft wide"
	)
	brush.kind = Crossing.Kind.FORD
	brush.step_width(40)
	assert_eq(
		brush.width(), Crossing.MAX_WIDTH_M[Crossing.Kind.FORD], "clamped by the ford's range"
	)
	brush.kind = Crossing.Kind.ARCH
	brush.step_width(-40)
	assert_eq(brush.width(), Crossing.MIN_WIDTH_M[Crossing.Kind.ARCH], "and the arch's")


func test_pane_has_a_tile_per_kind_and_emits_the_picked_one() -> void:
	var pane := BridgeToolPane.new()
	add_child_autofree(pane)
	assert_eq(BridgeToolPane.KIND_TILES.size(), Crossing.Kind.size())
	assert_eq(pane.kind_field.tiles.columns, Crossing.Kind.size(), "one row")
	for tile in BridgeToolPane.KIND_TILES:
		assert_not_null(IconButton.load_icon(String(tile.icon)), String(tile.icon))
	assert_eq(pane.kind_field.tiles.selected, &"bridge_plank", "Planks preselected")
	watch_signals(pane)
	pane.kind_field.tiles.selection_changed.emit(&"bridge_arch")
	assert_signal_emitted_with_parameters(pane, "kind_selected", [Crossing.Kind.ARCH])
	pane.kind_field.tiles.selection_changed.emit(&"bridge_ford")
	assert_signal_emitted_with_parameters(pane, "kind_selected", [Crossing.Kind.FORD])
	assert_signal_emit_count(pane, "kind_selected", 2)
	pane.select_kind(Crossing.Kind.ARCH)
	assert_eq(pane.kind_field.tiles.selected, &"bridge_arch")
	assert_signal_emit_count(pane, "kind_selected", 2, "select_kind is silent")
	assert_string_contains(BridgeToolPane.HINT, "a ford needs wadeable water")


func test_bridge_mode_input() -> void:
	var mode := BrushTool.Mode.BRIDGE
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	assert_eq(BrushTool.decide(press, mode, false, false), A.BEGIN)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_eq(BrushTool.decide(right, mode, true, false), A.CANCEL, "RMB drops a line")
	assert_eq(BrushTool.decide(right, mode, false, false), A.DESELECT)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.shift_pressed = true
	assert_eq(BrushTool.decide(wheel, mode, false, false), A.GROW, "Shift+wheel: width")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert_eq(BrushTool.decide(escape, mode, true, false), A.CANCEL)


# --- the gesture -----------------------------------------------------------------------


func test_a_line_across_water_previews_then_places_one_entry() -> void:
	var editor := _editor()
	var brush := BridgeBrush.new()
	brush.begin(Vector3(0, 0, -6))
	brush.track(editor, Vector3(0, 0, -5.5), false)
	assert_null(brush.preview, "still on the bank, away from the water")
	assert_eq(brush.refusal, CrossingPlacement.REFUSED_NO_WATER)
	brush.track(editor, Vector3(0, 0, -2.5), false)
	assert_not_null(brush.preview, "near the water: the crossing already shows")
	brush.track(editor, Vector3(0, 0, 3), false)
	assert_not_null(brush.preview, "bank to bank")
	assert_true(_doc.crossings.is_empty(), "the preview changes nothing")
	assert_false(_history.can_undo())
	var id := brush.finish(editor, 1.524, 5.0, "ft")
	assert_eq(id, 1)
	assert_false(brush.drawing)
	assert_eq(_doc.crossings.size(), 1)
	assert_eq(_history.undo_count(), 1, "one history entry")
	assert_eq(_history.undo(), "Place bridge")
	assert_true(_doc.crossings.is_empty())


func test_a_refused_release_says_why() -> void:
	var editor := _editor()
	var brush := BridgeBrush.new()
	brush.begin(Vector3(0, 0, 5))
	brush.track(editor, Vector3(3, 0, 6), false)
	assert_eq(brush.finish(editor, 1.524, 5.0, "ft"), -1)
	assert_eq(brush.message(), BridgeBrush.NO_WATER)
	brush.begin(Vector3(0, 0, 5))
	assert_eq(brush.finish(editor, 1.524, 5.0, "ft"), -1, "a click")
	assert_eq(brush.message(), BridgeBrush.SHORT)
	assert_false(_history.can_undo())


func test_stones_take_the_picked_kind_and_width() -> void:
	var editor := _editor()
	var brush := BridgeBrush.new()
	brush.kind = Crossing.Kind.STONES
	brush.step_width(-2)
	brush.begin(Vector3(2, 0, -3))
	brush.track(editor, Vector3(2, 0, 3), false)
	var id := brush.finish(editor, 1.524, 5.0, "ft")
	var placed := _doc.crossing(id)
	assert_eq(placed.kind, Crossing.Kind.STONES)
	assert_almost_eq(placed.width_m, brush.width(), 1e-4)


func test_an_arch_and_a_ford_take_the_picked_kind() -> void:
	# P4d-3: the two new tiles place through the same line as planks.
	var editor := _editor()
	var brush := BridgeBrush.new()
	brush.kind = Crossing.Kind.ARCH
	brush.begin(Vector3(0, 0, -3))
	brush.track(editor, Vector3(0, 0, 3), false)
	assert_not_null(brush.preview, "the arch previews")
	var arch_id := brush.finish(editor, 1.524, 5.0, "ft")
	assert_gt(arch_id, 0)
	assert_eq(_doc.crossing(arch_id).kind, Crossing.Kind.ARCH)
	assert_almost_eq(
		_doc.crossing(arch_id).width_m, Crossing.DEFAULT_WIDTH_M[Crossing.Kind.ARCH], 1e-4
	)
	brush.kind = Crossing.Kind.FORD
	brush.begin(Vector3(4, 0, -3))
	brush.track(editor, Vector3(4, 0, 3), false)
	assert_not_null(brush.preview, "the ford previews over waist water")
	var ford_id := brush.finish(editor, 1.524, 5.0, "ft")
	assert_gt(ford_id, 0)
	assert_eq(_doc.crossing(ford_id).kind, Crossing.Kind.FORD)
	assert_eq(_doc.crossings.size(), 2)
	assert_eq(_history.undo(), "Place ford")
	assert_eq(_history.undo(), "Place stone arch")
	assert_true(_doc.crossings.is_empty())


func test_ctrl_hover_over_a_ford_names_it() -> void:
	# P4d-3: before the labels covered every kind this hover indexed past the end.
	var editor := _editor()
	var id := editor.crossings.place(Crossing.Kind.FORD, Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_gt(id, 0)
	var brush := BridgeBrush.new()
	brush.track(editor, Vector3(0.2, 0, 0), true)
	assert_eq(brush.hover_id, id, "Ctrl held over the bar")
	var hovered := editor.document.crossing(brush.hover_id)
	assert_eq("Remove " + BridgeBrush.kind_label(hovered.kind).to_lower(), "Remove ford")


func test_ctrl_hover_and_erase() -> void:
	var editor := _editor()
	var id := _bridge(editor)
	var brush := BridgeBrush.new()
	brush.track(editor, Vector3(0.2, 0, 0), true)
	assert_eq(brush.hover_id, id, "Ctrl held over the deck")
	brush.track(editor, Vector3(0.2, 0, 0), false)
	assert_eq(brush.hover_id, -1, "no hover without Ctrl")
	assert_false(brush.erase_at(editor, Vector3(6, 0, 6)))
	assert_eq(brush.message(), BridgeBrush.NOTHING)
	assert_true(brush.erase_at(editor, Vector3(0.2, 0, 0)))
	assert_true(_doc.crossings.is_empty())
	assert_eq(_history.undo(), "Remove bridge")
	assert_eq(_doc.crossings.size(), 1)


func test_brush_tool_places_on_release_and_reports_a_refusal() -> void:
	var editor := _editor()
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	tool.set_mode(BrushTool.Mode.BRIDGE)
	watch_signals(tool)
	tool.bridge.begin(Vector3(0, 0, -3))
	tool.bridge.track(editor, Vector3(0, 0, 3), false)
	tool.finish_gesture()
	assert_eq(_doc.crossings.size(), 1)
	assert_signal_not_emitted(tool, "bridge_refused")
	tool.bridge.begin(Vector3(0, 0, 6))
	tool.bridge.track(editor, Vector3(1, 0, 7), false)
	tool.finish_gesture()
	assert_signal_emitted_with_parameters(tool, "bridge_refused", [BridgeBrush.NO_WATER])
	tool.bridge.begin(Vector3(3, 0, -3))
	tool.bridge.track(editor, Vector3(3, 0, 3), false)
	tool.call("_cancel_gesture")
	assert_false(tool.bridge.drawing)
	assert_eq(_doc.crossings.size(), 1, "a cancelled line places nothing")


# --- following edits -------------------------------------------------------------------


func test_follow_keeps_a_crossing_nothing_changed_under() -> void:
	var editor := _editor()
	_bridge(editor)
	var before := _doc.crossings[0]
	var result := CrossingEditor.followed_list(_doc, Rect2())
	assert_eq([result.moved, result.removed, result.reached], [0, 0, 1])
	assert_same(result.crossings[0], before, "the same object: no nudge")
	var node := _map.get_node(AuthoredCrossings.NODE_NAME) as AuthoredCrossings
	var builds := node.builds
	watch_signals(editor.crossings)
	# The edit reached it, so the record keeps the same list on both sides (P4d-5c: restore
	# refreshes it over undone ground); nothing changed under it, so nothing rebuilds now.
	var record := editor.crossings.follow(Rect2())
	assert_same(record.before, record.after, "the same list on both sides")
	assert_same(record.before[0], before)
	assert_false((record.area as Rect2).has_area(), "no scatter to regrow")
	assert_eq(node.builds, builds, "nothing rebuilt")
	assert_signal_not_emitted(editor.crossings, "followed")
	assert_eq(editor.crossings.follow(Rect2(20, 20, 1, 1)), {}, "out of reach: nothing to record")


func test_follow_re_anchors_when_a_bank_moves_keeping_the_id() -> void:
	var editor := _editor()
	var id := _bridge(editor)
	var before := _doc.crossing(id).copy()
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 4.0 and p.y > 1.5 and p.y < 5.0:
				heights[_doc.sample_index(x, z)] = 0.5
	_doc.heights = heights
	watch_signals(editor.crossings)
	var record := editor.crossings.follow(Rect2(-3, 1, 6, 3))
	assert_false(record.is_empty())
	assert_signal_emitted_with_parameters(editor.crossings, "followed", [1, 0])
	var moved := _doc.crossing(id)
	assert_not_null(moved, "the same id")
	assert_gt(moved.levels.z, before.levels.z + 0.3, "its end stands on the raised bank")
	assert_almost_eq(moved.levels.x, before.levels.x, 0.02, "the other end stays")
	editor.crossings.restore(record, false)
	assert_true(_doc.crossing(id).same_as(before))
	editor.crossings.restore(record, true)
	assert_true(_doc.crossing(id).same_as(moved))


func test_a_crossing_goes_with_its_water_in_the_erase_s_entry() -> void:
	var editor := _editor()
	var id := _bridge(editor)
	var before := _doc.crossing(id).copy()
	var entries := _history.undo_count()
	watch_signals(editor.crossings)
	assert_true(editor.water.erase_water_begin())
	editor.water.erase_water_dab(Vector3(0, 0, 0), Vector3(0.5, 0, 0), 1.0)
	assert_true(editor.water.erase_water_end())
	editor.finish_height_work()
	assert_true(_doc.water_bodies.is_empty())
	assert_null(_doc.crossing(id), "no water, no crossing")
	assert_signal_emitted_with_parameters(editor.crossings, "followed", [0, 1])
	assert_eq(_history.undo_count(), entries + 1, "one entry: the erase")
	assert_eq(_history.undo(), "Erase water")
	assert_eq(_doc.water_bodies.size(), 1)
	assert_true(_doc.crossing(id).same_as(before), "both come back")
	_history.redo()
	assert_null(_doc.crossing(id))


func test_a_sculpt_that_fills_the_river_removes_the_crossing_in_its_entry() -> void:
	var editor := _editor()
	var id := _bridge(editor)
	var before := _doc.crossing(id).copy()
	var entries := _history.undo_count()
	var tier_y := HeightBrush.tier_height(1, _doc.tier_height_m)
	assert_true(editor.begin_height_stroke(HeightBrush.TIER, tier_y))
	editor.stroke_dab(Vector3(-2, 0, 0), Vector3(2, 0, 0), 3.5, 1.0)
	editor.flush()
	assert_true(editor.end_stroke())
	editor.finish_height_work()
	assert_null(_doc.crossing(id), "the channel under it is filled")
	assert_eq(_history.undo_count(), entries + 1, "one entry: the stroke")
	_history.undo()
	assert_true(_doc.crossing(id).same_as(before), "undo puts it back with the ground")
	assert_not_null(
		(_map.get_node(AuthoredCrossings.NODE_NAME) as AuthoredCrossings).get_crossing_node(id)
	)


func test_a_river_falling_under_a_bridge_removes_it_in_the_carve_s_entry() -> void:
	# P4c-5: a tier north of a calm river, a bridge across the river just east of where a
	# tributary will come down. The tributary drawn off the tier into the river falls there,
	# and the bridge, snapped again from its own anchors, now stands too close to the fall: it
	# goes in the carve's entry (the follow rule, with the fall refusal) and undo brings the
	# ground, the water and the bridge back together.
	_doc = MapDocument.create_flat(Vector2i(30, 30), "grass", "v", 9)
	Fixtures.tier_band(_doc)
	var editor := _editor()
	editor.water.carve_river(
		PackedVector2Array([Vector2(-14, 3), Vector2(14, 3)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.WAIST
	)
	editor.finish_height_work()
	assert_true(WaterFalls.falls(_doc).is_empty(), "a calm river")
	var id := editor.crossings.place(Crossing.Kind.PLANK, Vector3(2.2, 0, 1), Vector3(2.2, 0, 5))
	assert_gt(id, 0, "a bridge over it")
	var before := _doc.crossing(id).copy()
	var entries := _history.undo_count()
	watch_signals(editor.crossings)
	var carved := editor.water.carve_river(
		PackedVector2Array([Vector2(0, -9), Vector2(0, 3)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	editor.finish_height_work()
	assert_gt(carved, 0, "the tributary is carved")
	assert_eq(WaterFalls.falls(_doc).size(), 1, "and falls off the tier into the river")
	assert_null(_doc.crossing(id), "the bridge is too close to the fall")
	assert_signal_emitted_with_parameters(editor.crossings, "followed", [0, 1])
	var again := CrossingPlacement.place(
		_doc, before.start, before.end, before.kind, before.width_m, before.style
	)
	assert_eq(again.refusal, CrossingPlacement.REFUSED_FALL, "for that reason")
	assert_eq(_history.undo_count(), entries + 1, "one entry: the carve")
	assert_eq(_history.undo(), "Carve river")
	editor.finish_height_work()
	assert_true(WaterFalls.falls(_doc).is_empty(), "undo takes the tributary and its fall")
	assert_true(_doc.crossing(id).same_as(before), "and brings the bridge back")
	assert_not_null(
		(_map.get_node(AuthoredCrossings.NODE_NAME) as AuthoredCrossings).get_crossing_node(id)
	)


func test_an_edit_away_from_a_crossing_leaves_it_alone() -> void:
	var editor := _editor()
	var id := _bridge(editor)
	var before := _doc.crossing(id)
	watch_signals(editor.crossings)
	var tier_y := HeightBrush.tier_height(1, _doc.tier_height_m)
	assert_true(editor.begin_height_stroke(HeightBrush.TIER, tier_y))
	editor.stroke_dab(Vector3(7, 0, 7), Vector3(8, 0, 7), 1.0, 1.0)
	editor.flush()
	assert_true(editor.end_stroke())
	editor.finish_height_work()
	assert_same(_doc.crossing(id), before, "untouched")
	assert_signal_not_emitted(editor.crossings, "followed")


# --- planning cost ---------------------------------------------------------------------


func test_courses_cut_near_a_walk_answer_the_same() -> void:
	var line := PackedVector2Array()
	var widths := PackedFloat32Array()
	for k in 30:
		line.append(Vector2(-9.0 + k * 0.6, 4.0 + sin(k * 0.5) * 2.0))
		widths.append(1.0)
	_doc.water_bodies.append(WaterBody.river(2, line, widths, WaterBody.Depth.ANKLE, 0.3))
	var near := Rect2(-1.5, -6.0, 3.0, 12.0)
	var cut := WaterGeometry.river_courses(_doc, near)
	var whole := WaterGeometry.river_courses(_doc)
	assert_lt((cut[2][0] as PackedVector2Array).size(), (whole[2][0] as PackedVector2Array).size())
	var far := WaterGeometry.river_courses(_doc, Rect2(-9.0, -9.5, 1.0, 1.0))
	assert_eq(far[1], [], "a river that never comes near is skipped")
	for z in range(-12, 13):
		for x in range(-3, 4):
			var p := near.position + Vector2(x + 3, z + 12) * Vector2(0.5, 0.5)
			assert_eq(
				WaterGeometry.level_at(_doc, p, -1, cut), WaterGeometry.level_at(_doc, p), str(p)
			)


# --- warming and look -------------------------------------------------------------------


func test_warm_surfaces_cover_planks_and_each_biome_s_rock() -> void:
	var surfaces := AuthoredCrossings.surfaces_for_styles(
		PackedStringArray(["rocky_badlands_summer_s1", "temperate_forest_summer_s1"])
	)
	assert_has(surfaces, AuthoredCrossings.WOOD_SURFACE)
	assert_has(surfaces, AuthoredCrossings.stone_surface("rocky_badlands_summer_s1"))
	assert_has(surfaces, AuthoredCrossings.stone_surface("temperate_forest_summer_s1"))
	assert_has(AuthoredCrossings.surfaces_for_styles(PackedStringArray()), "cliff")


func test_moss_grows_on_stone_tops_in_patches_by_climate() -> void:
	var crossing := Crossing.make(
		1, Crossing.Kind.STONES, Vector2(0, -3), Vector2(0, 3), Vector3(0.0, -0.1, 0.0), 1.15
	)
	_doc.crossings.append(crossing)
	var arrays: Array = CrossingGeometry.build_one(_doc, crossing).stone
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var split := AuthoredCrossings.moss_split(arrays, 0.6)
	var rock: PackedInt32Array = split[0][Mesh.ARRAY_INDEX]
	var moss: PackedInt32Array = split[1][Mesh.ARRAY_INDEX]
	assert_eq(rock.size() + moss.size(), indices.size(), "every facet is rock or moss")
	var tops := 0
	for t in range(0, indices.size(), 3):
		if normals[indices[t]].y > 0.9:
			tops += 1
	var mossy_tops := moss.size() / 3
	assert_gt(mossy_tops, tops / 4, "a good share of the tops")
	assert_lt(mossy_tops, tops, "in patches, not every top facet")
	for t in range(0, moss.size(), 3):
		assert_gt(normals[moss[t]].y, 0.5, "moss only on facets facing up")
	assert_eq(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array, indices, "input untouched")
	var none := AuthoredCrossings.moss_split(arrays, 0.0)
	assert_eq(none[1], [], "no moss at amount 0")
	assert_gt(AuthoredCrossings.moss_amount("temperate_forest_summer_s1"), 0.0)
	assert_gt(AuthoredCrossings.moss_amount("alpine_meadow_summer_s1"), 0.0)
	assert_eq(AuthoredCrossings.moss_amount("rocky_badlands_summer_s1"), 0.0, "dry: bare")
	assert_has(
		AuthoredCrossings.surfaces_for_styles(PackedStringArray(["temperate_forest_summer_s1"])),
		AuthoredCrossings.MOSS_SURFACE
	)
	assert_does_not_have(
		AuthoredCrossings.surfaces_for_styles(PackedStringArray(["rocky_badlands_summer_s1"])),
		AuthoredCrossings.MOSS_SURFACE
	)
