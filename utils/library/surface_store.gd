class_name SurfaceStore
extends RefCounted

## The one place the ground, the crossings, the swatches and the biome thumbnails get a
## palette surface's maps from (design doc 2.7 and 3.2, module 7). Two sources, one result:
##
## - A legacy palette surface (a test fixture palette) is a relative path under the palette root
##   whose PNG the editor imported; the texture is ResourceLoader's, exactly as
##   GroundPalette.load_texture always returned it.
## - A library surface (`surfaces/<name>/{albedo,normal,orm,height}.<webp|png>` plus surface.json
##   in a library folder, no editor import; core's files are `importer="keep"` raw lossless WebP in
##   the pack) is registered by LibraryRegistry.apply with a palette entry whose paths are
##   `surfaces/<runtime name>/<map>.<webp|png>`. The store decodes the file's bytes
##   (SurfaceBake.decode: WebP preferred when a folder holds both, map_file), bakes it to the
##   formats the import gives (SurfaceBake: BC7
##   albedo, BC5 normal, BC1 ORM, L8 height, full mip chains), keeps the result in memory and
##   in the raw cache (SurfaceCache, user://library_cache/<library id>/<hash>/), and hands out an
##   Image or an ImageTexture. A
##   library file is NEVER loaded through ResourceLoader (it does not work on a keep file in a
##   pack, and would fail in the editor). A map load can have the maps it is about to draw baked
##   ahead on a worker (prebake(), SurfacePrebake): the first texture() or image() then takes
##   the worker's result instead of baking in its own frame (about 200 ms per albedo, cold).
##
## Names. A surface is named by its palette name (`ash`, or `mylib__crystal` for a library
## surface of a non-core library: LibraryIds.runtime_surface) or by the string convention
## `lib://<library id>/<surface name>` (LibraryIds.surface_ref); runtime_name() turns either into
## the palette name and every name-taking function accepts both. lib:// is a string convention
## only: no scheme is registered with Godot and no resource is ever loaded through it.
##
## Nothing here executes library content: files are read as bytes or images, never as
## resources or scripts. A library file is also re-checked at load (size on disk, PNG or WebP
## header, dimensions) because the registry's check may be long past.

## A map file larger than this on disk is never read (a 2048 px RGBA16 map is about 32 MB raw, a
## compressed PNG or WebP far less).
const MAX_MAP_BYTES := 48 * 1024 * 1024
## A library biome's thumbnail: at most this many bytes on disk and this many pixels a side
## (larger ones are shrunk to the side).
const MAX_THUMB_BYTES := 4 * 1024 * 1024
const MAX_THUMB_PX := 1024
const SCHEME := LibraryIds.SURFACE_SCHEME
## The prebake lane's priorities, first to last: the maps a load waits for under its sheet, the
## pictures a panel shows (a biome tile), the ones it warms ahead of their first show (the Paint
## swatches).
const PRIORITY_LOAD := 0
const PRIORITY_SHOWN := 1
const PRIORITY_AHEAD := 2
## SurfaceWait's script, loaded on first use by start-up code (the start-up script graph).
const SURFACE_WAIT := "res://utils/library/surface_wait.gd"

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
## Counters tests and diagnostics read: bakes and cache_hits on the main thread, prebakes and
## prebake_hits by the prebake lane (counted when the main thread takes the map), cache_rejects,
## imports.
static var stats: Dictionary = _zero_stats()
## The lane that bakes maps ahead of their first use (prebake()), made on the first prebake.
static var _prebake: Variant = null  # a SurfacePrebake, loaded on first use (start-up size)
## Held around every bake (compression and cache write), on any thread, so two bakes never compete
## for the worker pool (a compression already spreads over every pool thread). It does not make
## the bytes reproducible: see SurfaceBake.bake. Lives here, not in SurfacePrebake, so start-up
## never loads that script.
static var compress_lock := Mutex.new()
## False turns prebake() into a no-op (every map bakes where it is first asked for): the
## performance harness's in-run A/B switch (perfaudit_system.gd `prebake`).
static var prebake_enabled: bool = true
## The open trace's step timers (OpenTrace, card coldopen), off by default: while on, every map
## load reports the microseconds of its steps (read: a cache hit; decode; bake: the compression;
## write: the cache file; hash: the SHA-256 of the surface's files) and timings sums them per
## side ("lane_<step>" for the prebake lane, "main_<step>" for the main thread) with a count per
## outcome ("lane_baked", "main_hit", ...), when the main thread takes the map.
static var timing_enabled: bool = false
static var timings: Dictionary = {}

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
			"root": root,
		}
		_hashes.erase(runtime)
		_forget_prebaked()
		var files: Dictionary = found.get("files", {})
		for kind: String in found["maps"]:
			var relative := SurfaceBake.relative_path(
				runtime, kind, SurfaceBake.extension_of(files, kind)
			)
			_paths[_key(root, relative)] = {"surface": runtime, "kind": kind}


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
	_forget_prebaked()


