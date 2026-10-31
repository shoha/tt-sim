extends GutTest

## The Wind autoload (autoloads/wind.gd): the uniforms are pushed only when they change, the
## weather settings retarget it, a change eases rather than snaps, and the reduce-motion /
## per-player motion scale stills the plants. Uses a private instance (not in the tree), and
## puts the global uniforms back to the shared instance's values afterwards.

var _wind: Node


func before_each() -> void:
	_wind = load("res://autoloads/wind.gd").new()


func after_each() -> void:
	_wind.free()
	Wind.publish(Wind.clock())


func test_publish_sets_each_global_only_when_it_changed() -> void:
	_wind.set_clock_override(10.0)
	_wind.publish(_wind.clock())
	var first: int = _wind.publish_count
	assert_true(first >= 1 and first <= 3)
	_wind.publish(_wind.clock())
	assert_eq(_wind.publish_count, first, "same clock, same state: no set calls")
	_wind.publish(_wind.clock() + 0.5)
	assert_eq(_wind.publish_count, first + 1, "only the phases moved")


func test_preset_retargets_and_eases_instead_of_snapping() -> void:
	_wind.set_preset("storm")
	assert_almost_eq(_wind.target.speed, 14.0, 0.001)
	assert_almost_eq(_wind.state.speed, 1.5, 0.001, "not there yet")
	_wind._process(0.5)
	assert_true(_wind.state.speed > 1.5 and _wind.state.speed < 14.0)
	for i in range(400):
		_wind._process(0.1)
	assert_eq(_wind.state, _wind.target, "settles exactly on the target")


func test_set_from_weather_uses_intensity_direction_and_seed() -> void:
	var settings := WeatherSettings.new()
	settings.wind_intensity = 1.0
	settings.wind_direction_deg = 90.0
	settings.wind_seed = 77.0
	_wind.set_from_weather(settings)
	assert_almost_eq(_wind.target.sway_scale, 3.2, 0.001)
	assert_almost_eq(_wind.target.dir_angle, PI * 0.5, 0.001)
	assert_eq(_wind.target.seed_id, 77)
	_wind.snap()
	_wind.set_clock_override(5.0)
	var dir: Vector3 = _wind.direction_at(Vector3.ZERO)
	assert_almost_eq(dir.length(), 1.0, 0.001)


func test_a_level_key_seeds_a_level_without_a_seed() -> void:
	var settings := WeatherSettings.new()
	_wind.set_from_weather(settings, "my_level")
	var a: int = _wind.target.seed_id
	_wind.set_from_weather(settings, "other_level")
	assert_ne(a, _wind.target.seed_id)
	_wind.set_from_weather(settings)
	assert_eq(_wind.target.seed_id, 0)


func test_a_sparse_weather_dictionary_keeps_the_other_keys() -> void:
	_wind.apply_weather_dict({"wind_intensity": 0.66})
	_wind.apply_weather_dict({"wind_seed": 5.0})
	assert_almost_eq(_wind.target.sway_scale, 2.2, 0.001)
	assert_eq(_wind.target.seed_id, 5)


func test_motion_scale_stills_the_plants_and_stops_the_phase_publishing() -> void:
	_wind.set_wind_motion(0.0)
	_wind.set_clock_override(3.0)
	_wind.publish(_wind.clock())
	var count: int = _wind.publish_count
	_wind.publish(_wind.clock() + 1.0)
	assert_eq(_wind.publish_count, count, "no phase sets while motion is 0")
	var gust: Vector4 = WindModel.uniforms(_wind.state, 3.0, _wind.motion_scale())[2]
	assert_eq(gust.w, 0.0)


func test_reduced_motion_overrides_the_player_scale() -> void:
	_wind.set_wind_motion(0.8)
	assert_almost_eq(_wind.motion_scale(), 0.8, 0.0001)
	_wind._reduced = true
	assert_eq(_wind.motion_scale(), 0.0)


func test_wind_motion_is_clamped_and_defaults_to_one() -> void:
	assert_eq(_wind.motion_scale(), 1.0)
	_wind.set_wind_motion(7.0)
	assert_eq(_wind.motion_scale(), 1.0)
	_wind.set_wind_motion(-1.0)
	assert_eq(_wind.motion_scale(), 0.0)


func test_the_autoload_is_registered_and_the_globals_exist() -> void:
	assert_not_null(Wind)
	for global_name in ["wind_dir", "wind_phase", "wind_gust"]:
		var found := false
		for entry in RenderingServer.global_shader_parameter_get_list():
			if String(entry) == global_name:
				found = true
		assert_true(found, "%s is a declared global" % global_name)
