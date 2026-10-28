extends GutTest

## Structures in the map document (Structure, MapStructureIO, StructureEditor, the live
## "structures" edit, the MapFingerprint key): the record and its JSON form, a saved map keeping
## its structures byte for byte, the reader and writer refusing hostile input, the editor's
## history, the edit a peer applies, and the fingerprint moving with edits.
## Summary: docs/systems/structures.md.

const SAVE_PATH := "user://test_map_document_structures.ttmap"
const SAVE_PATH_2 := "user://test_map_document_structures_2.ttmap"

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func after_each() -> void:
	for path in [SAVE_PATH, SAVE_PATH_2]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _plan() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])


func _structure(structure_id: int = 1) -> Structure:
	return Structure.make(
		structure_id, "core:cottage", _plan(), 482113907, {"height": 2.6, "floors": 2.0}, ""
	)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	return AuthoringEditor.create(_doc, _map, _history)


func _parse(list: Array) -> Dictionary:
	var warn_log := MapDocumentIO._WarningLog.new()
	var out := MapStructureIO.parse_list(list, _doc.extent_m(), warn_log)
	return {"list": out, "warnings": warn_log.items}


func _entry_bytes(doc: MapDocument) -> PackedByteArray:
	var entries := {}
	MapStructureIO.serialize(doc, entries)
	return entries.get(MapStructureIO.ENTRY, PackedByteArray())


# --- the record ---------------------------------------------------------------------------


func test_a_structure_round_trips_through_json() -> void:
	var structure := _structure()
	structure.style = "temperate_forest"
	structure.params["textured"] = true
	var parsed := _parse([MapStructureIO.structure_json(structure)])
	assert_eq(parsed.warnings.size(), 0)
	assert_eq(parsed.list.size(), 1)
	assert_true(structure.same_as(parsed.list[0]), "every field comes back")


func test_copy_is_independent_and_ids_are_free_ones() -> void:
	var structure := _structure()
	var copied := structure.copy()
	copied.footprint[0] = Vector2(9, 9)
	copied.params["height"] = 3.0
	assert_eq(structure.footprint[0], Vector2(-3, -2))
	assert_eq(structure.params["height"], 2.6)
	assert_eq(_doc.next_structure_id(), 1)
	_doc.structures.append(structure)
	assert_eq(_doc.next_structure_id(), 2)
	assert_eq(_doc.structure(1), structure)
	assert_null(_doc.structure(2))
	for k in MapDocument.MAX_STRUCTURES - 1:
		var more := _structure(k + 2)
		_doc.structures.append(more)
	assert_eq(_doc.next_structure_id(), -1, "full")


func test_a_saved_map_keeps_its_structures() -> void:
	_doc.structures.append(_structure(1))
	var second := _structure(2)
	second.recipe = "mylib:town_house"
	second.footprint = PackedVector2Array([Vector2(4, 4), Vector2(8, 4.5), Vector2(8, 8)])
	second.params = {}
	second.style = "desert"
	_doc.structures.append(second)
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(read.structures.size(), 2)
	assert_true(read.structures[0].same_as(_doc.structures[0]))
	assert_true(read.structures[1].same_as(_doc.structures[1]))
	assert_eq(read.structure(2).recipe, "mylib:town_house")


func test_a_map_without_structures_writes_no_entry() -> void:
	assert_eq(_entry_bytes(_doc).size(), 0)


# --- byte-identical re-save ---------------------------------------------------------------


func test_a_resave_is_byte_identical() -> void:
	_doc.structures.append(_structure(1))
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(_entry_bytes(read), _entry_bytes(_doc), "the entry's bytes survive a save and a load")
	assert_eq(MapDocumentIO.write(read, SAVE_PATH_2), OK)
	var reread: MapDocument = MapDocumentIO.read(SAVE_PATH_2)["document"]
	assert_eq(_entry_bytes(reread), _entry_bytes(_doc))


