extends Node

## Peer-to-peer asset streaming for multiplayer games.
##
## When a client needs an asset that has no external URL, this system
## allows downloading it directly from the host over the game network.
## Uses the disk cache for unified cache management.
##
## Host side: Responds to asset requests by reading and sending local files
## Client side: Requests assets from host when URL-based download is unavailable
##
## This is an internal sub-component of AssetManager. External code should
## access it via AssetManager.streamer rather than as a standalone autoload.
##
## Features:
##   - ZSTD compression for efficient transfer
##   - Chunked transfers with progress tracking
##   - Transfer resume support for interrupted downloads

const CHUNK_SIZE := 32768  # 32KB chunks
const MAX_CONCURRENT_TRANSFERS := 2
const TRANSFER_TIMEOUT := 60.0  # seconds

## Injected reference to the disk cache (set by AssetManager.setup).
var _cache_manager: Node

## Injected reference to the AssetManager facade (set by AssetManager.setup).
var _asset_manager: Node

## Signals
signal asset_received(pack_id: String, asset_id: String, variant_id: String, local_path: String)
signal asset_failed(pack_id: String, asset_id: String, variant_id: String, error: String)
signal transfer_progress(pack_id: String, asset_id: String, variant_id: String, progress: float)

## Active transfers on host (peer_id -> Array of active transfer keys)
var _host_transfers: Dictionary = {}

## Pending downloads on client (key -> download state)
var _client_downloads: Dictionary = {}

## Partial transfers saved for resume (key -> partial state)
var _partial_transfers: Dictionary = {}

## Queue of pending requests on client
var _request_queue: Array[Dictionary] = []

## Whether streaming is enabled
var _enabled: bool = true

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	# Load settings
	_load_settings()

	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Inject dependencies (called by AssetManager after adding to tree).
func setup(cache_manager: Node, asset_manager: Node) -> void:
	_cache_manager = cache_manager
	_asset_manager = asset_manager


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		_enabled = config.get_value("network", "p2p_enabled", true)


## Request a map from the host (convenience method)
## Uses the special _level_maps pack_id to stream map files
## @param level_folder: The level folder name (e.g., "my_dungeon")
## @param priority: Download priority (lower = higher priority)
func request_map_from_host(level_folder: String, priority: int = 50) -> void:
	request_from_host(Paths.LEVEL_MAPS_PACK_ID, level_folder, "map", priority)


## Request an asset from the host
## Called by AssetDownloader when no URL is available
func request_from_host(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	priority: int = Constants.ASSET_PRIORITY_DEFAULT,
) -> void:
	if not _enabled:
		asset_failed.emit(pack_id, asset_id, variant_id, "P2P streaming disabled")
		return

	if not multiplayer.has_multiplayer_peer():
		asset_failed.emit(pack_id, asset_id, variant_id, "Not connected to network")
		return

	if NetworkManager.is_host():
		# Host doesn't need to request from itself - asset should be local
		asset_failed.emit(pack_id, asset_id, variant_id, "Host cannot request from host")
		return

	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	# Already downloading?
	if _client_downloads.has(key):
		return

	# Already queued?
	for req in _request_queue:
		if req.key == key:
			return

	# Queue the request
	_request_queue.append(
		{
			"key": key,
			"pack_id": pack_id,
			"asset_id": asset_id,
			"variant_id": variant_id,
			"priority": priority
		}
	)

	_request_queue.sort_custom(func(a, b): return a.priority < b.priority)
	_process_request_queue()


## Process the request queue
func _process_request_queue() -> void:
	while _client_downloads.size() < MAX_CONCURRENT_TRANSFERS and _request_queue.size() > 0:
		var request = _request_queue.pop_front()
		_start_request(request)


## Start a request to the host
func _start_request(request: Dictionary) -> void:
	var key = request.key

	# Check for partial transfer to resume
	var resume_from: int = 0
	if _partial_transfers.has(key):
		var partial = _partial_transfers[key]
		resume_from = partial.received_count
		_client_downloads[key] = partial.duplicate(true)
		_partial_transfers.erase(key)
		print("AssetStreamer: Resuming %s from chunk %d" % [key, resume_from])
	else:
		_client_downloads[key] = {
			"pack_id": request.pack_id,
			"asset_id": request.asset_id,
			"variant_id": request.variant_id,
			"chunks": [],
			"total_chunks": 0,
			"received_count": 0,
			"original_size": 0,
			"started_at": Time.get_ticks_msec()
		}

	# Send request to host (peer_id 1) with resume info
	rpc_id(
		1, "_rpc_request_asset", request.pack_id, request.asset_id, request.variant_id, resume_from
	)
	print("AssetStreamer: Requesting %s from host (resume_from=%d)" % [key, resume_from])