## Forgets what was registered for the palette at `root` only (LibraryRegistry.apply serving one
## root leaves another root's registrations alone); loaded images and textures are dropped, they
## are read again from the cache.
static func clear_libraries_of(root: String) -> void:
	var prefix := root + "|"
	for table: Dictionary in [_thumbs, _paths]:
		for key: String in table.keys():
			if key.begins_with(prefix):
				table.erase(key)
	for runtime: String in _surfaces.keys():
		if String((_surfaces[runtime] as Dictionary).get("root", "")) == root:
			_surfaces.erase(runtime)
			_hashes.erase(runtime)
	_images.clear()
	_textures.clear()
	_forget_prebaked()


## Drops the in-memory images and textures of library surfaces, and what the prebake lane holds
## (the next load reads the cache).
static func clear_memory() -> void:
	_images.clear()
	_textures.clear()
	_forget_prebaked()


static func reset_stats() -> void:
	stats = _zero_stats()


static func _zero_stats() -> Dictionary:
	return {
		"bakes": 0,
		"cache_hits": 0,
		"prebakes": 0,
		"prebake_hits": 0,
		"cache_rejects": 0,
		"imports": 0,
	}


## Starts baking the maps of the library surfaces `names` (palette names or lib:// references; a
## plain palette's or an unknown name is skipped) on the prebake lane (SurfacePrebake: one worker
## task, the same bytes as a main-thread bake), so their first texture() or image() finds them
## baked instead of baking in its frame. `priority` places them in the lane's queue
## (PRIORITY_LOAD first); `kinds` limits the maps (all four when empty: a swatch needs only the
## albedo). Maps in memory or already queued are left alone, but a queued one moves up to a
## higher priority. A map asked for before the lane reached it is baked by the asker, as without a
## prebake.
static func prebake(
	names: PackedStringArray,
	priority: int = PRIORITY_LOAD,
	kinds: PackedStringArray = PackedStringArray()
) -> void:
	if not prebake_enabled:
		return
	for ref in names:
		var runtime := runtime_name(ref)
		var found: Dictionary = _surfaces.get(runtime, {})
		if found.is_empty():
			continue
		var files := _surface_files(found)
		for kind: String in files:
			if not kinds.is_empty() and not kind in kinds:
				continue
			var file := String(files[kind])
			if _images.has(file):
				continue
			if _prebake == null:
				_prebake = (load("res://utils/library/surface_prebake.gd") as GDScript).new()
			_prebake.add(
				{
					"file": file,
					"kind": kind,
					"library": String(found.get("library", "")),
					"name": String(found.get("name", "")),
					"runtime": runtime,
					"files": files,
					"hash": String(_hashes.get(runtime, "")),
				},
				priority
			)


## prebake() for the maps at the palette-relative paths `relatives` under `root` (a swatch's or a
## biome picture's albedo); a path that is not a registered library map is skipped.
static func prebake_paths(root: String, relatives: PackedStringArray, priority: int) -> void:
	for relative in relatives:
		var entry: Dictionary = _paths.get(_key(root, relative), {})
		if not entry.is_empty():
			prebake(
				PackedStringArray([String(entry["surface"])]),
				priority,
				PackedStringArray([String(entry["kind"])])
			)


## True while the prebake lane has maps queued or baking.
static func is_prebaking() -> bool:
	return _prebake != null and _prebake.is_busy()


## True while any map of the library surfaces `names` is queued or baking on the lane (a load
## waits for its own maps under its sheet, not for pictures queued behind them).
static func prebaking(names: PackedStringArray) -> bool:
	if _prebake == null:
		return false
	# Releases the lane tasks that have ended (the pool keeps a task until it is waited on).
	_prebake.is_busy()
	for ref in names:
		var found: Dictionary = _surfaces.get(runtime_name(ref), {})
		if found.is_empty():
			continue
		var dir := String(found.get("dir", ""))
		for kind in SurfaceBake.KINDS:
			var file := map_file(dir, kind)
			if file != "" and _prebake.is_pending(file):
				return true
	return false


## True while the map at palette-relative `relative` under `root` is queued or baking on the lane:
## its texture() or image() would wait for the bake (or bake it, when still queued).
static func is_pending(root: String, relative: String) -> bool:
	if _prebake == null:
		return false
	var entry: Dictionary = _paths.get(_key(root, relative), {})
	return not entry.is_empty() and _prebake.is_pending(_file_of(entry))


static func _forget_prebaked() -> void:
	if _prebake != null:
		_prebake.forget()


