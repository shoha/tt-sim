class_name SurfaceCache
extends RefCounted

## The raw cache of baked surface maps (design doc 2.7.2, S0 probe P2): the baked Image's bytes
## behind a small header, one file per map under `user://library_cache/<library id>/<hash>/`.
## It is never a Godot resource: nothing here is loaded with ResourceLoader (a .res can carry a
## script), the file is read with FileAccess and rebuilt with Image.create_from_data, and a file
## that does not match the header, the size its format and dimensions imply, or its own SHA-256
## is rejected and the map is baked again. The cache is a local artefact, not a source of truth:
## the header carries the engine version string and a different engine (whose compressor may
## differ) ignores the file and bakes anew, which then replaces it.
##
## Layout (little endian): "TTIMG" | u8 version | u16 engine length | engine | u32 format |
## u32 width | u32 height | u8 mip flag | u32 data length | 32 bytes SHA-256 of the data | data.

const MAGIC := "TTIMG"
const VERSION := 1
const FILE_EXTENSION := "ttimg"
const HASH_LENGTH := 16
const MAX_ENGINE_LENGTH := 128

## Where the caches live; tests point it at a scratch folder.
static var root: String = "user://library_cache"


## The engine version string written into, and required of, every cache file.
static func engine_id() -> String:
	var info := Engine.get_version_info()
	return "%s %s" % [String(info.get("string", "")), String(info.get("hash", ""))]


## The cache file of one map: <root>/<library id>/<hash>/<surface>_<kind>.ttimg. The library id
## and surface name are grammar-checked ids (no separators), so nothing here escapes the root.
static func path_for(
	library_id: String, hash_text: String, surface: String, kind: String
) -> String:
	return root.path_join(library_id).path_join(hash_text).path_join(
		"%s_%s.%s" % [surface, kind, FILE_EXTENSION]
	)


## The bytes of `image` (a baked map: a format SurfaceBake produces, with its mip chain).
static func encode(image: Image, engine: String = "") -> PackedByteArray:
	if engine == "":
		engine = engine_id()
	var data := image.get_data()
	var buffer := StreamPeerBuffer.new()
	buffer.put_data(MAGIC.to_ascii_buffer())
	buffer.put_u8(VERSION)
	var engine_bytes := engine.to_utf8_buffer()
	buffer.put_u16(engine_bytes.size())
	buffer.put_data(engine_bytes)
	buffer.put_u32(image.get_format())
	buffer.put_u32(image.get_width())
	buffer.put_u32(image.get_height())
	buffer.put_u8(1 if image.has_mipmaps() else 0)
	buffer.put_u32(data.size())
	buffer.put_data(_digest(data))
	buffer.put_data(data)
	return buffer.data_array


## The Image in `bytes`, or null when anything is off: magic, version, a different engine
## (`engine`, this one's by default), unknown format, dimensions out of range, a data length that
## is not the size the format implies, truncation or a digest mismatch. Never raises.
static func decode(bytes: PackedByteArray, engine: String = "") -> Image:
	if engine == "":
		engine = engine_id()
	var head := MAGIC.length() + 1 + 2
	if bytes.size() < head or bytes.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		return null
	if bytes[MAGIC.length()] != VERSION:
		return null
	var at := MAGIC.length() + 1
	var engine_length := bytes.decode_u16(at)
	at += 2
	if engine_length > MAX_ENGINE_LENGTH or bytes.size() < at + engine_length + 17 + 32:
		return null
	if bytes.slice(at, at + engine_length).get_string_from_utf8() != engine:
		return null
	at += engine_length
	var format := int(bytes.decode_u32(at))
	var width := int(bytes.decode_u32(at + 4))
	var height := int(bytes.decode_u32(at + 8))
	var mips := bytes[at + 12] == 1
	var length := int(bytes.decode_u32(at + 13))
	at += 17
	if width < SurfaceBake.MIN_SIZE or width > SurfaceBake.MAX_SIZE:
		return null
	if height < SurfaceBake.MIN_SIZE or height > SurfaceBake.MAX_SIZE or not mips:
		return null
	var expected := SurfaceBake.data_size(format, width, height)
	if expected < 0 or length != expected or bytes.size() != at + 32 + length:
		return null
	var digest := bytes.slice(at, at + 32)
	var data := bytes.slice(at + 32)
	if _digest(data) != digest:
		return null
	var image := Image.create_from_data(width, height, true, format as Image.Format, data)
	return image if image != null and not image.is_empty() else null


## Reads the cache file at `path`; null when it is missing or does not decode.
static func read(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return decode(bytes)


## Writes `image` to `path` (creating the folders); false on any failure. Written to a
## neighbouring temporary file and renamed, so a half-written cache is never read.
static func write(path: String, image: Image) -> bool:
	var base := LibraryPaths.cache()
	var target := LibraryPaths.resolve(path)
	if not base["ok"] or not target["ok"]:
		return false
	var cache_root := String(base["path"])
	if not LibraryPaths.inside(String(target["path"]), cache_root):
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	# The first folder under the cache root is the library's: the game made it, so it carries
	# the ownership marker that lets remove_library() delete it.
	var relative := String(target["path"]).substr(cache_root.length()).trim_prefix("/")
	var library_folder := cache_root.path_join(relative.get_slice("/", 0))
	if relative.contains("/") and not SafeDelete.is_owned(library_folder):
		SafeDelete.mark(library_folder, "surface_cache", cache_root)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(encode(image))
	file.close()
	if FileAccess.file_exists(path):
		SafeDelete.file(path, cache_root)
	return DirAccess.rename_absolute(temporary, path) == OK


## Deletes the baked maps of library `library_id` (its folder under the cache root); true when
## nothing is left. The folder goes only when it carries the ownership marker; a cache made
## before the marker existed is adopted first when it holds nothing but `.ttimg` and `.tmp`
## files (the cache is rebuilt on demand, so a refusal only costs disk).
static func remove_library(library_id: String) -> bool:
	var base := LibraryPaths.cache()
	var folder := LibraryPaths.child(base, library_id)
	if not folder["ok"]:
		return false
	var path := String(folder["path"])
	if not DirAccess.dir_exists_absolute(path):
		return true
	if not SafeDelete.is_owned(path):
		var extensions := PackedStringArray([FILE_EXTENSION, "tmp"])
		SafeDelete.mark_if_only(path, "surface_cache", extensions, String(base["path"]))
	return bool(SafeDelete.tree(path, String(base["path"]))["ok"])


static func _digest(data: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish()
