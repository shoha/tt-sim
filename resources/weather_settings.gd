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
]

@export var rain_intensity: float = 0.0
@export var snow_intensity: float = 0.0
@export var fog_intensity: float = 0.0
@export var wind_intensity: float = 0.0


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
