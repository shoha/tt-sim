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
##   - Ack-based flow control: the host keeps at most SEND_WINDOW_BYTES of chunks
##     unacknowledged per peer and sends more as the client acks them. Over Steam,
##     SteamMultiplayerPeer silently drops reliable messages once about 512 KB is queued
##     (Steam's default send buffer), so a map sent all at once never completed
##     (tests/net/steam_map_download.gd reproduces it over real Steam).

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
## Unacknowledged chunk bytes the host allows per peer, across all of its transfers: half
## of Steam's default 512 KB send buffer, leaving room for game traffic.
const SEND_WINDOW_BYTES := 256 * 1024

## Injected reference to the disk cache (set by AssetManager.setup).
var _cache_manager: Node

## Injected reference to the AssetManager facade (set by AssetManager.setup).
var _asset_manager: Node

## Active transfers on host: peer_id -> {key -> {"parts", "data", "total_chunks",
## "next_chunk", "acked_chunks"}}, in the order they started
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
		resume_from = first_missing_chunk(partial.get("chunks", []))
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


## The index of the first chunk not yet received (null), or the chunk count when every
## chunk is here: where a resumed transfer asks the host to start.
static func first_missing_chunk(chunks: Array) -> int:
	for i in chunks.size():
		if chunks[i] == null:
			return i
	return chunks.size()


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
	var total_chunks := StreamSendWindow.chunk_count(compressed.size(), CHUNK_SIZE)

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

	# Send chunks from the resume point, a window at a time as the client acks them
	_begin_host_transfer(
		peer_id, [pack_id, asset_id, variant_id, file_type], compressed, resume_from_chunk
	)


## Starts (or restarts) the windowed send of `compressed` to a peer from `start_chunk`.
## `parts` is [pack_id, asset_id, variant_id, file_type].
func _begin_host_transfer(
	peer_id: int, parts: Array, compressed: PackedByteArray, start_chunk: int
) -> void:
	var total_chunks := StreamSendWindow.chunk_count(compressed.size(), CHUNK_SIZE)
	var first := clampi(start_chunk, 0, total_chunks)
	var transfers: Dictionary = _host_transfers.get(peer_id, {})
	transfers["/".join(parts)] = {
		"parts": parts,
		"data": compressed,
		"total_chunks": total_chunks,
		"next_chunk": first,
		"acked_chunks": first,
	}
	_host_transfers[peer_id] = transfers
	_pump_peer(peer_id)


## Sends every chunk the peer's window has room for, across that peer's transfers in the
## order they started, and drops transfers the peer has fully acknowledged.
func _pump_peer(peer_id: int) -> void:
	var transfers: Dictionary = _host_transfers.get(peer_id, {})
	for key in transfers.keys():
		var state: Dictionary = transfers[key]
		if state.acked_chunks >= state.total_chunks:
			print(
				(
					"AssetStreamer: Finished sending %s to peer %d (%d chunks)"
					% [key, peer_id, state.total_chunks]
				)
			)
			transfers.erase(key)
	if transfers.is_empty():
		_host_transfers.erase(peer_id)
		return
	var in_flight := 0
	for state in transfers.values():
		in_flight += StreamSendWindow.bytes_in_flight(
			state.next_chunk, state.acked_chunks, state.data.size(), CHUNK_SIZE
		)
	for state in transfers.values():
		var count := StreamSendWindow.chunks_to_send(
			in_flight, SEND_WINDOW_BYTES, CHUNK_SIZE, state.total_chunks - state.next_chunk
		)
		for _i in count:
			var index: int = state.next_chunk
			var start := index * CHUNK_SIZE
			var chunk: PackedByteArray = state.data.slice(
				start, mini(start + CHUNK_SIZE, state.data.size())
			)
			_send_chunk_rpc(peer_id, state.parts, index, chunk)
			state.next_chunk = index + 1
			in_flight += chunk.size()


## Sends one chunk to a peer. Separate so tests can capture the sends.
func _send_chunk_rpc(peer_id: int, parts: Array, index: int, chunk: PackedByteArray) -> void:
	rpc_id(peer_id, "_rpc_asset_chunk", parts[0], parts[1], parts[2], parts[3], index, chunk)


## Host side of an ack: the peer holds every chunk before `received_chunks` of one of its
## transfers. The value comes from the peer, so it only ever moves the ack forward and
## never past what was sent.
func _on_chunk_ack(peer_id: int, key: String, received_chunks: int) -> void:
	var state: Dictionary = _host_transfers.get(peer_id, {}).get(key, {})
	if state.is_empty():
		return
	state.acked_chunks = clampi(received_chunks, state.acked_chunks, state.next_chunk)
	_pump_peer(peer_id)


## RPC: Client acknowledges the chunks of a transfer it holds (client -> host)
@rpc("any_peer", "reliable")
func _rpc_asset_chunk_ack(
	pack_id: String, asset_id: String, variant_id: String, file_type: String, received: int
) -> void:
	if not NetworkManager.is_host():
		return
	var key = "%s/%s/%s/%s" % [pack_id, asset_id, variant_id, file_type]
	_on_chunk_ack(multiplayer.get_remote_sender_id(), key, received)


## Client side of an ack, sent for every chunk stored. Separate so tests can capture it.
func _send_chunk_ack(download: Dictionary, received_chunks: int) -> void:
	rpc_id(
		1,
		"_rpc_asset_chunk_ack",
		download.pack_id,
		download.asset_id,
		download.variant_id,
		download.get("file_type", "model"),
		received_chunks
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

	var download: Dictionary = _client_downloads[key]
	# A resumed download keeps the chunks it already has when the file is unchanged;
	# anything else starts over.
	var resumable: bool = (
		download.get("chunks", []).size() == total_chunks
		and int(download.get("original_size", 0)) == original_size
	)
	download.total_chunks = total_chunks
	download.original_size = original_size
	if not resumable:
		download.chunks = []
		download.chunks.resize(total_chunks)
		download.received_count = 0
		download.received_bytes = 0
		download.acked_prefix = 0

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

	if chunk_index < 0 or chunk_index >= download.chunks.size():
		return

	# Store chunk, counting it once (a resend of a stored chunk adds nothing)
	if download.chunks[chunk_index] == null:
		download.received_count = int(download.get("received_count", 0)) + 1
		download.received_bytes = int(download.get("received_bytes", 0)) + chunk_data.size()
	download.chunks[chunk_index] = chunk_data
	var received: int = download.received_count

	# Ack the unbroken run of chunks from the start, which frees the host's send window
	var prefix := int(download.get("acked_prefix", 0))
	while prefix < download.chunks.size() and download.chunks[prefix] != null:
		prefix += 1
	download.acked_prefix = prefix
	_send_chunk_ack(download, prefix)
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


## Progress of one client download by key ("pack/asset/variant/file_type"):
## {"received_chunks", "total_chunks", "received_bytes"}, or {} when none is active.
func get_download_status(key: String) -> Dictionary:
	if not _client_downloads.has(key):
		return {}
	var download: Dictionary = _client_downloads[key]
	return {
		"received_chunks": int(download.get("received_count", 0)),
		"total_chunks": int(download.get("total_chunks", 0)),
		"received_bytes": int(download.get("received_bytes", 0)),
	}


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
