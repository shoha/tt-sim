extends GutTest

## The pure wind (WindModel, WindPresets, WindState; docs/systems/wind.md): determinism, a
## unit direction, no NaN over a grid, fronts that travel at the constant front speed, the
## preset table, the phase wrap, and the weather-settings round trip with the wind fields.

const T0 := 123456.789


func _windy() -> WindState:
	return WindPresets.state_for(0.66, -1.0, 0)


func test_wind_at_is_deterministic() -> void:
	var state := _windy()
	var p := Vector3(3.5, 0.0, -8.25)
	assert_eq(WindModel.wind_at(state, p, T0), WindModel.wind_at(state, p, T0))
	var twin := WindPresets.state_for(0.66, -1.0, 0)
	assert_eq(WindModel.wind_at(state, p, T0), WindModel.wind_at(twin, p, T0))


func test_direction_is_a_unit_vector_and_wind_points_along_it() -> void:
	for strength in [0.0, 0.33, 0.66, 1.0]:
		var state := WindPresets.state_for(strength, 40.0, 7)
		for t in [0.0, 17.3, 5000.1]:
			var dir := WindModel.direction_vec(state, t)
			assert_almost_eq(dir.length(), 1.0, 0.00001)
			var w := WindModel.wind_at(state, Vector3(1, 0, 2), t)
			assert_almost_eq(w.normalized().x, dir.x, 0.0001)
			assert_almost_eq(w.normalized().z, dir.y, 0.0001)
			assert_eq(w.y, 0.0)


func test_default_direction_is_toward_minus_z() -> void:
	var dir := WindModel.direction_vec(WindPresets.state_for(0.0, -1.0, 0), 10.0)
	assert_almost_eq(dir.x, 0.0, 0.00001)
	assert_almost_eq(dir.y, -1.0, 0.00001)


func test_no_nan_and_gust_in_range_over_a_grid() -> void:
	for strength in [0.0, 0.5, 1.0]:
		var state := WindPresets.state_for(strength, -1.0, 99)
		for ix in range(-10, 11):
			for iz in range(-10, 11):
				var p := Vector3(ix * 7.3, 0.0, iz * 5.1)
				var g := WindModel.gust_at(state, p, 1.0e9 + ix)
				assert_true(g >= 0.0 and g <= 1.0, "gust %f in range" % g)
				var w := WindModel.wind_at(state, p, 42.0)
				assert_false(is_nan(w.x) or is_nan(w.z))


func test_gust_travels_at_the_front_speed() -> void:
	# The first front moves at 3 m/s, the second at 0.8 of it (as the shader always did), so
	# the whole field is not one rigid translation; the first front is. Its phase advances
	# by k * v * dt, which is the phase shift of a pattern moved v * dt along the wind.
	var dt := 2.5
	var ka := TAU / WindModel.WAVELENGTH_A
	var d0 := fposmod(WindModel.phases(T0 + dt).x - WindModel.phases(T0).x, TAU)
	assert_almost_eq(d0, fposmod(ka * WindModel.FRONT_SPEED * dt, TAU), 0.0001)
	# After 380 s both fronts have turned a whole number of cycles (4 s and 7.9167 s per
	# cycle), so the field repeats exactly: the phase wrap leaves it unchanged.
	var state := WindPresets.state_for(0.0, 90.0, 0)
	var q := Vector3(4.0, 0.0, 9.0)
	assert_almost_eq(WindModel.gust_at(state, q, 10.0), WindModel.gust_at(state, q, 390.0), 0.0001)


func test_front_phase_moves_the_pattern_along_the_wind() -> void:
	# Along the wind (+x here), the first term is sin(k x - phase): advancing t by dt moves a
	# crest forward by FRONT_SPEED * dt, so g(x + v dt, t + dt) matches g(x, t) for the
	# first-front-only field (the second front travels slower, so we isolate it with seed 0
	# and compare the first term's argument).
	var ka := TAU / WindModel.WAVELENGTH_A
	var x := 5.0
	var dt := 1.7
	var arg0 := x * ka - WindModel.phases(T0).x
	var arg1 := (x + WindModel.FRONT_SPEED * dt) * ka - WindModel.phases(T0 + dt).x
	assert_almost_eq(angle_difference(arg0, arg1), 0.0, 0.0001)


func test_phases_stay_reduced_at_large_clock_values() -> void:
	for t in [0.0, 1.0e6, 7.9e7, 1.0e9]:
		var p := WindModel.phases(t)
		for v in [p.x, p.y, p.z]:
			# A Vector4 holds 32-bit floats, so a phase just under TAU may round up to it.
			assert_true(v >= 0.0 and v <= TAU + 0.00001, "phase %f reduced at t %f" % [v, t])


