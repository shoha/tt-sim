class_name FoliageSettings
extends Resource

## Typed wind-sway tuning per WindFoliage category. Replaces the sparse
## LevelData.foliage_overrides dictionary. Defaults come from WindFoliage.PRESETS
## so there is one source of truth for the base sway; a saved level stores explicit
## values, which means it pins the sway it was authored with even if the presets
## change later. to_dict() uses the "<category>_sway_<param>" keys that
## WindFoliage.get_effective_preset() reads, so the live and map-load apply paths
## consume it unchanged.

const KEYS: Array[String] = [
	"tree_sway_speed",
	"tree_sway_amplitude",
	"grass_sway_speed",
	"grass_sway_amplitude",
]

@export var tree_sway_speed: float = WindFoliage.PRESETS["tree"]["sway_speed"]
@export var tree_sway_amplitude: float = WindFoliage.PRESETS["tree"]["sway_amplitude"]
@export var grass_sway_speed: float = WindFoliage.PRESETS["grass"]["sway_speed"]
@export var grass_sway_amplitude: float = WindFoliage.PRESETS["grass"]["sway_amplitude"]


static func default() -> FoliageSettings:
	return FoliageSettings.new()


func to_dict() -> Dictionary:
	var data := {}
	for key in KEYS:
		data[key] = float(get(key))
	return data


static func from_dict(data: Variant) -> FoliageSettings:
	var settings := FoliageSettings.new()
	if data is not Dictionary:
		return settings
	var dict := data as Dictionary
	for key in KEYS:
		if dict.has(key):
			settings.set(key, float(dict[key]))
	return settings


func copy_settings() -> FoliageSettings:
	return duplicate() as FoliageSettings
