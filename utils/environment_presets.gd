extends RefCounted
class_name EnvironmentPresets

## Environment preset definitions and utilities for map lighting/mood.
## Presets define ambient light, fog, background, and post-processing settings.
## Map creators can select a preset and optionally override specific values.

## Available environment properties that can be configured
## These map to Godot's Environment resource properties
const PROPERTY_DEFAULTS = {
	# Background & Sky
	"background_mode": Environment.BG_COLOR,  # BG_COLOR, BG_SKY, BG_CANVAS
	"background_color": Color(0.3, 0.3, 0.3),
	"sky_preset": "",  # Sky preset name (see SKY_PRESETS); "" = no sky
	# Ambient light
	# AMBIENT_SOURCE_COLOR or AMBIENT_SOURCE_SKY
	"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
	"ambient_light_color": Color(0.4, 0.4, 0.45),
	"ambient_light_energy": 0.5,
	# Fog
	"fog_enabled": false,
	"fog_light_color": Color(0.5, 0.5, 0.55),
	"fog_light_energy": 1.0,
	"fog_density": 0.01,
	"fog_height": 0.0,
	"fog_height_density": 0.0,
	# Tonemap
	# LINEAR, REINHARDT, FILMIC, or ACES
	"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	"tonemap_exposure": 1.0,
	"tonemap_white": 1.0,
	# Glow/Bloom
	"glow_enabled": false,
	"glow_intensity": 0.8,
	"glow_strength": 1.0,
	"glow_bloom": 0.0,
	# SSAO (Screen Space Ambient Occlusion)
	"ssao_enabled": false,
	"ssao_intensity": 2.0,
	# SSR (Screen Space Reflections)
	"ssr_enabled": false,
	# SDFGI (Signed Distance Field Global Illumination)
	"sdfgi_enabled": false,
	# Reflected light (relevant when using a Sky)
	"reflected_light_source": Environment.REFLECTION_SOURCE_BG,
	# Color Adjustments
	"adjustment_enabled": false,
	"adjustment_brightness": 1.0,
	"adjustment_contrast": 1.0,
	"adjustment_saturation": 1.0,
}

## Built-in procedural sky presets.
## Each entry defines ProceduralSkyMaterial properties.
## Used when background_mode == BG_SKY and a sky_preset is selected.
const SKY_PRESETS = {
	"clear_day":
	{
		"description": "Clear blue sky with neutral horizon",
		"sky_top_color": Color(0.38, 0.45, 0.75),
		"sky_horizon_color": Color(0.65, 0.72, 0.83),
		"ground_bottom_color": Color(0.2, 0.17, 0.13),
		"ground_horizon_color": Color(0.65, 0.67, 0.67),
	},
	"sunset":
	{
		"description": "Warm orange/pink sunset sky",
		"sky_top_color": Color(0.15, 0.15, 0.45),
		"sky_horizon_color": Color(1.0, 0.55, 0.25),
		"ground_bottom_color": Color(0.1, 0.05, 0.02),
		"ground_horizon_color": Color(0.85, 0.45, 0.2),
	},
	"overcast":
	{
		"description": "Gray overcast sky",
		"sky_top_color": Color(0.45, 0.47, 0.52),
		"sky_horizon_color": Color(0.58, 0.6, 0.63),
		"ground_bottom_color": Color(0.25, 0.25, 0.25),
		"ground_horizon_color": Color(0.5, 0.52, 0.55),
	},
	"night_sky":
	{
		"description": "Dark night sky with faint horizon",
		"sky_top_color": Color(0.02, 0.02, 0.06),
		"sky_horizon_color": Color(0.05, 0.05, 0.12),
		"ground_bottom_color": Color(0.01, 0.01, 0.02),
		"ground_horizon_color": Color(0.03, 0.04, 0.06),
	},
}