func test_random_footprints_and_params_keep_their_bytes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for k in 40:
		var count := rng.randi_range(Structure.MIN_POINTS, Structure.MAX_POINTS)
		var plan := PackedVector2Array()
		# A star shaped plan around a random centre, redrawn until the shared plan rules
		# (ProcgenPlan) accept it. Both unsnapped and 1 cm snapped values: float32 must come
		# back bit for bit.
		for attempt in 500:
			plan = PackedVector2Array()
			var centre := Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			for i in count:
				var turn := TAU * (i + rng.randf_range(-0.2, 0.2)) / count
				var raw := centre + Vector2.from_angle(turn) * rng.randf_range(5.0, 9.0)
				plan.append(raw if k % 2 == 0 else raw.snappedf(Structure.FOOTPRINT_STEP_M))
			if ProcgenPlan.is_valid(plan):
				break
		assert_true(ProcgenPlan.is_valid(plan), "a valid plan of %d points was drawn" % count)
		var structure := Structure.make(
			k % Structure.MAX_ID + 1,
			"core:cottage",
			plan,
			rng.randi_range(0, Structure.MAX_SEED),
			{
				"height": Structure.round_param(rng.randf_range(0.0, 9.0)),
				"pitch": Structure.round_param(rng.randf_range(-3.0, 3.0))
			},
			""
		)
		var text := JSON.stringify(MapStructureIO.structure_json(structure), "", true)
		var parsed := _parse([JSON.parse_string(text)])
		assert_eq(parsed.list.size(), 1, "structure %d reads back" % k)
		if parsed.list.is_empty():
			continue
		var back: Structure = parsed.list[0]
		assert_eq(back.footprint, structure.footprint, "float32 points are bit identical")
		assert_eq(back.params, structure.params, "rounded params are identical")
		assert_eq(
			JSON.stringify(MapStructureIO.structure_json(back), "", true), text, "same text again"
		)


func test_params_are_rounded_on_write_and_read() -> void:
	var structure := _structure()
	structure.params = {"height": 2.5999999, "floors": 2}
	var json := MapStructureIO.structure_json(structure)
	assert_eq(json["params"]["height"], 2.6)
	assert_eq(json["params"]["floors"], 2.0)
	json["params"]["height"] = 2.6049
	var parsed := _parse([json])
	assert_eq(parsed.list[0].params["height"], 2.6, "the reader rounds an unrounded value")


# --- hostile input ------------------------------------------------------------------------


func test_the_reader_drops_a_structure_that_breaks_a_rule() -> void:
	var good := MapStructureIO.structure_json(_structure(1))
	var cases: Array = []
	var make_case := func(key: String, value: Variant) -> Dictionary:
		var json := MapStructureIO.structure_json(_structure(2))
		json[key] = value
		return json
	cases.append(make_case.call("id", 0))
	cases.append(make_case.call("id", 256))
	cases.append(make_case.call("id", 1.5))
	cases.append(make_case.call("id", "seven"))
	cases.append(make_case.call("recipe", ""))
	cases.append(make_case.call("recipe", "cottage"))
	cases.append(make_case.call("recipe", ":cottage"))
	cases.append(make_case.call("recipe", "core:"))
	cases.append(make_case.call("recipe", "a:b:c"))
	cases.append(make_case.call("recipe", "Core:cottage"))
	cases.append(make_case.call("recipe", "core:Cottage"))
	cases.append(make_case.call("recipe", "core:cot__tage"))
	cases.append(make_case.call("recipe", "core:" + "a".repeat(200)))
	cases.append(make_case.call("recipe", 7))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [1.0, 0.0]]))
	cases.append(make_case.call("footprint", "square"))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [1.0, 0.0], [1.0]]))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [1.0, 0.0], ["a", "b"]]))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [1.0, 0.0], [900.0, 0.0]]))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [1.0, 0.0], [1e300, 0.0]]))
	cases.append(make_case.call("footprint", [[0.0, 0.0], [40.0, 0.0], [0.0, 40.0], [-40, 0]]))
	cases.append(make_case.call("seed", -1))
	cases.append(make_case.call("seed", Structure.MAX_SEED + 1))
	cases.append(make_case.call("seed", 1.5))
	cases.append(make_case.call("seed", null))
	cases.append(make_case.call("params", [1, 2]))
	cases.append(make_case.call("params", {"height": "tall"}))
	cases.append(make_case.call("params", {"height": null}))
	cases.append(make_case.call("params", {"Height": 1.0}))
	cases.append(make_case.call("params", {"a b": 1.0}))
	cases.append(make_case.call("params", {"height": 1e9}))
	cases.append(make_case.call("params", {"height": NAN}))
	cases.append(make_case.call("params", {"height": INF}))
	cases.append(make_case.call("params", {"n".repeat(40): 1.0}))
	cases.append(make_case.call("style", 3))
	cases.append(make_case.call("style", "x".repeat(300)))
	cases.append("nope")
	cases.append(null)
	var many := {}
	for k in Structure.MAX_PARAMS + 1:
		many["p%d" % k] = 1.0
	cases.append(make_case.call("params", many))
	var big_plan: Array = []
	for k in Structure.MAX_POINTS + 1:
		big_plan.append([float(k) * 0.1, float(k % 2)])
	cases.append(make_case.call("footprint", big_plan))
	var dup := MapStructureIO.structure_json(_structure(1))
	cases.append(dup)
	var input: Array = [good]
	input.append_array(cases)
	var parsed := _parse(input)
	assert_eq(parsed.list.size(), 1, "only the good structure survives")
	assert_eq(parsed.warnings.size(), cases.size(), "and each other one is said")


