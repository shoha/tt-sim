extends GutTest

## The crossings entry of map.ttmap (MapCrossingIO through MapDocumentIO): crossings.json on
## write, on read, and on untrusted input. The full round trip through a real file is also
## test_map_document_io.gd's test_round_trip_through_a_file (Fixtures.full_doc() carries
## crossings).

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const DIR := "user://test_map_document_crossings"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(DIR)


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	Fixtures.add_crossings(doc)
	return doc


func _entries(doc: MapDocument) -> Dictionary:
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "", "serializes")
	return packed["entries"]


func _crossing_json(overrides: Dictionary = {}) -> Dictionary:
	var crossing := {
		"id": 1,
		"kind": "plank",
		"start": [-2, 0],
		"end": [2, 0],
		"levels": [0.3, 0.6, 0.3],
		"width_m": 1.5,
		"style": "",
	}
	crossing.merge(overrides, true)
	return crossing


func _parse_crossings(list: Variant, version: Variant = 1) -> Dictionary:
	var data := {"version": version, "crossings": list}
	var entries := Fixtures.minimal_entries(
		{"crossings.json": JSON.stringify(data).to_utf8_buffer()}
	)
	return MapDocumentIO.parse(entries)


# --- writing --------------------------------------------------------------------------


func test_crossings_entry_is_written_and_known() -> void:
	var entries := _entries(_doc())
	assert_true(entries.has("crossings.json"))
	assert_true("crossings.json" in MapDocumentIO.KNOWN_ENTRIES)
	assert_true(MapDocumentIO.ENTRY_CAPS.has("crossings.json"))
	var data: Dictionary = JSON.parse_string(entries["crossings.json"].get_string_from_utf8())
	assert_eq(data["version"], 1.0)
	assert_eq(data["crossings"].size(), 2)
	var plank: Dictionary = data["crossings"][0]
	assert_eq(plank["kind"], "plank")
	assert_eq(plank["id"], 2.0)
	assert_eq(plank["start"], [-3.25, -2.5])
	assert_eq(plank["levels"], [0.125, 0.5, 0.25])
	assert_eq(plank["style"], Fixtures.BIOME_A)
	assert_eq(data["crossings"][1]["kind"], "stones")


func test_no_crossings_no_entry() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	assert_false(_entries(doc).has("crossings.json"))


