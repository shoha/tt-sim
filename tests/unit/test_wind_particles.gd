extends GutTest

## The weather particles follow the global wind (docs/systems/wind.md phase b): the pure slant,
## drift and turbulence functions, the rate-limited update rule of WeatherRenderer, the default
## direction defined once, and a guard that no weather script keeps a literal wind vector.

const WEATHER_FILES: Array[String] = [
	"res://scenes/effects/weather_renderer.gd",
	"res://utils/wind_particles.gd",
	"res://resources/weather_settings.gd",
]


func _renderer() -> WeatherRenderer:
	var renderer := WeatherRenderer.new()
	add_child_autofree(renderer)
	renderer._rain_emitter = renderer._create_rain_emitter()
	renderer._snow_emitter = renderer._create_snow_emitter()
	renderer._wind_emitter = renderer._create_wind_emitter()
	for emitter: GPUParticles3D in [
		renderer._rain_emitter, renderer._snow_emitter, renderer._wind_emitter
	]:
		renderer.add_child(emitter)
	return renderer


func test_slant_is_monotonic_clamped_and_matches_the_design_points() -> void:
	var last := -1.0
	for i in range(0, 41):
		var s := WindParticles.slant_tan(float(i))
		assert_true(s >= last, "monotonic in speed")
		assert_true(s >= 0.0 and s <= WindParticles.RAIN_SLANT_MAX)
		last = s
	assert_eq(WindParticles.slant_tan(100.0), WindParticles.RAIN_SLANT_MAX)
	assert_eq(WindParticles.slant_tan(-3.0), 0.0)
	assert_almost_eq(WindParticles.slant_degrees(1.5), 3.9, 0.2)
	assert_almost_eq(WindParticles.slant_degrees(8.0), 19.8, 0.3)
	assert_almost_eq(WindParticles.slant_degrees(14.0), 32.2, 0.3)


func test_rain_direction_is_unit_leans_with_the_wind_and_keeps_its_ratio() -> void:
	var wind := Vector3(5.0, 0.0, -5.0)
	var dir := WindParticles.rain_direction(wind)
	assert_almost_eq(dir.length(), 1.0, 0.0001)
	assert_true(dir.y < 0.0)
	assert_true(dir.x > 0.0 and dir.z < 0.0, "leans toward the wind")
	var g := WindParticles.rain_gravity(wind)
	var lean_ratio := Vector2(g.x, g.z).length() / -g.y
	assert_almost_eq(lean_ratio, WindParticles.slant_tan(wind.length()), 0.0001)
	var still := WindParticles.rain_direction(Vector3.ZERO)
	assert_almost_eq(still.x, 0.0, 0.0001)
	assert_almost_eq(still.y, -1.0, 0.0001)


func test_rain_speed_scale_is_monotonic_and_capped() -> void:
	var last := 0.0
	for i in range(0, 30):
		var s := WindParticles.rain_speed_scale(Vector3(float(i), 0.0, 0.0))
		assert_true(s >= last)
		last = s
	assert_almost_eq(last, 1.0 + WindParticles.RAIN_SPEED_GAIN, 0.0001)


func test_snow_drift_is_half_the_wind_monotonic_and_capped() -> void:
	assert_almost_eq(WindParticles.snow_drift_speed(4.0), 2.0, 0.0001)
	assert_eq(WindParticles.snow_drift_speed(40.0), WindParticles.SNOW_DRIFT_MAX)
	var last := -1.0
	for i in range(0, 40):
		var d := WindParticles.snow_drift_speed(float(i))
		assert_true(d >= last)
		last = d
	var g := WindParticles.snow_gravity(Vector3(0.0, 0.0, -8.0))
	assert_almost_eq(g.z, -4.0, 0.0001, "drifts along the wind")
	assert_true(-g.y < WindParticles.SNOW_BASE_FALL, "falls slower in wind")
	assert_almost_eq(
		WindParticles.snow_gravity(Vector3.ZERO).y, -WindParticles.SNOW_BASE_FALL, 0.0001
	)


func test_snow_turbulence_rises_with_gusts_and_speed() -> void:
	assert_almost_eq(WindParticles.snow_turbulence(10.0, 0.0), 1.0, 0.0001)
	var turb := WindParticles.snow_turbulence
	assert_true(turb.call(10.0, 0.8) > turb.call(10.0, 0.2))
	assert_true(turb.call(14.0, 0.8) > turb.call(4.0, 0.8))
	assert_true(turb.call(99.0, 5.0) <= 1.0 + WindParticles.SNOW_TURBULENCE_GAIN)


func test_horizontal_direction_is_unit_with_a_default_fallback() -> void:
	assert_almost_eq(WindParticles.horizontal_direction(Vector3(3.0, 9.0, 4.0)).length(), 1.0, 0.0001)
	assert_eq(WindParticles.horizontal_direction(Vector3.ZERO), WindPresets.default_direction())


func test_streak_speed_rises_with_the_wind() -> void:
	assert_almost_eq(WindParticles.streak_speed(0.0), WindParticles.STREAK_BASE_SPEED, 0.0001)
	assert_true(WindParticles.streak_speed(14.0) > WindParticles.streak_speed(4.0))


