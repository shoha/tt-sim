class_name WaterPresets
extends RefCounted

## Named Water Style presets applied to the shared water ShaderMaterial by
## WaterGlbUtils.apply_water_style() -- mirrors EnvironmentPresets' dictionary-of-
## property-values pattern. Keys match shaders/water.gdshader uniform names
## exactly, so WaterGlbUtils can set them directly as shader_parameter/<key>.
## See docs/superpowers/specs/2026-08-11-water-shader-quality-design.md.
##
## "stylized": long, gentle waves, a wide bright shallow band, strong caustics and
## chunky foam -- a readable board-game look. "realistic": shorter waves, deeper and
## murkier water, a tighter specular glint and subtle caustics.

const PRESETS := {
	"stylized":
	{
		"water_color": Color(0.05, 0.30, 0.38, 0.8),
		"shore_color": Color(0.35, 0.75, 0.70, 0.6),
		"shore_depth_range": 0.4,
		"depth_absorption": 1.4,
		"shimmer_strength": 0.3,
		"ripple_scale": 1.6,
		"ripple_strength": 0.5,
		"fresnel_power": 4.0,
		"fresnel_strength": 0.5,
		"roughness_value": 0.15,
		"specular_value": 0.6,
		"sky_blend_strength": 0.15,
		"caustic_scale": 1.3,
		"caustic_strength": 1.0,
		"disturbance_ripple_radius": 1.2,
		"disturbance_ripple_strength": 0.5,
		"foam_color": Color(0.88, 0.94, 0.96, 0.9),
		"foam_edge_sensitivity": 1.5,
		"foam_strength": 1.0,
	},
	"realistic":
	{
		"water_color": Color(0.02, 0.12, 0.22, 0.9),
		"shore_color": Color(0.20, 0.50, 0.55, 0.7),
		"shore_depth_range": 0.5,
		"depth_absorption": 2.2,
		"shimmer_strength": 0.15,
		"ripple_scale": 2.0,
		"ripple_strength": 0.6,
		"fresnel_power": 3.0,
		"fresnel_strength": 0.7,
		"roughness_value": 0.06,
		"specular_value": 0.9,
		"sky_blend_strength": 0.35,
		"caustic_scale": 1.8,
		"caustic_strength": 0.5,
		"disturbance_ripple_radius": 1.2,
		"disturbance_ripple_strength": 0.5,
		"foam_color": Color(0.85, 0.92, 0.95, 0.85),
		"foam_edge_sensitivity": 1.5,
		"foam_strength": 0.7,
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
