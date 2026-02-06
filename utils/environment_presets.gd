extends RefCounted
class_name EnvironmentPresets

## Environment preset definitions and utilities for map lighting/mood.
## Presets define ambient light, fog, background, and post-processing settings.
## Map creators can select a preset and optionally override specific values.

## Available environment properties that can be configured
## These map to Godot's Environment resource properties
const PROPERTY_DEFAULTS = {
	# Background
	"background_mode": Environment.BG_COLOR, # BG_COLOR, BG_SKY, BG_CANVAS
	"background_color": Color(0.3, 0.3, 0.3),
	
	# Ambient light
	"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR, # AMBIENT_SOURCE_COLOR, AMBIENT_SOURCE_SKY
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
	"tonemap_mode": Environment.TONE_MAPPER_FILMIC, # TONE_MAPPER_LINEAR, TONE_MAPPER_REINHARDT, TONE_MAPPER_FILMIC, TONE_MAPPER_ACES
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
}


## Built-in environment presets
## Each preset overrides only the properties it needs to change from defaults
const PRESETS = {
	# ========== OUTDOOR PRESETS ==========
	
	"outdoor_day": {
		"description": "Bright outdoor daytime - clear sky, neutral lighting",
		"background_mode": Environment.BG_SKY,
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"ambient_light_color": Color(0.7, 0.75, 0.85),
		"ambient_light_energy": 0.6,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.0,
	},
	
	"outdoor_overcast": {
		"description": "Cloudy outdoor day - soft diffuse lighting",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.55, 0.58, 0.62),
		"ambient_light_color": Color(0.6, 0.62, 0.68),
		"ambient_light_energy": 0.7,
		"fog_enabled": true,
		"fog_light_color": Color(0.6, 0.62, 0.65),
		"fog_density": 0.002,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	},
	
	"outdoor_sunset": {
		"description": "Golden hour - warm orange/pink lighting",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.9, 0.5, 0.3),
		"ambient_light_color": Color(1.0, 0.7, 0.5),
		"ambient_light_energy": 0.5,
		"fog_enabled": true,
		"fog_light_color": Color(1.0, 0.6, 0.4),
		"fog_density": 0.003,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.5,
		"glow_bloom": 0.1,
	},
	
	"outdoor_night": {
		"description": "Moonlit night - cool blue tones, low visibility",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.03, 0.08),
		"ambient_light_color": Color(0.15, 0.18, 0.3),
		"ambient_light_energy": 0.25,
		"fog_enabled": true,
		"fog_light_color": Color(0.1, 0.12, 0.2),
		"fog_density": 0.008,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.8,
	},
	
	# ========== INDOOR/DUNGEON PRESETS ==========
	
	"indoor_neutral": {
		"description": "Standard indoor lighting - neutral, well-lit",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.15, 0.15),
		"ambient_light_color": Color(0.5, 0.48, 0.45),
		"ambient_light_energy": 0.4,
		"ssao_enabled": true,
		"ssao_intensity": 1.5,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	},
	
	"dungeon_dark": {
		"description": "Dark dungeon - minimal ambient, torch-lit atmosphere",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.02, 0.03),
		"ambient_light_color": Color(0.1, 0.08, 0.06),
		"ambient_light_energy": 0.15,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.04, 0.03),
		"fog_density": 0.02,
		"ssao_enabled": true,
		"ssao_intensity": 2.5,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 0.9,
	},
	
	"dungeon_crypt": {
		"description": "Eerie crypt - cold, deathly atmosphere",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.01, 0.02, 0.03),
		"ambient_light_color": Color(0.08, 0.1, 0.15),
		"ambient_light_energy": 0.2,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.08, 0.12),
		"fog_density": 0.025,
		"fog_height_density": 0.5,
		"ssao_enabled": true,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.3,
	},
	
	"cave": {
		"description": "Natural cave - damp, earthy tones",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.02, 0.02),
		"ambient_light_color": Color(0.12, 0.1, 0.08),
		"ambient_light_energy": 0.2,
		"fog_enabled": true,
		"fog_light_color": Color(0.08, 0.06, 0.05),
		"fog_density": 0.015,
		"ssao_enabled": true,
		"ssao_intensity": 2.0,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	},
	
	# ========== SPECIAL ATMOSPHERE PRESETS ==========
	
	"tavern": {
		"description": "Cozy tavern - warm firelit interior",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.08, 0.05, 0.03),
		"ambient_light_color": Color(0.8, 0.5, 0.3),
		"ambient_light_energy": 0.35,
		"fog_enabled": true,
		"fog_light_color": Color(0.3, 0.2, 0.1),
		"fog_density": 0.008,
		"ssao_enabled": true,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.4,
		"glow_bloom": 0.05,
	},
	
	"forest": {
		"description": "Dense forest - dappled green light",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.1, 0.15, 0.08),
		"ambient_light_color": Color(0.3, 0.45, 0.25),
		"ambient_light_energy": 0.45,
		"fog_enabled": true,
		"fog_light_color": Color(0.2, 0.3, 0.15),
		"fog_density": 0.006,
		"ssao_enabled": true,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	},
	
	"swamp": {
		"description": "Murky swamp - thick fog, sickly green",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.08, 0.1, 0.05),
		"ambient_light_color": Color(0.25, 0.3, 0.15),
		"ambient_light_energy": 0.35,
		"fog_enabled": true,
		"fog_light_color": Color(0.15, 0.2, 0.1),
		"fog_density": 0.04,
		"fog_height": -2.0,
		"fog_height_density": 1.0,
		"ssao_enabled": true,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
	},
	
	"underwater": {
		"description": "Underwater - blue-green murky depths",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.02, 0.08, 0.12),
		"ambient_light_color": Color(0.1, 0.25, 0.35),
		"ambient_light_energy": 0.4,
		"fog_enabled": true,
		"fog_light_color": Color(0.05, 0.15, 0.25),
		"fog_density": 0.05,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.3,
	},
	
	"hell": {
		"description": "Infernal realm - fiery red/orange glow",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.02, 0.0),
		"ambient_light_color": Color(0.6, 0.15, 0.05),
		"ambient_light_energy": 0.4,
		"fog_enabled": true,
		"fog_light_color": Color(0.4, 0.1, 0.0),
		"fog_density": 0.02,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.6,
		"glow_bloom": 0.15,
	},
	
	"ethereal": {
		"description": "Ethereal/fey realm - soft magical glow",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.1, 0.2),
		"ambient_light_color": Color(0.5, 0.4, 0.7),
		"ambient_light_energy": 0.5,
		"fog_enabled": true,
		"fog_light_color": Color(0.3, 0.25, 0.5),
		"fog_density": 0.01,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"glow_enabled": true,
		"glow_intensity": 0.7,
		"glow_bloom": 0.2,
	},
	
	"arctic": {
		"description": "Frozen tundra - cold blue-white",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.7, 0.75, 0.85),
		"ambient_light_color": Color(0.6, 0.7, 0.85),
		"ambient_light_energy": 0.6,
		"fog_enabled": true,
		"fog_light_color": Color(0.8, 0.85, 0.95),
		"fog_density": 0.008,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.1,
	},
	
	"desert": {
		"description": "Harsh desert - bright, warm, hazy",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.85, 0.75, 0.6),
		"ambient_light_color": Color(0.9, 0.8, 0.65),
		"ambient_light_energy": 0.65,
		"fog_enabled": true,
		"fog_light_color": Color(0.9, 0.8, 0.6),
		"fog_density": 0.004,
		"tonemap_mode": Environment.TONE_MAPPER_FILMIC,
		"tonemap_exposure": 1.2,
	},
	
	# ========== UTILITY PRESETS ==========
	
	"none": {
		"description": "No environment effects - use map's embedded lighting only",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.2, 0.2, 0.2),
		"ambient_light_color": Color(0.3, 0.3, 0.3),
		"ambient_light_energy": 0.3,
	},
	
	"bright_editor": {
		"description": "Bright editing mode - maximum visibility",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.4, 0.4, 0.45),
		"ambient_light_color": Color(0.8, 0.8, 0.85),
		"ambient_light_energy": 0.8,
		"tonemap_mode": Environment.TONE_MAPPER_LINEAR,
	},
}


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


## Get a complete environment configuration by merging:
## 1. Property defaults
## 2. Preset values (if specified)
## 3. Override values (if specified)
static func get_environment_config(preset_name: String = "", overrides: Dictionary = {}) -> Dictionary:
	var config = PROPERTY_DEFAULTS.duplicate()
	
	# Apply preset if specified
	if preset_name != "" and PRESETS.has(preset_name):
		var preset = PRESETS[preset_name]
		for key in preset:
			if key != "description":
				config[key] = preset[key]
	
	# Apply overrides
	for key in overrides:
		if config.has(key):
			config[key] = overrides[key]
	
	return config


## Apply environment configuration to a WorldEnvironment node
## Creates the Environment resource if needed
static func apply_to_world_environment(world_env: WorldEnvironment, preset_name: String = "", overrides: Dictionary = {}) -> void:
	var config = get_environment_config(preset_name, overrides)
	
	# Create or get environment
	var env = world_env.environment
	if not env:
		env = Environment.new()
		world_env.environment = env
	
	# Apply all settings
	_apply_config_to_environment(env, config)


## Apply configuration to an Environment resource
static func _apply_config_to_environment(env: Environment, config: Dictionary) -> void:
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
