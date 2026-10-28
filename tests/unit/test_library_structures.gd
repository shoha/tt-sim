extends GutTest

## The `structures/` kind of a content library, pure half (card S3, LibraryStructures through
## LibraryReader): a good index reads; every hostile or broken part is a WARNING and leaves out
## the structure it belongs to, never the library; recipe documents are bounded before they are
## built (bytes, nodes, connections, node types, nested tables); the hash of a library without
## structures is what it was; the thumbnail render job and the index merge are plain data.

const SW := preload("res://tests/unit/library_structure_world.gd")
const World := preload("res://tests/unit/library_world.gd")


func _read(entries: Array, recipes: Dictionary, files: Array = []) -> Dictionary:
	var result := {"warnings": [] as Array[String]}
	LibraryStructures.read(SW.sources(entries, recipes), files, not files.is_empty(), result)
	return result


func _cottage_recipes(id: String = "hut") -> Dictionary:
	return {id + LibraryStructures.RECIPE_SUFFIX: SW.recipe_text("cottage")}


func _has_warning(result: Dictionary, needle: String) -> bool:
	return (result["warnings"] as Array).any(func(line: String) -> bool: return needle in line)


# ---- a good index ----


func test_a_good_index_reads_with_its_fields_checked_and_a_digest() -> void:
	var text := SW.recipe_text("cottage")
	var result := _read(
		[SW.entry("hut", {"expose": ["height", "no_such_param"], "plans": ["rect", "l", "x"]})],
		{"hut.structure.json": text},
		["thumbnails/structures/hut.jpg"]
	)
	assert_eq((result["structures"] as Array).size(), 1)
	var item: Dictionary = result["structures"][0]
	assert_eq(item["id"], "hut")
	assert_eq(item["file"], "structures/hut.structure.json")
	assert_eq(item["digest"], text.sha256_text())
	var entry: Dictionary = item["entry"]
	assert_eq(entry["expose"], ["height"], "a name the interface lacks is dropped")
	assert_eq(entry["plans"], ["rect", "l"], "an unknown plan kind is dropped")
	assert_eq(entry["thumb"], "thumbnails/structures/hut.jpg")
	assert_true(_has_warning(result, "no_such_param"))


func test_defaults_fill_what_an_entry_leaves_out() -> void:
	var result := _read([{"id": "hut"}], _cottage_recipes())
	var entry: Dictionary = result["structures"][0]["entry"]
	assert_eq(entry["name"], "hut")
	assert_eq(entry["default_size_m"], [6.0, 4.0])
	assert_eq(entry["min_side_m"], LibraryStructures.DEFAULT_MIN_SIDE_M)
	assert_eq(entry["plans"], ["rect"])
	assert_eq(entry["expose"], [])
	assert_eq(entry["file"], "structures/hut.structure.json")


func test_a_missing_thumbnail_is_a_warning_and_the_entry_stays() -> void:
	var result := _read([SW.entry("hut")], _cottage_recipes(), ["library.json"])
	assert_eq((result["structures"] as Array).size(), 1)
	assert_eq(result["structures"][0]["entry"]["thumb"], "")
	assert_true(_has_warning(result, "thumbnail"))


func test_the_reader_carries_structures_and_the_library_stays_ok() -> void:
	var sources := {
		"library":
		JSON.stringify(
			{
				"format": "ttsim-library",
				"format_version": 1,
				"id": "huts",
				"contract": 1,
				"version": "1.0.0"
			}
		),
		"catalog": JSON.stringify({"format": "ttsim-catalog", "format_version": 1, "assets": []}),
		"biomes": {},
		"structures": SW.sources([SW.entry("hut")], _cottage_recipes()),
	}
	var read := LibraryReader.read(sources)
	assert_true(read["ok"], str(read["errors"]))
	assert_eq((read["structures"] as Array).size(), 1)
	assert_true(
		LibraryStructureStore.buildings_only(read), "no biome-def: a collection of buildings"
	)


# ---- hostile and broken input ----


func test_an_unreadable_index_ignores_the_structures_with_a_warning() -> void:
	for text in [
		"{not json",
		"[]",
		JSON.stringify({"format": "other", "format_version": 1, "structures": []})
	]:
		var result := {"warnings": [] as Array[String]}
		LibraryStructures.read({"index": text, "recipes": _cottage_recipes()}, [], false, result)
		assert_eq((result["structures"] as Array).size(), 0, text)
		assert_gt((result["warnings"] as Array).size(), 0, text)
	var newer := {"warnings": [] as Array[String]}
	LibraryStructures.read(
		{
			"index":
			JSON.stringify({"format": "ttsim-structures", "format_version": 9, "structures": []}),
			"recipes": {}
		},
		[],
		false,
		newer
	)
	assert_eq((newer["warnings"] as Array).size(), 1, "a newer format version is not read")


func test_an_index_over_its_byte_cap_is_refused() -> void:
	var result := {"warnings": [] as Array[String]}
	var big := " ".repeat(int(LibraryContracts.STRUCTURE_CAPS["index_bytes"]) + 1)
	LibraryStructures.read({"index": big, "recipes": {}}, [], false, result)
	assert_eq((result["structures"] as Array).size(), 0)
	assert_true(_has_warning(result, "over"))


