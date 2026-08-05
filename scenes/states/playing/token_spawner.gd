class_name TokenSpawner

## Owns spawned-token storage and the spawn/track/clear operations that
## mutate it: the placement_id -> BoardToken map, the network_id reverse
## index used for O(1) lookups, and the per-token signal bookkeeping needed
## for clean disconnects.
##
## Extracted from LevelPlayController to give it a single responsibility.
## Level-wide systems that only ever read the tracked tokens (network sync,
## permissions, undo/redo) stay on LevelPlayController; they reach into this
## class via get_spawned_tokens() / _find_token_by_network_id() instead of
## touching the storage directly.
##
## Plain-object sub-component (not a Node): constructed eagerly as a field
## default on LevelPlayController so it is always safe to call even before
## setup()/add_child() -- see MapDownloadCoordinator for the same pattern.

signal token_added(token: BoardToken)

var spawned_tokens: Dictionary = {}  # placement_id -> BoardToken

# Reverse index for O(1) network_id -> placement_id lookup
var _network_id_to_placement: Dictionary = {}  # network_id -> placement_id

# Signal connection tracking for proper disconnect (prevents lambda accumulation)
var _token_signal_connections: Dictionary = {}  # network_id -> Dictionary with handlers

var _game_map: GameMap = null
var _get_active_level_data_fn: Callable


## Initialize with a reference to the game map (for context-menu/camera wiring)
## and a callable that returns the currently active level data, which is
## owned by LevelPlayController and changes on every level load.
## get_active_level_data_fn() -> LevelData
func setup(game_map: GameMap, get_active_level_data_fn: Callable) -> void:
	_game_map = game_map
	_get_active_level_data_fn = get_active_level_data_fn


## Get the tracked tokens dictionary (placement_id -> BoardToken). Callers
## outside this class should treat the result as read-only.
func get_spawned_tokens() -> Dictionary:
	return spawned_tokens


## Get the local multiplayer API without requiring Node inheritance.
## Reads it off _game_map (a real, live Node this class already holds a reference to
## and that's guaranteed to be in the tree at both of this method's call sites --
## _track_token()/add_token_to_level() only ever run once a token has actually been
## added as a child under it) rather than (Engine.get_main_loop() as SceneTree).multiplayer,
## which was found to intermittently raise "Invalid access to property or key
## 'multiplayer' on a base object of type 'SceneTree'" when called from deep inside
## the async level-loading coroutine chain (level_loader.gd's _play_level_async,
## itself resumed through several await boundaries, some backed by
## AssetModelCache/GlbUtils' own WorkerThreadPool-based async loading). Node.multiplayer
## is the same underlying SceneMultiplayer the tree-level property would have returned
## (confirmed via probe), so this is a strictly safer way to reach it, not a behavior
## change.
func _get_multiplayer_api() -> MultiplayerAPI:
	return _game_map.multiplayer


## Track a spawned token
func _track_token(token: BoardToken, placement: TokenPlacement) -> void:
	spawned_tokens[placement.placement_id] = token
	_network_id_to_placement[token.network_id] = placement.placement_id

	# GM can interact with all tokens; players only with tokens they control
	var is_gm = NetworkManager.has_gm_access()
	var can_interact = is_gm
	var mp := _get_multiplayer_api()
	if not can_interact and mp.multiplayer_peer:
		can_interact = GameState.has_token_permission(
			token.network_id, mp.get_unique_id(), TokenPermissions.Permission.CONTROL
		)
	token.set_interactive(can_interact)

	# Register with GameState for network synchronization
	if GameState.has_authority():
		GameState.register_token_from_board_token(token)

		# Connect to token signals for state change broadcasting
		_connect_token_state_signals(token)


## Connect to token signals for broadcasting state changes over network.
## Stores callables so they can be disconnected later (prevents lambda accumulation).
func _connect_token_state_signals(token: BoardToken) -> void:
	if not GameState.has_authority():
		return
	_disconnect_token_state_signals(token)

	# Property changes use reliable channel (important, must arrive)
	# Optional args handle varying signal signatures (health_changed has 3 args, died has 0, etc.)
	var prop_handler := func(_a = null, _b = null, _c = null): _on_token_property_changed(token)
	var transform_handler := func(): _on_token_transform_changed(token)

	token.health_changed.connect(prop_handler)
	token.token_visibility_changed.connect(prop_handler)
	token.status_effect_added.connect(prop_handler)
	token.status_effect_removed.connect(prop_handler)
	token.died.connect(prop_handler)
	token.revived.connect(prop_handler)

	# Transform changes use unreliable channel with rate limiting (high-frequency, can drop)
	token.transform_changed.connect(transform_handler)
	token.transform_updated.connect(transform_handler)

	_token_signal_connections[token.network_id] = {
		"token": token,
		"prop_handler": prop_handler,
		"transform_handler": transform_handler,
	}


