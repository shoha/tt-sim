extends GutTest

## Moving a plaza in the Village tool (topic plazamove, docs/systems/villages.md section 10): the
## pure rules (VillagePlazas: interior against rim and handle, the grab offset, the click
## threshold, the village a moved plaza belongs to and the places it is refused), the editor's
## move_plaza (one history group, the paving following, a peer ending level, a move between
## villages) and the brush's gesture (VillageBrush on a BrushTool).

const POND_BED := -1.25
const POND_LEVEL := -0.25

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


func _row(editor: AuthoringEditor, z: float, seed_value: int = 5) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, z),
		Vector3(12, 0, z),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": 3}
	)


func _paint_state(doc: MapDocument) -> String:
	var weights := doc.surface_weights
	return "%s|%d|%d" % [",".join(doc.surface_ids), weights.size(), hash(weights)]


func _weight_at(doc: MapDocument, p: Vector2, surface: String) -> int:
	var s := doc.world_to_sample(p).round()
	return doc.surface_weight(doc.sample_index(int(s.x), int(s.y)), doc.surface_ids.find(surface))


func _carve_pond(centre: Vector2, radius: float) -> void:
	var heights := _doc.heights.duplicate()
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if _doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				heights[_doc.sample_index(x, z)] = POND_BED
				mask[_doc.sample_index(x, z)] = 2
	_doc.heights = heights
	_doc.pond_mask = mask
	_doc.water_bodies.append(WaterBody.pond(2, WaterBody.Depth.DEEP, POND_LEVEL))


func _verdict(id: int, index: int, at: Vector2) -> Dictionary:
	return VillagePlazas.move_problem(
		_doc, id, index, at, SettlementGround.world_of(_doc), VillageFieldGround.footprints(_doc)
	)


# --- the pure rules --------------------------------------------------------------------------


func test_the_rim_band_and_the_handle_dots_win_over_the_inside_and_the_inside_is_a_move() -> void:
	var village := Settlement.make(1, "market_town", 1, 5)
	village.plazas = [{"at": Vector2(0, 0), "radius": 4.0}]
	var all: Array[Settlement] = [village]
	assert_eq(VillagePlazas.pick(all, Vector2(1, 0), 0.9)["part"], VillagePlazas.PART_INSIDE)
	var band := VillagePlazas.pick(all, Vector2(3.2, 0), 0.9)
	assert_eq(band["part"], VillagePlazas.PART_RIM, "in the band")
	assert_eq(VillagePlazas.pick(all, Vector2(2.9, 0), 0.9)["part"], VillagePlazas.PART_INSIDE)
	var dot := VillagePlazas.handle_points(Vector2.ZERO, 4.0)[0]
	var inward := dot - dot.normalized() * 1.3
	assert_eq(VillagePlazas.pick(all, inward, 0.9)["part"], VillagePlazas.PART_INSIDE, "no dot reach")
	var reach := VillagePlazas.pick(all, inward, 0.9, 1.5)
	assert_eq(reach["part"], VillagePlazas.PART_RIM, "within a dot's reach it sizes")


func test_a_press_is_a_move_only_past_the_click_threshold() -> void:
	var pressed := Vector2(2, 3)
	assert_false(VillagePlazas.is_move(pressed, pressed))
	assert_false(VillagePlazas.is_move(pressed, pressed + Vector2(1.4, 0)))
	assert_true(VillagePlazas.is_move(pressed, pressed + Vector2(0, 1.5)))


func test_the_plaza_keeps_its_place_under_the_pointer_without_jumping() -> void:
	var centre := Vector2(10, 4)
	var grabbed := Vector2(11.3, 3.1)
	var offset := VillagePlazas.grab_offset(centre, grabbed)
	assert_eq(VillagePlazas.moved_to(grabbed, offset), centre, "no jump at the grab")
	var then := VillagePlazas.moved_to(grabbed + Vector2(5.0, -2.0), offset)
	assert_eq(then, Vector2(15, 2), "it moves by what the pointer moved")
	assert_eq(VillagePlazas.moved_to(Vector2(0.04, 0.26), Vector2.ZERO), Vector2(0.0, 0.3), "a tenth")


