extends GutTest

## Per-season overrides of a biome-def (step S9, BiomeSeasons and the compiler): a biome without
## overrides compiles byte for byte as before, a season with overrides compiles to its own runtime
## biome (`<lib>__<biome>_<season>_s<seed>`) with the ground, the ground look, the density scale
## and per-rule fields changed, the rule-level `seasons` (`only` and per-season overrides) apply,
## and the reader reports malformed overrides in the rule's own words. The library is built from
## strings (the designer fixture: `mini`, biome `meadow` of three rules in summer and autumn).

const Fixture := preload("res://tests/unit/designer_fixture.gd")


func _def() -> Dictionary:
	return Fixture.biome()


func _read(def: Dictionary) -> Dictionary:
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "mini",
		"name": "Mini",
		"version": "0.2.0",
		"contract": 1,
	}
	return LibraryReader.read(
		{
			"library": JSON.stringify(library),
			"catalog": JSON.stringify(Fixture.catalog()),
			"biomes": {"meadow.json": JSON.stringify(def)},
		}
	)


func _compile(def: Dictionary) -> Dictionary:
	var read := _read(def)
	assert_true(read["ok"], str(read["errors"]))
	return BiomeCompiler.compile(read, {"surfaces": {"grass": {}, "sand_red": {}}})


func _biome(compiled: Dictionary, season: String) -> Dictionary:
	for biome: Dictionary in compiled["palette"]["biomes"]:
		if biome["season"] == season:
			return biome
	return {}


func _rule(biome: Dictionary, key: String) -> Dictionary:
	for rule: Dictionary in biome.get("species", []):
		if rule["key"] == key:
			return rule
	return {}


func _has(lines: Array, needle: String) -> bool:
	for line: String in lines:
		if needle in line:
			return true
	return false


# ---- nothing applies ----


func test_a_def_without_overrides_is_returned_unchanged() -> void:
	var def := _def()
	assert_true(is_same(BiomeSeasons.effective(def, "summer"), def))
	def["seasons"][0]["overrides"] = {}
	assert_true(is_same(BiomeSeasons.effective(def, "summer"), def), "an empty override is none")
	assert_false(BiomeSeasons.has_overrides(def, "summer"))


func test_no_overrides_compile_to_the_same_palette_as_before() -> void:
	var plain := _compile(_def())
	var def := _def()
	def["seasons"][1]["overrides"] = {}
	var with_empty := _compile(def)
	assert_eq(JSON.stringify(with_empty["palette"]), JSON.stringify(plain["palette"]))
	assert_eq(with_empty["biome_ids"], ["mini__meadow_summer_s1", "mini__meadow_autumn_s2"])


# ---- a season's overrides ----


func test_a_season_compiles_to_its_own_biome_with_its_overrides() -> void:
	var def := _def()
	var colours := [[0.1, 0.2, 0.1], [0.2, 0.3, 0.1], [0.3, 0.3, 0.1]]
	def["ground_look"] = {"zones": {"colors_linear": colours}}
	def["seasons"][1]["overrides"] = {
		"ground": {"surface": "sand_red", "paths": null},
		"ground_look": {"zones": {"strength": 0.5}, "light": {"shade": 0.5}},
		"density_scale": {"large": 0.5},
		"rules":
		{
			"oak": {"density_factor": 0.5, "spacing_m": 6},
			"stones": {"query": {"tags_none": ["mineral"]}},
			"bushes": {"enabled": false},
		},
	}
	var compiled := _compile(def)
	var summer := _biome(compiled, "summer")
	var autumn := _biome(compiled, "autumn")
	assert_eq(autumn["id"], "mini__meadow_autumn_s2")
	assert_eq(summer["ground_surface"], "grass", "summer is untouched")
	assert_eq(autumn["ground_surface"], "sand_red")
	assert_false(autumn.has("path_surfaces") and not (autumn["path_surfaces"] as Array).is_empty())
	assert_eq(summer["ground_look"]["zones"].keys(), ["colors_linear"])
	assert_eq(autumn["ground_look"]["zones"]["strength"], 0.5)
	assert_eq(autumn["ground_look"]["zones"]["colors_linear"].size(), 3, "the base colours stay")
	assert_eq(autumn["ground_look"]["light"], {"shade": 0.5})
	assert_eq(_rule(summer, "oak")["density_per_m2"], 0.01)
	assert_almost_eq(float(_rule(autumn, "oak")["density_per_m2"]), 0.01 * 0.5 * 0.5, 1e-9)
	assert_eq(_rule(autumn, "oak")["min_spacing_m"], 6.0)
	assert_eq(_rule(autumn, "bushes"), {}, "a disabled rule is absent from the season")
	assert_false(_rule(summer, "bushes").is_empty())
	assert_true(_rule(autumn, "stones").is_empty(), "tags_none mineral leaves the stones empty")
	assert_true(_has(compiled["warnings"], "autumn_s2 rule stones: no asset resolves"))


