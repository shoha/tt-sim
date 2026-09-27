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

## Signals
## Every listener must declare all five parameters, file_type included. Godot 4.7
## does not drop extra trailing signal arguments: a handler with fewer parameters
## fails with "Method expected 4 argument(s), but called with 5" and never runs,
## which silently stalled every client map download
## (tests/unit/test_asset_streamer_listeners.gd guards this).
signal asset_received(
	pack_id: String, asset_id: String, variant_id: String, local_path: String, file_type: String
)
signal asset_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String, file_type: String
)
signal transfer_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float, file_type: String
)

const CHUNK_SIZE := 32768  # 32KB chunks
const MAX_CONCURRENT_TRANSFERS := 2
const TRANSFER_TIMEOUT := 60.0  # seconds

## Injected reference to the disk cache (set by AssetManager.setup).
var _cache_manager: Node

## Injected reference to the AssetManager facade (set by AssetManager.setup).
var _asset_manager: Node

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


func _ready() -> void:
	# Load settings
	_load_settings()

	# Connect to multiplayer signals
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Inject dependencies (called by AssetManager after adding to tree).
func setup(cache_manager: Node, asset_manager: Node) -> void:
	_cache_manager = cache_manager
	_asset_manager = asset_manager


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	if err == OK:
		_enabled = config.get_value("network", "p2p_enabled", true)


## Request a map from the host (convenience method)
## Uses the special _level_maps pack_id to stream map files
## @param level_folder: The level folder name (e.g., "my_dungeon")
## @param priority: Download priority (lower = higher priority)
func request_map_from_host(level_folder: String, priority: int = 50) -> void:
	request_map_file_from_host(level_folder, Paths.LEVEL_MAP_VARIANT, priority)


## Request one map file of a level from the host: variant "map" (map.glb) or "ttmap" (the
## authored map.ttmap). Any other variant fails at once, as the host would refuse it.
func request_map_file_from_host(
	level_folder: String, variant_id: String, priority: int = 50
) -> void:
	var file_type := Paths.get_level_map_file_type(variant_id)
	if file_type == "":
		asset_failed.emit(
			Paths.LEVEL_MAPS_PACK_ID, level_folder, variant_id, "Unknown map file", "model"
		)
		return
	request_from_host(Paths.LEVEL_MAPS_PACK_ID, level_folder, variant_id, file_type, priority)


## Request an asset from the host
## Called by AssetDownloader when no URL is available
## @param file_type: "model" or "icon" — determines which path/URL the host resolves
## and which cache slot the client stores the result under.
func request_from_host(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_type: String = "model",
	priority: int = Constants.ASSET_PRIORITY_DEFAULT,
) -> void:
	if not _enabled:
		asset_failed.emit(pack_id, asset_id, variant_id, "P2P streaming disabled", file_type)
		return

	if not multiplayer.has_multiplayer_peer():
		asset_failed.emit(pack_id, asset_id, variant_id, "Not connected to network", file_type)
		return

	if NetworkManager.is_host():
		# Host doesn't need to request from itself - asset should be local
		asset_failed.emit(pack_id, asset_id, variant_id, "Host cannot request from host", file_type)
		return

	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

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
			"file_type": file_type,
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
			"file_type": request.file_type,
			"chunks": [],
			"total_chunks": 0,
			"received_count": 0,
			"original_size": 0,
			"started_at": Time.get_ticks_msec()
		}

	# Send request to host (peer_id 1) with resume info
	rpc_id(
		1,
		"_rpc_request_asset",
		request.pack_id,
		request.asset_id,
		request.variant_id,
		request.file_type,
		resume_from
	)
	print("AssetStreamer: Requesting %s from host (resume_from=%d)" % [key, resume_from])


## Whether a client-requested level map name is authorized to be served: it must sanitize
## (see Paths.sanitize_level_name()) to exactly the level the host currently has active.
## A pack requesting an empty/no active level, or any name that doesn't match after
## sanitization (including traversal payloads, which sanitize to something else entirely
## or fall back to a generated name), is denied. Pure and static specifically so this
## security-critical decision can be unit-tested without a real multiplayer peer.
static func is_level_request_authorized(
	requested_name: String, active_level_folder: String
) -> bool:
	if active_level_folder == "":
		return false
	return Paths.sanitize_level_name(requested_name) == active_level_folder


