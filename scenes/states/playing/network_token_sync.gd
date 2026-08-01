class_name NetworkTokenSync

## Owns host/client network synchronization for spawned tokens: the periodic
## reconciliation broadcast, host-side handling of client-sent transforms and
## drag lock requests, client-side handling of drag lock broadcasts, and
## permission-driven token interactivity (including the client-side transform
## signal wiring/throttled sending used when a client controls a token).
##
## Extracted from LevelPlayController to give it a single responsibility.
## Looks up live tokens via TokenSpawner's get_spawned_tokens() /
## _find_token_by_network_id() instead of owning token storage itself.
##
## Plain-object sub-component (not a Node): constructed eagerly as a field
## default on LevelPlayController -- see TokenSpawner/MapDownloadCoordinator
## for the same pattern. Unlike those two, the TokenSpawner reference is
## injected at construction time via _init() rather than setup(), so that
## _on_client_transform_received() keeps working when called on a bare,
## unconfigured LevelPlayController that never had setup() called on it --
## see tests/unit/test_level_play_controller_transform_validation.gd, which
## does exactly that.
##
## The reconciliation Timer needs a real Node parent to live in the scene
## tree, which this plain object can't provide itself -- setup() receives the
## owning LevelPlayController (a Node) purely to add_child() the timer onto
## it.

const RECONCILIATION_INTERVAL: float = 2.0  # Full state sync every 2 seconds
const CLIENT_TRANSFORM_SEND_INTERVAL: float = 0.05  # 20 updates/sec max (same as host)

var _token_spawner: TokenSpawner
var _reconciliation_timer: Timer = null

# Token permission state
var _client_transform_throttle: Dictionary = {}  # network_id -> last_send_time (client-side)
## network_id -> {"changed": Callable, "updated": Callable}
var _client_connected_tokens: Dictionary = {}


## token_spawner is injected here (not via setup()) so this class always has
## a working reference even before setup() runs -- see class doc comment.
func _init(token_spawner: TokenSpawner) -> void:
	_token_spawner = token_spawner


## Get the local multiplayer API without requiring Node inheritance.
func _get_multiplayer_api() -> MultiplayerAPI:
	return (Engine.get_main_loop() as SceneTree).multiplayer


## Wire up network signal connections and create/parent the reconciliation
## timer. level_play_controller is used only as a Node parent for the timer
## (this class is a plain object and can't add_child() on itself). Safe to
## call repeatedly (e.g. on every PLAYING re-entry) -- signal connections are
## guarded with is_connected() checks.
func setup(level_play_controller: Node) -> void:
	if not _reconciliation_timer:
		_reconciliation_timer = Timer.new()
		_reconciliation_timer.wait_time = RECONCILIATION_INTERVAL
		_reconciliation_timer.autostart = false
		_reconciliation_timer.timeout.connect(_on_reconciliation_timeout)
		level_play_controller.add_child(_reconciliation_timer)

	# Listen for network state changes to update token interactivity
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Token permission signals
	if not GameState.permissions_changed.is_connected(_on_permissions_changed):
		GameState.permissions_changed.connect(_on_permissions_changed)

	# Host-side: listen for client transforms
	if not NetworkManager.client_token_transform_received.is_connected(
		_on_client_transform_received
	):
		NetworkManager.client_token_transform_received.connect(_on_client_transform_received)

	# Host-side: handle client drag lock requests
	if not NetworkManager.client_drag_lock_claimed.is_connected(_on_client_drag_lock_claimed):
		NetworkManager.client_drag_lock_claimed.connect(_on_client_drag_lock_claimed)
	if not NetworkManager.client_drag_lock_released.is_connected(_on_client_drag_lock_released):
		NetworkManager.client_drag_lock_released.connect(_on_client_drag_lock_released)

	# Client-side: receive drag lock broadcasts from host
	if not NetworkManager.drag_lock_granted.is_connected(_on_drag_lock_granted):
		NetworkManager.drag_lock_granted.connect(_on_drag_lock_granted)
	if not NetworkManager.drag_lock_denied.is_connected(_on_drag_lock_denied):
		NetworkManager.drag_lock_denied.connect(_on_drag_lock_denied)
	if not NetworkManager.drag_lock_released.is_connected(_on_drag_lock_released):
		NetworkManager.drag_lock_released.connect(_on_drag_lock_released)


