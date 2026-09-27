extends GutTest

## The water entries of map.ttmap (MapWaterIO through MapDocumentIO): splines.json,
## ponds.png and water_flow.png on write, on read, and on untrusted input. The full round
## trip through a real file, water included, is test_map_document_io.gd's
## test_round_trip_through_a_file (Fixtures.full_doc() carries water).

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const DIR := "user://test_map_document_water"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(DIR)


func _water_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	Fixtures.add_water(doc)
	return doc


func _entries(doc: MapDocument) -> Dictionary:
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "", "serializes")
	return packed["entries"]


func _splines(entries: Dictionary) -> Dictionary:
	return JSON.parse_string(entries["splines.json"].get_string_from_utf8())


## Entries of _water_doc() with splines.json replaced by `data`.
func _with_splines(data: Variant) -> Dictionary:
	var entries := _entries(_water_doc())
	entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
	return entries


func _river_json(overrides: Dictionary = {}) -> Dictionary:
	var body := {
		"id": 1,
		"kind": "river",
		"depth": "ankle",
		"level_m": 0.5,
		"speed": 1.0,
		"points": [[-5, 0], [5, 0]],
		"half_widths": [1, 1],
	}
	body.merge(overrides, true)
	return body


func _parse_bodies(bodies: Array) -> Dictionary:
	var entries := Fixtures.minimal_entries(
		{"splines.json": JSON.stringify({"version": 1, "bodies": bodies}).to_utf8_buffer()}
	)
	return MapDocumentIO.parse(entries)


# --- writing --------------------------------------------------------------------------


func test_water_entries_are_written() -> void:
	var entries := _entries(_water_doc())
	for entry_name in ["splines.json", "ponds.png", "water_flow.png"]:
		assert_true(entries.has(entry_name), entry_name)
		assert_true(entry_name in MapDocumentIO.KNOWN_ENTRIES)
		assert_true(MapDocumentIO.ENTRY_CAPS.has(entry_name))
	var data := _splines(entries)
	assert_eq(data["version"], 1.0)
	assert_eq(data["bodies"].size(), 2)
	assert_eq(data["bodies"][0]["kind"], "river")
	assert_eq(data["bodies"][0]["depth"], "waist")
	assert_eq(data["bodies"][0]["points"].size(), 3)
	assert_eq(data["bodies"][1], {"id": 7.0, "kind": "pond", "depth": "deep", "level_m": -1.25})
	var size := WaterFlowBaker.resolution_for(Vector2(20, 20) * 1.524)
	assert_eq(data["flow"], {"frame": "map_xz", "size": [float(size.x), float(size.y)]})


func test_bodies_without_ponds_or_flow_write_only_splines() -> void:
	var doc := _water_doc()
	doc.pond_mask = PackedByteArray()
	doc.water_flow = PackedByteArray()
	doc.water_flow_size = Vector2i.ZERO
	var entries := _entries(doc)
	assert_true(entries.has("splines.json"))
	assert_false(entries.has("ponds.png"))
	assert_false(entries.has("water_flow.png"))
	assert_false(_splines(entries).has("flow"))
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	assert_eq(result["document"].water_bodies.size(), 2)
	assert_true(result["document"].water_flow.is_empty())


func test_writer_refusals() -> void:
	var cases := {
		"id 0": func(d: MapDocument) -> void: d.water_bodies[0].id = 0,
		"duplicate id": func(d: MapDocument) -> void: d.water_bodies[1].id = d.water_bodies[0].id,
		"nan level": func(d: MapDocument) -> void: d.water_bodies[0].level_m = NAN,
		"inf speed": func(d: MapDocument) -> void: d.water_bodies[0].speed = INF,
		"fast": func(d: MapDocument) -> void: d.water_bodies[0].speed = 2.5,
		"off map": func(d: MapDocument) -> void: d.water_bodies[0].points[1] = Vector2(16, 0),
		"nan point": func(d: MapDocument) -> void: d.water_bodies[0].points[1] = Vector2(NAN, 0),
		"one point": func(d: MapDocument) -> void: d.water_bodies[0].points.resize(1),
		"widths": func(d: MapDocument) -> void: d.water_bodies[0].half_widths.resize(2),
		"thin": func(d: MapDocument) -> void: d.water_bodies[0].half_widths[0] = 0.05,
		"pond line": _give_the_pond_a_line,
		"mask size": func(d: MapDocument) -> void: d.pond_mask = PackedByteArray([7]),
		"mask id": func(d: MapDocument) -> void: d.pond_mask[0] = Fixtures.RIVER_ID,
		"flow size": func(d: MapDocument) -> void: d.water_flow_size = Vector2i(1, 4),
		"flow bytes": func(d: MapDocument) -> void: d.water_flow.resize(10),
		"too many points": _overlong_river,
		"too many rivers": func(d: MapDocument) -> void: _add_rivers(d, MapDocument.MAX_RIVERS),
		"too many bodies": _too_many_bodies,
	}
	for label in cases:
		var doc := _water_doc()
		cases[label].call(doc)
		var packed := MapDocumentIO.serialize(doc)
		assert_ne(packed["error"], "", "refused: " + label)
		assert_true(packed["entries"].is_empty(), "nothing to write: " + label)


