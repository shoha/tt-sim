class_name WaterPresets
extends RefCounted

## Named water presets in three independent groups, each owning a disjoint
## subset of WaterSettings.KEYS (asserted by test_water_presets.gd):
##
## - LOOKS: how the surface renders (glint, shine, sky reflection, caustics,
##   distortion, edge foam, token ripples, shallows width, the hidden shimmer /
##   fresnel / bob values).
## - PALETTES: deep color, shallows color, foam color and murkiness.
## - MOTIONS: wave amount, ripple detail, speed and foam amount.
##
## The Water pane shows one tile row per group and derives the selected tile
## by matching values (WaterSettings.matching_*), so a level never stores a
## tile id. Keys are shaders/water.gdshader uniform names, so WaterGlbUtils
## sets them directly as shader_parameter/<key>.
##
## get_preset()/get_preset_names() are the legacy two-name API: a style name
## maps through STYLE_COMPOSITION to one preset from each group, merged into a
## flat dictionary. LevelData keeps writing water_style so older builds get the
## closest look.

const CUSTOM_KEY := "custom"
const DEFAULT_PRESET := "stylized"

const LOOK_KEYS: Array[String] = [
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
const PALETTE_KEYS: Array[String] = ["water_color", "shore_color", "foam_color", "depth_absorption"]
const MOTION_KEYS: Array[String] = [
	"ripple_strength", "ripple_scale", "wave_speed", "foam_strength"
]

const LOOKS := {
	"stylized":
	{
		"roughness_value": 0.15,
		"specular_value": 0.6,
		"sky_blend_strength": 0.15,
		"caustic_strength": 1.0,
		"caustic_scale": 1.3,
		"refraction_strength": 0.03,
		"foam_edge_sensitivity": 1.5,
		"disturbance_ripple_strength": 0.5,
		"disturbance_ripple_radius": 1.2,
		"shore_depth_range": 0.4,
		"shimmer_strength": 0.3,
		"fresnel_power": 4.0,
		"fresnel_strength": 0.5,
		"bob_height": 0.02,
	},
	"realistic":
	{
		"roughness_value": 0.06,
		"specular_value": 0.9,
		"sky_blend_strength": 0.35,
		"caustic_strength": 0.5,
		"caustic_scale": 1.8,
		"refraction_strength": 0.03,
		"foam_edge_sensitivity": 1.5,
		"disturbance_ripple_strength": 0.5,
		"disturbance_ripple_radius": 1.2,
		"shore_depth_range": 0.5,
		"shimmer_strength": 0.15,
		"fresnel_power": 3.0,
		"fresnel_strength": 0.7,
		"bob_height": 0.02,
	},
}

## Deep color, shallows color, foam color, murkiness. Starting values from the
## design spec; tuned on the River level (see the plan's final task).
const PALETTES := {
	"lagoon":
	{
		"water_color": Color(0.05, 0.30, 0.38, 0.8),
		"shore_color": Color(0.35, 0.75, 0.70, 0.6),
		"foam_color": Color(0.88, 0.94, 0.96, 0.9),
		"depth_absorption": 1.4,
	},
	"lake":
	{
		"water_color": Color(0.02, 0.12, 0.22, 0.9),
		"shore_color": Color(0.20, 0.50, 0.55, 0.7),
		"foam_color": Color(0.85, 0.92, 0.95, 0.85),
		"depth_absorption": 2.2,
	},
	"river":
	{
		"water_color": Color(0.09, 0.17, 0.11, 0.9),
		"shore_color": Color(0.42, 0.50, 0.28, 0.7),
		"foam_color": Color(0.90, 0.91, 0.82, 0.85),
		"depth_absorption": 2.8,
	},
	"swamp":
	{
		"water_color": Color(0.07, 0.14, 0.03, 0.95),
		"shore_color": Color(0.28, 0.35, 0.10, 0.8),
		"foam_color": Color(0.80, 0.78, 0.55, 0.8),
		"depth_absorption": 5.0,
	},
	"ocean":
	{
		"water_color": Color(0.01, 0.05, 0.16, 0.95),
		"shore_color": Color(0.10, 0.36, 0.55, 0.75),
		"foam_color": Color(0.92, 0.95, 0.98, 0.9),
		"depth_absorption": 2.8,
	},
	# Pale palettes need a low depth_absorption: at 2.6 the deep color saturated
	# every texel and Glacial read as flat cyan paint instead of milky water.
	"glacial":
	{
		"water_color": Color(0.08, 0.42, 0.52, 0.85),
		"shore_color": Color(0.50, 0.80, 0.88, 0.65),
		"foam_color": Color(0.90, 0.96, 1.00, 0.9),
		"depth_absorption": 1.4,
	},
}

const MOTIONS := {
	"still":
	{"ripple_strength": 0.15, "ripple_scale": 1.2, "wave_speed": 0.2, "foam_strength": 0.3},
	"gentle":
	{"ripple_strength": 0.5, "ripple_scale": 1.6, "wave_speed": 0.6, "foam_strength": 1.0},
	"lively":
	{"ripple_strength": 0.65, "ripple_scale": 2.0, "wave_speed": 0.9, "foam_strength": 1.0},
	"rough": {"ripple_strength": 0.9, "ripple_scale": 2.6, "wave_speed": 1.4, "foam_strength": 1.5},
}

## Legacy style name -> [look, palette, motion].
const STYLE_COMPOSITION := {
	"stylized": ["stylized", "lagoon", "gentle"],
	"realistic": ["realistic", "lake", "gentle"],
}


static func get_look_names() -> Array[String]:
	return _names(LOOKS)


static func get_palette_names() -> Array[String]:
	return _names(PALETTES)


static func get_motion_names() -> Array[String]:
	return _names(MOTIONS)


static func get_preset_names() -> Array[String]:
	return _names(STYLE_COMPOSITION)


## Flat dictionary over every WaterSettings key for a legacy style name. Falls
## back to DEFAULT_PRESET for an unrecognized name (corrupt save data, "custom"
## from a newer build, or a style removed later) rather than erroring.
static func get_preset(preset_name: String) -> Dictionary:
	var parts: Array = STYLE_COMPOSITION.get(preset_name, STYLE_COMPOSITION[DEFAULT_PRESET])
	var merged := {}
	merged.merge(LOOKS[parts[0]])
	merged.merge(PALETTES[parts[1]])
	merged.merge(MOTIONS[parts[2]])
	return merged


static func _names(group: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for key in group.keys():
		names.append(key)
	return names