## Built-in environment presets
## Each preset overrides only the properties it needs to change from defaults.
## Presets now use the full range of properties including sky, fog details,
## tonemap, glow, and post-processing effects where appropriate.
const PRESETS = {
	# ========== OUTDOOR PRESETS ==========
	"outdoor_day":
	{
		"description": "Bright outdoor daytime - clear sky, neutral lighting",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "clear_day",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.7, 0.75, 0.85),
		"ambient_light_energy": 0.6,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.0,
		"tonemap_white": 1.2,
		"ssao_enabled": true,
		"ssao_intensity": 1.0,
	},
	"outdoor_overcast":
	{
		"description": "Cloudy outdoor day - soft diffuse lighting",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "overcast",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.6, 0.62, 0.68),
		"ambient_light_energy": 0.7,
		"fog_enabled": true,
		"fog_light_color": Color(0.6, 0.62, 0.65),
		"fog_light_energy": 0.8,
		"fog_density": 0.002,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.95,
		"ssao_enabled": true,
		"ssao_intensity": 1.2,
	},
	"outdoor_sunset":
	{
		"description": "Golden hour - warm orange/pink lighting",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "sunset",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(1.0, 0.7, 0.5),
		"ambient_light_energy": 0.5,
		"fog_enabled": true,
		"fog_light_color": Color(1.0, 0.6, 0.4),
		"fog_light_energy": 1.2,
		"fog_density": 0.003,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.1,
		"tonemap_white": 1.5,
		"glow_enabled": true,
		"glow_intensity": 0.5,
		"glow_strength": 1.1,
		"glow_bloom": 0.1,
	},
	"outdoor_night":
	{
		"description": "Moonlit night - cool blue tones, low visibility",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "night_sky",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.15, 0.18, 0.3),
		"ambient_light_energy": 0.25,
		"fog_enabled": true,
		"fog_light_color": Color(0.1, 0.12, 0.2),
		"fog_light_energy": 0.6,
		"fog_density": 0.008,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.8,
		"glow_enabled": true,
		"glow_intensity": 0.3,
		"glow_bloom": 0.05,
		"ssao_enabled": true,
		"ssao_intensity": 1.5,
	},
	# ========== INDOOR/DUNGEON PRESETS ==========
	"indoor_neutral":
	{
		"description": "Standard indoor lighting - neutral, well-lit",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.15, 0.15),
		"ambient_light_color": Color(0.5, 0.48, 0.45),
		"ambient_light_energy": 0.4,
		"ssao_enabled": true,
		"ssao_intensity": 1.5,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.0,
		"tonemap_white": 1.0,
	},
	"dungeon_dark":
	{
		"description": "Dark dungeon - minimal ambient, torch-lit atmosphere",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.02, 0.03),
		"ambient_light_color": Color(0.1, 0.08, 0.06),
		"ambient_light_energy": 0.15,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.04, 0.03),
		"fog_light_energy": 0.5,
		"fog_density": 0.02,
		"ssao_enabled": true,
		"ssao_intensity": 2.5,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.9,
		"tonemap_white": 0.9,
		"glow_enabled": true,
		"glow_intensity": 0.2,
		"glow_bloom": 0.02,
	},
	"dungeon_crypt":
	{
		"description": "Eerie crypt - cold, deathly atmosphere",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.01, 0.02, 0.03),
		"ambient_light_color": Color(0.08, 0.1, 0.15),
		"ambient_light_energy": 0.2,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.08, 0.12),
		"fog_light_energy": 0.7,
		"fog_density": 0.025,
		"fog_height": -1.0,
		"fog_height_density": 0.5,
		"ssao_enabled": true,
		"ssao_intensity": 2.0,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.85,
		"glow_enabled": true,
		"glow_intensity": 0.3,
		"glow_bloom": 0.05,
	},
	"cave":
	{
		"description": "Natural cave - damp, earthy tones",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.02, 0.02),
		"ambient_light_color": Color(0.12, 0.1, 0.08),
		"ambient_light_energy": 0.2,
		"fog_enabled": true,
		"fog_light_color": Color(0.08, 0.06, 0.05),
		"fog_light_energy": 0.6,
		"fog_density": 0.015,
		"fog_height_density": 0.2,
		"ssao_enabled": true,
		"ssao_intensity": 2.0,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.9,
	},
	# ========== SPECIAL ATMOSPHERE PRESETS ==========
	"tavern":
	{
		"description": "Cozy tavern - warm firelit interior",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.08, 0.05, 0.03),
		"ambient_light_color": Color(0.8, 0.5, 0.3),
		"ambient_light_energy": 0.35,
		"fog_enabled": true,
		"fog_light_color": Color(0.3, 0.2, 0.1),
		"fog_light_energy": 0.8,
		"fog_density": 0.008,
		"ssao_enabled": true,
		"ssao_intensity": 1.5,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.0,
		"glow_enabled": true,
		"glow_intensity": 0.4,
		"glow_strength": 1.1,
		"glow_bloom": 0.05,
	},
	"forest":
	{
		"description": "Dense forest - dappled green light",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "clear_day",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.3, 0.45, 0.25),
		"ambient_light_energy": 0.45,
		"fog_enabled": true,
		"fog_light_color": Color(0.2, 0.3, 0.15),
		"fog_light_energy": 0.9,
		"fog_density": 0.006,
		"fog_height_density": 0.3,
		"ssao_enabled": true,
		"ssao_intensity": 1.8,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.0,
	},
	"swamp":
	{
		"description": "Murky swamp - thick fog, sickly green",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.08, 0.1, 0.05),
		"ambient_light_color": Color(0.25, 0.3, 0.15),
		"ambient_light_energy": 0.35,
		"fog_enabled": true,
		"fog_light_color": Color(0.15, 0.2, 0.1),
		"fog_light_energy": 1.0,
		"fog_density": 0.04,
		"fog_height": -2.0,
		"fog_height_density": 1.0,
		"ssao_enabled": true,
		"ssao_intensity": 2.0,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.9,
		"glow_enabled": true,
		"glow_intensity": 0.2,
		"glow_bloom": 0.03,
	},
	"underwater":
	{
		"description": "Underwater - blue-green murky depths",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.08, 0.12),
		"ambient_light_color": Color(0.1, 0.25, 0.35),
		"ambient_light_energy": 0.4,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.15, 0.25),
		"fog_light_energy": 1.2,
		"fog_density": 0.05,
		"fog_height_density": 0.8,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.9,
		"glow_enabled": true,
		"glow_intensity": 0.3,
		"glow_bloom": 0.08,
		"ssr_enabled": true,
	},
	"hell":
	{
		"description": "Infernal realm - fiery red/orange glow",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.02, 0.0),
		"ambient_light_color": Color(0.6, 0.15, 0.05),
		"ambient_light_energy": 0.4,
		"fog_enabled": true,
		"fog_light_color": Color(0.4, 0.1, 0.0),
		"fog_light_energy": 1.5,
		"fog_density": 0.02,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.1,
		"tonemap_white": 1.3,
		"glow_enabled": true,
		"glow_intensity": 0.6,
		"glow_strength": 1.2,
		"glow_bloom": 0.15,
	},
	"ethereal":
	{
		"description": "Ethereal/fey realm - soft magical glow",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.1, 0.2),
		"ambient_light_color": Color(0.5, 0.4, 0.7),
		"ambient_light_energy": 0.5,
		"fog_enabled": true,
		"fog_light_color": Color(0.3, 0.25, 0.5),
		"fog_light_energy": 1.0,
		"fog_density": 0.01,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.05,
		"glow_enabled": true,
		"glow_intensity": 0.7,
		"glow_strength": 1.3,
		"glow_bloom": 0.2,
	},
	"arctic":
	{
		"description": "Frozen tundra - cold blue-white",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "overcast",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.6, 0.7, 0.85),
		"ambient_light_energy": 0.6,
		"fog_enabled": true,
		"fog_light_color": Color(0.8, 0.85, 0.95),
		"fog_light_energy": 0.9,
		"fog_density": 0.008,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.1,
		"tonemap_white": 1.2,
		"ssr_enabled": true,
	},
	"desert":
	{
		"description": "Harsh desert - bright, warm, hazy",
		"background_mode": Environment.BG_SKY,
		"sky_preset": "clear_day",
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"ambient_light_color": Color(0.9, 0.8, 0.65),
		"ambient_light_energy": 0.65,
		"fog_enabled": true,
		"fog_light_color": Color(0.9, 0.8, 0.6),
		"fog_light_energy": 1.0,
		"fog_density": 0.004,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.2,
		"tonemap_white": 1.4,
	},
	# ========== UTILITY PRESETS ==========
	"none":
	{
		"description": "No environment effects - use map's embedded lighting only",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.2, 0.2, 0.2),
		"ambient_light_color": Color(0.3, 0.3, 0.3),
		"ambient_light_energy": 0.3,
	},
	"bright_editor":
	{
		"description": "Bright editing mode - maximum visibility",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.4, 0.4, 0.45),
		"ambient_light_color": Color(0.8, 0.8, 0.85),
		"ambient_light_energy": 0.8,
		"tonemap_mode": Environment.TONE_MAPPER_LINEAR,
		"tonemap_exposure": 1.2,
	},
}


