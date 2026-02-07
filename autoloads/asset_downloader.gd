extends Node

## Handles downloading assets from remote URLs and caching them locally.
## Supports HTTP downloads from GitHub, Cloudflare R2, Dropbox, and other services.
## Uses AssetCacheManager for unified cache management with LRU eviction.

const MAX_CONCURRENT_DOWNLOADS: int = 3
const DOWNLOAD_TIMEOUT: float = 60.0 # seconds

## Emitted when an asset download completes successfully
signal download_completed(pack_id: String, asset_id: String, variant_id: String, local_path: String)

## Emitted when an asset download fails
signal download_failed(pack_id: String, asset_id: String, variant_id: String, error: String)

## Emitted during download progress (0.0 to 1.0)
signal download_progress(pack_id: String, asset_id: String, variant_id: String, progress: float)

## Emitted when all queued downloads are complete
signal all_downloads_completed


class DownloadRequest:
	var pack_id: String
	var asset_id: String
	var variant_id: String
	var url: String
	var cache_path: String
	var priority: int # Lower = higher priority
	var http_request: HTTPRequest
	var bytes_downloaded: int = 0
	var total_bytes: int = 0
	var target_path: String = "" # When set, download to this path instead of cache (for user_assets)
	
	func get_key() -> String:
		return "%s/%s/%s" % [pack_id, asset_id, variant_id]
	
	func get_dedup_key() -> String:
		return target_path if target_path != "" else get_key()


## Queue of pending downloads
var _download_queue: Array[DownloadRequest] = []

## Currently active downloads (key -> DownloadRequest)
var _active_downloads: Dictionary = {}

## Completed download cache (key -> local_path)
var _completed_cache: Dictionary = {}

## Failed downloads that should not be retried this session
var _failed_downloads: Dictionary = {}


func _ready() -> void:
	pass # AssetCacheManager handles cache directory setup


func _process(_delta: float) -> void:
	if not _active_downloads.is_empty():
		_update_download_progress()


## Check if an asset is already cached locally
## Delegates to AssetCacheManager for unified cache access
## Returns the local path if cached, empty string otherwise
func get_cached_path(pack_id: String, asset_id: String, variant_id: String, file_type: String = "model") -> String:
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]
	
	# Check memory cache first (for this session's downloads)
	if _completed_cache.has(key):
		var cached_path = _completed_cache[key]
		if FileAccess.file_exists(cached_path):
			return cached_path
		else:
			_completed_cache.erase(key)
	
	# Delegate to AssetCacheManager
	if has_node("/root/AssetCacheManager"):
		var cache_manager = get_node("/root/AssetCacheManager")
		return cache_manager.get_cached_path(pack_id, asset_id, variant_id, file_type)
	
	# Fallback: check filesystem directly
	var cache_path = _get_cache_path(pack_id, asset_id, variant_id, file_type)
	if FileAccess.file_exists(cache_path):
		_completed_cache[key] = cache_path
		return cache_path
	
	return ""


## Get the cache path for an asset (whether it exists or not)
func _get_cache_path(pack_id: String, asset_id: String, variant_id: String, file_type: String = "model") -> String:
	if has_node("/root/AssetCacheManager"):
		var cache_manager = get_node("/root/AssetCacheManager")
		return cache_manager.get_expected_cache_path(pack_id, asset_id, variant_id, file_type)
	
	# Fallback
	var extension = ".glb" if file_type == "model" else ".png"
	return "user://asset_cache/%s/%s/%s%s" % [pack_id, asset_id, variant_id, extension]


