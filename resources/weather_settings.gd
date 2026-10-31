class_name WeatherSettings
extends Resource

## Typed weather intensities (0 = off, 1 = max) for a level. Replaces the sparse
## LevelData.weather_overrides dictionary. to_dict() is complete, so
## WeatherRenderer.apply_weather() (via GameMap.apply_weather_overrides) always
## receives every intensity and a revert can never leave an effect stuck on.

const KEYS: Array[String] = [
	"rain_intensity",
	"snow_intensity",
	"fog_intensity",
	"wind_intensity",
	"wind_seed",
	"wind_direction_deg",
]

## wind_direction_deg value meaning "the default direction" (see WindPresets.DEFAULT_DIR_ANGLE).
const WIND_DIRECTION_AUTO := -1.0

@export var rain_intensity: float = 0.0
@export var snow_intensity: float = 0.0
@export var fog_intensity: float = 0.0
@export var wind_intensity: float = 0.0
## Phases the wind's gust fronts and veer (docs/systems/wind.md section 3). Stored as a float
## in the dictionary, so keep it under 2^24; 0 = derive it from the level.
@export var wind_seed: float = 0.0
## Degrees on the map plane (0 = +x, 90 = +z) the wind blows toward; below 0 = the default
## (WindPresets.DEFAULT_DIR_ANGLE).
@export var wind_direction_deg: float = WIND_DIRECTION_AUTO


static func default() -> WeatherSettings:
	return WeatherSettings.new()


func to_dict() -> Dictionary:
	var data := {}
	for key in KEYS:
		data[key] = float(get(key))
	return data


static func from_dict(data: Variant) -> WeatherSettings:
	var settings := WeatherSettings.new()
	if data is not Dictionary:
		return settings
	var dict := data as Dictionary
	for key in KEYS:
		if dict.has(key):
			settings.set(key, float(dict[key]))
	return settings


func copy_settings() -> WeatherSettings:
	return duplicate() as WeatherSettings
