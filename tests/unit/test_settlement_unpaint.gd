extends GutTest

## Taking back a Dress's ground (villages3, docs/systems/settlements.md "Ground"): the record keeps
## the strokes it laid (SettlementGroundIO: round trip, hostile input), Clear removes exactly that
## paint, a re-dress takes it back and lays the new plan in one entry, ground painted by hand is
## left alone, and a live-edit peer ends byte for byte the same, undo included.

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


func _street(editor: AuthoringEditor, from_z: float = 0.0) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, from_z),
		Vector3(12, 0, from_z),
		-1.0,
		{"seed": 5, "side": 2, "preset": 3}
	)


func _paint_state(doc: MapDocument) -> String:
	var weights := doc.surface_weights
	return "%s|%d|%d" % [",".join(doc.surface_ids), weights.size(), hash(weights)]


func _hand_paint(surface: String, at: Vector2, radius: float) -> void:
	var stroke := SurfaceStroke.begin(_doc, surface, false)
	stroke.dab(at, at, radius, 3.0)
	assert_false(stroke.finish().is_empty(), "%s painted by hand" % surface)


func _weight_at(p: Vector2, surface: String) -> int:
	var s := _doc.world_to_sample(p).round()
	return _doc.surface_weight(_doc.sample_index(int(s.x), int(s.y)), _doc.surface_ids.find(surface))


## How many samples farther than `corridor` metres from the street line (z = 0) differ between the
## weights now and `then`.
func _differing_outside(then: PackedByteArray, corridor: float) -> int:
	var count := _doc.sample_count()
	var plane := count * MapDocument.SURFACE_CHANNELS
	var differing := 0
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if absf(_doc.sample_to_world(Vector2(x, z)).y) <= corridor:
				continue
			var at := _doc.sample_index(x, z) * MapDocument.SURFACE_CHANNELS
			for k in MapDocument.SURFACE_CHANNELS:
				if (
					then[at + k] != _doc.surface_weights[at + k]
					or then[plane + at + k] != _doc.surface_weights[plane + at + k]
				):
					differing += 1
					break
	return differing


func _send(
	entry: Dictionary, host: AuthoringEditor, peer_doc: MapDocument, peer: AuthoringEditor, undo: bool
) -> void:
	for op in LiveEditCodec.ops_of(entry, host, undo):
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)


func _stroke(surface: String, a: Vector2, b: Vector2, radius: float, seconds: float) -> Dictionary:
	return {"surface": surface, "from": a, "to": b, "radius": radius, "seconds": seconds}


# --- the record ---------------------------------------------------------------------------------


func test_the_ground_list_round_trips_byte_for_byte_and_is_left_out_when_empty() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	record.ground = [
		_stroke("flagstone_sandstone", Vector2(-12, 0), Vector2(12.25, 0.5), 3.23, 1.2),
		_stroke("cobblestone", Vector2(1.25, -8.5), Vector2(1.25, -8.5), 4.48, 1.2),
		_stroke("flagstone_sandstone", Vector2(3, 3), Vector2(3.5, 1.5), 1.05, 1.2),
	]
	assert_eq(MapSettlementIO.settlement_problem(record), "")
	var json := MapSettlementIO.settlement_json(record)
	assert_eq((json["ground"]["surfaces"] as Array).size(), 2, "each surface is named once")
	assert_eq((json["ground"]["strokes"] as Array).size(), 3)
	var text := JSON.stringify([json], "", false, true)
	var log := MapDocumentIO._WarningLog.new()
	var read := MapSettlementIO.parse_list(JSON.parse_string(text), log)
	assert_eq(read.size(), 1, "read back")
	assert_eq(read[0].ground, record.ground)
	assert_eq(JSON.stringify([MapSettlementIO.settlement_json(read[0])], "", false, true), text)
	assert_eq(record.copy().ground, record.ground)
	var bare := Settlement.make(2, "market_town", 3, 5)
	assert_false(MapSettlementIO.settlement_json(bare).has("ground"), "none is left out")
	assert_ne(record.fingerprint(), bare.fingerprint(), "the ground changes the fingerprint")


