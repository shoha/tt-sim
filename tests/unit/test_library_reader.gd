extends GutTest

## LibraryReader (utils/library/library_reader.gd): the miniature library reads clean, every
## hostile or malformed file is reported (never thrown), unknown keys warn, the S0 portable-names
## rules hold, and LibraryRegistry.read_sources hands the reader the files of a folder.

const MINI := "res://tests/fixtures/library_mini"
const MINI_GLBS: Array[String] = [
	"assets/tree/Tree_Oak_v0.glb", "assets/tree/Tree_Oak_v1.glb", "assets/rock/Rock_Stone_v0.glb"
]


## The mini library as mutable parts: parsed "library", "catalog" and "biome" dictionaries and the
## "files" list (its three GLB paths added to the JSON files the fixture holds).
func _parts() -> Dictionary:
	var sources := LibraryRegistry.read_sources(MINI)
	var files: Array = sources["files"]
	files.append_array(MINI_GLBS)
	return {
		"library": JSON.parse_string(sources["library"]),
		"catalog": JSON.parse_string(sources["catalog"]),
		"biome": JSON.parse_string(sources["biomes"]["meadow.json"]),
		"files": files,
	}


## The reader's result for `parts` packed back into sources.
func _read(parts: Dictionary) -> Dictionary:
	return (
		LibraryReader
		. read(
			{
				"library": JSON.stringify(parts["library"]),
				"catalog": JSON.stringify(parts["catalog"]),
				"biomes": {"meadow.json": JSON.stringify(parts["biome"])},
				"files": parts["files"],
			}
		)
	)


func _has(lines: Array, needle: String) -> bool:
	return lines.any(func(line: String) -> bool: return needle in line)


func test_the_mini_library_reads_clean() -> void:
	var read := _read(_parts())
	assert_eq(read["errors"], [])
	assert_eq(read["warnings"], [])
	assert_true(read["ok"])
	assert_eq(read["library"]["id"], "mini")
	assert_eq(read["catalog_order"], ["Tree_Oak_v0", "Tree_Oak_v1", "Rock_Stone_v0"])
	assert_eq((read["biomes"] as Array).size(), 1)


func test_read_sources_lists_the_folder_sorted_and_reads_the_json() -> void:
	var sources := LibraryRegistry.read_sources(MINI)
	assert_false(sources.has("error"))
	assert_eq(
		sources["files"],
		["assets/catalog.json", "biomes/meadow.json", "library.json"],
		"relative and sorted"
	)
	assert_eq((sources["biomes"] as Dictionary).keys(), ["meadow.json"])
	assert_true(String(sources["library"]).contains('"mini"'))
	assert_true(LibraryRegistry.read_sources("res://tests/fixtures/no_such_library").has("error"))
	assert_true(LibraryRegistry.read_sources("").has("error"))


func test_garbage_never_throws() -> void:
	for garbage: Variant in [
		{}, {"library": "[]"}, {"library": "{", "catalog": "null", "biomes": 3}
	]:
		var read := LibraryReader.read(garbage)
		assert_false(read["ok"])
		assert_gt((read["errors"] as Array).size(), 0)
	var parts := _parts()
	parts["library"]["id"] = 7
	parts["library"]["contract"] = "one"
	parts["library"]["dependencies"] = "none"
	parts["catalog"]["assets"] = [1, "x", null, {"id": []}]
	parts["biome"]["rules"] = [3, {"key": 5}]
	parts["biome"]["seasons"] = "summer"
	var read := _read(parts)
	assert_false(read["ok"])
	assert_gt((read["errors"] as Array).size(), 5)