## True when the palette-relative path is a registered library map (not an editor import).
static func is_library_path(root: String, relative: String) -> bool:
	return _paths.has(_key(root, relative))


## True when the palette-relative path is a library biome's own thumbnail (registered by
## register_thumbnails), not the installed palette's picture.
static func is_library_thumbnail(root: String, relative: String) -> bool:
	return _thumbs.has(_key(root, relative))


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
## baked map as an ImageTexture.
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


## The surface set in `folder` (a `surfaces/<name>` folder: surface.json plus the maps), loaded
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
		var file := map_file(folder, kind)
		if file != "":
			files[kind] = file
			SurfaceBake.check_png(map_header_of(file), kind, "surface " + name, errors, warnings)
	if not files.has("albedo"):
		errors.append("surface %s: albedo.webp or albedo.png is missing" % name)
	if not errors.is_empty():
		return out
	out["info"] = checked["info"]
	var hash_text := files_hash(name, files)
	for kind: String in files:
		var baked := _bake_or_cache(String(files[kind]), kind, library_id, name, hash_text)
		if baked == null:
			errors.append("surface %s: %s could not be decoded" % [name, String(files[kind]).get_file()])
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


## {ok, width, height, bit_depth, color_type, interlace} of the PNG at `path`, read from its
## first bytes; {ok: false, error} when it is missing, unreadable or not a PNG.
static func png_header_of(path: String) -> Dictionary:
	return _header_of(path, "png")


## SurfaceBake.map_header of the map file at `path` (WebP or PNG by its extension), read from its
## first bytes and checked against its size; {ok: false, error} when it is missing, over
## MAX_MAP_BYTES, unreadable, not the format its name says or a truncated WebP.
static func map_header_of(path: String) -> Dictionary:
	return _header_of(path, path.get_extension())