func test_a_moved_plaza_belongs_to_the_nearest_village_measured_without_itself() -> void:
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var editor := _editor()
	var a := editor.settlements.dress(_row(editor, -32.0), "farming_hamlet")
	var b := editor.settlements.dress(_row(editor, 32.0, 6), "market_town")
	assert_true(editor.settlements.add_plaza(a, Vector2(0, -22), 4.0))
	assert_eq(VillagePlazas.destination_village(_doc, a, 0, Vector2(0, -18)), a, "its own")
	assert_eq(VillagePlazas.destination_village(_doc, a, 0, Vector2(0, 22)), b, "the nearer village")
	assert_eq(VillagePlazas.destination_village(_doc, a, 0, Vector2(0, 1)), a, "a few metres nearer")
	assert_eq(VillagePlazas.destination_village(_doc, a, 0, Vector2(0, 150)), -1, "out of reach")
	# Its old place does not count: the plaza at the street's far end does not hold it there.
	assert_eq(VillagePlazas.destination_village(_doc, a, 0, Vector2(0, 10)), b)


func test_a_place_is_refused_for_water_steep_ground_a_building_and_distance() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_row(editor, 0.0), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	assert_eq(_verdict(id, 0, Vector2(7, 10))["reason"], &"", "open ground")
	assert_eq(_verdict(id, 0, Vector2(7, 10))["village"], id)
	var plans := VillageFieldGround.footprints(_doc)
	assert_false(plans.is_empty())
	var house := Vector2.ZERO
	for corner in plans[0]:
		house += corner / plans[0].size()
	assert_eq(_verdict(id, 0, house)["reason"], SettlementEditor.REFUSED_BUILDING)
	assert_eq(_verdict(id, 0, Vector2(0, 150))["reason"], SettlementEditor.REFUSED_REACH)
	assert_eq(_verdict(id, 5, Vector2(7, 10))["reason"], SettlementEditor.REFUSED_STREET, "no plaza")
	_carve_pond(Vector2(7, 10), 4.0)
	assert_eq(_verdict(id, 0, Vector2(7, 10))["reason"], SettlementEditor.REFUSED_WATER)
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			heights[_doc.sample_index(x, z)] = p.x * 1.2 if p.x > 0.0 else 0.0
	_doc.heights = heights
	_doc.pond_mask = PackedByteArray()
	_doc.pond_mask.resize(_doc.sample_count())
	_doc.water_bodies.clear()
	assert_eq(_verdict(id, 0, Vector2(4, 10))["reason"], SettlementEditor.REFUSED_STEEP)


# --- the editor ---------------------------------------------------------------------------------


func test_moving_a_plaza_takes_the_old_paving_back_and_lays_the_new_in_one_entry() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_row(editor, 0.0), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	var before := _paint_state(_doc)
	var strokes := _doc.settlement(id).ground.size()
	var entries := _history.undo_count()
	assert_true(editor.settlements.move_plaza(id, 0, Vector2(7.04, 10)))
	assert_eq(_history.undo_count(), entries + 1, "the paving and the record are one entry")
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(7.04, 10), "to a hundredth")
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 3.0)
	assert_eq(_doc.settlement(id).ground.size(), strokes, "the old stroke was replaced, not added to")
	assert_eq(_weight_at(_doc, Vector2(-7, 10), "cobblestone"), 0, "bare where it was")
	assert_gt(_weight_at(_doc, Vector2(7, 10), "cobblestone"), 200, "paved where it is")
	var moved := _paint_state(_doc)
	_history.undo()
	assert_eq(_paint_state(_doc), before, "undo restores both places")
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10))
	_history.redo()
	assert_eq(_paint_state(_doc), moved)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(7.04, 10))


func test_a_move_that_changes_nothing_or_is_refused_records_nothing() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_row(editor, 0.0), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	var entries := _history.undo_count()
	var state := _paint_state(_doc)
	assert_false(editor.settlements.move_plaza(id, 0, Vector2(-7, 10)), "where it stands")
	assert_false(editor.settlements.move_plaza(id, 0, Vector2(0, 150)), "out of reach")
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_REACH)
	assert_false(editor.settlements.move_plaza(id, 4, Vector2(7, 10)), "no such plaza")
	assert_false(editor.settlements.move_plaza(99, 0, Vector2(7, 10)), "no such village")
	assert_eq(_history.undo_count(), entries)
	assert_eq(_paint_state(_doc), state)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10))


