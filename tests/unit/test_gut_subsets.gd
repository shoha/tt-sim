extends GutTest

## The named GUT subsets (tests/.gutconfig_*.json, the inner-loop runs in AGENTS.md "Running
## tests from the CLI") list their scripts by path. GUT only logs "Could not find script" for a
## listed path that is gone and runs the rest, so a renamed or deleted script would drop out of
## its subset without failing anything. This test runs in the full suite and fails instead.

const TESTS_DIR := "res://tests/"
const SUBSET_PREFIX := ".gutconfig_"
## The subsets AGENTS.md documents. A scan that misses one means the scan itself broke (the
## files start with a dot, which DirAccess treats as hidden on some platforms).
const DOCUMENTED_SUBSETS := ["avatar", "authoring", "net", "ui"]


## The subset config file names under tests/ (not the full run's .gutconfig.json).
func _subset_configs() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return found
	dir.include_hidden = true
	for file_name in dir.get_files():
		if file_name.begins_with(SUBSET_PREFIX) and file_name.ends_with(".json"):
			found.append(file_name)
	return found


func test_every_documented_subset_has_a_config() -> void:
	var configs := _subset_configs()
	for subset in DOCUMENTED_SUBSETS:
		assert_has(configs, "%s%s.json" % [SUBSET_PREFIX, subset])


func test_every_listed_script_exists() -> void:
	var configs := _subset_configs()
	assert_gt(configs.size(), 0, "found subset configs under " + TESTS_DIR)
	for file_name in configs:
		var config: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(TESTS_DIR + file_name)
		)
		assert_typeof(config, TYPE_DICTIONARY, file_name + " parses to an object")
		if not config is Dictionary:
			continue
		var scripts: Array = config.get("tests", [])
		assert_gt(scripts.size(), 0, file_name + " lists scripts")
		for path in scripts:
			assert_true(
				FileAccess.file_exists(path),
				"%s lists %s, which does not exist" % [file_name, path]
			)
