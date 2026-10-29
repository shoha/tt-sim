extends GutTest

## Structures served by libraries (card S3): the registry reads a library's `structures/` kind into
## LibraryStructureStore (rows, recipe texts and digests by `<library>:<id>` reference), a map's
## structure references count as library use (MapLibraries), the S2 resolver seam
## (StructureRecipes) reads the registry first, a reference nobody serves builds a placeholder
## plot instead of a hole, a hostile library loses only its bad structures, and Verify builds each
## recipe at its default footprint. The shipped core library holds the five starter structures
## and their pins.

const SW := preload("res://tests/unit/library_structure_world.gd")
const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_library_structure_store"

var _paths: Dictionary = {}
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	SW.write(_paths["alien"], {"hut": "cottage", "manor": "townhouse"})
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply(_paths["base"])


func after_each() -> void:
	StructureRecipes.resolver = Callable()
	StructureRecipes.procgen_fallback = false


# ---- serving ----


func test_a_library_with_structures_serves_rows_recipes_and_digests() -> void:
	var rows := LibraryStructureStore.structures("alienworld")
	assert_eq(
		rows.map(func(r: Dictionary) -> String: return r["ref"]),
		["alienworld:hut", "alienworld:manor"]
	)
	var row := LibraryStructureStore.structure("alienworld:hut")
	assert_eq(row["name"], "Hut")
	assert_eq(row["default_size_m"], [6.0, 4.0])
	assert_true(String(row["thumb"]).ends_with("alienworld/thumbnails/structures/hut.jpg"))
	assert_true(FileAccess.file_exists(row["thumb"]), "the tile is a file of the library")
	var recipe := LibraryStructureStore.recipe("alienworld:hut")
	assert_eq(recipe["digest"], String(recipe["text"]).sha256_text())
	assert_eq(row["digest"], recipe["digest"])
	assert_true(LibraryStructureStore.has("alienworld:manor"))
	assert_false(LibraryStructureStore.has("alienworld:castle"))
	assert_eq(LibraryStructureStore.recipe("alienworld:castle"), {})
	assert_eq(LibraryStructureStore.structure("nope"), {})
	assert_eq(LibraryRegistry.info("alienworld", _paths["base"])["structure_count"], 2)


func test_a_library_without_structures_serves_none_and_the_files_are_identity() -> void:
	assert_eq(LibraryStructureStore.structures("core"), [])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	var before: String = info["hash"]
	for relative in [
		"structures/index.json", "structures/hut.structure.json", "structures/manor.structure.json"
	]:
		DirAccess.remove_absolute(_paths["alien"].path_join(relative))
	LibraryRegistry.clear()
	LibraryRegistry.apply(_paths["base"])
	assert_ne(
		LibraryRegistry.info("alienworld", _paths["base"])["hash"],
		before,
		"structures are part of the identity"
	)
	assert_eq(LibraryStructureStore.structures("alienworld"), [])


func test_a_hostile_recipe_costs_only_its_own_structure() -> void:
	var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
	data["nodes"][0]["type"] = "run_script"
	World.write_text(
		_paths["alien"].path_join("structures/hut.structure.json"), JSON.stringify(data)
	)
	LibraryRegistry.clear()
	LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["status"], "ok", "the library is fine")
	assert_false(LibraryStructureStore.has("alienworld:hut"))
	assert_true(LibraryStructureStore.has("alienworld:manor"))
	assert_true((info["warnings"] as Array).any(func(line: String) -> bool: return "hut" in line))


func test_a_collection_of_buildings_without_a_biome_is_served() -> void:
	var folder: String = _paths["user"] + "/huts"
	World.write_json(
		folder + "/library.json",
		{
			"format": "ttsim-library",
			"format_version": 1,
			"id": "huts",
			"version": "1.0.0",
			"contract": 1
		}
	)
	World.write_json(
		folder + "/assets/catalog.json",
		{"format": "ttsim-catalog", "format_version": 1, "assets": []}
	)
	SW.write(folder, {"cabin": "cottage"})
	LibraryRegistry.clear()
	var result := LibraryRegistry.apply(_paths["base"])
	var info := LibraryRegistry.info("huts", _paths["base"])
	assert_eq(info["status"], "ok", str(result["errors"]))
	assert_true(LibraryStructureStore.has("huts:cabin"))
	assert_eq(LibraryRegistry.record_of("huts")["version"], "1.0.0", "a map can record it")