func test_unknown_keys_warn_at_every_level() -> void:
	var parts := _parts()
	parts["library"]["colour"] = 1
	parts["catalog"]["extra"] = 1
	parts["catalog"]["assets"][0]["flavour"] = "x"
	parts["biome"]["new_key"] = 1
	parts["biome"]["ground"]["cliffs"] = "typo"
	parts["biome"]["rules"][0]["densty_per_m2"] = 0.1
	parts["biome"]["rules"][0]["query"]["cunt"] = 3
	parts["biome"]["rules"][0]["habit"]["wet"] = true
	var read := _read(parts)
	assert_true(read["ok"], "unknown keys are warnings, not errors: %s" % str(read["errors"]))
	for needle in [
		"colour", "extra", "flavour", "new_key", "cliffs", "densty_per_m2", "cunt", "wet"
	]:
		assert_true(_has(read["warnings"], "'%s'" % needle), "warns about %s" % needle)


func test_a_newer_format_or_contract_is_refused() -> void:
	var parts := _parts()
	parts["library"]["format_version"] = 2
	parts["library"]["contract"] = LibraryContracts.CONTRACT_VERSION + 1
	var read := _read(parts)
	assert_false(read["ok"])
	assert_true(_has(read["errors"], "format_version 2 is newer"))
	assert_true(_has(read["errors"], "written for contract"))


func test_library_ids_and_reserved_ids() -> void:
	for bad in ["legacy", "dev", "Mini", "mi__ni", "a/b"]:
		var parts := _parts()
		parts["library"]["id"] = bad
		assert_false(_read(parts)["ok"], "library id '%s'" % bad)
	var core := _parts()
	core["library"]["id"] = "core"
	assert_true(_read(core)["ok"], "core is the official id")


func test_case_insensitive_duplicates_are_errors() -> void:
	var parts := _parts()
	var twin: Dictionary = (parts["catalog"]["assets"][0] as Dictionary).duplicate(true)
	twin["id"] = "tree_oak_v0"
	twin["file"] = "assets/tree/tree_oak_v0.glb"
	parts["catalog"]["assets"].append(twin)
	var read := _read(parts)
	assert_false(read["ok"])
	assert_true(_has(read["errors"], "repeats (case-insensitively)"))
	var files := _parts()
	files["files"].append("assets/TREE/tree_oak_v0.GLB")
	assert_true(_has(_read(files)["errors"], "collides with another file"))


func test_exact_case_and_missing_files() -> void:
	var parts := _parts()
	parts["files"] = (parts["files"] as Array).filter(
		func(f: String) -> bool: return not f.ends_with("Rock_Stone_v0.glb")
	)
	parts["files"].append("assets/rock/rock_stone_v0.glb")
	var read := _read(parts)
	assert_false(read["ok"])
	assert_true(_has(read["errors"], "names are case-sensitive"), str(read["errors"]))
	var gone := _parts()
	gone["files"] = (gone["files"] as Array).filter(
		func(f: String) -> bool: return not f.ends_with("Tree_Oak_v1.glb")
	)
	assert_true(_has(_read(gone)["errors"], "does not exist"))


func test_unsafe_reserved_and_disallowed_names_are_errors() -> void:
	for file in [
		"assets/tree/con.glb",
		"assets/tree/x.",
		"assets/tree/a\\b.glb",
		"C:/x.glb",
		"../x.glb",
		"assets/tree/x.exe",
		"assets/tree/x.gd",
		"assets/tree/x.tres",
	]:
		var parts := _parts()
		parts["files"].append(file)
		assert_false(_read(parts)["ok"], "file '%s'" % file)
	for file in [
		"assets/tree/con.glb",
		"assets/tree/x.glb ",
		"/etc/x.glb",
		"assets\\x.glb",
		"assets/../x.glb",
		"assets/tree/Oak.png",
	]:
		var parts := _parts()
		parts["catalog"]["assets"][0]["file"] = file
		parts["files"].append(file)
		assert_false(_read(parts)["ok"], "catalog file '%s'" % file)


func test_over_length_and_malformed_asset_ids() -> void:
	for id in ["x".repeat(65), "a/b", "has space", "", "NUL"]:
		var parts := _parts()
		parts["catalog"]["assets"][0]["id"] = id
		assert_false(_read(parts)["ok"], "asset id '%s'" % id)