func test_caps_are_reachable() -> void:
	var doc := _water_doc()
	_grow_river(doc.water_bodies[0], MapDocument.MAX_RIVER_POINTS)
	_add_rivers(doc, MapDocument.MAX_RIVERS - 1)
	_add_ponds(doc, MapDocument.MAX_WATER_BODIES - doc.water_bodies.size())
	assert_eq(doc.water_bodies.size(), MapDocument.MAX_WATER_BODIES)
	var entries := _entries(doc)
	assert_lt(entries["splines.json"].size(), MapDocumentIO.ENTRY_CAPS["splines.json"])
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	assert_eq(result["document"].water_bodies.size(), MapDocument.MAX_WATER_BODIES)


func _give_the_pond_a_line(doc: MapDocument) -> void:
	doc.water_bodies[1].points = doc.water_bodies[0].points


func _overlong_river(doc: MapDocument) -> void:
	_grow_river(doc.water_bodies[0], MapDocument.MAX_RIVER_POINTS + 1)


func _too_many_bodies(doc: MapDocument) -> void:
	_add_ponds(doc, MapDocument.MAX_WATER_BODIES)


func _grow_river(river: WaterBody, count: int) -> void:
	var line := PackedVector2Array()
	var widths := PackedFloat32Array()
	for k in count:
		line.append(Vector2(-14.0 + 28.0 * k / (count - 1), sin(k * 0.1) * 3.0))
		widths.append(1.0)
	river.points = line
	river.half_widths = widths


func _add_rivers(doc: MapDocument, count: int) -> void:
	for _k in count:
		var line := PackedVector2Array([Vector2(-5, 1), Vector2(5, 1)])
		var widths := PackedFloat32Array([0.5, 0.5])
		var body_id := doc.next_water_id()
		doc.water_bodies.append(WaterBody.river(body_id, line, widths, WaterBody.Depth.ANKLE, 0))


func _add_ponds(doc: MapDocument, count: int) -> void:
	for _k in count:
		doc.water_bodies.append(WaterBody.pond(doc.next_water_id(), WaterBody.Depth.WAIST, 0))


# --- reading --------------------------------------------------------------------------


