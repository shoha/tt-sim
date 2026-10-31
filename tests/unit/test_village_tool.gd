extends GutTest

## The Village tool (villagetool, docs/systems/villages.md section 10): the pure rules
## (VillagePlazas: pick, radius of a drag, the village a press belongs to, a plaza's paving
## stroke, the pane's state; VillageSwatch), the editor's new edits (resize_plaza, remove_plaza
## that takes the paving back) as one history entry each with a live-edit peer ending level, the
## brush's gestures (VillageBrush on a BrushTool), the pane (VillageToolPane) and the tool's place
## in the registry.

const A := BrushTool.Action

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


func _editor(doc: MapDocument = null, history: AuthoringHistory = null) -> AuthoringEditor:
	var use := doc if doc != null else _doc
	var root := _map
	if doc != null:
		root = Node3D.new()
		add_child_autofree(root)
	root.add_child(AuthoredTerrain.create(use))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	root.add_child(node)
	var editor := AuthoringEditor.create(use, root, history if history != null else _history)
	editor.scatter.attach_document(use)
	return editor


func _street(editor: AuthoringEditor) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, 0),
		Vector3(12, 0, 0),
		-1.0,
		{"seed": 5, "side": 2, "preset": 3}
	)


func _paint_state(doc: MapDocument) -> String:
	var weights := doc.surface_weights
	return "%s|%d|%d" % [",".join(doc.surface_ids), weights.size(), hash(weights)]


func _weight_at(p: Vector2, surface: String) -> int:
	var s := _doc.world_to_sample(p).round()
	return _doc.surface_weight(_doc.sample_index(int(s.x), int(s.y)), _doc.surface_ids.find(surface))


func _village(plazas: Array = []) -> Settlement:
	var record := Settlement.make(1, "market_town", 1, 5)
	for plaza in plazas:
		record.plazas.append(plaza)
	return record


func _list(records: Array[Settlement]) -> Array[Settlement]:
	return records


# --- the pure rules --------------------------------------------------------------------------


func test_radius_is_held_to_the_plaza_range_in_tenths() -> void:
	assert_eq(VillagePlazas.clamp_radius(0.2), Settlement.PLAZA_MIN_RADIUS_M)
	assert_eq(VillagePlazas.clamp_radius(99.0), Settlement.PLAZA_MAX_RADIUS_M)
	assert_eq(VillagePlazas.clamp_radius(5.04), 5.0)
	assert_almost_eq(VillagePlazas.clamp_radius(5.06), 5.1, 0.0001)


func test_a_click_or_short_drag_makes_the_default_plaza_and_a_drag_sizes_it() -> void:
	var centre := Vector2(3, 4)
	assert_eq(VillagePlazas.radius_for_drag(centre, centre), VillagePlazas.DEFAULT_RADIUS_M)
	assert_eq(
		VillagePlazas.radius_for_drag(centre, centre + Vector2(1.2, 0)), VillagePlazas.DEFAULT_RADIUS_M
	)
	assert_eq(VillagePlazas.radius_for_drag(centre, centre + Vector2(0, 7.04)), 7.0)
	assert_eq(VillagePlazas.radius_for_drag(centre, centre + Vector2(2, 0)), 2.0)
	assert_eq(VillagePlazas.radius_for_drag(centre, centre + Vector2(40, 0)), 16.0, "clamped")


func test_a_rim_drag_follows_the_pointer_without_jumping_where_it_grabbed() -> void:
	assert_eq(VillagePlazas.radius_for_rim_drag(5.0, 5.4, 5.4), 5.0, "no move, no change")
	assert_eq(VillagePlazas.radius_for_rim_drag(5.0, 5.4, 8.4), 8.0)
	assert_eq(VillagePlazas.radius_for_rim_drag(5.0, 5.4, 0.0), 2.0, "clamped to the minimum")


