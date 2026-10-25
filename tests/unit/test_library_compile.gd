extends GutTest

## BiomeCompiler and LibraryRegistry (utils/library/): the savanna library compiles to a frozen
## golden (the exact biome and asset dictionaries a plantgen package carries, plus role and
## habit) with zero palette warnings; the miniature library compiles with the non-core id
## prefix, defaults from its roles and relations expanded by role; hostile inputs degrade to
## warnings and dropped rules; the registry lays the compiled library over a palette root with
## the overlay merge rule and loads its GLBs; the pure modules touch no files or scene tree.
##
## Fixtures: tests/fixtures/library_savanna (JSON copied from plantgen's out/lib_slice, no GLBs)
## with library_savanna_compiled.json, the golden (regenerate: godot --headless --path . --script
## res://tools/compile_library_cli.gd -- --library <folder> --out <file>), and
## tests/fixtures/library_mini (JSON only; this test writes its three GLBs under user://).

const SAVANNA := "res://tests/fixtures/library_savanna"
const GOLDEN := "res://tests/fixtures/library_savanna_compiled.json"
const MINI_SRC := "res://tests/fixtures/library_mini"
const ROOT := "user://test_library_compile"
const MINI := ROOT + "/mini"
const BASE := ROOT + "/base"
const SETTINGS := ROOT + "/settings.cfg"
const RUNTIME := "mini__meadow_summer_s1"
const PURE_MODULES: Array[String] = [
	"library_contracts", "library_ids", "library_reader", "biome_compiler"
]

var _saved_settings_path: String = ""


func before_all() -> void:
	for relative in ["library.json", "assets/catalog.json", "biomes/meadow.json"]:
		DirAccess.make_dir_recursive_absolute(MINI.path_join(relative).get_base_dir())
		var text := FileAccess.get_file_as_string(MINI_SRC.path_join(relative))
		var file := FileAccess.open(MINI.path_join(relative), FileAccess.WRITE)
		file.store_string(text)
		file.close()
	_write_glb("assets/tree/Tree_Oak_v0.glb", "Tree_Oak_v0_LOD0")
	_write_glb("assets/tree/Tree_Oak_v1.glb", "Tree_Oak_v1_LOD0")
	_write_glb("assets/rock/Rock_Stone_v0.glb", "Rock_Stone_v0_LOD0")
	_write_base()
	_saved_settings_path = LibraryRegistry.settings_path
	LibraryRegistry.settings_path = SETTINGS


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings_path
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	_remove_tree(ROOT)


func before_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	DirAccess.remove_absolute(SETTINGS)


# ---- fixtures ----


func _write_glb(relative: String, node_name: String) -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0.5, 0, 0.2), Vector3(0, 2, 0.1)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var root := Node3D.new()
	root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	DirAccess.make_dir_recursive_absolute(MINI.path_join(relative).get_base_dir())
	document.write_to_filesystem(state, MINI.path_join(relative))
	root.free()


