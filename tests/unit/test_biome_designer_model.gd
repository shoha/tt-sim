extends GutTest

## BiomeDesignerModel (step S8a): the draft biome-def, its commands and undo, validation per
## field, compile-on-edit, dirty tracking, save and lock files, and "Duplicate as new
## collection". The library is built from strings in the test, so nothing depends on a library
## on disk except the scratch folder the save tests write.

const ROOT := "user://test_biome_designer"

var _folder: String = ""


func before_each() -> void:
	_folder = ROOT + "/mini"
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(_folder + "/biomes")


func after_all() -> void:
	_remove_tree(ROOT)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ---- fixture ----


func _entry(id: String, group: String, category: String, size_class: String, tags: Array) -> Dictionary:
	return {
		"id": id,
		"group": group,
		"name": group,
		"category": category,
		"subtype": group,
		"tags": tags,
		"seasons": [],
		"roles": [],
		"size_class": size_class,
		"wind_category": "tree" if category == "tree" else "",
		"dimensions_m": [3.0, 5.0, 3.0],
		"triangles": 100,
		"file": "assets/%s.glb" % id,
		"node": id + "_LOD0",
	}


func _catalog() -> Dictionary:
	var assets: Array = []
	for group in ["oak", "birch", "pine"]:
		for v in 2:
			assets.append(_entry("Tree_%s_v%d" % [group, v], group, "tree", "large", ["deciduous"]))
	for group in ["rock_a", "rock_b"]:
		assets.append(_entry("Rock_%s" % group, group, "rock", "small", ["mineral"]))
	assets.append(_entry("Bush_a", "bush_a", "bush", "medium", ["shrub"]))
	return {"format": "ttsim-catalog", "format_version": 1, "assets": assets}


func _biome() -> Dictionary:
	return {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "meadow",
		"name": "Meadow",
		"surfaces": "legacy",
		"seasons": [{"id": "summer", "seed": 1}, {"id": "autumn", "seed": 2}],
		"ground": {"surface": "grass", "paths": []},
		"rules":
		[
			{
				"key": "oak",
				"role": "canopy_tree",
				"weight": 1,
				"density_per_m2": 0.01,
				"spacing_m": 4.5,
				"slope_max_deg": 35,
				"near": [],
				"avoid": [],
				"query": {"match": [{"ref": "Tree_oak_v0"}, {"ref": "Tree_oak_v1"}]},
			},
			{
				"key": "stones",
				"role": "stones",
				"density_per_m2": 0.06,
				"near": [{"rule": "oak", "distance_m": 3, "influence": 0.4, "transition_m": 2}],
				"avoid": [],
				"query": {"match": [{"category": "rock"}], "count": 1},
			},
			{
				"key": "bushes",
				"role": "shrub",
				"density_per_m2": 0.05,
				"near": [],
				"avoid": [{"rule": "stones", "distance_m": 1, "influence": 0.5, "transition_m": 1}],
				"query": {"match": [{"ref": "Bush_a"}]},
			},
		],
	}


func _context(writable: bool = true) -> Dictionary:
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "mini",
		"name": "Mini",
		"version": "0.2.0",
		"contract": 1,
	}
	var read := LibraryReader.read(
		{
			"library": JSON.stringify(library),
			"catalog": JSON.stringify(_catalog()),
			"biomes": {"meadow.json": JSON.stringify(_biome())},
		}
	)
	assert_true(read["ok"], str(read["errors"]))
	return {
		"ok": true,
		"id": "mini",
		"name": "Mini",
		"version": "0.2.0",
		"source": "user" if writable else "official",
		"official": not writable,
		"writable": writable,
		"folder": _folder,
		"read": read,
		"files": [],
		"hash": "abc12345",
		"dependencies": {},
		"dependency_list": [],
		"biomes": ["meadow"],
		"surfaces": {},
	}


func _model(writable: bool = true) -> BiomeDesignerModel:
	var model := BiomeDesignerModel.from_context(_context(writable), "meadow")
	assert_eq(model.error, "")
	return model


# ---- reading ----


