extends Node
class_name LevelPlayController

## Manages level playback: loading maps, spawning tokens, tracking state.
## Extracted from MapMenuController to follow single-responsibility principle.

signal level_loaded(level_data: LevelData)
signal level_cleared()
signal token_spawned(token: BoardToken, placement: TokenPlacement)
signal token_added(token: BoardToken)

const RECONCILIATION_INTERVAL: float = 2.0 # Full state sync every 2 seconds

var active_level_data: LevelData = null
var spawned_tokens: Dictionary = {} # placement_id -> BoardToken
var loaded_map_instance: Node3D = null
var _game_map: GameMap = null
var _reconciliation_timer: Timer = null


## Initialize with a reference to the game map
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_setup_reconciliation_timer()

	# Listen for network state changes to update token interactivity
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


func _setup_reconciliation_timer() -> void:
	if _reconciliation_timer:
		return

	_reconciliation_timer = Timer.new()
	_reconciliation_timer.wait_time = RECONCILIATION_INTERVAL
	_reconciliation_timer.autostart = false
	_reconciliation_timer.timeout.connect(_on_reconciliation_timeout)
	add_child(_reconciliation_timer)


func _on_reconciliation_timeout() -> void:
	# Only host broadcasts reconciliation
	if not NetworkManager.is_host():
		return

	# Sync all token positions to catch any physics drift
	broadcast_token_positions()


func _on_connection_state_changed(_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState) -> void:
	_update_all_token_state()


## Update interactivity and visibility for all spawned tokens based on player role
## Only GM can interact with tokens, players can only view
## Hidden tokens are semi-transparent for GM, invisible for players
func _update_all_token_state() -> void:
	var can_interact = NetworkManager.is_gm() or not NetworkManager.is_networked()
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
		if is_instance_valid(token):
			token.set_interactive(can_interact)
			# Refresh visibility visuals based on current role
			token._update_visibility_visuals()


## Load and play a level
func play_level(level_data: LevelData) -> bool:
	if not _game_map:
		push_error("LevelPlayController: No GameMap set. Call setup() first.")
		return false

	# Clear any previously loaded level first
	clear_level()

	# Store reference to active level
	active_level_data = level_data

	# Load the map model from level data
	if not _load_level_map(level_data):
		push_error("LevelPlayController: Failed to load map")
		return false

	var drag_and_drop = _game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("LevelPlayController: Could not find DragAndDrop3D node")
		return false

	# Spawn all tokens from the level
	for placement in level_data.token_placements:
		var token = BoardTokenFactory.create_from_placement(placement)
		if token:
			drag_and_drop.add_child(token)
			_track_token(token, placement)
			_connect_token_context_menu(token)
			token_spawned.emit(token, placement)

	level_loaded.emit(level_data)

	# Start reconciliation timer for networked games
	if NetworkManager.is_host() and _reconciliation_timer:
		_reconciliation_timer.start()

	return true


## Load the map model from level data
func _load_level_map(level_data: LevelData) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.queue_free()
		loaded_map_instance = null

	# Clear any existing map children from the game map
	_clear_existing_maps()

	# Check for valid map path
	if level_data.map_path == "":
		push_error("LevelPlayController: No map path in level data")
		return false

	if not ResourceLoader.exists(level_data.map_path):
		push_error("LevelPlayController: Map file not found: " + level_data.map_path)
		return false

	# Load and instantiate the map
	var map_scene = load(level_data.map_path)
	if not map_scene:
		push_error("LevelPlayController: Failed to load map scene")
		return false

	loaded_map_instance = map_scene.instantiate() as Node3D
	if not loaded_map_instance:
		push_error("LevelPlayController: Map is not a Node3D")
		return false

	loaded_map_instance.name = "LevelMap"
	loaded_map_instance.scale = level_data.map_scale
	loaded_map_instance.position = level_data.map_offset

	# Add to the GameMap node
	_game_map.add_child(loaded_map_instance)

	return true


## Track a spawned token
func _track_token(token: BoardToken, placement: TokenPlacement) -> void:
	spawned_tokens[placement.placement_id] = token

	# Only GM can interact with tokens, players can only view
	token.set_interactive(NetworkManager.is_gm() or not NetworkManager.is_networked())

	# Register with GameState for network synchronization
	if GameState.has_authority():
		GameState.register_token_from_board_token(token)

		# Connect to token signals for state change broadcasting
		_connect_token_state_signals(token)


## Connect to token signals for broadcasting state changes over network
func _connect_token_state_signals(token: BoardToken) -> void:
	if not GameState.has_authority():
		return

	# Property changes use reliable channel (important, must arrive)
	# Use lambdas to ignore signal arguments and just pass the token
	token.health_changed.connect(func(_cur, _max, _old = null): _on_token_property_changed(token))
	token.token_visibility_changed.connect(func(_visible): _on_token_property_changed(token))
	token.status_effect_added.connect(func(_effect): _on_token_property_changed(token))
	token.status_effect_removed.connect(func(_effect): _on_token_property_changed(token))
	token.died.connect(func(): _on_token_property_changed(token))
	token.revived.connect(func(): _on_token_property_changed(token))

	# Transform changes use unreliable channel with rate limiting (high-frequency, can drop)
	token.position_changed.connect(func(): _on_token_transform_changed(token))
	token.rotation_changed.connect(func(): _on_token_transform_changed(token))
	token.scale_changed.connect(func(): _on_token_transform_changed(token))
	token.transform_updated.connect(func(): _on_token_transform_changed(token))


## Handle property changes (health, visibility, status) - uses reliable channel
func _on_token_property_changed(token: BoardToken) -> void:
	if not NetworkManager.is_host():
		return
	NetworkStateSync.broadcast_token_properties(token)


