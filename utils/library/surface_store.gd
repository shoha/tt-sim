class_name SurfaceStore
extends RefCounted

## The one place the ground, the crossings, the swatches and the biome thumbnails get a
## palette surface's maps from (design doc 2.7 and 3.2, module 7). Two sources, one result:
##
## - A legacy palette surface (the installed treecube palette, a package, a test fixture) is a
##   relative path under the palette root whose PNG the editor imported; the texture is
##   ResourceLoader's, exactly as GroundPalette.load_texture always returned it.
## - A library surface (`surfaces/<name>/{albedo,normal,orm,height}.png` plus surface.json in a
##   library folder, no editor import) is registered by LibraryRegistry.apply with a palette
##   entry whose paths are `surfaces/<runtime name>/<map>.png`. The store decodes the PNG with
##   Image.load_from_file, bakes it to the formats the import gives (SurfaceBake: BC7 albedo, BC5
##   normal, BC1 ORM, L8 height, full mip chains), keeps the result in memory and in the raw
##   cache (SurfaceCache, user://library_cache/<library id>/<hash>/), and hands out an Image or
##   an ImageTexture. A library file that HAS an editor import (a res:// library in the pack)
##   takes the imported texture instead, as a legacy surface does.
##
## Names. A surface is named by its palette name (`ash`, or `mylib__crystal` for a library
## surface of a non-core library: LibraryIds.runtime_surface) or by the string convention
## `lib://<library id>/<surface name>` (LibraryIds.surface_ref); runtime_name() turns either into
## the palette name and every name-taking function accepts both. lib:// is a string convention
## only: no scheme is registered with Godot and no resource is ever loaded through it.
##
## Nothing here executes library content: files are read as bytes or images, never as
## resources or scripts. A library file is also re-checked at load (size on disk, PNG header,
## dimensions) because the registry's check may be long past.

## A PNG larger than this on disk is never read (a 2048 px RGBA16 map is about 32 MB raw, a
## compressed PNG far less).
const MAX_PNG_BYTES := 48 * 1024 * 1024
## A library biome's thumbnail: at most this many bytes on disk and this many pixels a side
## (larger ones are shrunk to the side).
const MAX_THUMB_BYTES := 4 * 1024 * 1024
const MAX_THUMB_PX := 1024
const SCHEME := LibraryIds.SURFACE_SCHEME

## "<root>|<palette-relative path>" -> {surface: runtime name, kind}.
static var _paths: Dictionary = {}
## "<root>|<palette-relative path>" -> the absolute JPG or PNG of a library biome's own thumbnail
## (S4), read as an image and never as a resource, at most MAX_THUMB_BYTES and MAX_THUMB_PX.
static var _thumbs: Dictionary = {}
## Runtime surface name -> {library, name, info, dir}.
static var _surfaces: Dictionary = {}
## Absolute file -> baked Image / Texture2D, kept for the process.
static var _images: Dictionary = {}
static var _textures: Dictionary = {}
## Runtime surface name -> the hash of its four files (the cache folder name).
static var _hashes: Dictionary = {}
## Counters tests and diagnostics read: bakes, cache_hits, cache_rejects, imports.
static var stats: Dictionary = {"bakes": 0, "cache_hits": 0, "cache_rejects": 0, "imports": 0}

# ---- names ----


## The palette surface name `ref` stands for: `lib://core/ash` is `ash`, `lib://mylib/crystal` is
## `mylib__crystal`, anything else (a plain name) is returned as given.
static func runtime_name(ref: String) -> String:
	var parsed := LibraryIds.parse_surface_ref(ref)
	if parsed.is_empty():
		return ref
	return LibraryIds.runtime_surface(String(parsed["library"]), String(parsed["name"]))


## The `lib://<library id>/<name>` form of a palette surface name: a registered library surface
## answers with its library, a name with a `<lib>__` prefix with that library, any other name
## with core.
static func ref_of(name: String) -> String:
	if _surfaces.has(name):
		var found: Dictionary = _surfaces[name]
		return LibraryIds.surface_ref(String(found["library"]), String(found["name"]))
	if LibraryIds.SEPARATOR in name:
		var library := name.get_slice(LibraryIds.SEPARATOR, 0)
		return LibraryIds.surface_ref(library, name.substr(library.length() + 2))
	return LibraryIds.surface_ref(LibraryContracts.CORE_ID, name)


# ---- registration (LibraryRegistry.apply) ----


