extends GutTest

## CrossingEditor (P4b-1), the API the Bridge tool (P4b-2) calls: plan (the live preview,
## changing nothing), place / add, replace, remove, crossing_at, each one history entry that
## undoes and redoes exactly, refreshing the map's AuthoredCrossings and the scatter.

const RIVER_LEVEL := -0.2
const BED := -1.0

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


func _node() -> AuthoredCrossings:
	return _map.get_node(AuthoredCrossings.NODE_NAME) as AuthoredCrossings


func test_plan_previews_without_changing_anything() -> void:
	var editor := _editor()
	var plan := editor.crossings.plan(Crossing.Kind.PLANK, Vector3(0, 0, -0.5), Vector3(0, 0, 0.5))
	assert_not_null(plan)
	assert_eq(editor.crossings.last_refusal, &"")
	assert_lt(plan.start.y, -1.5)
	assert_gt(plan.end.y, 1.5)
	assert_true(_doc.crossings.is_empty(), "nothing added")
	assert_false(_history.can_undo())
	var none := editor.crossings.plan(Crossing.Kind.PLANK, Vector3(0, 0, 5), Vector3(0, 0, 7))
	assert_null(none)
	assert_eq(editor.crossings.last_refusal, CrossingPlacement.REFUSED_NO_WATER)


func test_place_undo_redo() -> void:
	var editor := _editor()
	var first := editor.crossings.place(Crossing.Kind.PLANK, Vector3(0, 0, -1), Vector3(0, 0, 1))
	var second := editor.crossings.place(Crossing.Kind.STONES, Vector3(5, 0, -1), Vector3(5, 0, 1))
	assert_eq([first, second], [1, 2])
	assert_eq(_doc.crossings.size(), 2)
	assert_not_null(_node().get_crossing_node(1))
	assert_not_null(_node().get_crossing_node(2))
	assert_true(_node().has_decks())
	assert_eq(editor.crossings.list().size(), 2)
	assert_eq(editor.crossings.get_crossing(2).kind, Crossing.Kind.STONES)
	assert_eq(_history.undo(), "Place stepping stones")
	assert_eq(_doc.crossings.size(), 1)
	assert_null(_node().get_crossing_node(2), "the node follows the undo")
	assert_eq(_history.undo(), "Place bridge")
	assert_true(_doc.crossings.is_empty())
	assert_false(_node().has_decks())
	_history.redo()
	_history.redo()
	assert_eq(_doc.crossings.size(), 2)
	assert_not_null(_node().get_crossing_node(2))