## Handle transform changes (position, rotation, scale) - uses unreliable channel with rate limiting
func _on_token_transform_changed(token: BoardToken) -> void:
	if not NetworkManager.is_host():
		return
	NetworkStateSync.broadcast_token_transform(token)


## Connect token's context menu signal to game map
func _connect_token_context_menu(token: BoardToken) -> void:
	var token_controller = token.get_controller_component()
	if token_controller and token_controller.has_signal("context_menu_requested"):
		if _game_map.has_method("_on_token_context_menu_requested"):
			token_controller.context_menu_requested.connect(_game_map._on_token_context_menu_requested)


## Clear any existing map models from the game map
func _clear_existing_maps() -> void:
	if not _game_map:
		return

	# List of node names/types to preserve (not maps)
	var preserved_names = ["MapMenu", "DragAndDrop3D", "LevelMap", "CameraHolder", "PixelateCanvas", "SharpenCanvas"]

	for child in _game_map.get_children():
		# Skip UI nodes, environments, and the drag-and-drop container
		if child.name in preserved_names:
			continue
		if child is Control or child is CanvasLayer:
			continue
		# If it's a Node3D that's not one of our known nodes, it's likely a map model
		if child is Node3D:
			child.queue_free()


## Spawn an asset token and add it to the current level
## Returns the created token, or null if spawning failed
## Supports remote assets - will show placeholder while downloading
func spawn_asset(pack_id: String, asset_id: String, variant_id: String = "default") -> BoardToken:
	if not _game_map or not active_level_data:
		push_warning("LevelPlayController: Cannot spawn asset - no GameMap or active level")
		return null

	# Use async factory to support remote asset downloading
	var result = BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)
	var token = result.token as BoardToken

	if not token:
		push_error("LevelPlayController: Failed to create board token for %s/%s" % [pack_id, asset_id])
		return null

	if result.is_placeholder:
		print("LevelPlayController: Spawning placeholder for %s/%s (downloading...)" % [pack_id, asset_id])

	_game_map.drag_and_drop_node.add_child(token)
	_connect_token_context_menu(token)
	add_token_to_level(token, pack_id, asset_id, variant_id)
	token_added.emit(token)
	return token


## Add a new token to the active level
func add_token_to_level(token: BoardToken, pack_id: String, asset_id: String, variant_id: String = "default") -> void:
	if not active_level_data:
		return

	# Create a new placement for this token
	var placement = TokenPlacement.new()
	placement.pack_id = pack_id
	placement.asset_id = asset_id
	placement.variant_id = variant_id
	placement.position = Vector3.ZERO # Will be updated when saved

	# Set default name from asset
	placement.token_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)

	# Add to level data
	active_level_data.add_token_placement(placement)

	# Track the token with metadata
	token.set_meta("placement_id", placement.placement_id)
	token.set_meta("pack_id", pack_id)
	token.set_meta("asset_id", asset_id)
	token.set_meta("variant_id", variant_id)
	spawned_tokens[placement.placement_id] = token

	# Only GM can interact with tokens, players can only view
	token.set_interactive(NetworkManager.is_gm() or not NetworkManager.is_networked())

	# Register with GameState for network synchronization
	if GameState.has_authority():
		GameState.register_token_from_board_token(token)
		_connect_token_state_signals(token)
		# Broadcast new token to clients (use full state so clients can create the token)
		if NetworkManager.is_host():
			NetworkStateSync.broadcast_full_state()


## Save current token positions to level data
func save_token_positions() -> String:
	if not active_level_data:
		push_error("LevelPlayController: No active level to save")
		return ""

	# Update map position and scale from the loaded map instance
	if is_instance_valid(loaded_map_instance):
		active_level_data.map_scale = loaded_map_instance.scale
		active_level_data.map_offset = loaded_map_instance.position

	# Update each placement with current token position
	for placement in active_level_data.token_placements:
		if spawned_tokens.has(placement.placement_id):
			var token = spawned_tokens[placement.placement_id] as BoardToken
			if is_instance_valid(token):
				_sync_placement_from_token(placement, token)
				# Also sync to GameState
				if GameState.has_authority():
					GameState.sync_from_board_token(token)

	# Broadcast updated state to clients
	if NetworkManager.is_host():
		NetworkStateSync.broadcast_full_state()

	# Save the level
	return LevelManager.save_level(active_level_data)


## Sync all token positions to network (call after drags, etc.)
## Uses full state broadcast for reconciliation to ensure consistency
func broadcast_token_positions() -> void:
	if not NetworkManager.is_host():
		return

	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
		if is_instance_valid(token):
			GameState.sync_from_board_token(token)

	# Use full state for reconciliation to ensure all clients are in sync
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


## Clear spawned tokens
func clear_level_tokens() -> void:
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id]
		if is_instance_valid(token):
			token.queue_free()

	spawned_tokens.clear()
	active_level_data = null

	# Clear GameState
	GameState.clear_all_tokens()


## Clear the loaded level map
func clear_level_map() -> void:
	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.queue_free()
		loaded_map_instance = null


## Clear everything from the current level
func clear_level() -> void:
	# Stop reconciliation timer
	if _reconciliation_timer:
		_reconciliation_timer.stop()

	# Clear network sync throttle state
	NetworkStateSync.clear_throttle_state()

	clear_level_tokens()
	clear_level_map()
	level_cleared.emit()


## Check if a level is currently loaded
func has_active_level() -> bool:
	return active_level_data != null


## Get token count
func get_token_count() -> int:
	return spawned_tokens.size()
