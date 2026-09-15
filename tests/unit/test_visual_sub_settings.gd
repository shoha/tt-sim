extends GutTest

## Round-trip and default tests for the typed visual sub-settings that replace the
## untyped lofi/weather/foliage override dictionaries on LevelData. The dictionaries
## they emit use the same keys the live apply functions already read, and from_dict()
## must accept the sparse dictionaries older level files contain.


func test_lofi_defaults_match_constants() -> void:
	var lofi := LofiSettings.default()
	for key in LofiSettings.KEYS:
		assert_almost_eq(float(lofi.get(key)), float(Constants.LOFI_DEFAULTS[key]), 0.000001, key)


func test_lofi_to_dict_is_complete_and_round_trips() -> void:
	var lofi := LofiSettings.default()
	lofi.pixelation = 0.05
	lofi.grain_intensity = 0.3

	var data := lofi.to_dict()
	assert_eq(data.keys().size(), LofiSettings.KEYS.size())
	for key in LofiSettings.KEYS:
		assert_true(data.has(key), key)

	var back := LofiSettings.from_dict(data)
	assert_almost_eq(back.pixelation, 0.05, 0.000001)
	assert_almost_eq(back.grain_intensity, 0.3, 0.000001)
	assert_almost_eq(back.saturation, float(Constants.LOFI_DEFAULTS["saturation"]), 0.000001)


func test_lofi_from_sparse_dict_fills_defaults() -> void:
	var lofi := LofiSettings.from_dict({"pixelation": 0.02})
	assert_almost_eq(lofi.pixelation, 0.02, 0.000001)
	assert_almost_eq(
		lofi.vignette_strength, float(Constants.LOFI_DEFAULTS["vignette_strength"]), 0.000001
	)


func test_lofi_from_non_dict_is_default() -> void:
	var lofi := LofiSettings.from_dict(null)
	assert_eq(lofi.to_dict(), LofiSettings.default().to_dict())


func test_lofi_copy_is_independent() -> void:
	var lofi := LofiSettings.default()
	var copy := lofi.copy_settings()
	copy.pixelation = 9.0
	assert_almost_eq(lofi.pixelation, float(Constants.LOFI_DEFAULTS["pixelation"]), 0.000001)


func test_weather_defaults_are_zero_and_round_trip() -> void:
	var weather := WeatherSettings.default()
	for key in WeatherSettings.KEYS:
		assert_eq(float(weather.get(key)), 0.0, key)
	weather.rain_intensity = 0.7
	var back := WeatherSettings.from_dict(weather.to_dict())
	assert_almost_eq(back.rain_intensity, 0.7, 0.000001)
	assert_eq(back.snow_intensity, 0.0)


func test_weather_from_sparse_dict_fills_zero() -> void:
	var weather := WeatherSettings.from_dict({"fog_intensity": 0.4})
	assert_almost_eq(weather.fog_intensity, 0.4, 0.000001)
	assert_eq(weather.wind_intensity, 0.0)


func test_foliage_defaults_match_wind_presets() -> void:
	var foliage := FoliageSettings.default()
	assert_almost_eq(
		foliage.tree_sway_speed, float(WindFoliage.PRESETS["tree"]["sway_speed"]), 0.000001
	)
	assert_almost_eq(
		foliage.grass_sway_amplitude,
		float(WindFoliage.PRESETS["grass"]["sway_amplitude"]),
		0.000001
	)


func test_foliage_to_dict_feeds_get_effective_preset() -> void:
	var foliage := FoliageSettings.default()
	foliage.grass_sway_speed = 9.0
	var preset := WindFoliage.get_effective_preset("grass", foliage.to_dict())
	assert_almost_eq(float(preset["sway_speed"]), 9.0, 0.000001)
	var tree := WindFoliage.get_effective_preset("tree", foliage.to_dict())
	assert_almost_eq(
		float(tree["sway_speed"]), float(WindFoliage.PRESETS["tree"]["sway_speed"]), 0.000001
	)


func test_foliage_from_sparse_dict_fills_presets() -> void:
	var foliage := FoliageSettings.from_dict({"tree_sway_speed": 1.2})
	assert_almost_eq(foliage.tree_sway_speed, 1.2, 0.000001)
	assert_almost_eq(
		foliage.grass_sway_speed, float(WindFoliage.PRESETS["grass"]["sway_speed"]), 0.000001
	)
