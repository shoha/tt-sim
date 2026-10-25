extends GutTest

## The designer's season edits (step S9, DesignerSeasonEdits over BiomeDesignerModel): adding and
## removing seasons, what a season changes of the ground, the look, the density scale and a rule,
## the rule's presence in a season, clearing, the counts the panels show, undo of every one of
## them, the compile of each season to its own runtime biome, and the queries and locks that read
## the season-effective rule. The library is the designer fixture (`mini`, biome `meadow`, two
## seasons `summer` and `autumn`).

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_biome_designer_seasons/mini"

var _model: BiomeDesignerModel = null


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER + "/biomes")
	_model = BiomeDesignerModel.from_context(Fixture.context(FOLDER, true), "meadow")
	assert_eq(_model.error, "")


func after_all() -> void:
	for file_name in DirAccess.get_files_at(FOLDER + "/biomes"):
		DirAccess.remove_absolute(FOLDER + "/biomes/" + file_name)


func _biome(season: String) -> Dictionary:
	var result := _model.compile()
	assert_true(result["ok"], str(result["validation"]))
	for biome: Dictionary in result["compiled"]["palette"]["biomes"]:
		if biome["season"] == season:
			return biome
	return {}


func _rule(season: String, key: String) -> Dictionary:
	for rule: Dictionary in _biome(season).get("species", []):
		if rule["key"] == key:
			return rule
	return {}


# ---- the list ----


func test_add_season_takes_the_next_seed_and_undoes() -> void:
	assert_true(DesignerSeasonEdits.add_season(_model, "winter"))
	assert_eq(_model.season_ids(), ["summer", "autumn", "winter"])
	assert_eq(_model.season_list()[2], {"id": "winter", "seed": 3})
	assert_eq(_model.runtime_ids()[2], "mini__meadow_winter_s3")
	assert_true(_model.undo())
	assert_eq(_model.season_ids(), ["summer", "autumn"])
	assert_false(DesignerSeasonEdits.add_season(_model, "summer"), "a season id is used once")
	assert_false(DesignerSeasonEdits.add_season(_model, "Not Valid"))
	assert_eq(DesignerSeasonEdits.unused_names(_model), ["winter", "spring", "wet", "dry"])


func test_a_biome_holds_at_most_the_most_seasons() -> void:
	for i in LibraryContracts.MAX_SEASONS - 2:
		assert_true(DesignerSeasonEdits.add_season(_model, "s%d" % i))
	assert_eq(_model.season_ids().size(), LibraryContracts.MAX_SEASONS)
	assert_false(DesignerSeasonEdits.add_season(_model, "one_more"))


func test_remove_season_takes_its_overrides_with_it_and_the_last_one_stays() -> void:
	DesignerSeasonEdits.set_present(_model, "bushes", "autumn", false)
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "weight", 3)
	assert_true(DesignerSeasonEdits.remove_season(_model, "autumn"))
	assert_eq(_model.season_ids(), ["summer"])
	for key in _model.rule_keys():
		assert_false(_model.rule(key).has("seasons"), "%s keeps no trace of autumn" % key)
	assert_true(_model.undo())
	assert_eq(_model.season_ids(), ["summer", "autumn"])
	assert_eq(DesignerSeasonEdits.rule_override(_model, "oak", "autumn"), {"weight": 3})
	DesignerSeasonEdits.remove_season(_model, "autumn")
	assert_false(DesignerSeasonEdits.remove_season(_model, "summer"), "the last season stays")


func test_set_seed_renames_the_runtime_biome() -> void:
	assert_true(DesignerSeasonEdits.set_seed(_model, "autumn", 7))
	assert_eq(_model.runtime_ids()[1], "mini__meadow_autumn_s7")
	assert_false(DesignerSeasonEdits.set_seed(_model, "autumn", 7), "no change")
	assert_false(DesignerSeasonEdits.set_seed(_model, "ghost", 7))


# ---- the biome in a season ----


func test_a_seasons_ground_compiles_into_its_own_biome() -> void:
	assert_true(DesignerSeasonEdits.set_ground(_model, "autumn", "surface", "sand_red"))
	assert_true(DesignerSeasonEdits.has_ground_override(_model, "autumn", "surface"))
	assert_eq(DesignerSeasonEdits.ground_override(_model, "autumn", "surface"), "sand_red")
	assert_eq(_biome("autumn")["ground_surface"], "sand_red")
	assert_eq(_biome("summer")["ground_surface"], "grass", "summer keeps the biome's ground")
	assert_true(DesignerSeasonEdits.set_ground(_model, "autumn", "surface", null))
	assert_false(_model.def["seasons"][1].has("overrides"), "an empty override goes")
	assert_eq(_biome("autumn")["ground_surface"], "grass")


