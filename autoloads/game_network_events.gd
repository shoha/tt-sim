extends Node

## Centralized event bus for game networking events.
## Provides a single subscription point for all network-related events.
##
## Architecture:
##   - Aggregates events from NetworkManager, NetworkStateSync, AssetStreamer
##   - Provides typed signals for cleaner code
##   - Reduces coupling between network producers and consumers
##   - Enables easier debugging and logging of network events
##
## Usage:
##   GameNetworkEvents.connection_established.connect(_on_connected)
##   GameNetworkEvents.token_state_received.connect(_on_token_update)
##
## Note: This is separate from netfox's NetworkEvents which handles low-level
## network timing and rollback. This focuses on game-level events.

# =============================================================================
# CONNECTION EVENTS
# =============================================================================

## Emitted when successfully connected as host or client
signal connection_established(is_host: bool)

## Emitted when connection is lost or disconnected
signal connection_lost(reason: String)

## Emitted when connection attempt fails
signal connection_failed(reason: String)

## Emitted when a peer joins the game
signal peer_joined(peer_id: int, player_info: Dictionary)

## Emitted when a peer leaves the game
signal peer_left(peer_id: int)

## Emitted when room code is received (host only)
signal room_code_ready(code: String)

# =============================================================================
# GAME STATE EVENTS
# =============================================================================

## Emitted when game is starting (host notifies clients)
signal game_starting

## Emitted when level data is received from host
signal level_received(level_data: Dictionary)

## Emitted when full game state is received (initial sync or reconciliation)
signal full_state_received(state: Dictionary)

## Emitted when a late joiner has been fully synchronized
signal late_joiner_synced(peer_id: int)

# =============================================================================
# TOKEN SYNC EVENTS
# =============================================================================

## Emitted when a token's transform is updated (high frequency, unreliable)
signal token_transform_updated(
	network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)

## Emitted when a token's properties are updated (reliable)
signal token_state_updated(network_id: String, state: Dictionary)

## Emitted when a batch of transforms is received
signal token_transforms_batch_updated(batch: Dictionary)

## Emitted when a token is added to the game
signal token_added(network_id: String, state: Dictionary)

## Emitted when a token is removed from the game
signal token_removed(network_id: String)

# =============================================================================
# ASSET STREAMING EVENTS
# =============================================================================

## Emitted when an asset download/stream starts
signal asset_transfer_started(pack_id: String, asset_id: String, variant_id: String)

## Emitted during asset transfer progress
signal asset_transfer_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float
)

## Emitted when an asset transfer completes
signal asset_transfer_completed(
	pack_id: String, asset_id: String, variant_id: String, local_path: String
)

## Emitted when an asset transfer fails
signal asset_transfer_failed(pack_id: String, asset_id: String, variant_id: String, error: String)

# =============================================================================
# SYNC CONTROL EVENTS
# =============================================================================

## Emitted when sync should be requested (e.g., after reconnect)
signal sync_requested

## Emitted when level sync is complete for a peer
signal level_sync_complete(peer_id: int)

## Emitted when state sync is complete for a peer
signal state_sync_complete(peer_id: int)

# =============================================================================
# INTERNAL STATE
# =============================================================================

var _connected := false
var _is_host := false


func _ready() -> void:
	# Defer signal connections to ensure autoloads are ready
	call_deferred("_connect_all_signals")


func _connect_all_signals() -> void:
	_connect_network_manager_signals()
	_connect_network_state_sync_signals()
	_connect_asset_signals()


func _connect_network_manager_signals() -> void:
	# Connection events
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.room_code_received.is_connected(_on_room_code_received):
		NetworkManager.room_code_received.connect(_on_room_code_received)

	# Player events
	if not NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.connect(_on_player_joined)
	if not NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.connect(_on_player_left)

	# Game events
	if not NetworkManager.game_starting.is_connected(_on_game_starting):
		NetworkManager.game_starting.connect(_on_game_starting)
	if not NetworkManager.level_data_received.is_connected(_on_level_data_received):
		NetworkManager.level_data_received.connect(_on_level_data_received)
	if not NetworkManager.game_state_received.is_connected(_on_game_state_received):
		NetworkManager.game_state_received.connect(_on_game_state_received)
	if not NetworkManager.late_joiner_connected.is_connected(_on_late_joiner_connected):
		NetworkManager.late_joiner_connected.connect(_on_late_joiner_connected)

	# Token events
	if not NetworkManager.token_transform_received.is_connected(_on_token_transform_received):
		NetworkManager.token_transform_received.connect(_on_token_transform_received)
	if not NetworkManager.transform_batch_received.is_connected(_on_transform_batch_received):
		NetworkManager.transform_batch_received.connect(_on_transform_batch_received)
	if not NetworkManager.token_state_received.is_connected(_on_token_state_received):
		NetworkManager.token_state_received.connect(_on_token_state_received)
	if not NetworkManager.token_removed_received.is_connected(_on_token_removed_received):
		NetworkManager.token_removed_received.connect(_on_token_removed_received)


