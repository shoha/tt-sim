extends GutTest

## Unit tests for DefaultSun (utils/default_sun.gd) -- keyframe interpolation of
## sun elevation, azimuth, color, and energy by time of day.
##
## DefaultSun is a generator, not the lighting interface: settings_for_time()
## produces a SunSettings that a level then stores and the user is free to
## hand-edit, and apply() is a dumb applier with no interpolation of its own.
## Time of day only drives the sun light, never the separate Environment and
## ambient config (see LevelEnvironmentManager).


func test_settings_for_time_matches_noon_keyframe_exactly() -> void:
	var noon: Dictionary = DefaultSun.KEYFRAMES[12.0]

	var s := DefaultSun.settings_for_time(12.0)

	assert_almost_eq(s.elevation_degrees, float(noon["elevation_degrees"]), 0.001)
	assert_almost_eq(s.azimuth_degrees, float(noon["azimuth_degrees"]), 0.001)
	assert_eq(s.color, noon["color"])
	assert_almost_eq(s.energy, float(noon["energy"]), 0.001)


func test_settings_for_time_matches_night_keyframe_at_zero_and_twentyfour() -> void:
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]

	assert_almost_eq(DefaultSun.settings_for_time(0.0).energy, float(night["energy"]), 0.001)
	assert_almost_eq(DefaultSun.settings_for_time(24.0).energy, float(night["energy"]), 0.001)


func test_settings_for_time_interpolates_halfway_between_night_and_dawn() -> void:
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]
	var dawn: Dictionary = DefaultSun.KEYFRAMES[6.0]
	var expected_elevation: float = lerpf(
		night["elevation_degrees"], dawn["elevation_degrees"], 0.5
	)
	var expected_azimuth: float = lerpf(night["azimuth_degrees"], dawn["azimuth_degrees"], 0.5)
	var expected_energy: float = lerpf(night["energy"], dawn["energy"], 0.5)

	var s := DefaultSun.settings_for_time(3.0)

	assert_almost_eq(s.elevation_degrees, expected_elevation, 0.001)
	assert_almost_eq(s.azimuth_degrees, expected_azimuth, 0.001)
	assert_almost_eq(s.energy, expected_energy, 0.001)


func test_settings_for_time_sweeps_azimuth_across_the_day() -> void:
	var morning := DefaultSun.settings_for_time(9.0).azimuth_degrees
	var evening := DefaultSun.settings_for_time(21.0).azimuth_degrees

	assert_ne(morning, evening)


func test_settings_for_time_reverses_direction_between_dawn_and_dusk() -> void:
	# Regression test for the real-world behavior this sweep exists to
	# reproduce: a real sun's azimuth differs by ~180 degrees between sunrise
	# and sunset, which is why shadows point opposite directions at dawn vs.
	# dusk (not just different lengths, as a fixed-azimuth sun would give).
	var dawn: Dictionary = DefaultSun.KEYFRAMES[6.0]
	var dusk: Dictionary = DefaultSun.KEYFRAMES[18.0]

	var azimuth_dawn := DefaultSun.settings_for_time(6.0).azimuth_degrees
	var azimuth_dusk := DefaultSun.settings_for_time(18.0).azimuth_degrees

	assert_almost_eq(azimuth_dawn, float(dawn["azimuth_degrees"]), 0.001)
	assert_almost_eq(azimuth_dusk, float(dusk["azimuth_degrees"]), 0.001)
	assert_almost_eq(absf(azimuth_dusk - azimuth_dawn), 180.0, 0.001)


func test_settings_for_time_clamps_out_of_range_time_of_day() -> void:
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]

	assert_almost_eq(DefaultSun.settings_for_time(-5.0).energy, float(night["energy"]), 0.001)
	assert_almost_eq(DefaultSun.settings_for_time(30.0).energy, float(night["energy"]), 0.001)


func test_settings_for_time_records_the_clamped_hour_it_was_generated_from() -> void:
	assert_almost_eq(DefaultSun.settings_for_time(9.5).time_of_day, 9.5, 0.001)
	assert_almost_eq(DefaultSun.settings_for_time(30.0).time_of_day, 24.0, 0.001)


func test_settings_for_time_anchors_default_hour_to_the_camera_tuned_azimuth() -> void:
	# 135 degrees is the azimuth this game's fixed isometric camera was
	# originally tuned against; DEFAULT_TIME_OF_DAY is anchored to land on it.
	var s := DefaultSun.settings_for_time(DefaultSun.DEFAULT_TIME_OF_DAY)

	assert_almost_eq(s.azimuth_degrees, 135.0, 0.001)


func test_apply_writes_direction_color_and_energy_to_the_light() -> void:
	var light := DirectionalLight3D.new()
	var s := SunSettings.new()
	s.elevation_degrees = 30.0
	s.azimuth_degrees = 200.0
	s.color = Color(0.1, 0.9, 0.3)
	s.energy = 1.75

	DefaultSun.apply(light, s)

	assert_almost_eq(light.rotation_degrees.x, -30.0, 0.001)
	assert_almost_eq(light.rotation_degrees.y, 200.0, 0.001)
	assert_eq(light.light_color, Color(0.1, 0.9, 0.3))
	assert_almost_eq(light.light_energy, 1.75, 0.001)
	light.free()


func test_apply_writes_the_shadow_properties() -> void:
	var light := DirectionalLight3D.new()
	var s := SunSettings.new()
	s.shadows_enabled = false
	s.softness = 2.5
	s.shadow_darkness = 0.4

	DefaultSun.apply(light, s)

	assert_eq(light.shadow_enabled, false)
	assert_almost_eq(light.light_angular_distance, 2.5, 0.001)
	assert_almost_eq(light.shadow_opacity, 0.4, 0.001)
	light.free()


func test_default_returns_the_settings_for_the_default_hour() -> void:
	var expected := DefaultSun.settings_for_time(DefaultSun.DEFAULT_TIME_OF_DAY)

	var s := SunSettings.default()

	assert_almost_eq(s.azimuth_degrees, expected.azimuth_degrees, 0.001)
	assert_almost_eq(s.elevation_degrees, expected.elevation_degrees, 0.001)
	assert_almost_eq(s.energy, expected.energy, 0.001)
	assert_eq(s.color, expected.color)