func test_catalog_fields_are_checked_against_the_contract() -> void:
	var cases := {
		"category": "plant",
		"size_class": "huge",
		"wind_category": "water",
		"dimensions_m": [1.0, -2.0, 1.0],
		"node": "",
	}
	for field: String in cases:
		var parts := _parts()
		parts["catalog"]["assets"][0][field] = cases[field]
		assert_false(_read(parts)["ok"], field)


func test_biome_def_problems() -> void:
	var cases := {
		"role": ["role", "sorcerer"],
		"size": ["size_class", "gigantic"],
		"density": ["density_per_m2", "lots"],
		"slope": ["slope_max_deg", 120],
		"habit": ["habit", {"water": "swamp"}],
		"align": ["align", "sideways"],
		"relation": ["near", [{"distance_m": 1}]],
		"relation role": ["near", [{"role": "wizard"}]],
		"empty match": ["query", {"match": []}],
		"bad ref": ["query", {"match": [{"ref": "a/b"}]}],
	}
	for label: String in cases:
		var parts := _parts()
		parts["biome"]["rules"][0][cases[label][0]] = cases[label][1]
		assert_false(_read(parts)["ok"], label)
	var no_query := _parts()
	(no_query["biome"]["rules"][0] as Dictionary).erase("query")
	assert_false(_read(no_query)["ok"], "no query")
	var repeated := _parts()
	repeated["biome"]["rules"][1]["key"] = "oak"
	assert_true(_has(_read(repeated)["errors"], "repeated"))
	var mismatch := _parts()
	mismatch["biome"]["id"] = "forest"
	assert_true(_has(_read(mismatch)["errors"], "does not match the file name"))
	var dangling := _parts()
	dangling["biome"]["rules"][1]["avoid"] = [{"rule": "ghost"}]
	var read := _read(dangling)
	assert_true(read["ok"], "a dangling relation is a warning, as the palette treats it")
	assert_true(_has(read["warnings"], "'ghost'"))


func test_caps_are_checked_before_parsing() -> void:
	var huge := "x".repeat(LibraryContracts.CAPS["library_json_bytes"] + 1)
	var read := LibraryReader.read({"library": huge, "catalog": "", "biomes": {}})
	assert_true(_has(read["errors"], "library.json is over"))
	var parts := _parts()
	var rule: Dictionary = parts["biome"]["rules"][0]
	parts["biome"]["rules"] = []
	for i in LibraryContracts.CAPS["rules_per_biome"] + 1:
		var copy := rule.duplicate(true)
		copy["key"] = "r%d" % i
		parts["biome"]["rules"].append(copy)
	assert_true(_has(_read(parts)["errors"], "over the cap"))


func test_unsupported_features_warn_instead_of_failing() -> void:
	var parts := _parts()
	parts["library"]["dependencies"] = [{"id": "core", "version": "^1.0"}]
	parts["biome"]["surfaces"] = "own"
	parts["biome"]["seasons"][0]["overrides"] = {"density_scale": {"large": 0.5}}
	parts["biome"]["rules"][0]["query"]["match"].append({"category": "tree", "subtype": "oak"})
	var read := _read(parts)
	assert_true(read["ok"], str(read["errors"]))
	assert_false(_has(read["warnings"], "dependenc"), "the registry resolves dependencies")
	assert_true(_has(read["warnings"], "treated as legacy"))
	assert_true(_has(read["warnings"], "overrides are not applied"))
	assert_true(_has(read["warnings"], "only {ref} clauses"))


# ---- step S4: dependencies, refs into a dependency, catalog integrity fields ----


