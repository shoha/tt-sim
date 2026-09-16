class_name SwatchTextures
extends RefCounted

## Small painted textures that show what a choice does: a sky preset's
## gradient for the Sky tiles, and a lighting preset's background colour over
## its ambient colour for the preset picker. Generated once per name and
## cached for the process; unknown names paint a neutral grey.

const SKY_SIZE := 24
const SWATCH_SIZE := 16
const FALLBACK := Color(0.3, 0.3, 0.3)

static var _cache: Dictionary = {}


static func sky_gradient(preset_name: String) -> ImageTexture:
	var key := "sky:" + preset_name
	if _cache.has(key):
		return _cache[key]
	var sky: Dictionary = EnvironmentPresets.SKY_PRESETS.get(preset_name, {})
	var top: Color = sky.get("sky_top_color", FALLBACK)
	var horizon: Color = sky.get("sky_horizon_color", FALLBACK)
	var ground_top: Color = sky.get("ground_horizon_color", FALLBACK)
	var ground_bottom: Color = sky.get("ground_bottom_color", FALLBACK)
	var image := Image.create(SKY_SIZE, SKY_SIZE, false, Image.FORMAT_RGBA8)
	var horizon_row := int(SKY_SIZE * 2 / 3)
	for y in range(SKY_SIZE):
		var color: Color
		if y < horizon_row:
			color = top.lerp(horizon, float(y) / float(horizon_row - 1))
		else:
			var t := float(y - horizon_row) / float(SKY_SIZE - horizon_row - 1)
			color = ground_top.lerp(ground_bottom, t)
		for x in range(SKY_SIZE):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func preset_swatch(preset_name: String) -> ImageTexture:
	var key := "preset:" + preset_name
	if _cache.has(key):
		return _cache[key]
	var lookup := preset_name if EnvironmentPresets.PRESETS.has(preset_name) else ""
	var config := EnvironmentPresets.get_environment_config(lookup, {}, {})
	var background: Color = config.get("background_color", FALLBACK)
	var ambient: Color = config.get("ambient_light_color", FALLBACK)
	var image := Image.create(SWATCH_SIZE, SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	var split := SWATCH_SIZE / 2
	for y in range(SWATCH_SIZE):
		var color := background if y < split else ambient
		for x in range(SWATCH_SIZE):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