func test_nan_and_inf_points_are_refused_by_the_writer() -> void:
	for bad in [NAN, INF, -INF]:
		var structure := _structure()
		structure.footprint[1] = Vector2(bad, 0.0)
		assert_ne(MapStructureIO.structure_problem(structure, _doc.extent_m()), "", str(bad))


func test_the_writer_refuses_a_document_with_a_bad_structure() -> void:
	var structure := _structure()
	structure.seed_value = -4
	_doc.structures.append(structure)
	assert_ne(MapStructureIO.problem(_doc), "")
	assert_ne(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	assert_engine_error("not writing")


func test_the_writer_refuses_a_repeated_id_and_an_oversized_list() -> void:
	_doc.structures.append(_structure(1))
	_doc.structures.append(_structure(1))
	assert_string_contains(MapStructureIO.problem(_doc), "twice")
	_doc.structures.clear()
	for k in MapDocument.MAX_STRUCTURES + 1:
		_doc.structures.append(_structure(k % Structure.MAX_ID + 1))
	assert_string_contains(MapStructureIO.problem(_doc), "more than")


func test_the_reader_caps_a_huge_list_before_building_it() -> void:
	var list: Array = []
	for k in 100000:
		list.append(null)
	var parsed := _parse(list)
	assert_eq(parsed.list.size(), 0)
	assert_lte(parsed.warnings.size(), MapDocumentIO.MAX_WARNINGS + 1, "warnings are capped")
	var good: Array = []
	for k in MapDocument.MAX_STRUCTURES + 10:
		good.append(MapStructureIO.structure_json(_structure(k % Structure.MAX_ID + 1)))
	assert_eq(_parse(good).list.size(), MapDocument.MAX_STRUCTURES, "past the cap is ignored")


func test_a_footprint_of_a_million_points_is_refused_cheaply() -> void:
	var json := MapStructureIO.structure_json(_structure())
	var points: Array = []
	for k in 100000:
		points.append([0.0, 0.0])
	json["footprint"] = points
	var parsed := _parse([json])
	assert_eq(parsed.list.size(), 0)
	assert_eq(parsed.warnings.size(), 1)


func test_a_wrong_entry_shape_is_ignored_with_a_warning() -> void:
	for text in ['{"version": 2, "structures": []}', '{"version": 1, "structures": 4}', "[1]"]:
		var warn_log := MapDocumentIO._WarningLog.new()
		var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		MapStructureIO.parse({MapStructureIO.ENTRY: text.to_utf8_buffer()}, doc, warn_log)
		assert_eq(doc.structures.size(), 0, text)
		assert_eq(warn_log.items.size(), 1, text)


# --- the editor ---------------------------------------------------------------------------


func test_the_editor_adds_removes_and_undoes() -> void:
	var editor := _editor()
	var added := editor.structures.add(_structure(77))
	assert_eq(added, 1, "a new structure takes a free id")
	assert_eq(_doc.structures.size(), 1)
	var replaced := _structure(1)
	replaced.seed_value = 5
	assert_eq(editor.structures.add(replaced), 1, "an existing id is replaced")
	assert_eq(_doc.structures.size(), 1)
	assert_eq(_doc.structures[0].seed_value, 5)
	assert_eq(_history.undo(), "Change structure cottage")
	assert_eq(_doc.structures[0].seed_value, 482113907)
	assert_eq(_history.undo(), "Place structure cottage")
	assert_eq(_doc.structures.size(), 0)
	_history.redo()
	assert_eq(_doc.structures.size(), 1)
	assert_true(editor.structures.remove(1))
	assert_false(editor.structures.remove(1))
	assert_eq(_doc.structures.size(), 0)
	assert_eq(_history.undo(), "Remove structure cottage")
	assert_eq(editor.structures.list().size(), 1)
	assert_not_null(editor.structures.get_structure(1))


func test_the_editor_refuses_what_the_writer_would_refuse() -> void:
	var editor := _editor()
	var bad := _structure()
	bad.recipe = "nonsense"
	assert_eq(editor.structures.add(bad), -1)
	assert_eq(editor.structures.last_refusal, StructureEditor.REFUSED_INVALID)
	assert_eq(_doc.structures.size(), 0)
	assert_false(_history.can_undo(), "nothing recorded")
	for k in MapDocument.MAX_STRUCTURES:
		_doc.structures.append(_structure(k % Structure.MAX_ID + 1))
	var extra := _structure(200)
	assert_eq(editor.structures.add(extra), -1)
	assert_eq(editor.structures.last_refusal, StructureEditor.REFUSED_FULL)


# --- the peer's copy ----------------------------------------------------------------------


func _peer() -> AuthoringEditor:
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	return AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())