func test_the_model_reads_the_draft() -> void:
	var model := _model()
	assert_eq(model.rule_keys(), ["oak", "stones", "bushes"])
	assert_eq(model.value("oak", "spacing_m"), 4.5)
	assert_eq(model.value("stones", "spacing_m", "none"), "none")
	assert_eq(model.runtime_ids(), ["mini__meadow_summer_s1", "mini__meadow_autumn_s2"])
	assert_eq(model.rules_by_role(), {"canopy_tree": ["oak"], "stones": ["stones"], "shrub": ["bushes"]})
	assert_false(model.is_dirty())
	assert_almost_eq(model.effective_number("stones", "spacing_m"), 0.8, 0.0001, "small class default")
	assert_almost_eq(model.effective_number("oak", "spacing_m"), 4.5, 0.0001)


func test_a_missing_library_or_biome_is_an_error_not_a_crash() -> void:
	var bad := BiomeDesignerModel.from_context({"ok": false, "error": "nope"}, "meadow")
	assert_eq(bad.error, "nope")
	var none := BiomeDesignerModel.from_context(_context(), "absent")
	assert_true("no biome" in none.error)


# ---- rules and history ----


func test_add_remove_duplicate_move_rename_and_undo_all_of_it() -> void:
	var model := _model()
	var original := model.def.duplicate(true)
	var key := model.add_rule("canopy_tree", {}, "Birch Grove")
	assert_eq(key, "birch_grove")
	assert_eq(model.rule_keys(), ["oak", "birch_grove", "stones", "bushes"], "after the last of its role")
	assert_eq(model.duplicate_rule("oak"), "oak_2")
	assert_true(model.move_rule("oak_2", 3))
	assert_eq(model.rename_rule("stones", "pebbles"), "pebbles")
	assert_eq(model.value("bushes", "avoid")[0]["rule"], "pebbles", "relations follow a rename")
	assert_true(model.remove_rule("oak"))
	assert_eq(model.value("pebbles", "near"), [], "the relation to the removed rule is dropped")
	assert_true(model.is_dirty())
	var edited := model.def.duplicate(true)
	while model.can_undo():
		model.undo()
	assert_eq(model.def, original)
	assert_false(model.is_dirty(), "undone to the saved state")
	while model.can_redo():
		model.redo()
	assert_eq(model.def, edited, "redo replays every step")


func test_redo_replays_and_a_new_edit_clears_it() -> void:
	var model := _model()
	model.set_field("oak", "weight", 3)
	model.undo()
	assert_true(model.can_redo())
	assert_eq(model.history_label(true), "Set weight")
	model.redo()
	assert_eq(model.value("oak", "weight"), 3)
	model.undo()
	model.set_field("oak", "weight", 5)
	assert_false(model.can_redo())


func test_unique_keys() -> void:
	var model := _model()
	assert_eq(model.unique_key("oak"), "oak_2")
	assert_eq(model.unique_key("  New Rule "), "new_rule")
	assert_eq(model.unique_key(""), "rule")


func test_new_rules_carry_the_role_defaults() -> void:
	var model := _model()
	var key := model.add_rule("grass")
	var rule := model.rule(key)
	assert_eq(rule["role"], "grass")
	assert_eq(rule["density_per_m2"], 8.0)
	assert_eq(rule["query"]["match"], [{"role": "grass"}])
	assert_eq(model.add_rule("dragon"), "", "an unknown role makes no rule")


func test_set_field_with_null_erases_and_a_same_value_is_no_edit() -> void:
	var model := _model()
	assert_false(model.set_field("oak", "spacing_m", 4.5), "same value")
	assert_true(model.set_field("oak", "spacing_m", 6))
	assert_true(model.set_field("oak", "spacing_m", null))
	assert_false(model.rule("oak").has("spacing_m"))
	assert_false(model.set_field("oak", "spacing_m", null), "already clear")
	assert_false(model.set_field("nobody", "spacing_m", 1))
	model.undo()
	assert_eq(model.value("oak", "spacing_m"), 6)