func test_round_trip_through_a_file_is_exact() -> void:
	var doc := _doc()
	var path := DIR.path_join("crossings.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray())
	var read: MapDocument = result["document"]
	assert_eq(read.crossings.size(), 2)
	for i in 2:
		assert_true(read.crossings[i].same_as(doc.crossings[i]), "crossing %d bit-exact" % i)
	assert_eq(read.crossing(5).kind, Crossing.Kind.STONES)
	assert_null(read.crossing(3))


func test_writer_refusals() -> void:
	var cases := {
		"id 0": func(d: MapDocument) -> void: d.crossings[0].id = 0,
		"duplicate id": func(d: MapDocument) -> void: d.crossings[1].id = d.crossings[0].id,
		"nan anchor": func(d: MapDocument) -> void: d.crossings[0].start = Vector2(NAN, 0),
		"off map": func(d: MapDocument) -> void: d.crossings[0].end = Vector2(16, 0),
		"zero span": func(d: MapDocument) -> void: d.crossings[0].end = d.crossings[0].start,
		"long": _long_span,
		"inf level": func(d: MapDocument) -> void: d.crossings[0].levels = Vector3(0, INF, 0),
		"huge level": func(d: MapDocument) -> void: d.crossings[0].levels = Vector3.ONE * 2000,
		"steep middle": func(d: MapDocument) -> void: d.crossings[0].levels = Vector3(0, 5, 0),
		"narrow": func(d: MapDocument) -> void: d.crossings[0].width_m = 0.2,
		"wide stones": func(d: MapDocument) -> void: d.crossings[1].width_m = 2.0,
		"nan width": func(d: MapDocument) -> void: d.crossings[0].width_m = NAN,
		"long style": func(d: MapDocument) -> void: d.crossings[0].style = "x".repeat(300),
		"too many": _too_many,
	}
	for label in cases:
		var doc := _doc()
		cases[label].call(doc)
		var packed := MapDocumentIO.serialize(doc)
		assert_ne(packed["error"], "", "refused: " + label)
		assert_true(packed["entries"].is_empty(), "nothing to write: " + label)


func _long_span(doc: MapDocument) -> void:
	doc.crossings[0].start = Vector2(-13, 0)
	doc.crossings[0].end = Vector2(13, 0)


func _too_many(doc: MapDocument) -> void:
	for _k in MapDocument.MAX_CROSSINGS:
		var extra := doc.crossings[0].copy()
		extra.id = doc.crossings.size() + 10
		doc.crossings.append(extra)


func test_cap_is_reachable_and_ids_run_out_cleanly() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var template := _doc().crossings[0]
	while doc.next_crossing_id() > 0:
		var extra := template.copy()
		extra.id = doc.next_crossing_id()
		doc.crossings.append(extra)
	assert_eq(doc.crossings.size(), MapDocument.MAX_CROSSINGS)
	var entries := _entries(doc)
	assert_lt(entries["crossings.json"].size(), MapDocumentIO.ENTRY_CAPS["crossings.json"])
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	assert_eq(result["document"].crossings.size(), MapDocument.MAX_CROSSINGS)


# --- reading --------------------------------------------------------------------------


func test_malformed_crossings_are_skipped() -> void:
	var cases := {
		"not an object": 5,
		"unknown kind": _crossing_json({"kind": "arch"}),
		"id": _crossing_json({"id": 256}),
		"fractional id": _crossing_json({"id": 1.5}),
		"no start": _crossing_json({"start": null}),
		"pair": _crossing_json({"end": [1]}),
		"string coordinate": _crossing_json({"end": ["2", 0]}),
		"off the map": _crossing_json({"end": [40, 0]}),
		"zero span": _crossing_json({"end": [-2, 0]}),
		"levels shape": _crossing_json({"levels": [0, 1]}),
		"string level": _crossing_json({"levels": [0, "high", 0]}),
		"huge level": _crossing_json({"levels": [0, 1e300, 0]}),
		"width": _crossing_json({"width_m": 9}),
		"no width": _crossing_json({"width_m": null}),
		"style": _crossing_json({"style": 7}),
	}
	for label in cases:
		var result := _parse_crossings([cases[label], _crossing_json({"id": 9})])
		var doc: MapDocument = result["document"]
		assert_not_null(doc, label)
		assert_eq(doc.crossings.size(), 1, "only the good crossing is kept: " + label)
		assert_eq(doc.crossings[0].id, 9, label)
		assert_true(Fixtures.has_warning(result, "skipped"), label + str(result["warnings"]))


func test_duplicate_ids_keep_the_first() -> void:
	var result := _parse_crossings([_crossing_json(), _crossing_json({"width_m": 2.0})])
	assert_eq(result["document"].crossings.size(), 1)
	assert_eq(result["document"].crossings[0].width_m, 1.5)
	assert_true(Fixtures.has_warning(result, "used twice"))


func test_cap_on_read() -> void:
	var list: Array = []
	for k in MapDocument.MAX_CROSSINGS + 3:
		list.append(_crossing_json({"id": k + 1}))
	var result := _parse_crossings(list)
	assert_eq(result["document"].crossings.size(), MapDocument.MAX_CROSSINGS)
	assert_true(Fixtures.has_warning(result, "over the cap"))


func test_bad_entry_drops_the_crossings_only() -> void:
	for version in [2, null, "1"]:
		var result := _parse_crossings([_crossing_json()], version)
		assert_not_null(result["document"], "the map still loads")
		assert_eq(result["document"].crossings.size(), 0, str(version))
		assert_true(Fixtures.has_warning(result, "crossings ignored"))
	var no_list := _parse_crossings({"a": 1})
	assert_eq(no_list["document"].crossings.size(), 0)
	var not_json := Fixtures.minimal_entries({"crossings.json": "{".to_utf8_buffer()})
	assert_true(Fixtures.has_warning(MapDocumentIO.parse(not_json), "not valid JSON"))


func test_oversized_entry_is_ignored() -> void:
	var entries := _entries(_doc())
	var huge := PackedByteArray()
	huge.resize(MapDocumentIO.ENTRY_CAPS["crossings.json"] + 1)
	entries["crossings.json"] = huge
	var result := MapDocumentIO.parse(entries)
	assert_not_null(result["document"])
	assert_true(Fixtures.has_warning(result, "over its cap"))
	assert_eq(result["document"].crossings.size(), 0)


func test_next_crossing_id_fills_gaps_only_at_the_top() -> void:
	var doc := _doc()
	assert_eq(doc.next_crossing_id(), 6, "one past the highest")
	doc.crossings[1].id = Crossing.MAX_ID
	assert_eq(doc.next_crossing_id(), 1, "the lowest free id once the top is taken")