func test_clearing_the_registry_forgets_the_structures() -> void:
	assert_eq(LibraryStructureStore.structures().size(), 2)
	LibraryRegistry.clear()
	assert_eq(LibraryStructureStore.structures().size(), 0)


# ---- maps ----


func test_a_maps_structure_references_count_as_library_use() -> void:
	var doc := SW.map_with("alienworld:hut")
	assert_eq(
		LibraryStructureStore.used_by(doc), {"alienworld": PackedStringArray(["alienworld:hut"])}
	)
	assert_true("alienworld" in MapLibraries.used_ids(doc))
	var records := MapLibraries.record_for(doc)
	var ours := records.filter(func(r: Dictionary) -> bool: return r["id"] == "alienworld")
	assert_eq(ours.size(), 1, "the map lists the library its structure comes from")
	assert_eq(ours[0]["version"], "0.3.1")
	assert_eq(MapLibraries.format_for(records), MapDocument.FORMAT_LIBRARIES)
	assert_eq(LibraryRegistry.assets_used_by(doc), {}, "a structure is no palette asset")


func test_a_core_structure_names_core_and_keeps_the_plain_format() -> void:
	var doc := SW.map_with("core:cottage")
	assert_eq(MapLibraries.used_ids(doc), ["core"])
	assert_eq(MapLibraries.format_for(MapLibraries.record_for(doc)), MapDocument.FORMAT)


func test_references_are_collected_once_and_sorted_per_library() -> void:
	var doc := SW.map_with("alienworld:manor")
	var plan := doc.structures[0].footprint
	doc.structures.append(Structure.make(2, "alienworld:hut", plan, 6))
	doc.structures.append(Structure.make(3, "alienworld:hut", plan, 7))
	doc.structures.append(Structure.make(4, "core:cottage", plan, 8))
	var used := LibraryStructureStore.used_by(doc)
	assert_eq(used["alienworld"], PackedStringArray(["alienworld:hut", "alienworld:manor"]))
	assert_eq(used["core"], PackedStringArray(["core:cottage"]))


func test_a_library_missing_on_this_install_is_reported_by_the_map_check() -> void:
	var doc := SW.map_with("lostlib:hall")
	doc.libraries = MapLibraries.record_for(doc)
	assert_true(doc.libraries.any(func(r: Dictionary) -> bool: return r["id"] == "lostlib"))
	var report := MapLibraries.check(doc.libraries)
	assert_false(report["ok"])
	assert_eq(report["missing"].map(func(m: Dictionary) -> String: return m["id"]), ["lostlib"])


# ---- the resolver seam and the placeholder ----


func test_the_resolver_reads_the_registry_and_builds_the_recipe() -> void:
	var doc := SW.map_with("alienworld:hut")
	var parts := StructureGeometry.build_one(doc, doc.structures[0])
	assert_eq(parts.problem, "")
	assert_false(parts.placeholder)
	assert_gt(StructureGeometry.triangle_count(parts), 500)
	assert_not_null(StructureRecipes.document("alienworld:hut"))
	assert_eq(
		StructureRecipes.digest("alienworld:hut"),
		LibraryStructureStore.recipe("alienworld:hut")["digest"]
	)


func test_an_explicit_resolver_wins_and_the_procgen_folder_is_only_a_fallback() -> void:
	var text := SW.recipe_text("townhouse")
	StructureRecipes.resolver = func(_ref: String) -> Dictionary: return {"text": text}
	assert_eq(
		StructureRecipes.digest("alienworld:hut"), text.sha256_text(), "the resolver is first"
	)
	StructureRecipes.resolver = Callable()
	assert_eq(StructureRecipes.digest("nolib:nothing"), "", "nobody serves it, no fallback")
	assert_false(StructureRecipes.exists("core:castle"))
	assert_false(StructureRecipes.exists("core:cottage"), "the test world's core has none")
	StructureRecipes.procgen_fallback = true
	assert_true(StructureRecipes.exists("core:cottage"), "the fallback reads procgen's folder")