func test_a_slider_drag_is_one_undo_step() -> void:
	var model := _model()
	for step in 8:
		model.set_field("oak", "spacing_m", 5.0 + step * 0.5, true)
	assert_eq(model.value("oak", "spacing_m"), 8.5)
	model.undo()
	assert_eq(model.value("oak", "spacing_m"), 4.5, "one undo takes the whole drag back")
	assert_false(model.can_undo())
	model.set_field("oak", "spacing_m", 5.0)
	model.set_field("oak", "spacing_m", 6.0)
	model.undo()
	assert_eq(model.value("oak", "spacing_m"), 5.0, "separate (unmerged) edits are separate steps")


func test_set_role_moves_a_default_size_class_along() -> void:
	var model := _model()
	model.set_field("oak", "size_class", "large")
	assert_true(model.set_role("oak", "palm"))
	assert_eq(model.value("oak", "role"), "palm")
	assert_false(model.rule("oak").has("size_class"), "the old role's default class goes")
	model.set_field("oak", "size_class", "small")
	model.set_role("oak", "canopy_tree")
	assert_eq(model.value("oak", "size_class"), "small", "a chosen class stays")
	assert_false(model.set_role("oak", "dragon"))
	assert_true(model.set_size_class("oak", "large"))
	assert_false(model.rule("oak").has("size_class"), "the role's default is stored as nothing")


# ---- queries ----


func test_query_edits_and_pins() -> void:
	var model := _model()
	assert_eq(model.add_clause("stones", {"ref": "Rock_rock_a"}), 1)
	assert_eq(model.add_clause("stones", {"ref": "Rock_rock_a"}), 1, "the same clause is not added twice")
	assert_true(model.remove_clause("stones", 1))
	assert_false(model.remove_clause("stones", 0) and model.remove_clause("stones", 0), "never the last clause")
	assert_true(model.set_query_field("stones", "tags_any", ["mineral"]))
	assert_true(model.set_query_field("stones", "tags_any", []))
	assert_false(model.rule("stones")["query"].has("tags_any"))
	assert_true(model.set_pin("stones", "Rock_rock_b", true))
	assert_false(model.set_pin("stones", "Rock_rock_b", true))
	assert_eq(model.rule("stones")["query"]["pin"], ["Rock_rock_b"])
	assert_true(model.set_pin("stones", "Rock_rock_b", false))
	assert_false(model.rule("stones")["query"].has("pin"))
	assert_true(model.set_query("bushes", {"match": [{"category": "bush"}]}))


func test_resolved_assets_follow_the_query_and_the_edit() -> void:
	var model := _model()
	var refs: Array[String] = []
	for found in model.resolved_assets("oak"):
		refs.append(found["ref"])
	assert_eq(refs, ["Tree_oak_v0", "Tree_oak_v1"])
	assert_eq(model.resolved_assets("stones").size(), 1, "count 1 of two rock groups")
	model.set_query_field("stones", "count", "all")
	assert_eq(model.resolved_assets("stones").size(), 2)
	assert_eq(model.rules_using("Tree_oak_v1"), ["oak"])
	assert_eq(model.catalog().size(), 9)


# ---- terrain response ----


func test_curves_slope_min_and_their_undo() -> void:
	var model := _model()
	assert_true(DesignerResponseEdits.set_preset(model, "oak", "slope", "ramp_down"))
	assert_eq(DesignerResponseEdits.curve(model, "oak", "slope"), [[0.0, 1.0], [90.0, 0.0]])
	assert_true(DesignerResponseEdits.add_point(model, "oak", "slope", 40.0))
	assert_eq(DesignerResponseEdits.curve(model, "oak", "slope").size(), 3)
	assert_true(DesignerResponseEdits.move_point(model, "oak", "slope", 1, 30.0, 0.8))
	assert_true(DesignerResponseEdits.move_point(model, "oak", "slope", 1, 32.0, 0.8))
	assert_eq(DesignerResponseEdits.curve(model, "oak", "slope")[1], [32.0, 0.8])
	assert_true(DesignerResponseEdits.remove_point(model, "oak", "slope", 1))
	assert_true(DesignerResponseEdits.set_slope_min(model, "oak", 12))
	assert_eq(model.value("oak", "slope_min_deg"), 12.0)
	assert_true(DesignerResponseEdits.set_slope_min(model, "oak", 0))
	assert_false(model.rule("oak").has("slope_min_deg"))
	assert_true(DesignerResponseEdits.set_preset(model, "oak", "slope", "none"))
	assert_false(model.rule("oak").has("response"), "an emptied response goes away")
	var checked := model.validation()
	assert_true((checked["errors"] as Array).is_empty(), str(checked["errors"]))
	while model.can_undo():
		model.undo()
	assert_false(model.rule("oak").has("response"))
	assert_false(model.is_dirty())


