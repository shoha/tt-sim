extends Node

## Asset resolution pipeline for locating and loading assets.
## Provides a unified interface for resolving assets through multiple sources:
##   1. Local pack files (res://user_assets/)
##   2. Disk cache (user://asset_cache/)
##   3. HTTP download (from URLs in manifest)
##   4. P2P streaming (from host in multiplayer)
##
## Architecture:
##   - Single entry point for asset resolution
##   - Async resolution with signal-based completion
##   - Automatic fallback through resolution stages
##   - Integrated with AssetCacheManager for unified caching
##
## Usage:
##   var request_id = AssetResolver.resolve_model_async(pack_id, asset_id, variant_id)
##   AssetResolver.asset_resolved.connect(_on_asset_resolved)
##   # or
##   var path = AssetResolver.resolve_model_sync(pack_id, asset_id, variant_id) # blocks if not available

## Emitted when async resolution completes successfully
signal asset_resolved(request_id: String, pack_id: String, asset_id: String, variant_id: String, local_path: String)

## Emitted when async resolution fails
signal asset_failed(request_id: String, pack_id: String, asset_id: String, variant_id: String, error: String)

## Emitted during resolution (for progress tracking)
signal resolution_progress(request_id: String, stage: String, progress: float)

## Resolution stages
enum Stage {
	LOCAL, ## Checking local pack files
	CACHE, ## Checking disk cache
	HTTP, ## Downloading from URL
	P2P, ## Streaming from host
	FAILED ## All sources exhausted
}


## Pending resolution requests
class ResolutionRequest:
	var request_id: String
	var pack_id: String
	var asset_id: String
	var variant_id: String
	var file_type: String # "model" or "icon"
	var priority: int
	var stage: Stage = Stage.LOCAL
	var created_at: float
	
	func _init(p_id: String, a_id: String, v_id: String, f_type: String = "model", prio: int = 100) -> void:
		request_id = _generate_id()
		pack_id = p_id
		asset_id = a_id
		variant_id = v_id
		file_type = f_type
		priority = prio
		created_at = Time.get_unix_time_from_system()
	
	func get_key() -> String:
		return "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]
	
	static func _generate_id() -> String:
		return "%d_%d" % [Time.get_ticks_msec(), randi()]


## Active resolution requests (request_id -> ResolutionRequest)
var _active_requests: Dictionary = {}

## Mapping from asset key to request_id (for deduplication)
var _key_to_request: Dictionary = {}


func _ready() -> void:
	# Connect to download/streaming signals
	_connect_download_signals()


func _connect_download_signals() -> void:
	# AssetDownloader signals
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		if not downloader.download_completed.is_connected(_on_http_download_completed):
			downloader.download_completed.connect(_on_http_download_completed)
		if not downloader.download_failed.is_connected(_on_http_download_failed):
			downloader.download_failed.connect(_on_http_download_failed)
		if not downloader.download_progress.is_connected(_on_http_download_progress):
			downloader.download_progress.connect(_on_http_download_progress)
	
	# AssetStreamer signals
	if has_node("/root/AssetStreamer"):
		var streamer = get_node("/root/AssetStreamer")
		if not streamer.asset_received.is_connected(_on_p2p_asset_received):
			streamer.asset_received.connect(_on_p2p_asset_received)
		if not streamer.asset_failed.is_connected(_on_p2p_asset_failed):
			streamer.asset_failed.connect(_on_p2p_asset_failed)
		if not streamer.transfer_progress.is_connected(_on_p2p_transfer_progress):
			streamer.transfer_progress.connect(_on_p2p_transfer_progress)


# =============================================================================
# PUBLIC API: SYNCHRONOUS RESOLUTION
# =============================================================================

