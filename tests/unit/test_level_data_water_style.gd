extends GutTest

## Round-trip tests for LevelData.water_style -- mirrors
## tests/unit/test_level_data_visual_settings.gd's style for a simple scalar
## field.


func test_to_dict_includes_water_style() -> void:
	var level := LevelData.new()
	level.water = WaterSettings.from_style("realistic")

	var data := level.to_dict()

	assert_eq(data["water_style"], "realistic")


func test_to_dict_writes_water_overrides_and_matching_look() -> void:
	var level := LevelData.new()
	level.water = WaterSettings.from_style("realistic")

	var data := level.to_dict()

	assert_eq(data["water_style"], "realistic")
	assert_eq(data["water_overrides"], level.water.to_dict())
	assert_typeof(data["water_overrides"]["water_color"], TYPE_STRING)


func test_to_dict_writes_custom_style_after_an_edit() -> void:
	var level := LevelData.new()
	level.water.roughness_value = 0.33

	assert_eq(level.to_dict()["water_style"], "custom")


func test_from_dict_restores_water_overrides() -> void:
	var settings := WaterSettings.default()
	settings.water_color = Color(0.2, 0.3, 0.4, 0.5)
	settings.caustic_scale = 2.5
	var data := {"water_style": "stylized", "water_overrides": settings.to_dict()}

	var level := LevelData.from_dict(data)

	assert_eq(level.water.to_dict(), settings.to_dict())


func test_from_dict_without_overrides_seeds_from_water_style() -> void:
	var level := LevelData.from_dict({"water_style": "realistic"})

	assert_eq(level.water.matching_look(), "realistic")
	assert_eq(level.water.matching_palette(), "lake")
	assert_eq(level.water.matching_motion(), "gentle")


func test_from_dict_without_anything_is_default_water() -> void:
	var level := LevelData.from_dict({})

	assert_eq(level.water.to_dict(), WaterSettings.default().to_dict())


func test_duplicate_level_copies_water_independently() -> void:
	var level := LevelData.new()
	level.water.wave_speed = 1.7

	var copy := level.duplicate_level()
	copy.water.wave_speed = 0.1

	assert_almost_eq(level.water.wave_speed, 1.7, 0.0001)


func test_legacy_tres_water_overrides_property_is_absorbed() -> void:
	var level := LevelData.new()
	var settings := WaterSettings.default()
	settings.foam_strength = 1.9

	level.set("water_overrides", settings.to_dict())

	assert_almost_eq(level.water.foam_strength, 1.9, 0.0001)


func test_from_dict_restores_water_style() -> void:
	var data := {"water_style": "realistic"}

	var level := LevelData.from_dict(data)

	assert_eq(level.water_style, "realistic")


func test_from_dict_defaults_to_stylized_when_missing() -> void:
	var level := LevelData.from_dict({})

	assert_eq(level.water_style, "stylized")


func test_duplicate_level_copies_water_style() -> void:
	var level := LevelData.new()
	level.water_style = "realistic"

	var copy := level.duplicate_level()

	assert_eq(copy.water_style, "realistic")