func test_a_plaza_dropped_nearer_another_village_joins_it_in_one_entry() -> void:
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var editor := _editor()
	var a := editor.settlements.dress(_row(editor, -32.0), "farming_hamlet")
	var b := editor.settlements.dress(_row(editor, 32.0, 6), "market_town")
	assert_true(editor.settlements.add_plaza(a, Vector2(0, -22), 4.0))
	var before := _paint_state(_doc)
	var entries := _history.undo_count()
	assert_true(editor.settlements.move_plaza(a, 0, Vector2(30, 24)))
	assert_eq(_history.undo_count(), entries + 1, "a removal and an addition, one group")
	assert_eq(_doc.settlement(a).plazas.size(), 0)
	assert_eq(_doc.settlement(b).plazas.size(), 1)
	assert_eq(_doc.settlement(b).plazas[0]["at"], Vector2(30, 24))
	assert_ne(_paint_state(_doc), before)
	_history.undo()
	assert_eq(_paint_state(_doc), before)
	assert_eq(_doc.settlement(a).plazas.size(), 1)
	assert_eq(_doc.settlement(b).plazas.size(), 0)


func test_a_move_into_a_full_village_is_refused_and_leaves_the_map_alone() -> void:
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var editor := _editor()
	var a := editor.settlements.dress(_row(editor, -32.0), "farming_hamlet")
	var b := editor.settlements.dress(_row(editor, 32.0, 6), "market_town")
	assert_true(editor.settlements.add_plaza(a, Vector2(0, -22), 4.0))
	for k in Settlement.MAX_PLAZAS:
		assert_true(editor.settlements.add_plaza(b, Vector2(-15.0 + 10.0 * k, 22), 3.0))
	var entries := _history.undo_count()
	assert_false(editor.settlements.move_plaza(a, 0, Vector2(0, 22)))
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_FULL)
	assert_eq(_history.undo_count(), entries)
	assert_eq(_doc.settlement(a).plazas.size(), 1)


func test_a_peer_ends_level_through_a_move_in_a_village_and_between_villages() -> void:
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var host := _editor()
	var peer_doc := MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	var first := _row(host, -32.0)
	var second := _row(host, 32.0, 6)
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var a := host.settlements.dress(first, "farming_hamlet")
	var b := host.settlements.dress(second, "market_town")
	assert_true(host.settlements.add_plaza(a, Vector2(0, -22), 4.0))
	assert_true(host.settlements.move_plaza(a, 0, Vector2(30, -24)))
	assert_true(host.settlements.move_plaza(a, 0, Vector2(30, 24)))
	assert_eq(entries.size(), 5, "two dresses, an addition and two moves are one entry each")
	for entry in entries:
		_send(entry, host, peer_doc, peer, false)
	assert_eq(_paint_state(peer_doc), _paint_state(_doc), "the same ground byte for byte")
	assert_eq(peer_doc.settlement(b).plazas[0]["at"], Vector2(30, 24))
	assert_eq(peer_doc.settlement(a).plazas.size(), 0)
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


# --- the brush ------------------------------------------------------------------------------------


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func _frame(mode: VillageBrush, tool: BrushTool, at: Vector3) -> void:
	tool.hit = at
	mode.frame(tool)


func _plaza_scene() -> Dictionary:
	var editor := _editor()
	var id := editor.settlements.dress(_row(editor, 0.0), "market_town")
	assert_true(editor.settlements.add_plaza(id, Vector2(-7, 10), 3.0))
	return {"editor": editor, "id": id, "mode": VillageBrush.new()}


func test_a_press_inside_a_plaza_dragged_past_a_click_moves_it_at_the_release() -> void:
	var scene := _plaza_scene()
	var id: int = scene["id"]
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	var entries := _history.undo_count()
	_frame(mode, tool, Vector3(-6, 0, 10))
	assert_eq(mode.hover_part, VillagePlazas.PART_INSIDE)
	mode.press(tool)
	assert_eq(mode.gesture, VillageBrush.GESTURE_PICK)
	_frame(mode, tool, Vector3(-4.8, 0, 10))
	assert_eq(mode.gesture, VillageBrush.GESTURE_PICK, "under the threshold it is still a click")
	_frame(mode, tool, Vector3(8, 0, 10))
	assert_eq(mode.gesture, VillageBrush.GESTURE_MOVE)
	assert_eq(mode.move_destination(), Vector2(7, 10), "the disc kept its place under the pointer")
	assert_eq(mode.move_reason(), &"")
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10), "nothing is repaved mid-drag")
	assert_eq(_history.undo_count(), entries)
	mode.end(tool)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(7, 10))
	assert_eq(_history.undo_count(), entries + 1, "one entry for the whole drag")
	assert_eq(mode.selected_plaza, 0, "still the picked plaza")
	assert_eq(mode.gesture, &"")


