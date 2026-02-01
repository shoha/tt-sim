extends Node

## Centralized network state synchronization service.
## Handles bidirectional state sync between host and clients.
##
## Architecture:
##   - Host uses broadcast_* methods to send state to clients
##   - Clients receive state via signals and apply to visuals
##   - Rate limiting prevents network flooding during high-frequency updates
##   - Transform updates use unreliable channel (fast, can drop)
##   - Property updates use reliable channel (must arrive)
##
## Usage:
##   NetworkStateSync.broadcast_token_transform(token)  # Host sends position
##   NetworkStateSync.broadcast_token_properties(token)  # Host sends health/visibility
##   NetworkStateSync.token_transform_received.connect(_on_transform)  # Client listens

## Emitted when a token's transform is received from host (clients only)
signal token_transform_received(network_id: String, position: Vector3, rotation: Vector3, scale: Vector3)

## Emitted when a token's full state is received from host (clients only)
signal token_state_received(network_id: String, token_state: TokenState)

## Emitted when a token is removed on the host (clients only)
signal token_removed_received(network_id: String)

## Emitted when full game state is received (clients only, for initial sync)
signal full_state_received(state_dict: Dictionary)

## Rate limiting for transform updates
const TRANSFORM_SEND_INTERVAL := 0.05  # 20 updates/sec max per token
var _transform_throttle: Dictionary = {}  # network_id -> last_send_time (float)

## Pending transform updates (for batching)
var _pending_transforms: Dictionary = {}  # network_id -> {position, rotation, scale}
var _transform_batch_timer: Timer = null
const TRANSFORM_BATCH_INTERVAL := 0.033  # ~30fps batch rate


func _ready() -> void:
	# Connect to NetworkManager signals for receiving data
	NetworkManager.game_state_received.connect(_on_game_state_received)
	
	# Setup batch timer for transform updates
	_setup_batch_timer()


func _setup_batch_timer() -> void:
	_transform_batch_timer = Timer.new()
	_transform_batch_timer.wait_time = TRANSFORM_BATCH_INTERVAL
	_transform_batch_timer.autostart = true
	_transform_batch_timer.timeout.connect(_flush_pending_transforms)
	add_child(_transform_batch_timer)


# =============================================================================
# HOST-SIDE: BROADCASTING
# =============================================================================

## Broadcast a token's transform (position, rotation, scale) to all clients.
## Uses unreliable channel and rate limiting for efficiency.
## Call this for high-frequency updates like dragging.
func broadcast_token_transform(token: BoardToken) -> void:
	if not NetworkManager.is_host():
		return
	
	var network_id = token.network_id
	
	# Rate limiting check
	var now = Time.get_ticks_msec() / 1000.0
	var last_send = _transform_throttle.get(network_id, 0.0)
	
	if now - last_send < TRANSFORM_SEND_INTERVAL:
		# Queue for next batch instead of sending immediately
		_queue_transform_update(token)
		return
	
	_transform_throttle[network_id] = now
	_send_transform_update(token)


## Queue a transform update for the next batch send
func _queue_transform_update(token: BoardToken) -> void:
	var state = TokenState.from_board_token(token)
	_pending_transforms[token.network_id] = {
		"position": _vector3_to_array(state.position),
		"rotation": _vector3_to_array(state.rotation),
		"scale": _vector3_to_array(state.scale),
	}


## Send a single token's transform immediately
func _send_transform_update(token: BoardToken) -> void:
	var state = TokenState.from_board_token(token)
	
	# Also update GameState
	GameState.sync_from_board_token(token)
	
	# Send via unreliable RPC
	NetworkManager._rpc_receive_token_transform.rpc(
		token.network_id,
		_vector3_to_array(state.position),
		_vector3_to_array(state.rotation),
		_vector3_to_array(state.scale)
	)


## Flush all pending transform updates as a batch
func _flush_pending_transforms() -> void:
	if not NetworkManager.is_host():
		return
	
	if _pending_transforms.is_empty():
		return
	
	# Send batch update
	NetworkManager._rpc_receive_transform_batch.rpc(_pending_transforms.duplicate())
	_pending_transforms.clear()


## Broadcast a token's full state (properties) to all clients.
## Uses reliable channel - call for important changes like health/death.
func broadcast_token_properties(token: BoardToken) -> void:
	if not NetworkManager.is_host():
		return
	
	# Update GameState
	GameState.sync_from_board_token(token)
	
	var state = GameState.get_token_state(token.network_id)
	if not state:
		return
	
	# Send via reliable RPC
	NetworkManager._rpc_receive_token_state.rpc(token.network_id, state.to_dict())


## Broadcast that a token was removed
func broadcast_token_removed(network_id: String) -> void:
	if not NetworkManager.is_host():
		return
	
	NetworkManager._rpc_receive_token_removed.rpc(network_id)


## Broadcast the full game state to all clients (for initial sync or reconciliation)
func broadcast_full_state() -> void:
	if not NetworkManager.is_host():
		return
	
	NetworkManager.broadcast_game_state(GameState.get_full_state_dict())


## Send full state to a specific peer (e.g., late joiner)
func send_full_state_to_peer(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	
	NetworkManager.send_game_state_to_peer(peer_id, GameState.get_full_state_dict())


# =============================================================================
# CLIENT-SIDE: RECEIVING
# =============================================================================

func _on_game_state_received(state_dict: Dictionary) -> void:
	# Apply to GameState
	GameState.apply_full_state_dict(state_dict)
	
	# Emit signal for visual layer
	full_state_received.emit(state_dict)


# =============================================================================
# HELPERS
# =============================================================================

## Convert Vector3 to array for network transmission (more compact than dict)
func _vector3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Convert array back to Vector3
static func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(arr[0], arr[1], arr[2])


## Clear rate limiting state (call when level changes)
func clear_throttle_state() -> void:
	_transform_throttle.clear()
	_pending_transforms.clear()