## Disconnect all network signals connected in setup(). Call from
## LevelPlayController._exit_tree().
func teardown() -> void:
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)
	if GameState.permissions_changed.is_connected(_on_permissions_changed):
		GameState.permissions_changed.disconnect(_on_permissions_changed)
	if NetworkManager.client_token_transform_received.is_connected(_on_client_transform_received):
		NetworkManager.client_token_transform_received.disconnect(_on_client_transform_received)
	if NetworkManager.client_drag_lock_claimed.is_connected(_on_client_drag_lock_claimed):
		NetworkManager.client_drag_lock_claimed.disconnect(_on_client_drag_lock_claimed)
	if NetworkManager.client_drag_lock_released.is_connected(_on_client_drag_lock_released):
		NetworkManager.client_drag_lock_released.disconnect(_on_client_drag_lock_released)
	if NetworkManager.drag_lock_granted.is_connected(_on_drag_lock_granted):
		NetworkManager.drag_lock_granted.disconnect(_on_drag_lock_granted)
	if NetworkManager.drag_lock_denied.is_connected(_on_drag_lock_denied):
		NetworkManager.drag_lock_denied.disconnect(_on_drag_lock_denied)
	if NetworkManager.drag_lock_released.is_connected(_on_drag_lock_released):
		NetworkManager.drag_lock_released.disconnect(_on_drag_lock_released)


## Start the reconciliation timer (host-only). Call after a level finishes loading.
func start_reconciliation_timer() -> void:
	if NetworkManager.is_host() and _reconciliation_timer:
		_reconciliation_timer.start()


## Stop the reconciliation timer. Call on level clear.
func stop_reconciliation_timer() -> void:
	if _reconciliation_timer:
		_reconciliation_timer.stop()


## Disconnect all client transform signals and clear throttle state. Call
## from LevelPlayController.clear_level_tokens() -- _client_connected_tokens
## and _client_transform_throttle live here now.
func reset() -> void:
	for network_id in _client_connected_tokens.keys():
		_disconnect_client_transform_signals(network_id)
	_client_transform_throttle.clear()


func _on_reconciliation_timeout() -> void:
	# Only host broadcasts reconciliation
	if not NetworkManager.is_host():
		return

	# Sync all token positions to catch any physics drift
	broadcast_token_positions()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	_update_all_token_state()


## Update interactivity and visibility for all spawned tokens based on player role.
## GM can interact with all tokens, players can only interact with tokens they control.
## Hidden tokens are semi-transparent for GM, invisible for players.
func _update_all_token_state() -> void:
	var is_gm = NetworkManager.has_gm_access()
	var mp := _get_multiplayer_api()
	var my_peer_id = mp.get_unique_id() if mp.multiplayer_peer else 0

	var tokens := _token_spawner.get_spawned_tokens()
	for placement_id in tokens:
		var token = tokens[placement_id] as BoardToken
		if is_instance_valid(token):
			var can_interact = is_gm
			# Players can interact with tokens they have CONTROL permission for
			if not can_interact and my_peer_id > 0:
				can_interact = GameState.has_token_permission(
					token.network_id, my_peer_id, TokenPermissions.Permission.CONTROL
				)
			token.set_interactive(can_interact)
			# Refresh visibility visuals based on current role
			token._update_visibility_visuals()

	# Update client-side transform signal wiring based on permissions
	if not is_gm and NetworkManager.is_networked():
		_update_client_transform_wiring()


## Sync all token positions to network (call after drags, etc.)
## Skips tokens currently under client authority to avoid overwriting GameState
## with stale interpolation data from the host's visual.
func broadcast_token_positions() -> void:
	if not NetworkManager.is_host():
		return

	var tokens := _token_spawner.get_spawned_tokens()
	for placement_id in tokens:
		var token = tokens[placement_id] as BoardToken
		if is_instance_valid(token):
			# Skip tokens currently under client authority:
			# 1. Drag-locked by a non-host peer (client is actively dragging)
			var lock_holder := GameState.get_drag_lock(token.network_id)
			if lock_holder > 1:
				continue
			# 2. Still network-interpolating on the host (client just dropped,
			#    host visual hasn't converged yet)
			if token._dragging_object and token._dragging_object.is_network_interpolating():
				continue
			GameState.sync_from_board_token(token)

	# Use per-token transforms instead of full state blast to avoid
	# clearing client-side permissions and drag locks every 2 seconds.
	_broadcast_reconciliation_transforms()