func test_dependencies_are_checked_for_shape_and_range() -> void:
	var good := _parts()
	good["library"]["dependencies"] = [
		{"id": "core", "version": "^1.0"}, {"id": "other-lib", "version": ">=2.1 <3"}
	]
	var read := _read(good)
	assert_true(read["ok"], str(read["errors"]))
	assert_eq(read["warnings"], [])
	var cases := {
		"not an object": ["core"],
		"depends on itself": [{"id": "mini", "version": "*"}],
		"listed twice": [{"id": "core", "version": "*"}, {"id": "core", "version": "^1"}],
		"must match": [{"id": "Bad Id", "version": "*"}],
		"contains '__'": [{"id": "a__b", "version": "*"}],
		"version must be a string": [{"id": "core", "version": 1}],
		"not a version range": [{"id": "core", "version": "^banana"}],
	}
	for needle: String in cases:
		var parts := _parts()
		parts["library"]["dependencies"] = cases[needle]
		var result := _read(parts)
		assert_false(result["ok"], needle)
		assert_true(_has(result["errors"], needle), "%s in %s" % [needle, result["errors"]])
	var too_many := _parts()
	too_many["library"]["dependencies"] = []
	for i in LibraryContracts.MAX_DEPENDENCIES + 1:
		too_many["library"]["dependencies"].append({"id": "lib%d" % i, "version": "*"})
	assert_true(_has(_read(too_many)["errors"], "at most 8"))
	var not_a_list := _parts()
	not_a_list["library"]["dependencies"] = {"core": "^1"}
	assert_false(_read(not_a_list)["ok"])
	var typo := _parts()
	typo["library"]["dependencies"] = [{"id": "core", "versoin": "^1"}]
	assert_true(_has(_read(typo)["warnings"], "unknown key 'versoin'"))


func test_aliases_and_retired_are_shape_checked_with_warnings() -> void:
	var good := _parts()
	good["library"]["aliases"] = {"Old": "Tree_Oak_v0"}
	good["library"]["retired"] = ["Gone"]
	var read := _read(good)
	assert_true(read["ok"])
	assert_eq(read["warnings"], [])
	var bad := _parts()
	bad["library"]["aliases"] = {"Old": 5}
	bad["library"]["retired"] = "Gone"
	var result := _read(bad)
	assert_true(result["ok"], "a wrong rename entry never blocks the library")
	assert_true(_has(result["warnings"], "alias 'Old'"))
	assert_true(_has(result["warnings"], "retired must be a list"))
	var worse := _parts()
	worse["library"]["aliases"] = ["x"]
	assert_true(_has(_read(worse)["warnings"], "aliases must be an object"))


func test_a_query_ref_may_name_a_dependencys_asset() -> void:
	var parts := _parts()
	parts["biome"]["rules"][0]["query"]["match"].append({"ref": "core:Tree_Oak_v9"})
	var read := _read(parts)
	assert_true(read["ok"], str(read["errors"]))
	for bad in ["core:", "a:b:c", "Bad Lib:Oak", "core:has/slash"]:
		var broken := _parts()
		broken["biome"]["rules"][0]["query"]["match"].append({"ref": bad})
		assert_false(_read(broken)["ok"], bad)


func test_catalog_entries_may_carry_package_stem_and_integrity_fields() -> void:
	var parts := _parts()
	var entry: Dictionary = parts["catalog"]["assets"][0]
	entry["package_stem"] = "Tree_Oak_v0"
	entry["sha256"] = "ab".repeat(32)
	entry["bytes"] = 1234
	var read := _read(parts)
	assert_true(read["ok"], str(read["errors"]))
	assert_eq(read["warnings"], [], "package_stem is a known catalog key")
	var typo := _parts()
	typo["catalog"]["assets"][0]["package_stm"] = "x"
	assert_true(_has(_read(typo)["warnings"], "unknown key 'package_stm'"), "typos still warn")


func test_a_malformed_sha256_or_byte_count_is_an_error() -> void:
	for digest in ["abc", "A".repeat(64), 12, "g".repeat(64)]:
		var parts := _parts()
		parts["catalog"]["assets"][0]["sha256"] = digest
		var read := _read(parts)
		assert_false(read["ok"], str(digest))
		assert_true(_has(read["errors"], "sha256 must be"))
	for size in [-1, 1.5, "100", LibraryContracts.CAPS["glb_bytes"] + 1]:
		var parts := _parts()
		parts["catalog"]["assets"][0]["bytes"] = size
		assert_false(_read(parts)["ok"], str(size))