func test_pick_prefers_the_rim_then_the_smallest_disc_and_otherwise_nothing() -> void:
	var big := _village([{"at": Vector2(0, 0), "radius": 8.0}])
	var small := Settlement.make(2, "farming_hamlet", 2, 5)
	small.plazas = [{"at": Vector2(0, 0), "radius": 3.0}]
	var all := _list([big, small])
	var rim := VillagePlazas.pick(all, Vector2(8.3, 0), 0.9)
	assert_eq(rim["settlement"], 1)
	assert_eq(rim["part"], VillagePlazas.PART_RIM)
	var inside := VillagePlazas.pick(all, Vector2(1, 0), 0.9)
	assert_eq(inside["settlement"], 2, "the smaller disc of the two")
	assert_eq(inside["part"], VillagePlazas.PART_INSIDE)
	assert_eq(VillagePlazas.pick(all, Vector2(20, 0), 0.9), {}, "bare ground")
	var near_both := VillagePlazas.pick(all, Vector2(3.2, 0), 0.9)
	assert_eq(near_both["settlement"], 2, "the nearer rim wins over the bigger disc's inside")
	assert_eq(near_both["part"], VillagePlazas.PART_RIM)


func test_a_press_belongs_to_the_picked_village_in_reach_else_the_nearest() -> void:
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var editor := _editor()
	var first := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, -32),
		Vector3(12, 0, -32),
		-1.0,
		{"seed": 5, "side": 2, "preset": 3}
	)
	var second := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, 32),
		Vector3(12, 0, 32),
		-1.0,
		{"seed": 6, "side": 2, "preset": 3}
	)
	var a := editor.settlements.dress(first, "farming_hamlet")
	var b := editor.settlements.dress(second, "market_town")
	assert_gt(a, 0)
	assert_gt(b, 0)
	var near_a := Vector2(0, -22)
	var near_b := Vector2(0, 38)
	assert_eq(VillagePlazas.village_for(_doc, near_a, a, 30.0), a, "in reach of the picked one")
	assert_eq(VillagePlazas.village_for(_doc, near_b, a, 30.0), b, "too far from it: the nearer one")
	var between := Vector2(0, 1)
	assert_eq(VillagePlazas.village_for(_doc, between, -1), b, "nearest when none is picked")
	assert_eq(VillagePlazas.village_for(_doc, between, a), a, "the picked one by a few metres")
	assert_eq(VillagePlazas.village_for(_doc, Vector2(0, 8), a), b, "but not by many")
	assert_eq(VillagePlazas.village_for(_doc, Vector2(0, 0), -1, 20.0), -1, "out of everyone's reach")
	assert_almost_eq(VillagePlazas.distance_to(_doc, _doc.settlement(a), near_a), 10.0, 0.01)


func test_a_plazas_paving_stroke_is_found_and_a_missing_one_is_minus_one() -> void:
	var plaza := {"at": Vector2(1.25, 8.5), "radius": 4.0}
	var ground: Array[Dictionary] = [
		{"surface": "a", "from": Vector2(-12, 0), "to": Vector2(12, 0), "radius": 3.2, "seconds": 1.2},
		{
			"surface": "b",
			"from": Vector2(1.25, 8.5),
			"to": Vector2(1.25, 8.5),
			"radius": 4.48,
			"seconds": 1.2
		},
		{"surface": "a", "from": Vector2(2, 2), "to": Vector2(2, 3), "radius": 1.0, "seconds": 1.2},
	]
	assert_eq(VillagePlazas.stroke_index(ground, plaza), 1)
	assert_eq(VillagePlazas.stroke_index(ground, {"at": Vector2(1.25, 8.5), "radius": 5.0}), -1)
	assert_eq(VillagePlazas.stroke_index(ground, {"at": Vector2(9, 9), "radius": 4.0}), -1)


func test_the_panes_state_names_the_picked_village_and_plaza() -> void:
	var record := _village(
		[{"at": Vector2(0, 9), "radius": 4.0}, {"at": Vector2(5, 9), "radius": 2.5}]
	)
	_doc.settlements = _list([record])
	var state := VillagePlazas.state_of(_doc, 1, 1)
	assert_eq(state["village"], 1)
	assert_eq(state["kit"], "market_town")
	assert_eq(state["plazas"], 2)
	assert_eq(state["plaza"], 1)
	assert_eq(state["radius"], 2.5)
	assert_false(state["full"])
	assert_ne(state["road"], "", "the kit's road surface is named")
	assert_ne(state["plaza_ground"], "")
	var none := VillagePlazas.state_of(_doc, -1, -1)
	assert_eq(none["village"], -1)
	assert_eq(none["plaza"], -1)
	assert_eq((none["villages"] as Array).size(), 1)
	assert_eq(VillagePlazas.state_of(_doc, 1, 7)["plaza"], -1, "an index past the end is none")