func test_a_season_can_have_no_accents_at_all() -> void:
	_model.def["ground"]["accents"] = [{"surface": "grass", "coverage": 0.1, "scale_m": 3}]
	assert_true(DesignerSeasonEdits.set_ground(_model, "autumn", "accents", []))
	assert_eq(_biome("summer")["ground_accents"].size(), 1)
	assert_eq(_biome("autumn")["ground_accents"].size(), 0)


func test_a_seasons_look_is_laid_over_the_biomes() -> void:
	var colours := [[0.1, 0.2, 0.1], [0.2, 0.3, 0.1], [0.3, 0.3, 0.1]]
	_model.def["ground_look"] = {"zones": {"colors_linear": colours, "strength": 0.9}}
	assert_true(DesignerSeasonEdits.set_ground_look(_model, "autumn", {"zones": {"strength": 0.4}}))
	assert_eq(DesignerSeasonEdits.look_override(_model, "autumn"), {"zones": {"strength": 0.4}})
	assert_eq(_biome("summer")["ground_look"]["zones"]["strength"], 0.9)
	assert_eq(_biome("autumn")["ground_look"]["zones"]["strength"], 0.4)
	assert_eq(_biome("autumn")["ground_look"]["zones"]["colors_linear"].size(), 3)
	assert_true(DesignerSeasonEdits.set_ground_look(_model, "autumn", null))
	assert_eq(DesignerSeasonEdits.look_override(_model, "autumn"), {})


func test_a_seasons_density_scale_multiplies_its_class() -> void:
	assert_true(DesignerSeasonEdits.set_density_scale(_model, "autumn", "large", 0.5))
	assert_almost_eq(float(_rule("autumn", "oak")["density_per_m2"]), 0.005, 1e-9)
	assert_almost_eq(float(_rule("summer", "oak")["density_per_m2"]), 0.01, 1e-9)
	assert_true(DesignerSeasonEdits.set_density_scale(_model, "autumn", "large", null))
	assert_almost_eq(float(_rule("autumn", "oak")["density_per_m2"]), 0.01, 1e-9)


# ---- a rule in a season ----


func test_a_rules_change_in_a_season_leaves_the_others_alone() -> void:
	assert_true(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "density_factor", 0.5))
	assert_true(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "spacing_m", 6))
	assert_eq(DesignerSeasonEdits.rule_override(_model, "oak", "autumn").size(), 2)
	assert_almost_eq(float(_rule("autumn", "oak")["density_per_m2"]), 0.005, 1e-9)
	assert_eq(_rule("autumn", "oak")["min_spacing_m"], 6.0)
	assert_eq(_rule("summer", "oak")["min_spacing_m"], 4.5)
	assert_eq(_model.value("oak", "spacing_m"), 4.5, "the rule itself is not touched")
	assert_true(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "spacing_m", null))
	assert_true(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "density_factor", null))
	assert_false(_model.rule("oak").has("seasons"), "no empty override is left behind")


func test_only_the_fields_the_contract_names_can_change_by_season() -> void:
	assert_false(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "role", "grass"))
	assert_false(DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "enabled", false))
	assert_false(DesignerSeasonEdits.set_rule_field(_model, "ghost", "autumn", "weight", 2))


func test_a_drag_of_a_seasons_field_is_one_undo_step() -> void:
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "weight", 2, true)
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "weight", 3, true)
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "weight", 4, true)
	assert_true(_model.undo())
	assert_eq(DesignerSeasonEdits.rule_override(_model, "oak", "autumn"), {})
	assert_false(_model.can_undo())


func test_a_rule_can_leave_a_season_and_come_back() -> void:
	assert_true(DesignerSeasonEdits.is_present(_model, "bushes", "autumn"))
	assert_true(DesignerSeasonEdits.set_present(_model, "bushes", "autumn", false))
	assert_false(DesignerSeasonEdits.is_present(_model, "bushes", "autumn"))
	assert_eq(_model.rule("bushes")["seasons"], {"only": ["summer"]})
	assert_false(_rule("summer", "bushes").is_empty())
	assert_true(_rule("autumn", "bushes").is_empty(), "the rule is not in the autumn biome")
	assert_false(DesignerSeasonEdits.set_present(_model, "bushes", "autumn", false), "no change")
	assert_true(DesignerSeasonEdits.set_present(_model, "bushes", "autumn", true))
	assert_false(_model.rule("bushes").has("seasons"), "present everywhere needs no list")
	assert_false(_rule("autumn", "bushes").is_empty())


func test_presence_with_three_seasons_keeps_the_order() -> void:
	DesignerSeasonEdits.add_season(_model, "winter")
	DesignerSeasonEdits.set_present(_model, "bushes", "autumn", false)
	assert_eq(_model.rule("bushes")["seasons"], {"only": ["summer", "winter"]})
	DesignerSeasonEdits.set_present(_model, "bushes", "summer", false)
	assert_eq(_model.rule("bushes")["seasons"], {"only": ["winter"]})
	DesignerSeasonEdits.set_present(_model, "bushes", "autumn", true)
	assert_eq(_model.rule("bushes")["seasons"], {"only": ["autumn", "winter"]})