## Registers the surfaces of a compiled library (BiomeCompiler.compile's `surfaces`) found under
## `folder`, for the palette at `root`. Replaces an earlier registration of the same names.
static func register_library(root: String, folder: String, surfaces: Dictionary) -> void:
	for runtime: String in surfaces:
		var found: Dictionary = surfaces[runtime]
		var dir := folder.path_join("surfaces").path_join(String(found["name"]))
		_surfaces[runtime] = {
			"library": String(found["library"]),
			"name": String(found["name"]),
			"info": (found["info"] as Dictionary).duplicate(true),
			"dir": dir,
		}
		_hashes.erase(runtime)
		for kind: String in found["maps"]:
			_paths[_key(root, SurfaceBake.relative_path(runtime, kind))] = {
				"surface": runtime, "kind": kind
			}


## Registers the biome thumbnails of a compiled library (BiomeCompiler.compile's `thumbnails`:
## {palette-relative path: absolute file}) for the palette at `root`.
static func register_thumbnails(root: String, thumbnails: Dictionary) -> void:
	for relative: String in thumbnails:
		_thumbs[_key(root, relative)] = String(thumbnails[relative])
		_textures.erase(String(thumbnails[relative]))


## Forgets every registered library surface and what was loaded from it (the cache files stay).
static func clear_libraries() -> void:
	_thumbs.clear()
	_paths.clear()
	_surfaces.clear()
	_images.clear()
	_textures.clear()
	_hashes.clear()


## Drops the in-memory images and textures of library surfaces (the next load reads the cache).
static func clear_memory() -> void:
	_images.clear()
	_textures.clear()


static func reset_stats() -> void:
	stats = {"bakes": 0, "cache_hits": 0, "cache_rejects": 0, "imports": 0}


## True when the palette-relative path is a registered library map (not an editor import).
static func is_library_path(root: String, relative: String) -> bool:
	return _paths.has(_key(root, relative))


static func is_library_surface(name: String) -> bool:
	return _surfaces.has(runtime_name(name))


## The readable name from the library's surface.json (`label`), "" for a surface that is not a
## registered library surface (the caller falls back to its own table).
static func label_of(name: String) -> String:
	var found: Dictionary = _surfaces.get(runtime_name(name), {})
	return String((found.get("info", {}) as Dictionary).get("label", ""))


## A copy of the surface.json fields of a registered library surface, {} otherwise.
static func info_of(name: String) -> Dictionary:
	var found: Dictionary = _surfaces.get(runtime_name(name), {})
	return (found.get("info", {}) as Dictionary).duplicate(true)


# ---- loading ----


## True when the map at palette-relative `relative` under `root` can be drawn.
static func available(root: String, relative: String) -> bool:
	if relative == "":
		return false
	var entry: Dictionary = _paths.get(_key(root, relative), {})
	if not entry.is_empty():
		return FileAccess.file_exists(_file_of(entry))
	if _thumbs.has(_key(root, relative)):
		return FileAccess.file_exists(String(_thumbs[_key(root, relative)]))
	return ResourceLoader.exists(root.path_join(relative))


## The texture of the map at palette-relative `relative` under `root`, or null. A legacy path is
## ResourceLoader's imported texture (null when there is none); a registered library path is the
## editor import when its file has one, else the baked map as an ImageTexture.
static func texture(root: String, relative: String) -> Texture2D:
	if relative == "":
		return null
	var entry: Dictionary = _paths.get(_key(root, relative), {})
	if entry.is_empty() and _thumbs.has(_key(root, relative)):
		return _thumbnail_texture(String(_thumbs[_key(root, relative)]))
	if entry.is_empty():
		var path := root.path_join(relative)
		if not ResourceLoader.exists(path):
			return null
		return ResourceLoader.load(path) as Texture2D
	var file := _file_of(entry)
	if _textures.has(file):
		return _textures[file]
	var loaded: Texture2D = null
	if file.begins_with("res://") and ResourceLoader.exists(file, "Texture2D"):
		loaded = ResourceLoader.load(file, "Texture2D") as Texture2D
		stats["imports"] += 1
	else:
		var image := _baked(entry)
		if image != null:
			loaded = ImageTexture.create_from_image(image)
	if loaded != null:
		_textures[file] = loaded
	return loaded