## RPC: Client requests an asset from host (with optional resume)
@rpc("any_peer", "reliable")
func _rpc_request_asset(
	pack_id: String, asset_id: String, variant_id: String, resume_from_chunk: int = 0
) -> void:
	if not NetworkManager.is_host():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	if resume_from_chunk > 0:
		print(
			(
				"AssetStreamer: Peer %d resuming asset %s from chunk %d"
				% [peer_id, key, resume_from_chunk]
			)
		)
	else:
		print("AssetStreamer: Peer %d requesting asset %s" % [peer_id, key])

	# Resolve the file path based on pack type
	var file_path: String
	if pack_id == Paths.LEVEL_MAPS_PACK_ID:
		# Special handling for level maps - asset_id is the level folder name
		file_path = Paths.get_level_map_path(asset_id)
	else:
		# Regular asset pack - use AssetManager
		file_path = _asset_manager.get_model_path(pack_id, asset_id, variant_id)

	if file_path == "" or not FileAccess.file_exists(file_path):
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id)
		return

	# Read and send the file (with resume support)
	_send_asset_to_peer(peer_id, pack_id, asset_id, variant_id, file_path, resume_from_chunk)


## Send an asset file to a peer in chunks (with resume support)
func _send_asset_to_peer(
	peer_id: int,
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_path: String,
	resume_from_chunk: int = 0
) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id)
		return

	var data = file.get_buffer(file.get_length())
	file.close()

	# Compress the data
	var compressed = data.compress(FileAccess.COMPRESSION_ZSTD)
	var total_chunks = ceili(float(compressed.size()) / CHUNK_SIZE)

	print(
		(
			"AssetStreamer: Sending %s to peer %d (%d bytes, %d chunks, starting from %d)"
			% [
				"%s/%s/%s" % [pack_id, asset_id, variant_id],
				peer_id,
				compressed.size(),
				total_chunks,
				resume_from_chunk
			]
		)
	)

	# Send header (always send so client knows total)
	rpc_id(peer_id, "_rpc_asset_header", pack_id, asset_id, variant_id, total_chunks, data.size())

	# Send chunks starting from resume point (spread across frames to avoid blocking)
	_send_chunks_async(
		peer_id, pack_id, asset_id, variant_id, compressed, total_chunks, resume_from_chunk
	)


## Async chunk sending to avoid blocking (with resume support)
func _send_chunks_async(
	peer_id: int,
	pack_id: String,
	asset_id: String,
	variant_id: String,
	compressed: PackedByteArray,
	total_chunks: int,
	start_chunk: int = 0
) -> void:
	for i in range(start_chunk, total_chunks):
		var start = i * CHUNK_SIZE
		var end = mini(start + CHUNK_SIZE, compressed.size())
		var chunk = compressed.slice(start, end)

		rpc_id(peer_id, "_rpc_asset_chunk", pack_id, asset_id, variant_id, i, chunk)

		# Yield every few chunks to avoid blocking
		if (i - start_chunk) % 4 == 3:
			await get_tree().process_frame

	var chunks_sent = total_chunks - start_chunk
	print(
		(
			"AssetStreamer: Finished sending %s/%s/%s to peer %d (%d chunks)"
			% [pack_id, asset_id, variant_id, peer_id, chunks_sent]
		)
	)


## RPC: Asset not found on host
@rpc("authority", "reliable")
func _rpc_asset_not_found(pack_id: String, asset_id: String, variant_id: String) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	_client_downloads.erase(key)

	push_error("AssetStreamer: Asset not found on host: " + key)
	asset_failed.emit(pack_id, asset_id, variant_id, "Asset not found on host")

	_process_request_queue()


## RPC: Asset header (starts a transfer)
@rpc("authority", "reliable")
func _rpc_asset_header(
	pack_id: String, asset_id: String, variant_id: String, total_chunks: int, original_size: int
) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	if not _client_downloads.has(key):
		return

	_client_downloads[key].total_chunks = total_chunks
	_client_downloads[key].original_size = original_size
	_client_downloads[key].chunks = []
	_client_downloads[key].chunks.resize(total_chunks)

	print("AssetStreamer: Receiving %s (%d chunks, %d bytes)" % [key, total_chunks, original_size])