func test_round_trip_through_a_file() -> void:
	var doc := _water_doc()
	var path := DIR.path_join("water.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray())
	var read: MapDocument = result["document"]
	assert_eq(read.water_bodies.size(), 2)
	var river := read.water_bodies[0]
	assert_eq(river.id, Fixtures.RIVER_ID)
	assert_eq(river.kind, WaterBody.Kind.RIVER)
	assert_eq(river.depth, WaterBody.Depth.WAIST)
	assert_eq(river.speed, 0.8)
	assert_true(river.points == doc.water_bodies[0].points)
	assert_eq(read.water_body(Fixtures.POND_ID).level_m, -1.25)
	assert_true(read.pond_mask == doc.pond_mask)
	assert_eq(read.water_flow_size, doc.water_flow_size)
	assert_true(read.water_flow == doc.water_flow, "the flow map ships bit-exact")
	assert_true(WaterFlowBaker.bake(read, read.water_flow_size) == read.water_flow, "rebake")


func test_malformed_bodies_are_skipped() -> void:
	var cases := {
		"not an object": 5,
		"unknown kind": _river_json({"kind": "lake"}),
		"unknown depth": _river_json({"depth": 3}),
		"id": _river_json({"id": 256}),
		"fractional id": _river_json({"id": 1.5}),
		"no level": _river_json({"level_m": "high"}),
		"huge level": _river_json({"level_m": 1e300}),
		"speed": _river_json({"speed": -1}),
		"no points": _river_json({"points": null}),
		"one point": _river_json({"points": [[0, 0]], "half_widths": [1]}),
		"pair": _river_json({"points": [[0, 0], [1]]}),
		"string coordinate": _river_json({"points": [[0, 0], ["1", 0]]}),
		"off the map": _river_json({"points": [[0, 0], [20, 0]]}),
		"widths": _river_json({"half_widths": [1]}),
		"wide": _river_json({"half_widths": [1, 11]}),
		"pond with a line": {"id": 2, "kind": "pond", "depth": "deep", "level_m": 0, "points": []},
	}
	for label in cases:
		var result := _parse_bodies([cases[label], _river_json({"id": 9})])
		var doc: MapDocument = result["document"]
		assert_not_null(doc, label)
		assert_eq(doc.water_bodies.size(), 1, "only the good body is kept: " + label)
		assert_true(Fixtures.has_warning(result, "skipped"), label + str(result["warnings"]))


func test_body_caps_on_read() -> void:
	var bodies: Array = []
	for k in MapDocument.MAX_WATER_BODIES + 3:
		bodies.append({"id": k + 1, "kind": "pond", "depth": "ankle", "level_m": 0})
	var result := _parse_bodies(bodies)
	assert_eq(result["document"].water_bodies.size(), MapDocument.MAX_WATER_BODIES)
	assert_true(Fixtures.has_warning(result, "over the cap"))
	var rivers: Array = []
	for k in MapDocument.MAX_RIVERS + 2:
		rivers.append(_river_json({"id": k + 1}))
	var capped := _parse_bodies(rivers)
	assert_eq(capped["document"].water_bodies.size(), MapDocument.MAX_RIVERS)
	var too_long: Array = []
	for k in MapDocument.MAX_RIVER_POINTS + 1:
		too_long.append([0, 0])
	var widths: Array = []
	widths.resize(too_long.size())
	widths.fill(1)
	var long := _parse_bodies([_river_json({"points": too_long, "half_widths": widths})])
	assert_eq(long["document"].water_bodies.size(), 0)


func test_duplicate_ids_keep_the_first() -> void:
	var result := _parse_bodies([_river_json(), _river_json({"level_m": 9})])
	assert_eq(result["document"].water_bodies.size(), 1)
	assert_eq(result["document"].water_bodies[0].level_m, 0.5)
	assert_true(Fixtures.has_warning(result, "used twice"))


func test_bad_splines_drop_all_water() -> void:
	for data in [[], {"bodies": []}, {"version": 2, "bodies": []}, {"version": 1}]:
		var result := MapDocumentIO.parse(_with_splines(data))
		var doc: MapDocument = result["document"]
		assert_not_null(doc, "the map itself still loads")
		assert_eq(doc.water_bodies.size(), 0, str(data))
		assert_true(doc.pond_mask.is_empty() and doc.water_flow.is_empty(), str(data))
		assert_gt(result["warnings"].size(), 0)
	var not_json := _entries(_water_doc())
	not_json["splines.json"] = "{".to_utf8_buffer()
	assert_true(Fixtures.has_warning(MapDocumentIO.parse(not_json), "not valid JSON"))


func test_images_without_splines_are_ignored() -> void:
	var entries := _entries(_water_doc())
	entries.erase("splines.json")
	var result := MapDocumentIO.parse(entries)
	assert_true(result["document"].pond_mask.is_empty())
	assert_true(result["document"].water_flow.is_empty())
	assert_true(Fixtures.has_warning(result, "ponds.png without splines.json"))
	assert_true(Fixtures.has_warning(result, "water_flow.png without splines.json"))


func test_pond_mask_bytes_naming_no_pond_are_cleared() -> void:
	var doc := _water_doc()
	var entries := _entries(doc)
	var data := _splines(entries)
	data["bodies"].pop_back()
	entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
	var result := MapDocumentIO.parse(entries)
	var read: MapDocument = result["document"]
	assert_eq(read.pond_mask.count(0), read.sample_count(), "every byte cleared")
	assert_true(Fixtures.has_warning(result, "name no pond"))
	var wrong := _entries(doc)
	wrong["ponds.png"] = Fixtures.mask_png(Vector2i(4, 4), Image.FORMAT_L8)
	var small := MapDocumentIO.parse(wrong)
	assert_true(small["document"].pond_mask.is_empty())
	assert_true(Fixtures.has_warning(small, "sample grid"))


func test_flow_map_needs_matching_metadata() -> void:
	var cases := {
		"no flow": null,
		"frame": {"frame": "plane_uv", "size": [122, 122]},
		"size": {"frame": "map_xz", "size": [64, 122]},
		"huge": {"frame": "map_xz", "size": [4096, 4096]},
		"shape": {"frame": "map_xz", "size": 122},
	}
	for label in cases:
		var doc := _water_doc()
		var entries := _entries(doc)
		var data := _splines(entries)
		data.erase("flow")
		if cases[label] != null:
			data["flow"] = cases[label]
		entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
		var result := MapDocumentIO.parse(entries)
		var read: MapDocument = result["document"]
		assert_true(read.water_flow.is_empty(), label)
		assert_eq(read.water_flow_size, Vector2i.ZERO, label)
		assert_eq(read.water_bodies.size(), 2, "the bodies are kept: " + label)
		assert_true(Fixtures.has_warning(result, "water_flow.png"), label)
	var garbage := _entries(_water_doc())
	garbage["water_flow.png"] = "not a png".to_utf8_buffer()
	assert_true(MapDocumentIO.parse(garbage)["document"].water_flow.is_empty())


func test_oversized_water_entries_are_ignored() -> void:
	for entry_name in ["splines.json", "ponds.png", "water_flow.png"]:
		var entries := _entries(_water_doc())
		var huge := PackedByteArray()
		huge.resize(MapDocumentIO.ENTRY_CAPS[entry_name] + 1)
		entries[entry_name] = huge
		var result := MapDocumentIO.parse(entries)
		assert_not_null(result["document"])
		assert_true(Fixtures.has_warning(result, "over its cap"), entry_name)
