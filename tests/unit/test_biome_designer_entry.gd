extends GutTest

## The way into the biome designer and the live session on a real map (step S8a), over the small
## multi-library world of tests/unit/library_world.gd (`core` official, `alienworld` the player's):
## which biomes the picker offers and which of them can be saved, preparing a session (the draft
## compiled and laid over the palette before the proving ground is built), "New biome from a core
## biome" (a user collection that depends on core), and an edit going all the way to the plants on
## a proving ground built from the library's own biome: compile, lay over, partial regeneration.

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_biome_designer_entry"
const ALIEN := "alienworld"
const TREES_ASSET := World.ALIEN_RUNTIME + "/Crystal_Spire_v0"
const SHARD_ASSET := World.ALIEN_RUNTIME + "/Crystal_Shard_v0"

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
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply()


func _row(rows: Array[Dictionary], library: String) -> Dictionary:
	for row in rows:
		if row["library"] == library:
			return row
	return {}


## A map for `model`'s proving ground with its plants grown, and a session over it.
func _live(model: BiomeDesignerModel) -> Dictionary:
	var document := ProvingGround.build(World.ALIEN_RUNTIME)
	var scatter := AuthoredScatter.new()
	add_child_autofree(scatter)
	scatter.attach_document(document)
	scatter.grow_seconds = 0.0
	scatter.request_region(Rect2(-document.extent_m() * 0.5, document.extent_m()))
	await _await_regeneration(scatter)
	# The two wind assets (the spire and core's oak) warn once that their vertex format is not
	# the graphics warm-up's: the test GLBs are not the game's.
	assert_engine_error(2, "the fixture GLBs differ from the warm-up's vertex format")
	var controller := AuthoringController.new()
	controller.scatter = scatter
	controller.document = document
	add_child_autofree(controller)
	var session := BiomeDesignerSession.new()
	session.debounce = 0.0
	add_child_autofree(session)
	session.setup(model, controller)
	return {"scatter": scatter, "session": session}


func _await_regeneration(scatter: AuthoredScatter) -> void:
	var frames := 0
	while (scatter.is_regenerating() or scatter.is_growing()) and frames < 600:
		await get_tree().process_frame
		frames += 1
	scatter.complete_growth()


func _rows_of(scatter: AuthoredScatter, asset_id: String) -> int:
	var rows: PackedFloat32Array = scatter.rows_by_asset().get(asset_id, PackedFloat32Array())
	return rows.size() / MapDocument.ROW_STRIDE


# ---- what the picker offers ----


func test_designable_lists_the_biomes_and_says_which_can_be_saved() -> void:
	var rows := BiomeDesignerEntry.designable()
	var core := _row(rows, "core")
	var alien := _row(rows, ALIEN)
	assert_eq(core["biome"], "forest")
	assert_false(core["writable"], "an official library is read-only")
	assert_true(core["official"])
	assert_eq(alien["biome"], "crystal_basin")
	assert_true(alien["writable"])
	assert_eq(alien["library_name"], "Alien World")
	assert_false(LibraryRegistry.designer_writable("core", "dev"), "core is never written")
	assert_true(LibraryRegistry.designer_writable("mine", "dev"))
	assert_false(LibraryRegistry.designer_writable("mine", "official"))


# ---- preparing a session ----


func test_prepare_compiles_the_draft_over_the_palette_and_builds_the_request() -> void:
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	assert_true(prepared["ok"], str(prepared["error"]))
	assert_eq(prepared["runtime_id"], World.ALIEN_RUNTIME)
	var request: Dictionary = prepared["request"]
	assert_eq(request["new_map"]["proving_ground"], World.ALIEN_RUNTIME)
	assert_eq(request["designer"]["model"], prepared["model"])
	assert_true((request["level"] as LevelData).level_name.begins_with("Designing"))
	var biome := PaletteLibrary.biome(World.ALIEN_RUNTIME)
	assert_false(biome.is_empty(), "the draft is in the palette before the map is built")
	assert_eq(biome["species"].size(), 2)


func test_prepare_refuses_what_is_not_there() -> void:
	assert_false(BiomeDesignerEntry.prepare("nobody", "x")["ok"])
	var missing := BiomeDesignerEntry.prepare(ALIEN, "no_such_biome")
	assert_false(missing["ok"])
	assert_true("no biome" in String(missing["error"]))


func test_a_core_biome_opens_read_only() -> void:
	var prepared := BiomeDesignerEntry.prepare("core", "forest")
	assert_true(prepared["ok"], str(prepared["error"]))
	var model: BiomeDesignerModel = prepared["model"]
	assert_false(model.writable)
	model.set_field("trees", "weight", 3)
	assert_false(model.save()["ok"])


# ---- new biome from a core biome ----