func _connect_network_state_sync_signals() -> void:
	if not NetworkStateSync.full_state_received.is_connected(_on_full_state_sync_received):
		NetworkStateSync.full_state_received.connect(_on_full_state_sync_received)


func _connect_asset_signals() -> void:
	# AssetDownloader
	if not AssetDownloader.download_completed.is_connected(_on_download_completed):
		AssetDownloader.download_completed.connect(_on_download_completed)
	if not AssetDownloader.download_failed.is_connected(_on_download_failed):
		AssetDownloader.download_failed.connect(_on_download_failed)
	if not AssetDownloader.download_progress.is_connected(_on_download_progress):
		AssetDownloader.download_progress.connect(_on_download_progress)

	# AssetStreamer
	if not AssetStreamer.asset_received.is_connected(_on_stream_completed):
		AssetStreamer.asset_received.connect(_on_stream_completed)
	if not AssetStreamer.asset_failed.is_connected(_on_stream_failed):
		AssetStreamer.asset_failed.connect(_on_stream_failed)
	if not AssetStreamer.transfer_progress.is_connected(_on_stream_progress):
		AssetStreamer.transfer_progress.connect(_on_stream_progress)


# =============================================================================
# SIGNAL HANDLERS - CONNECTION
# =============================================================================


func _on_connection_state_changed(old_state: int, new_state: int) -> void:
	# NetworkManager.ConnectionState enum values
	const OFFLINE = 0
	const _CONNECTING = 1  # Unused but kept for documentation
	const HOSTING = 2
	const JOINED = 3

	if new_state == HOSTING or new_state == JOINED:
		_connected = true
		_is_host = (new_state == HOSTING)
		connection_established.emit(_is_host)
	elif old_state != OFFLINE and new_state == OFFLINE:
		_connected = false
		connection_lost.emit("Disconnected")


func _on_connection_failed(reason: String) -> void:
	_connected = false
	connection_failed.emit(reason)


func _on_room_code_received(code: String) -> void:
	room_code_ready.emit(code)


func _on_player_joined(peer_id: int, player_info: Dictionary) -> void:
	peer_joined.emit(peer_id, player_info)


func _on_player_left(peer_id: int) -> void:
	peer_left.emit(peer_id)


# =============================================================================
# SIGNAL HANDLERS - GAME STATE
# =============================================================================


func _on_game_starting() -> void:
	game_starting.emit()


func _on_level_data_received(level_dict: Dictionary) -> void:
	level_received.emit(level_dict)


func _on_game_state_received(state_dict: Dictionary) -> void:
	full_state_received.emit(state_dict)


func _on_full_state_sync_received(state_dict: Dictionary) -> void:
	full_state_received.emit(state_dict)


func _on_late_joiner_connected(peer_id: int) -> void:
	late_joiner_synced.emit(peer_id)


# =============================================================================
# SIGNAL HANDLERS - TOKEN SYNC
# =============================================================================


func _on_token_transform_received(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	token_transform_updated.emit(network_id, pos, rot, scl)


func _on_transform_batch_received(batch: Dictionary) -> void:
	token_transforms_batch_updated.emit(batch)


func _on_token_state_received(network_id: String, token_dict: Dictionary) -> void:
	token_state_updated.emit(network_id, token_dict)


func _on_token_removed_received(network_id: String) -> void:
	token_removed.emit(network_id)


# =============================================================================
# SIGNAL HANDLERS - ASSETS
# =============================================================================


func _on_download_completed(
	pack_id: String, asset_id: String, variant_id: String, local_path: String
) -> void:
	asset_transfer_completed.emit(pack_id, asset_id, variant_id, local_path)


func _on_download_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String
) -> void:
	asset_transfer_failed.emit(pack_id, asset_id, variant_id, error)


func _on_download_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float
) -> void:
	asset_transfer_progress.emit(pack_id, asset_id, variant_id, progress)


func _on_stream_completed(
	pack_id: String, asset_id: String, variant_id: String, local_path: String
) -> void:
	asset_transfer_completed.emit(pack_id, asset_id, variant_id, local_path)


func _on_stream_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String
) -> void:
	asset_transfer_failed.emit(pack_id, asset_id, variant_id, error)


func _on_stream_progress(
	pack_id: String, asset_id: String, variant_id: String, progress: float
) -> void:
	asset_transfer_progress.emit(pack_id, asset_id, variant_id, progress)


# =============================================================================
# PUBLIC API
# =============================================================================


## Check if currently connected to a game
func is_connected_to_game() -> bool:
	return _connected


## Check if we're the host
func is_hosting() -> bool:
	return _connected and _is_host


## Request a full state sync from host (client only)
func request_sync() -> void:
	sync_requested.emit()


## Notify that level sync is complete for a peer (host only)
func notify_level_sync_complete(peer_id: int) -> void:
	level_sync_complete.emit(peer_id)


## Notify that state sync is complete for a peer (host only)
func notify_state_sync_complete(peer_id: int) -> void:
	state_sync_complete.emit(peer_id)