func test_a_broken_curve_is_an_error_on_its_field() -> void:
	var model := _model()
	model.set_field("oak", "response", {"slope": [[10, 0.2], [5, 0.9]]})
	var verdict := model.validation()
	assert_true(DesignerValidation.has_error(verdict, "oak", "response"), str(verdict))
	assert_false(model.compile()["ok"], "a draft with errors is not compiled")


# ---- validation and compile ----


func test_validation_names_the_rule_and_field() -> void:
	var model := _model()
	model.set_field("stones", "density_per_m2", -2)
	model.set_field("bushes", "slope_max_deg", 400)
	var verdict := model.validation()
	assert_true(DesignerValidation.has_error(verdict, "stones", "density_per_m2"))
	assert_true(DesignerValidation.has_error(verdict, "bushes", "slope_max_deg"))
	assert_false(DesignerValidation.has_error(verdict, "oak"))
	assert_eq(DesignerValidation.field_of("biomes/x.json rule 'a': weight must be a number"), "weight")
	assert_eq(DesignerValidation.rule_of("biomes/x.json rule 'abc': spacing_m"), "abc")
	assert_eq(DesignerValidation.rule_of("biome b_summer_s1 rule oak: no asset resolves"), "oak")


func test_compile_makes_one_palette_biome_per_season() -> void:
	var model := _model()
	var result := model.compile()
	assert_true(result["ok"], str(result["validation"]))
	var compiled: Dictionary = result["compiled"]
	assert_eq(compiled["biome_ids"], ["mini__meadow_summer_s1", "mini__meadow_autumn_s2"])
	var biome: Dictionary = compiled["palette"]["biomes"][0]
	assert_eq(biome["species"].size(), 3)
	assert_eq(biome["species"][0]["assets"], ["mini__meadow_summer_s1/Tree_oak_v0", "mini__meadow_summer_s1/Tree_oak_v1"])
	assert_eq(biome["species"][1]["assets"].size(), 1, "the filter picked one rock group")
	assert_true(float(result["msec"]) < 500.0)
	model.set_field("stones", "slope_min_deg", 20)
	DesignerResponseEdits.set_curve(model, "stones", "slope", [[0, 0.5], [60, 1.0]])
	var second := model.compile()
	var rule: Dictionary = second["compiled"]["palette"]["biomes"][0]["species"][1]
	assert_eq(rule["slope_min_deg"], 20)
	assert_eq(rule["response"]["slope"], [[0, 0.5], [60, 1.0]])


func test_a_rule_that_selects_nothing_is_dropped_with_a_warning_on_its_query() -> void:
	var model := _model()
	model.set_query("bushes", {"match": [{"category": "flower"}]})
	var result := model.compile()
	assert_true(result["ok"], "the other rules still compile")
	var biome: Dictionary = result["compiled"]["palette"]["biomes"][0]
	assert_eq(biome["species"].size(), 2)
	assert_false(DesignerValidation.for_field(result["validation"], "bushes", "query").is_empty())


