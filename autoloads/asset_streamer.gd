extends Node

## Peer-to-peer asset streaming for multiplayer games.
## 
## When a client needs an asset that has no external URL, this system
## allows downloading it directly from the host over the game network.
##
## Host side: Responds to asset requests by reading and sending local files
## Client side: Requests assets from host when URL-based download is unavailable

const CHUNK_SIZE := 32768 # 32KB chunks
const MAX_CONCURRENT_TRANSFERS := 2
const TRANSFER_TIMEOUT := 60.0 # seconds

## Signals
signal asset_received(pack_id: String, asset_id: String, variant_id: String, local_path: String)
signal asset_failed(pack_id: String, asset_id: String, variant_id: String, error: String)
signal transfer_progress(pack_id: String, asset_id: String, variant_id: String, progress: float)


## Active transfers on host (peer_id -> Array of active transfer keys)
var _host_transfers: Dictionary = {}

## Pending downloads on client (key -> download state)
var _client_downloads: Dictionary = {}

## Queue of pending requests on client
var _request_queue: Array[Dictionary] = []

## Whether streaming is enabled
var _enabled: bool = true


func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Request an asset from the host
## Called by AssetDownloader when no URL is available
func request_from_host(pack_id: String, asset_id: String, variant_id: String, priority: int = 100) -> void:
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
	_request_queue.append({
		"key": key,
		"pack_id": pack_id,
		"asset_id": asset_id,
		"variant_id": variant_id,
		"priority": priority
	})
	
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
	
	_client_downloads[key] = {
		"pack_id": request.pack_id,
		"asset_id": request.asset_id,
		"variant_id": request.variant_id,
		"chunks": [],
		"total_chunks": 0,
		"started_at": Time.get_ticks_msec()
	}
	
	# Send request to host (peer_id 1)
	rpc_id(1, "_rpc_request_asset", request.pack_id, request.asset_id, request.variant_id)
	print("AssetStreamer: Requesting %s from host" % key)


## RPC: Client requests an asset from host
@rpc("any_peer", "reliable")
func _rpc_request_asset(pack_id: String, asset_id: String, variant_id: String) -> void:
	if not NetworkManager.is_host():
		return
	
	var peer_id = multiplayer.get_remote_sender_id()
	var key = "%s/%s/%s" % [pack_id, asset_id, variant_id]
	
	print("AssetStreamer: Peer %d requesting asset %s" % [peer_id, key])
	
	# Get the model path
	var model_path = AssetPackManager.get_model_path(pack_id, asset_id, variant_id)
	
	if model_path == "" or not FileAccess.file_exists(model_path):
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id)
		return
	
	# Read and send the file
	_send_asset_to_peer(peer_id, pack_id, asset_id, variant_id, model_path)


## Send an asset file to a peer in chunks
func _send_asset_to_peer(peer_id: int, pack_id: String, asset_id: String, variant_id: String, file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id)
		return
	
	var data = file.get_buffer(file.get_length())
	file.close()
	
	# Compress the data
	var compressed = data.compress(FileAccess.COMPRESSION_ZSTD)
	var total_chunks = ceili(float(compressed.size()) / CHUNK_SIZE)
	
	print("AssetStreamer: Sending %s to peer %d (%d bytes, %d chunks)" % [
		"%s/%s/%s" % [pack_id, asset_id, variant_id],
		peer_id,
		compressed.size(),
		total_chunks
	])
	
	# Send header
	rpc_id(peer_id, "_rpc_asset_header", pack_id, asset_id, variant_id, total_chunks, data.size())
	
	# Send chunks (spread across frames to avoid blocking)
	_send_chunks_async(peer_id, pack_id, asset_id, variant_id, compressed, total_chunks)


## Async chunk sending to avoid blocking
func _send_chunks_async(peer_id: int, pack_id: String, asset_id: String, variant_id: String, compressed: PackedByteArray, total_chunks: int) -> void:
	for i in range(total_chunks):
		var start = i * CHUNK_SIZE
		var end = mini(start + CHUNK_SIZE, compressed.size())
		var chunk = compressed.slice(start, end)
		
		rpc_id(peer_id, "_rpc_asset_chunk", pack_id, asset_id, variant_id, i, chunk)
		
		# Yield every few chunks to avoid blocking
		if i % 4 == 3:
			await get_tree().process_frame
	
	print("AssetStreamer: Finished sending %s/%s/%s to peer %d" % [pack_id, asset_id, variant_id, peer_id])


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
func _rpc_asset_header(pack_id: String, asset_id: String, variant_id: String, total_chunks: int, original_size: int) -> void:
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
func _rpc_asset_chunk(pack_id: String, asset_id: String, variant_id: String, chunk_index: int, chunk_data: PackedByteArray) -> void:
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
		asset_failed.emit(download.pack_id, download.asset_id, download.variant_id, "Decompression failed")
		_client_downloads.erase(key)
		_process_request_queue()
		return
	
	# Save to cache
	var cache_path = "user://asset_cache/%s/%s/%s.glb" % [download.pack_id, download.asset_id, download.variant_id]
	var cache_dir = cache_path.get_base_dir()
	
	if not DirAccess.dir_exists_absolute(cache_dir):
		DirAccess.make_dir_recursive_absolute(cache_dir)
	
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if not file:
		push_error("AssetStreamer: Failed to write cache file: " + cache_path)
		asset_failed.emit(download.pack_id, download.asset_id, download.variant_id, "Failed to write file")
		_client_downloads.erase(key)
		_process_request_queue()
		return
	
	file.store_buffer(data)
	file.close()
	
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