## Disconnect stored token signal handlers (idempotent).
func _disconnect_token_state_signals(token: BoardToken) -> void:
	if not _token_signal_connections.has(token.network_id):
		return
	var info: Dictionary = _token_signal_connections[token.network_id]
	var t: BoardToken = info["token"]
	if not is_instance_valid(t):
		_token_signal_connections.erase(token.network_id)
		return
	var ph: Callable = info["prop_handler"]
	var th: Callable = info["transform_handler"]
	for sig in [
		t.health_changed,
		t.token_visibility_changed,
		t.status_effect_added,
		t.status_effect_removed,
		t.died,
		t.revived,
	]:
		if sig.is_connected(ph):
			sig.disconnect(ph)
	for sig in [t.transform_changed, t.transform_updated]:
		if sig.is_connected(th):
			sig.disconnect(th)
	_token_signal_connections.erase(token.network_id)


## Handle property changes (health, visibility, status) - uses reliable channel
func _on_token_property_changed(token: BoardToken) -> void:
	# Keep GameState an accurate mirror of the live token for every authority
	# (host or local single-player) so undo/redo and other GameState-based
	# systems see the same values the token actually holds.
	if GameState.has_authority():
		GameState.sync_from_board_token(token)

	if not NetworkManager.is_host():
		return
	NetworkStateSync.broadcast_token_properties(token)


## Handle transform changes (position, rotation, scale) - uses unreliable channel with rate limiting
func _on_token_transform_changed(token: BoardToken) -> void:
	if not NetworkManager.is_host():
		return
	NetworkStateSync.broadcast_token_transform(token)


## Connect token's context menu signal and other per-token signals to game map
func _connect_token_context_menu(token: BoardToken) -> void:
	var token_controller = token.get_controller_component()
	if token_controller and token_controller.has_signal("context_menu_requested"):
		if _game_map and _game_map.has_method("_on_token_context_menu_requested"):
			token_controller.context_menu_requested.connect(
				_game_map._on_token_context_menu_requested
			)

	# Camera shake on token drop (local drops only — signal not emitted for network tokens)
	if _game_map:
		token.token_landed.connect(_on_token_landed.bind(token))

	# Double-click to center camera on token (any player)
	if token_controller and _game_map:
		token_controller.focus_requested.connect(_game_map.focus_camera_on)


## Handle token landing — apply camera shake proportional to drop height and token scale.
## NOTE: Screen shake disabled for now — uncomment the call below to re-enable.
func _on_token_landed(_drop_height: float, _token: BoardToken) -> void:
	pass


## Spawn an asset token and add it to the current level
## Returns the created token, or null if spawning failed
## Supports remote assets - will show placeholder while downloading
## If the model isn't cached yet, a placeholder appears instantly and upgrades
## asynchronously once the model finishes loading (no main-thread stall).
func spawn_asset(
	pack_id: String,
	asset_id: String,
	variant_id: String = "default",
	spawn_position: Vector3 = Vector3.ZERO,
) -> BoardToken:
	var active_level_data: LevelData = _get_active_level_data_fn.call()
	if not _game_map or not active_level_data:
		push_warning("TokenSpawner: Cannot spawn asset - no GameMap or active level")
		return null

	# The factory returns the real token if the model is cached, or a placeholder
	# that auto-upgrades when the async load completes (see create_from_asset_async).
	var result = BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)
	var token = result.token as BoardToken

	if not token:
		push_error("TokenSpawner: Failed to create board token for %s/%s" % [pack_id, asset_id])
		return null

	if result.is_placeholder:
		print("TokenSpawner: Spawning placeholder for %s/%s (loading...)" % [pack_id, asset_id])

	_game_map.drag_and_drop_node.add_child(token)

	# Set spawn position before the token renders at origin
	if spawn_position != Vector3.ZERO and token.rigid_body:
		token.rigid_body.global_position = spawn_position

	_connect_token_context_menu(token)
	add_token_to_level(token, pack_id, asset_id, variant_id)
	# Immediate pop-in for single token placement
	token.play_spawn_animation()
	token_added.emit(token)
	return token


