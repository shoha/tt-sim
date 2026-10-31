extends GutTest

## The GM's wind controls (card wind_de): the pure compass words and table, the preset and
## re-roll helpers, and the weather codec carrying wind_direction_deg and wind_seed to the saved
## level, to the visual broadcast, to a late joiner's snapshot and back from old saved levels.


func test_every_point_round_trips_through_its_heading() -> void:
	for entry: Array in WindCompass.POINTS:
		var id: StringName = entry[0]
		assert_eq(WindCompass.id_for(WindCompass.direction_for(id)), id, String(id))


func test_auto_is_the_default_sentinel() -> void:
	assert_eq(WindCompass.direction_for(WindCompass.AUTO_ID), WeatherSettings.WIND_DIRECTION_AUTO)
	assert_eq(WindCompass.id_for(-1.0), WindCompass.AUTO_ID)
	assert_eq(WindCompass.direction_for(&"nonsense"), WeatherSettings.WIND_DIRECTION_AUTO)


func test_the_grid_is_a_compass_with_auto_in_the_middle() -> void:
	assert_eq(WindCompass.GRID.size(), 9)
	assert_eq(WindCompass.GRID[4], WindCompass.AUTO_ID)
	assert_eq(WindCompass.GRID[0], &"nw")
	assert_eq(WindCompass.GRID[8], &"se")
	for id in WindCompass.GRID:
		if id != WindCompass.AUTO_ID:
			assert_false(WindCompass.point(id).is_empty(), String(id))


func test_headings_are_where_the_wind_blows_toward() -> void:
	# North is -z (up the default view), so wind from the north blows toward +z (90 degrees).
	assert_eq(WindCompass.direction_for(&"n"), 90.0)
	assert_eq(WindCompass.direction_for(&"w"), 0.0, "from the west blows toward +x")
	assert_eq(
		WindCompass.direction_for(&"sw"), 315.0, "the default diagonal is from the south-west"
	)
	assert_almost_eq(WindPresets.default_direction_deg(), 315.0, 0.001)


func test_readout_names_the_source() -> void:
	assert_eq(WindCompass.readout(45.0), "Wind from the north-west")
	assert_eq(WindCompass.readout(0.0), "Wind from the west")
	assert_eq(WindCompass.readout(180.0), "Wind from the east")


func test_readout_for_the_default_says_automatic() -> void:
	assert_eq(WindCompass.readout(-1.0), "Wind from the south-west (automatic)")


func test_readout_between_points_says_roughly() -> void:
	assert_eq(WindCompass.readout(65.0), "Wind from roughly the north-west")
	assert_eq(WindCompass.readout(46.0), "Wind from the north-west", "within a few degrees counts")
	assert_eq(WindCompass.id_for(65.0), &"", "no tile stands for it")


func test_readout_wraps_across_north_of_the_circle() -> void:
	assert_eq(WindCompass.readout(359.0), "Wind from the west")
	assert_eq(WindCompass.readout(355.0), "Wind from the west")


func test_every_tile_has_a_plain_tooltip() -> void:
	for id in WindCompass.GRID:
		var tip := WindCompass.tooltip_for(id)
		assert_false(tip.is_empty(), String(id))
		assert_true(tip.contains("wind"), tip)


func test_preset_names_follow_the_stops() -> void:
	assert_eq(WindPresets.name_for(0.0), "calm")
	assert_eq(WindPresets.name_for(0.33), "breezy")
	assert_eq(WindPresets.name_for(0.66), "windy")
	assert_eq(WindPresets.name_for(1.0), "storm")
	assert_eq(WindPresets.name_for(0.5), "", "a dragged strength is no preset")


func test_preset_speeds_are_the_designs_stops() -> void:
	var speeds: Array[float] = []
	for preset_name in WindPresets.PRESET_ORDER:
		var row := WindPresets.row_at(WindPresets.strength_of(preset_name))
		speeds.append(float(row[WindPresets.COL_SPEED]))
	assert_eq(speeds, [1.5, 4.0, 8.0, 14.0] as Array[float])


func test_preset_tooltips_are_plain_words() -> void:
	for preset_name in WindPresets.PRESET_ORDER:
		var tip := WindPresets.preset_tooltip(preset_name)
		assert_true(tip.contains("metres a second"), tip)
	assert_eq(WindPresets.preset_tooltip("gale"), "")


