class_name MapDownloadCoordinator

## Manages requesting and receiving map downloads via AssetStreamer for
## client-side map loading (P2P map streaming when a client doesn't already
## have the requested map cached locally).
##
## Extracted from LevelPlayController to give it a single responsibility.
## Actually loading the downloaded map file into a scene
## (_load_map_from_path / _finalize_map_loading) stays on LevelPlayController
## for now, so those two steps are injected here as Callables via setup().

signal map_download_started(level_folder: String)
signal map_download_progress(level_folder: String, progress: float)
signal map_download_completed(level_folder: String)
signal map_download_failed(level_folder: String, error: String)

var _pending_map_level_folder: String = ""  # Level folder waiting for map download
var _streamer_connected: bool = false

var _load_map_from_path_fn: Callable
var _finalize_map_loading_fn: Callable


## Initialize with callables for loading a downloaded map file into a scene.
## load_map_from_path_fn(path: String) -> Node3D
## finalize_map_loading_fn(map: Node3D) -> void
func setup(load_map_from_path_fn: Callable, finalize_map_loading_fn: Callable) -> void:
	_load_map_from_path_fn = load_map_from_path_fn
	_finalize_map_loading_fn = finalize_map_loading_fn


## Connect to AssetStreamer for map downloads
func connect_asset_streamer() -> void:
	if _streamer_connected:
		return

	if not AssetManager.streamer.asset_received.is_connected(_on_map_received):
		AssetManager.streamer.asset_received.connect(_on_map_received)
	if not AssetManager.streamer.asset_failed.is_connected(_on_map_failed):
		AssetManager.streamer.asset_failed.connect(_on_map_failed)
	if not AssetManager.streamer.transfer_progress.is_connected(_on_map_transfer_progress):
		AssetManager.streamer.transfer_progress.connect(_on_map_transfer_progress)
	_streamer_connected = true


## Disconnect from AssetStreamer signals
func disconnect_asset_streamer() -> void:
	if not _streamer_connected:
		return

	if AssetManager.streamer.asset_received.is_connected(_on_map_received):
		AssetManager.streamer.asset_received.disconnect(_on_map_received)
	if AssetManager.streamer.asset_failed.is_connected(_on_map_failed):
		AssetManager.streamer.asset_failed.disconnect(_on_map_failed)
	if AssetManager.streamer.transfer_progress.is_connected(_on_map_transfer_progress):
		AssetManager.streamer.transfer_progress.disconnect(_on_map_transfer_progress)
	_streamer_connected = false


## Handle map download completion from AssetStreamer
func _on_map_received(
	pack_id: String, asset_id: String, _variant_id: String, local_path: String
) -> void:
	# Only handle map downloads
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return

	# Check if this is the map we're waiting for
	if asset_id != _pending_map_level_folder:
		return

	print("MapDownloadCoordinator: Map downloaded for level: " + asset_id)
	map_download_completed.emit(asset_id)

	# Now load the map
	var map = _load_map_from_path_fn.call(local_path)
	if map:
		_finalize_map_loading_fn.call(map)
	else:
		push_error("MapDownloadCoordinator: Failed to load downloaded map")
		map_download_failed.emit(asset_id, "Failed to load map file")

	_pending_map_level_folder = ""


## Handle map download failure from AssetStreamer
func _on_map_failed(pack_id: String, asset_id: String, _variant_id: String, error: String) -> void:
	# Only handle map downloads
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return

	if asset_id == _pending_map_level_folder:
		push_error("MapDownloadCoordinator: Map download failed: " + error)
		map_download_failed.emit(asset_id, error)
		_pending_map_level_folder = ""


## Handle map download progress
func _on_map_transfer_progress(
	pack_id: String, asset_id: String, _variant_id: String, progress: float
) -> void:
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return

	if asset_id == _pending_map_level_folder:
		map_download_progress.emit(asset_id, progress)


## Get the cached map path for a level (if it exists)
func get_cached_map_path(level_folder: String) -> String:
	return AssetManager.streamer.get_cached_map_path(level_folder)


## Request map download from host
func request_map_download(level_folder: String) -> bool:
	if not AssetManager.streamer.is_enabled():
		push_error("MapDownloadCoordinator: P2P streaming is disabled")
		return false

	_pending_map_level_folder = level_folder
	AssetManager.streamer.request_map_from_host(level_folder)

	print("MapDownloadCoordinator: Requesting map download for level: " + level_folder)
	map_download_started.emit(level_folder)

	# Return true to indicate level loading will continue async
	return true


## Check if a map download is in progress
func is_map_downloading() -> bool:
	return _pending_map_level_folder != ""


## Reset pending download state and disconnect from AssetStreamer.
## Call when exiting PLAYING state.
func reset() -> void:
	_pending_map_level_folder = ""
	disconnect_asset_streamer()
