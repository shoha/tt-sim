extends GutTest

## Round-trip tests for LevelData.water_style -- mirrors
## tests/unit/test_level_data_sun_overrides.gd's style for a simple scalar field.


func test_to_dict_includes_water_style() -> void:
	var level := LevelData.new()
	level.water_style = "realistic"

	var data := level.to_dict()

	assert_eq(data["water_style"], "realistic")


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