func test_the_biome_edits() -> void:
	var model := _model()
	assert_true(DesignerBiomeEdits.set_ground(model, "cliff", "rock_grey"))
	assert_eq(DesignerBiomeEdits.ground_value(model, "cliff"), "rock_grey")
	assert_true(DesignerBiomeEdits.set_ground(model, "cliff", ""))
	assert_eq(DesignerBiomeEdits.ground_value(model, "cliff"), null)
	assert_false(DesignerBiomeEdits.set_ground(model, "sky", "x"))
	assert_true(DesignerBiomeEdits.set_accents(model, [{"surface": "dirt", "coverage": 0.2, "scale_m": 3}]))
	assert_true(DesignerBiomeEdits.set_ground_look(model, {"zones": {"tint": 0.2}}))
	assert_true(DesignerBiomeEdits.set_ground_look(model, null))
	assert_true(DesignerBiomeEdits.set_density_scale(model, "large", 0.5))
	assert_eq(model.def["density_scale"], {"large": 0.5})
	assert_true(DesignerBiomeEdits.set_seasons(model, [{"id": "summer", "seed": 1}]))
	assert_eq(model.runtime_ids().size(), 1)
	assert_false(DesignerBiomeEdits.set_seasons(model, []))
	assert_true(DesignerBiomeEdits.set_info(model, "name", "Green Meadow"))
	assert_true((model.validation()["errors"] as Array).is_empty())
	while model.can_undo():
		model.undo()
	assert_false(model.is_dirty())


# ---- save, revert, locks ----


func test_save_writes_the_biome_and_reads_back_equal() -> void:
	var model := _model()
	model.set_field("oak", "spacing_m", 6)
	model.add_rule("rock", {"match": [{"ref": "Rock_rock_a"}]})
	assert_true(model.is_dirty())
	var written := model.save()
	assert_true(written["ok"], str(written))
	assert_false(model.is_dirty())
	var text := FileAccess.get_file_as_string(_folder + "/biomes/meadow.json")
	assert_true(text.ends_with("\n"))
	var again := JSON.parse_string(text) as Dictionary
	assert_eq(again["rules"][0]["spacing_m"], 6.0)
	assert_false("35.0" in text, "whole numbers are written as integers")
	var errors: Array[String] = []
	var warnings: Array[String] = []
	assert_true(LibraryReader.check_biome(again, "meadow.json", errors, warnings), str(errors))


func test_an_official_library_cannot_be_saved() -> void:
	var model := _model(false)
	model.set_field("oak", "weight", 2)
	var written := model.save()
	assert_false(written["ok"])
	assert_true("read-only" in written["error"])
	assert_false(FileAccess.file_exists(_folder + "/biomes/meadow.json"))


func test_a_draft_with_errors_is_not_saved() -> void:
	var model := _model()
	model.set_field("oak", "density_per_m2", -1)
	assert_false(model.save()["ok"])
	assert_false(FileAccess.file_exists(_folder + "/biomes/meadow.json"))


func test_revert_restores_the_saved_draft() -> void:
	var model := _model()
	model.set_field("oak", "weight", 9)
	model.revert()
	assert_eq(model.value("oak", "weight"), 1)
	assert_false(model.is_dirty())
	assert_false(model.can_undo())


func test_changes_are_announced() -> void:
	var model := _model()
	watch_signals(model)
	model.set_field("oak", "weight", 2)
	model.undo()
	assert_signal_emit_count(model, "changed", 2)
	model.save()
	assert_signal_emitted(model, "saved")