## Resolve a model path synchronously
## Returns local path if available (local or cached), empty string if needs download
## Does NOT trigger async download - use resolve_model_async for that
func resolve_model_sync(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	return _resolve_sync(pack_id, asset_id, variant_id, "model")


## Resolve an icon path synchronously
func resolve_icon_sync(pack_id: String, asset_id: String, variant_id: String = "default") -> String:
	return _resolve_sync(pack_id, asset_id, variant_id, "icon")


func _resolve_sync(pack_id: String, asset_id: String, variant_id: String, file_type: String) -> String:
	# Stage 1: Check local pack
	var local_path = _check_local_pack(pack_id, asset_id, variant_id, file_type)
	if local_path != "":
		return local_path
	
	# Stage 2: Check cache
	var cached_path = _check_cache(pack_id, asset_id, variant_id, file_type)
	if cached_path != "":
		return cached_path
	
	# Not available locally
	return ""


## Check if an asset is available locally (sync check only)
func is_available_locally(pack_id: String, asset_id: String, variant_id: String = "default", file_type: String = "model") -> bool:
	return _resolve_sync(pack_id, asset_id, variant_id, file_type) != ""


# =============================================================================
# PUBLIC API: ASYNCHRONOUS RESOLUTION
# =============================================================================

## Resolve a model asynchronously
## Returns request_id for tracking
## Emits asset_resolved or asset_failed when complete
func resolve_model_async(pack_id: String, asset_id: String, variant_id: String = "default", priority: int = 100) -> String:
	return _resolve_async(pack_id, asset_id, variant_id, "model", priority)


## Resolve an icon asynchronously
func resolve_icon_async(pack_id: String, asset_id: String, variant_id: String = "default", priority: int = 100) -> String:
	return _resolve_async(pack_id, asset_id, variant_id, "icon", priority)


func _resolve_async(pack_id: String, asset_id: String, variant_id: String, file_type: String, priority: int) -> String:
	# Create request
	var request = ResolutionRequest.new(pack_id, asset_id, variant_id, file_type, priority)
	var key = request.get_key()
	
	# Check for existing request (deduplication)
	if _key_to_request.has(key):
		var existing_id = _key_to_request[key]
		if _active_requests.has(existing_id):
			# Update priority if higher
			var existing: ResolutionRequest = _active_requests[existing_id]
			if priority < existing.priority:
				existing.priority = priority
			return existing_id
	
	# Stage 1: Check local pack (synchronous, fast)
	var local_path = _check_local_pack(pack_id, asset_id, variant_id, file_type)
	if local_path != "":
		# Emit immediately on next frame
		call_deferred("_emit_resolved", request.request_id, pack_id, asset_id, variant_id, local_path)
		return request.request_id
	
	# Stage 2: Check cache (synchronous, fast)
	var cached_path = _check_cache(pack_id, asset_id, variant_id, file_type)
	if cached_path != "":
		call_deferred("_emit_resolved", request.request_id, pack_id, asset_id, variant_id, cached_path)
		return request.request_id
	
	# Stage 3+: Need async download
	# Register the request
	_active_requests[request.request_id] = request
	_key_to_request[key] = request.request_id
	
	# Try HTTP first, then P2P
	request.stage = Stage.HTTP
	if not _try_http_download(request):
		# No URL available, try P2P
		request.stage = Stage.P2P
		if not _try_p2p_download(request):
			# No resolution sources available
			_complete_request(request.request_id, "", "No download sources available")
	
	return request.request_id


## Cancel an active resolution request
func cancel_request(request_id: String) -> void:
	if not _active_requests.has(request_id):
		return
	
	var request: ResolutionRequest = _active_requests[request_id]
	_key_to_request.erase(request.get_key())
	_active_requests.erase(request_id)


# =============================================================================
# RESOLUTION STAGES
# =============================================================================

## Check local pack for asset
func _check_local_pack(pack_id: String, asset_id: String, variant_id: String, file_type: String) -> String:
	if not has_node("/root/AssetPackManager"):
		return ""
	
	var pack_manager = get_node("/root/AssetPackManager")
	var pack = pack_manager.get_pack(pack_id)
	if not pack:
		return ""
	
	# Only check local path if pack has a base_path
	if pack.base_path == "":
		return ""
	
	var path: String
	if file_type == "model":
		path = pack.get_model_path(asset_id, variant_id)
	else:
		path = pack.get_icon_path(asset_id, variant_id)
	
	if path == "":
		return ""
	# user:// paths need FileAccess; res:// paths use ResourceLoader
	if path.begins_with("user://"):
		return path if FileAccess.file_exists(path) else ""
	return path if ResourceLoader.exists(path) else ""


## Check cache for asset
func _check_cache(pack_id: String, asset_id: String, variant_id: String, file_type: String) -> String:
	if not has_node("/root/AssetCacheManager"):
		return ""
	
	var cache_manager = get_node("/root/AssetCacheManager")
	return cache_manager.get_cached_path(pack_id, asset_id, variant_id, file_type)


## Try HTTP download
## Returns true if download was started
func _try_http_download(request: ResolutionRequest) -> bool:
	if not has_node("/root/AssetPackManager") or not has_node("/root/AssetDownloader"):
		return false
	
	var pack_manager = get_node("/root/AssetPackManager")
	var pack = pack_manager.get_pack(request.pack_id)
	if not pack:
		return false
	
	var url: String
	if request.file_type == "model":
		url = pack.get_model_url(request.asset_id, request.variant_id)
	else:
		url = pack.get_icon_url(request.asset_id, request.variant_id)
	
	if url == "":
		return false
	
	# Start download
	var downloader = get_node("/root/AssetDownloader")
	downloader.request_download(
		request.pack_id,
		request.asset_id,
		request.variant_id,
		url,
		request.priority,
		request.file_type
	)
	
	resolution_progress.emit(request.request_id, "http", 0.0)
	return true


## Try P2P streaming from host
## Returns true if request was started
func _try_p2p_download(request: ResolutionRequest) -> bool:
	if not has_node("/root/AssetStreamer") or not has_node("/root/NetworkManager"):
		return false
	
	var network_manager = get_node("/root/NetworkManager")
	if not network_manager.is_client():
		return false
	
	var streamer = get_node("/root/AssetStreamer")
	if not streamer.is_enabled():
		return false
	
	streamer.request_from_host(
		request.pack_id,
		request.asset_id,
		request.variant_id,
		request.priority
	)
	
	resolution_progress.emit(request.request_id, "p2p", 0.0)
	return true


# =============================================================================
# DOWNLOAD CALLBACKS
# =============================================================================

func _on_http_download_completed(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	_handle_download_complete(key, local_path)
	
	# Also check icon key
	var icon_key = "%s/%s/%s/icon" % [pack_id, asset_id, variant_id]
	if _key_to_request.has(icon_key):
		# Check if this was an icon download based on path extension
		if local_path.ends_with(".png") or local_path.ends_with(".jpg"):
			_handle_download_complete(icon_key, local_path)


func _on_http_download_failed(pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	
	if not _key_to_request.has(key):
		return
	
	var request_id = _key_to_request[key]
	var request: ResolutionRequest = _active_requests.get(request_id)
	if not request:
		return
	
	# HTTP failed, try P2P as fallback
	request.stage = Stage.P2P
	if not _try_p2p_download(request):
		_complete_request(request_id, "", error)


func _on_http_download_progress(pack_id: String, asset_id: String, variant_id: String, progress: float) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	if _key_to_request.has(key):
		var request_id = _key_to_request[key]
		resolution_progress.emit(request_id, "http", progress)


func _on_p2p_asset_received(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	_handle_download_complete(key, local_path)


func _on_p2p_asset_failed(pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	
	if not _key_to_request.has(key):
		return
	
	var request_id = _key_to_request[key]
	_complete_request(request_id, "", error)


func _on_p2p_transfer_progress(pack_id: String, asset_id: String, variant_id: String, progress: float) -> void:
	var key = "%s/%s/%s/model" % [pack_id, asset_id, variant_id]
	if _key_to_request.has(key):
		var request_id = _key_to_request[key]
		resolution_progress.emit(request_id, "p2p", progress)


func _handle_download_complete(key: String, local_path: String) -> void:
	if not _key_to_request.has(key):
		return
	
	var request_id = _key_to_request[key]
	_complete_request(request_id, local_path, "")


# =============================================================================
# HELPERS
# =============================================================================

func _complete_request(request_id: String, local_path: String, error: String) -> void:
	if not _active_requests.has(request_id):
		return
	
	var request: ResolutionRequest = _active_requests[request_id]
	
	# Clean up
	_key_to_request.erase(request.get_key())
	_active_requests.erase(request_id)
	
	# Emit result
	if local_path != "":
		asset_resolved.emit(request_id, request.pack_id, request.asset_id, request.variant_id, local_path)
	else:
		asset_failed.emit(request_id, request.pack_id, request.asset_id, request.variant_id, error)


func _emit_resolved(request_id: String, pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	asset_resolved.emit(request_id, pack_id, asset_id, variant_id, local_path)


## Get active request count (for debugging)
func get_active_request_count() -> int:
	return _active_requests.size()