func test_a_relative_density_factor_scales_a_rule_without_an_absolute_density() -> void:
	var def := _def()
	def["rules"][0].erase("density_per_m2")
	def["rules"][0]["density_factor"] = 2.0
	def["seasons"][1]["overrides"] = {"rules": {"oak": {"density_factor": 0.25}}}
	var compiled := _compile(def)
	var class_default := float(LibraryContracts.class_defaults("large")["density_per_m2"])
	var summer := float(_rule(_biome(compiled, "summer"), "oak")["density_per_m2"])
	var autumn := float(_rule(_biome(compiled, "autumn"), "oak")["density_per_m2"])
	assert_almost_eq(summer, class_default * 2.0, 1e-9)
	assert_almost_eq(autumn, class_default * 0.5, 1e-9)


func test_a_density_factor_of_zero_removes_the_rule_from_the_season() -> void:
	var def := _def()
	def["seasons"][1]["overrides"] = {"rules": {"bushes": {"density_factor": 0}}}
	var compiled := _compile(def)
	assert_true(_rule(_biome(compiled, "autumn"), "bushes").is_empty())
	assert_false(_rule(_biome(compiled, "summer"), "bushes").is_empty())


func test_the_biome_density_scale_multiplies_every_rule_of_its_class() -> void:
	var def := _def()
	def["density_scale"] = {"medium": 2.0}
	var compiled := _compile(def)
	var biome := _biome(compiled, "summer")
	assert_almost_eq(float(_rule(biome, "bushes")["density_per_m2"]), 0.05 * 2.0, 1e-9)
	assert_eq(_rule(biome, "oak")["density_per_m2"], 0.01, "another class is not scaled")
	def["seasons"][1]["overrides"] = {"density_scale": {"medium": 1.0}}
	var autumn := _biome(_compile(def), "autumn")
	assert_almost_eq(float(_rule(autumn, "bushes")["density_per_m2"]), 0.05, 1e-9)


func test_a_season_query_override_changes_what_the_rule_selects() -> void:
	var def := _def()
	def["rules"][0]["query"] = {"match": [{"category": "tree"}], "count": "all", "order": "id"}
	var pine := {"query": {"match": [{"ref": "Tree_pine_v0"}]}}
	def["seasons"][1]["overrides"] = {"rules": {"oak": pine}}
	var compiled := _compile(def)
	assert_eq(_rule(_biome(compiled, "summer"), "oak")["assets"].size(), 6)
	assert_eq(
		_rule(_biome(compiled, "autumn"), "oak")["assets"],
		["mini__meadow_autumn_s2/Tree_pine_v0"]
	)


# ---- a rule's own seasons ----


func test_a_rule_grows_only_in_the_seasons_it_lists() -> void:
	var def := _def()
	def["rules"][2]["seasons"] = {"only": ["summer"]}
	var compiled := _compile(def)
	assert_false(_rule(_biome(compiled, "summer"), "bushes").is_empty())
	assert_true(_rule(_biome(compiled, "autumn"), "bushes").is_empty())
	assert_false(_biome(compiled, "autumn").has("seasons"), "no stray key reaches the palette")
	assert_false(_rule(_biome(compiled, "summer"), "bushes").has("seasons"))


