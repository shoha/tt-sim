class_name LofiSettings
extends Resource

## Typed lo-fi post-processing parameters for a level. Replaces the sparse
## LevelData.lofi_overrides dictionary. Only the seven numeric shader parameters
## the Visuals drawer exposes live here; color_tint, grain_speed and grain_scale
## stay shader defaults (reset from Constants.LOFI_DEFAULTS at map load) because
## they are not level-editable and a Color would not survive JSON.
##
## to_dict() is complete (every key, every time) and uses the shader parameter
## names as keys, so GameMap.apply_lofi_overrides() consumes it unchanged and a
## full application never leaves a previous level's value behind. from_dict()
## accepts the sparse dictionaries older level files contain.

const KEYS: Array[String] = [
	"pixelation",
	"saturation",
	"color_levels",
	"dither_strength",
	"vignette_strength",
	"vignette_radius",
	"grain_intensity",
]

@export var pixelation: float = Constants.LOFI_DEFAULTS["pixelation"]
@export var saturation: float = Constants.LOFI_DEFAULTS["saturation"]
@export var color_levels: float = Constants.LOFI_DEFAULTS["color_levels"]
@export var dither_strength: float = Constants.LOFI_DEFAULTS["dither_strength"]
@export var vignette_strength: float = Constants.LOFI_DEFAULTS["vignette_strength"]
@export var vignette_radius: float = Constants.LOFI_DEFAULTS["vignette_radius"]
@export var grain_intensity: float = Constants.LOFI_DEFAULTS["grain_intensity"]


static func default() -> LofiSettings:
	return LofiSettings.new()


## Shader-parameter dictionary: every key, current value.
func to_dict() -> Dictionary:
	var data := {}
	for key in KEYS:
		data[key] = float(get(key))
	return data


## Rebuild from to_dict() output or from an older sparse dictionary. Missing keys
## keep their defaults; anything that is not a Dictionary yields the defaults.
static func from_dict(data: Variant) -> LofiSettings:
	var settings := LofiSettings.new()
	if data is not Dictionary:
		return settings
	var dict := data as Dictionary
	for key in KEYS:
		if dict.has(key):
			settings.set(key, float(dict[key]))
	return settings


## Independent copy (all fields are floats, so duplicate() is a deep copy).
func copy_settings() -> LofiSettings:
	return duplicate() as LofiSettings