func test_the_kit_swatch_joins_road_and_plaza_along_the_diagonal() -> void:
	var road := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	road.fill(Color.RED)
	var plaza := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	plaza.fill(Color.BLUE)
	var joined := VillageSwatch.split(road, plaza)
	assert_eq(joined.get_pixel(0, 0), Color.RED, "road to the upper left")
	assert_eq(joined.get_pixel(7, 7), Color.BLUE, "plaza to the lower right")
	assert_eq(joined.get_pixel(5, 0), Color.RED)
	assert_eq(joined.get_pixel(0, 5), Color.RED)
	assert_eq(joined.get_pixel(7, 4), Color.BLUE)
	assert_ne(joined.get_pixel(3, 4), Color.RED, "the seam between them")
	assert_ne(joined.get_pixel(3, 4), Color.BLUE)


func test_every_kit_has_a_picture_of_its_own_ground() -> void:
	for kit in Settlement.KIND_NAMES:
		var texture := VillageSwatch.kit_texture(kit, PaletteLibrary.DEFAULT_ROOT, 24)
		assert_eq(texture.get_width(), 24, kit)
		assert_ne(VillagePlazas.ground_of(kit).get("road", ""), "", kit)


# --- the editor: resize and remove -------------------------------------------------------------


func test_resizing_a_plaza_repaves_it_as_one_entry_and_undoes() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town", 0.7, 1.0)
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 10), 3.0))
	var small := _paint_state(_doc)
	var strokes := _doc.settlement(id).ground.size()
	var entries := _history.undo_count()
	assert_true(editor.settlements.resize_plaza(id, 0, 5.5))
	assert_eq(_history.undo_count(), entries + 1, "the paving and the record are one entry")
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 5.5)
	var ground := _doc.settlement(id).ground
	assert_eq(ground.size(), strokes, "the old disc stroke was replaced, not added to")
	assert_ne(_paint_state(_doc), small, "repaved")
	assert_gt(_weight_at(Vector2(0, 14.8), "cobblestone"), 100, "the wider disc reaches 4.8 m out")
	var wide := {"at": Vector2(0, 10), "radius": 5.5}
	assert_eq(VillagePlazas.stroke_index(ground, wide), strokes - 1)
	_history.undo()
	assert_eq(_paint_state(_doc), small)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 3.0)
	_history.redo()
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 5.5)


func test_a_smaller_plaza_gives_its_ground_back() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 10), 5.5))
	assert_gt(_weight_at(Vector2(0, 14.8), "cobblestone"), 100)
	assert_true(editor.settlements.resize_plaza(id, 0, 3.0))
	assert_eq(_weight_at(Vector2(0, 14.8), "cobblestone"), 0, "bare again beyond the new rim")
	assert_gt(_weight_at(Vector2(0, 10), "cobblestone"), 200, "paved inside it")


func test_resize_refuses_what_the_record_refuses_or_changes_nothing() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 10), 3.0))
	var entries := _history.undo_count()
	assert_false(editor.settlements.resize_plaza(id, 0, 3.0), "the same size")
	assert_false(editor.settlements.resize_plaza(id, 0, 40.0), "too wide")
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_PLAZA)
	assert_false(editor.settlements.resize_plaza(id, 0, 0.5), "too small")
	assert_false(editor.settlements.resize_plaza(id, 3, 4.0), "no such plaza")
	assert_false(editor.settlements.resize_plaza(99, 0, 4.0), "no such village")
	assert_eq(_history.undo_count(), entries, "nothing was recorded")
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 3.0)


func test_removing_a_plaza_takes_its_paving_back_in_one_entry() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	var before := _paint_state(_doc)
	var strokes := _doc.settlement(id).ground.size()
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 10), 3.0))
	var paved := _paint_state(_doc)
	assert_ne(paved, before)
	assert_true(_doc.surface_ids.has("cobblestone"))
	var entries := _history.undo_count()
	assert_true(editor.settlements.remove_plaza(id, 0))
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(_doc.settlement(id).plazas.size(), 0)
	assert_eq(_doc.settlement(id).ground.size(), strokes, "its stroke left the record's list")
	assert_eq(_paint_state(_doc), before, "the ground is as it was before the plaza, slot included")
	_history.undo()
	assert_eq(_paint_state(_doc), paved, "undo brings the plaza and its ground back")
	assert_eq(_doc.settlement(id).plazas.size(), 1)