## Get list of all available sky preset names
static func get_sky_preset_names() -> Array[String]:
	var names: Array[String] = []
	for key in SKY_PRESETS.keys():
		names.append(key)
	names.sort()
	return names


## Get a sky preset's description
static func get_sky_preset_description(preset_name: String) -> String:
	if SKY_PRESETS.has(preset_name):
		return SKY_PRESETS[preset_name].get("description", "")
	return ""


## Create a Sky resource with ProceduralSkyMaterial from a sky preset.
## Returns null if the preset name is not found.
static func create_sky_from_preset(preset_name: String) -> Sky:
	if not SKY_PRESETS.has(preset_name):
		return null
	var config = SKY_PRESETS[preset_name]
	var material = ProceduralSkyMaterial.new()
	material.sky_top_color = config.get("sky_top_color", Color(0.38, 0.45, 0.75))
	material.sky_horizon_color = config.get("sky_horizon_color", Color(0.65, 0.72, 0.83))
	material.ground_bottom_color = config.get("ground_bottom_color", Color(0.2, 0.17, 0.13))
	material.ground_horizon_color = config.get("ground_horizon_color", Color(0.65, 0.67, 0.67))
	var sky = Sky.new()
	sky.sky_material = material
	return sky


## Get list of all available preset names
static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for key in PRESETS.keys():
		names.append(key)
	names.sort()
	return names


