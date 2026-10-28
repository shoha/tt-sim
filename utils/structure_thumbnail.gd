class_name StructureThumbnail
extends RefCounted

## A structure's picture for its palette tile (StructureToolPane): the library's rendered tile
## (`thumbnails/structures/<id>.jpg`, a row's `thumb` as an absolute path), read once per file
## and size and cached. A structure with no readable tile gets a plain paper square, so a tile
## is never a hole.

## The rendered tiles are wider than tall: the middle is kept, cut to a square.
static var _cache := {}


## The picture of palette row `row` (LibraryStructureStore.structure) at `size` px square.
static func of(row: Dictionary, size: int) -> Texture2D:
	var path := String(row.get("thumb", ""))
	var key := "%s:%d" % [path, size]
	if _cache.has(key):
		return _cache[key]
	var image: Image = null
	if path != "" and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		image = Image.new()
		var error := image.load_jpg_from_buffer(bytes)
		if error != OK:
			error = image.load_png_from_buffer(bytes)
		if error != OK or image.is_empty():
			image = null
	if image == null:
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_rgba8(199, 189, 168))
	else:
		var side := mini(image.get_width(), image.get_height())
		var offset := Vector2i(image.get_width() - side, image.get_height() - side) / 2
		image = image.get_region(Rect2i(offset, Vector2i(side, side)))
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
