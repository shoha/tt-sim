@tool
extends RefCounted

## The export half of the shipped surface bakes (card exportbake, 2026-11-09). An exported game
## has no image compressor (SurfaceBake's class doc), so without this a player's game draws the
## official libraries' surfaces uncompressed: about three times the texture memory of BC (+207 MB
## for a 16-layer map, measured on the forest and test_map), a re-decode of most maps on every
## open, and an error per map. The export plugin (plugin.gd) runs entries() and bytes_for() in the
## editor, which compresses, and adds each map's TTIMG bytes to the pack at
## SurfaceCache.shipped_path_for; the game's SurfaceStore.load_map reads them first.
##
## Only the kinds a game cannot make are shipped (KINDS: albedo BC7, normal BC5, ORM BC1). A height
## map bakes to L8 in the game exactly as in the editor and is cached there after its first use.
## The key is the cache's (SurfaceStore.files_hash of the set's own files), so a pack whose maps
## changed can never meet a stale bake. Pure of the scene tree; tests call it on scratch folders.

const KINDS: Array[String] = ["albedo", "normal", "orm"]
const LIBRARIES_ROOT := "res://libraries"
## The editor's own raw cache (SurfaceCache's layout). Named here, not read from SurfaceCache.root:
## in the editor a non-tool script's static vars are never initialised, so that one is empty.
const EDITOR_CACHE := "user://library_cache"


## One entry per map to ship, {library, name, kind, file, hash, path}, for every surface set of
## every library folder (one with a library.json naming its id) under `libraries_root`, sorted by
## folder, surface and kind order; `path` is the map's place under `under` (the pack's root).
static func entries(
	libraries_root: String = LIBRARIES_ROOT, under: String = SurfaceCache.SHIPPED_ROOT
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var folders := DirAccess.get_directories_at(libraries_root)
	folders.sort()
	for folder in folders:
		var library_dir := libraries_root.path_join(folder)
		var library_id := library_id_of(library_dir)
		if library_id == "":
			continue
		var surfaces_dir := library_dir.path_join("surfaces")
		var names := DirAccess.get_directories_at(surfaces_dir)
		names.sort()
		for name in names:
			var dir := surfaces_dir.path_join(name)
			var files := {}
			for kind in SurfaceBake.KINDS:
				var file := SurfaceStore.map_file(dir, kind)
				if file != "":
					files[kind] = file
			if files.is_empty():
				continue
			var hash_text := SurfaceStore.files_hash(name, files)
			for kind in KINDS:
				if files.has(kind):
					out.append(
						{
							"library": library_id,
							"name": name,
							"kind": kind,
							"file": String(files[kind]),
							"hash": hash_text,
							"path": SurfaceCache.shipped_path_for(library_id, hash_text, name, kind, under),
						}
					)
	return out


## The id in `library_dir`/library.json, "" when there is none.
static func library_id_of(library_dir: String) -> String:
	var path := library_dir.path_join("library.json")
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ""
	return String((parsed as Dictionary).get("id", ""))


## The TTIMG bytes of `entry`'s map baked to its compressed format: the editor's own cache entry
## when this engine baked it already (a developer's machine), else decoded and baked now (about
## 0.2 s for a 1024 albedo). Empty when the map cannot be decoded or this binary cannot compress.
static func bytes_for(entry: Dictionary, cache_root: String = EDITOR_CACHE) -> PackedByteArray:
	var kind := String(entry["kind"])
	var cache_path := SurfaceCache.shipped_path_for(
		String(entry["library"]), String(entry["hash"]), String(entry["name"]), kind, cache_root
	)
	var image := SurfaceCache.read(cache_path)
	if image == null or image.get_format() != SurfaceBake.format_of(kind):
		var file := String(entry["file"])
		var decoded := SurfaceBake.decode(FileAccess.get_file_as_bytes(file), file.get_extension())
		image = SurfaceBake.bake(decoded, kind) if decoded != null else null
	if image == null or image.get_format() != SurfaceBake.format_of(kind):
		return PackedByteArray()
	return SurfaceCache.encode(image)
