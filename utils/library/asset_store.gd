class_name AssetStore
extends RefCounted

## The one place a library asset's mesh comes from (design doc 3.2, module 6), keyed by
## (library id, asset id). LibraryRegistry.apply registers each served library's assets (where
## the GLB lives, its node, the catalog's sha256 and byte count, whether the library is
## official); PaletteLibrary._source_mesh asks for the mesh of any asset the store serves and
## otherwise loads the built-in palette as it always did.
##
## Lazy: nothing is read until a mesh is asked for, then the GLB's bytes are read once and
## checked (size cap, GlbGuard: container, no external uri, texture sizes from the image headers
## before any decode), and for a library that is NOT official the bytes must match the catalog's
## `sha256` and `bytes` or the asset is refused (a warning once, then a cached null, so a missing
## plant never stalls a map). Official libraries skip the hash on load (they ship inside the
## game); verify() runs the same check for a test or a CLI. The parse is GLTFDocument over the
## bytes with mesh compression off, from a file path: never ResourceLoader, so no library file is
## ever a resource or a script. Every material of the parsed mesh is a BaseMaterial3D (glTF
## cannot carry a shader); sanitize() makes that certain, and instance() hands out a duplicate
## dressed with WindFoliage.apply_material, the replacement every built-in asset gets, so a
## library material never draws with anything but the game's own shaders.
##
## The cache is per (root, asset id) like PaletteLibrary's; clear() drops registrations and
## meshes together (PaletteLibrary.clear_cache calls it, and LibraryRegistry.apply registers
## again). A Mutex guards the tables: scatter preparation resolves assets on worker threads.

const MAX_FILE_BYTES := PaletteAssetFiles.MAX_ASSET_FILE_BYTES

static var _lock: Mutex = Mutex.new()
## "<root>|<asset id>" -> {library, path, node, sha256, bytes, official}.
static var _entries: Dictionary = {}
## "<root>|<asset id>" -> Mesh, or null when the load was refused or failed (cached too).
static var _meshes: Dictionary = {}
## "<root>|<asset id>" -> why the load failed.
static var _errors: Dictionary = {}
## Counters tests read: parses (GLBs decoded), cache_hits, hash_checks, refused.
static var stats: Dictionary = {"parses": 0, "cache_hits": 0, "hash_checks": 0, "refused": 0}

# ---- registration (LibraryRegistry.apply) ----


## Registers the assets of one compiled library for the palette at `root`. `origins` is
## BiomeCompiler.compile's: {asset id: {library, file, node, sha256, bytes, path}}; an asset
## brought in from a dependency keeps its own library (and its own official flag, `official_of`
## {library id: bool}, `official` for any library not listed).
static func register_library(
	root: String, origins: Dictionary, official: bool, official_of: Dictionary = {}
) -> void:
	_lock.lock()
	for asset_id: String in origins:
		var origin: Dictionary = origins[asset_id]
		var library := String(origin["library"])
		_entries[_key(root, asset_id)] = {
			"library": library,
			"path": String(origin["path"]),
			"node": String(origin["node"]),
			"sha256": String(origin.get("sha256", "")),
			"bytes": int(origin.get("bytes", 0)),
			"official": bool(official_of.get(library, official)),
		}
		_meshes.erase(_key(root, asset_id))
		_errors.erase(_key(root, asset_id))
	_lock.unlock()


## Forgets every registration and every loaded mesh.
static func clear() -> void:
	_lock.lock()
	_entries.clear()
	_meshes.clear()
	_errors.clear()
	_lock.unlock()


## Drops the loaded meshes only (the next mesh() reads the files again).
static func clear_meshes() -> void:
	_lock.lock()
	_meshes.clear()
	_errors.clear()
	_lock.unlock()


static func reset_stats() -> void:
	stats = {"parses": 0, "cache_hits": 0, "hash_checks": 0, "refused": 0}


# ---- lookup ----