## A palette root of its own: one surface (`grass`) and a forest biome the library must leave be.
func _write_base() -> void:
	DirAccess.make_dir_recursive_absolute(BASE)
	var surface := {
		"albedo": "surfaces/grass/albedo.png",
		"normal": "surfaces/grass/normal.png",
		"orm": "surfaces/grass/orm.png",
		"height": "surfaces/grass/height.png",
		"tile_m": 2.0,
		"kind": "grass",
		"role": "ground",
	}
	var rule := {
		"key": "oak",
		"kind": "tree",
		"size_class": "large",
		"density_per_m2": 0.01,
		"assets": ["forest_summer_s1/Oak"],
	}
	var document := {
		"format": 1,
		"palette_version": "base",
		"surfaces": {"grass": surface},
		"biomes":
		[
			{
				"id": "forest_summer_s1",
				"biome": "forest",
				"season": "summer",
				"seed": 1,
				"name": "Forest",
				"ground_surface": "grass",
				"species": [rule],
			}
		],
		"assets":
		{
			"forest_summer_s1/Oak":
			{
				"file": "assets/forest_summer_s1/Oak.glb",
				"node": "Oak",
				"wind_category": "tree",
				"size_class": "large",
				"dimensions_m": [5, 7, 5],
			}
		},
	}
	var file := FileAccess.open(BASE.path_join("palette.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _surfaces() -> Dictionary:
	return PaletteLibrary.get_palette(BASE)["surfaces"]


## The mini library as mutable parts (parsed "library", "catalog" and "biome"; its GLB paths are
## not needed, the compile does not check files).
func _parts() -> Dictionary:
	var sources := LibraryRegistry.read_sources(MINI)
	return {
		"library": JSON.parse_string(sources["library"]),
		"catalog": JSON.parse_string(sources["catalog"]),
		"biome": JSON.parse_string(sources["biomes"]["meadow.json"]),
	}


## LibraryReader's result for `parts` (the unedited mini library when none are given).
func _mini_read(parts: Dictionary = {}) -> Dictionary:
	if parts.is_empty():
		parts = _parts()
	return (
		LibraryReader
		. read(
			{
				"library": JSON.stringify(parts["library"]),
				"catalog": JSON.stringify(parts["catalog"]),
				"biomes": {String(parts["biome"]["id"]) + ".json": JSON.stringify(parts["biome"])},
			}
		)
	)


func _normal(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _rule(compiled: Dictionary, key: String) -> Dictionary:
	for rule: Dictionary in compiled["palette"]["biomes"][0]["species"]:
		if rule["key"] == key:
			return rule
	return {}


# ---- the savanna golden ----


func test_savanna_compiles_to_the_frozen_golden_with_no_warnings() -> void:
	var sources := LibraryRegistry.read_sources(SAVANNA)
	sources.erase("files")
	var read := LibraryReader.read(sources)
	assert_eq(read["errors"], [])
	assert_eq(read["warnings"], [])
	var surfaces: Dictionary = PaletteLibrary.get_palette()["surfaces"]
	var compiled := BiomeCompiler.compile(read, {"surfaces": surfaces})
	assert_eq(compiled["warnings"], [], "no compile warnings")
	assert_eq(compiled["palette_warnings"], [], "validate_palette: zero warnings")
	assert_eq(compiled["biome_ids"], ["savanna_summer_s1"])
	var palette: Dictionary = (compiled["palette"] as Dictionary).duplicate()
	palette.erase("surfaces")
	var version := String(palette["palette_version"])
	palette.erase("palette_version")
	assert_true(version.begins_with("core@1.0.0-dev"), version)
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	golden.erase("palette_version")
	assert_eq(JSON.stringify(_normal(palette), "", true), JSON.stringify(golden, "", true))
	assert_eq((palette["biomes"][0]["species"] as Array).size(), 13)
	assert_eq((palette["assets"] as Dictionary).size(), 34)


func test_the_compiled_savanna_validates_into_the_palette_without_losing_a_rule() -> void:
	var sources := LibraryRegistry.read_sources(SAVANNA)
	sources.erase("files")
	var compiled := BiomeCompiler.compile(
		LibraryReader.read(sources), {"surfaces": PaletteLibrary.get_palette()["surfaces"]}
	)
	var validated := PaletteLibrary.validate_palette(compiled["palette"])
	assert_eq(validated["warnings"], [])
	var biome: Dictionary = validated["palette"]["biomes"][0]
	assert_eq(biome["id"], "savanna_summer_s1")
	assert_eq((biome["species"] as Array).size(), 13)
	assert_eq((validated["palette"]["assets"] as Dictionary).size(), 34)


func test_role_and_habit_ride_in_the_compiled_form_only() -> void:
	var sources := LibraryRegistry.read_sources(SAVANNA)
	sources.erase("files")
	var compiled := BiomeCompiler.compile(LibraryReader.read(sources), {})
	var acacia := _rule(compiled, "acacia")
	assert_eq(acacia["role"], "canopy_tree")
	assert_eq(acacia["habit"], {"water": "", "charred": false})
	assert_eq(acacia["library"], "core")
	# validate_palette is a whitelist: until the step that reads role and habit extends it (S2),
	# the served rule does not carry them.
	var served: Dictionary = PaletteLibrary.validate_palette(compiled["palette"])["palette"]
	assert_false((served["biomes"][0]["species"][0] as Dictionary).has("role"))
	assert_false((served["biomes"][0]["species"][0] as Dictionary).has("habit"))


# ---- the mini library, non-core ----


func test_the_mini_library_compiles_with_the_library_prefix() -> void:
	var compiled := BiomeCompiler.compile(_mini_read(), {"folder": MINI, "surfaces": _surfaces()})
	assert_eq(compiled["warnings"], [])
	assert_eq(compiled["palette_warnings"], [])
	assert_eq(compiled["library"], "mini")
	assert_eq(compiled["biome_ids"], [RUNTIME])
	var biome: Dictionary = compiled["palette"]["biomes"][0]
	assert_eq(biome["id"], RUNTIME)
	assert_eq(biome["biome"], "mini__meadow", "the biome field is prefixed too")
	assert_eq(biome["season"], "summer")
	assert_eq(biome["seed"], 1)
	assert_eq(biome["ground_surface"], "grass")
	assert_eq(biome["thumbnail"], "thumbnails/meadow_summer_s1.jpg")
	var assets: Dictionary = compiled["palette"]["assets"]
	assert_eq(
		assets.keys(),
		[RUNTIME + "/Tree_Oak_v0", RUNTIME + "/Tree_Oak_v1", RUNTIME + "/Rock_Stone_v0"]
	)
	assert_eq(
		assets[RUNTIME + "/Tree_Oak_v0"]["file"], "assets/tree/Tree_Oak_v0.glb", "library-relative"
	)
	assert_eq(
		compiled["paths"][RUNTIME + "/Rock_Stone_v0"], MINI + "/assets/rock/Rock_Stone_v0.glb"
	)
	assert_eq(compiled["palette"]["palette_version"], "mini@0.1.0")


func test_defaults_come_from_the_role_and_class() -> void:
	var compiled := BiomeCompiler.compile(_mini_read(), {})
	var stones := _rule(compiled, "stones")
	assert_eq(stones["kind"], "rock")
	assert_eq(stones["size_class"], "small", "the role's class")
	assert_eq(stones["align"], "normal", "rocks lie on the slope")
	assert_eq(stones["yaw_random_deg"], 360.0, "the class default")
	assert_eq(stones["min_spacing_m"], 0.25, "spacing_m renamed")
	assert_eq(stones["scale_floor"], 0.5)
	assert_null(stones["pattern"])
	assert_eq(stones["habit"], {"water": "", "charred": false})
	var oak := _rule(compiled, "oak")
	assert_eq(oak["kind"], "tree")
	assert_null(oak["scale_floor"])
	assert_null(oak["clump"])


func test_a_role_relation_expands_to_every_rule_of_that_role() -> void:
	var compiled := BiomeCompiler.compile(_mini_read(), {})
	var near: Array = _rule(compiled, "stones")["near"]
	assert_eq(near.size(), 1)
	assert_eq(near[0]["species"], "oak")
	assert_eq(near[0]["distance_m"], 3)
	assert_false(near[0].has("role"))
	assert_false(near[0].has("rule"))


func test_a_missing_density_takes_the_class_default_with_a_warning() -> void:
	var parts := _parts()
	parts["biome"]["rules"][0].erase("density_per_m2")
	parts["biome"]["rules"][0]["density_factor"] = 2.0
	var compiled := BiomeCompiler.compile(_mini_read(parts), {})
	assert_almost_eq(float(_rule(compiled, "oak")["density_per_m2"]), 0.04, 1e-9)
	assert_true(compiled["warnings"].any(func(w: String) -> bool: return "class default" in w))


# ---- hostile and malformed ----


func test_a_ref_missing_from_the_catalog_is_skipped_with_a_warning() -> void:
	var parts := _parts()
	parts["biome"]["rules"][0]["query"]["match"].append({"ref": "Tree_Ghost_v9"})
	var read := _mini_read(parts)
	assert_true(read["ok"], "the reader does not cross-check refs")
	var compiled := BiomeCompiler.compile(read, {})
	assert_true(compiled["warnings"].any(func(w: String) -> bool: return "Tree_Ghost_v9" in w))
	assert_eq(_rule(compiled, "oak")["assets"].size(), 2, "the real refs stay")


func test_a_rule_whose_refs_all_miss_is_dropped_and_a_biome_with_none_is_skipped() -> void:
	var one := _parts()
	one["biome"]["rules"][1]["query"]["match"] = [{"ref": "Nope"}]
	var compiled := BiomeCompiler.compile(_mini_read(one), {})
	assert_eq((compiled["palette"]["biomes"][0]["species"] as Array).size(), 1)
	assert_true(compiled["warnings"].any(func(w: String) -> bool: return "no asset resolves" in w))
	var all := _parts()
	for rule: Dictionary in all["biome"]["rules"]:
		rule["query"]["match"] = [{"ref": "Nope"}]
	var none := BiomeCompiler.compile(_mini_read(all), {})
	assert_eq(none["biome_ids"], [])
	assert_eq(none["palette"]["biomes"], [])
	assert_true(none["warnings"].any(func(w: String) -> bool: return "skipped" in w))


func test_an_asset_id_over_the_palette_cap_is_skipped() -> void:
	# Longest legal parts everywhere: 32 + 2 + 48 + 1 + 16 + 3 + 1 + 64 is over the palette's 160.
	var parts := _parts()
	parts["library"]["id"] = "l".repeat(32)
	parts["biome"]["id"] = "b".repeat(48)
	parts["biome"]["seasons"][0]["id"] = "s".repeat(16)
	parts["catalog"]["assets"][0]["id"] = "A".repeat(64)
	parts["biome"]["rules"][0]["query"]["match"] = [{"ref": "A".repeat(64)}, {"ref": "Tree_Oak_v1"}]
	var read := _mini_read(parts)
	assert_true(read["ok"], str(read["errors"]))
	var compiled := BiomeCompiler.compile(read, {})
	assert_true(compiled["warnings"].any(func(w: String) -> bool: return "too long" in w))
	assert_gt((compiled["palette"]["assets"] as Dictionary).size(), 0, "the short ref stays")
	for asset_id: String in compiled["palette"]["assets"]:
		assert_lt(asset_id.length(), PaletteLibrary.MAX_ID_LENGTH)


func test_a_relation_to_a_dropped_rule_is_dropped() -> void:
	var parts := _parts()
	parts["biome"]["rules"][1]["avoid"] = [{"rule": "oak"}]
	parts["biome"]["rules"][0]["query"]["match"] = [{"ref": "Nope"}]
	var compiled := BiomeCompiler.compile(_mini_read(parts), {})
	var stones := _rule(compiled, "stones")
	assert_eq(stones["avoid"], [])
	assert_eq(stones["near"], [], "the role relation found the dropped rule")
	assert_true(compiled["warnings"].any(func(w: String) -> bool: return "relation" in w))


func test_a_library_that_did_not_read_cleanly_compiles_to_nothing() -> void:
	var compiled := BiomeCompiler.compile({"ok": false}, {})
	assert_eq(compiled["palette"], {})
	assert_eq(compiled["biome_ids"], [])
	assert_eq((compiled["warnings"] as Array).size(), 1)


func test_two_seasons_get_their_own_asset_prefixes() -> void:
	var parts := _parts()
	parts["biome"]["seasons"].append({"id": "winter", "seed": 2})
	var compiled := BiomeCompiler.compile(_mini_read(parts), {"surfaces": _surfaces()})
	assert_eq(compiled["biome_ids"], [RUNTIME, "mini__meadow_winter_s2"])
	assert_true(compiled["palette"]["assets"].has("mini__meadow_winter_s2/Tree_Oak_v0"))
	assert_eq(compiled["palette_warnings"], [])
	for biome: Dictionary in compiled["palette"]["biomes"]:
		for rule: Dictionary in biome["species"]:
			for asset_id: String in rule["assets"]:
				assert_eq(asset_id.get_slice("/", 0), biome["id"], "live edits need this prefix")


# ---- the registry ----


func test_the_dev_override_is_off_by_default_and_changes_nothing() -> void:
	assert_eq(LibraryRegistry.dev_override(), "")
	assert_false(LibraryRegistry.has_override())
	var before := PaletteLibrary.get_palette(BASE)
	var result := LibraryRegistry.apply(BASE)
	assert_true(result["ok"])
	assert_false(result["applied"])
	assert_same(PaletteLibrary.get_palette(BASE), before)
	assert_eq(LibraryRegistry.served(), {})


func test_apply_lays_the_library_over_the_palette_and_loads_its_glbs() -> void:
	LibraryRegistry.set_dev_override(MINI)
	var result := LibraryRegistry.apply(BASE)
	assert_true(result["ok"], str(result["error"]))
	assert_true(result["applied"])
	assert_eq(result["library"], "mini")
	assert_eq(result["biomes"], [RUNTIME])
	assert_eq(result["report"]["parsed"].size(), 3)
	assert_eq(result["report"]["failed"], [])
	var ids := PaletteLibrary.biomes(BASE).map(func(b: Dictionary) -> String: return b["id"])
	assert_eq(ids, ["forest_summer_s1", RUNTIME], "another biome is left alone")
	var species := PaletteLibrary.species(RUNTIME, BASE)
	assert_eq(species.size(), 2)
	assert_eq(species[0]["height_m"], 8.0, "dimensions travel with the assets")
	var resolved := PaletteLibrary.resolve(RUNTIME + "/Tree_Oak_v0", BASE)
	assert_false(resolved.is_empty(), "the GLB loads from the library folder")
	assert_true(resolved["mesh"] is Mesh)
	assert_eq(resolved["wind_category"], "tree")
	assert_eq(LibraryRegistry.served()["mini"]["biome_ids"], [RUNTIME])
	assert_eq(LibraryRegistry.served()["mini"]["assets"], 3)


func test_a_compiled_core_biome_replaces_the_palettes_biome_of_that_id() -> void:
	# The mini library renamed to core with a biome named forest: the merge rule is the
	# overlay's, per runtime id.
	var folder := ROOT + "/as_core"
	for relative in ["library.json", "assets/catalog.json", "biomes/forest.json"]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(relative).get_base_dir())
	var library: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(MINI + "/library.json")
	)
	library["id"] = "core"
	var biome: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(MINI + "/biomes/meadow.json")
	)
	biome["id"] = "forest"
	var writes := {
		"library.json": library,
		"assets/catalog.json":
		JSON.parse_string(FileAccess.get_file_as_string(MINI + "/assets/catalog.json")),
		"biomes/forest.json": biome,
	}
	for relative: String in writes:
		var file := FileAccess.open(folder.path_join(relative), FileAccess.WRITE)
		file.store_string(JSON.stringify(writes[relative]))
		file.close()
	for glb in [
		"assets/tree/Tree_Oak_v0.glb",
		"assets/tree/Tree_Oak_v1.glb",
		"assets/rock/Rock_Stone_v0.glb"
	]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(glb).get_base_dir())
		DirAccess.copy_absolute(MINI.path_join(glb), folder.path_join(glb))
	LibraryRegistry.set_dev_override(folder)
	var result := LibraryRegistry.apply(BASE)
	assert_true(result["ok"], str(result["error"]))
	assert_eq(result["biomes"], ["forest_summer_s1"], "core ids carry no prefix")
	var assets: Dictionary = PaletteLibrary.get_palette(BASE)["assets"]
	assert_false(assets.has("forest_summer_s1/Oak"), "the replaced biome's own assets went")
	assert_true(assets.has("forest_summer_s1/Tree_Oak_v0"))
	assert_eq(PaletteLibrary.biomes(BASE).size(), 1)
	_remove_tree(folder)


