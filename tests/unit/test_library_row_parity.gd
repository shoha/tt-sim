extends GutTest

## The library route against the package route (design doc 6.1, step S5): every biome generated at
## seed 1234 over a fixed square through (a) PaletteLibrary.overlay_package with plantgen's
## palette package and (b) LibraryRegistry with the library plantgen exported from the same
## package must give byte-identical rows, the same rules, the same biome fields and the same assets
## table once the library's asset ids are mapped back to the package's stems through the catalog's
## `package_stem` (a stem whose bytes differ per biome is `<stem>_<biome>` in the library). The
## technique is scatter_golden.gd's (a varying painted density, flat ground).
##
## Two tests. The miniature (always on) builds a core-shaped library and its package in a scratch
## folder, with renamed ids and surfaces by name. The real one reads the nine-biome folders outside
## this repo from environment variables and is pending when they are not set:
##   PLANTGEN_LIB_CORE      the exported library (plantgen out/lib_core)
##   PLANTGEN_LIB_CORE_PKG  the package it was built from (plantgen out/lib_core_pkg)
## Run (PowerShell):  $env:PLANTGEN_LIB_CORE='D:/dev/plantgen/out/lib_core'
##   $env:PLANTGEN_LIB_CORE_PKG='D:/dev/plantgen/out/lib_core_pkg'
##   godot --headless --path <project> --script res://addons/gut/gut_cmdln.gd --
##     '-gconfig=tests/.gutconfig.json' -gselect=test_library_row_parity
## The one-biome slice of step S1 still runs when PLANTGEN_LIB_SLICE and PLANTGEN_LIB_SLICE_PKG
## name plantgen's out/lib_slice and out/lib_slice_pkg.

const Compare := preload("res://tests/unit/library_route_compare.gd")
const World := preload("res://tests/unit/library_world.gd")

const ENV_CORE := "PLANTGEN_LIB_CORE"
const ENV_CORE_PKG := "PLANTGEN_LIB_CORE_PKG"
const ENV_SLICE := "PLANTGEN_LIB_SLICE"
const ENV_SLICE_PKG := "PLANTGEN_LIB_SLICE_PKG"
const ROOT := "user://test_library_row_parity"
const BASE := ROOT + "/base"
const PACKAGE := ROOT + "/package"
const LIBRARY := ROOT + "/core"
const SETTINGS := ROOT + "/settings.cfg"
const MINI_RUNTIME := "meadow_summer_s1"
const SURFACE_SRC := "res://tests/fixtures/library_surfaces/surfaces"

var _saved_settings_path: String = ""


func before_all() -> void:
	_saved_settings_path = LibraryRegistry.settings_path
	LibraryRegistry.settings_path = SETTINGS


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings_path
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	DirAccess.remove_absolute(SETTINGS)


func after_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


# ---- the shared comparison ----


## Asserts the package snapshot and the (already mapped) library snapshot agree for `runtimes`.
func _assert_routes_equal(package: Dictionary, library: Dictionary, runtimes: Array) -> void:
	for runtime: String in runtimes:
		var want: Dictionary = package[runtime]
		var got: Dictionary = library[runtime]
		var want_fields: Dictionary = want["biome"]
		var got_fields: Dictionary = got["biome"]
		assert_eq(got_fields.keys().size(), want_fields.keys().size(), "%s: field set" % runtime)
		for field: String in want_fields:
			assert_eq(got_fields.get(field), want_fields[field], "%s: biome %s" % [runtime, field])
		var want_rules: Array = want["species"]
		var got_rules: Array = got["species"]
		assert_eq(got_rules.size(), want_rules.size(), "%s: the same number of rules" % runtime)
		for i in mini(want_rules.size(), got_rules.size()):
			assert_eq(
				Compare.rule_text(got_rules[i]),
				Compare.rule_text(want_rules[i]),
				"%s: rule %s" % [runtime, want_rules[i].get("key")]
			)
		assert_eq(Compare.plans(got_rules), Compare.plans(want_rules), "%s: habit" % runtime)
		assert_gt(
			(want["rows"] as Dictionary).size(), 0, "%s: the package route grows plants" % runtime
		)
		assert_eq((got["rows"] as Dictionary).keys().size(), (want["rows"] as Dictionary).size())
		for asset_id: String in want["rows"]:
			assert_eq(
				got["rows"].get(asset_id), want["rows"][asset_id], "%s: %s" % [runtime, asset_id]
			)
	var want_assets: Dictionary = package["assets"]
	var got_assets: Dictionary = library["assets"]
	for runtime: String in runtimes:
		for id: String in want_assets:
			if not id.begins_with(runtime + "/"):
				continue
			assert_true(got_assets.has(id), "assets table has %s" % id)
			for field in ["node", "wind_category", "size_class", "dimensions_m"]:
				assert_eq(
					(got_assets.get(id, {}) as Dictionary).get(field),
					(want_assets[id] as Dictionary).get(field),
					"%s: %s" % [id, field]
				)