## RPC: Asset chunk received
@rpc("authority", "reliable")
func _rpc_asset_chunk(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	chunk_index: int,
	chunk_data: PackedByteArray
) -> void:
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]

	if not _client_downloads.has(key):
		return

	var download = _client_downloads[key]

	# Store chunk
	download.chunks[chunk_index] = chunk_data

	# Count received chunks
	var received = 0
	for chunk in download.chunks:
		if chunk != null:
			received += 1

	# Track received count for resume
	download.received_count = received
	download.last_chunk_time = Time.get_ticks_msec()

	# Emit progress
	var progress = float(received) / float(download.total_chunks)
	transfer_progress.emit(pack_id, asset_id, variant_id, progress)

	# Check if complete
	if received >= download.total_chunks:
		_finalize_download(key)


## Finalize a completed download
func _finalize_download(key: String) -> void:
	var download = _client_downloads[key]

	# Combine chunks
	var compressed = PackedByteArray()
	for chunk in download.chunks:
		if chunk != null:
			compressed.append_array(chunk)

	# Decompress
	var data = compressed.decompress(download.original_size, FileAccess.COMPRESSION_ZSTD)

	if data.size() != download.original_size:
		push_error("AssetStreamer: Decompression failed for " + key)
		asset_failed.emit(
			download.pack_id, download.asset_id, download.variant_id, "Decompression failed"
		)
		_client_downloads.erase(key)
		_process_request_queue()
		return

	# Store via AssetCacheManager
	var cache_path = _cache_manager.store_asset(
		download.pack_id, download.asset_id, download.variant_id, data, "model"
	)
	if cache_path == "":
		push_error("AssetStreamer: Failed to store asset in cache")
		asset_failed.emit(
			download.pack_id, download.asset_id, download.variant_id, "Failed to cache file"
		)
		_client_downloads.erase(key)
		_process_request_queue()
		return

	print("AssetStreamer: Downloaded and cached %s (%d bytes)" % [key, data.size()])

	# Clean up and emit success
	_client_downloads.erase(key)
	asset_received.emit(download.pack_id, download.asset_id, download.variant_id, cache_path)

	_process_request_queue()


## Clean up when a peer disconnects
func _on_peer_connected(_peer_id: int) -> void:
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	# Host: Clean up any transfers to this peer
	_host_transfers.erase(peer_id)

	# Client: If we disconnected from host, save partial transfers for resume
	if peer_id == 1:  # Host peer_id
		_save_partial_transfers()


## Save current downloads as partial transfers for resume
func _save_partial_transfers() -> void:
	for key in _client_downloads:
		var download = _client_downloads[key]
		# Only save if we've received some chunks
		if download.get("received_count", 0) > 0:
			_partial_transfers[key] = download.duplicate(true)
			print(
				(
					"AssetStreamer: Saved partial transfer %s (%d/%d chunks)"
					% [key, download.received_count, download.total_chunks]
				)
			)
	_client_downloads.clear()


## Clear partial transfers (call when starting fresh)
func clear_partial_transfers() -> void:
	_partial_transfers.clear()


## Enable or disable P2P streaming
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Check if P2P streaming is enabled
func is_enabled() -> bool:
	return _enabled


## Get the number of active downloads (client side)
func get_active_download_count() -> int:
	return _client_downloads.size()


## Get the number of queued requests (client side)
func get_queued_request_count() -> int:
	return _request_queue.size()


## Get the cached map path for a level (if it exists)
## @param level_folder: The level folder name
## @return: The cached path, or empty string if not cached
func get_cached_map_path(level_folder: String) -> String:
	return _cache_manager.get_cached_path(Paths.LEVEL_MAPS_PACK_ID, level_folder, "map", "model")


## Check if a map download is in progress for a level
func is_map_downloading(level_folder: String) -> bool:
	var key = "%s/%s/map" % [Paths.LEVEL_MAPS_PACK_ID, level_folder]
	return _client_downloads.has(key)


## Check if a map download is queued for a level
func is_map_queued(level_folder: String) -> bool:
	var key = "%s/%s/map" % [Paths.LEVEL_MAPS_PACK_ID, level_folder]
	for req in _request_queue:
		if req.key == key:
			return true
	return false
