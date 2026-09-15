extends GutTest

## LevelData serialises its typed lofi/weather/foliage settings under the historical
## JSON keys (lofi_overrides, weather_overrides, foliage_overrides) as complete
## dictionaries, and loads the sparse dictionaries older files contain. The on-disk
## format version is unchanged.


func test_to_dict_writes_complete_dicts_under_the_legacy_keys() -> void:
	var level := LevelData.new()
	level.foliage.tree_sway_speed = 1.2
	level.weather.rain_intensity = 0.5
	level.lofi.pixelation = 0.05

	var data := level.to_dict()

	assert_eq(int(data["format_version"]), 1)
	assert_almost_eq(float(data["foliage_overrides"]["tree_sway_speed"]), 1.2, 0.000001)
	assert_true(data["foliage_overrides"].has("grass_sway_amplitude"), "complete, not sparse")
	assert_almost_eq(float(data["weather_overrides"]["rain_intensity"]), 0.5, 0.000001)
	assert_eq(float(data["weather_overrides"]["snow_intensity"]), 0.0)
	assert_almost_eq(float(data["lofi_overrides"]["pixelation"]), 0.05, 0.000001)
	assert_eq(data["lofi_overrides"].keys().size(), LofiSettings.KEYS.size())


func test_from_dict_loads_sparse_legacy_dicts() -> void:
	var data := {
		"foliage_overrides": {"grass_sway_speed": 2.5},
		"weather_overrides": {"fog_intensity": 0.3},
		"lofi_overrides": {"pixelation": 0.02},
	}

	var level := LevelData.from_dict(data)

	assert_almost_eq(level.foliage.grass_sway_speed, 2.5, 0.000001)
	assert_almost_eq(
		level.foliage.tree_sway_speed, float(WindFoliage.PRESETS["tree"]["sway_speed"]), 0.000001
	)
	assert_almost_eq(level.weather.fog_intensity, 0.3, 0.000001)
	assert_eq(level.weather.rain_intensity, 0.0)
	assert_almost_eq(level.lofi.pixelation, 0.02, 0.000001)


func test_from_dict_without_the_keys_gives_defaults() -> void:
	var level := LevelData.from_dict({})
	assert_eq(level.foliage.to_dict(), FoliageSettings.default().to_dict())
	assert_eq(level.weather.to_dict(), WeatherSettings.default().to_dict())
	assert_eq(level.lofi.to_dict(), LofiSettings.default().to_dict())


func test_round_trip_preserves_values() -> void:
	var level := LevelData.new()
	level.lofi.vignette_strength = 0.4
	level.weather.wind_intensity = 0.9
	level.foliage.grass_sway_amplitude = 0.07

	var back := LevelData.from_dict(level.to_dict())

	assert_almost_eq(back.lofi.vignette_strength, 0.4, 0.000001)
	assert_almost_eq(back.weather.wind_intensity, 0.9, 0.000001)
	assert_almost_eq(back.foliage.grass_sway_amplitude, 0.07, 0.000001)


func test_duplicate_level_copies_settings_independently() -> void:
	var level := LevelData.new()
	level.foliage.tree_sway_speed = 1.2
	level.lofi.pixelation = 0.05

	var copy := level.duplicate_level()
	copy.foliage.tree_sway_speed = 9.9
	copy.lofi.pixelation = 9.9
	copy.weather.rain_intensity = 1.0

	assert_almost_eq(level.foliage.tree_sway_speed, 1.2, 0.000001)
	assert_almost_eq(level.lofi.pixelation, 0.05, 0.000001)
	assert_eq(level.weather.rain_intensity, 0.0)


func test_legacy_tres_dictionary_properties_are_absorbed_by_set() -> void:
	# ResourceLoader assigns properties by name when loading an old .tres, which
	# bypasses from_dict(); LevelData._set() must convert the legacy dictionaries.
	var level := LevelData.new()
	level.set("lofi_overrides", {"pixelation": 0.03})
	level.set("weather_overrides", {"snow_intensity": 0.6})
	level.set("foliage_overrides", {"tree_sway_amplitude": 0.2})

	assert_almost_eq(level.lofi.pixelation, 0.03, 0.000001)
	assert_almost_eq(level.weather.snow_intensity, 0.6, 0.000001)
	assert_almost_eq(level.foliage.tree_sway_amplitude, 0.2, 0.000001)