func test_a_recipe_no_one_serves_builds_a_placeholder_plot() -> void:
	var doc := SW.map_with("lostlib:hall")
	var parts := StructureGeometry.build_one(doc, doc.structures[0])
	assert_true(parts.placeholder)
	assert_string_contains(parts.problem, "unknown")
	assert_eq((parts.meshes as Array).size(), 1)
	assert_gt(StructureGeometry.triangle_count(parts), 4, "a top face and a skirt")
	assert_lt(StructureGeometry.triangle_count(parts), 40)
	assert_eq(parts.top, StructureGeometry.NONE, "nobody stands on a plot")
	assert_true((parts.collision as PackedVector3Array).is_empty())
	var low := 1000.0
	var high := -1000.0
	for vertex: Vector3 in parts.meshes[0].arrays[Mesh.ARRAY_VERTEX]:
		low = minf(low, vertex.y)
		high = maxf(high, vertex.y)
		assert_lt(absf(vertex.x), 3.01, "inside the footprint")
	assert_gt(high - low, 0.1)
	assert_lt(high - low, 0.5)


func test_a_plot_follows_a_slope_and_faces_outward() -> void:
	var doc := SW.map_with("lostlib:hall")
	var rise := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			rise[doc.sample_index(x, z)] = 0.2 * doc.sample_to_world(Vector2(x, z)).x
	doc.heights = rise
	var parts := StructureGeometry.build_one(doc, doc.structures[0])
	var arrays: Array = parts.meshes[0].arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var left := 1000.0
	var right := -1000.0
	for vertex in vertices:
		if vertex.x < -2.9:
			left = minf(left, vertex.y)
		if vertex.x > 2.9:
			right = maxf(right, vertex.y)
	assert_gt(right - left, 1.0, "the slab rises with the ground")
	for t in indices.size() / 3:
		var a := vertices[indices[t * 3]]
		var face := (
			(vertices[indices[t * 3 + 1]] - a).cross(vertices[indices[t * 3 + 2]] - a).normalized()
		)
		assert_gt(face.dot(normals[indices[t * 3]]), 0.5, "triangle %d faces its normal" % t)


func test_the_placeholder_becomes_the_building_once_the_library_arrives() -> void:
	var doc := SW.map_with("alienworld:hut")
	DirAccess.remove_absolute(_paths["alien"].path_join("structures/index.json"))
	LibraryRegistry.clear()
	LibraryRegistry.apply(_paths["base"])
	var map := Node3D.new()
	add_child_autofree(map)
	var nodes := AuthoredStructures.refresh_map(map, doc)
	nodes.flush()
	assert_not_null(nodes.get_structure_node(1))
	assert_lt(_triangles(nodes.get_structure_node(1)), 40, "a plot")
	assert_engine_error(1, "the missing recipe is logged once")
	var plot_key := StructureGeometry.key_of(doc, doc.structures[0])
	SW.write(_paths["alien"], {"hut": "cottage", "manor": "townhouse"})
	LibraryRegistry.clear()
	LibraryRegistry.apply(_paths["base"])
	assert_ne(
		StructureGeometry.key_of(doc, doc.structures[0]),
		plot_key,
		"the recipe's digest is in the key"
	)
	nodes.refresh(doc, false)
	assert_gt(_triangles(nodes.get_structure_node(1)), 500, "the building")


func _triangles(node: Node) -> int:
	var total := 0
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var array_mesh := (mesh as MeshInstance3D).mesh
		if array_mesh.get_surface_count() > 0:
			total += array_mesh.surface_get_array_index_len(0) / 3
	return total


# ---- verify ----


func test_verify_lists_structures_and_builds_each_at_its_default_footprint() -> void:
	var plan := LibraryVerify.plan("alienworld", _paths["base"])
	assert_eq(plan["state"], LibraryVerify.READY)
	assert_true("structure:alienworld:hut" in plan["assets"])
	var made := LibraryVerify.check("structure:alienworld:hut", _paths["base"])
	assert_true(made["ok"], str(made))
	assert_gt(int(made["triangles"]), 500)
	assert_eq(LibraryVerify.short_name("structure:alienworld:hut"), "hut")