func test_hostile_ground_skips_the_settlement_with_a_warning() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	record.ground = [_stroke("cobblestone", Vector2(0, 0), Vector2(1, 1), 2.0, 1.2)]
	var base := MapSettlementIO.settlement_json(record)
	var many: Array = []
	for k in SettlementGroundIO.MAX_STROKES + 1:
		many.append([0, 0, 0, 1, 1, 2.0, 1.2])
	var surfaces: Array = []
	for k in SettlementGroundIO.MAX_SURFACES + 1:
		surfaces.append("s%d" % k)
	var cases := {
		"too many strokes": {"surfaces": ["a"], "strokes": many},
		"one surface too many": {"surfaces": surfaces, "strokes": [[0, 0, 0, 1, 1, 2, 1]]},
		"unlisted surface": {"surfaces": ["a"], "strokes": [[1, 0, 0, 1, 1, 2, 1]]},
		"negative surface": {"surfaces": ["a"], "strokes": [[-1, 0, 0, 1, 1, 2, 1]]},
		"short row": {"surfaces": ["a"], "strokes": [[0, 0, 0, 1, 1, 2]]},
		"text number": {"surfaces": ["a"], "strokes": [[0, "x", 0, 1, 1, 2, 1]]},
		"huge radius": {"surfaces": ["a"], "strokes": [[0, 0, 0, 1, 1, 99, 1]]},
		"no radius": {"surfaces": ["a"], "strokes": [[0, 0, 0, 1, 1, 0, 1]]},
		"no exposure": {"surfaces": ["a"], "strokes": [[0, 0, 0, 1, 1, 2, 0]]},
		"far away": {"surfaces": ["a"], "strokes": [[0, 1.0e9, 0, 1, 1, 2, 1]]},
		"surface not text": {"surfaces": [7], "strokes": [[0, 0, 0, 1, 1, 2, 1]]},
		"empty surface": {"surfaces": [""], "strokes": [[0, 0, 0, 1, 1, 2, 1]]},
		"not an object": [1, 2],
		"strokes not a list": {"surfaces": ["a"], "strokes": "x"},
	}
	for label: String in cases:
		var hostile := base.duplicate(true)
		hostile["ground"] = cases[label]
		var log := MapDocumentIO._WarningLog.new()
		assert_eq(MapSettlementIO.parse_list([hostile], log).size(), 0, label)
		assert_gt(log.items.size(), 0, "%s: a warning" % label)
	record.ground = [_stroke("cobblestone", Vector2(0, 0), Vector2(1, 1), 99.0, 1.2)]
	assert_ne(MapSettlementIO.settlement_problem(record), "", "the writer refuses too")


func test_strokes_far_off_the_map_take_nothing_and_break_nothing() -> void:
	var editor := _editor()
	var street := _street(editor)
	editor.settlements.dress(street, "farming_hamlet")
	var painted := _paint_state(_doc)
	var strokes: Array[Dictionary] = [
		_stroke("dirt_road_packed", Vector2(900, 900), Vector2(950, 900), 5.0, 1.2)
	]
	assert_eq(SettlementUnpaint.remove(_doc, strokes), {}, "nothing there to take")
	assert_eq(_paint_state(_doc), painted)


# --- Clear -------------------------------------------------------------------------------------


func test_the_record_remembers_the_strokes_dress_laid() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "market_town")
	var record := _doc.settlement(id)
	assert_gt(record.ground.size(), 4, "a road and the door paths")
	assert_eq(MapSettlementIO.settlement_problem(record), "")
	for stroke in record.ground:
		assert_eq(stroke["surface"], "flagstone_sandstone")
	_history.undo()
	assert_eq(_doc.settlements.size(), 0)
	_history.redo()
	assert_eq(_doc.settlement(id).ground, record.ground, "redo brings the list back with the paint")


func test_clear_takes_back_exactly_what_dress_laid_in_one_entry() -> void:
	var editor := _editor()
	var street := _street(editor)
	var before := _paint_state(_doc)
	var id := editor.settlements.dress(street, "farming_hamlet")
	# A plaza on the road's edge and the door paths: its paint lies over the others.
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 4), 4.0))
	assert_true(_doc.surface_ids.has("flagstone_sandstone"), "the plaza took a slot")
	var painted := _paint_state(_doc)
	var entries := _history.undo_count()
	assert_true(editor.settlements.clear(id))
	assert_eq(_history.undo_count(), entries + 1, "the paint and the record go in one entry")
	assert_eq(_doc.settlements.size(), 0)
	assert_eq(_paint_state(_doc), before, "the ground is as it was before the Dress, slots included")
	_history.undo()
	assert_eq(_paint_state(_doc), painted, "undo brings the paint back")
	assert_eq(_doc.settlements.size(), 1)
	assert_gt(_doc.settlement(id).ground.size(), 3)
	_history.redo()
	assert_eq(_paint_state(_doc), before, "redo takes it back again")


func test_clear_without_paint_still_clears_the_record() -> void:
	var editor := _editor()
	var street := _street(editor)
	editor.settlements.lays_ground = false
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_eq(_doc.settlement(id).ground.size(), 0, "nothing laid, nothing remembered")
	var entries := _history.undo_count()
	assert_true(editor.settlements.clear(id))
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(_doc.settlements.size(), 0)


