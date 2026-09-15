extends GutTest

## LevelVisualState is the one snapshot/apply/broadcast unit for everything the
## Visuals drawer edits. These tests pin the round trips the drawer's Cancel and
## Save paths and the client receive path depend on.


func _make_level() -> LevelData:
	var level := LevelData.new()
	level.light_intensity_scale = 0.5
	level.environment_preset = "outdoor_day"
	level.environment_overrides = {"ambient_light_energy": 2.0, "fog_light_color": Color.RED}
	level.water_style = "realistic"
	level.lofi.pixelation = 0.05
	level.weather.rain_intensity = 0.7
	level.foliage.tree_sway_speed = 1.5
	level.visual_settings.sun.azimuth_degrees = 123.0
	level.grid_cell_size = 2.0
	level.display_unit = "m"
	level.display_unit_per_cell = 1.5
	return level


func test_from_level_data_then_apply_round_trips() -> void:
	var level := _make_level()
	var state := LevelVisualState.from_level_data(level)
	var target := LevelData.new()

	state.apply_to_level_data(target)

	assert_eq(target.to_dict()["light_intensity_scale"], 0.5)
	assert_eq(target.environment_preset, "outdoor_day")
	assert_eq(target.environment_overrides["fog_light_color"], Color.RED)
	assert_eq(target.water_style, "realistic")
	assert_almost_eq(target.lofi.pixelation, 0.05, 0.000001)
	assert_almost_eq(target.weather.rain_intensity, 0.7, 0.000001)
	assert_almost_eq(target.foliage.tree_sway_speed, 1.5, 0.000001)
	assert_almost_eq(target.visual_settings.sun.azimuth_degrees, 123.0, 0.000001)
	assert_almost_eq(target.grid_cell_size, 2.0, 0.000001)
	assert_eq(target.display_unit, "m")
	assert_almost_eq(target.display_unit_per_cell, 1.5, 0.000001)


func test_snapshot_is_independent_of_the_level() -> void:
	var level := _make_level()
	var state := LevelVisualState.from_level_data(level)

	level.lofi.pixelation = 9.0
	level.environment_overrides["ambient_light_energy"] = 9.0
	level.visual_settings.sun.azimuth_degrees = 9.0

	assert_almost_eq(state.lofi.pixelation, 0.05, 0.000001)
	assert_eq(state.environment_overrides["ambient_light_energy"], 2.0)
	assert_almost_eq(state.sun.azimuth_degrees, 123.0, 0.000001)


func test_apply_does_not_alias_the_state() -> void:
	var state := LevelVisualState.from_level_data(_make_level())
	var target := LevelData.new()
	state.apply_to_level_data(target)

	target.weather.rain_intensity = 0.0
	target.environment_overrides.clear()
	target.visual_settings.sun.azimuth_degrees = 0.0

	assert_almost_eq(state.weather.rain_intensity, 0.7, 0.000001)
	assert_eq(state.environment_overrides.size(), 2)
	assert_almost_eq(state.sun.azimuth_degrees, 123.0, 0.000001)


func test_copy_is_independent() -> void:
	var state := LevelVisualState.from_level_data(_make_level())
	var copy := state.copy()
	copy.foliage.tree_sway_speed = 9.0
	copy.water_style = "stylized"
	assert_almost_eq(state.foliage.tree_sway_speed, 1.5, 0.000001)
	assert_eq(state.water_style, "realistic")


func test_to_broadcast_dict_has_the_network_keys() -> void:
	var state := LevelVisualState.from_level_data(_make_level())

	var data := state.to_broadcast_dict()

	var expected: Array[String] = [
		"light_intensity",
		"environment_preset",
		"environment_overrides",
		"lofi_overrides",
		"weather_overrides",
		"foliage_overrides",
		"sun_settings",
		"water_style",
	]
	for key in expected:
		assert_true(data.has(key), key)
	assert_eq(data.keys().size(), expected.size())
	assert_eq(data["light_intensity"], 0.5)
	assert_almost_eq(float(data["sun_settings"]["azimuth_degrees"]), 123.0, 0.000001)
	assert_almost_eq(float(data["weather_overrides"]["rain_intensity"]), 0.7, 0.000001)
	assert_eq(data["environment_overrides"]["fog_light_color"], Color.RED)


func test_patch_updates_only_present_keys() -> void:
	var state := LevelVisualState.from_level_data(_make_level())

	state.patch_from_broadcast_dict(
		{"lofi_overrides": {"pixelation": 0.2}, "water_style": "stylized"}
	)

	assert_almost_eq(state.lofi.pixelation, 0.2, 0.000001)
	assert_eq(state.water_style, "stylized")
	assert_almost_eq(state.weather.rain_intensity, 0.7, 0.000001, "untouched")
	assert_eq(state.environment_preset, "outdoor_day", "untouched")


func test_patch_environment_takes_overrides_only_with_preset() -> void:
	var state := LevelVisualState.from_level_data(_make_level())

	state.patch_from_broadcast_dict({"environment_preset": "", "environment_overrides": {}})

	assert_eq(state.environment_preset, "")
	assert_eq(state.environment_overrides.size(), 0)


func test_patch_sun_from_dict() -> void:
	var state := LevelVisualState.from_level_data(_make_level())
	var sun := SunSettings.default()
	sun.elevation_degrees = 12.0

	state.patch_from_broadcast_dict({"sun_settings": sun.to_dict()})

	assert_almost_eq(state.sun.elevation_degrees, 12.0, 0.000001)


func test_broadcast_round_trip_through_patch() -> void:
	var state := LevelVisualState.from_level_data(_make_level())
	var other := LevelVisualState.from_level_data(LevelData.new())

	other.patch_from_broadcast_dict(state.to_broadcast_dict())

	assert_eq(other.to_broadcast_dict()["light_intensity"], 0.5)
	assert_eq(other.environment_preset, "outdoor_day")
	assert_almost_eq(other.foliage.tree_sway_speed, 1.5, 0.000001)
	assert_almost_eq(other.sun.azimuth_degrees, 123.0, 0.000001)
