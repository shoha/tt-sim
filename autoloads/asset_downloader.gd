extends Node

## Handles downloading assets from remote URLs and caching them locally.
## Supports HTTP downloads from GitHub, Cloudflare R2, Dropbox, and other services.
## Uses the disk cache for unified cache management with LRU eviction.
##
## This is an internal sub-component of AssetManager. External code should
## access it via AssetManager.downloader rather than as a standalone autoload.

const MAX_CONCURRENT_DOWNLOADS: int = 3
const DOWNLOAD_TIMEOUT: float = 60.0  # seconds

## Injected reference to the disk cache (set by AssetManager.setup).
var _cache_manager: Node

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
	var priority: int  # Lower = higher priority
	var http_request: HTTPRequest
	var bytes_downloaded: int = 0
	var total_bytes: int = 0
	var target_path: String = ""  # When set, download to this path instead of cache (for user_assets)

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
	set_process(false)


func _exit_tree() -> void:
	# Cancel active HTTPRequests so their background threads can join
	# immediately instead of blocking shutdown for up to DOWNLOAD_TIMEOUT
	# per request.
	for key in _active_downloads:
		var request: DownloadRequest = _active_downloads[key]
		if request.http_request and is_instance_valid(request.http_request):
			request.http_request.cancel_request()


## Inject dependencies (called by AssetManager after adding to tree).
func setup(cache_manager: Node) -> void:
	_cache_manager = cache_manager


func _process(_delta: float) -> void:
	_update_download_progress()
	if _active_downloads.is_empty():
		set_process(false)