## Get a preset's description
static func get_preset_description(preset_name: String) -> String:
	if PRESETS.has(preset_name):
		return PRESETS[preset_name].get("description", "")
	return ""


## Get a complete environment configuration by merging layers:
## 1. PROPERTY_DEFAULTS (base)
## 2. Map defaults — applied when preset is "" and map_defaults is non-empty
## 3. Preset values — applied when a named preset is selected
## 4. User overrides — always applied on top
##
## When preset is "" (no explicit choice) and the map provides its own
## embedded environment, the map's settings are used as the base instead of
## a named preset.  This means map defaults are always re-derived from the
## live map file, never baked into level_data.
static func get_environment_config(
	preset_name: String = "",
	overrides: Dictionary = {},
	map_defaults: Dictionary = {},
) -> Dictionary:
	var config = PROPERTY_DEFAULTS.duplicate()

	# Layer: map defaults (when no preset is explicitly selected)
	if preset_name == "" and not map_defaults.is_empty():
		for key in map_defaults:
			if key != "description" and config.has(key):
				config[key] = map_defaults[key]
	# Layer: named preset
	elif preset_name != "" and PRESETS.has(preset_name):
		var preset = PRESETS[preset_name]
		for key in preset:
			if key != "description":
				config[key] = preset[key]

	# Layer: user overrides (always on top)
	for key in overrides:
		if config.has(key):
			config[key] = overrides[key]

	return config


## Apply environment configuration to a WorldEnvironment node.
## Creates the Environment resource if needed.
## [param map_sky] is an optional Sky resource extracted from the loaded map,
## used when sky_preset == "map_default".
## [param map_defaults] is the config extracted from the map's embedded
## WorldEnvironment; used as the base layer when preset_name is "".
static func apply_to_world_environment(
	world_env: WorldEnvironment,
	preset_name: String = "",
	overrides: Dictionary = {},
	map_sky: Sky = null,
	map_defaults: Dictionary = {},
) -> void:
	var config = get_environment_config(preset_name, overrides, map_defaults)

	# Create or get environment
	var env = world_env.environment
	if not env:
		env = Environment.new()
		world_env.environment = env

	# Apply all settings
	_apply_config_to_environment(env, config, map_sky)