func test_removing_a_plaza_leaves_the_others_paved_and_hand_paint_alone() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	assert_true(editor.settlements.add_plaza(id, Vector2(7, 10), 3.0))
	var hand := SurfaceStroke.begin(_doc, "dirt_road_packed", false)
	hand.dab(Vector2(0, -11), Vector2(0, -11), 2.0, 3.0)
	assert_false(hand.finish().is_empty())
	var handed := _weight_at(Vector2(0, -11), "dirt_road_packed")
	assert_true(editor.settlements.remove_plaza(id, 0))
	assert_eq(_weight_at(Vector2(-7, 10), "cobblestone"), 0, "the first plaza is bare")
	assert_gt(_weight_at(Vector2(7, 10), "cobblestone"), 200, "the second stays paved")
	assert_eq(_weight_at(Vector2(0, -11), "dirt_road_packed"), handed, "hand paint is untouched")
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(7, 10), "the second is now the first")


func test_a_peer_ends_level_through_add_resize_remove_and_their_undos() -> void:
	var host := _editor()
	var street := _street(host)
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "market_town")
	assert_true(host.settlements.add_plaza(id, Vector2(0, 10), 3.0))
	assert_true(host.settlements.resize_plaza(id, 0, 6.0))
	assert_true(host.settlements.remove_plaza(id, 0))
	assert_eq(entries.size(), 4, "dress, add, resize and remove are one entry each")
	for entry in entries:
		_send(entry, host, peer_doc, peer, false)
	assert_eq(_paint_state(peer_doc), _paint_state(_doc), "the same ground byte for byte")
	assert_eq(peer_doc.settlement(id).plazas.size(), 0)
	for k in range(entries.size() - 1, -1, -1):
		_history.undo()
		_send(entries[k], host, peer_doc, peer, true)
		assert_eq(_paint_state(peer_doc), _paint_state(_doc), "undo %d keeps the peer level" % k)
		assert_eq(peer_doc.settlements.size(), _doc.settlements.size())


func _send(
	entry: Dictionary, host: AuthoringEditor, peer_doc: MapDocument, peer: AuthoringEditor, undo: bool
) -> void:
	for op in LiveEditCodec.ops_of(entry, host, undo):
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)


# --- the brush: gestures -----------------------------------------------------------------------


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func _frame(mode: VillageBrush, tool: BrushTool, at: Vector3) -> void:
	tool.hit = at
	mode.frame(tool)


func test_a_click_on_bare_ground_opens_a_default_plaza_in_one_entry_and_picks_it() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	_frame(mode, tool, Vector3(0, 0, 9))
	assert_eq(mode.selected_village, id, "the only village is picked without a press")
	var entries := _history.undo_count()
	assert_false(mode.press(tool))
	assert_true(mode.took_press())
	assert_eq(mode.gesture, VillageBrush.GESTURE_NEW)
	mode.end(tool)
	assert_eq(_doc.settlement(id).plazas.size(), 1)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], VillagePlazas.DEFAULT_RADIUS_M)
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(mode.selected_plaza, 0)
	assert_true(mode.has_selection())
	assert_false(mode.took_press(), "the gesture is over")


func test_dragging_from_bare_ground_sizes_the_new_plaza() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	_frame(mode, tool, Vector3(0, 0, 9))
	mode.press(tool)
	_frame(mode, tool, Vector3(4.04, 0, 9))
	assert_eq(mode.preview_radius(), 4.0, "the preview is the radius the release lays")
	assert_eq(_doc.settlement(id).plazas.size(), 0, "nothing is laid until the release")
	mode.end(tool)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 4.0)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(0, 9))