## Send per-token transform updates for reconciliation instead of a full state
## blast. This avoids the destructive clear-and-rebuild path in
## apply_full_state_dict which clears permissions and drag locks on clients.
func _broadcast_reconciliation_transforms() -> void:
	var tokens := _token_spawner.get_spawned_tokens()
	for placement_id in tokens:
		var token = tokens[placement_id] as BoardToken
		if is_instance_valid(token):
			NetworkStateSync.broadcast_token_transform(token)


## Called when any token permission changes (grant or revoke).
## Updates interactivity for the affected token and manages client transform wiring.
func _on_permissions_changed(network_id: String, _peer_id: int) -> void:
	# If network_id is empty, it's a full permissions sync — update everything
	if network_id == "":
		_update_all_token_state()
		return

	# Update interactivity for the specific token
	var is_gm = NetworkManager.has_gm_access()
	var mp := _get_multiplayer_api()
	var my_peer_id = mp.get_unique_id() if mp.multiplayer_peer else 0

	var token = _token_spawner._find_token_by_network_id(network_id)
	if token:
		var can_interact = is_gm
		if not can_interact and my_peer_id > 0:
			can_interact = GameState.has_token_permission(
				network_id, my_peer_id, TokenPermissions.Permission.CONTROL
			)
		token.set_interactive(can_interact)

	# Update client-side transform signal wiring
	if not is_gm and NetworkManager.is_networked():
		_update_client_transform_wiring()


## Host-side: handle a client-sent token transform.
## Validates permission, applies to local BoardToken and GameState, broadcasts to others.
func _on_client_transform_received(
	sender_id: int,
	network_id: String,
	pos: Vector3,
	rot: Vector3,
	scl: Vector3,
) -> void:
	if not NetworkManager.is_host():
		return

	# Validate that the sender has CONTROL permission
	if not GameState.has_token_permission(
		network_id, sender_id, TokenPermissions.Permission.CONTROL
	):
		return

	# Reject non-finite values so a buggy/malicious client can't inject NaN/Inf into
	# shared state -- this would otherwise propagate to every other client via the
	# broadcast below and to disk on next save.
	if not (pos.is_finite() and rot.is_finite() and scl.is_finite()):
		return

	# Apply transform to the host's local BoardToken (with interpolation)
	var token = _token_spawner._find_token_by_network_id(network_id)
	if not token:
		return  # Token doesn't exist on host — don't update GameState or broadcast
	token.set_interpolation_target(pos, rot, scl)

	# Update GameState
	GameState.update_token_property(network_id, "position", pos)
	GameState.update_token_property(network_id, "rotation", rot)
	GameState.update_token_property(network_id, "scale", scl)

	# Broadcast to all OTHER clients (not the sender)
	NetworkStateSync.broadcast_client_token_transform(network_id, pos, rot, scl, sender_id)


## Host-side: handle a client drag lock claim.
## Grants if the token is free; denies if another peer holds the lock.
func _on_client_drag_lock_claimed(sender_id: int, network_id: String) -> void:
	if not NetworkManager.is_host():
		return

	# Validate CONTROL permission before granting
	if not GameState.has_token_permission(
		network_id, sender_id, TokenPermissions.Permission.CONTROL
	):
		NetworkManager._rpc_drag_lock_denied.rpc_id(sender_id, network_id)
		return

	if GameState.claim_drag_lock(network_id, sender_id):
		# Granted — apply to host's local token and broadcast to all clients
		var token = _token_spawner._find_token_by_network_id(network_id)
		if token:
			token.set_drag_lock(sender_id)
		NetworkManager._rpc_drag_lock_granted.rpc(network_id, sender_id)
	else:
		# Denied — someone else holds the lock
		NetworkManager._rpc_drag_lock_denied.rpc_id(sender_id, network_id)