## Both routes over `runtimes`: the package overlaid on `root`, then the library laid by the
## registry as the developer override. Returns [package snapshot, mapped library snapshot].
func _both_routes(
	package: String, library: String, root: String, runtimes: Array, overlay_only: Array = []
) -> Array:
	var overlay := PaletteLibrary.overlay_package(package, root, overlay_only)
	assert_true(overlay["ok"], str(overlay["error"]))
	var from_package := Compare.snapshot(root, runtimes)
	PaletteLibrary.clear_cache()
	LibraryRegistry.set_dev_override(library)
	var applied := LibraryRegistry.apply(root)
	assert_true(applied["ok"], str(applied["error"]))
	assert_eq(applied["report"]["failed"], [], "every GLB parsed")
	assert_eq(applied["warnings"], [], "no read, compile or palette warnings")
	assert_eq((applied["biomes"] as Array).size(), runtimes.size())
	var from_library := Compare.snapshot(root, runtimes)
	return [from_package, Compare.mapped(from_library, Compare.stems_of(library))]


# ---- the miniature, always on ----


func test_a_core_shaped_library_equals_its_package_with_renamed_ids() -> void:
	_write_mini_world()
	var both := _both_routes(PACKAGE, LIBRARY, BASE, [MINI_RUNTIME])
	_assert_routes_equal(both[0], both[1], [MINI_RUNTIME])
	var rows: Dictionary = both[1][MINI_RUNTIME]["rows"]
	assert_true(rows.has(MINI_RUNTIME + "/Tree_Oak_v0"), "mapped back to the package stem")
	var served: Array = LibraryRegistry.served().keys()
	assert_eq(served, ["core"])


func test_the_library_ids_differ_from_the_package_stems() -> void:
	_write_mini_world()
	var stems := Compare.stems_of(LIBRARY)
	assert_eq(stems["Tree_Oak_v0_meadow"], "Tree_Oak_v0")
	assert_eq(stems["Tree_Oak_v1"], "Tree_Oak_v1", "an unchanged stem keeps its name")
	assert_eq(
		Compare.package_id("meadow_summer_s1/Tree_Oak_v0_meadow", stems),
		MINI_RUNTIME + "/Tree_Oak_v0"
	)
	assert_eq(Compare.package_id("meadow_summer_s1/Unknown", stems), MINI_RUNTIME + "/Unknown")


## A core-shaped library (id core, surfaces by name, a thumbnail, bindings, ids renamed where a
## stem differs per biome) and the package route's twin of it, under ROOT.
func _write_mini_world() -> void:
	World.remove_tree(ROOT)
	World.write_base(BASE)
	World.edit_json(BASE.path_join("palette.json"), _extend_base)
	_write_package()
	_write_library()


func _extend_base(document: Dictionary) -> void:
	(document["surfaces"] as Dictionary).merge(_surface_table())


## The installed form of the four surfaces the library carries as folders.
func _surface_table() -> Dictionary:
	var surfaces := {}
	for entry in [
		["lilac", "ground", 3.0],
		["dune", "ground", 3.0],
		["slate", "cliff", 5.0],
		["boards", "built", 2.0]
	]:
		var name: String = entry[0]
		surfaces[name] = {
			"albedo": "surfaces/%s/albedo.png" % name,
			"normal": "surfaces/%s/normal.png" % name,
			"orm": "surfaces/%s/orm.png" % name,
			"height": "surfaces/%s/height.png" % name,
			"tile_m": entry[2],
			"kind": name,
			"role": entry[1],
		}
	return surfaces


func _tree_rule() -> Dictionary:
	return {
		"key": "oak",
		"role": "canopy_tree",
		"size_class": "large",
		"weight": 1,
		"density_per_m2": 0.01,
		"spacing_m": 4.5,
		"slope_max_deg": 35,
		"scale_spread": 0.15,
		"scale_floor": null,
		"yaw_random_deg": 360,
		"align": "upright",
		"pattern": null,
		"clump": null,
		"near": [],
		"avoid": [],
		"habit": {"water": "", "charred": false},
		"query":
		{
			"match": [{"ref": "Tree_Oak_v0_meadow"}, {"ref": "Tree_Oak_v1"}],
			"count": "all",
			"order": "explicit"
		},
	}