## Apply configuration to an Environment resource.
## [param map_sky] optional Sky resource for the "map_default" sky preset.
static func _apply_config_to_environment(
	env: Environment, config: Dictionary, map_sky: Sky = null
) -> void:
	# Background
	env.background_mode = config.get("background_mode", Environment.BG_COLOR)
	env.background_color = config.get("background_color", Color(0.3, 0.3, 0.3))

	# Ambient light
	env.ambient_light_source = config.get("ambient_light_source", Environment.AMBIENT_SOURCE_COLOR)
	env.ambient_light_color = config.get("ambient_light_color", Color(0.4, 0.4, 0.45))
	env.ambient_light_energy = config.get("ambient_light_energy", 0.5)

	# Fog
	env.fog_enabled = config.get("fog_enabled", false)
	env.fog_light_color = config.get("fog_light_color", Color(0.5, 0.5, 0.55))
	env.fog_light_energy = config.get("fog_light_energy", 1.0)
	env.fog_density = config.get("fog_density", 0.01)
	env.fog_height = config.get("fog_height", 0.0)
	env.fog_height_density = config.get("fog_height_density", 0.0)

	# Tonemap
	env.tonemap_mode = config.get("tonemap_mode", Environment.TONE_MAPPER_FILMIC)
	env.tonemap_exposure = config.get("tonemap_exposure", 1.0)
	env.tonemap_white = config.get("tonemap_white", 1.0)

	# Glow
	env.glow_enabled = config.get("glow_enabled", false)
	env.glow_intensity = config.get("glow_intensity", 0.8)
	env.glow_strength = config.get("glow_strength", 1.0)
	env.glow_bloom = config.get("glow_bloom", 0.0)

	# SSAO
	env.ssao_enabled = config.get("ssao_enabled", false)
	env.ssao_intensity = config.get("ssao_intensity", 2.0)

	# SSR
	env.ssr_enabled = config.get("ssr_enabled", false)

	# SDFGI
	env.sdfgi_enabled = config.get("sdfgi_enabled", false)

	# Reflected light source
	env.reflected_light_source = config.get(
		"reflected_light_source", Environment.REFLECTION_SOURCE_BG
	)

	# Color adjustments
	env.adjustment_enabled = config.get("adjustment_enabled", false)
	env.adjustment_brightness = config.get("adjustment_brightness", 1.0)
	env.adjustment_contrast = config.get("adjustment_contrast", 1.0)
	env.adjustment_saturation = config.get("adjustment_saturation", 1.0)

	# Sky — create or assign Sky resource when background mode is BG_SKY
	var sky_preset_name: String = config.get("sky_preset", "")
	if env.background_mode == Environment.BG_SKY:
		if sky_preset_name == "map_default" and map_sky:
			env.sky = map_sky
		elif SKY_PRESETS.has(sky_preset_name):
			env.sky = create_sky_from_preset(sky_preset_name)
		elif not env.sky:
			# BG_SKY requested but no preset specified and no existing sky — use default
			env.sky = create_sky_from_preset("clear_day")
	else:
		# Not BG_SKY — clear any existing sky to free memory
		env.sky = null


## Extract all supported settings from an existing Environment resource into a
## config dictionary.  This is the inverse of _apply_config_to_environment() and
## uses the same key names as PROPERTY_DEFAULTS so the result can be used
## directly as overrides or compared against presets.
static func extract_from_environment(env: Environment) -> Dictionary:
	if not env:
		return {}
	var config = {
		"background_mode": env.background_mode,
		"background_color": env.background_color,
		"ambient_light_source": env.ambient_light_source,
		"ambient_light_color": env.ambient_light_color,
		"ambient_light_energy": env.ambient_light_energy,
		"fog_enabled": env.fog_enabled,
		"fog_light_color": env.fog_light_color,
		"fog_light_energy": env.fog_light_energy,
		"fog_density": env.fog_density,
		"fog_height": env.fog_height,
		"fog_height_density": env.fog_height_density,
		"tonemap_mode": env.tonemap_mode,
		"tonemap_exposure": env.tonemap_exposure,
		"tonemap_white": env.tonemap_white,
		"glow_enabled": env.glow_enabled,
		"glow_intensity": env.glow_intensity,
		"glow_strength": env.glow_strength,
		"glow_bloom": env.glow_bloom,
		"ssao_enabled": env.ssao_enabled,
		"ssao_intensity": env.ssao_intensity,
		"ssr_enabled": env.ssr_enabled,
		"sdfgi_enabled": env.sdfgi_enabled,
		"reflected_light_source": env.reflected_light_source,
		"adjustment_enabled": env.adjustment_enabled,
		"adjustment_brightness": env.adjustment_brightness,
		"adjustment_contrast": env.adjustment_contrast,
		"adjustment_saturation": env.adjustment_saturation,
	}
	# If the environment has a sky, mark it so the editor can offer "map_default"
	if env.sky:
		config["sky_preset"] = "map_default"
	else:
		config["sky_preset"] = ""
	return config


## Create a new Environment resource with the given configuration
static func create_environment(preset_name: String = "", overrides: Dictionary = {}) -> Environment:
	var config = get_environment_config(preset_name, overrides)
	var env = Environment.new()
	_apply_config_to_environment(env, config)
	return env


## Convert environment overrides to/from JSON-safe format
## Colors are stored as hex strings for readability
static func overrides_to_json(overrides: Dictionary) -> Dictionary:
	var json_safe = {}
	for key in overrides:
		var value = overrides[key]
		if value is Color:
			json_safe[key] = "#" + value.to_html(false)
		else:
			json_safe[key] = value
	return json_safe


static func overrides_from_json(json_data: Dictionary) -> Dictionary:
	var overrides = {}
	for key in json_data:
		var value = json_data[key]
		# Check if this is a color property and convert from hex
		if key.ends_with("_color") and value is String and value.begins_with("#"):
			overrides[key] = Color.from_string(value, Color.WHITE)
		else:
			overrides[key] = value
	return overrides
