class_name MasonryTextures
extends RefCounted

## The baked masonry texture set a textured wall wears (assets/textures/masonry/: albedo, normal
## and ORM, from plantgen's tools/bake_masonry_cli.gd): irregular courses of stones with joints
## and bevels, tileable, TILE_M wide and TILE_H_M high, in grey so the biome's rock colours it.
## The files are raw PNGs (importer "keep"), read as images and made into mipmapped textures once.

const FOLDER := "res://assets/textures/masonry/"
## One tile covers this much wall, metres (the UVs of a textured wall are metres).
const TILE_M := 6.0
const TILE_H_M := 1.2
## The mean sRGB tone of the albedo's stones, which a tint divides out to land on a target colour.
const MEAN_TONE := 0.6

static var _set: Dictionary = {}


## Whether the baked files are there (safe on any thread: textures() makes textures, which only the
## main thread does).
static func available() -> bool:
	return FileAccess.file_exists(FOLDER + "albedo.png")


## {"albedo", "normal", "orm"}: ImageTextures with mipmaps (empty when the files are missing).
static func textures() -> Dictionary:
	if not _set.is_empty():
		return _set
	for key in ["albedo", "normal", "orm"]:
		# A raw PNG in the pack (importer "keep"): read its bytes, as the library surfaces are.
		var image := Image.new()
		var bytes := FileAccess.get_file_as_bytes(FOLDER + key + ".png")
		if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
			return {}
		image.generate_mipmaps()
		_set[key] = ImageTexture.create_from_image(image)
	return _set


## The albedo colour that makes the grey tile read as `rock` (a palette surface's mean linear
## colour), by `lift`.
static func tint_of(mean_linear: Array, lift: Color = Color.WHITE) -> Color:
	var target := Color(float(mean_linear[0]), float(mean_linear[1]), float(mean_linear[2]))
	var srgb := target.linear_to_srgb()
	return Color(
		srgb.r / MEAN_TONE * lift.r, srgb.g / MEAN_TONE * lift.g, srgb.b / MEAN_TONE * lift.b
	)