## True when the store serves `asset_id` of the palette at `root`.
static func serves(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> bool:
	_lock.lock()
	var found := _entries.has(_key(root, asset_id))
	_lock.unlock()
	return found


## The library that supplied `asset_id`, "" when the store does not serve it.
static func library_of(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	return String(_entry(root, asset_id).get("library", ""))


## The absolute GLB file of `asset_id`, "" when the store does not serve it.
static func path_of(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	return String(_entry(root, asset_id).get("path", ""))


## Every served asset id of `library_id` under `root`, sorted.
static func assets_of(
	library_id: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Array[String]:
	var out: Array[String] = []
	_lock.lock()
	for key: String in _entries:
		if key.begins_with(root + "|") and _entries[key]["library"] == library_id:
			out.append(key.substr(root.length() + 1))
	_lock.unlock()
	out.sort()
	return out


## Why the last load of `asset_id` failed, "" when it did not.
static func error_of(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	_lock.lock()
	var text := String(_errors.get(_key(root, asset_id), ""))
	_lock.unlock()
	return text


# ---- meshes ----


## The Mesh of `asset_id` supplied by `library_id`, parsed on first use and cached; null (with
## a warning, once) when the store does not serve that pair or the load is refused or fails.
## The mesh is shared: duplicate it before changing it (PaletteLibrary.resolve and instance()
## do).
static func mesh(
	library_id: String, asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Mesh:
	var entry := _entry(root, asset_id)
	if entry.is_empty() or entry["library"] != library_id:
		return null
	return mesh_for(asset_id, root)


## mesh() for whichever library supplied `asset_id`.
static func mesh_for(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Mesh:
	var key := _key(root, asset_id)
	_lock.lock()
	var entry: Dictionary = _entries.get(key, {})
	var cached := _meshes.has(key)
	var held: Mesh = _meshes.get(key)
	_lock.unlock()
	if entry.is_empty():
		return null
	if cached:
		stats["cache_hits"] += 1
		return held
	var loaded := _load(entry)
	_lock.lock()
	if loaded["mesh"] == null:
		_errors[key] = loaded["error"]
	_meshes[key] = loaded["mesh"]
	_lock.unlock()
	if loaded["mesh"] == null:
		push_warning("AssetStore: asset '%s' (%s): %s" % [asset_id, entry["library"], loaded["error"]])
	return loaded["mesh"]


## A duplicate of the asset's mesh dressed like a built-in asset: WindFoliage.apply_material
## for `category` ("tree", "grass" or "" for none). null when the mesh cannot be had.
static func instance(
	library_id: String, asset_id: String, category: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Mesh:
	var source := mesh(library_id, asset_id, root)
	if source == null:
		return null
	var copy := source.duplicate() as Mesh
	WindFoliage.apply_material(copy, category)
	return copy


## The whole check of one asset without caching a mesh: {ok, error, library}. Official libraries
## are not hashed on load; a test or a CLI calls this to hash them too.
static func verify(asset_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	var entry := _entry(root, asset_id)
	if entry.is_empty():
		return {"ok": false, "error": "not served", "library": ""}
	var read := _read_checked(entry, true)
	return {"ok": read["error"] == "", "error": read["error"], "library": entry["library"]}


## Replaces any material that is not a BaseMaterial3D with a plain StandardMaterial3D. glTF
## cannot carry a shader, so this is a guarantee more than a repair.
static func sanitize(mesh_in: Mesh) -> int:
	var replaced := 0
	for i in mesh_in.get_surface_count():
		var material := mesh_in.surface_get_material(i)
		if material != null and not material is BaseMaterial3D and mesh_in is ArrayMesh:
			(mesh_in as ArrayMesh).surface_set_material(i, StandardMaterial3D.new())
			replaced += 1
	return replaced


# ---- internals ----


static func _key(root: String, asset_id: String) -> String:
	return root + "|" + asset_id


static func _entry(root: String, asset_id: String) -> Dictionary:
	_lock.lock()
	var entry: Dictionary = (_entries.get(_key(root, asset_id), {}) as Dictionary).duplicate()
	_lock.unlock()
	return entry


## {mesh, error}: reads and checks the file, then decodes the node's mesh.
static func _load(entry: Dictionary) -> Dictionary:
	var read := _read_checked(entry, not bool(entry["official"]))
	if read["error"] != "":
		stats["refused"] += 1
		return {"mesh": null, "error": read["error"]}
	var found := _parse(read["buffer"], String(entry["path"]), String(entry["node"]))
	stats["parses"] += 1
	if found == null:
		return {"mesh": null, "error": "no mesh named '%s' in the GLB" % entry["node"]}
	sanitize(found)
	return {"mesh": found, "error": ""}


## {buffer, error}: the file's bytes, within the cap, past GlbGuard and, when `check_hash`, equal to
## the catalog's byte count and sha256.
static func _read_checked(entry: Dictionary, check_hash: bool) -> Dictionary:
	var path := String(entry["path"])
	if path == "" or not FileAccess.file_exists(path):
		return {"buffer": PackedByteArray(), "error": "the GLB '%s' is missing" % path.get_file()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"buffer": PackedByteArray(), "error": "the GLB cannot be opened"}
	if file.get_length() > MAX_FILE_BYTES:
		return {"buffer": PackedByteArray(), "error": "the GLB is over %d bytes" % MAX_FILE_BYTES}
	var buffer := file.get_buffer(file.get_length())
	file.close()
	if check_hash:
		stats["hash_checks"] += 1
		var wanted_bytes := int(entry.get("bytes", 0))
		if wanted_bytes > 0 and wanted_bytes != buffer.size():
			var text := "the GLB is %d bytes, the catalog says %d" % [buffer.size(), wanted_bytes]
			return {"buffer": buffer, "error": text}
		var wanted_hash := String(entry.get("sha256", ""))
		if wanted_hash != "" and _sha256(buffer) != wanted_hash:
			return {"buffer": buffer, "error": "the GLB does not match the catalog's sha256"}
	var guard := GlbGuard.inspect(buffer)
	if not guard["ok"]:
		return {"buffer": buffer, "error": String(guard["error"])}
	return {"buffer": buffer, "error": ""}


static func _sha256(buffer: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(buffer)
	return hashing.finish().hex_encode()


## The Mesh of `node_name` in a GLB held in `buffer`, parsed with mesh compression off.
static func _parse(buffer: PackedByteArray, path: String, node_name: String) -> Mesh:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(buffer, "", state, PaletteOverlay.FORCE_DISABLE_COMPRESSION) != OK:
		return null
	var scene := document.generate_scene(state)
	if scene == null:
		return null
	var node := GlbUtils.find_node_by_name(scene, node_name)
	if node == null:
		node = GlbUtils.find_node_by_name(scene, node_name.validate_node_name())
	var found: Mesh = null
	if node is MeshInstance3D:
		found = (node as MeshInstance3D).mesh
		if (node as Node3D).transform != Transform3D.IDENTITY:
			push_warning("AssetStore: node '%s' in %s is not at the origin" % [node_name, path])
	scene.free()
	return found