func test_remove_and_crossing_at() -> void:
	var editor := _editor()
	var id := editor.crossings.place(Crossing.Kind.PLANK, Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_eq(editor.crossings.crossing_at(Vector3(0.2, 0, 0)), id, "on the deck")
	assert_eq(editor.crossings.crossing_at(Vector3(0, 0, 2.3)), id, "at its bank end")
	assert_eq(editor.crossings.crossing_at(Vector3(4, 0, 0)), -1, "beside it")
	assert_true(editor.crossings.remove(id))
	assert_false(editor.crossings.remove(id), "already gone")
	assert_true(_doc.crossings.is_empty())
	assert_null(_node().get_crossing_node(id))
	_history.undo()
	assert_eq(_doc.crossings.size(), 1)
	assert_eq(_doc.crossings[0].id, id, "the id comes back with it")


func test_replace_keeps_the_id() -> void:
	var editor := _editor()
	var id := editor.crossings.place(Crossing.Kind.PLANK, Vector3(0, 0, -1), Vector3(0, 0, 1))
	var moved := editor.crossings.get_crossing(id)
	var before := moved.copy()
	moved.width_m = 2.0
	moved.id = 77
	assert_true(editor.crossings.replace(id, moved))
	assert_eq(_doc.crossing(id).width_m, 2.0)
	assert_null(_doc.crossing(77))
	_history.undo()
	assert_true(_doc.crossing(id).same_as(before))
	moved.width_m = 50.0
	assert_false(editor.crossings.replace(id, moved), "invalid")
	assert_eq(editor.crossings.last_refusal, CrossingEditor.REFUSED_INVALID)
	assert_false(editor.crossings.replace(99, moved), "no such crossing")


func test_add_refuses_what_the_writer_would() -> void:
	var editor := _editor()
	var bad := Crossing.make(
		0, Crossing.Kind.PLANK, Vector2(0, -2), Vector2(0, 2), Vector3.ZERO, 9.0
	)
	assert_eq(editor.crossings.add(bad), -1)
	assert_eq(editor.crossings.last_refusal, CrossingEditor.REFUSED_INVALID)
	assert_true(_doc.crossings.is_empty())
	var good := Crossing.make(
		40, Crossing.Kind.PLANK, Vector2(0, -2), Vector2(0, 2), Vector3(0.2, 0.5, 0.2), 1.5
	)
	assert_eq(editor.crossings.add(good), 1, "a free id replaces the given one")
	while _doc.next_crossing_id() > 0:
		var extra := good.copy()
		extra.id = _doc.next_crossing_id()
		_doc.crossings.append(extra)
	assert_eq(editor.crossings.add(good), -1)
	assert_eq(editor.crossings.last_refusal, CrossingEditor.REFUSED_FULL)
	assert_null(editor.crossings.plan(Crossing.Kind.PLANK, Vector3(0, 0, -1), Vector3(0, 0, 1)))
	assert_eq(editor.crossings.last_refusal, CrossingEditor.REFUSED_FULL)


func test_a_river_deepened_under_a_ford_removes_it_and_undo_restores_it() -> void:
	# P4d-2: a ford across the waist river, then a deep tributary carved into the river right
	# there. The tributary takes the river's level where it joins and its channel is cut two
	# metres under it, so the water under the ford's wet run is deep now: the ford, snapped
	# again from its own anchors, is refused deep and goes in the carve's entry (the follow
	# rule); undo brings the ground, the water and the ford back together.
	var editor := _editor()
	var id := editor.crossings.place(Crossing.Kind.FORD, Vector3(0.3, 0, -1), Vector3(0, 0, 1))
	assert_gt(id, 0, "a ford over the waist river")
	var before := _doc.crossing(id).copy()
	assert_almost_eq(before.levels.y, RIVER_LEVEL - CrossingPlacement.FORD_DEPTH_M, 0.0001)
	var entries := _history.undo_count()
	watch_signals(editor.crossings)
	var carved := editor.water.carve_river(
		PackedVector2Array([Vector2(0, -9), Vector2(0, 0)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.DEEP
	)
	editor.finish_height_work()
	assert_gt(carved, 0, "the deep tributary is carved")
	assert_null(_doc.crossing(id), "the water under the ford is deep")
	assert_signal_emitted_with_parameters(editor.crossings, "followed", [0, 1])
	var again := CrossingPlacement.place(
		_doc, before.start, before.end, before.kind, before.width_m, before.style
	)
	assert_eq(again.refusal, CrossingPlacement.REFUSED_DEEP, "for that reason")
	assert_eq(_history.undo_count(), entries + 1, "one entry: the carve")
	assert_eq(_history.undo(), "Carve river")
	editor.finish_height_work()
	assert_true(_doc.crossing(id).same_as(before), "undo brings the ford back")
	assert_not_null(_node().get_crossing_node(id))
	assert_not_null(_node().get_crossing_node(id).get_node_or_null("Ford"))


func test_the_document_saves_what_was_placed() -> void:
	var editor := _editor()
	editor.crossings.place(Crossing.Kind.STONES, Vector3(0, 0, -1), Vector3(0, 0, 1))
	var packed := MapDocumentIO.serialize(_doc)
	assert_eq(packed["error"], "")
	var read: MapDocument = MapDocumentIO.parse(packed["entries"])["document"]
	assert_true(read.crossings[0].same_as(_doc.crossings[0]))