func test_new_from_makes_a_collection_that_depends_on_the_source() -> void:
	var made := BiomeDesignerEntry.new_from("core", "forest", "my_forest", "My Forest")
	assert_true(made["ok"], str(made["error"]))
	assert_true(DirAccess.dir_exists_absolute(_paths["user"] + "/my_forest"))
	var entry := LibraryRegistry.info("my_forest")
	assert_eq(entry["status"], "ok", str(entry["reasons"]))
	assert_eq(entry["source"], "user")
	assert_eq(entry["dependencies"], [{"id": "core", "version": "^1.2"}])
	var prepared := BiomeDesignerEntry.prepare("my_forest", "forest")
	assert_true(prepared["ok"], str(prepared["error"]))
	var model: BiomeDesignerModel = prepared["model"]
	assert_true(model.writable)
	assert_eq(model.runtime_ids(), ["my_forest__forest_summer_s1"])
	var biome := PaletteLibrary.biome("my_forest__forest_summer_s1")
	var assets: Array = biome["species"][0]["assets"]
	assert_eq(assets[0], "my_forest__forest_summer_s1/core__Tree_Oak_v0", "the plants stay in core")
	model.set_field("trees", "density_per_m2", 0.5)
	assert_true(model.save()["ok"])
	var path: String = _paths["user"] + "/my_forest/biomes/forest.json"
	var saved := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	assert_eq(saved["rules"][0]["density_per_m2"], 0.5)
	assert_eq(saved["rules"][0]["query"]["match"][0]["ref"], "core:Tree_Oak_v0")


func test_new_from_refuses_a_taken_or_reserved_id() -> void:
	assert_false(BiomeDesignerEntry.new_from("core", "forest", ALIEN, "Alien")["ok"])
	assert_false(BiomeDesignerEntry.new_from("core", "forest", "core", "Core")["ok"])
	assert_false(BiomeDesignerEntry.new_from("nobody", "forest", "mine", "Mine")["ok"])


# ---- an edit all the way to the plants ----


func test_an_edit_regenerates_the_plants_of_the_proving_ground() -> void:
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	assert_true(prepared["ok"], str(prepared["error"]))
	var model: BiomeDesignerModel = prepared["model"]
	var live := await _live(model)
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var trees_before := _rows_of(scatter, TREES_ASSET)
	assert_true(trees_before > 5, "%d crystal spires" % trees_before)
	assert_true(_rows_of(scatter, SHARD_ASSET) > 5)
	watch_signals(session)
	model.set_field("trees", "density_per_m2", 0.0)
	await get_tree().create_timer(0.1).timeout
	await _await_regeneration(scatter)
	assert_signal_emitted(session, "compiled")
	assert_signal_emitted(session, "regenerated")
	assert_eq(_rows_of(scatter, TREES_ASSET), 0, "no spires once their density is 0")
	assert_true(_rows_of(scatter, SHARD_ASSET) > 0, "the shards stay")
	assert_true(session.stats["total_ms"] > 0.0)
	assert_eq(session.stats["of"], 2)
	model.undo()
	await get_tree().create_timer(0.1).timeout
	await _await_regeneration(scatter)
	assert_eq(_rows_of(scatter, TREES_ASSET), trees_before, "undo brings the same spires back")


func test_removing_a_rule_clears_its_plants_and_the_budget_counts_the_rest() -> void:
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	var model: BiomeDesignerModel = prepared["model"]
	var live := await _live(model)
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var before := session.budget()
	assert_true(before["instances"] > 0)
	assert_eq(before["by_rule"].keys().size(), 2)
	model.remove_rule("trees")
	await get_tree().create_timer(0.1).timeout
	await _await_regeneration(scatter)
	assert_eq(_rows_of(scatter, TREES_ASSET), 0)
	assert_eq(session.rule_of_asset(SHARD_ASSET), "stones")
	var after := session.budget()
	assert_true(after["instances"] < before["instances"])
	assert_true(after["triangles"] < before["triangles"])


func test_an_invalid_draft_keeps_the_last_good_map() -> void:
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	var model: BiomeDesignerModel = prepared["model"]
	var live := await _live(model)
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var trees := _rows_of(scatter, TREES_ASSET)
	watch_signals(session)
	model.set_field("trees", "density_per_m2", -4)
	await get_tree().create_timer(0.1).timeout
	assert_signal_emitted(session, "compiled")
	var result: Dictionary = get_signal_parameters(session, "compiled")[0]
	assert_false(result["ok"])
	assert_false(scatter.is_regenerating())
	assert_eq(_rows_of(scatter, TREES_ASSET), trees, "nothing changed on the map")
	assert_signal_not_emitted(session, "regenerated")


func test_switching_the_season_moves_the_map_to_that_seasons_plants() -> void:
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(data: Dictionary) -> void:
			data["seasons"] = [{"id": "summer", "seed": 1}, {"id": "autumn", "seed": 2}]
	)
	LibraryRegistry.apply()
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	assert_true(prepared["ok"], str(prepared["error"]))
	var model: BiomeDesignerModel = prepared["model"]
	assert_eq(model.runtime_ids().size(), 2)
	var live := await _live(model)
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var autumn := "alienworld__crystal_basin_autumn_s2/Crystal_Spire_v0"
	assert_true(_rows_of(scatter, TREES_ASSET) > 5)
	assert_eq(_rows_of(scatter, autumn), 0)
	session.set_season(1)
	assert_eq(
		session.controller.document.biome_ids,
		PackedStringArray(["alienworld__crystal_basin_autumn_s2"])
	)
	await get_tree().create_timer(0.1).timeout
	await _await_regeneration(scatter)
	assert_engine_error(4, "the summer and the autumn plants warn once each")
	assert_eq(_rows_of(scatter, TREES_ASSET), 0, "the summer plants are gone")
	assert_true(_rows_of(scatter, autumn) > 5, "the autumn plants stand")
	session.set_season(0)
	await get_tree().create_timer(0.1).timeout
	await _await_regeneration(scatter)
	assert_eq(_rows_of(scatter, autumn), 0)
	assert_true(_rows_of(scatter, TREES_ASSET) > 5)