# ---- clearing and counting ----


func test_summary_counts_what_a_season_changes_and_clear_takes_it_away() -> void:
	assert_eq(DesignerSeasonEdits.summary(_model, "autumn")["total"], 0)
	DesignerSeasonEdits.set_ground(_model, "autumn", "surface", "sand_red")
	DesignerSeasonEdits.set_density_scale(_model, "autumn", "large", 0.5)
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "weight", 2)
	DesignerSeasonEdits.set_present(_model, "bushes", "autumn", false)
	var summary := DesignerSeasonEdits.summary(_model, "autumn")
	assert_eq(summary["ground"], 1)
	assert_eq(summary["density"], 1)
	assert_eq(summary["rules"], 1)
	assert_eq(summary["hidden"], 1)
	assert_eq(summary["total"], 4)
	assert_eq(DesignerSeasonEdits.summary(_model, "summer")["total"], 0)
	assert_true(BiomeSeasons.has_overrides(_model.def, "autumn"))
	assert_true(DesignerSeasonEdits.clear(_model, "autumn"))
	assert_eq(DesignerSeasonEdits.summary(_model, "autumn")["total"], 0)
	assert_false(BiomeSeasons.has_overrides(_model.def, "autumn"))
	assert_false(DesignerSeasonEdits.clear(_model, "autumn"), "nothing left to clear")
	assert_true(_model.undo(), "clearing is one undo step")
	assert_eq(DesignerSeasonEdits.summary(_model, "autumn")["total"], 4)


func test_every_season_edit_keeps_the_draft_valid() -> void:
	DesignerSeasonEdits.add_season(_model, "winter")
	DesignerSeasonEdits.set_ground(_model, "winter", "surface", "snow")
	DesignerSeasonEdits.set_rule_field(_model, "oak", "winter", "density_factor", 0)
	var response := {"slope": [[0, 1], [60, 0.2]]}
	DesignerSeasonEdits.set_rule_field(_model, "stones", "winter", "response", response)
	DesignerSeasonEdits.set_present(_model, "bushes", "winter", false)
	var verdict := _model.validation()
	assert_eq(verdict["errors"], [])
	assert_eq(_biome("winter")["species"].size(), 1, "oak left by a factor of 0, bushes by presence")
	assert_eq(_rule("winter", "stones")["response"]["slope"], [[0, 1], [60, 0.2]])


# ---- what the panels read ----


func test_a_season_reads_its_own_query() -> void:
	var query := {"match": [{"category": "tree"}], "count": "all", "order": "id"}
	_model.set_query("oak", query)
	DesignerSeasonEdits.set_rule_field(
		_model, "oak", "autumn", "query", {"match": [{"ref": "Tree_pine_v0"}]}
	)
	assert_eq(_model.resolved_assets("oak", "summer").size(), 6)
	assert_eq(_model.resolved_assets("oak", "autumn").size(), 1)
	assert_eq(_model.resolved_assets("oak", "autumn")[0]["id"], "Tree_pine_v0")


func test_a_lock_follows_the_season_query() -> void:
	var query := {"match": [{"category": "tree"}], "count": 2, "order": "id"}
	_model.set_query("oak", query)
	assert_true(_model.set_locked("oak", true))
	assert_eq(_model.locks.keys().size(), 2, "one lock per season")
	assert_eq(DesignerLocks.state(_model, "oak")["state"], "locked")
	DesignerSeasonEdits.set_rule_field(_model, "oak", "autumn", "query", {"count": 1})
	var state := DesignerLocks.state(_model, "oak")
	assert_eq(state["state"], "stale_query", "autumn's query is not the one the lock was taken on")
	assert_eq(state["seasons"]["summer"]["state"], "locked")
	assert_eq(state["seasons"]["autumn"]["state"], "stale_query")
	assert_true(DesignerLocks.refresh(_model, "oak"))
	assert_eq(DesignerLocks.state(_model, "oak")["state"], "locked")
	DesignerSeasonEdits.set_present(_model, "oak", "autumn", false)
	assert_true(_model.is_locked("oak"))
	var written := _model.save()
	assert_true(written["ok"], str(written))
	var lock_file := FOLDER + "/biomes/meadow.lock.json"
	var lock := JSON.parse_string(FileAccess.get_file_as_string(lock_file)) as Dictionary
	assert_true(lock["rules"].has("summer/oak"))
	assert_false(lock["rules"].has("autumn/oak"), "the rule is not in autumn, so no lock is written")