func test_a_broken_library_changes_nothing_and_says_why() -> void:
	var before := PaletteLibrary.get_palette(BASE)
	LibraryRegistry.set_dev_override(ROOT + "/no_such_library")
	var missing := LibraryRegistry.apply(BASE)
	assert_false(missing["ok"])
	assert_string_contains(String(missing["error"]), "not a folder")
	assert_same(PaletteLibrary.get_palette(BASE), before)
	LibraryRegistry.set_dev_override(BASE)
	var wrong := LibraryRegistry.apply(BASE)
	assert_false(wrong["ok"], "a palette folder is not a library")
	assert_string_contains(String(wrong["error"]), "library.json")
	assert_same(PaletteLibrary.get_palette(BASE), before)
	assert_eq(LibraryRegistry.served(), {})


func test_the_saved_dev_path_comes_from_settings_unless_one_is_set() -> void:
	assert_eq(LibraryRegistry.saved_dev_path(), "")
	var config := ConfigFile.new()
	config.set_value(LibraryRegistry.SECTION, LibraryRegistry.KEY_DEV_PATH, MINI)
	config.save(SETTINGS)
	assert_eq(LibraryRegistry.saved_dev_path(), MINI)
	LibraryRegistry.use_saved_override()
	assert_eq(LibraryRegistry.dev_override(), MINI)
	LibraryRegistry.set_dev_override("elsewhere")
	LibraryRegistry.use_saved_override()
	assert_eq(LibraryRegistry.dev_override(), "elsewhere", "a run override wins")