func test_phase_has_no_jump_across_the_old_hourly_wrap() -> void:
	# TIME wraps every 3600 s; the wind clock is the unix clock, with no seam there.
	var before := WindModel.phases(3599.99)
	var after := WindModel.phases(3600.01)
	var expected := 0.02 * TAU / WindModel.WAVELENGTH_A * WindModel.FRONT_SPEED
	assert_almost_eq(angle_difference(before.x, after.x), expected, 0.001)


func test_a_preset_change_does_not_move_the_phases() -> void:
	# Phases depend only on the clock, so no preset change can make a field jump.
	assert_eq(WindModel.phases(T0), WindModel.phases(T0))
	var calm := WindPresets.state_for(0.0, -1.0, 0)
	var storm := WindPresets.state_for(1.0, -1.0, 0)
	var u_calm := WindModel.uniforms(calm, T0, 1.0)
	var u_storm := WindModel.uniforms(storm, T0, 1.0)
	assert_eq(u_calm[1], u_storm[1])


func test_preset_table_is_monotonic_in_strength() -> void:
	var last: Array = WindPresets.row_at(0.0)
	for i in range(1, 101):
		var row := WindPresets.row_at(float(i) / 100.0)
		for col in [
			WindPresets.COL_SPEED,
			WindPresets.COL_GUST,
			WindPresets.COL_RIPPLE,
			WindPresets.COL_VEER_AMP,
			WindPresets.COL_SWAY
		]:
			assert_true(float(row[col]) >= float(last[col]) - 0.000001, "column %d rises" % col)
		last = row


func test_preset_stops_match_the_design_table() -> void:
	var calm := WindPresets.state_for(WindPresets.strength_of("calm"), -1.0, 0)
	var storm := WindPresets.state_for(WindPresets.strength_of("storm"), -1.0, 0)
	assert_almost_eq(calm.speed, 1.5, 0.0001)
	assert_almost_eq(calm.sway_scale, 1.0, 0.0001)
	assert_almost_eq(calm.gust_amp, WindModel.CALM_GUST_AMP, 0.0001)
	assert_almost_eq(storm.speed, 14.0, 0.0001)
	assert_almost_eq(storm.sway_scale, 3.2, 0.0001)
	assert_almost_eq(WindPresets.state_for(0.33, -1.0, 0).speed, 4.0, 0.0001)
	assert_almost_eq(WindPresets.state_for(0.66, -1.0, 0).sway_scale, 2.2, 0.0001)
	assert_eq(WindPresets.strength_of("nonsense"), -1.0)


func test_blend_reaches_the_target_by_the_short_way_round() -> void:
	var a := WindState.make(PI - 0.1, 1.0, 0.3, 0.0, 0.0, 100.0, 1.0, 0)
	var b := WindState.make(-PI + 0.1, 3.0, 0.5, 0.0, 0.0, 100.0, 2.0, 0)
	var mid := WindPresets.blend(a, b, 0.5)
	assert_almost_eq(absf(angle_difference(mid.dir_angle, PI)), 0.0, 0.0001, "through PI, not 0")
	assert_almost_eq(mid.speed, 2.0, 0.0001)
	assert_true(WindPresets.near(b, b))
	assert_false(WindPresets.near(a, b))


func test_seed_changes_the_field_but_seed_zero_is_unphased() -> void:
	var p := Vector3(2.0, 0.0, 3.0)
	var a := WindPresets.state_for(0.66, -1.0, 0)
	var b := WindPresets.state_for(0.66, -1.0, 1234)
	assert_eq(WindModel.seed_phase(a), 0.0)
	assert_ne(WindModel.gust_at(a, p, 50.0), WindModel.gust_at(b, p, 50.0))


func test_weather_settings_round_trip_the_wind_fields() -> void:
	var settings := WeatherSettings.new()
	settings.wind_intensity = 0.7
	settings.wind_seed = 4242.0
	settings.wind_direction_deg = 135.0
	var back := WeatherSettings.from_dict(settings.to_dict())
	assert_eq(back.wind_intensity, 0.7)
	assert_eq(back.wind_seed, 4242.0)
	assert_eq(back.wind_direction_deg, 135.0)


func test_old_saved_weather_loads_with_the_default_wind_fields() -> void:
	var old := {
		"rain_intensity": 0.5, "snow_intensity": 0.0, "fog_intensity": 0.1, "wind_intensity": 0.4
	}
	var settings := WeatherSettings.from_dict(old)
	assert_eq(settings.wind_intensity, 0.4)
	assert_eq(settings.wind_seed, 0.0)
	assert_eq(settings.wind_direction_deg, WeatherSettings.WIND_DIRECTION_AUTO)
	var level := LevelData.new()
	level.weather = settings
	assert_true(level.weather.to_dict().has("wind_seed"))