## Host-side: handle a client drag lock release.
func _on_client_drag_lock_released(sender_id: int, network_id: String) -> void:
	if not NetworkManager.is_host():
		return

	# Only the lock holder can release
	if GameState.get_drag_lock(network_id) != sender_id:
		return

	GameState.release_drag_lock(network_id)

	# Apply to host's local token
	var token = _token_spawner._find_token_by_network_id(network_id)
	if token:
		token.clear_drag_lock()

		# Snap the host's visual to GameState's authoritative position.
		# GameState has the exact position from the client's last RPC,
		# but the host's visual may still be interpolating toward it.
		var state := GameState.get_token_state(network_id)
		if state:
			token.set_transform_immediate(state.position, state.rotation, state.scale)

		# Broadcast the final authoritative position to all clients so
		# everyone converges to the same resting position.
		NetworkStateSync.broadcast_token_transform(token)

	# Broadcast release to all clients
	NetworkManager._rpc_drag_lock_released.rpc(network_id)


## Client-side: another peer (or the host) has locked this token.
## Disables dragging on the local copy.
func _on_drag_lock_granted(network_id: String, locker_peer_id: int) -> void:
	var token = _token_spawner._find_token_by_network_id(network_id)
	if token:
		token.set_drag_lock(locker_peer_id)


## Client-side: this client's lock claim was denied.
## Cancel the in-progress drag via the cancel-settle path.
func _on_drag_lock_denied(network_id: String) -> void:
	var token = _token_spawner._find_token_by_network_id(network_id)
	if not token:
		return
	var draggable := token._dragging_object as DraggableToken
	if draggable:
		draggable.cancel_from_lock_denied()


## Client-side: a drag lock has been released, token is free to drag again.
func _on_drag_lock_released(network_id: String) -> void:
	var token = _token_spawner._find_token_by_network_id(network_id)
	if token:
		token.clear_drag_lock()


## Dynamically connect/disconnect transform signals for tokens this client controls.
## Called when permissions change on the client side.
func _update_client_transform_wiring() -> void:
	var mp := _get_multiplayer_api()
	if not mp.multiplayer_peer:
		return
	var my_peer_id = mp.get_unique_id()

	# Get the list of tokens this client has CONTROL permission for
	var controlled = GameState.get_controlled_tokens(
		my_peer_id, TokenPermissions.Permission.CONTROL
	)

	# Disconnect tokens that are no longer controlled
	var to_disconnect: Array[String] = []
	for network_id in _client_connected_tokens:
		if network_id not in controlled:
			to_disconnect.append(network_id)

	for network_id in to_disconnect:
		_disconnect_client_transform_signals(network_id)

	# Connect tokens that are newly controlled
	for network_id in controlled:
		if network_id not in _client_connected_tokens:
			_connect_client_transform_signals(network_id)


## Connect transform signals for a client-controlled token.
func _connect_client_transform_signals(network_id: String) -> void:
	var token = _token_spawner._find_token_by_network_id(network_id)
	if not token:
		return

	# Store callables so they can be disconnected later
	var changed_callable = func(): _on_client_token_transform_changed(token)
	var updated_callable = func(): _on_client_token_transform_changed(token)
	token.transform_changed.connect(changed_callable)
	token.transform_updated.connect(updated_callable)
	_client_connected_tokens[network_id] = {
		"token": token,
		"changed": changed_callable,
		"updated": updated_callable,
	}


## Disconnect transform signals for a token that is no longer client-controlled.
func _disconnect_client_transform_signals(network_id: String) -> void:
	if not _client_connected_tokens.has(network_id):
		return

	var data: Dictionary = _client_connected_tokens[network_id]
	var token: BoardToken = data.get("token")
	if is_instance_valid(token):
		var changed_callable: Callable = data.get("changed")
		var updated_callable: Callable = data.get("updated")
		if token.transform_changed.is_connected(changed_callable):
			token.transform_changed.disconnect(changed_callable)
		if token.transform_updated.is_connected(updated_callable):
			token.transform_updated.disconnect(updated_callable)

	_client_connected_tokens.erase(network_id)


## Client-side: send a token transform to the host with rate limiting.
func _on_client_token_transform_changed(token: BoardToken) -> void:
	if GameState.has_authority():
		return

	var network_id = token.network_id

	# Rate limiting
	var now = Time.get_ticks_msec() / 1000.0
	var last_send = _client_transform_throttle.get(network_id, 0.0)
	if now - last_send < CLIENT_TRANSFORM_SEND_INTERVAL:
		return
	_client_transform_throttle[network_id] = now

	# Get current transform from the rigid body
	var state = TokenState.from_board_token(token)
	NetworkManager.send_client_token_transform(
		network_id, state.position, state.rotation, state.scale
	)