func test_a_live_edit_carries_a_structure_to_a_peer_and_its_undo() -> void:
	var host := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	host.structures.add(_structure())
	assert_eq(entries.size(), 1)
	var op := LiveEditCodec.op_of(entries[0], host)
	assert_eq(op.kind, "structures")
	var peer := _peer()
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer.document)
	assert_eq(decoded.problem, "")
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer.document.structures.size(), 1)
	assert_true(peer.document.structures[0].same_as(_doc.structures[0]))
	var undo_op := LiveEditCodec.op_of(entries[0], host, true)
	var undone := LiveEditCodec.decode(LiveEditCodec.encode(undo_op), peer.document)
	assert_eq(undone.problem, "")
	LiveEditCodec.apply(undone.op, peer)
	assert_eq(peer.document.structures.size(), 0, "the undo travels as the list before")


func test_a_live_edit_with_a_bad_structure_is_refused() -> void:
	var bad := MapStructureIO.structure_json(_structure())
	bad["footprint"] = [[0.0, 0.0], [NAN, 1.0], [2.0, 2.0]]
	var op := {
		"v": LiveEditCodec.VERSION, "kind": "structures", "args": [[bad], Rect2()], "redo": true
	}
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), _doc)
	assert_ne(decoded.problem, "")
	var short := {"v": LiveEditCodec.VERSION, "kind": "structures", "args": [[]], "redo": true}
	assert_ne(LiveEditCodec.decode(LiveEditCodec.encode(short), _doc).problem, "")
	var undo_side := {
		"v": LiveEditCodec.VERSION, "kind": "structures", "args": [[], Rect2()], "redo": false
	}
	assert_ne(
		LiveEditCodec.decode(LiveEditCodec.encode(undo_side), _doc).problem,
		"",
		"structures take no direction"
	)


# --- the fingerprint ----------------------------------------------------------------------


func test_the_fingerprint_moves_with_every_structure_edit() -> void:
	var empty := MapFingerprint.of(null, _doc)
	assert_eq(empty.structures, [])
	_doc.structures.append(_structure())
	var base := MapFingerprint.of(null, _doc)
	assert_eq(MapFingerprint.diff(empty, base), ["structures"])
	assert_eq(MapFingerprint.diff(base, MapFingerprint.of(null, _doc)), [], "stable")
	var edits: Array[Callable] = [
		func(s: Structure) -> void: s.footprint[2] = Vector2(3.5, 2),
		func(s: Structure) -> void: s.seed_value += 1,
		func(s: Structure) -> void: s.params["floors"] = 3.0,
		func(s: Structure) -> void: s.params.erase("floors"),
		func(s: Structure) -> void: s.style = "desert",
		func(s: Structure) -> void: s.recipe = "core:townhouse",
	]
	for edit in edits:
		var changed := _structure()
		edit.call(changed)
		_doc.structures[0] = changed
		assert_eq(MapFingerprint.diff(base, MapFingerprint.of(null, _doc)), ["structures"])
	_doc.structures[0] = _structure()
	assert_eq(MapFingerprint.diff(base, MapFingerprint.of(null, _doc)), [], "put back")


func test_two_peers_fingerprint_alike_after_a_live_edit() -> void:
	var host := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	host.structures.add(_structure())
	var peer := _peer()
	var decoded := LiveEditCodec.decode(
		LiveEditCodec.encode(LiveEditCodec.op_of(entries[0], host)), peer.document
	)
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(
		MapFingerprint.diff(MapFingerprint.of(null, _doc), MapFingerprint.of(null, peer.document)),
		[]
	)
