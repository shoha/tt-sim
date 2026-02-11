extends Node

## Unified cache manager for asset downloads.
## Single source of truth for all cached assets (HTTP downloads and P2P streaming).
## Provides LRU eviction to prevent unbounded disk growth.
##
## Architecture:
##   - Manages cache at user://asset_cache/
##   - Tracks file sizes and access times for LRU eviction
##   - Emits signals when cache is updated
##   - Thread-safe cache operations
##
## Usage:
##   AssetCacheManager.get_cached_path("pack", "asset", "variant") -> path or ""
##   AssetCacheManager.store_asset("pack", "asset", "variant", data) -> stored path
##   AssetCacheManager.has_cached("pack", "asset", "variant") -> bool

const CACHE_DIR := "user://asset_cache/"
const MAX_CACHE_SIZE_MB := 500
const CACHE_INDEX_FILE := "user://asset_cache_index.json"

## Emitted when an asset is added to the cache
signal cache_updated(cache_key: String, path: String)

## Emitted when assets are evicted from cache
signal cache_evicted(cache_keys: Array[String])

## Emitted when cache is cleared
signal cache_cleared


## Cache entry structure
class CacheEntry:
	var path: String
	var size_bytes: int
	var last_access: float  # Unix timestamp
	var file_type: String  # "model" or "icon"

	func _init(p: String = "", s: int = 0, t: String = "model") -> void:
		path = p
		size_bytes = s
		last_access = Time.get_unix_time_from_system()
		file_type = t

	func to_dict() -> Dictionary:
		return {
			"path": path,
			"size_bytes": size_bytes,
			"last_access": last_access,
			"file_type": file_type
		}

	static func from_dict(data: Dictionary) -> CacheEntry:
		var entry = CacheEntry.new()
		entry.path = data.get("path", "")
		entry.size_bytes = data.get("size_bytes", 0)
		entry.last_access = data.get("last_access", 0.0)
		entry.file_type = data.get("file_type", "model")
		return entry


## Cache index: cache_key -> CacheEntry
var _cache_index: Dictionary = {}

## Total size of cached files in bytes
var _total_cache_size: int = 0

## Lock for thread safety
var _cache_mutex := Mutex.new()


func _ready() -> void:
	_ensure_cache_dir()
	_load_cache_index()
	_validate_cache_index()


# =============================================================================
# PUBLIC API
# =============================================================================


