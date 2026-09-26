class_name MapDownloadCoordinator

## Manages requesting and receiving map downloads via AssetStreamer for
## client-side map loading (P2P map streaming when a client doesn't already
## have the requested map cached locally).
##
## A level's map is one or two files: map.glb (streaming variant "map") and the authored
## map.ttmap (variant "ttmap"). request_map_download() is told which of them are missing
## and which are already available (local or cached), requests the missing ones, and
## loads the map only once every expected file is here, through the loader's async
## load_map_sources_async and _finalize_map_loading, injected via setup().
##
## Failure routing mirrors the host's loader: a GLB that fails to download fails the map;
## a document that fails while a GLB is expected lets the GLB load without it (the loader
## tells the player), and a document-only map fails.
##
## Extracted from LevelPlayController to give it a single responsibility.

signal map_download_started(level_folder: String)
signal map_download_progress(level_folder: String, progress: float)
signal map_download_completed(level_folder: String)
signal map_download_failed(level_folder: String, error: String)

## The AssetStreamer used for requests and signals; tests replace it with a double.
var streamer: Node = null

var _pending_map_level_folder: String = ""  # Level folder waiting for map download
## Variant ids still downloading for the pending folder.
var _waiting: Dictionary = {}
## Variant id -> local path of every file of the pending map that is here.
var _paths: Dictionary = {}
## Variant ids of the pending map whose download failed but which the map can do without.
var _dropped: Dictionary = {}
## Bumped on every request and reset, so a load finishing after either is discarded.
var _generation: int = 0
var _streamer_connected: bool = false

var _load_map_sources_fn: Callable
var _finalize_map_loading_fn: Callable


## Initialize with callables for loading the downloaded files into a scene.
## load_map_sources_fn(glb_path: String, document_path: String) -> Node3D (a coroutine;
## either path may be "")
## finalize_map_loading_fn(map: Node3D) -> void
func setup(load_map_sources_fn: Callable, finalize_map_loading_fn: Callable) -> void:
	_load_map_sources_fn = load_map_sources_fn
	_finalize_map_loading_fn = finalize_map_loading_fn


func _get_streamer() -> Node:
	if streamer == null:
		streamer = AssetManager.streamer
	return streamer


## Connect to AssetStreamer for map downloads
func connect_asset_streamer() -> void:
	if _streamer_connected:
		return
	var source := _get_streamer()
	if not source.asset_received.is_connected(_on_map_received):
		source.asset_received.connect(_on_map_received)
	if not source.asset_failed.is_connected(_on_map_failed):
		source.asset_failed.connect(_on_map_failed)
	if not source.transfer_progress.is_connected(_on_map_transfer_progress):
		source.transfer_progress.connect(_on_map_transfer_progress)
	_streamer_connected = true


## Disconnect from AssetStreamer signals
func disconnect_asset_streamer() -> void:
	if not _streamer_connected:
		return
	var source := _get_streamer()
	if source.asset_received.is_connected(_on_map_received):
		source.asset_received.disconnect(_on_map_received)
	if source.asset_failed.is_connected(_on_map_failed):
		source.asset_failed.disconnect(_on_map_failed)
	if source.transfer_progress.is_connected(_on_map_transfer_progress):
		source.transfer_progress.disconnect(_on_map_transfer_progress)
	_streamer_connected = false


## Handle a map file download completing. The handlers take AssetStreamer's trailing
## file_type argument: Godot 4 does not drop extra signal arguments, it refuses the call
## ("Method expected 4 argument(s), but called with 5"), which is how every map download
## was silently lost before this took five.
func _on_map_received(
	pack_id: String, asset_id: String, variant_id: String, local_path: String, _file_type := ""
) -> void:
	if not _is_pending(pack_id, asset_id, variant_id):
		return
	print("MapDownloadCoordinator: Map file %s downloaded for level: %s" % [variant_id, asset_id])
	_waiting.erase(variant_id)
	_paths[variant_id] = local_path
	if _waiting.is_empty():
		_load_downloaded_map()