func test_more_structures_than_the_cap_keep_the_first_ones() -> void:
	var entries: Array = []
	var recipes := {}
	for k in int(LibraryContracts.STRUCTURE_CAPS["structures"]) + 5:
		var id := "s%d" % k
		entries.append(SW.entry(id))
		recipes[id + LibraryStructures.RECIPE_SUFFIX] = SW.recipe_text("cottage")
	var result := _read(entries, recipes)
	assert_eq(
		(result["structures"] as Array).size(), int(LibraryContracts.STRUCTURE_CAPS["structures"])
	)
	assert_true(_has_warning(result, "over the cap"))


func test_a_bad_entry_is_left_out_and_its_neighbours_stay() -> void:
	var recipes := _cottage_recipes("good")
	recipes["Bad.structure.json"] = SW.recipe_text("cottage")
	var entries: Array = [
		{"id": "Bad"},
		{"id": "a__b"},
		"not an object",
		{"id": ""},
		SW.entry("good"),
		SW.entry("good"),
		SW.entry("moved", {"file": "structures/elsewhere.structure.json"}),
		SW.entry("tiny", {"default_size_m": [1, 1], "min_side_m": 3}),
	]
	var result := {"warnings": [] as Array[String]}
	var raw_index := {"format": "ttsim-structures", "format_version": 1, "structures": entries}
	LibraryStructures.read(
		{"index": JSON.stringify(raw_index), "recipes": recipes}, [], false, result
	)
	assert_eq(
		(result["structures"] as Array).map(func(item: Dictionary) -> String: return item["id"]),
		["good"],
		"only the good one, once"
	)
	assert_gt((result["warnings"] as Array).size(), 5)


func test_unknown_keys_warn_and_are_not_kept() -> void:
	var result := _read([SW.entry("hut", {"colour": "red"})], _cottage_recipes())
	assert_true(_has_warning(result, "unknown key 'colour'"))
	assert_false((result["structures"][0]["entry"] as Dictionary).has("colour"))


func test_a_thumb_path_must_be_a_thumbnails_jpg() -> void:
	for bad in ["../x.jpg", "/abs.jpg", "assets/x.jpg", "thumbnails/x.png", "C:/x.jpg"]:
		var result := _read([SW.entry("hut", {"thumb": bad})], _cottage_recipes())
		assert_eq(result["structures"][0]["entry"]["thumb"], "thumbnails/structures/hut.jpg", bad)


func test_a_recipe_is_data_checked_before_it_is_built() -> void:
	var good := SW.recipe_text("cottage")
	assert_eq(LibraryStructures.recipe_problem(good), "")
	assert_ne(LibraryStructures.recipe_problem(""), "")
	assert_ne(LibraryStructures.recipe_problem("{oops"), "")
	assert_ne(LibraryStructures.recipe_problem("[1]"), "")
	assert_ne(LibraryStructures.recipe_problem(JSON.stringify({"format": "other"})), "")
	var big := good + " ".repeat(int(LibraryContracts.STRUCTURE_CAPS["recipe_bytes"]))
	assert_string_contains(LibraryStructures.recipe_problem(big), "bytes")


func test_a_recipe_with_too_many_nodes_or_connections_is_refused() -> void:
	var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
	var nodes: Array = data["nodes"]
	var template: Dictionary = nodes[0]
	for k in int(LibraryContracts.STRUCTURE_CAPS["recipe_nodes"]):
		var copy := template.duplicate(true)
		copy["id"] = "extra_%d" % k
		nodes.append(copy)
	assert_string_contains(LibraryStructures.recipe_problem(JSON.stringify(data)), "nodes")
	data = JSON.parse_string(SW.recipe_text("cottage"))
	var links: Array = data["connections"]
	for k in int(LibraryContracts.STRUCTURE_CAPS["recipe_connections"]) + 1:
		links.append(links[0].duplicate())
	assert_string_contains(LibraryStructures.recipe_problem(JSON.stringify(data)), "connections")


func test_a_recipe_with_a_bad_node_or_connection_is_refused() -> void:
	var cases := {
		"unknown type": func(d: Dictionary) -> void: d["nodes"][0]["type"] = "run_script",
		"no id": func(d: Dictionary) -> void: d["nodes"][0].erase("id"),
		"repeated id": func(d: Dictionary) -> void: d["nodes"][1]["id"] = d["nodes"][0]["id"],
		"bad position": func(d: Dictionary) -> void: d["nodes"][0]["position"] = ["x", 1],
		"nested table": func(d: Dictionary) -> void: d["nodes"][0]["params"] = {"a": {"b": 1}},
		"nested list": func(d: Dictionary) -> void: d["nodes"][0]["params"] = {"a": [[1]]},
		"params not an object": func(d: Dictionary) -> void: d["nodes"][0]["params"] = 5,
		"connection to nowhere": func(d: Dictionary) -> void: d["connections"][0]["to"] = "ghost_9",
		"connection not an object": func(d: Dictionary) -> void: d["connections"][0] = 3,
		"no ports": func(d: Dictionary) -> void: d["connections"][0].erase("from_port"),
		"interface name": func(d: Dictionary) -> void: d["interface"][0]["name"] = "Bad Name",
		"interface table": func(d: Dictionary) -> void: d["interface"][0]["tip"] = {"x": 1},
		"nodes not a list": func(d: Dictionary) -> void: d["nodes"] = "none",
	}
	for label: String in cases:
		var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
		(cases[label] as Callable).call(data)
		assert_ne(LibraryStructures.recipe_problem(JSON.stringify(data)), "", label)


