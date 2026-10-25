class_name GlbGuard
extends RefCounted

## The look at a library GLB before GLTFDocument decodes anything (design doc 5.5 step 5): the
## container is well formed, nothing points outside the file, and every embedded texture is
## small enough, judged from the image headers alone. A hostile or careless library could
## otherwise hand GLTFDocument a 20000 x 20000 PNG and ask the engine to allocate it.
##
## Pure statics over the file's bytes: no files, no engine decode. What it checks:
## - the 12-byte header (magic `glTF`, version 2, a length no longer than the file), a JSON
##   chunk first, at most one BIN chunk after it, every chunk inside the file;
## - no buffer and no image carries a `uri` (a library GLB is self-contained: an external or
##   data URI is refused, so nothing is fetched from a path the library names);
## - at most LibraryContracts.MAX_GLB_IMAGES images, each in a bufferView inside the BIN chunk,
##   PNG or JPEG, its width and height (read from the header) within
##   LibraryContracts.MAX_GLB_TEXTURE_PX, the total pixels within MAX_TOTAL_PIXELS.

const MAGIC := 0x46546C67
const CHUNK_JSON := 0x4E4F534A
const CHUNK_BIN := 0x004E4942
## A glTF JSON chunk (nodes, accessors, materials) is text; 16 MiB is far above any asset.
const MAX_JSON_BYTES := 16 * 1024 * 1024
## The sum of every image's pixels: 64 images of 4096 px would be 1 GiB decoded.
const MAX_TOTAL_PIXELS := 4096 * 4096 * 2
## How much of an image the size is read from (a JPEG's frame header can follow a profile).
const HEAD_BYTES := 65536


## {ok, error, images: Array[Vector2i] (each image's size), json: Dictionary (the parsed JSON
## chunk, {} on failure)} for the bytes of a .glb.
static func inspect(buffer: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "error": "", "images": [] as Array[Vector2i], "json": {}}
	var size := buffer.size()
	if size < 20:
		out["error"] = "not a GLB (too short)"
		return out
	if buffer.decode_u32(0) != MAGIC or buffer.decode_u32(4) != 2:
		out["error"] = "not a version 2 GLB"
		return out
	var declared := buffer.decode_u32(8)
	if declared > size:
		out["error"] = "GLB header claims %d bytes, the file has %d" % [declared, size]
		return out
	var json_length := buffer.decode_u32(12)
	if buffer.decode_u32(16) != CHUNK_JSON or json_length > MAX_JSON_BYTES or 20 + json_length > size:
		out["error"] = "GLB has no usable JSON chunk"
		return out
	var json := JSON.new()
	var text := buffer.slice(20, 20 + json_length).get_string_from_utf8()
	if json.parse(text) != OK or not json.data is Dictionary:
		out["error"] = "GLB JSON chunk does not parse"
		return out
	var bin := _bin_chunk(buffer, 20 + json_length, size)
	if bin.has("error"):
		out["error"] = String(bin["error"])
		return out
	out["json"] = json.data
	var problem := _check_document(json.data, buffer, bin, out["images"])
	out["error"] = problem
	out["ok"] = problem == ""
	return out


## The BIN chunk after the JSON one as {start, length} (length 0 when there is none), or
## {"error": text}.
static func _bin_chunk(buffer: PackedByteArray, at: int, size: int) -> Dictionary:
	if at + 8 > size:
		return {"start": at, "length": 0}
	var length := buffer.decode_u32(at)
	if buffer.decode_u32(at + 4) != CHUNK_BIN:
		return {"start": at, "length": 0}
	if at + 8 + length > size:
		return {"error": "GLB BIN chunk runs past the end of the file"}
	return {"start": at + 8, "length": length}