func test_the_foliage_library_layers_the_content_library_and_drops_it_again() -> void:
	LibraryRegistry.set_dev_override(MINI)
	var applied := FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	assert_true(applied["ok"])
	assert_true(applied["content_library"]["applied"])
	assert_true(PaletteLibrary.get_palette(BASE)["assets"].has(RUNTIME + "/Tree_Oak_v0"))
	LibraryRegistry.clear()
	FoliageLibrary.apply(FoliageLibrary.TREECUBE, "", BASE)
	assert_false(PaletteLibrary.get_palette(BASE)["assets"].has(RUNTIME + "/Tree_Oak_v0"))
	assert_eq(PaletteLibrary.biomes(BASE).size(), 1)


# ---- the architecture rules ----


func test_the_pure_modules_touch_no_files_or_scene_tree() -> void:
	var forbidden := [
		"FileAccess",
		"DirAccess",
		"EventBus",
		"ResourceLoader",
		"get_tree",
		"Node3D",
		"load(",
		"preload("
	]
	for module in PURE_MODULES:
		var path := "res://utils/library/%s.gd" % module
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var stripped := line.strip_edges()
			if not stripped.begins_with("#"):
				code += line + "\n"
		for word: String in forbidden:
			assert_false(word in code, "%s must not use %s" % [module, word])


func test_only_the_registry_lists_folders() -> void:
	var offenders: Array[String] = []
	for file_name in DirAccess.get_files_at("res://utils/library"):
		if not file_name.ends_with(".gd") or file_name == "library_registry.gd":
			continue
		if "DirAccess" in FileAccess.get_file_as_string("res://utils/library/" + file_name):
			offenders.append(file_name)
	assert_eq(offenders, [])