## The Image of the map at `relative` under `root`, a copy the caller may change, or null: the
## baked map for a library surface (no GPU round trip), the imported texture's image otherwise.
static func image(root: String, relative: String) -> Image:
	var entry: Dictionary = _paths.get(_key(root, relative), {})
	if not entry.is_empty():
		var file := _file_of(entry)
		if file.begins_with("res://") and ResourceLoader.exists(file, "Texture2D"):
			return _texture_image(texture(root, relative))
		var baked := _baked(entry)
		return baked.duplicate() as Image if baked != null else null
	return _texture_image(texture(root, relative))


## texture() for map `kind` of the surface `ref` names (a palette name or a lib:// reference) in
## the palette at `root`.
static func texture_of(root: String, ref: String, kind: String) -> Texture2D:
	return texture(root, _relative_of(root, ref, kind))


## image() for map `kind` of the surface `ref` names in the palette at `root`.
static func image_of(root: String, ref: String, kind: String) -> Image:
	return image(root, _relative_of(root, ref, kind))


## The surface set in `folder` (a `surfaces/<name>` folder: surface.json plus the PNGs), loaded
## and baked without registering anything: {ok, errors, warnings, info, images: {kind: Image},
## mean_albedo_linear (info's when given, else measured from the albedo)}. `library_id` names the
## cache folder. A set that fails the reader's checks returns ok false and no images.
static func load_set(folder: String, library_id: String = "dev") -> Dictionary:
	var out := {
		"ok": false,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"info": {},
		"images": {},
		"mean_albedo_linear": Color(0, 0, 0),
	}
	var errors: Array[String] = out["errors"]
	var warnings: Array[String] = out["warnings"]
	var name := folder.trim_suffix("/").get_file()
	for problem in LibraryIds.surface_problems(name):
		errors.append(problem)
	var checked := SurfaceBake.check_info(
		_text_of(folder.path_join(SurfaceReader.INFO_FILE), SurfaceBake.MAX_INFO_BYTES), name
	)
	errors.append_array(checked["errors"])
	warnings.append_array(checked["warnings"])
	var files := {}
	for kind in SurfaceBake.KINDS:
		var file := folder.path_join(kind + ".png")
		if FileAccess.file_exists(file):
			files[kind] = file
			SurfaceBake.check_png(png_header_of(file), kind, "surface " + name, errors, warnings)
	if not files.has("albedo"):
		errors.append("surface %s: albedo.png is missing" % name)
	if not errors.is_empty():
		return out
	out["info"] = checked["info"]
	var hash_text := _hash_files(name, files)
	for kind: String in files:
		var baked := _bake_or_cache(String(files[kind]), kind, library_id, name, hash_text)
		if baked == null:
			errors.append("surface %s: %s.png could not be decoded" % [name, kind])
		else:
			out["images"][kind] = baked
	if not errors.is_empty():
		out["images"] = {}
		return out
	var mean: Variant = (checked["info"] as Dictionary).get("albedo_mean_linear")
	if mean is Array:
		out["mean_albedo_linear"] = Color(mean[0], mean[1], mean[2])
	else:
		out["mean_albedo_linear"] = SurfaceBake.mean_albedo_linear(out["images"]["albedo"])
	out["ok"] = true
	return out


## The maps of the installed palette surface `name` at `root`, from the editor import (what a
## library set must equal): {kind: Image}, a kind with no texture left out.
static func load_installed(root: String, name: String) -> Dictionary:
	var images := {}
	var entry: Dictionary = PaletteLibrary.surfaces(root).get(runtime_name(name), {})
	for kind in SurfaceBake.KINDS:
		var loaded := image(root, String(entry.get(kind, "")))
		if loaded != null:
			images[kind] = loaded
	return images