## Request download of an asset
## If already cached/present, emits download_completed immediately
## If already downloading, does nothing (will emit when complete)
## Otherwise, queues the download
## @param target_path: Optional. When set, download to this path instead of cache (e.g. user://user_assets/pack/models/file.glb)
func request_download(pack_id: String, asset_id: String, variant_id: String, url: String, priority: int = 100, file_type: String = "model", target_path: String = "") -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	
	# Already present?
	var dest_path: String
	if target_path != "":
		dest_path = target_path
		if FileAccess.file_exists(dest_path):
			call_deferred("_emit_completed", pack_id, asset_id, variant_id, dest_path)
			return
	else:
		dest_path = get_cached_path(pack_id, asset_id, variant_id, file_type)
		if dest_path != "":
			call_deferred("_emit_completed", pack_id, asset_id, variant_id, dest_path)
			return
	
	# Already failed this session?
	var dedup_key = target_path if target_path != "" else key
	if _failed_downloads.has(dedup_key):
		call_deferred("_emit_failed", pack_id, asset_id, variant_id, _failed_downloads[dedup_key])
		return
	
	# Already downloading or queued?
	for request in _download_queue:
		if request.get_dedup_key() == dedup_key:
			if priority < request.priority:
				request.priority = priority
				_sort_queue()
			return
	if _active_downloads.has(dedup_key):
		return
	
	# Create new download request
	var request = DownloadRequest.new()
	request.pack_id = pack_id
	request.asset_id = asset_id
	request.variant_id = variant_id
	request.url = url
	request.cache_path = target_path if target_path != "" else _get_cache_path(pack_id, asset_id, variant_id, file_type)
	request.priority = priority
	request.target_path = target_path
	
	_download_queue.append(request)
	_sort_queue()
	_process_queue()


## Sort download queue by priority (lower number = higher priority)
func _sort_queue() -> void:
	_download_queue.sort_custom(func(a: DownloadRequest, b: DownloadRequest) -> bool:
		return a.priority < b.priority
	)


## Process the download queue, starting new downloads if slots available
func _process_queue() -> void:
	while _active_downloads.size() < MAX_CONCURRENT_DOWNLOADS and _download_queue.size() > 0:
		var request = _download_queue.pop_front()
		_start_download(request)
	
	# Check if all downloads are complete
	if _active_downloads.is_empty() and _download_queue.is_empty():
		all_downloads_completed.emit()


## Start a download
func _start_download(request: DownloadRequest) -> void:
	var key = request.get_dedup_key()
	
	# Ensure cache subdirectory exists (AssetCacheManager may not have created it yet)
	var cache_dir = request.cache_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(cache_dir):
		var err = DirAccess.make_dir_recursive_absolute(cache_dir)
		if err != OK:
			_handle_download_error(request, "Failed to create cache directory")
			return
	
	# Create HTTP request node
	var http_request = HTTPRequest.new()
	http_request.timeout = DOWNLOAD_TIMEOUT
	http_request.download_file = request.cache_path
	http_request.use_threads = true
	add_child(http_request)
	
	request.http_request = http_request
	_active_downloads[key] = request
	
	# Connect signals
	http_request.request_completed.connect(_on_request_completed.bind(request))
	
	# Start the request
	var error = http_request.request(request.url)
	if error != OK:
		_handle_download_error(request, "Failed to start HTTP request: " + str(error))
		return
	
	# Emit initial progress
	download_progress.emit(request.pack_id, request.asset_id, request.variant_id, 0.0)
	
	print("AssetDownloader: Starting download of %s from %s" % [key, request.url])


## Poll active downloads for progress (called from _process)
func _update_download_progress() -> void:
	for key in _active_downloads:
		var request = _active_downloads[key] as DownloadRequest
		if request.http_request:
			var downloaded = request.http_request.get_downloaded_bytes()
			var total = request.http_request.get_body_size()
			
			if total > 0:
				var progress = float(downloaded) / float(total)
				# Only emit if progress changed significantly
				if abs(progress - request.bytes_downloaded / max(1.0, float(request.total_bytes))) > 0.05:
					request.bytes_downloaded = downloaded
					request.total_bytes = total
					download_progress.emit(request.pack_id, request.asset_id, request.variant_id, progress)
			elif downloaded > 0 and request.bytes_downloaded != downloaded:
				# Unknown total size, emit indeterminate progress
				request.bytes_downloaded = downloaded
				download_progress.emit(request.pack_id, request.asset_id, request.variant_id, -1.0)