## Get the cached path for an asset (model)
## Returns empty string if not cached
func get_cached_path(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> String:
	var key = _make_key(pack_id, asset_id, variant_id, file_type)

	_cache_mutex.lock()
	var entry: CacheEntry = _cache_index.get(key)
	_cache_mutex.unlock()

	if not entry:
		return ""

	# Verify file still exists
	if not FileAccess.file_exists(entry.path):
		_remove_from_index(key)
		return ""

	# Update access time
	_update_access_time(key)
	return entry.path


## Check if an asset is cached
func has_cached(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> bool:
	return get_cached_path(pack_id, asset_id, variant_id, file_type) != ""


## Store an asset in the cache
## Returns the cache path on success, empty string on failure
func store_asset(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	data: PackedByteArray,
	file_type: String = "model"
) -> String:
	var key = _make_key(pack_id, asset_id, variant_id, file_type)
	var cache_path = _get_cache_path(pack_id, asset_id, variant_id, file_type)

	# Ensure subdirectory exists
	var cache_dir = cache_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(cache_dir):
		var err = DirAccess.make_dir_recursive_absolute(cache_dir)
		if err != OK:
			push_error("AssetCacheManager: Failed to create cache directory: %s" % cache_dir)
			return ""

	# Check if we need to evict before storing
	var data_size = data.size()
	_evict_if_needed(data_size)

	# Write the file
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if not file:
		push_error("AssetCacheManager: Failed to open cache file for writing: %s" % cache_path)
		return ""

	file.store_buffer(data)
	file.close()

	# Add to index
	_add_to_index(key, cache_path, data_size, file_type)

	print("AssetCacheManager: Cached %s (%d bytes)" % [key, data_size])
	cache_updated.emit(key, cache_path)

	return cache_path


## Store an asset that's already been written to disk (by HTTP download)
## Call this to register an externally-written file in the cache index
func register_cached_file(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_path: String,
	file_type: String = "model"
) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("AssetCacheManager: Cannot register non-existent file: %s" % file_path)
		return

	var key = _make_key(pack_id, asset_id, variant_id, file_type)
	var file_size = FileAccess.open(file_path, FileAccess.READ).get_length()

	_add_to_index(key, file_path, file_size, file_type)
	cache_updated.emit(key, file_path)


## Get the expected cache path for an asset (whether it exists or not)
func get_expected_cache_path(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> String:
	return _get_cache_path(pack_id, asset_id, variant_id, file_type)


## Remove a specific asset from cache
func remove_cached(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> void:
	var key = _make_key(pack_id, asset_id, variant_id, file_type)

	_cache_mutex.lock()
	var entry: CacheEntry = _cache_index.get(key)
	_cache_mutex.unlock()

	if entry:
		# Delete the file
		if FileAccess.file_exists(entry.path):
			DirAccess.remove_absolute(entry.path)
		_remove_from_index(key)


## Clear the entire cache
func clear_cache() -> void:
	_cache_mutex.lock()

	# Delete all cached files
	for key in _cache_index:
		var entry: CacheEntry = _cache_index[key]
		if FileAccess.file_exists(entry.path):
			DirAccess.remove_absolute(entry.path)

	_cache_index.clear()
	_total_cache_size = 0

	_cache_mutex.unlock()

	_save_cache_index()

	# Clean up empty directories
	_cleanup_empty_dirs(CACHE_DIR)

	print("AssetCacheManager: Cache cleared")
	cache_cleared.emit()


## Get current cache size in bytes
func get_cache_size_bytes() -> int:
	return _total_cache_size


## Get current cache size in MB
func get_cache_size_mb() -> float:
	return float(_total_cache_size) / (1024.0 * 1024.0)


## Get cache usage as a percentage (0.0 to 1.0)
func get_cache_usage() -> float:
	var max_bytes = MAX_CACHE_SIZE_MB * 1024 * 1024
	return float(_total_cache_size) / float(max_bytes)


# =============================================================================
# PRIVATE HELPERS
# =============================================================================


## Create a unique key for a cached asset
func _make_key(pack_id: String, asset_id: String, variant_id: String, file_type: String) -> String:
	return "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]


## Get the cache path for an asset
func _get_cache_path(
	pack_id: String, asset_id: String, variant_id: String, file_type: String
) -> String:
	var extension = ".glb" if file_type == "model" else ".png"
	return CACHE_DIR + "%s/%s/%s%s" % [pack_id, asset_id, variant_id, extension]


## Ensure the cache directory exists
func _ensure_cache_dir() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)


## Add an entry to the cache index
func _add_to_index(key: String, path: String, size: int, file_type: String) -> void:
	_cache_mutex.lock()

	# Remove old entry if exists (updating)
	if _cache_index.has(key):
		var old_entry: CacheEntry = _cache_index[key]
		_total_cache_size -= old_entry.size_bytes

	var entry = CacheEntry.new(path, size, file_type)
	_cache_index[key] = entry
	_total_cache_size += size

	_cache_mutex.unlock()

	_save_cache_index()


## Remove an entry from the cache index
func _remove_from_index(key: String) -> void:
	_cache_mutex.lock()

	if _cache_index.has(key):
		var entry: CacheEntry = _cache_index[key]
		_total_cache_size -= entry.size_bytes
		_cache_index.erase(key)

	_cache_mutex.unlock()

	_save_cache_index()


## Update access time for an entry (for LRU tracking)
func _update_access_time(key: String) -> void:
	_cache_mutex.lock()

	if _cache_index.has(key):
		var entry: CacheEntry = _cache_index[key]
		entry.last_access = Time.get_unix_time_from_system()

	_cache_mutex.unlock()


## Evict old entries if needed to make room for new data
func _evict_if_needed(incoming_size: int) -> void:
	var max_bytes = MAX_CACHE_SIZE_MB * 1024 * 1024
	var target_size = max_bytes - incoming_size

	if _total_cache_size <= target_size:
		return

	# Get all entries sorted by last access (oldest first)
	var entries: Array[Dictionary] = []

	_cache_mutex.lock()
	for key in _cache_index:
		var entry: CacheEntry = _cache_index[key]
		entries.append({"key": key, "entry": entry})
	_cache_mutex.unlock()

	entries.sort_custom(func(a, b): return a.entry.last_access < b.entry.last_access)

	# Evict until we're under target
	var evicted_keys: Array[String] = []
	for item in entries:
		if _total_cache_size <= target_size:
			break

		var key: String = item.key
		var entry: CacheEntry = item.entry

		# Delete the file
		if FileAccess.file_exists(entry.path):
			DirAccess.remove_absolute(entry.path)

		_cache_mutex.lock()
		_total_cache_size -= entry.size_bytes
		_cache_index.erase(key)
		_cache_mutex.unlock()

		evicted_keys.append(key)
		print(
			(
				"AssetCacheManager: Evicted %s (%.1f MB freed)"
				% [key, entry.size_bytes / 1024.0 / 1024.0]
			)
		)

	if evicted_keys.size() > 0:
		_save_cache_index()
		cache_evicted.emit(evicted_keys)


## Save cache index to disk
func _save_cache_index() -> void:
	var data: Dictionary = {}

	_cache_mutex.lock()
	for key in _cache_index:
		var entry: CacheEntry = _cache_index[key]
		data[key] = entry.to_dict()
	_cache_mutex.unlock()

	var file = FileAccess.open(CACHE_INDEX_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))
		file.close()


## Load cache index from disk
func _load_cache_index() -> void:
	if not FileAccess.file_exists(CACHE_INDEX_FILE):
		return

	var file = FileAccess.open(CACHE_INDEX_FILE, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_warning("AssetCacheManager: Failed to parse cache index")
		return

	var data: Dictionary = json.data

	_cache_mutex.lock()
	_cache_index.clear()
	_total_cache_size = 0

	for key in data:
		var entry = CacheEntry.from_dict(data[key])
		_cache_index[key] = entry
		_total_cache_size += entry.size_bytes

	_cache_mutex.unlock()

	print(
		(
			"AssetCacheManager: Loaded cache index with %d entries (%.1f MB)"
			% [_cache_index.size(), get_cache_size_mb()]
		)
	)


## Validate cache index against actual files
func _validate_cache_index() -> void:
	var invalid_keys: Array[String] = []

	_cache_mutex.lock()
	for key in _cache_index:
		var entry: CacheEntry = _cache_index[key]
		if not FileAccess.file_exists(entry.path):
			invalid_keys.append(key)
	_cache_mutex.unlock()

	# Remove invalid entries
	for key in invalid_keys:
		_remove_from_index(key)

	if invalid_keys.size() > 0:
		print("AssetCacheManager: Removed %d stale cache entries" % invalid_keys.size())


## Clean up empty directories recursively
func _cleanup_empty_dirs(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_cleanup_empty_dirs(full_path)
			# Check if subdir is now empty
			var subdir = DirAccess.open(full_path)
			if subdir:
				subdir.list_dir_begin()
				if subdir.get_next() == "":
					DirAccess.remove_absolute(full_path)
				subdir.list_dir_end()
		file_name = dir.get_next()
	dir.list_dir_end()
