extends GutTest

## LevelData serialises its typed lofi/weather/foliage settings under the historical
## JSON keys (lofi_overrides, weather_overrides, foliage_overrides) as complete
## dictionaries, and loads the sparse dictionaries older files contain. The on-disk
## format version is unchanged. The last test covers the other persistence path --
## LevelManager.save_level()'s ResourceSaver .tres write, which never goes through
## to_dict() at all.

const TRES_ROUND_TRIP_PATH := "user://test_typed_settings_roundtrip.tres"


func after_each() -> void:
	if FileAccess.file_exists(TRES_ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRES_ROUND_TRIP_PATH))


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


func test_legacy_set_covers_sun_overrides_and_rejects_unknown_properties() -> void:
	# _set() intercepts four legacy dictionary keys from pre-typed .tres levels;
	# everything else must return false so Object.set() falls back to the
	# engine's default property setter and real @export fields are unaffected.
	var level := LevelData.new()

	level.set("lofi_overrides", {"pixelation": 0.07})
	level.set("weather_overrides", {"wind_intensity": 0.4})
	level.set("foliage_overrides", {"grass_sway_speed": 3.1})
	var legacy_sun := {"mode": "auto", "time_of_day": 14.0}
	level.set("sun_overrides", legacy_sun)

	assert_almost_eq(level.lofi.pixelation, 0.07, 0.000001)
	assert_almost_eq(level.weather.wind_intensity, 0.4, 0.000001)
	assert_almost_eq(level.foliage.grass_sway_speed, 3.1, 0.000001)
	assert_eq(level.visual_settings.sun.to_dict(), SunSettings.from_legacy(legacy_sun).to_dict())

	assert_false(level._set(&"not_a_real_property", "value"), "unknown property must return false")

	# A real @export property is unaffected by _set()'s legacy interception.
	level.set("level_name", "Renamed")
	assert_eq(level.level_name, "Renamed")


func test_typed_settings_survive_a_tres_save_and_load() -> void:
	# LevelManager.save_level() persists through ResourceSaver, not to_dict(), so
	# the three sub-resources have to survive .tres serialisation independently:
	# a Resource-typed @export that failed to round-trip here would silently come
	# back as null or as a fresh default.
	var level := LevelData.new()
	level.lofi.pixelation = 0.05
	level.weather.rain_intensity = 0.5
	level.foliage.tree_sway_speed = 1.2

	assert_eq(ResourceSaver.save(level, TRES_ROUND_TRIP_PATH), OK, "ResourceSaver.save failed")

	# CACHE_MODE_IGNORE so the assertions read the file, not the instance that
	# ResourceSaver just put in the resource cache under the same path.
	var loaded := (
		ResourceLoader.load(TRES_ROUND_TRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	)

	assert_not_null(loaded, "the .tres did not load back as a LevelData")
	if loaded == null:
		return
	assert_not_null(loaded.lofi, "lofi came back null")
	assert_not_null(loaded.weather, "weather came back null")
	assert_not_null(loaded.foliage, "foliage came back null")
	assert_almost_eq(loaded.lofi.pixelation, 0.05, 0.000001)
	assert_almost_eq(loaded.weather.rain_intensity, 0.5, 0.000001)
	assert_almost_eq(loaded.foliage.tree_sway_speed, 1.2, 0.000001)
