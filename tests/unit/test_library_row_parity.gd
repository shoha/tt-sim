extends GutTest

## The library route against the package route (design doc 6.1, step S5), kept alive by step S10.
##
## Two proofs. (1) The miniature: a core-shaped library and the package it was built from, in a
## scratch folder, with renamed ids and surfaces by name, must give byte-identical rows, the same
## rules, biome fields and assets table once the library's asset ids are mapped back to the
## package's stems through the catalog's `package_stem`. (2) The shipped core library
## (res://libraries/core, served as the palette) must reproduce the plantgen package route it was
## built from: tests/fixtures/library_core_golden.json freezes, per biome of the nine, the package
## route's biome fields, rules, plan roles, scatter rows at seed 1234 over a fixed square and
## assets table, computed on 2026-10-25 from plantgen's out/lib_core_pkg2 laid over the retired
## treecube palette by the retired overlay code, BEFORE that code was deleted (byte-identical to
## the library route then: 2074 assertions). No plantgen folder is needed any more. The technique
## is scatter_golden.gd's (a varying painted density, flat ground); the digests are Windows' bytes.
## Re-freeze the fixture only for a deliberate rebuild of core, after comparing it with the new
## package it came from.

const Compare := preload("res://tests/unit/library_route_compare.gd")
const World := preload("res://tests/unit/library_world.gd")

const GOLDEN := "res://tests/fixtures/library_core_golden.json"
const CORE_FOLDER := "res://libraries/core"
const ROOT := "user://test_library_row_parity"
const BASE := ROOT + "/base"
const PACKAGE := ROOT + "/package"
const LIBRARY := ROOT + "/core"
const SETTINGS := ROOT + "/settings.cfg"
const MINI_RUNTIME := "meadow_summer_s1"
const SURFACE_SRC := "res://tests/fixtures/library_surfaces/surfaces"

var _saved_settings_path: String = ""
var _saved_official: String = ""


func before_all() -> void:
	_saved_settings_path = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	LibraryRegistry.settings_path = SETTINGS
	# The miniature's library is core-shaped (id core): the shipped core is not part of it.
	LibraryRegistry.official_root = ROOT + "/no_official"


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings_path
	LibraryRegistry.official_root = _saved_official
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


## The package route: the package's palette.json laid over the palette under `root`, as the retired
## PaletteLibrary.overlay_package did (validate, replace the biomes of the same id with their
## assets; GLBs are not read, the comparison needs none).
func _lay_package(package: String, root: String) -> void:
	var text := FileAccess.get_file_as_string(package.path_join("palette.json"))
	var raw: Dictionary = JSON.parse_string(text)
	var report := PaletteLibrary.install_overlay(
		LibraryLayer.lay(raw, PaletteLibrary.base_for_serving(root)), root
	)
	assert_true(report["ok"], str(report["error"]))


## Both routes over `runtimes`: the package laid on `root`, then the library laid by the
## registry as the developer override. Returns [package snapshot, mapped library snapshot].
func _both_routes(package: String, library: String, root: String, runtimes: Array) -> Array:
	_lay_package(package, root)
	var from_package := Compare.snapshot(root, runtimes)
	PaletteLibrary.clear_cache()
	LibraryRegistry.set_dev_override(library)
	var applied := LibraryRegistry.apply(root)
	assert_true(applied["ok"], str(applied["error"]))
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


# ---- the shipped core against the frozen package route ----


## `value` after a JSON round trip, the form the golden fixture holds.
func _through_json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true))


func test_the_shipped_core_reproduces_the_frozen_package_route_for_all_nine_biomes() -> void:
	if OS.get_name() != "Windows":
		pending("row digests are Windows' float bytes")
		return
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var biomes: Dictionary = golden["biomes"]
	var runtimes: Array = biomes.keys()
	runtimes.sort()
	assert_eq(runtimes.size(), 9, "all nine biomes")
	assert_eq(int(golden["seed"]), Compare.SEED)
	var root := PaletteLibrary.DEFAULT_ROOT
	assert_eq(PaletteLibrary.get_palette(root)["biomes"].size(), 9, "core served on first read")
	var snapshot := Compare.mapped(Compare.snapshot(root, runtimes), Compare.stems_of(CORE_FOLDER))
	for runtime: String in runtimes:
		var want: Dictionary = biomes[runtime]
		var got: Dictionary = snapshot[runtime]
		var want_fields: Dictionary = want["biome"]
		var got_fields: Dictionary = _through_json(got["biome"])
		assert_eq(got_fields.keys().size(), want_fields.keys().size(), "%s: field set" % runtime)
		for field: String in want_fields:
			assert_eq(got_fields.get(field), want_fields[field], "%s: biome %s" % [runtime, field])
		var got_rules: Array = got["species"]
		var want_rules: Array = want["rules"]
		assert_eq(got_rules.size(), want_rules.size(), "%s: the same number of rules" % runtime)
		for i in mini(want_rules.size(), got_rules.size()):
			assert_eq(Compare.rule_text(got_rules[i]), want_rules[i], "%s: rule %d" % [runtime, i])
		assert_eq(Compare.plans(got_rules), want["plans"], "%s: habit" % runtime)
		var want_rows: Dictionary = want["rows"]
		assert_gt(want_rows.size(), 5, "%s grows plants" % runtime)
		assert_eq((got["rows"] as Dictionary).keys().size(), want_rows.size(), runtime + " kinds")
		var total := 0
		for asset_id: String in want_rows:
			assert_eq(got["rows"].get(asset_id), want_rows[asset_id], "%s: %s" % [runtime, asset_id])
			total += int(String(want_rows[asset_id]).get_slice(":", 0))
		var want_assets: Dictionary = want["assets"]
		for id: String in want_assets:
			var got_asset: Dictionary = snapshot["assets"].get(id, {})
			assert_false(got_asset.is_empty(), "assets table has %s" % id)
			for field in ["node", "wind_category", "size_class", "dimensions_m"]:
				assert_eq(
					_through_json(got_asset.get(field)),
					(want_assets[id] as Dictionary).get(field),
					"%s: %s" % [id, field]
				)
		gut.p(
			(
				"%s: %d rules, %d asset kinds, %d rows, byte-identical to the package route"
				% [runtime, want_rules.size(), want_rows.size(), total]
			)
		)