func _stone_rule() -> Dictionary:
	return {
		"key": "stones",
		"role": "stones",
		"weight": 1,
		"density_per_m2": 0.06,
		"spacing_m": 0.25,
		"slope_max_deg": 55,
		"scale_spread": 0.3,
		"scale_floor": 0.5,
		"yaw_random_deg": 360,
		"align": "upright",
		"clump":
		{"children_spacing_m": 0.25, "parents_per_m2": 0.05, "radius_m": 1.2, "transition_m": 0.8},
		"near": [{"role": "canopy_tree", "distance_m": 3, "influence": 0.4, "transition_m": 2}],
		"avoid": [],
		"query": {"match": [{"ref": "Rock_Stone_v0_meadow"}], "count": "all", "order": "explicit"},
	}


func _write_library() -> void:
	var assets := [
		{
			"id": "Tree_Oak_v0_meadow",
			"stem": "Tree_Oak_v0",
			"category": "tree",
			"wind": "tree",
			"size": "large"
		},
		{
			"id": "Tree_Oak_v1",
			"stem": "Tree_Oak_v1",
			"category": "tree",
			"wind": "tree",
			"size": "large"
		},
		{
			"id": "Rock_Stone_v0_meadow",
			"stem": "Rock_Stone_v0",
			"category": "rock",
			"wind": "",
			"size": "small"
		},
	]
	var entries: Array = []
	for item: Dictionary in assets:
		var relative := "assets/%s/%s.glb" % [item["category"], item["id"]]
		World.write_glb(LIBRARY.path_join(relative), "%s_LOD0" % item["stem"])
		var bytes := FileAccess.get_file_as_bytes(LIBRARY.path_join(relative))
		(
			entries
			. append(
				{
					"id": item["id"],
					"package_stem": item["stem"],
					"category": item["category"],
					"wind_category": item["wind"],
					"size_class": item["size"],
					"dimensions_m": [2.0, 4.0, 2.0],
					"file": relative,
					"node": "%s_LOD0" % item["stem"],
					"bytes": bytes.size(),
					"sha256": World.sha256_of(bytes),
				}
			)
		)
	World.write_json(
		LIBRARY.path_join("assets/catalog.json"),
		{"format": "ttsim-catalog", "format_version": 1, "assets": entries}
	)
	(
		World
		. write_json(
			LIBRARY.path_join("library.json"),
			{
				"format": "ttsim-library",
				"format_version": 1,
				"id": "core",
				"name": "Core",
				"version": "1.0.0-dev",
				"contract": 1,
				"license": "CC0-1.0",
				"dependencies": [],
				"default_biome": "meadow",
				"bindings": {"paint": {"default": "boards"}, "fire": {"ash_surface": "slate"}},
			}
		)
	)
	(
		World
		. write_json(
			LIBRARY.path_join("biomes/meadow.json"),
			{
				"format": "ttsim-biome",
				"format_version": 1,
				"id": "meadow",
				"name": "Meadow",
				"climate": "temperate",
				"surfaces": "library",
				"thumbnail": "thumbnails/meadow.jpg",
				"seasons": [{"id": "summer", "seed": 1}],
				"ground":
				{
					"surface": "lilac",
					"cliff": "slate",
					"accents": [{"surface": "dune", "coverage": 0.1, "scale_m": 6}],
					"paths": ["boards"],
				},
				"rules": [_tree_rule(), _stone_rule()],
			}
		)
	)
	for pair in [["lilac", "lilac"], ["dune", "lilac"], ["slate", "slate"], ["boards", "boards"]]:
		for file in ["albedo.png", "normal.png", "orm.png", "height.png", "surface.json"]:
			var bytes := FileAccess.get_file_as_bytes("%s/%s/%s" % [SURFACE_SRC, pair[1], file])
			World.write_bytes(LIBRARY.path_join("surfaces/%s/%s" % [pair[0], file]), bytes)
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.5, 0.2))
	DirAccess.make_dir_recursive_absolute(LIBRARY.path_join("thumbnails"))
	image.save_jpg(LIBRARY.path_join("thumbnails/meadow.jpg"))