func test_streak_ratio_is_zero_off_then_monotonic() -> void:
	assert_eq(WindParticles.streak_ratio(0.0), 0.0)
	assert_almost_eq(WindParticles.streak_ratio(0.01), WindParticles.STREAK_MIN_RATIO, 0.01)
	assert_eq(WindParticles.streak_ratio(1.0), 1.0)
	assert_true(WindParticles.streak_ratio(0.6) > WindParticles.streak_ratio(0.3))


func test_default_direction_is_defined_once_and_old_levels_keep_the_sentinel() -> void:
	var dir := WindPresets.default_direction()
	assert_almost_eq(dir.x, 0.707107, 0.0001)
	assert_almost_eq(dir.z, -0.707107, 0.0001)
	var angle := WindPresets.state_for(0.5, -1.0, 0).dir_angle
	assert_almost_eq(angle, WindPresets.DEFAULT_DIR_ANGLE, 1e-6)
	assert_eq(WindState.new().dir_angle, WindPresets.DEFAULT_DIR_ANGLE)
	assert_almost_eq(WindPresets.default_direction_deg(), 315.0, 0.001)
	var round_trip := WeatherSettings.from_dict(WeatherSettings.default().to_dict())
	assert_eq(round_trip.wind_direction_deg, WeatherSettings.WIND_DIRECTION_AUTO)
	var old := WeatherSettings.from_dict({"rain_intensity": 0.5, "wind_intensity": 0.4})
	assert_eq(old.wind_direction_deg, WeatherSettings.WIND_DIRECTION_AUTO)


func test_smoothing_and_change_rule() -> void:
	var s := WindParticles.smooth_toward(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 0.1)
	assert_true(s.x > 0.0 and s.x < 10.0, "eases, does not jump")
	assert_false(
		WindParticles.changed_enough(Vector3(5, 0, 0), Vector3(5.05, 0, 0), 0.2, 0.21)
	)
	assert_true(WindParticles.changed_enough(Vector3(5, 0, 0), Vector3(5.5, 0, 0), 0.2, 0.2))
	assert_true(WindParticles.changed_enough(Vector3(5, 0, 0), Vector3(5, 0, 0), 0.2, 0.4))


func test_the_renderer_writes_only_at_the_interval_and_only_on_change() -> void:
	var renderer := _renderer()
	var wind := Vector3(6.0, 0.0, -6.0)
	assert_true(renderer.wind_due(0.016), "unprimed: sample at once")
	assert_true(renderer.step_wind(wind, 0.3))
	assert_eq(renderer.wind_apply_count, 1)
	var due := 0
	for i in range(60):  # one second at 60 fps
		if renderer.wind_due(1.0 / 60.0):
			due += 1
			renderer.step_wind(wind, 0.3)
	assert_true(due >= 7 and due <= 10, "at most 10 Hz, got %d" % due)
	assert_eq(renderer.wind_apply_count, 1, "a steady wind writes nothing more")
	# A gust: the target jumps, the write follows in a few steps, and fewer than the samples.
	var writes := 0
	var samples := 0
	for i in range(30):
		if renderer.wind_due(0.1):
			samples += 1
			if renderer.step_wind(Vector3(12.0, 0.0, -12.0), 0.8):
				writes += 1
	assert_true(writes >= 1 and writes <= samples)
	var mat := renderer._rain_emitter.process_material as ParticleProcessMaterial
	assert_true(mat.gravity.x > 0.0 and mat.gravity.z < 0.0, "rain leans along the wind")
	assert_almost_eq(mat.direction.length(), 1.0, 0.001)


func test_motion_zero_stills_the_lean_but_not_the_fall() -> void:
	var renderer := _renderer()
	renderer.wind_due(0.1)
	renderer.step_wind(Vector3.ZERO, 0.0)
	var rain := renderer._rain_emitter.process_material as ParticleProcessMaterial
	assert_almost_eq(rain.gravity.x, 0.0, 0.0001)
	assert_almost_eq(rain.gravity.y, -WindParticles.RAIN_GRAVITY, 0.0001, "still falls")
	var snow := renderer._snow_emitter.process_material as ParticleProcessMaterial
	assert_almost_eq(snow.gravity.x, 0.0, 0.0001)
	assert_almost_eq(snow.gravity.y, -WindParticles.SNOW_BASE_FALL, 0.0001, "still falls")
	assert_false(renderer._wind_emitter.visible, "the streaks hide")


func test_no_weather_script_keeps_a_literal_wind_vector() -> void:
	var literal := RegEx.create_from_string(
		(
			"\\bWIND_DIRECTION\\b|RAIN_WIND_STRENGTH|SNOW_WIND_STRENGTH|0\\.7071"
			+ "|Vector3\\(\\s*1\\s*,\\s*0\\s*,\\s*-1\\s*\\)"
		)
	)
	for path in WEATHER_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, path)
		if file == null:
			continue
		var text := file.get_as_text()
		assert_null(literal.search(text), "%s keeps a literal wind vector" % path)
