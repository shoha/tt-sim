extends GutTest

## The lock commands and words of the biome designer (step S9, DesignerLocks over
## BiomeDesignerModel): locking a rule or the whole biome, how a lock stands (locked, stale because
## the query changed, stale because the catalogs now give other plants), taking a lock again, the
## summary the slot list shows, and the lock file Save writes and a reader gets back. The library
## is the designer fixture.

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_designer_locks/mini"

var _model: BiomeDesignerModel = null


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER + "/biomes")
	_model = BiomeDesignerModel.from_context(Fixture.context(FOLDER, true), "meadow")
	# A filter rule, so a lock has something to freeze beyond the explicit refs.
	_model.set_query("stones", {"match": [{"category": "rock"}], "count": 1, "order": "id"})


func after_all() -> void:
	for file_name in DirAccess.get_files_at(FOLDER + "/biomes"):
		DirAccess.remove_absolute(FOLDER + "/biomes/" + file_name)


func test_a_rule_is_unlocked_locked_and_unlocked_again() -> void:
	assert_eq(DesignerLocks.state(_model, "stones")["state"], "unlocked")
	assert_true(_model.set_locked("stones", true))
	var state := DesignerLocks.state(_model, "stones")
	assert_eq(state["state"], "locked")
	assert_eq(state["seasons"].keys(), ["summer", "autumn"])
	assert_eq(state["seasons"]["summer"]["held"], ["Rock_rock_a"])
	assert_true(_model.is_locked("stones"))
	assert_false(_model.set_locked("stones", true), "no change")
	assert_true(_model.set_locked("stones", false))
	assert_eq(DesignerLocks.state(_model, "stones")["state"], "unlocked")


func test_a_changed_query_makes_the_lock_stale() -> void:
	_model.set_locked("stones", true)
	_model.set_query_field("stones", "order", "hash")
	assert_eq(DesignerLocks.state(_model, "stones")["state"], "stale_query")
	assert_true(DesignerLocks.refresh(_model, "stones"))
	assert_eq(DesignerLocks.state(_model, "stones")["state"], "locked")
	assert_false(DesignerLocks.refresh(_model, "oak"), "an unlocked rule has nothing to take again")


func test_other_plants_in_the_catalog_make_it_stale_in_its_own_way() -> void:
	_model.set_locked("stones", true)
	_model.locks["summer/stones"]["assets"] = ["Rock_rock_b"]
	var state := DesignerLocks.state(_model, "stones")
	assert_eq(state["state"], "stale_catalog")
	assert_eq(state["seasons"]["summer"]["held"], ["Rock_rock_b"])
	assert_eq(state["seasons"]["summer"]["now"], ["Rock_rock_a"])
	assert_eq(state["seasons"]["autumn"]["state"], "locked", "the other season is as it was")


func test_the_compiler_uses_a_good_lock_and_ignores_a_stale_one() -> void:
	_model.set_locked("stones", true)
	_model.locks["summer/stones"]["assets"] = ["Rock_rock_b"]
	_model.locks["autumn/stones"]["assets"] = ["Rock_rock_b"]
	var result := _model.compile()
	var biome: Dictionary = result["compiled"]["palette"]["biomes"][0]
	assert_eq(biome["species"][1]["assets"], ["mini__meadow_summer_s1/Rock_rock_b"], "the lock wins")
	_model.set_query_field("stones", "order", "hash")
	result = _model.compile()
	var warnings := "\n".join(PackedStringArray(result["compiled"]["warnings"]))
	assert_true("lock file is stale" in warnings, "the compiler says so: %s" % warnings)


func test_lock_all_and_unlock_all_are_one_step_each() -> void:
	assert_true(DesignerLocks.set_all(_model, true))
	for key in _model.rule_keys():
		assert_true(_model.is_locked(key), key)
	assert_false(DesignerLocks.set_all(_model, true), "already locked")
	var summary := DesignerLocks.summary(_model)
	assert_eq(summary["locked"], 3)
	assert_eq(summary["total"], 3)
	assert_eq(summary["stale"], 0)
	assert_eq(summary["saved"], 0)
	assert_true(DesignerLocks.changed(_model))
	assert_true(DesignerLocks.set_all(_model, false))
	assert_eq(DesignerLocks.summary(_model)["locked"], 0)
	assert_false(DesignerLocks.changed(_model), "unlocked again is the saved state")


func test_save_writes_the_lock_file_and_a_reader_gets_it_back() -> void:
	DesignerLocks.set_all(_model, true)
	var written := _model.save()
	assert_true(written["ok"], str(written))
	assert_false(DesignerLocks.changed(_model), "what is written is the saved state")
	assert_eq(DesignerLocks.summary(_model)["saved"], 3)
	var path := FOLDER + "/biomes/meadow.lock.json"
	assert_true(FileAccess.file_exists(path))
	var lock := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	assert_eq(lock["format"], LibraryContracts.FORMAT_LOCK)
	assert_eq(lock["biome"], "meadow")
	assert_eq(lock["rules"]["summer/stones"]["assets"], ["Rock_rock_a"])
	DesignerLocks.set_all(_model, false)
	assert_true(_model.save()["ok"])
	assert_false(FileAccess.file_exists(path), "no locks, no lock file")


func test_a_lock_survives_undo_of_other_edits() -> void:
	_model.set_locked("stones", true)
	_model.set_field("oak", "weight", 2)
	assert_true(_model.undo())
	assert_true(_model.is_locked("stones"))
	assert_eq(DesignerLocks.state(_model, "stones")["state"], "locked")