static func _check_document(
	doc: Dictionary, buffer: PackedByteArray, bin: Dictionary, sizes: Array[Vector2i]
) -> String:
	var buffers: Variant = doc.get("buffers", [])
	if buffers is Array:
		for entry: Variant in buffers as Array:
			if entry is Dictionary and (entry as Dictionary).has("uri"):
				return "a buffer names a uri (a library GLB must be self-contained)"
	var images: Variant = doc.get("images", [])
	if not images is Array:
		return "images is not a list"
	if (images as Array).size() > LibraryContracts.MAX_GLB_IMAGES:
		var cap := LibraryContracts.MAX_GLB_IMAGES
		return "GLB embeds %d images, over %d" % [(images as Array).size(), cap]
	var views: Variant = doc.get("bufferViews", [])
	var total := 0
	for raw: Variant in images as Array:
		if not raw is Dictionary or (raw as Dictionary).has("uri"):
			return "an image names a uri (a library GLB must embed its textures)"
		var index: Variant = (raw as Dictionary).get("bufferView")
		if not index is float and not index is int:
			return "an image has no bufferView"
		var found := _view_bytes(views, int(index), buffer, bin)
		if found.is_empty():
			return "an image's bufferView lies outside the file"
		var head_end: int = found["start"] + mini(found["length"], HEAD_BYTES)
		var dims := image_size(buffer.slice(found["start"], head_end))
		if dims == Vector2i.ZERO:
			return "an image is neither PNG nor JPEG"
		var limit := LibraryContracts.MAX_GLB_TEXTURE_PX
		if dims.x < 1 or dims.y < 1 or dims.x > limit or dims.y > limit:
			return "an image is %d x %d px, over %d" % [dims.x, dims.y, limit]
		total += dims.x * dims.y
		if total > MAX_TOTAL_PIXELS:
			return "the images hold over %d pixels in all" % MAX_TOTAL_PIXELS
		sizes.append(dims)
	return ""


## {start, length} (file offsets) of bufferView `index`, or {} when it is not inside the BIN
## chunk.
static func _view_bytes(
	views: Variant, index: int, buffer: PackedByteArray, bin: Dictionary
) -> Dictionary:
	if not views is Array or index < 0 or index >= (views as Array).size():
		return {}
	var view: Variant = (views as Array)[index]
	if not view is Dictionary:
		return {}
	var offset := int((view as Dictionary).get("byteOffset", 0))
	var length: Variant = (view as Dictionary).get("byteLength")
	if not length is float and not length is int:
		return {}
	var count := int(length)
	if offset < 0 or count < 8 or offset + count > int(bin["length"]):
		return {}
	var start := int(bin["start"]) + offset
	if start + count > buffer.size():
		return {}
	return {"start": start, "length": count}


## The pixel size an image's header declares, Vector2i.ZERO for anything but PNG or JPEG.
## `head` is the first bytes of the image (a JPEG's frame header can sit a few KB in).
static func image_size(head: PackedByteArray) -> Vector2i:
	if head.size() >= 24 and head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E:
		var is_ihdr := head[12] == 0x49 and head[13] == 0x48 and head[14] == 0x44 and head[15] == 0x52
		if head[3] == 0x47 and is_ihdr:
			return Vector2i(_be32(head, 16), _be32(head, 20))
		return Vector2i.ZERO
	if head.size() >= 4 and head[0] == 0xFF and head[1] == 0xD8:
		return _jpeg_size(head)
	return Vector2i.ZERO


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Walks JPEG segments to the first start-of-frame marker for its height and width.
static func _jpeg_size(head: PackedByteArray) -> Vector2i:
	var at := 2
	while at + 9 < head.size():
		if head[at] != 0xFF:
			return Vector2i.ZERO
		var marker := head[at + 1]
		if marker == 0xFF:
			at += 1
			continue
		var length := (head[at + 2] << 8) | head[at + 3]
		var is_frame := marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8
		if is_frame and marker != 0xCC:
			var height := (head[at + 5] << 8) | head[at + 6]
			var width := (head[at + 7] << 8) | head[at + 8]
			return Vector2i(width, height)
		at += 2 + length
	return Vector2i.ZERO