## Add a new token to the active level
func add_token_to_level(
	token: BoardToken, pack_id: String, asset_id: String, variant_id: String = "default"
) -> void:
	var active_level_data: LevelData = _get_active_level_data_fn.call()
	if not active_level_data:
		return

	# Create a new placement for this token
	var placement = TokenPlacement.new()
	placement.pack_id = pack_id
	placement.asset_id = asset_id
	placement.variant_id = variant_id
	placement.position = Vector3.ZERO  # Will be updated when saved

	# Set default name from asset
	placement.token_name = AssetManager.get_asset_display_name(pack_id, asset_id)

	# Add to level data
	active_level_data.add_token_placement(placement)

	# Track the token with metadata
	token.set_meta("placement_id", placement.placement_id)
	token.pack_id = pack_id
	token.asset_id = asset_id
	token.variant_id = variant_id
	spawned_tokens[placement.placement_id] = token
	_network_id_to_placement[token.network_id] = placement.placement_id

	# GM can interact with all tokens; players only with tokens they control
	var is_gm = NetworkManager.has_gm_access()
	var can_interact_new = is_gm
	var mp := _get_multiplayer_api()
	if not can_interact_new and mp.multiplayer_peer:
		can_interact_new = GameState.has_token_permission(
			token.network_id, mp.get_unique_id(), TokenPermissions.Permission.CONTROL
		)
	token.set_interactive(can_interact_new)

	# Register with GameState for network synchronization
	if GameState.has_authority():
		GameState.register_token_from_board_token(token)
		_connect_token_state_signals(token)
		# Broadcast new token to clients (use full state so clients can create the token)
		if NetworkManager.is_host():
			NetworkStateSync.broadcast_full_state()


## Sync placement data from a token's current state
func _sync_placement_from_token(placement: TokenPlacement, token: BoardToken) -> void:
	# The rigid_body is what actually gets moved/scaled during dragging
	var rigid_body = token.get_rigid_body()
	if rigid_body:
		placement.position = rigid_body.global_position
		placement.rotation_y = rigid_body.rotation.y
		placement.scale = rigid_body.scale
	else:
		placement.position = token.global_position
		placement.rotation_y = token.rotation.y
		placement.scale = token.scale

	# Also sync current stats
	placement.token_name = token.token_name
	placement.max_health = token.max_health
	placement.current_health = token.current_health
	placement.is_visible_to_players = token.is_visible_to_players
	placement.is_player_controlled = token.is_player_controlled


## Find a token by its network_id in spawned_tokens (O(1) via reverse index).
func _find_token_by_network_id(network_id: String) -> BoardToken:
	var placement_id: String = _network_id_to_placement.get(network_id, "")
	if placement_id == "":
		return null
	var token = spawned_tokens.get(placement_id)
	if token and is_instance_valid(token):
		return token
	return null


## Public wrapper around _find_token_by_network_id for external callers that
## don't have direct access to spawned_tokens (e.g. GameplayActionHistory's
## undo/redo replay, which needs to invoke a live token's real mutators).
func find_token_by_network_id(network_id: String) -> BoardToken:
	return _find_token_by_network_id(network_id)


## Clear spawned tokens
func clear_level_tokens() -> void:
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id]
		if is_instance_valid(token):
			token.queue_free()

	spawned_tokens.clear()
	_network_id_to_placement.clear()

	# Disconnect host-side token signals before clearing the stored callables
	for network_id in _token_signal_connections.keys():
		var info: Dictionary = _token_signal_connections[network_id]
		var t: BoardToken = info["token"]
		if is_instance_valid(t):
			_disconnect_token_state_signals(t)
	_token_signal_connections.clear()


## Handle undo of a token removal: re-create the token from saved state.
func _on_removal_undo_requested(action: Dictionary) -> void:
	if not NetworkManager.has_gm_access() or not _game_map:
		return
	var token_state := TokenState.from_dict(action.token_state_dict)
	var token := RootNetworkHandler.create_token_from_state(token_state)
	if not token:
		UIManager.show_error("Failed to undo token removal")
		return
	_game_map.drag_and_drop_node.add_child(token)
	_track_token_from_undo(token, token_state, action.pack_id, action.asset_id, action.variant_id)
	_connect_token_context_menu(token)
	token.play_spawn_animation()
	if NetworkManager.is_host():
		NetworkStateSync.broadcast_full_state()


## Track a token re-created by undo. Similar to add_token_to_level but
## reuses the original network_id and placement_id.
func _track_token_from_undo(
	token: BoardToken,
	token_state: TokenState,
	pack_id: String,
	asset_id: String,
	variant_id: String,
) -> void:
	token.pack_id = pack_id
	token.asset_id = asset_id
	token.variant_id = variant_id

	var placement_id: String = token_state.network_id
	spawned_tokens[placement_id] = token
	_network_id_to_placement[token.network_id] = placement_id

	token.set_interactive(NetworkManager.has_gm_access())

	if GameState.has_authority():
		GameState.register_token(token_state)
		_connect_token_state_signals(token)


## Get token count
func get_token_count() -> int:
	return spawned_tokens.size()