func test_locking_freezes_the_selection_and_survives_a_save() -> void:
	var model := _model()
	model.set_query("stones", {"match": [{"category": "rock"}], "count": 1})
	var before := model.resolved_assets("stones")
	assert_true(model.set_locked("stones", true))
	assert_true(model.is_locked("stones"))
	assert_true(model.is_dirty(), "locking is an unsaved change")
	assert_true(model.save()["ok"])
	assert_true(FileAccess.file_exists(_folder + "/biomes/meadow.lock.json"))
	var lock := JSON.parse_string(FileAccess.get_file_as_string(_folder + "/biomes/meadow.lock.json")) as Dictionary
	assert_eq(lock["format"], "ttsim-biome-lock")
	assert_eq((lock["rules"] as Dictionary).keys(), ["autumn/stones", "summer/stones"])
	assert_eq(lock["rules"]["summer/stones"]["assets"], [before[0]["ref"]])
	# A reader of the folder's files compiles to the locked asset even if the catalog grows.
	var catalog := _catalog()
	catalog["assets"].append(_entry("Rock_aaa", "aaa", "rock", "small", ["mineral"]))
	var library := {"format": "ttsim-library", "format_version": 1, "id": "mini", "name": "Mini", "version": "0.2.0", "contract": 1}
	var read := LibraryReader.read(
		{
			"library": JSON.stringify(library),
			"catalog": JSON.stringify(catalog),
			"biomes": {"meadow.json": FileAccess.get_file_as_string(_folder + "/biomes/meadow.json")},
			"locks": {"meadow.lock.json": FileAccess.get_file_as_string(_folder + "/biomes/meadow.lock.json")},
		}
	)
	assert_true(read["ok"], str(read["errors"]))
	var compiled := BiomeCompiler.compile(read, {"surfaces": {}})
	var assets: Array = compiled["palette"]["biomes"][0]["species"][1]["assets"]
	assert_eq(assets, ["mini__meadow_summer_s1/" + String(before[0]["local"])])
	assert_true(model.set_locked("stones", false))
	assert_true(model.save()["ok"])
	assert_false(FileAccess.file_exists(_folder + "/biomes/meadow.lock.json"), "no locks, no file")


# ---- duplicate as new collection ----


func test_duplicate_as_new_collection_depends_on_the_source() -> void:
	var model := _model(false)
	model.add_clause("oak", {"ref": "Tree_pine_v0"})
	model.set_pin("stones", "Rock_rock_b", true)
	var made := LibraryWriter.create_collection(
		ROOT + "/user", "my_meadow", "My Meadow", model.context, "meadow", model.def
	)
	assert_true(made["ok"], str(made))
	var folder: String = made["folder"]
	var library := JSON.parse_string(FileAccess.get_file_as_string(folder + "/library.json")) as Dictionary
	assert_eq(library["id"], "my_meadow")
	assert_eq(library["dependencies"], [{"id": "mini", "version": "^0.2"}])
	var biome := JSON.parse_string(FileAccess.get_file_as_string(folder + "/biomes/meadow.json")) as Dictionary
	assert_eq(biome["rules"][0]["query"]["match"][0], {"ref": "mini:Tree_oak_v0"})
	assert_eq(biome["rules"][1]["query"]["pin"], ["mini:Rock_rock_b"])
	assert_eq(biome["surfaces"], "library")
	# The copy reads clean and compiles against the source as its dependency.
	var read := LibraryReader.read(
		{
			"library": FileAccess.get_file_as_string(folder + "/library.json"),
			"catalog": FileAccess.get_file_as_string(folder + "/assets/catalog.json"),
			"biomes": {"meadow.json": FileAccess.get_file_as_string(folder + "/biomes/meadow.json")},
		}
	)
	assert_true(read["ok"], str(read["errors"]))
	var compiled := BiomeCompiler.compile(
		read, {"surfaces": {}, "dependencies": {"mini": {"read": model.context["read"], "folder": _folder}}}
	)
	var species: Array = compiled["palette"]["biomes"][0]["species"]
	assert_eq(species.size(), 3)
	assert_eq(species[0]["assets"][0], "my_meadow__meadow_summer_s1/mini__Tree_oak_v0")
	assert_eq(species[0]["assets"].size(), 3)
	var again := LibraryWriter.create_collection(ROOT + "/user", "my_meadow", "x", model.context, "meadow", model.def)
	assert_false(again["ok"], "an existing library is never overwritten")
	for reserved in ["core", "draft", "Bad Id", ""]:
		assert_false(
			LibraryWriter.create_collection(ROOT + "/user", reserved, "x", model.context, "meadow", model.def)["ok"],
			"refused: '%s'" % reserved
		)


func test_dependency_ranges() -> void:
	assert_eq(LibraryWriter.dependency_range("1.0.0-dev"), "^1.0")
	assert_eq(LibraryWriter.dependency_range("2.3.4"), "^2.3")
	assert_eq(LibraryWriter.dependency_range("weird"), "*")