static func _header_of(path: String, extension: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot be opened"}
	var length := file.get_length()
	if length > MAX_MAP_BYTES:
		return {"ok": false, "error": "is over %d bytes" % MAX_MAP_BYTES}
	var bytes := file.get_buffer(SurfaceBake.HEADER_BYTES)
	file.close()
	return SurfaceBake.map_header(bytes, extension, length)


## The map file of `kind` in the surface folder `dir`: `<kind>.webp` when it exists, else
## `<kind>.png` (SurfaceBake.MAP_EXTENSIONS order), or "" when neither does.
static func map_file(dir: String, kind: String) -> String:
	for extension in SurfaceBake.MAP_EXTENSIONS:
		var candidate := dir.path_join("%s.%s" % [kind, extension])
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


# ---- internals ----


static func _key(root: String, relative: String) -> String:
	return root + "|" + relative


static func _relative_of(root: String, ref: String, kind: String) -> String:
	var entry: Dictionary = PaletteLibrary.surfaces(root).get(runtime_name(ref), {})
	return String(entry.get(kind, ""))


static func _file_of(entry: Dictionary) -> String:
	var found: Dictionary = _surfaces.get(String(entry["surface"]), {})
	var dir := String(found.get("dir", ""))
	var file := map_file(dir, String(entry["kind"]))
	return file if file != "" else dir.path_join(String(entry["kind"]) + ".png")


## A library biome's thumbnail as a texture (cached by file), or null for a missing, oversized
## or unreadable file. The bytes are decoded as an image (JPG or PNG by extension), never loaded
## as a resource.
static func _thumbnail_texture(file: String) -> Texture2D:
	if _textures.has(file):
		return _textures[file]
	var picture := thumbnail_image(file, MAX_THUMB_PX)
	if picture == null:
		return null
	var made := ImageTexture.create_from_image(picture)
	_textures[file] = made
	return made


## The JPG or PNG `file` decoded from its bytes (never loaded as a resource), shrunk to at most
## `max_side` pixels a side, or null for a missing, oversized (MAX_THUMB_BYTES, or a header over
## MAX_GLB_TEXTURE_PX) or undecodable file. Biome thumbnails and AssetThumbnails use it.
static func thumbnail_image(file: String, max_side: int) -> Image:
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
	if side > max_side:
		var scale := float(max_side) / side
		picture.resize(
			maxi(1, int(picture.get_width() * scale)), maxi(1, int(picture.get_height() * scale))
		)
	return picture


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
	if _prebake != null:
		var lane: Dictionary = _prebake.take(file)
		if not lane.is_empty():
			if not _hashes.has(runtime):
				_hashes[runtime] = String(lane["hash"])
			_count(lane, "prebakes", "prebake_hits")
			if lane["image"] != null:
				_images[file] = lane["image"]
			return lane["image"]
	var found: Dictionary = _surfaces.get(runtime, {})
	var files := _surface_files(found)
	if not _hashes.has(runtime):
		var hashed_at := Time.get_ticks_usec() if timing_enabled else 0
		_hashes[runtime] = files_hash(String(found.get("name", "")), files)
		if timing_enabled:
			_time("main_hash", Time.get_ticks_usec() - hashed_at)
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


## {kind: absolute map file} of the maps a registered surface (`_surfaces` entry) has on disk.
static func _surface_files(found: Dictionary) -> Dictionary:
	var files := {}
	for kind in SurfaceBake.KINDS:
		var file := map_file(String(found.get("dir", "")), kind)
		if file != "":
			files[kind] = file
	return files


## load_map() on the main thread, counted in stats.
static func _bake_or_cache(
	file: String, kind: String, library_id: String, name: String, hash_text: String
) -> Image:
	var loaded := load_map(file, kind, library_id, name, hash_text)
	_count(loaded, "bakes", "cache_hits")
	return loaded["image"]


## Adds load_map's outcome `loaded` to stats under `baked_key` or `hit_key`.
static func _count(loaded: Dictionary, baked_key: String, hit_key: String) -> void:
	if loaded["rejected"]:
		stats["cache_rejects"] += 1
	match String(loaded["outcome"]):
		"baked":
			stats[baked_key] += 1
		"hit":
			stats[hit_key] += 1
	if timing_enabled and loaded.has("us"):
		var side := "lane_" if baked_key == "prebakes" else "main_"
		_time(side + String(loaded["outcome"]), 1)
		var steps: Dictionary = loaded["us"]
		for step: String in steps:
			_time(side + step, int(steps[step]))


## Adds `amount` to timings[`key`] (the open trace's step timers).
static func _time(key: String, amount: int) -> void:
	timings[key] = int(timings.get(key, 0)) + amount


## The map of `file` as {image, outcome, rejected}: the raw cache's when it holds a valid entry for
## this engine (outcome "hit"), else decoded from the WebP or PNG, baked and written to the cache
## ("baked"); image null and outcome "failed" when the file is missing, hostile or unreadable;
## rejected true when a cache file was there but unusable. It reads and writes no table of the
## store, so the prebake lane runs it on its worker; the bake and the cache write hold
## compress_lock (one compression at a time). Two bakes of one PNG can differ in a few BC7 block
## bytes (SurfaceBake.bake), and the cache and memory then hold valid, equivalent maps.
static func load_map(
	file: String, kind: String, library_id: String, name: String, hash_text: String
) -> Dictionary:
	var out := {"image": null, "outcome": "failed", "rejected": false}
	# The open trace's step timers (timing_enabled): microseconds per step, in out["us"].
	var timed := timing_enabled
	var at := Time.get_ticks_usec() if timed else 0
	var cache_path := SurfaceCache.path_for(library_id, hash_text, name, kind)
	if FileAccess.file_exists(cache_path):
		var cached := SurfaceCache.read(cache_path)
		if cached != null and cached.get_format() == SurfaceBake.format_of(kind):
			out["image"] = cached
			out["outcome"] = "hit"
			if timed:
				out["us"] = {"read": Time.get_ticks_usec() - at}
			return out
		out["rejected"] = true
	var header := map_header_of(file)
	var problems: Array[String] = []
	SurfaceBake.check_png(header, kind, name, problems, [] as Array[String])
	if not problems.is_empty():
		push_warning("SurfaceStore: %s" % problems[0])
		return out
	# From bytes, not Image.load_from_file: that one warns (once per process) for a res:// file the
	# editor knows through its keep sidecar, and the bytes are the same ones in a pack.
	var decoded := SurfaceBake.decode(FileAccess.get_file_as_bytes(file), file.get_extension())
	var decoded_at := Time.get_ticks_usec() if timed else 0
	compress_lock.lock()
	var locked_at := Time.get_ticks_usec() if timed else 0
	var baked := SurfaceBake.bake(decoded, kind)
	var baked_at := Time.get_ticks_usec() if timed else 0
	if baked != null:
		SurfaceCache.write(cache_path, baked)
	compress_lock.unlock()
	if timed:
		out["us"] = {
			"decode": decoded_at - at,
			"lock": locked_at - decoded_at,
			"bake": baked_at - locked_at,
			"write": Time.get_ticks_usec() - baked_at,
		}
	if baked == null:
		push_warning("SurfaceStore: %s could not be decoded" % file)
		return out
	out["image"] = baked
	out["outcome"] = "baked"
	return out


## A short hash of the surface's files (name and the SHA-256 of each map), the cache folder name:
## editing a map, or re-encoding it (PNG to WebP), gives a new folder, so a stale bake is never
## read. Reads files only, so the prebake lane calls it on its worker.
static func files_hash(name: String, files: Dictionary) -> String:
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
