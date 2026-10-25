extends GutTest

## LibraryIds (utils/library/): the id grammar and runtime id mapping, the S0 probe rules (no
## slash or double underscore inside a part, the whole asset id under the palette's 160, a prefix
## per season) and the portable-names rules. The contract tables and the contract.json export
## are test_library_contracts.gd's.


func test_core_keeps_todays_runtime_ids() -> void:
	assert_eq(LibraryIds.runtime_biome("core", "savanna", "summer", 1), "savanna_summer_s1")
	assert_eq(
		LibraryIds.runtime_asset("savanna_summer_s1", "Tree_Acacia_v0"),
		"savanna_summer_s1/Tree_Acacia_v0"
	)
	assert_eq(LibraryIds.biome_field("core", "savanna"), "savanna")
	assert_eq(LibraryIds.runtime_surface("core", "grass_savanna"), "grass_savanna")
	assert_eq(LibraryIds.library_of("savanna_summer_s1/Tree_Acacia_v0"), "core")


func test_other_libraries_are_prefixed() -> void:
	var biome := LibraryIds.runtime_biome("alienworld", "crystal_basin", "summer", 2)
	assert_eq(biome, "alienworld__crystal_basin_summer_s2")
	assert_eq(LibraryIds.biome_field("alienworld", "crystal_basin"), "alienworld__crystal_basin")
	assert_eq(LibraryIds.runtime_surface("alienworld", "sand"), "alienworld__sand")
	assert_eq(LibraryIds.library_of(biome + "/Tree_Crystal_v0"), "alienworld")
	assert_eq(LibraryIds.library_of(biome), "alienworld")


func test_runtime_ids_parse_back() -> void:
	assert_eq(
		LibraryIds.parse_runtime_biome("savanna_summer_s1"),
		{"library": "core", "biome": "savanna", "season": "summer", "seed": 1}
	)
	assert_eq(
		LibraryIds.parse_runtime_biome("alienworld__crystal_basin_winter_s12"),
		{"library": "alienworld", "biome": "crystal_basin", "season": "winter", "seed": 12}
	)
	assert_eq(LibraryIds.parse_runtime_biome("not a biome"), {})
	assert_eq(LibraryIds.parse_runtime_biome("a__b__c_summer_s1"), {}, "two separators")


func test_asset_ids_keep_exactly_one_slash_and_one_prefix_per_season() -> void:
	var summer := LibraryIds.runtime_asset(
		LibraryIds.runtime_biome("mini", "meadow", "summer", 1), "Oak"
	)
	var winter := LibraryIds.runtime_asset(
		LibraryIds.runtime_biome("mini", "meadow", "winter", 1), "Oak"
	)
	assert_ne(summer, winter, "every season is its own asset prefix")
	for id in [summer, winter]:
		assert_eq(String(id).count("/"), 1)
		var parsed := LibraryIds.parse_runtime_biome(String(id).get_slice("/", 0))
		assert_eq(parsed["library"], "mini")
		assert_eq(parsed["biome"], "meadow")


func test_library_id_grammar() -> void:
	assert_eq(LibraryIds.library_problems("core").size(), 0)
	assert_eq(LibraryIds.library_problems("alien-world_2").size(), 0)
	for bad in [
		"", "A", "x", "1abc", "a/b", "a__b", "legacy", "draft", "dev", "a".repeat(33), "with space"
	]:
		assert_gt(LibraryIds.library_problems(bad).size(), 0, "'%s' is refused" % bad)


func test_biome_season_and_local_id_grammar() -> void:
	assert_eq(LibraryIds.biome_problems("crystal_basin").size(), 0)
	for bad in ["", "Savanna", "a/b", "a__b", "9lives", "a".repeat(49)]:
		assert_gt(LibraryIds.biome_problems(bad).size(), 0, "biome '%s'" % bad)
	assert_eq(LibraryIds.season_problems("summer").size(), 0)
	assert_gt(LibraryIds.season_problems("late_summer").size(), 0, "no underscore in a season")
	assert_eq(LibraryIds.local_problems("Tree_Acacia_v0").size(), 0)
	for bad in ["", "a/b", "a\\b", "a.b", "a b", "con", "NUL", "x".repeat(65)]:
		assert_gt(LibraryIds.local_problems(bad).size(), 0, "local id '%s'" % bad)


func test_whole_asset_id_stays_under_the_palette_cap() -> void:
	var biome := "x".repeat(100)
	assert_true(LibraryIds.asset_id_fits(biome, "y".repeat(58)), "159 characters")
	assert_false(LibraryIds.asset_id_fits(biome, "y".repeat(59)), "160 is rejected by the palette")
	assert_eq(PaletteLibrary.MAX_ID_LENGTH, LibraryIds.MAX_ASSET_ID_LENGTH, "the same cap")


func test_portable_names() -> void:
	assert_eq(LibraryIds.path_problems("assets/tree/Tree_Oak_v0.glb").size(), 0)
	for bad in [
		"",
		"/abs/x.glb",
		"C:/x.glb",
		"assets\\x.glb",
		"assets/../x.glb",
		"assets/con.glb",
		"assets/aux",
		"assets/x.",
		"assets/x ",
		"assets//x.glb",
		"res://x.glb",
		"a/".repeat(70) + "x.glb",
	]:
		assert_gt(LibraryIds.path_problems(bad).size(), 0, "path '%s' is refused" % bad.left(30))
	assert_gt(LibraryIds.segment_problems("lpt1.txt").size(), 0, "a device name with an extension")


func test_case_duplicates_are_reported_once_in_input_order() -> void:
	var dups := LibraryIds.case_duplicates(["a.glb", "B.glb", "A.GLB", "b.glb", "A.GLB", "c"])
	assert_eq(Array(dups), ["A.GLB", "b.glb"])
	assert_eq(LibraryIds.case_duplicates(["a", "b"]).size(), 0)


func test_aliases_follow_renames_but_not_forever() -> void:
	assert_eq(LibraryIds.resolve_alias({"old": "mid", "mid": "new"}, "old"), "new")
	assert_eq(LibraryIds.resolve_alias({}, "same"), "same")
	assert_eq(LibraryIds.resolve_alias({"a": "b", "b": "a"}, "a").length(), 1, "a cycle ends")