func _write_package() -> void:
	var assets := {}
	for entry in [
		["Tree_Oak_v0", "tree", "large"],
		["Tree_Oak_v1", "tree", "large"],
		["Rock_Stone_v0", "", "small"]
	]:
		var id := "%s/%s" % [MINI_RUNTIME, entry[0]]
		var file := "assets/%s/%s.glb" % [MINI_RUNTIME, entry[0]]
		World.write_glb(PACKAGE.path_join(file), "%s_LOD0" % entry[0])
		assets[id] = {
			"file": file,
			"node": "%s_LOD0" % entry[0],
			"wind_category": entry[1],
			"size_class": entry[2],
			"dimensions_m": [2.0, 4.0, 2.0],
		}
	var oak := {
		"key": "oak",
		"kind": "tree",
		"size_class": "large",
		"density_per_m2": 0.01,
		"min_spacing_m": 4.5,
		"slope_max_deg": 35,
		"scale_spread": 0.15,
		"scale_floor": null,
		"yaw_random_deg": 360,
		"align": "upright",
		"clump": null,
		"pattern": null,
		"near": [],
		"avoid": [],
		"assets": [MINI_RUNTIME + "/Tree_Oak_v0", MINI_RUNTIME + "/Tree_Oak_v1"],
	}
	var stones := {
		"key": "stones",
		"kind": "rock",
		"size_class": "small",
		"density_per_m2": 0.06,
		"min_spacing_m": 0.25,
		"slope_max_deg": 55,
		"scale_spread": 0.3,
		"scale_floor": 0.5,
		"yaw_random_deg": 360,
		"align": "upright",
		"clump":
		{"children_spacing_m": 0.25, "parents_per_m2": 0.05, "radius_m": 1.2, "transition_m": 0.8},
		"near": [{"species": "oak", "distance_m": 3, "influence": 0.4, "transition_m": 2}],
		"avoid": [],
		"assets": [MINI_RUNTIME + "/Rock_Stone_v0"],
	}
	(
		World
		. write_json(
			PACKAGE.path_join("palette.json"),
			{
				"format": 1,
				"palette_version": "pkg",
				"surfaces": _surface_table(),
				"biomes":
				[
					{
						"id": MINI_RUNTIME,
						"biome": "meadow",
						"season": "summer",
						"seed": 1,
						"name": "Meadow",
						"climate": "temperate",
						"ground_surface": "lilac",
						"cliff_surface": "slate",
						"scree_surface": "",
						"ground_accents": [{"surface": "dune", "coverage": 0.1, "scale_m": 6}],
						"path_surfaces": ["boards"],
						"thumbnail": "thumbnails/%s.jpg" % MINI_RUNTIME,
						"species": [oak, stones],
					}
				],
				"assets": assets,
			}
		)
	)


# ---- the real folders, pending without them ----


func test_all_nine_biomes_of_the_library_equal_the_package_route() -> void:
	var library := OS.get_environment(ENV_CORE)
	var package := OS.get_environment(ENV_CORE_PKG)
	if library == "" or package == "":
		pending("set %s and %s to run the nine-biome parity" % [ENV_CORE, ENV_CORE_PKG])
		return
	if OS.get_name() != "Windows":
		pending("row digests are Windows' float bytes")
		return
	var palette: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(package.path_join("palette.json"))
	)
	var runtimes: Array = []
	for entry: Dictionary in palette["biomes"]:
		runtimes.append(String(entry["id"]))
	runtimes.sort()
	assert_eq(runtimes.size(), 9, "all nine biomes")
	var both := _both_routes(package, library, PaletteLibrary.DEFAULT_ROOT, runtimes)
	_assert_routes_equal(both[0], both[1], runtimes)
	for runtime: String in runtimes:
		var rows: Dictionary = both[0][runtime]["rows"]
		assert_gt(rows.size(), 5, runtime + " grows plants")
		var total := 0
		for digest: String in rows.values():
			total += int(digest.get_slice(":", 0))
		gut.p(
			(
				"%s: %d rules, %d asset kinds, %d rows, byte-identical"
				% [runtime, (both[0][runtime]["species"] as Array).size(), rows.size(), total]
			)
		)


func test_savanna_slice_equals_the_package_route() -> void:
	var library := OS.get_environment(ENV_SLICE)
	var package := OS.get_environment(ENV_SLICE_PKG)
	if library == "" or package == "":
		pending("set %s and %s to run the slice parity" % [ENV_SLICE, ENV_SLICE_PKG])
		return
	if OS.get_name() != "Windows":
		pending("row digests are Windows' float bytes")
		return
	var runtimes := ["savanna_summer_s1"]
	var both := _both_routes(package, library, PaletteLibrary.DEFAULT_ROOT, runtimes, runtimes)
	_assert_routes_equal(both[0], both[1], runtimes)