## {ok, width, height, bit_depth, color_type, interlace} of the PNG at `path`, read from its
## first bytes; {ok: false, error} when it is missing, unreadable or not a PNG.
static func png_header_of(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot be opened"}
	if file.get_length() > MAX_PNG_BYTES:
		return {"ok": false, "error": "is over %d bytes" % MAX_PNG_BYTES}
	var bytes := file.get_buffer(SurfaceBake.PNG_HEADER_BYTES)
	file.close()
	return SurfaceBake.png_header(bytes)


# ---- internals ----


static func _key(root: String, relative: String) -> String:
	return root + "|" + relative


static func _relative_of(root: String, ref: String, kind: String) -> String:
	var entry: Dictionary = PaletteLibrary.surfaces(root).get(runtime_name(ref), {})
	return String(entry.get(kind, ""))


static func _file_of(entry: Dictionary) -> String:
	var found: Dictionary = _surfaces.get(String(entry["surface"]), {})
	return String(found.get("dir", "")).path_join(String(entry["kind"]) + ".png")


## A library biome's thumbnail as a texture (cached by file), or null for a missing, oversized
## or unreadable file. The bytes are decoded as an image (JPG or PNG by extension), never loaded
## as a resource.
static func _thumbnail_texture(file: String) -> Texture2D:
	if _textures.has(file):
		return _textures[file]
	if not FileAccess.file_exists(file):
		return null
	var handle := FileAccess.open(file, FileAccess.READ)
	if handle == null or handle.get_length() > MAX_THUMB_BYTES:
		return null
	var bytes := handle.get_buffer(handle.get_length())
	handle.close()
	# The size is read from the header before anything is decoded.
	var dims := GlbGuard.image_size(bytes.slice(0, GlbGuard.HEAD_BYTES))
	var limit := LibraryContracts.MAX_GLB_TEXTURE_PX
	if dims == Vector2i.ZERO or dims.x > limit or dims.y > limit:
		return null
	var picture := Image.new()
	var err := (
		picture.load_png_from_buffer(bytes)
		if file.get_extension().to_lower() == "png"
		else picture.load_jpg_from_buffer(bytes)
	)
	if err != OK or picture.is_empty():
		return null
	var side := maxi(picture.get_width(), picture.get_height())
	if side > MAX_THUMB_PX:
		var scale := float(MAX_THUMB_PX) / side
		picture.resize(
			maxi(1, int(picture.get_width() * scale)), maxi(1, int(picture.get_height() * scale))
		)
	var made := ImageTexture.create_from_image(picture)
	_textures[file] = made
	return made


static func _texture_image(loaded: Texture2D) -> Image:
	if loaded == null:
		return null
	var picture := loaded.get_image()
	return picture if picture != null and not picture.is_empty() else null


## The baked map of a registered path entry, from memory, the cache or the PNG.
static func _baked(entry: Dictionary) -> Image:
	var file := _file_of(entry)
	if _images.has(file):
		return _images[file]
	var runtime := String(entry["surface"])
	var found: Dictionary = _surfaces.get(runtime, {})
	var files := {}
	for kind in SurfaceBake.KINDS:
		var candidate := String(found.get("dir", "")).path_join(kind + ".png")
		if FileAccess.file_exists(candidate):
			files[kind] = candidate
	if not _hashes.has(runtime):
		_hashes[runtime] = _hash_files(String(found.get("name", "")), files)
	var baked := _bake_or_cache(
		file,
		String(entry["kind"]),
		String(found.get("library", "")),
		String(found.get("name", "")),
		String(_hashes[runtime])
	)
	if baked != null:
		_images[file] = baked
	return baked


## The map of `file`: the raw cache when it holds a valid entry for this engine, else decoded from
## the PNG, baked, and written to the cache. Null when the PNG is missing, hostile or unreadable.
static func _bake_or_cache(
	file: String, kind: String, library_id: String, name: String, hash_text: String
) -> Image:
	var cache_path := SurfaceCache.path_for(library_id, hash_text, name, kind)
	if FileAccess.file_exists(cache_path):
		var cached := SurfaceCache.read(cache_path)
		if cached != null and cached.get_format() == SurfaceBake.format_of(kind):
			stats["cache_hits"] += 1
			return cached
		stats["cache_rejects"] += 1
	var header := png_header_of(file)
	var problems: Array[String] = []
	SurfaceBake.check_png(header, kind, name, problems, [] as Array[String])
	if not problems.is_empty():
		push_warning("SurfaceStore: %s" % problems[0])
		return null
	var decoded := Image.load_from_file(file)
	var baked := SurfaceBake.bake(decoded, kind)
	if baked == null:
		push_warning("SurfaceStore: %s could not be decoded" % file)
		return null
	stats["bakes"] += 1
	SurfaceCache.write(cache_path, baked)
	return baked


## A short hash of the surface's files (name and the SHA-256 of each map), the cache folder name:
## editing a PNG gives a new folder, so a stale bake is never read.
static func _hash_files(name: String, files: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(name.to_utf8_buffer())
	for kind in SurfaceBake.KINDS:
		if files.has(kind):
			hashing.update(kind.to_utf8_buffer())
			hashing.update(FileAccess.get_sha256(String(files[kind])).to_utf8_buffer())
	return hashing.finish().hex_encode().substr(0, SurfaceCache.HASH_LENGTH)


static func _text_of(path: String, cap: int) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(mini(file.get_length(), cap + 1))
	file.close()
	return bytes.get_string_from_utf8()
