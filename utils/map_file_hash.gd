class_name MapFileHash
extends RefCounted

## Content hashes of a level's map files (map.glb, map.ttmap), so a client can tell whether
## the copy it cached from an earlier session is still the host's current file.
##
## The host puts one SHA-256 per map file into the level dictionary it broadcasts
## (LevelData.map_hashes, key "map_hashes", keyed by streaming variant id: "map", "ttmap").
## A client compares that with the hash stored beside its cache entry and downloads again on
## a mismatch. Before this, the cache was keyed by level folder alone and never
## invalidated, so a map the host re-saved was never picked up.
##
## Hashing streams the file in chunks and is cached per path, keyed by the file's size and
## modification time, so the host hashes each file version once per session, not per
## broadcast or per request. Anything that rewrites a map file calls invalidate() as well,
## because modification times have one-second resolution.
##
## Hashes arrive from the host peer, so sanitize() treats them as untrusted: only the two
## known variant keys, only 64-character lowercase hex values.

const HASHES_KEY := "map_hashes"
const HASH_LENGTH := 64
const _CHUNK_BYTES := 1 << 20

## path -> {"size": int, "mtime": int, "hash": String}
static var _cache: Dictionary = {}


## True when `value` is a SHA-256 hex digest as this class writes it.
static func is_valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != HASH_LENGTH:
		return false
	for c in value:
		if not c in "0123456789abcdef":
			return false
	return true


## The well-formed entries of an untrusted `map_hashes` value: variant id -> hash, only for
## the two map variants. Anything else (wrong type, unknown key, malformed hash) is dropped.
static func sanitize(raw: Variant) -> Dictionary:
	var clean := {}
	if not raw is Dictionary:
		return clean
	for variant in [Paths.LEVEL_MAP_VARIANT, Paths.LEVEL_MAP_DOCUMENT_VARIANT]:
		var value: Variant = raw.get(variant)
		if is_valid_hash(value):
			clean[variant] = value
	return clean


## SHA-256 of `data` as lowercase hex.
static func hash_bytes(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


## SHA-256 of the file at `path`, streamed; "" when it cannot be read. Uncached.
static func hash_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var remaining := file.get_length()
	while remaining > 0:
		var chunk := file.get_buffer(mini(remaining, _CHUNK_BYTES))
		if chunk.is_empty():
			return ""
		context.update(chunk)
		remaining -= chunk.size()
	return context.finish().hex_encode()


## hash_file(), remembered per path until the file's size or modification time changes or
## invalidate() is called for it. "" when the file is missing.
static func hash_file_cached(path: String) -> String:
	if not FileAccess.file_exists(path):
		_cache.erase(path)
		return ""
	var size := _file_size(path)
	var mtime := FileAccess.get_modified_time(path)
	var entry: Dictionary = _cache.get(path, {})
	if entry.get("size", -1) == size and entry.get("mtime", -1) == mtime:
		return entry["hash"]
	var digest := hash_file(path)
	if digest != "":
		_cache[path] = {"size": size, "mtime": mtime, "hash": digest}
	return digest


## Forgets the cached hash of `path` (call after rewriting the file).
static func invalidate(path: String) -> void:
	_cache.erase(path)


## Variant id -> hash for the map files a level dictionary names, read from the host's own
## level folder. Only folder levels have files a client downloads; a res:// map ships with
## the game and gets no hash.
static func hashes_for_level_dict(level_dict: Dictionary) -> Dictionary:
	var hashes := {}
	var folder: Variant = level_dict.get("level_folder", "")
	if not folder is String or folder == "":
		return hashes
	var map_path: Variant = level_dict.get("map_path", "")
	if map_path is String and map_path != "" and not map_path.begins_with("res://"):
		var digest := hash_file_cached(Paths.get_level_map_path(folder))
		if digest != "":
			hashes[Paths.LEVEL_MAP_VARIANT] = digest
	var document: Variant = level_dict.get("map_document", "")
	if document is String and document != "":
		var digest := hash_file_cached(Paths.get_level_map_document_path(folder))
		if digest != "":
			hashes[Paths.LEVEL_MAP_DOCUMENT_VARIANT] = digest
	return hashes


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else -1