func test_verify_fails_a_structure_that_is_not_served_or_does_not_build() -> void:
	var gone := LibraryVerify.check("structure:alienworld:castle", _paths["base"])
	assert_false(gone["ok"])
	assert_string_contains(gone["error"], "not served")
	# A recipe with no Output node reads (every type is known) but yields nothing to build.
	var data: Dictionary = JSON.parse_string(SW.recipe_text("cottage"))
	var kept: Array = []
	var dropped := {}
	for node: Dictionary in data["nodes"]:
		if node["type"] == "output":
			dropped[node["id"]] = true
		else:
			kept.append(node)
	data["nodes"] = kept
	data["connections"] = (data["connections"] as Array).filter(
		func(c: Dictionary) -> bool: return not dropped.has(c["to"]) and not dropped.has(c["from"])
	)
	World.write_text(
		_paths["alien"].path_join("structures/hut.structure.json"), JSON.stringify(data)
	)
	LibraryRegistry.clear()
	LibraryRegistry.apply(_paths["base"])
	var broken := LibraryVerify.check("structure:alienworld:hut", _paths["base"])
	assert_false(broken["ok"], "a recipe that does not build fails the check")
	assert_string_contains(LibraryVerify.plain_error(broken["error"]), "recipe")


func test_the_verify_budgets_are_the_documented_ones() -> void:
	assert_eq(LibraryVerify.STRUCTURE_MAX_TRIANGLES, 60000)
	assert_eq(LibraryVerify.STRUCTURE_MAX_MSEC, 400.0)


# ---- the shipped core library ----


func test_core_ships_the_five_starter_structures_with_matching_pins() -> void:
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.user_root = ROOT + "/no_user_libraries"
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(PaletteLibrary.DEFAULT_ROOT)
	var ids := LibraryStructureStore.structures("core").map(
		func(r: Dictionary) -> String: return r["id"]
	)
	ids.sort()
	assert_eq(
		ids,
		[
			"adobe_house",
			"adobe_parapet",
			"adobe_rounded",
			"alpine_chalet",
			"barn",
			"brick_terrace",
			"canal_house",
			"castle_keep",
			"chapel",
			"chinese_hall",
			"cottage",
			"cottage_chimneyed",
			"cottage_hip",
			"dome_hall",
			"dutch_bell_house",
			"dutch_canal_house",
			"gambrel_barn",
			"gatehouse",
			"half_hip_cottage",
			"house_flat",
			"house_hip",
			"log_cabin",
			"mansard_townhouse",
			"market_hall",
			"minka",
			"pagoda_tower",
			"pueblo",
			"round_hut",
			"roundhouse",
			"ruin_barn",
			"ruin_chapel",
			"ruin_cottage",
			"ruin_tower",
			"ruin_townhouse",
			"saltbox_house",
			"slate_house",
			"stone_house",
			"thatched_cottage",
			"tower_hex",
			"townhouse",
			"townhouse_chimneyed",
			"townhouse_end",
			"townhouse_flat",
			"townhouse_hip",
			"townhouse_timber",
			"townhouse_trimmed",
			"tudor_townhouse",
			"turf_longhouse",
			"villa_stucco",
			"watchtower"
		]
	)
	var pins := (
		FileAccess
		. get_file_as_string("res://libraries/core/structures/pins.txt")
		. strip_edges()
		. split("\n")
	)
	assert_eq(pins.size(), 50)
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var moved := PackedStringArray()
	for line in pins:
		var cells := line.split(" ")
		var plan := StructurePlacement.pin_plan(LibraryStructureStore.structure("core:" + cells[0]))
		var parts := StructureGeometry.build_one(
			doc, Structure.make(1, "core:" + cells[0], plan, 5)
		)
		assert_eq(parts.problem, "", line)
		var now := (
			"%s %s %d"
			% [
				cells[0],
				StructureGeometry.digest_of(parts),
				StructureGeometry.triangle_count(parts)
			]
		)
		if now != " ".join(cells.slice(0, 3)):
			moved.append("pinned '%s' now '%s'" % [line, now])
	assert_eq(
		moved.size(),
		0,
		"a deliberate change re-pins (tools/export_core_structures.gd): %s" % "; ".join(moved)
	)
	for row in LibraryStructureStore.structures("core"):
		assert_ne(String(row["thumb"]), "", "%s has a tile in the index" % row["ref"])
