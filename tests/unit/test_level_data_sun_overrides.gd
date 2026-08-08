extends GutTest

## Round-trip tests for LevelData.sun_overrides -- the flat-key override
## dictionary (see DefaultSun.configure_directional_light and
## LevelEnvironmentManager) that lets a level pick a sun mode ("auto" | "on" |
## "off") and time of day. Mirrors the existing serialization for
## weather_overrides/foliage_overrides.


func test_to_dict_includes_sun_overrides() -> void:
	var level := LevelData.new()
	level.sun_overrides = {"mode": "on", "time_of_day": 8.0}

	var data := level.to_dict()

	assert_eq(data["sun_overrides"], {"mode": "on", "time_of_day": 8.0})


func test_from_dict_restores_sun_overrides() -> void:
	var data := {"sun_overrides": {"mode": "off"}}

	var level := LevelData.from_dict(data)

	assert_eq(level.sun_overrides, {"mode": "off"})


func test_from_dict_defaults_to_empty_dict_when_missing() -> void:
	var level := LevelData.from_dict({})

	assert_eq(level.sun_overrides, {})


func test_duplicate_level_copies_sun_overrides_independently() -> void:
	var level := LevelData.new()
	level.sun_overrides = {"mode": "on"}

	var copy := level.duplicate_level()
	copy.sun_overrides["mode"] = "off"

	assert_eq(level.sun_overrides["mode"], "on")
