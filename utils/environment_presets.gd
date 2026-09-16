class_name EnvironmentPresets
extends RefCounted

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
	"ambient_light_energy": 0.55,
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
	"glow_enabled": true,
	"glow_intensity": 0.3,
	"glow_strength": 1.0,
	"glow_bloom": 0.05,
	# Reflected light (relevant when using a Sky)
	"reflected_light_source": Environment.REFLECTION_SOURCE_BG,
	# Color Adjustments
	"adjustment_enabled": false,
	"adjustment_brightness": 1.0,
	"adjustment_contrast": 1.0,
	"adjustment_saturation": 1.0,
}

## Sky presets. Every entry carries a procedural gradient (used as the fallback when
## a panorama cannot load, and by headless tests). HDRI entries add:
##   panorama         res:// path of the 1024x512 EXR (VRAM compressed on import)
##   tile / preview   PNGs painted by tools/curate_skies.gd for the Sky pane
##   sun_azimuth_deg  brightest column above the horizon, panorama frame
##   energy           PanoramaSkyMaterial.energy_multiplier (exposure normalised)
## Add a sky by adding a manifest entry, running tools/curate_skies.gd, and pasting
## the printed entry here plus a tile in SkyPane.SKY_TILES.
const SKY_PRESETS = {
	"clear_day":
	{
		"description": "Clear midday sky, cool fill, hard shadows",
		"sky_top_color": Color(0.38, 0.45, 0.75),
		"sky_horizon_color": Color(0.65, 0.72, 0.83),
		"ground_bottom_color": Color(0.2, 0.17, 0.13),
		"ground_horizon_color": Color(0.65, 0.67, 0.67),
		"panorama": "res://assets/skies/clear_day.exr",
		"tile": "res://assets/skies/clear_day_tile.png",
		"preview": "res://assets/skies/clear_day_preview.png",
		"sun_azimuth_deg": 179.3,
		"energy": 0.754,
	},
	"cloudy":
	{
		"description": "Bright day with scattered clouds, soft fill",
		"sky_top_color": Color(0.42, 0.52, 0.78),
		"sky_horizon_color": Color(0.72, 0.76, 0.84),
		"ground_bottom_color": Color(0.2, 0.18, 0.14),
		"ground_horizon_color": Color(0.62, 0.64, 0.64),
		"panorama": "res://assets/skies/cloudy.exr",
		"tile": "res://assets/skies/cloudy_tile.png",
		"preview": "res://assets/skies/cloudy_preview.png",
		"sun_azimuth_deg": 180.0,
		"energy": 0.472,
	},
	"overcast":
	{
		"description": "Flat grey overcast, shadowless and even",
		"sky_top_color": Color(0.45, 0.47, 0.52),
		"sky_horizon_color": Color(0.58, 0.6, 0.63),
		"ground_bottom_color": Color(0.25, 0.25, 0.25),
		"ground_horizon_color": Color(0.5, 0.52, 0.55),
		"panorama": "res://assets/skies/overcast.exr",
		"tile": "res://assets/skies/overcast_tile.png",
		"preview": "res://assets/skies/overcast_preview.png",
		"sun_azimuth_deg": 180.7,
		"energy": 0.739,
	},
	"morning":
	{
		"description": "Cool clear dawn, low pale sun",
		"sky_top_color": Color(0.35, 0.42, 0.62),
		"sky_horizon_color": Color(0.85, 0.78, 0.7),
		"ground_bottom_color": Color(0.16, 0.14, 0.12),
		"ground_horizon_color": Color(0.55, 0.52, 0.5),
		"panorama": "res://assets/skies/morning.exr",
		"tile": "res://assets/skies/morning_tile.png",
		"preview": "res://assets/skies/morning_preview.png",
		"sun_azimuth_deg": 170.9,
		"energy": 1.077,
	},
	"sunset":
	{
		"description": "Orange sunset with lit clouds, warm fill",
		"sky_top_color": Color(0.15, 0.15, 0.45),
		"sky_horizon_color": Color(1.0, 0.55, 0.25),
		"ground_bottom_color": Color(0.1, 0.05, 0.02),
		"ground_horizon_color": Color(0.85, 0.45, 0.2),
		"panorama": "res://assets/skies/sunset.exr",
		"tile": "res://assets/skies/sunset_tile.png",
		"preview": "res://assets/skies/sunset_preview.png",
		"sun_azimuth_deg": 270.7,
		"energy": 0.82,
	},
	"dusk":
	{
		"description": "Blue dusk after sunset, faint warm horizon",
		"sky_top_color": Color(0.08, 0.1, 0.28),
		"sky_horizon_color": Color(0.45, 0.35, 0.4),
		"ground_bottom_color": Color(0.04, 0.03, 0.04),
		"ground_horizon_color": Color(0.25, 0.2, 0.22),
		"panorama": "res://assets/skies/dusk.exr",
		"tile": "res://assets/skies/dusk_tile.png",
		"preview": "res://assets/skies/dusk_preview.png",
		"sun_azimuth_deg": 189.1,
		"energy": 0.904,
	},
	"storm":
	{
		"description": "Dark thunderstorm sky, dim and dramatic",
		"sky_top_color": Color(0.18, 0.2, 0.25),
		"sky_horizon_color": Color(0.35, 0.36, 0.4),
		"ground_bottom_color": Color(0.1, 0.1, 0.1),
		"ground_horizon_color": Color(0.28, 0.28, 0.3),
		"panorama": "res://assets/skies/storm.exr",
		"tile": "res://assets/skies/storm_tile.png",
		"preview": "res://assets/skies/storm_preview.png",
		"sun_azimuth_deg": 61.5,
		"energy": 0.713,
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

## Engine convention between the panorama's brightest column and the yaw
## Environment.sky_rotation needs so that column faces the sun. Godot samples an
## equirectangular panorama mirrored relative to the sun azimuth convention
## (panorama column c lands at world azimuth 180 - c when unrotated), so the sky's
## own azimuth is ADDED to the sun's and this half turn closes the gap. Calibrated
## in the live check on 2026-09-16 (clear_day, sun at 143 and 323 degrees): with
## the sun off, the boulder's sky-lit side matched the direct sun only under this
## rule. See docs/lighting-and-environment.md, "Sky follows the sun".
const SKY_YAW_OFFSET_DEG := 180.0

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
	},
	# ========== INDOOR/DUNGEON PRESETS ==========
	"indoor_neutral":
	{
		"description": "Standard indoor lighting - neutral, well-lit",
		"background_mode": Environment.BG_COLOR,
		"background_color": Color(0.15, 0.15, 0.15),
		"ambient_light_color": Color(0.5, 0.48, 0.45),
		"ambient_light_energy": 0.4,
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

## Picker grouping in display order. Every key in PRESETS appears exactly
## once (tests/unit/test_environment_presets_groups.gd enforces it).
const PRESET_GROUPS := {
	"Outdoor": ["outdoor_day", "outdoor_overcast", "outdoor_sunset", "outdoor_night"],
	"Indoor": ["indoor_neutral", "dungeon_dark", "dungeon_crypt", "cave", "tavern"],
	"Fantasy": ["forest", "swamp", "underwater", "hell", "ethereal", "arctic", "desert"],
	"Other": ["none", "bright_editor"],
}

## One Sky per preset name, built on first use. Assigning a Sky to an Environment
## re-bakes its radiance cubemap, so callers that apply the environment repeatedly
## (every slider tick in the Visuals drawer) must reuse the same instance.
static var _sky_cache: Dictionary = {}

## Panorama paths already warned about (missing/unloadable), so
## create_sky_from_config() warns once per path instead of once per call.
static var _warned_panoramas: Dictionary = {}


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


## Create a Sky resource for a sky preset: a PanoramaSkyMaterial when the entry
## ships a panorama, else the entry's procedural gradient. Null for unknown names.
static func create_sky_from_preset(preset_name: String) -> Sky:
	if not SKY_PRESETS.has(preset_name):
		return null
	return create_sky_from_config(SKY_PRESETS[preset_name])


## Build a Sky from one SKY_PRESETS-shaped entry. A panorama that cannot be loaded
## (missing file, headless import not run) falls back to the gradient colours and
## warns once per path so a broken asset is visible without spamming.
static func create_sky_from_config(config: Dictionary) -> Sky:
	var sky := Sky.new()
	var panorama_path: String = config.get("panorama", "")
	if not panorama_path.is_empty():
		var texture: Texture2D = null
		if ResourceLoader.exists(panorama_path):
			texture = load(panorama_path) as Texture2D
		if texture:
			var panorama := PanoramaSkyMaterial.new()
			panorama.panorama = texture
			panorama.energy_multiplier = float(config.get("energy", 1.0))
			sky.sky_material = panorama
			return sky
		if not _warned_panoramas.has(panorama_path):
			_warned_panoramas[panorama_path] = true
			push_warning(
				"EnvironmentPresets: sky panorama missing, using gradient: " + panorama_path
			)
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = config.get("sky_top_color", Color(0.38, 0.45, 0.75))
	material.sky_horizon_color = config.get("sky_horizon_color", Color(0.65, 0.72, 0.83))
	material.ground_bottom_color = config.get("ground_bottom_color", Color(0.2, 0.17, 0.13))
	material.ground_horizon_color = config.get("ground_horizon_color", Color(0.65, 0.67, 0.67))
	sky.sky_material = material
	return sky


static func is_hdri_sky(preset_name: String) -> bool:
	return SKY_PRESETS.has(preset_name) and SKY_PRESETS[preset_name].has("panorama")


## The sun's azimuth inside the panorama (degrees), 0.0 for anything else.
static func get_sky_sun_azimuth(preset_name: String) -> float:
	if not is_hdri_sky(preset_name):
		return 0.0
	return float(SKY_PRESETS[preset_name].get("sun_azimuth_deg", 0.0))


## Environment.sky_rotation that turns an HDRI sky's brightest column to the sun's
## azimuth. Gradients, "", and "map_default" never rotate.
static func sky_rotation_for(sun_azimuth_deg: float, sky_key: String) -> Vector3:
	if not is_hdri_sky(sky_key):
		return Vector3.ZERO
	var yaw := wrapf(
		sun_azimuth_deg + get_sky_sun_azimuth(sky_key) + SKY_YAW_OFFSET_DEG, 0.0, 360.0
	)
	return Vector3(0.0, deg_to_rad(yaw), 0.0)


## Cached Sky for a sky preset, or null for an unknown name.
static func get_sky_for_preset(preset_name: String) -> Sky:
	if _sky_cache.has(preset_name):
		return _sky_cache[preset_name]
	var sky := create_sky_from_preset(preset_name)
	if sky:
		_sky_cache[preset_name] = sky
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


static func get_preset_group(preset_name: String) -> String:
	for group in PRESET_GROUPS:
		if PRESET_GROUPS[group].has(preset_name):
			return group
	return "Other"


## Readable picker label: "" is the map's own lighting, otherwise the key with
## underscores replaced and words capitalised ("outdoor_day" -> "Outdoor Day").
static func display_name(preset_name: String) -> String:
	if preset_name.is_empty():
		return "Map defaults"
	return preset_name.replace("_", " ").capitalize()


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

	# Reflected light source
	env.reflected_light_source = config.get(
		"reflected_light_source", Environment.REFLECTION_SOURCE_BG
	)

	# Color adjustments
	env.adjustment_enabled = config.get("adjustment_enabled", false)
	env.adjustment_brightness = config.get("adjustment_brightness", 1.0)
	env.adjustment_contrast = config.get("adjustment_contrast", 1.0)
	env.adjustment_saturation = config.get("adjustment_saturation", 1.0)

	# Sky -- assign only when it actually changes: setting Environment.sky, even to an
	# equivalent resource, re-bakes the radiance cubemap.
	var sky_preset_name: String = config.get("sky_preset", "")
	if env.background_mode == Environment.BG_SKY:
		var target_sky: Sky = null
		if sky_preset_name == "map_default" and map_sky:
			target_sky = map_sky
		elif SKY_PRESETS.has(sky_preset_name):
			target_sky = get_sky_for_preset(sky_preset_name)
		elif not env.sky:
			# BG_SKY requested but no preset specified and no existing sky -- use default
			target_sky = get_sky_for_preset("clear_day")
		if target_sky and env.sky != target_sky:
			env.sky = target_sky
	else:
		# Not BG_SKY — clear any existing sky to free memory
		env.sky = null

	# Cross-validate: sky-sourced ambient light requires an actual sky. A config can
	# set ambient_light_source to AMBIENT_SOURCE_SKY independently of background_mode
	# (e.g. a partial override), which would otherwise silently zero out ambient light
	# once env.sky is nulled above. Fall back to the color source in that case.
	if env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and not env.sky:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR


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
		if key.ends_with("_color"):
			if value is String and value.begins_with("#"):
				overrides[key] = Color.from_string(value, Color.WHITE)
			elif value is Dictionary:
				overrides[key] = SerializationUtils.dict_to_color(value)
			else:
				overrides[key] = value
		else:
			overrides[key] = value
	return overrides