## The file the host serves for a level map request, or "" to refuse it: the level must be
## authorized (is_level_request_authorized) and the variant one of the two map files
## (Paths.get_level_map_file_for_variant), so neither client-controlled value can name any
## other file. Pure and static for the same reason as is_level_request_authorized.
static func level_map_file_for_request(
	requested_name: String, variant_id: String, active_level_folder: String
) -> String:
	if not is_level_request_authorized(requested_name, active_level_folder):
		return ""
	return Paths.get_level_map_file_for_variant(
		Paths.sanitize_level_name(requested_name), variant_id
	)


## RPC: Client requests an asset from host (with optional resume)
@rpc("any_peer", "reliable")
func _rpc_request_asset(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_type: String = "model",
	resume_from_chunk: int = 0
) -> void:
	if not NetworkManager.is_host():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

	if resume_from_chunk > 0:
		print(
			(
				"AssetStreamer: Peer %d resuming asset %s from chunk %d"
				% [peer_id, key, resume_from_chunk]
			)
		)
	else:
		print("AssetStreamer: Peer %d requesting asset %s" % [peer_id, key])

	# Level map assets: asset_id is a client-controlled level folder name. Only ever serve
	# the level the host currently has loaded — never an arbitrary saved level, and never a
	# path-traversal escape out of user://levels/. Extracted into a static helper (rather
	# than left inline) so this security-critical decision is unit-testable without a real
	# multiplayer peer -- see is_level_request_authorized() and its tests.
	# The variant names which map file (whitelist: "map" -> map.glb, "ttmap" -> map.ttmap).
	if pack_id == Paths.LEVEL_MAPS_PACK_ID:
		var file_path := level_map_file_for_request(
			asset_id, variant_id, NetworkManager.get_current_level_folder()
		)
		if file_path == "":
			push_warning(
				(
					"AssetStreamer: Peer %d requested map file '%s' of level '%s' -- %s"
					% [peer_id, variant_id, asset_id, "not a map file of the active level, denied"]
				)
			)
			rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id, file_type)
			return

		if not FileAccess.file_exists(file_path):
			rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id, file_type)
			return

		_send_asset_to_peer(
			peer_id, pack_id, asset_id, variant_id, file_type, file_path, resume_from_chunk
		)
		return

	# If the pack has a public URL, redirect the client to HTTP rather than
	# streaming through the relay (faster, zero relay bandwidth).
	var url: String = (
		_asset_manager.get_model_url(pack_id, asset_id, variant_id)
		if file_type == "model"
		else _asset_manager.get_icon_url(pack_id, asset_id, variant_id)
	)
	if url != "":
		print("AssetStreamer: Redirecting peer %d to URL for %s" % [peer_id, key])
		rpc_id(peer_id, "_rpc_redirect_to_url", pack_id, asset_id, variant_id, file_type, url)
		return

	# Resolve the file path based on file_type
	var file_path: String = (
		_asset_manager.get_model_path(pack_id, asset_id, variant_id)
		if file_type == "model"
		else _asset_manager.get_icon_path(pack_id, asset_id, variant_id)
	)

	if file_path == "" or not FileAccess.file_exists(file_path):
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id, file_type)
		return

	# Read and send the file (with resume support)
	_send_asset_to_peer(
		peer_id, pack_id, asset_id, variant_id, file_type, file_path, resume_from_chunk
	)


## Send an asset file to a peer in chunks (with resume support)
func _send_asset_to_peer(
	peer_id: int,
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_type: String,
	file_path: String,
	resume_from_chunk: int = 0
) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		rpc_id(peer_id, "_rpc_asset_not_found", pack_id, asset_id, variant_id, file_type)
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
				"%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type],
				peer_id,
				compressed.size(),
				total_chunks,
				resume_from_chunk
			]
		)
	)

	# Send header (always send so client knows total)
	rpc_id(
		peer_id,
		"_rpc_asset_header",
		pack_id,
		asset_id,
		variant_id,
		file_type,
		total_chunks,
		data.size()
	)

	# Send chunks starting from resume point (spread across frames to avoid blocking)
	_send_chunks_async(
		peer_id,
		pack_id,
		asset_id,
		variant_id,
		file_type,
		compressed,
		total_chunks,
		resume_from_chunk
	)


## Async chunk sending to avoid blocking (with resume support)
func _send_chunks_async(
	peer_id: int,
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_type: String,
	compressed: PackedByteArray,
	total_chunks: int,
	start_chunk: int = 0
) -> void:
	for i in range(start_chunk, total_chunks):
		var start = i * CHUNK_SIZE
		var end = mini(start + CHUNK_SIZE, compressed.size())
		var chunk = compressed.slice(start, end)

		rpc_id(peer_id, "_rpc_asset_chunk", pack_id, asset_id, variant_id, file_type, i, chunk)

		# Yield every few chunks to avoid blocking
		if (i - start_chunk) % 4 == 3:
			await get_tree().process_frame
			if not is_instance_valid(self):
				return

	var chunks_sent = total_chunks - start_chunk
	print(
		(
			"AssetStreamer: Finished sending %s/%s/%s/%s to peer %d (%d chunks)"
			% [pack_id, asset_id, variant_id, file_type, peer_id, chunks_sent]
		)
	)