func test_a_press_inside_released_under_the_threshold_only_picks() -> void:
	var scene := _plaza_scene()
	var id: int = scene["id"]
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	var entries := _history.undo_count()
	_frame(mode, tool, Vector3(-6, 0, 10))
	mode.press(tool)
	_frame(mode, tool, Vector3(-4.8, 0, 10))
	mode.end(tool)
	assert_eq(mode.selected_plaza, 0)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10))
	assert_eq(_history.undo_count(), entries)


func test_a_rim_press_still_sizes_and_never_moves() -> void:
	var scene := _plaza_scene()
	var id: int = scene["id"]
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	_frame(mode, tool, Vector3(-4, 0, 10))
	mode.press(tool)
	assert_eq(mode.gesture, VillageBrush.GESTURE_RESIZE)
	_frame(mode, tool, Vector3(-1, 0, 10))
	assert_eq(mode.gesture, VillageBrush.GESTURE_RESIZE)
	mode.end(tool)
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10), "the centre stayed")
	assert_eq(_doc.settlement(id).plazas[0]["radius"], 6.0)


func test_dropping_a_plaza_on_water_is_refused_and_it_stays() -> void:
	var scene := _plaza_scene()
	var id: int = scene["id"]
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	_carve_pond(Vector2(7, 10), 4.0)
	var entries := _history.undo_count()
	watch_signals(tool)
	_frame(mode, tool, Vector3(-6, 0, 10))
	mode.press(tool)
	_frame(mode, tool, Vector3(8, 0, 10))
	assert_eq(mode.gesture, VillageBrush.GESTURE_MOVE)
	assert_eq(mode.move_reason(), SettlementEditor.REFUSED_WATER)
	assert_eq(VillageBrush.short_reason(mode.move_reason()), VillageBrush.WATER_SHORT)
	mode.end(tool)
	assert_signal_emitted_with_parameters(tool, "refused", [VillageBrush.WATER])
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10), "the plaza returns")
	assert_eq(_history.undo_count(), entries)
	assert_eq(mode.selected_plaza, 0)


func test_carrying_a_plaza_back_to_where_it_started_refuses_nothing() -> void:
	var scene := _plaza_scene()
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	_frame(mode, tool, Vector3(-6, 0, 10))
	mode.press(tool)
	_frame(mode, tool, Vector3(0, 0, 10))
	_frame(mode, tool, Vector3(-6, 0, 10))
	assert_eq(mode.gesture, VillageBrush.GESTURE_MOVE, "a move once begun stays one")
	assert_eq(mode.move_destination(), Vector2(-7, 10))
	assert_eq(mode.move_reason(), &"")


func test_escape_drops_a_held_move() -> void:
	var scene := _plaza_scene()
	var id: int = scene["id"]
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	var entries := _history.undo_count()
	_frame(mode, tool, Vector3(-6, 0, 10))
	mode.press(tool)
	_frame(mode, tool, Vector3(0, 0, 10))
	mode.cancel(tool)
	assert_eq(mode.gesture, &"")
	assert_eq(_doc.settlement(id).plazas[0]["at"], Vector2(-7, 10))
	assert_eq(_history.undo_count(), entries)
	assert_eq(mode.move_destination(), mode.centre())


func test_the_hover_pill_says_a_press_inside_drags_it_and_the_rim_still_sizes() -> void:
	var scene := _plaza_scene()
	var mode: VillageBrush = scene["mode"]
	var tool := _tool(scene["editor"])
	_frame(mode, tool, Vector3(-6, 0, 10))
	assert_eq(VillageRings.hover_text(_doc, mode), VillageBrush.HOVER_INSIDE)
	assert_true(VillageBrush.HOVER_INSIDE.contains("move"))
	mode.select(scene["id"], 0)
	assert_eq(VillageRings.hover_text(_doc, mode), VillageBrush.HOVER_PICKED)
	assert_true(VillageBrush.HOVER_PICKED.contains("move"))
	_frame(mode, tool, Vector3(-4, 0, 10))
	assert_eq(VillageRings.hover_text(_doc, mode), VillageBrush.HOVER_RIM)
