extends Node

## Manages discovery and loading of user asset packs.
## Scans the user_assets/ directory for packs containing manifest.json files.
## Supports both local and remote asset packs with on-demand downloading.
## Provides API for accessing assets across all loaded packs.

const AssetPackClass = preload("res://resources/asset_pack.gd")
const USER_ASSETS_DIR: String = "res://user_assets/"
const CACHE_DIR: String = "user://asset_cache/"

## Dictionary of pack_id -> AssetPack
var _packs: Dictionary = {}

## Signal emitted when all packs have been loaded
signal packs_loaded

## Signal emitted when a remote asset becomes available after download
signal asset_available(pack_id: String, asset_id: String, variant_id: String, local_path: String)

## Signal emitted when a remote asset download fails
signal asset_download_failed(pack_id: String, asset_id: String, variant_id: String, error: String)


func _ready() -> void:
	_discover_packs()
	_connect_downloader_signals()


## Connect to AssetDownloader signals
func _connect_downloader_signals() -> void:
	# AssetDownloader may not be ready yet, so we defer this
	call_deferred("_deferred_connect_downloader")


func _deferred_connect_downloader() -> void:
	# Connect to AssetDownloader
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		if not downloader.download_completed.is_connected(_on_asset_downloaded):
			downloader.download_completed.connect(_on_asset_downloaded)
		if not downloader.download_failed.is_connected(_on_asset_download_failed):
			downloader.download_failed.connect(_on_asset_download_failed)
	else:
		push_warning("AssetPackManager: AssetDownloader autoload not found")
	
	# Connect to AssetStreamer (P2P fallback)
	if has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		if not streamer.asset_received.is_connected(_on_p2p_asset_received):
			streamer.asset_received.connect(_on_p2p_asset_received)
		if not streamer.asset_failed.is_connected(_on_p2p_asset_failed):
			streamer.asset_failed.connect(_on_p2p_asset_failed)
	else:
		push_warning("AssetPackManager: AssetStreamer autoload not found")


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
	if not has_node("/root/AssetDownloader"):
		return ""
	var downloader = get_node("/root/AssetDownloader")
	return downloader.get_cached_path(pack_id, asset_id, variant_id, "model")


## Get the cached icon path if it exists
func _get_cached_icon_path(pack_id: String, asset_id: String, variant_id: String) -> String:
	if not has_node("/root/AssetDownloader"):
		return ""
	var downloader = get_node("/root/AssetDownloader")
	return downloader.get_cached_path(pack_id, asset_id, variant_id, "icon")


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
