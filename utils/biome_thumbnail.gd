class_name BiomeThumbnail
extends RefCounted

## A starting biome's picture for its tile (the new-map dialog's Start from, the authoring
## drawer's Biome pane and its Place foldouts). The palette's thumbnail is the biome's assets
## rendered on a grey studio floor against a grey wall (treecube's build_palette.py), and at
## tile size that read as a grey square (193, 194, 193) with a few specks, not a place. This
## keys the studio grey out and stands the assets in a small painted landscape instead: the
## morning sky of the title backdrop (ThemeColors.SKY_TOP to SKY_LOW), a far ridge in haze
## whose skyline the biome's id draws (as MapPlaceholder draws a map's from its folder), and
## the biome's own ground (its ground surface's albedo, lifted luminous: sap-green grass,
## golden savanna, terracotta badlands), with the assets' contact shadows kept as shade on
## that ground. The crop is tightened to the assets so they read at 52 px.
##
## Built once per biome and size on the CPU (about 16k pixels at 64 px) and cached.

## The square of the studio render the assets stand in: in every palette thumbnail they span
## about 0.24-0.76 across and 0.34-0.73 down. Origin and side as fractions of the render.
const CROP_ORIGIN := Vector2(0.21, 0.25)
const CROP_SIDE := 0.58
## The working resolution as a multiple of the tile's: keying above the final size keeps the
## leaves' edges clean once it is downsampled.
const SUPERSAMPLE := 2
## Chroma (the largest channel less the smallest) under KEY_LOW is studio grey, over KEY_HIGH
## an asset; between, a soft edge.
const KEY_LOW := 0.05
const KEY_HIGH := 0.13
## Dark pixels are assets whatever their chroma (a trunk's shadow side): fully from the first
## luma, not at all from the second.
const DARK_LUMA := Vector2(0.28, 0.42)
## Studio grey darker than the wall (luma 0.71) is a contact shadow: it shades the painted
## ground in proportion, never below SHADE_MIN.
const SHADE_FROM := 0.68
const SHADE_MIN := 0.55
## The painted horizon from the top, and the far ridge's greatest height above it.
const HORIZON := 0.46
const RIDGE := 0.1
## The ground's least OKHSL saturation and its lightness band: a forest floor's dull tan and
## a dark grass both lift into a luminous ground (the painterly verdict: never grey or muddy).
const GROUND_SATURATION := 0.5
const GROUND_LIGHTNESS := Vector2(0.6, 0.7)
## How far the far ridge and the ground at the horizon fade into the low sky's haze, and how
## much deeper the foreground is than the ground at the horizon.
const RIDGE_HAZE := 0.55
const HORIZON_HAZE := 0.3
const FORE_DEEPEN := 0.1

static var _cache := {}


## The painted picture of `biome` (a palette biome entry with its "id", "thumbnail" and
## "ground_surface") at `size` px square. A biome whose thumbnail cannot be read falls back
## to the plain palette thumbnail.
static func of(
	biome: Dictionary, size: int, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Texture2D:
	var id := String(biome.get("id", ""))
	var key := "%s:%s:%d" % [root, id, size]
	if _cache.has(key):
		return _cache[key]
	var thumbnail := String(biome.get("thumbnail", ""))
	var studio := _studio(root.path_join(thumbnail), size * SUPERSAMPLE)
	if studio == null:
		return SwatchTextures.palette_thumbnail(thumbnail, size, root)
	var image := paint(studio, ground_colour(biome, root), MapPlaceholder.seed_of(id))
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## The biome's ground as the picture paints it: the mean of its ground surface's albedo,
## lifted to GROUND_SATURATION and into the GROUND_LIGHTNESS band at the same hue.
static func ground_colour(biome: Dictionary, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(
		String(biome.get("ground_surface", "")), {}
	)
	var mean := _mean(root.path_join(String(surface.get("albedo", ""))))
	if mean.a == 0.0:
		mean = ThemeColors.MOSS_LIGHT
	return Color.from_ok_hsl(
		mean.ok_hsl_h,
		maxf(mean.ok_hsl_s, GROUND_SATURATION),
		clampf(mean.ok_hsl_l, GROUND_LIGHTNESS.x, GROUND_LIGHTNESS.y)
	)


## Paints the landscape behind `studio` (a square crop of the studio render) and keys the
## studio's grey out over it: sky, the far ridge whose skyline `seed` draws, then the ground
## from `ground` at the horizon's haze to a deeper foreground.
static func paint(studio: Image, ground: Color, seed: float) -> Image:
	var side := studio.get_width()
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var sky_top := ThemeColors.SKY_TOP
	var sky_low := ThemeColors.SKY_LOW
	var ridge := ground.lerp(sky_low, RIDGE_HAZE)
	var near := ground.lerp(sky_low, HORIZON_HAZE)
	var fore := Color.from_ok_hsl(
		ground.ok_hsl_h, ground.ok_hsl_s, ground.ok_hsl_l - FORE_DEEPEN
	)
	var phase := seed * TAU
	var edge := 1.0 / side
	for y in side:
		var v := (float(y) + 0.5) / side
		var sky := sky_top.lerp(sky_low, clampf(v / HORIZON, 0.0, 1.0))
		var land := near.lerp(fore, clampf((v - HORIZON) / (1.0 - HORIZON), 0.0, 1.0))
		var below := ridge.lerp(land, smoothstep(HORIZON - edge, HORIZON + edge, v))
		for x in side:
			var u := (float(x) + 0.5) / side
			var rise := 0.55 + 0.45 * sin(u * 5.0 + phase) * cos(u * 2.3 - phase)
			var crest := HORIZON - RIDGE * rise
			var back := sky.lerp(below, smoothstep(crest - edge, crest + edge, v))
			var pixel := studio.get_pixel(x, y)
			var high := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var chroma := high - minf(pixel.r, minf(pixel.g, pixel.b))
			var luma := pixel.get_luminance()
			var asset := maxf(
				smoothstep(KEY_LOW, KEY_HIGH, chroma),
				1.0 - smoothstep(DARK_LUMA.x, DARK_LUMA.y, luma)
			)
			if v > crest:
				var shade := clampf(luma / SHADE_FROM, SHADE_MIN, 1.0)
				back = Color(back.r * shade, back.g * shade, back.b * shade)
			out.set_pixel(x, y, Color(back.lerp(pixel, asset), 1.0))
	return out


## The square of the studio render at `path` the assets stand in, `side` px, or null.
static func _studio(path: String, side: int) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null:
		return null
	var image := source.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	var full := float(mini(image.get_width(), image.get_height()))
	var origin := Vector2i((CROP_ORIGIN * full).round())
	var crop := int(round(CROP_SIDE * full))
	image = image.get_region(Rect2i(origin, Vector2i(crop, crop)))
	image.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return image


## The mean colour of the texture at `path` (alpha 0 when there is none).
static func _mean(path: String) -> Color:
	if not ResourceLoader.exists(path):
		return Color(0, 0, 0, 0)
	var source := load(path) as Texture2D
	var image: Image = source.get_image() if source != null else null
	if image == null or image.is_empty():
		return Color(0, 0, 0, 0)
	if image.is_compressed():
		image.decompress()
	image.resize(8, 8, Image.INTERPOLATE_LANCZOS)
	var sum := Vector3.ZERO
	for y in 8:
		for x in 8:
			var pixel := image.get_pixel(x, y)
			sum += Vector3(pixel.r, pixel.g, pixel.b)
	sum /= 64.0
	return Color(sum.x, sum.y, sum.z)
