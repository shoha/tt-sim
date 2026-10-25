class_name AssetThumbnails
extends RefCounted

## The pictures of catalog assets (the catalog's `thumb`, a 256 px PNG beside the library) as
## textures for the designer's asset picker. Each file is decoded from its bytes through
## SurfaceStore.thumbnail_image (size-capped, never loaded as a resource), kept in a texture cache
## that holds at most CACHE_CAP pictures (least recently used leaves first), and a missing,
## oversized or undecodable file gives null so the caller falls back to its category icon. A
## failed file is remembered too, so a library with a broken picture is not re-read on every
## redraw. The transparent border of a render is trimmed (_trimmed) so the plant fills the tile.

const MAX_SIDE := 256
const CACHE_CAP := 512
const TRIM_MARGIN := 4

## file -> Texture2D (or null for a file that failed), oldest first: a hit moves its entry last.
static var _cache: Dictionary = {}
static var stats: Dictionary = {"decodes": 0, "hits": 0}
## The cache size (CACHE_CAP; a test lowers it).
static var cap: int = CACHE_CAP


## The texture of the absolute (or res://) `file`, or null when there is none to show.
static func texture(file: String) -> Texture2D:
	if file == "":
		return null
	if _cache.has(file):
		var kept: Variant = _cache[file]
		_cache.erase(file)
		_cache[file] = kept
		stats["hits"] = int(stats["hits"]) + 1
		return kept as Texture2D
	stats["decodes"] = int(stats["decodes"]) + 1
	var picture := SurfaceStore.thumbnail_image(file, MAX_SIDE)
	var made: Texture2D = null
	if picture != null:
		made = ImageTexture.create_from_image(_trimmed(picture))
	_cache[file] = made
	while _cache.size() > cap:
		_cache.erase(_cache.keys()[0])
	return made


## `picture` cropped to its visible pixels plus a margin: the renders leave a wide transparent
## border, which would shrink the plant to a speck on a small tile. A picture with no visible
## pixel is returned as it is.
static func _trimmed(picture: Image) -> Image:
	var used := picture.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return picture
	used = used.grow(TRIM_MARGIN).intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	return picture.get_region(used)


static func cached_count() -> int:
	return _cache.size()


static func clear() -> void:
	_cache.clear()
	cap = CACHE_CAP
	stats = {"decodes": 0, "hits": 0}