func test_a_rule_level_season_override_applies_after_the_season_level_one() -> void:
	var def := _def()
	def["rules"][0]["seasons"] = {"autumn": {"weight": 3, "density_factor": 0.5}}
	def["seasons"][1]["overrides"] = {"rules": {"oak": {"weight": 2, "density_factor": 0.5}}}
	var autumn := _biome(_compile(def), "autumn")
	assert_eq(_rule(autumn, "oak")["weight"], 3.0, "the rule's own override wins")
	assert_almost_eq(float(_rule(autumn, "oak")["density_per_m2"]), 0.01 * 0.25, 1e-9)


func test_the_designer_summer_stays_the_first_season_when_autumn_changes_everything() -> void:
	var def := _def()
	def["seasons"][1]["overrides"] = {"rules": {"oak": {"enabled": false}}}
	var compiled := _compile(def)
	assert_eq(compiled["biome_ids"].size(), 2)
	assert_eq(_biome(compiled, "summer")["species"].size(), 3)
	assert_eq(_biome(compiled, "autumn")["species"].size(), 2)


# ---- the reader's words ----


func _errors_of(def: Dictionary) -> Array:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	LibraryReader.check_biome(def, "meadow.json", errors, warnings)
	return errors


func _warnings_of(def: Dictionary) -> Array:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	LibraryReader.check_biome(def, "meadow.json", errors, warnings)
	return warnings


func test_a_good_override_reads_clean() -> void:
	var def := _def()
	def["seasons"][1]["overrides"] = {
		"ground": {"surface": "sand_red"},
		"density_scale": {"large": 0.5},
		"rules": {"oak": {"density_factor": 0, "spacing_m": 5, "query": {"tags_any": ["deciduous"]}}},
	}
	def["rules"][1]["seasons"] = {"only": ["summer"], "autumn": {"weight": 2}}
	assert_eq(_errors_of(def), [])
	assert_eq(_warnings_of(def), [])


func test_malformed_overrides_are_errors_in_the_rules_words() -> void:
	var def := _def()
	def["seasons"][1]["overrides"] = {
		"ground": 5,
		"density_scale": {"large": -1},
		"rules": {"oak": {"spacing_m": -2, "enabled": "no", "query": 7}, "bushes": 3},
	}
	var errors := _errors_of(def)
	assert_true(_has(errors, "overrides.ground must be an object"))
	assert_true(_has(errors, "density_scale.large must be a number"))
	assert_true(_has(errors, "rule 'oak': spacing_m must be a number"))
	assert_true(_has(errors, "enabled must be true or false"))
	assert_true(_has(errors, "query must be an object"))
	assert_true(_has(errors, "override of rule 'bushes' must be an object"))
	def["seasons"][1]["overrides"] = 5
	assert_true(_has(_errors_of(def), "overrides must be an object"))


func test_unknown_keys_and_names_are_warnings() -> void:
	var def := _def()
	def["seasons"][1]["overrides"] = {
		"colour": 1, "ground": {"sky": "x"}, "rules": {"ghost": {"role": "grass", "weight": 2}}
	}
	def["rules"][0]["seasons"] = {"only": ["summer", "monsoon"], "monsoon": {"weight": 1}}
	var warnings := _warnings_of(def)
	assert_true(_has(warnings, "override 'colour' is unknown"))
	assert_true(_has(warnings, "ground override 'sky' is unknown"))
	assert_true(_has(warnings, "names 'ghost', which is not a rule"))
	assert_true(_has(warnings, "field 'role' cannot change by season"))
	assert_true(_has(warnings, "only names 'monsoon', which is not a season"))
	assert_true(_has(warnings, "'monsoon' is not a season of this biome"))


func test_the_contract_publishes_the_season_tables() -> void:
	var data: Dictionary = JSON.parse_string(LibraryContracts.export_json())
	assert_eq(data["seasons"]["override_keys"], Array(LibraryContracts.SEASON_OVERRIDE_KEYS))
	assert_eq(data["seasons"]["rule_fields"], Array(LibraryContracts.SEASON_RULE_FIELDS))
	assert_eq(int(data["seasons"]["max"]), LibraryContracts.MAX_SEASONS)