func test_reroll_never_returns_zero_or_the_current_seed() -> void:
	for entropy in [0, 1, 77, -5, 0xFFFFFF, 0xFFFFFE, 123456789]:
		var seed_value := WindPresets.reroll_seed(77.0, entropy)
		assert_true(seed_value >= 1.0 and seed_value <= float(WindPresets.SEED_MAX), str(entropy))
		assert_ne(seed_value, 77.0)
		assert_eq(seed_value, floorf(seed_value), "a whole number: the float codec keeps it exact")


func test_reroll_is_pure() -> void:
	assert_eq(WindPresets.reroll_seed(5.0, 999), WindPresets.reroll_seed(5.0, 999))
	assert_ne(WindPresets.reroll_seed(5.0, 999), WindPresets.reroll_seed(5.0, 1000))


func _windy_level() -> LevelData:
	var level := LevelData.new()
	level.weather.wind_intensity = 0.66
	level.weather.wind_direction_deg = 45.0
	level.weather.wind_seed = 424242.0
	return level


func test_saved_level_round_trips_the_wind_controls() -> void:
	var data := _windy_level().to_dict()
	var weather: Dictionary = data["weather_overrides"]
	assert_eq(weather["wind_direction_deg"], 45.0)
	assert_eq(weather["wind_seed"], 424242.0)
	var back := LevelData.from_dict(data)
	assert_almost_eq(back.weather.wind_intensity, 0.66, 0.000001)
	assert_eq(back.weather.wind_direction_deg, 45.0)
	assert_eq(int(back.weather.wind_seed), 424242)


func test_an_old_level_without_the_wind_keys_loads_the_defaults() -> void:
	var old := {"weather_overrides": {"rain_intensity": 0.4, "wind_intensity": 0.5}}
	var level := LevelData.from_dict(old)
	assert_almost_eq(level.weather.wind_intensity, 0.5, 0.000001)
	assert_eq(level.weather.wind_direction_deg, WeatherSettings.WIND_DIRECTION_AUTO)
	assert_eq(level.weather.wind_seed, 0.0)


func test_visual_state_carries_the_wind_controls_both_ways() -> void:
	var state := LevelVisualState.from_level_data(_windy_level())
	var data := state.to_broadcast_dict()
	assert_eq(data["weather_overrides"]["wind_direction_deg"], 45.0)
	assert_eq(data["weather_overrides"]["wind_seed"], 424242.0)
	var client := LevelVisualState.from_level_data(LevelData.new())
	client.patch_from_broadcast_dict(data)
	assert_eq(client.weather.wind_direction_deg, 45.0)
	assert_eq(int(client.weather.wind_seed), 424242)
	assert_eq(client.copy().weather.to_dict(), client.weather.to_dict())


func test_a_late_joiners_snapshot_is_patched_with_the_wind_controls() -> void:
	var snapshot := LevelData.new().to_dict()
	var broadcast := {"weather_overrides": _windy_level().weather.to_dict()}
	var patched := LevelVisualState.patch_level_dict(snapshot, broadcast)
	var joiner := LevelData.from_dict(patched)
	assert_eq(joiner.weather.wind_direction_deg, 45.0)
	assert_eq(int(joiner.weather.wind_seed), 424242)
	assert_almost_eq(joiner.weather.wind_intensity, 0.66, 0.000001)


func test_the_wind_autoload_reads_the_controls_from_a_sparse_override() -> void:
	var wind: Node = load("res://autoloads/wind.gd").new()
	wind.apply_weather_dict({"wind_intensity": 0.66, "wind_direction_deg": 45.0, "wind_seed": 9.0})
	assert_almost_eq(wind.target.dir_angle, deg_to_rad(45.0), 0.001)
	assert_eq(wind.target.seed_id, 9)
	assert_almost_eq(wind.target.speed, 8.0, 0.01)
	wind.apply_weather_dict({"wind_seed": 10.0})
	assert_almost_eq(wind.target.dir_angle, deg_to_rad(45.0), 0.001, "sparse keys keep the rest")
	assert_eq(wind.target.seed_id, 10)
	wind.free()
	Wind.publish(Wind.clock())