## Handle HTTP request completion
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray, request: DownloadRequest) -> void:
	var key = request.get_dedup_key()
	
	# Clean up HTTP request node
	if request.http_request:
		request.http_request.queue_free()
		request.http_request = null
	
	# Remove from active downloads
	_active_downloads.erase(key)
	
	# Check for errors
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = _get_http_result_error(result)
		_handle_download_error(request, error_msg)
		_process_queue()
		return
	
	if response_code < 200 or response_code >= 300:
		# Handle redirects for services like Dropbox
		if response_code >= 300 and response_code < 400:
			for header in headers:
				if header.to_lower().begins_with("location:"):
					var redirect_url = header.substr(9).strip_edges()
					print("AssetDownloader: Following redirect to %s" % redirect_url)
					request.url = redirect_url
					_start_download(request)
					return
		
		_handle_download_error(request, "HTTP error: " + str(response_code))
		_process_queue()
		return
	
	# Success! Verify the file was written
	if not FileAccess.file_exists(request.cache_path):
		_handle_download_error(request, "Download completed but file not found")
		_process_queue()
		return
	
	# Register with AssetCacheManager only for cache downloads (not user_assets)
	if request.target_path == "":
		var file_type = "model" if request.cache_path.ends_with(".glb") else "icon"
		if has_node("/root/AssetCacheManager"):
			var cache_manager = get_node("/root/AssetCacheManager")
			cache_manager.register_cached_file(request.pack_id, request.asset_id, request.variant_id, request.cache_path, file_type)
		var cache_key = "%s/%s" % [request.get_key(), file_type]
		_completed_cache[cache_key] = request.cache_path
	
	print("AssetDownloader: Completed download of %s" % key)
	download_completed.emit(request.pack_id, request.asset_id, request.variant_id, request.cache_path)
	
	_process_queue()


## Handle download errors
func _handle_download_error(request: DownloadRequest, error_msg: String) -> void:
	var key = request.get_dedup_key()
	
	# Clean up partial download
	if FileAccess.file_exists(request.cache_path):
		DirAccess.remove_absolute(request.cache_path)
	
	# Record failure to prevent retries this session
	_failed_downloads[key] = error_msg
	
	push_error("AssetDownloader: Failed to download %s: %s" % [key, error_msg])
	download_failed.emit(request.pack_id, request.asset_id, request.variant_id, error_msg)


## Get human-readable error message for HTTP result
func _get_http_result_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Cannot connect to host"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Response body too large"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Failed to decompress response"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Error writing download file"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Too many redirects"
		HTTPRequest.RESULT_TIMEOUT:
			return "Request timed out"
		_:
			return "Unknown error: " + str(result)


## Deferred emit for completed downloads (for cached assets)
func _emit_completed(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	download_completed.emit(pack_id, asset_id, variant_id, local_path)


## Deferred emit for failed downloads
func _emit_failed(pack_id: String, asset_id: String, variant_id: String, error: String) -> void:
	download_failed.emit(pack_id, asset_id, variant_id, error)


## Check if a download is in progress for an asset
func is_downloading(pack_id: String, asset_id: String, variant_id: String) -> bool:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	return _active_downloads.has(key) or _is_queued(key)


## Check if an asset is queued for download
func _is_queued(key: String) -> bool:
	for request in _download_queue:
		if request.get_key() == key:
			return true
	return false


## Get the number of active downloads
func get_active_download_count() -> int:
	return _active_downloads.size()


## Get the number of queued downloads
func get_queued_download_count() -> int:
	return _download_queue.size()


## Cancel all pending downloads (does not cancel active downloads)
func cancel_pending_downloads() -> void:
	_download_queue.clear()


## Clear the failed downloads cache, allowing retries
func clear_failed_cache() -> void:
	_failed_downloads.clear()


## Clear all caches (for testing/debugging)
func clear_all_caches() -> void:
	_completed_cache.clear()
	_failed_downloads.clear()
	
	# Use AssetCacheManager if available
	if has_node("/root/AssetCacheManager"):
		var cache_manager = get_node("/root/AssetCacheManager")
		cache_manager.clear_cache()
	else:
		# Fallback: clear filesystem cache directly
		var cache_dir = "user://asset_cache/"
		var dir = DirAccess.open(cache_dir)
		if dir:
			_recursive_delete(cache_dir)
			DirAccess.make_dir_recursive_absolute(cache_dir)


## Recursively delete a directory
func _recursive_delete(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			_recursive_delete(full_path)
			DirAccess.remove_absolute(full_path)
		else:
			DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
