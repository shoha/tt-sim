extends GutTest

## Unit tests for DefaultSun.configure_directional_light() (utils/default_sun.gd)
## -- keyframe interpolation of sun elevation/color/energy by time_of_day. Time-
## of-day only drives the sun light itself, never the separate Environment/
## ambient config (see
## docs/superpowers/specs/2026-08-08-lighting-rendering-defaults-design.md).


func test_configure_directional_light_matches_noon_keyframe_exactly() -> void:
	var light := DirectionalLight3D.new()
	DefaultSun.configure_directional_light(light, 12.0)
	var noon: Dictionary = DefaultSun.KEYFRAMES[12.0]

	assert_almost_eq(light.rotation_degrees.x, -float(noon["elevation_degrees"]), 0.001)
	assert_eq(light.light_color, noon["color"])
	assert_almost_eq(light.light_energy, float(noon["energy"]), 0.001)
	light.free()


func test_configure_directional_light_matches_night_keyframe_at_zero_and_twentyfour() -> void:
	var light := DirectionalLight3D.new()
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]

	DefaultSun.configure_directional_light(light, 0.0)
	assert_almost_eq(light.light_energy, float(night["energy"]), 0.001)

	DefaultSun.configure_directional_light(light, 24.0)
	assert_almost_eq(light.light_energy, float(night["energy"]), 0.001)
	light.free()


func test_configure_directional_light_interpolates_halfway_between_night_and_dawn() -> void:
	var light := DirectionalLight3D.new()
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]
	var dawn: Dictionary = DefaultSun.KEYFRAMES[6.0]
	var expected_elevation: float = lerpf(
		night["elevation_degrees"], dawn["elevation_degrees"], 0.5
	)
	var expected_energy: float = lerpf(night["energy"], dawn["energy"], 0.5)

	DefaultSun.configure_directional_light(light, 3.0)

	assert_almost_eq(light.rotation_degrees.x, -expected_elevation, 0.001)
	assert_almost_eq(light.light_energy, expected_energy, 0.001)
	light.free()


func test_configure_directional_light_uses_a_fixed_azimuth_regardless_of_time() -> void:
	var light := DirectionalLight3D.new()

	DefaultSun.configure_directional_light(light, 9.0)
	assert_almost_eq(light.rotation_degrees.y, DefaultSun.AZIMUTH_DEGREES, 0.001)

	DefaultSun.configure_directional_light(light, 21.0)
	assert_almost_eq(light.rotation_degrees.y, DefaultSun.AZIMUTH_DEGREES, 0.001)
	light.free()


func test_configure_directional_light_clamps_out_of_range_time_of_day() -> void:
	var light := DirectionalLight3D.new()
	var night: Dictionary = DefaultSun.KEYFRAMES[0.0]

	DefaultSun.configure_directional_light(light, -5.0)
	assert_almost_eq(light.light_energy, float(night["energy"]), 0.001)

	DefaultSun.configure_directional_light(light, 30.0)
	assert_almost_eq(light.light_energy, float(night["energy"]), 0.001)
	light.free()