## Check if an asset is already cached locally
## Delegates to AssetCacheManager for unified cache access
## Returns the local path if cached, empty string otherwise
func get_cached_path(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> String:
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

	# Check memory cache first (for this session's downloads)
	if _completed_cache.has(key):
		var cached_path = _completed_cache[key]
		if FileAccess.file_exists(cached_path):
			return cached_path
		else:
			_completed_cache.erase(key)

	# Delegate to AssetCacheManager
	return _cache_manager.get_cached_path(pack_id, asset_id, variant_id, file_type)


## Get the cache path for an asset (whether it exists or not)
func _get_cache_path(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> String:
	return _cache_manager.get_expected_cache_path(pack_id, asset_id, variant_id, file_type)


## Request download of an asset
## If already cached/present, emits download_completed immediately
## If already downloading, does nothing (will emit when complete)
## Otherwise, queues the download
## @param target_path: Optional. When set, download to this path instead of cache (e.g. user://user_assets/pack/models/file.glb)
func request_download(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	url: String,
	priority: int = Constants.ASSET_PRIORITY_DEFAULT,
	file_type: String = "model",
	target_path: String = ""
) -> void:
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
	request.cache_path = (
		target_path
		if target_path != ""
		else _get_cache_path(pack_id, asset_id, variant_id, file_type)
	)
	request.priority = priority
	request.target_path = target_path

	_download_queue.append(request)
	_sort_queue()
	_process_queue()


## Queue a batch of downloads that the caller has already confirmed are not
## present on disk.  Skips the per-item FileAccess.file_exists check and
## performs a single O(n) dedup pass before enqueueing.
## Each item Dictionary must have: pack_id, asset_id, variant_id, url,
## file_type, target_path, priority.
func request_downloads_bulk(items: Array[Dictionary]) -> void:
	if items.is_empty():
		return

	# Build O(1) lookup of dedup keys already active or queued.
	var in_flight: Dictionary = {}
	for key in _active_downloads:
		in_flight[key] = true
	for req in _download_queue:
		in_flight[req.get_dedup_key()] = true

	var new_requests: Array[DownloadRequest] = []

	for item in items:
		var pack_id: String = item["pack_id"]
		var asset_id: String = item["asset_id"]
		var variant_id: String = item["variant_id"]
		var url: String = item["url"]
		var file_type: String = item["file_type"]
		var target_path: String = item["target_path"]
		var priority: int = item["priority"]

		var dedup_key: String = (
			target_path if target_path != "" else "%s/%s/%s" % [pack_id, asset_id, variant_id]
		)

		if _failed_downloads.has(dedup_key):
			call_deferred(
				"_emit_failed", pack_id, asset_id, variant_id, _failed_downloads[dedup_key]
			)
			continue

		if in_flight.has(dedup_key):
			continue

		in_flight[dedup_key] = true

		var req := DownloadRequest.new()
		req.pack_id = pack_id
		req.asset_id = asset_id
		req.variant_id = variant_id
		req.url = url
		req.cache_path = (
			target_path
			if target_path != ""
			else _get_cache_path(pack_id, asset_id, variant_id, file_type)
		)
		req.priority = priority
		req.target_path = target_path

		new_requests.append(req)

	if new_requests.is_empty():
		_process_queue()
		return

	_download_queue.append_array(new_requests)
	_sort_queue()
	_process_queue()


## Sort download queue by priority (lower number = higher priority)
func _sort_queue() -> void:
	_download_queue.sort_custom(
		func(a: DownloadRequest, b: DownloadRequest) -> bool: return a.priority < b.priority
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
	set_process(true)

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
				if (
					abs(progress - request.bytes_downloaded / max(1.0, float(request.total_bytes)))
					> 0.05
				):
					request.bytes_downloaded = downloaded
					request.total_bytes = total
					download_progress.emit(
						request.pack_id, request.asset_id, request.variant_id, progress
					)
			elif downloaded > 0 and request.bytes_downloaded != downloaded:
				# Unknown total size, emit indeterminate progress
				request.bytes_downloaded = downloaded
				download_progress.emit(request.pack_id, request.asset_id, request.variant_id, -1.0)


## Handle HTTP request completion
func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	_body: PackedByteArray,
	request: DownloadRequest
) -> void:
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
		_cache_manager.register_cached_file(
			request.pack_id, request.asset_id, request.variant_id, request.cache_path, file_type
		)
		var cache_key = "%s/%s" % [request.get_key(), file_type]
		_completed_cache[cache_key] = request.cache_path

	print("AssetDownloader: Completed download of %s" % key)
	download_completed.emit(
		request.pack_id, request.asset_id, request.variant_id, request.cache_path
	)

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
	return UpdateInstaller.get_http_error(result)


## Deferred emit for completed downloads (for cached assets)
func _emit_completed(
	pack_id: String, asset_id: String, variant_id: String, local_path: String
) -> void:
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


## Check if there are any pending (queued or active) downloads for a given variant.
## Useful for determining whether a variant's UI item should be removed yet.
func has_pending_downloads_for(pack_id: String, asset_id: String, variant_id: String) -> bool:
	for key in _active_downloads:
		var request = _active_downloads[key] as DownloadRequest
		if (
			request.pack_id == pack_id
			and request.asset_id == asset_id
			and request.variant_id == variant_id
		):
			return true
	for request in _download_queue:
		if (
			request.pack_id == pack_id
			and request.asset_id == asset_id
			and request.variant_id == variant_id
		):
			return true
	return false


## Get the number of queued downloads counted by unique variant (not per file).
func get_queued_variant_count() -> int:
	var variants: Dictionary = {}
	for request in _download_queue:
		variants[request.get_key()] = true
	return variants.size()


## Cancel all pending downloads (does not cancel active downloads)
func cancel_pending_downloads() -> void:
	_download_queue.clear()


## Clear the failed downloads cache, allowing retries
func clear_failed_cache() -> void:
	_failed_downloads.clear()


## Clear only the failed-download entries belonging to a single pack, allowing
## just that pack's assets to be retried without wiping unrelated failures.
## Dedup keys for pack downloads are either "pack_id/asset_id/variant_id" or,
## for user_assets downloads with a target_path, the target_path itself
## (which is always prefixed with "user://user_assets/<pack_id>/").
func clear_failed_for_pack(pack_id: String) -> void:
	var key_prefix := "%s/" % pack_id
	var path_prefix := "user://user_assets/%s/" % pack_id
	var keys_to_erase: Array = []
	for key in _failed_downloads:
		if (key as String).begins_with(key_prefix) or (key as String).begins_with(path_prefix):
			keys_to_erase.append(key)
	for key in keys_to_erase:
		_failed_downloads.erase(key)


## Clear all caches (for testing/debugging)
func clear_all_caches() -> void:
	_completed_cache.clear()
	_failed_downloads.clear()

	_cache_manager.clear_cache()