func test_dragging_a_rim_resizes_and_a_press_inside_only_picks() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 9), 4.0))
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	var entries := _history.undo_count()
	_frame(mode, tool, Vector3(1, 0, 9))
	assert_eq(mode.hover_part, VillagePlazas.PART_INSIDE)
	mode.press(tool)
	assert_eq(mode.gesture, VillageBrush.GESTURE_PICK)
	mode.end(tool)
	assert_eq(mode.selected_plaza, 0, "picked")
	assert_eq(_history.undo_count(), entries, "a pick records nothing")
	_frame(mode, tool, Vector3(4, 0, 9))
	assert_eq(mode.hover_part, VillagePlazas.PART_RIM)
	mode.press(tool)
	assert_eq(mode.gesture, VillageBrush.GESTURE_RESIZE)
	_frame(mode, tool, Vector3(7, 0, 9))
	assert_eq(mode.preview_radius(), 7.0, "the rim follows the pointer")
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 4.0, "until the release")
	mode.end(tool)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 7.0)
	assert_eq(_history.undo_count(), entries + 1, "one entry for the whole drag")


func test_a_rim_press_released_in_place_changes_nothing() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 9), 4.0))
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	var entries := _history.undo_count()
	_frame(mode, tool, Vector3(4, 0, 9))
	mode.press(tool)
	mode.end(tool)
	assert_eq(_history.undo_count(), entries)
	assert_eq(mode.selected_plaza, 0)


func test_a_press_with_no_village_or_a_full_one_says_why_and_lays_nothing() -> void:
	var editor := _editor()
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	watch_signals(tool)
	_frame(mode, tool, Vector3(0, 0, 9))
	assert_false(mode.press(tool))
	assert_false(mode.took_press())
	assert_eq(mode.message(), VillageBrush.NO_VILLAGE)
	assert_signal_emitted_with_parameters(tool, "refused", [VillageBrush.NO_VILLAGE])
	var id := editor.settlements.dress(_street(editor), "market_town")
	for k in Settlement.MAX_PLAZAS:
		assert_true(editor.settlements.add_plaza(id, Vector2(-9.0 + 6.0 * k, 10), 2.5))
	_frame(mode, tool, Vector3(0, 0, -9))
	mode.press(tool)
	assert_eq(mode.message(), VillageBrush.FULL)
	assert_eq(_doc.settlement(id).plazas.size(), Settlement.MAX_PLAZAS)


func test_delete_removes_the_plaza_under_the_pointer_and_keeps_the_pick_in_step() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	assert_true(editor.settlements.add_plaza(id, Vector2(7, 10), 3.0))
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	mode.select(id, 1)
	_frame(mode, tool, Vector3(-7, 0, 10))
	assert_true(mode.has_target())
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	assert_eq(BrushTool.decide(key, mode.picks, false, mode.has_target()), A.REMOVE)
	var entries := _history.undo_count()
	mode.remove_target(tool)
	assert_eq(_doc.settlement(id).plazas.size(), 1)
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(mode.selected_plaza, 0, "the picked plaza is now the first")
	assert_false(mode.has_target())
	assert_eq(BrushTool.decide(key, mode.picks, false, mode.has_target()), A.NONE, "nothing under it")


func test_brackets_step_the_plaza_under_the_pointer_a_metre() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 10), 4.0))
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	_frame(mode, tool, Vector3(0, 0, 10))
	mode.step(tool, 1)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 5.0)
	mode.step(tool, -1)
	mode.step(tool, -1)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 3.0)
	for k in 6:
		mode.step(tool, -1)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 2.0, "held at the smallest")
	_frame(mode, tool, Vector3(0, 0, -9))
	mode.select(id, 0)
	mode.step(tool, 2)
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 4.0, "with none under it, the picked plaza")


func test_escape_lets_go_of_a_gesture_then_of_the_pick() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	_frame(mode, tool, Vector3(0, 0, 9))
	mode.press(tool)
	_frame(mode, tool, Vector3(5, 0, 9))
	mode.cancel(tool)
	assert_eq(mode.gesture, &"")
	assert_eq(_doc.settlement(id).plazas.size(), 0, "nothing laid")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 9), 4.0))
	mode.select(id, 0)
	assert_true(mode.has_selection())
	mode.cancel(tool)
	assert_false(mode.has_selection())
	assert_eq(mode.selected_village, id, "the village stays picked")