func test_a_refused_recipe_leaves_the_structure_out_with_a_warning() -> void:
	var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
	data["nodes"][0]["type"] = "run_script"
	var result := _read(
		[SW.entry("hut"), SW.entry("fine")],
		{
			"hut.structure.json": JSON.stringify(data),
			"fine.structure.json": SW.recipe_text("cottage")
		}
	)
	assert_eq(result["structures"].size(), 1)
	assert_eq(result["structures"][0]["id"], "fine")
	assert_true(_has_warning(result, "hut"))


# ---- the hash ----


func test_a_library_without_structures_hashes_as_it_did() -> void:
	var plain := {
		"library": "{}", "catalog": "{}", "biomes": {"a.json": "1"}, "locks": {}, "surfaces": {}
	}
	var with_empty := plain.duplicate(true)
	with_empty["structures"] = {"index": "", "recipes": {}}
	assert_eq(LibraryHash.of(plain, 8), LibraryHash.of(with_empty, 8))
	var with_structures := plain.duplicate(true)
	with_structures["structures"] = SW.sources([SW.entry("hut")], _cottage_recipes())
	assert_ne(
		LibraryHash.of(plain, 8), LibraryHash.of(with_structures, 8), "structures are identity"
	)


# ---- the render job and the index ----


func test_the_thumbnail_job_draws_one_tile_per_structure() -> void:
	var items: Array = _read(
		[SW.entry("hut"), SW.entry("manor")],
		{
			"hut.structure.json": SW.recipe_text("cottage"),
			"manor.structure.json": SW.recipe_text("townhouse")
		}
	)["structures"]
	var job := LibraryStructures.thumbnail_job("huts", items, "D:/out", "D:/lib")
	var ops: Array = (job["steps"] as Array).map(
		func(s: Dictionary) -> String: return String(s["op"])
	)
	assert_eq(ops.count("thumbnail"), 2)
	assert_eq(ops.count("library_dev"), 1, "a library that is not served is laid over the game")
	for step: Dictionary in job["steps"]:
		if step["op"] == "thumbnail":
			assert_true(step["structure"])
			assert_eq(step["folder"], "D:/out")
	var served := LibraryStructures.thumbnail_job("core", items, "D:/out")
	var served_ops: Array = (served["steps"] as Array).map(
		func(s: Dictionary) -> String: return String(s["op"])
	)
	assert_false(served_ops.has("library_dev"), "core is already served")


func test_the_writer_puts_a_tile_under_thumbnails_structures_and_refuses_bad_places() -> void:
	var root := "user://test_library_structures_writer"
	World.remove_tree(root)
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.6, 0.4))
	for x in 64:
		image.set_pixel(x, x, Color.WHITE)
	var bytes := LibraryThumbnailer.encode(image)
	var folder := ProjectSettings.globalize_path(root)
	var made := LibraryWriter.write_structure_thumbnail(folder, "hut", bytes)
	assert_true(made["ok"], str(made["error"]))
	assert_true(FileAccess.file_exists(folder.path_join("thumbnails/structures/hut.jpg")))
	assert_false(LibraryWriter.write_structure_thumbnail(folder, "../x", bytes)["ok"])
	assert_false(
		LibraryWriter.write_structure_thumbnail("res://libraries/core", "hut", bytes)["ok"]
	)
	assert_false(
		LibraryWriter.write_structure_thumbnail(folder, "hut", PackedByteArray([1, 2]))["ok"]
	)
	World.remove_tree(root)


func test_two_indexes_merge_by_id_and_a_clash_is_refused() -> void:
	var left := LibraryStructures.index_text([SW.entry("a"), SW.entry("b")])
	var right := LibraryStructures.index_text([SW.entry("b"), SW.entry("c")])
	var merged := LibraryStructures.merge_index(left.to_utf8_buffer(), right.to_utf8_buffer())
	assert_true(merged["ok"])
	var ids: Array = (JSON.parse_string(merged["text"])["structures"] as Array).map(
		func(e: Dictionary) -> String: return e["id"]
	)
	assert_eq(ids, ["a", "b", "c"])
	var clash := LibraryStructures.index_text([SW.entry("b", {"name": "Other"})])
	assert_false(LibraryStructures.merge_index(left.to_utf8_buffer(), clash.to_utf8_buffer())["ok"])
