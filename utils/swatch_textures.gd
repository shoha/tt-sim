class_name SwatchTextures
extends RefCounted

## Small textures that show what a choice does: a sky preset's tile and preview
## (the shipped PNGs for HDRI skies, painted gradients otherwise) and a lighting
## preset's background colour over its ambient colour for the preset picker.
## Loaded or painted once per name and cached for the process; unknown names
## paint a neutral grey.

const SKY_SIZE := 24
const PREVIEW_WIDTH := 280
const PREVIEW_HEIGHT := 70
const SWATCH_SIZE := 16
const FALLBACK := Color(0.3, 0.3, 0.3)

static var _cache: Dictionary = {}


## 24x24 tile: the shipped tile PNG for an HDRI sky, else sky over ground bands.
static func sky_gradient(preset_name: String) -> Texture2D:
	return _sky_texture("sky:", preset_name, "tile", SKY_SIZE, SKY_SIZE, int(SKY_SIZE * 2 / 3))


## 280x70 preview strip: the shipped preview PNG for an HDRI sky, else painted.
static func sky_preview(preset_name: String) -> Texture2D:
	return _sky_texture(
		"preview:",
		preset_name,
		"preview",
		PREVIEW_WIDTH,
		PREVIEW_HEIGHT,
		int(PREVIEW_HEIGHT * 2 / 3)
	)


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


static func _sky_texture(
	prefix: String,
	preset_name: String,
	shipped_field: String,
	width: int,
	height: int,
	horizon: int
) -> Texture2D:
	var key := prefix + preset_name
	if _cache.has(key):
		return _cache[key]
	var sky: Dictionary = EnvironmentPresets.SKY_PRESETS.get(preset_name, {})
	var shipped: String = sky.get(shipped_field, "")
	var texture: Texture2D = null
	if not shipped.is_empty() and ResourceLoader.exists(shipped):
		texture = load(shipped) as Texture2D
	if texture == null:
		texture = _paint_bands(
			width,
			height,
			horizon,
			sky.get("sky_top_color", FALLBACK),
			sky.get("sky_horizon_color", FALLBACK),
			sky.get("ground_horizon_color", FALLBACK),
			sky.get("ground_bottom_color", FALLBACK)
		)
	_cache[key] = texture
	return texture


## Sky gradient down to horizon_row, ground gradient below it.
static func _paint_bands(
	width: int,
	height: int,
	horizon_row: int,
	top: Color,
	horizon: Color,
	ground_top: Color,
	ground_bottom: Color
) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		var color: Color
		if y < horizon_row:
			color = top.lerp(horizon, float(y) / float(horizon_row - 1))
		else:
			var t := float(y - horizon_row) / float(height - horizon_row - 1)
			color = ground_top.lerp(ground_bottom, t)
		for x in range(width):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