func test_an_undo_that_takes_the_picked_plaza_away_lets_go_of_it() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 9), 4.0))
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	mode.select(id, 0)
	_history.undo()
	_frame(mode, tool, Vector3(0, 0, -9))
	assert_eq(mode.selected_plaza, -1)
	assert_eq(mode.selected_village, id)


func test_the_view_changes_when_the_document_does() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "market_town")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	_frame(mode, tool, Vector3(0, 0, -9))
	watch_signals(mode)
	_frame(mode, tool, Vector3(1, 0, -9))
	assert_signal_not_emitted(mode, "view_changed")
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 9), 4.0))
	_frame(mode, tool, Vector3(1, 0, -9))
	assert_signal_emitted(mode, "view_changed")


# --- the pane and the registry -----------------------------------------------------------------


func test_the_tool_is_on_the_rail_with_an_icon_help_and_no_shortcut_clash() -> void:
	var tool := ToolRegistry.find(VillageTool.ID)
	assert_not_null(tool)
	assert_true(tool.exists_in(ToolDescriptor.AUTHORING))
	assert_false(tool.exists_in(ToolDescriptor.PLAY))
	assert_not_null(IconButton.load_icon(tool.icon), "the rail icon exists")
	assert_gt(tool.help_rows().size(), 3)
	assert_true(tool.brush_mode == VillageBrush)


func test_the_pane_shows_what_to_do_first_then_the_kits_with_their_ground() -> void:
	var pane := VillageToolPane.new()
	add_child_autofree(pane)
	pane.show_state(VillagePlazas.state_of(_doc, -1, -1))
	assert_true(pane.empty_note.visible, "no village: it says what to do")
	assert_false(pane.kit_field.visible)
	var record := _village([{"at": Vector2(0, 9), "radius": 4.0}])
	_doc.settlements = _list([record])
	pane.show_state(VillagePlazas.state_of(_doc, 1, 0), 3.28, "ft")
	assert_false(pane.empty_note.visible)
	assert_true(pane.kit_field.visible)
	for item in SettlementSection.CHIPS:
		assert_true(pane.kit_field.tiles.has_tile(StringName("village_kit_" + String(item["kit"]))))
	assert_eq(pane.kit_field.tiles.selected, &"village_kit_market_town")
	assert_true(pane.ground_note.text.begins_with("Road: "))
	assert_true(pane.plaza_box.visible)
	assert_false(pane.remove_button.disabled)
	assert_eq(pane.size_slider.value, 4.0)
	assert_eq(pane.size_value.text, "26 ft", "the width across, in the level's units")
	assert_false(pane.village_field.visible, "one village needs no row of them")


func test_the_pane_signals_are_the_authors_picks_and_not_the_panes_updates() -> void:
	var pane := VillageToolPane.new()
	add_child_autofree(pane)
	_doc.settlements = _list([_village([{"at": Vector2(0, 9), "radius": 4.0}])])
	watch_signals(pane)
	pane.show_state(VillagePlazas.state_of(_doc, 1, 0))
	assert_signal_not_emitted(pane, "kit_picked")
	assert_signal_not_emitted(pane, "radius_committed")
	pane.kit_field.tiles.get_node("village_kit_hill_fort_village").button_pressed = true
	assert_signal_emitted_with_parameters(pane, "kit_picked", ["hill_fort_village"])
	pane.size_slider.value = 7.0
	assert_signal_emitted_with_parameters(pane, "radius_committed", [7.0])
	pane.remove_button.pressed.emit()
	assert_signal_emitted(pane, "remove_requested")


func test_the_pane_offers_a_row_of_villages_when_there_are_several() -> void:
	var pane := VillageToolPane.new()
	add_child_autofree(pane)
	var other := Settlement.make(2, "harbour_town", 2, 5)
	_doc.settlements = _list([_village(), other])
	pane.show_state(VillagePlazas.state_of(_doc, 2, -1))
	assert_true(pane.village_field.visible)
	assert_eq(pane.village_field.tiles.selected, &"village_2")
	assert_true(pane.size_slider.editable == false, "no plaza picked: the size is not editable")
	assert_true(pane.remove_button.disabled)
	watch_signals(pane)
	pane.village_field.tiles.get_node("village_1").button_pressed = true
	assert_signal_emitted_with_parameters(pane, "village_picked", [1])