## RPC: Asset not found on host
@rpc("authority", "reliable")
func _rpc_asset_not_found(
	pack_id: String, asset_id: String, variant_id: String, file_type: String = "model"
) -> void:
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]
	_client_downloads.erase(key)

	push_error("AssetStreamer: Asset not found on host: " + key)
	asset_failed.emit(pack_id, asset_id, variant_id, "Asset not found on host", file_type)

	_process_request_queue()


## RPC: Host redirects client to download asset from a public URL.
## Avoids relay streaming when the pack has a CDN/GitHub URL.
@rpc("authority", "reliable")
func _rpc_redirect_to_url(
	pack_id: String, asset_id: String, variant_id: String, file_type: String, url: String
) -> void:
	if not NetworkManager.is_client():
		return

	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

	# Clean up P2P state so the concurrency slot is freed and the queue advances.
	_client_downloads.erase(key)
	_partial_transfers.erase(key)
	_request_queue = _request_queue.filter(func(r): return r.key != key)

	print("AssetStreamer: Host redirected %s to URL: %s" % [key, url])

	# Trigger HTTP download. The resolver's _on_http_download_completed callback
	# handles completion → asset_resolved → asset_available → factory upgrade.
	_asset_manager.downloader.request_download(
		pack_id, asset_id, variant_id, url, Constants.ASSET_PRIORITY_DEFAULT, file_type
	)
	_process_request_queue()


## RPC: Asset header (starts a transfer)
@rpc("authority", "reliable")
func _rpc_asset_header(
	pack_id: String,
	asset_id: String,
	variant_id: String,
	file_type: String,
	total_chunks: int,
	original_size: int
) -> void:
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

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
	file_type: String,
	chunk_index: int,
	chunk_data: PackedByteArray
) -> void:
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]

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
	transfer_progress.emit(pack_id, asset_id, variant_id, progress, file_type)

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

	var file_type: String = download.get("file_type", "model")

	if data.size() != download.original_size:
		push_error("AssetStreamer: Decompression failed for " + key)
		asset_failed.emit(
			download.pack_id,
			download.asset_id,
			download.variant_id,
			"Decompression failed",
			file_type
		)
		_client_downloads.erase(key)
		_process_request_queue()
		return

	# Store via AssetCacheManager
	var cache_path = _cache_manager.store_asset(
		download.pack_id, download.asset_id, download.variant_id, data, file_type
	)
	if cache_path == "":
		push_error("AssetStreamer: Failed to store asset in cache")
		asset_failed.emit(
			download.pack_id,
			download.asset_id,
			download.variant_id,
			"Failed to cache file",
			file_type
		)
		_client_downloads.erase(key)
		_process_request_queue()
		return

	print("AssetStreamer: Downloaded and cached %s (%d bytes)" % [key, data.size()])

	# Clean up and emit success
	_client_downloads.erase(key)
	asset_received.emit(
		download.pack_id, download.asset_id, download.variant_id, cache_path, file_type
	)

	_process_request_queue()


## Clean up when a peer disconnects
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
	return get_cached_map_file(level_folder, Paths.LEVEL_MAP_VARIANT, "")


## The cached copy of one map file of a level (variant "map" or "ttmap"), or "" when there
## is none, the variant is unknown, or `expected_hash` is set and differs from the cached
## file's hash; a stale copy is removed so the next request downloads it again.
func get_cached_map_file(level_folder: String, variant_id: String, expected_hash: String) -> String:
	var file_type := Paths.get_level_map_file_type(variant_id)
	if file_type == "":
		return ""
	return _cache_manager.get_cached_path_matching(
		Paths.LEVEL_MAPS_PACK_ID, level_folder, variant_id, file_type, expected_hash
	)


## Check if a map download is in progress for a level
func is_map_downloading(level_folder: String) -> bool:
	var key = "%s/%s/map/model" % [Paths.LEVEL_MAPS_PACK_ID, level_folder]
	return _client_downloads.has(key)


## Check if a map download is queued for a level
func is_map_queued(level_folder: String) -> bool:
	var key = "%s/%s/map/model" % [Paths.LEVEL_MAPS_PACK_ID, level_folder]
	for req in _request_queue:
		if req.key == key:
			return true
	return false