## Handle a map file download failing
func _on_map_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String, _file_type := ""
) -> void:
	if not _is_pending(pack_id, asset_id, variant_id):
		return
	_waiting.erase(variant_id)
	var glb_expected := _paths.has(Paths.LEVEL_MAP_VARIANT) or _waiting.has(Paths.LEVEL_MAP_VARIANT)
	if variant_id == Paths.LEVEL_MAP_DOCUMENT_VARIANT and glb_expected:
		push_warning("MapDownloadCoordinator: Map document download failed: " + error)
		_dropped[variant_id] = true
		if _waiting.is_empty():
			_load_downloaded_map()
		return
	push_error("MapDownloadCoordinator: Map download failed: " + error)
	var folder := _pending_map_level_folder
	_clear_pending()
	map_download_failed.emit(folder, error)


## Handle map download progress: the mean over the files still expected.
func _on_map_transfer_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float, _file_type := ""
) -> void:
	if not _is_pending(pack_id, asset_id, variant_id):
		return
	var total := _waiting.size() + _paths.size()
	var done := float(_paths.size()) + progress
	map_download_progress.emit(asset_id, done / maxf(total, 1.0))


func _is_pending(pack_id: String, asset_id: String, variant_id: String) -> bool:
	return (
		pack_id == Paths.LEVEL_MAPS_PACK_ID
		and asset_id != ""
		and asset_id == _pending_map_level_folder
		and _waiting.has(variant_id)
	)


## Every expected file is here: load and finalize the map (async), unless a newer request
## or a reset replaced this one meanwhile.
func _load_downloaded_map() -> void:
	var folder := _pending_map_level_folder
	var glb_path: String = _paths.get(Paths.LEVEL_MAP_VARIANT, "")
	var document_path: String = _paths.get(Paths.LEVEL_MAP_DOCUMENT_VARIANT, "")
	var document_dropped := _dropped.has(Paths.LEVEL_MAP_DOCUMENT_VARIANT)
	_clear_pending()
	var generation := _generation
	map_download_completed.emit(folder)
	if document_dropped:
		push_warning("MapDownloadCoordinator: loading %s without its map document" % folder)
	var map: Node3D = await _load_map_sources_fn.call(glb_path, document_path)
	if generation != _generation:
		if is_instance_valid(map):
			map.free()
		return
	if map:
		_finalize_map_loading_fn.call(map)
	else:
		push_error("MapDownloadCoordinator: Failed to load downloaded map")
		map_download_failed.emit(folder, "Failed to load map file")


## The cached copy of one map file of a level, or "" when there is none or its content
## hash differs from `expected_hash` (a stale copy, which is dropped from the cache).
## An empty expected hash accepts any cached copy (a host that sent none).
func get_cached_map_file(level_folder: String, variant_id: String, expected_hash: String) -> String:
	return _get_streamer().get_cached_map_file(level_folder, variant_id, expected_hash)


## Get the cached map path for a level (if it exists)
func get_cached_map_path(level_folder: String) -> String:
	return get_cached_map_file(level_folder, Paths.LEVEL_MAP_VARIANT, "")


## Requests the `missing` map files (variant ids) of a level from the host. `available`
## maps the variant ids already here to their paths; the map loads when every file of
## both sets is here. Returns true when the load will continue asynchronously.
func request_map_download(
	level_folder: String, missing: Array = [Paths.LEVEL_MAP_VARIANT], available: Dictionary = {}
) -> bool:
	var source := _get_streamer()
	if not source.is_enabled():
		push_error("MapDownloadCoordinator: P2P streaming is disabled")
		return false
	if missing.is_empty():
		push_error("MapDownloadCoordinator: nothing to download for " + level_folder)
		return false

	_clear_pending()
	_generation += 1
	_pending_map_level_folder = level_folder
	_paths = available.duplicate()
	for variant_id in missing:
		_waiting[variant_id] = true

	map_download_started.emit(level_folder)
	for variant_id in missing:
		print(
			(
				"MapDownloadCoordinator: Requesting map file %s for level: %s"
				% [variant_id, level_folder]
			)
		)
		source.request_map_file_from_host(level_folder, variant_id)

	# Return true to indicate level loading will continue async
	return true


## Check if a map download is in progress
func is_map_downloading() -> bool:
	return _pending_map_level_folder != ""


## The variant ids still downloading (for tests and diagnostics).
func waiting_variants() -> Array:
	return _waiting.keys()


func _clear_pending() -> void:
	_pending_map_level_folder = ""
	_waiting.clear()
	_paths.clear()
	_dropped.clear()


## Reset pending download state and disconnect from AssetStreamer.
## Call when exiting PLAYING state.
func reset() -> void:
	_clear_pending()
	_generation += 1
	disconnect_asset_streamer()
