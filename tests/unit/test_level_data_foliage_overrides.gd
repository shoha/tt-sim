extends GutTest

## Round-trip tests for LevelData.foliage_overrides -- the flat-key override
## dictionary (see WindFoliage.get_effective_preset) that lets a level tune
## per-category wind-sway speed/amplitude. Mirrors the existing serialization
## for weather_overrides/lofi_overrides. There is no existing test_level_data.gd
## to extend, matching this test suite's per-feature file convention (see
## test_glb_utils_lighting_extras.gd / test_level_environment_manager_lighting_extras.gd).


func test_to_dict_includes_foliage_overrides() -> void:
	var level := LevelData.new()
	level.foliage_overrides = {"tree_sway_speed": 1.2, "grass_sway_amplitude": 0.05}

	var data := level.to_dict()

	assert_eq(data["foliage_overrides"], {"tree_sway_speed": 1.2, "grass_sway_amplitude": 0.05})


func test_from_dict_restores_foliage_overrides() -> void:
	var data := {"foliage_overrides": {"grass_sway_speed": 2.5}}

	var level := LevelData.from_dict(data)

	assert_eq(level.foliage_overrides, {"grass_sway_speed": 2.5})


func test_from_dict_defaults_to_empty_dict_when_missing() -> void:
	var level := LevelData.from_dict({})

	assert_eq(level.foliage_overrides, {})


func test_duplicate_level_copies_foliage_overrides_independently() -> void:
	var level := LevelData.new()
	level.foliage_overrides = {"tree_sway_speed": 1.2}

	var copy := level.duplicate_level()
	copy.foliage_overrides["tree_sway_speed"] = 9.9

	assert_eq(level.foliage_overrides["tree_sway_speed"], 1.2)
