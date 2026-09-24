class_name WaterSettings
extends Resource

## Typed per-level water tuning: one field per shaders/water.gdshader uniform the
## Water pane can author. Modelled on FoliageSettings, with one difference:
## three fields are Colors, which do not survive JSON, so to_dict() writes them
## as hex strings (Color.to_html) and from_dict() reads either a hex string or a
## Color (in-process broadcasts and .tres levels never go through JSON). Use
## colors_match() for round-trip comparison since hex serialisation quantises to 1/255.
##
## to_dict() is complete (every key, every time) and uses the uniform names as
## keys, so WaterGlbUtils.apply_water_settings() consumes it unchanged and a full
## apply never leaves a previous level's value behind. A saved level stores
## explicit values and therefore pins the water it was authored with, even if
## WaterPresets changes later. The defaults below are the "stylized" look, the
## "lagoon" palette and the "gentle" motion (see WaterPresets).

const KEYS: Array[String] = [
	"water_color",
	"shore_color",
	"foam_color",
	"depth_absorption",
	"ripple_strength",
	"ripple_scale",
	"wave_speed",
	"foam_strength",
	"roughness_value",
	"specular_value",
	"sky_blend_strength",
	"caustic_strength",
	"caustic_scale",
	"refraction_strength",
	"foam_edge_sensitivity",
	"disturbance_ripple_strength",
	"disturbance_ripple_radius",
	"shore_depth_range",
	"shimmer_strength",
	"fresnel_power",
	"fresnel_strength",
	"bob_height",
]
const COLOR_KEYS: Array[String] = ["water_color", "shore_color", "foam_color"]
## Hex serialisation quantises each channel to 1/255, so colours that went through
## to_dict()/from_dict() (or an 8-bit image) are compared with this tolerance, not
## is_equal_approx.
const COLOR_TOLERANCE := 1.0 / 255.0

@export var water_color: Color = Color(0.05, 0.30, 0.38, 0.8)
@export var shore_color: Color = Color(0.35, 0.75, 0.70, 0.6)
@export var foam_color: Color = Color(0.88, 0.94, 0.96, 0.9)
@export var depth_absorption: float = 1.4
@export var ripple_strength: float = 0.5
@export var ripple_scale: float = 1.6
@export var wave_speed: float = 0.6
@export var foam_strength: float = 1.0
@export var roughness_value: float = 0.15
@export var specular_value: float = 0.6
@export var sky_blend_strength: float = 0.15
@export var caustic_strength: float = 1.0
@export var caustic_scale: float = 1.3
@export var refraction_strength: float = 0.03
@export var foam_edge_sensitivity: float = 1.5
@export var disturbance_ripple_strength: float = 0.5
@export var disturbance_ripple_radius: float = 1.2
@export var shore_depth_range: float = 0.4
@export var shimmer_strength: float = 0.3
@export var fresnel_power: float = 4.0
@export var fresnel_strength: float = 0.5
@export var bob_height: float = 0.02


static func default() -> WaterSettings:
	return WaterSettings.new()


## Uniform-name dictionary: every key, current value, colors as hex strings.
func to_dict() -> Dictionary:
	var data := {}
	for key: String in KEYS:
		if key in COLOR_KEYS:
			data[key] = (get(key) as Color).to_html(true)
		else:
			data[key] = float(get(key))
	return data


## Rebuild from to_dict() output or a sparse dictionary. Missing keys keep
## their defaults; unknown keys are ignored; anything that is not a Dictionary
## yields the defaults.
static func from_dict(data: Variant) -> WaterSettings:
	var settings := WaterSettings.new()
	if data is not Dictionary:
		return settings
	var dict := data as Dictionary
	for key: String in KEYS:
		if not dict.has(key):
			continue
		if key in COLOR_KEYS:
			settings.set(key, color_from_value(dict[key], settings.get(key)))
		else:
			settings.set(key, float(dict[key]))
	return settings


## A Color from either a Color or an HTML hex string; anything else, or an
## invalid string, returns fallback so a corrupt save cannot poison the material.
static func color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var hex_str: String = value
		if Color.html_is_valid(hex_str):
			return Color.html(hex_str)
	return fallback


static func colors_match(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) <= COLOR_TOLERANCE
		and absf(a.g - b.g) <= COLOR_TOLERANCE
		and absf(a.b - b.b) <= COLOR_TOLERANCE
		and absf(a.a - b.a) <= COLOR_TOLERANCE
	)


func copy_settings() -> WaterSettings:
	return duplicate() as WaterSettings


## The settings a legacy LevelData.water_style name meant, via
## WaterPresets.STYLE_COMPOSITION. Unknown names (including "custom") give the
## defaults, which is what the old preset lookup did too.
static func from_style(style: String) -> WaterSettings:
	return WaterSettings.from_dict(WaterPresets.get_preset(style))


## Overwrite just the keys in values (one preset group's worth), leaving the
## other groups untouched -- this is what a tile press does.
func apply_group(values: Dictionary) -> void:
	for key: String in values:
		if key in COLOR_KEYS:
			set(key, color_from_value(values[key], get(key)))
		elif key in KEYS:
			set(key, float(values[key]))


func matching_look() -> String:
	return _matching(WaterPresets.LOOKS)


func matching_palette() -> String:
	return _matching(WaterPresets.PALETTES)


func matching_motion() -> String:
	return _matching(WaterPresets.MOTIONS)


## The id of the preset in group whose every value matches this resource, or
## WaterPresets.CUSTOM_KEY. Floats compare with is_equal_approx and colors with
## colors_match (a hex-quantisation tolerance) so a level that went through JSON
## still matches the palette it was saved with.
func _matching(group: Dictionary) -> String:
	for id: String in group:
		var values: Dictionary = group[id]
		var matches := true
		for key: String in values:
			if key in COLOR_KEYS:
				if not colors_match(get(key), values[key]):
					matches = false
					break
			elif not is_equal_approx(float(get(key)), float(values[key])):
				matches = false
				break
		if matches:
			return id
	return WaterPresets.CUSTOM_KEY
