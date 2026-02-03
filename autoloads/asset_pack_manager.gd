extends Node

## Manages discovery and loading of user asset packs.
## Scans the user_assets/ directory for packs containing manifest.json files.
## Supports both local and remote asset packs with on-demand downloading.
## Provides API for accessing assets across all loaded packs.
##
## Model Instance API:
##   get_model_instance() - Get a model Node3D (async, uses memory cache)
##   get_model_instance_sync() - Get a model Node3D (sync, uses memory cache)
##   preload_models() - Preload multiple models async with progress
##   clear_model_cache() - Clear the in-memory model cache

const AssetPackClass = preload("res://resources/asset_pack.gd")
const USER_ASSETS_DIR: String = "res://user_assets/"
const CACHE_DIR: String = "user://asset_cache/"

## Dictionary of pack_id -> AssetPack
var _packs: Dictionary = {}

## In-memory cache for loaded model scenes (path -> Node3D template or PackedScene)
## This avoids re-parsing GLB files when creating multiple tokens of the same type
var _model_cache: Dictionary = {}

## Tracks which models are currently being loaded async (path -> true)
var _loading_models: Dictionary = {}

## Signal emitted when all packs have been loaded
signal packs_loaded

## Signal emitted when a remote asset becomes available after download
signal asset_available(pack_id: String, asset_id: String, variant_id: String, local_path: String)

## Signal emitted when a remote asset download fails
signal asset_download_failed(pack_id: String, asset_id: String, variant_id: String, error: String)


func _ready() -> void:
	_discover_packs()
	_connect_resolver_signals()


## Connect to AssetResolver signals (unified resolution pipeline)
func _connect_resolver_signals() -> void:
	# AssetResolver may not be ready yet, so we defer this
	call_deferred("_deferred_connect_resolver")


func _deferred_connect_resolver() -> void:
	# Connect to AssetResolver for unified asset resolution
	if has_node("/root/AssetResolver"):
		var resolver = get_node("/root/AssetResolver")
		if not resolver.asset_resolved.is_connected(_on_resolver_asset_resolved):
			resolver.asset_resolved.connect(_on_resolver_asset_resolved)
		if not resolver.asset_failed.is_connected(_on_resolver_asset_failed):
			resolver.asset_failed.connect(_on_resolver_asset_failed)
	else:
		# Fallback: connect to individual downloaders
		push_warning("AssetPackManager: AssetResolver not found, using direct connections")
		_connect_legacy_signals()


func _connect_legacy_signals() -> void:
	# Fallback for backwards compatibility
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		if not downloader.download_completed.is_connected(_on_asset_downloaded):
			downloader.download_completed.connect(_on_asset_downloaded)
		if not downloader.download_failed.is_connected(_on_asset_download_failed):
			downloader.download_failed.connect(_on_asset_download_failed)
	
	if has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		if not streamer.asset_received.is_connected(_on_p2p_asset_received):
			streamer.asset_received.connect(_on_p2p_asset_received)
		if not streamer.asset_failed.is_connected(_on_p2p_asset_failed):
			streamer.asset_failed.connect(_on_p2p_asset_failed)


