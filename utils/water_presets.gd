class_name WaterPresets
extends RefCounted

## Named Water Style presets applied to the shared water ShaderMaterial by
## WaterGlbUtils.apply_water_style() -- mirrors EnvironmentPresets' dictionary-of-
## property-values pattern. Keys match shaders/water.gdshader uniform names
## exactly, so WaterGlbUtils can set them directly as shader_parameter/<key>.
## See docs/superpowers/specs/2026-08-11-water-shader-quality-design.md.

const PRESETS := {
	"stylized":
	{
		"water_color": Color(0.04, 0.22, 0.28, 0.75),
		"shore_color": Color(0.35, 0.75, 0.7, 0.65),
		"ripple_scale": 4.0,
		"fresnel_power": 4.0,
		"fresnel_strength": 0.5,
		"roughness_value": 0.08,
		"specular_value": 0.6,
		"sky_blend_strength": 0.15,
		"disturbance_ripple_radius": 1.2,
		"disturbance_ripple_strength": 0.5,
		"foam_color": Color(0.85, 0.92, 0.95, 0.9),
		"foam_edge_sensitivity": 0.15,
		"foam_strength": 0.8,
	},
	"realistic":
	{
		"water_color": Color(0.02, 0.12, 0.22, 0.85),
		"shore_color": Color(0.25, 0.55, 0.6, 0.7),
		"ripple_scale": 7.0,
		"fresnel_power": 3.0,
		"fresnel_strength": 0.7,
		"roughness_value": 0.04,
		"specular_value": 0.9,
		"sky_blend_strength": 0.4,
		"disturbance_ripple_radius": 1.2,
		"disturbance_ripple_strength": 0.5,
		"foam_color": Color(0.85, 0.92, 0.95, 0.9),
		"foam_edge_sensitivity": 0.15,
		"foam_strength": 0.8,
	},
}

const DEFAULT_PRESET := "stylized"


static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for key in PRESETS.keys():
		names.append(key)
	return names


## Falls back to DEFAULT_PRESET for an unrecognized name (corrupt save data,
## or a preset removed in a future version) rather than erroring.
static func get_preset(preset_name: String) -> Dictionary:
	return PRESETS.get(preset_name, PRESETS[DEFAULT_PRESET]).duplicate()