func test_paint_by_hand_stays_through_clear() -> void:
	var editor := _editor()
	var street := _street(editor)
	_hand_paint("cobblestone", Vector2(0, 0), 2.0)
	_hand_paint("cobblestone", Vector2(-10, -11), 2.0)
	_hand_paint("dirt_road_packed", Vector2(10, 11), 2.0)
	var by_hand := _doc.surface_weights.duplicate()
	var ids := _doc.surface_ids.duplicate()
	var under_road := _weight_at(Vector2(0, 0), "cobblestone")
	assert_gt(under_road, 200, "painted by hand under the road's middle")
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_lt(_weight_at(Vector2(0, 0), "cobblestone"), under_road - 100, "the road took the room")
	assert_true(editor.settlements.clear(id))
	assert_eq(_doc.surface_ids, ids, "the same slots")
	assert_eq(_differing_outside(by_hand, 4.5), 0, "hand paint away from the road is untouched")
	assert_almost_eq(
		float(_weight_at(Vector2(0, 0), "cobblestone")),
		float(under_road),
		3.0,
		"under the road it gets its room back"
	)
	assert_eq(_weight_at(Vector2(0, 0), "dirt_road_packed"), 0, "and no road is left")
	assert_gt(_weight_at(Vector2(10, 11), "dirt_road_packed"), 200, "hand-painted road surface stays")


func test_a_redress_leaves_hand_paint_alone_and_lays_the_same_ground() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	_hand_paint("cobblestone", Vector2(-10, -11), 2.0)
	_hand_paint("dirt_road_packed", Vector2(10, 11), 2.0)
	var painted := _paint_state(_doc)
	var weights := _doc.surface_weights.duplicate()
	assert_true(editor.settlements.redress(id))
	assert_eq(_paint_state(_doc), painted, "the same ground, the hand paint included")
	assert_eq(_differing_outside(weights, 4.5), 0)


func test_a_redress_follows_the_street_where_it_stands_now() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_gt(_weight_at(Vector2(0, 0), "dirt_road_packed"), 200, "the road is on the first line")
	_doc.wall(street).points = PackedVector2Array([Vector2(-12, 7), Vector2(12, 7)])
	var entries := _history.undo_count()
	assert_true(editor.settlements.redress(id))
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(_weight_at(Vector2(0, 0), "dirt_road_packed"), 0, "the old road is taken back")
	assert_gt(_weight_at(Vector2(0, 7), "dirt_road_packed"), 200, "the new one is laid")
	var moved := _paint_state(_doc)
	_history.undo()
	assert_gt(_weight_at(Vector2(0, 0), "dirt_road_packed"), 200, "one undo restores the old road")
	assert_eq(_weight_at(Vector2(0, 7), "dirt_road_packed"), 0)
	_history.redo()
	assert_eq(_paint_state(_doc), moved)


func test_clearing_one_street_leaves_the_street_that_crosses_it_paved() -> void:
	var editor := _editor()
	var street := _street(editor)
	var other := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(0, 0, -13),
		Vector3(0, 0, 13),
		-1.0,
		{"seed": 8, "side": 2, "preset": 3}
	)
	var first := editor.settlements.dress(street, "farming_hamlet")
	var second := editor.settlements.dress(other, "farming_hamlet")
	assert_gt(first, 0)
	assert_gt(second, 0)
	assert_true(editor.settlements.clear(first))
	assert_gt(
		_weight_at(Vector2(0, -9), "dirt_road_packed"),
		150,
		"the street that crosses it is still paved away from the crossing"
	)
	assert_eq(_weight_at(Vector2(-9, 0), "dirt_road_packed"), 0, "the cleared street is bare")


# --- a live-edit peer ----------------------------------------------------------------------------


func test_a_peer_ends_with_the_same_ground_through_dress_redress_clear_and_their_undos() -> void:
	var host := _editor()
	var street := _street(host)
	_hand_paint("cobblestone", Vector2(0, 0), 2.0)
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	peer_doc.walls = _doc.walls.duplicate()
	peer_doc.surface_ids = _doc.surface_ids.duplicate()
	peer_doc.surface_weights = _doc.surface_weights.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "farming_hamlet")
	assert_true(host.settlements.add_plaza(id, Vector2(0, 4), 4.0))
	_doc.wall(street).points = PackedVector2Array([Vector2(-12, 6), Vector2(12, 6)])
	peer_doc.walls = _doc.walls.duplicate()
	assert_true(host.settlements.redress(id))
	assert_true(host.settlements.clear(id))
	assert_eq(entries.size(), 4, "dress, plaza, re-dress and Clear are one entry each")
	for entry in entries:
		_send(entry, host, peer_doc, peer, false)
	assert_eq(_paint_state(peer_doc), _paint_state(_doc), "the same ground byte for byte")
	assert_eq(peer_doc.settlements.size(), 0)
	for k in range(entries.size() - 1, -1, -1):
		_history.undo()
		_send(entries[k], host, peer_doc, peer, true)
		assert_eq(_paint_state(peer_doc), _paint_state(_doc), "undo %d keeps the peer level" % k)
		assert_eq(peer_doc.settlements.size(), _doc.settlements.size())
	assert_eq(peer_doc.settlements.size(), 0)
	assert_eq(peer_doc.surface_ids, PackedStringArray(["cobblestone"]), "only the hand paint is left")
