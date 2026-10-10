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
## The new-map dialog's Start from tiles take a wide strip (strip()) instead of the square: the
## same landscape painted across the tile with the assets in its middle, cropped closer top
## and bottom so they stand taller, its corners rounded; Bare ground is that landscape with
## nothing on it (bare_strip()), its ground the bare surface's own.
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
## A strip keeps this band of the studio square's height (the assets span about 0.16-0.83 of
## it), so they stand taller in the strip than in the square.
const STRIP_BAND := Vector2(0.1, 0.88)
## A strip's corner radius, as a share of its height.
const STRIP_CORNER := 0.12
## The studio wall's grey: keyed out entirely and too light to shade the ground.
const STUDIO_GREY := Color(0.71, 0.71, 0.71)

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


## The picture of `biome` as a wide strip `size` px (wider than tall): the landscape across
## the whole strip, the assets in its middle, the corners rounded. A biome whose thumbnail
## cannot be read paints its ground alone.
static func strip(
	biome: Dictionary, size: Vector2i, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Texture2D:
	var id := String(biome.get("id", ""))
	var key := "%s:%s:%dx%d" % [root, id, size.x, size.y]
	if not _cache.has(key):
		var high := size * SUPERSAMPLE
		var side := int(round(float(high.y) / (STRIP_BAND.y - STRIP_BAND.x)))
		var square := _studio(root.path_join(String(biome.get("thumbnail", ""))), side)
		var studio: Image = null
		if square != null:
			var top := int(round(STRIP_BAND.x * side))
			studio = square.get_region(Rect2i(0, top, side, mini(high.y, side - top)))
		var ground := ground_colour(biome, root)
		_cache[key] = _strip_texture(studio, size, ground, MapPlaceholder.seed_of(id))
	return _cache[key]


## Plain ground with nothing on it as a strip `size` px (the new-map dialog's Bare ground): the
## same painted landscape, its ground `surface`'s own (a palette surface entry), lifted.
static func bare_strip(
	surface: Dictionary, size: Vector2i, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Texture2D:
	var albedo := String(surface.get("albedo", ""))
	var key := "%s:bare:%s:%dx%d" % [root, albedo, size.x, size.y]
	if not _cache.has(key):
		var ground := _luminous(_mean(root.path_join(albedo)))
		_cache[key] = _strip_texture(null, size, ground, MapPlaceholder.seed_of("bare_ground"))
	return _cache[key]


## The biome's ground as the picture paints it: the mean of its ground surface's albedo,
## lifted to GROUND_SATURATION and into the GROUND_LIGHTNESS band at the same hue.
static func ground_colour(biome: Dictionary, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(
		String(biome.get("ground_surface", "")), {}
	)
	return _luminous(_mean(root.path_join(String(surface.get("albedo", "")))))


## `mean` lifted to GROUND_SATURATION and into the GROUND_LIGHTNESS band at its own hue (moss
## when there is none).
static func _luminous(mean: Color) -> Color:
	if mean.a == 0.0:
		mean = ThemeColors.MOSS_LIGHT
	return Color.from_ok_hsl(
		mean.ok_hsl_h,
		maxf(mean.ok_hsl_s, GROUND_SATURATION),
		clampf(mean.ok_hsl_l, GROUND_LIGHTNESS.x, GROUND_LIGHTNESS.y)
	)


## Paints the landscape behind `studio` (a crop of the studio render) and keys the studio's
## grey out over it: sky, the far ridge whose skyline `seed` draws, then the ground from
## `ground` at the horizon's haze to a deeper foreground. The picture is `size` px (the
## studio's own size when zero) with the studio centred across it; with no studio, or beyond
## its sides, the landscape stands empty.
static func paint(studio: Image, ground: Color, seed: float, size := Vector2i.ZERO) -> Image:
	if size == Vector2i.ZERO:
		size = studio.get_size()
	var studio_size := studio.get_size() if studio != null else Vector2i.ZERO
	var studio_left := (size.x - studio_size.x) / 2
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var sky_top := ThemeColors.SKY_TOP
	var sky_low := ThemeColors.SKY_LOW
	var ridge := ground.lerp(sky_low, RIDGE_HAZE)
	var near := ground.lerp(sky_low, HORIZON_HAZE)
	var fore := Color.from_ok_hsl(
		ground.ok_hsl_h, ground.ok_hsl_s, ground.ok_hsl_l - FORE_DEEPEN
	)
	var phase := seed * TAU
	var edge := 1.0 / size.y
	for y in size.y:
		var v := (float(y) + 0.5) / size.y
		var sky := sky_top.lerp(sky_low, clampf(v / HORIZON, 0.0, 1.0))
		var land := near.lerp(fore, clampf((v - HORIZON) / (1.0 - HORIZON), 0.0, 1.0))
		var below := ridge.lerp(land, smoothstep(HORIZON - edge, HORIZON + edge, v))
		for x in size.x:
			# The skyline in heights across, so a wide strip rolls on rather than stretches.
			var u := (float(x) + 0.5) / size.y
			var rise := 0.55 + 0.45 * sin(u * 5.0 + phase) * cos(u * 2.3 - phase)
			var crest := HORIZON - RIDGE * rise
			var back := sky.lerp(below, smoothstep(crest - edge, crest + edge, v))
			var sx := x - studio_left
			var inside := sx >= 0 and sx < studio_size.x and y < studio_size.y
			var pixel := studio.get_pixel(sx, y) if inside else STUDIO_GREY
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


## A strip `size` px painted at SUPERSAMPLE over `studio` (a band of the studio square at that
## resolution, or null for empty ground), downsampled, its corners rounded.
static func _strip_texture(studio: Image, size: Vector2i, ground: Color, seed: float) -> Texture2D:
	var image := paint(studio, ground, seed, size * SUPERSAMPLE)
	image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var radius := STRIP_CORNER * size.y
	for y in size.y:
		for x in size.x:
			var dx := maxf(radius - (x + 0.5), (x + 0.5) - (size.x - radius))
			var dy := maxf(radius - (y + 0.5), (y + 0.5) - (size.y - radius))
			if dx <= 0.0 or dy <= 0.0:
				continue
			var outside := Vector2(dx, dy).length() - radius
			var pixel := image.get_pixel(x, y)
			pixel.a = clampf(0.5 - outside, 0.0, 1.0)
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)


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