func _on_resolver_asset_resolved(_request_id: String, pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	asset_available.emit(pack_id, asset_id, variant_id, local_path)


func _on_resolver_asset_failed(_request_id: String, pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	asset_download_failed.emit(pack_id, asset_id, variant_id, error)


func _on_asset_downloaded(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	asset_available.emit(pack_id, asset_id, variant_id, local_path)


func _on_asset_download_failed(pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	# URL download failed - try P2P fallback if we're a client
	if NetworkManager.is_client() and has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		if streamer.is_enabled():
			print("AssetPackManager: URL download failed, trying P2P fallback for %s/%s/%s" % [pack_id, asset_id, variant_id])
			streamer.request_from_host(pack_id, asset_id, variant_id)
			return
	
	asset_download_failed.emit(pack_id, asset_id, variant_id, error)


func _on_p2p_asset_received(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	asset_available.emit(pack_id, asset_id, variant_id, local_path)


func _on_p2p_asset_failed(pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	asset_download_failed.emit(pack_id, asset_id, variant_id, error)


## Discover and load all asset packs from the user_assets directory
func _discover_packs() -> void:
	_packs.clear()
	
	var dir = DirAccess.open(USER_ASSETS_DIR)
	if dir == null:
		push_warning("AssetPackManager: Could not open user_assets directory: " + USER_ASSETS_DIR)
		packs_loaded.emit()
		return
	
	dir.list_dir_begin()
	var folder_name = dir.get_next()
	
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var pack_path = USER_ASSETS_DIR + folder_name + "/"
			var manifest_path = pack_path + "manifest.json"
			
			if FileAccess.file_exists(manifest_path):
				var pack = _load_pack(manifest_path, pack_path)
				if pack:
					_packs[pack.pack_id] = pack
					print("AssetPackManager: Loaded pack '" + pack.display_name + "' with " + str(pack.assets.size()) + " assets")
		
		folder_name = dir.get_next()
	
	dir.list_dir_end()
	packs_loaded.emit()


## Load a single pack from its manifest file
func _load_pack(manifest_path: String, pack_path: String):
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("AssetPackManager: Failed to open manifest: " + manifest_path)
		return null
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("AssetPackManager: Failed to parse manifest JSON: " + json.get_error_message())
		return null
	
	return AssetPackClass.from_manifest(json.data, pack_path)


## Get all loaded packs
func get_packs() -> Array:
	var result: Array = []
	for pack in _packs.values():
		result.append(pack)
	return result


## Get a pack by ID
func get_pack(pack_id: String):
	return _packs.get(pack_id)


## Check if a pack exists
func has_pack(pack_id: String) -> bool:
	return _packs.has(pack_id)


## Get all assets from a specific pack
func get_assets(pack_id: String) -> Array:
	var pack = get_pack(pack_id)
	if not pack:
		return []
	return pack.get_all_assets()


## Get a specific asset from a pack
func get_asset(pack_id: String, asset_id: String):
	var pack = get_pack(pack_id)
	if not pack:
		return null
	return pack.get_asset(asset_id)


## Get the model path for a specific asset and variant
func get_model_path(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		push_error("AssetPackManager: Pack not found: " + pack_id)
		return ""
	return pack.get_model_path(asset_id, variant_id)


## Get the icon path for a specific asset and variant
func get_icon_path(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		push_error("AssetPackManager: Pack not found: " + pack_id)
		return ""
	return pack.get_icon_path(asset_id, variant_id)


## Resolve the model path, checking cache first, then local, then triggering download
## Returns the local path if available (local or cached), empty string if needs download
## If needs download, automatically queues it and emits asset_available when ready
func resolve_model_path(pack_id: String, asset_id: String, variant_id: String = "default", priority: int = 100) -> String:
	# Use AssetResolver if available
	if has_node("/root/AssetResolver"):
		var resolver = get_node("/root/AssetResolver")
		# Try sync resolution first (local + cache)
		var sync_path = resolver.resolve_model_sync(pack_id, asset_id, variant_id)
		if sync_path != "":
			return sync_path
		# Start async resolution (downloads)
		resolver.resolve_model_async(pack_id, asset_id, variant_id, priority)
		return ""
	
	# Fallback: original implementation
	var pack = get_pack(pack_id)
	if not pack:
		push_error("AssetPackManager: Pack not found: " + pack_id)
		return ""
	
	# 1. Check local path first (for local packs)
	if pack.base_path != "":
		var local_path = pack.get_model_path(asset_id, variant_id)
		if local_path != "" and ResourceLoader.exists(local_path):
			return local_path
	
	# 2. Check cache (for previously downloaded remote assets)
	var cached_path = _get_cached_model_path(pack_id, asset_id, variant_id)
	if cached_path != "":
		return cached_path
	
	# 3. Try URL-based download if available
	var url = pack.get_model_url(asset_id, variant_id)
	if url != "":
		_request_download(pack_id, asset_id, variant_id, url, priority, "model")
		return ""
	
	# 4. Try P2P streaming as fallback (if we're a client)
	if NetworkManager.is_client() and has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		if streamer.is_enabled():
			streamer.request_from_host(pack_id, asset_id, variant_id, priority)
	
	return ""


## Resolve the icon path, checking cache first, then local, then triggering download
func resolve_icon_path(pack_id: String, asset_id: String, variant_id: String = "default", priority: int = 100) -> String:
	# Use AssetResolver if available
	if has_node("/root/AssetResolver"):
		var resolver = get_node("/root/AssetResolver")
		var sync_path = resolver.resolve_icon_sync(pack_id, asset_id, variant_id)
		if sync_path != "":
			return sync_path
		resolver.resolve_icon_async(pack_id, asset_id, variant_id, priority)
		return ""
	
	# Fallback: original implementation
	var pack = get_pack(pack_id)
	if not pack:
		return ""
	
	# 1. Check local path first
	if pack.base_path != "":
		var local_path = pack.get_icon_path(asset_id, variant_id)
		if local_path != "" and ResourceLoader.exists(local_path):
			return local_path
	
	# 2. Check cache
	var cached_path = _get_cached_icon_path(pack_id, asset_id, variant_id)
	if cached_path != "":
		return cached_path
	
	# 3. Need to download
	var url = pack.get_icon_url(asset_id, variant_id)
	if url != "":
		_request_download(pack_id, asset_id, variant_id, url, priority, "icon")
	
	return ""


## Check if an asset is available locally (either local pack or cached)
func is_asset_available(pack_id: String, asset_id: String, variant_id: String = "default") -> bool:
	var pack = get_pack(pack_id)
	if not pack:
		return false
	
	# Check local
	if pack.base_path != "":
		var local_path = pack.get_model_path(asset_id, variant_id)
		if local_path != "" and ResourceLoader.exists(local_path):
			return true
	
	# Check cache
	return _get_cached_model_path(pack_id, asset_id, variant_id) != ""


## Check if an asset needs to be downloaded
func needs_download(pack_id: String, asset_id: String, variant_id: String = "default") -> bool:
	if is_asset_available(pack_id, asset_id, variant_id):
		return false
	
	var pack = get_pack(pack_id)
	if not pack:
		return false
	
	# Check if URL download is available
	if pack.get_model_url(asset_id, variant_id) != "":
		return true
	
	# Check if P2P streaming is available (client connected to host)
	if NetworkManager.is_client() and has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		return streamer.is_enabled()
	
	return false


## Get the cached model path if it exists
func _get_cached_model_path(pack_id: String, asset_id: String, variant_id: String) -> String:
	# Try AssetCacheManager first (unified cache)
	if has_node("/root/AssetCacheManager"):
		var cache_manager = get_node("/root/AssetCacheManager")
		return cache_manager.get_cached_path(pack_id, asset_id, variant_id, "model")
	
	# Fallback to AssetDownloader
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		return downloader.get_cached_path(pack_id, asset_id, variant_id, "model")
	
	return ""


## Get the cached icon path if it exists
func _get_cached_icon_path(pack_id: String, asset_id: String, variant_id: String) -> String:
	# Try AssetCacheManager first (unified cache)
	if has_node("/root/AssetCacheManager"):
		var cache_manager = get_node("/root/AssetCacheManager")
		return cache_manager.get_cached_path(pack_id, asset_id, variant_id, "icon")
	
	# Fallback to AssetDownloader
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		return downloader.get_cached_path(pack_id, asset_id, variant_id, "icon")
	
	return ""


## Request a download from the AssetDownloader
func _request_download(pack_id: String, asset_id: String, variant_id: String, url: String, priority: int, file_type: String) -> void:
	if not has_node("/root/AssetDownloader"):
		push_error("AssetPackManager: AssetDownloader not available for remote asset")
		return
	var downloader = get_node("/root/AssetDownloader")
	downloader.request_download(pack_id, asset_id, variant_id, url, priority, file_type)


## Get the model URL for a specific asset (for external use or debugging)
func get_model_url(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		return ""
	return pack.get_model_url(asset_id, variant_id)


## Get the icon URL for a specific asset
func get_icon_url(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	var pack = get_pack(pack_id)
	if not pack:
		return ""
	return pack.get_icon_url(asset_id, variant_id)


## Register a remote pack from a manifest dictionary
## This allows adding packs that don't exist locally
func register_remote_pack(manifest: Dictionary) -> bool:
	var pack = AssetPackClass.from_manifest(manifest, "")
	if pack.pack_id == "":
		push_error("AssetPackManager: Remote pack manifest missing pack_id")
		return false
	
	if _packs.has(pack.pack_id):
		push_warning("AssetPackManager: Overwriting existing pack: " + pack.pack_id)
	
	_packs[pack.pack_id] = pack
	print("AssetPackManager: Registered remote pack '%s' with %d assets" % [pack.display_name, pack.assets.size()])
	return true


## Load a remote pack from a URL pointing to manifest.json
## This is async - the pack will be available after download completes
func load_remote_pack_from_url(manifest_url: String) -> void:
	if not has_node("/root/AssetDownloader"):
		push_error("AssetPackManager: Cannot load remote pack - AssetDownloader not available")
		return
	
	# Create a temporary HTTPRequest to fetch the manifest
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_manifest_downloaded.bind(http_request))
	
	var error = http_request.request(manifest_url)
	if error != OK:
		push_error("AssetPackManager: Failed to request manifest from " + manifest_url)
		http_request.queue_free()


func _on_manifest_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("AssetPackManager: Failed to download remote manifest")
		return
	
	var json_text = body.get_string_from_utf8()
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		push_error("AssetPackManager: Failed to parse remote manifest JSON")
		return
	
	if register_remote_pack(json.data):
		packs_loaded.emit()


## Get all variant IDs for a specific asset
func get_variants(pack_id: String, asset_id: String) -> Array[String]:
	var asset = get_asset(pack_id, asset_id)
	if not asset:
		return []
	return asset.get_variant_ids()


## Get the display name for an asset
func get_asset_display_name(pack_id: String, asset_id: String) -> String:
	var asset = get_asset(pack_id, asset_id)
	if not asset:
		return "Unknown"
	return asset.display_name


## Get all assets across all packs as a flat list
## Returns array of dictionaries with pack_id, asset_id, and asset reference
func get_all_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pack in _packs.values():
		for asset in pack.get_all_assets():
			result.append({
				"pack_id": pack.pack_id,
				"pack_name": pack.display_name,
				"asset_id": asset.asset_id,
				"asset": asset
			})
	return result


## Reload all packs (useful for hot-reloading during development)
func reload_packs() -> void:
	_discover_packs()


# =============================================================================
# MODEL INSTANCE API (with in-memory caching)
# =============================================================================

## Get a model instance for an asset (async, uses cache)
## Returns a new Node3D instance (duplicated from cache if available)
## Handles path resolution, loading, and caching automatically
## @param pack_id: The pack identifier
## @param asset_id: The asset identifier
## @param variant_id: The variant (default, shiny, etc.)
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes (for maps)
## @return: A Node3D model instance, or null on failure
func get_model_instance(pack_id: String, asset_id: String, variant_id: String = "default", create_static_bodies: bool = false) -> Node3D:
	var path = resolve_model_path(pack_id, asset_id, variant_id)
	if path == "":
		# Asset needs to be downloaded - caller should wait for asset_available signal
		return null
	
	return await get_model_instance_from_path(path, create_static_bodies)


## Get a model instance from a resolved path (async, uses cache)
## @param path: The resolved model path (res:// or user://)
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes
## @return: A Node3D model instance, or null on failure
func get_model_instance_from_path(path: String, create_static_bodies: bool = false) -> Node3D:
	var cache_key = path + ("_static" if create_static_bodies else "")
	
	# Check cache first
	if _model_cache.has(cache_key):
		return _get_instance_from_cache(cache_key)
	
	# Wait if another call is already loading this model
	while _loading_models.has(cache_key):
		await get_tree().process_frame
		if _model_cache.has(cache_key):
			return _get_instance_from_cache(cache_key)
	
	# Mark as loading
	_loading_models[cache_key] = true
	
	var model: Node3D = null
	
	# Load based on path type
	if path.begins_with("user://") and path.ends_with(".glb"):
		# GLB file - use async loading
		var result = await GlbUtils.load_glb_with_processing_async(path, create_static_bodies)
		if result.success:
			model = result.scene
	else:
		# res:// path - use threaded resource loading
		var load_status = ResourceLoader.load_threaded_request(path)
		if load_status == OK:
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			var resource = ResourceLoader.load_threaded_get(path)
			if resource is PackedScene:
				# Cache the PackedScene itself
				_model_cache[cache_key] = resource
				_loading_models.erase(cache_key)
				return resource.instantiate() as Node3D
	
	# Cache the loaded model as a template
	if model:
		_model_cache[cache_key] = model
		_loading_models.erase(cache_key)
		# Return a duplicate, keep original as template
		return model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	
	_loading_models.erase(cache_key)
	return null


## Get a model instance synchronously (uses cache, blocks if not cached)
## Prefer get_model_instance() for better performance
func get_model_instance_sync(pack_id: String, asset_id: String, variant_id: String = "default", create_static_bodies: bool = false) -> Node3D:
	var path = resolve_model_path(pack_id, asset_id, variant_id)
	if path == "":
		return null
	
	return get_model_instance_from_path_sync(path, create_static_bodies)


## Get a model instance from a path synchronously
func get_model_instance_from_path_sync(path: String, create_static_bodies: bool = false) -> Node3D:
	var cache_key = path + ("_static" if create_static_bodies else "")
	
	# Check cache first
	if _model_cache.has(cache_key):
		return _get_instance_from_cache(cache_key)
	
	var model: Node3D = null
	
	# Load based on path type
	if path.begins_with("user://") and path.ends_with(".glb"):
		model = GlbUtils.load_glb_with_processing(path, create_static_bodies)
	else:
		if ResourceLoader.exists(path):
			var resource = load(path)
			if resource is PackedScene:
				_model_cache[cache_key] = resource
				return resource.instantiate() as Node3D
	
	# Cache the loaded model as a template
	if model:
		_model_cache[cache_key] = model
		return model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	
	return null


## Get an instance from the cache (handles both PackedScene and Node3D templates)
func _get_instance_from_cache(cache_key: String) -> Node3D:
	var cached = _model_cache[cache_key]
	
	if cached is PackedScene:
		return cached.instantiate() as Node3D
	
	if cached is Node3D and is_instance_valid(cached):
		return cached.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	
	# Invalid cache entry
	_model_cache.erase(cache_key)
	return null


## Preload multiple models asynchronously (for batch loading before spawning)
## @param assets: Array of dictionaries with pack_id, asset_id, variant_id keys
## @param progress_callback: Optional callback(loaded: int, total: int) for progress
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes
## @return: Number of models successfully loaded
func preload_models(assets: Array, progress_callback: Callable = Callable(), create_static_bodies: bool = false) -> int:
	# Collect unique paths
	var unique_paths: Dictionary = {}
	for asset in assets:
		if not asset is Dictionary:
			continue
		var pack_id = asset.get("pack_id", "")
		var asset_id = asset.get("asset_id", "")
		var variant_id = asset.get("variant_id", "default")
		
		if pack_id == "" or asset_id == "":
			continue
		
		var path = resolve_model_path(pack_id, asset_id, variant_id)
		if path != "":
			var cache_key = path + ("_static" if create_static_bodies else "")
			unique_paths[cache_key] = path
	
	var total = unique_paths.size()
	var loaded = 0
	
	for cache_key in unique_paths:
		var path = unique_paths[cache_key]
		
		# Skip if already cached
		if _model_cache.has(cache_key):
			loaded += 1
			if progress_callback.is_valid():
				progress_callback.call(loaded, total)
			continue
		
		# Load the model
		var model = await get_model_instance_from_path(path, create_static_bodies)
		if model:
			# We got a duplicate - free it since we just wanted to populate the cache
			model.queue_free()
			loaded += 1
		
		if progress_callback.is_valid():
			progress_callback.call(loaded, total)
		
		# Yield to keep UI responsive
		await get_tree().process_frame
	
	return loaded


## Clear the in-memory model cache (call when switching levels to free memory)
func clear_model_cache() -> void:
	for cache_key in _model_cache:
		var cached = _model_cache[cache_key]
		# Free Node3D templates (PackedScene doesn't need explicit freeing)
		if cached is Node3D and is_instance_valid(cached):
			cached.free()
	
	_model_cache.clear()
	_loading_models.clear()
	print("AssetPackManager: Model cache cleared")
