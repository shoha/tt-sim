extends Node
class_name LevelPlayController

## Manages level playback: loading maps, spawning tokens, tracking state.
## Extracted from MapMenuController to follow single-responsibility principle.
## Supports async map loading for client-side map downloads.
## Uses threaded loading to avoid blocking the main thread.

signal level_loaded(level_data: LevelData)
signal level_cleared
signal token_spawned(token: BoardToken, placement: TokenPlacement)
signal token_added(token: BoardToken)
signal map_download_started(level_folder: String)
signal map_download_progress(level_folder: String, progress: float)
signal map_download_completed(level_folder: String)
signal map_download_failed(level_folder: String, error: String)
signal level_loading_started
signal level_loading_progress(progress: float, status: String)
signal level_loading_completed

const RECONCILIATION_INTERVAL: float = 2.0  # Full state sync every 2 seconds
const TOKENS_PER_FRAME: int = 3  # How many tokens to spawn per frame during progressive loading
const CLIENT_TRANSFORM_SEND_INTERVAL: float = 0.05  # 20 updates/sec max (same as host)

var active_level_data: LevelData = null
var spawned_tokens: Dictionary = {}  # placement_id -> BoardToken
var loaded_map_instance: Node3D = null
var is_editor_preview: bool = false  # True when playing a level from the level editor
var _game_map: GameMap = null
var _reconciliation_timer: Timer = null
var _pending_map_level_folder: String = ""  # Level folder waiting for map download
var _streamer_connected: bool = false
var _is_loading: bool = false  # True while async loading is in progress
var _environment_manager := LevelEnvironmentManager.new()  # Manages lighting/atmosphere

# Token permission state
var _pending_permission_requests: Dictionary = {}  # "network_id:peer_id" -> true (host-side)
var _client_transform_throttle: Dictionary = {}  # network_id -> last_send_time (client-side)
var _client_connected_tokens: Dictionary = {}  # network_id -> { "changed": Callable, "updated": Callable }


## Initialize with a reference to the game map
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_environment_manager.setup(game_map)
	_setup_reconciliation_timer()
	_connect_asset_streamer()

	# Listen for network state changes to update token interactivity
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Listen for visual settings changes from the host (map scale, lighting, environment, lo-fi)
	if not NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.connect(_on_visual_settings_received)

	# Token permission signals
	if not GameState.permissions_changed.is_connected(_on_permissions_changed):
		GameState.permissions_changed.connect(_on_permissions_changed)

	# Host-side: listen for permission requests and client transforms
	if not NetworkManager.token_permission_requested.is_connected(_on_token_permission_requested):
		NetworkManager.token_permission_requested.connect(_on_token_permission_requested)
	if not NetworkManager.client_token_transform_received.is_connected(_on_client_transform_received):
		NetworkManager.client_token_transform_received.connect(_on_client_transform_received)

	# Client-side: listen for permission responses and full permission syncs
	if not NetworkManager.token_permission_response_received.is_connected(_on_permission_response_received):
		NetworkManager.token_permission_response_received.connect(_on_permission_response_received)
	if not NetworkManager.token_permissions_received.is_connected(_on_permissions_received):
		NetworkManager.token_permissions_received.connect(_on_permissions_received)

	# Clean up permissions when a player disconnects
	if not NetworkManager.player_left.is_connected(_on_player_left_permissions):
		NetworkManager.player_left.connect(_on_player_left_permissions)


func _exit_tree() -> void:
	# Disconnect network signals
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)
	if NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.disconnect(_on_visual_settings_received)

	# Disconnect permission signals
	if GameState.permissions_changed.is_connected(_on_permissions_changed):
		GameState.permissions_changed.disconnect(_on_permissions_changed)
	if NetworkManager.token_permission_requested.is_connected(_on_token_permission_requested):
		NetworkManager.token_permission_requested.disconnect(_on_token_permission_requested)
	if NetworkManager.client_token_transform_received.is_connected(_on_client_transform_received):
		NetworkManager.client_token_transform_received.disconnect(_on_client_transform_received)
	if NetworkManager.token_permission_response_received.is_connected(_on_permission_response_received):
		NetworkManager.token_permission_response_received.disconnect(_on_permission_response_received)
	if NetworkManager.token_permissions_received.is_connected(_on_permissions_received):
		NetworkManager.token_permissions_received.disconnect(_on_permissions_received)
	if NetworkManager.player_left.is_connected(_on_player_left_permissions):
		NetworkManager.player_left.disconnect(_on_player_left_permissions)

	# Disconnect AssetStreamer signals
	_disconnect_asset_streamer()


## Connect to AssetStreamer for map downloads
func _connect_asset_streamer() -> void:
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
func _disconnect_asset_streamer() -> void:
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

	print("LevelPlayController: Map downloaded for level: " + asset_id)
	map_download_completed.emit(asset_id)

	# Now load the map
	var map = _load_map_from_path(local_path)
	if map:
		_finalize_map_loading(map)
	else:
		push_error("LevelPlayController: Failed to load downloaded map")
		map_download_failed.emit(asset_id, "Failed to load map file")

	_pending_map_level_folder = ""


## Handle map download failure from AssetStreamer
func _on_map_failed(pack_id: String, asset_id: String, _variant_id: String, error: String) -> void:
	# Only handle map downloads
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return

	if asset_id == _pending_map_level_folder:
		push_error("LevelPlayController: Map download failed: " + error)
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


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	_update_all_token_state()


## Update interactivity and visibility for all spawned tokens based on player role.
## GM can interact with all tokens, players can only interact with tokens they control.
## Hidden tokens are semi-transparent for GM, invisible for players.
func _update_all_token_state() -> void:
	var is_gm = NetworkManager.is_gm() or not NetworkManager.is_networked()
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0

	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
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


## Load and play a level (async version - does not block main thread)
## Returns true if loading started successfully, false on immediate failure
## Listen to level_loaded signal for completion
## Stores pending level data when a new level is requested during loading
var _queued_level_data: LevelData = null


func play_level(level_data: LevelData) -> bool:
	if not _game_map:
		push_error("LevelPlayController: No GameMap set. Call setup() first.")
		return false

	if _is_loading:
		# If we're already loading, queue this level to load after current completes/aborts
		# This handles cases like: host sends new level while client is still loading previous
		push_warning("LevelPlayController: Queueing level (currently loading)")
		_queued_level_data = level_data
		return true  # Return true - level will be loaded when current finishes

	# Start async loading
	_play_level_async(level_data)
	return true


## Internal async implementation of level loading
func _play_level_async(level_data: LevelData) -> void:
	_is_loading = true
	level_loading_started.emit()
	level_loading_progress.emit(0.0, "Preparing...")

	# Yield a few frames to let UI updates process:
	# - Loading overlay fades in
	# - Level editor fades out
	# This prevents the UI from appearing frozen during initial setup
	for i in range(3):
		await get_tree().process_frame

	# Check if we're still valid (user might have navigated away)
	if not _is_valid_for_loading():
		_abort_loading()
		return

	# Clear any previously loaded level first (also clears model cache)
	clear_level()

	# Yield after clearing to let freed nodes process
	await get_tree().process_frame

	# Check validity again after yield
	if not _is_valid_for_loading():
		_abort_loading()
		return

	# Store reference to active level
	active_level_data = level_data

	level_loading_progress.emit(0.05, "Loading map...")

	# Load the map model from level data (async)
	var map_loaded = await _load_level_map_async(level_data)

	# Check validity after async map load
	if not _is_valid_for_loading():
		_abort_loading()
		return

	if not map_loaded:
		push_error("LevelPlayController: Failed to load map")
		_abort_loading()
		return

	var drag_and_drop = _game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("LevelPlayController: Could not find DragAndDrop3D node")
		_abort_loading()
		return

	# Pre-load all unique token models (this is the key optimization)
	# This way each model is loaded only ONCE, then tokens clone from cache
	var total_tokens = level_data.token_placements.size()
	if total_tokens > 0:
		level_loading_progress.emit(0.2, "Loading token models...")

		# Build asset list for preloading
		var assets_to_preload: Array[Dictionary] = []
		for placement in level_data.token_placements:
			assets_to_preload.append(
				{
					"pack_id": placement.pack_id,
					"asset_id": placement.asset_id,
					"variant_id": placement.variant_id
				}
			)

		if assets_to_preload.size() > 0:
			# Pre-load with progress callback (create_static_bodies=false for tokens)
			var _loaded_count = await AssetManager.preload_models(
				assets_to_preload,
				func(loaded: int, total: int):
					var model_progress = 0.2 + (0.4 * loaded / max(total, 1))
					level_loading_progress.emit(
						model_progress, "Loading models... (%d/%d)" % [loaded, total]
					),
				false  # create_static_bodies
			)

		# Check validity after async model preload
		if not _is_valid_for_loading():
			_abort_loading()
			return

	# Now spawn tokens - this is fast since models are already cached
	var spawned_count = 0
	level_loading_progress.emit(0.6, "Spawning tokens...")

	for placement in level_data.token_placements:
		# Check validity before spawning each batch
		if not _is_valid_for_loading():
			_abort_loading()
			return

		var token = BoardTokenFactory.create_from_placement_async(placement).token
		if token and is_instance_valid(drag_and_drop):
			drag_and_drop.add_child(token)
			_track_token(token, placement)
			_connect_token_context_menu(token)
			# Staggered pop-in animation — sequential cascade instead of random
			token.play_spawn_animation(spawned_count * 0.05)
			token_spawned.emit(token, placement)

		spawned_count += 1

		# Yield every batch of tokens to keep UI responsive
		# With cached models, we can spawn more per frame
		if spawned_count % (TOKENS_PER_FRAME * 2) == 0:
			var progress = 0.6 + (0.4 * spawned_count / max(total_tokens, 1))
			level_loading_progress.emit(
				progress, "Spawning tokens... (%d/%d)" % [spawned_count, total_tokens]
			)
			await get_tree().process_frame

	level_loading_progress.emit(1.0, "Complete")

	# Yield a couple frames to let all tokens render before hiding loading screen
	for i in range(2):
		await get_tree().process_frame

	_is_loading = false
	level_loading_completed.emit()
	level_loaded.emit(level_data)

	# Start reconciliation timer for networked games
	if NetworkManager.is_host() and _reconciliation_timer:
		_reconciliation_timer.start()

	# Check if another level was queued during loading
	_process_queued_level()


## Load the map model from level data (async version - does not block main thread)
## Uses threaded file I/O for GLB loading
func _load_level_map_async(level_data: LevelData) -> bool:
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

	# Get the absolute map path
	var map_path = level_data.get_absolute_map_path()
	if map_path == "":
		push_error("LevelPlayController: Cannot resolve map path")
		return false

	# Try to load the map from various sources
	var map: Node3D = null

	# 1. Check if it's a res:// path (legacy format)
	if map_path.begins_with("res://"):
		var result = await GlbUtils.load_map_async(map_path, true, _get_light_intensity_scale())
		if result.success:
			map = result.scene

	# 2. Check if it's a user:// path (folder-based format)
	elif map_path.begins_with("user://"):
		var path_to_load = ""

		if FileAccess.file_exists(map_path):
			path_to_load = map_path
		else:
			# Check cache (for clients who downloaded from host)
			var cached_path = _get_cached_map_path(level_data.level_folder)
			if cached_path != "":
				path_to_load = cached_path
			elif NetworkManager.is_client():
				# Request map from host - this is already async
				return _request_map_download(level_data.level_folder)
			else:
				push_error("LevelPlayController: Map file not found: " + map_path)
				return false

		if path_to_load != "":
			# Use async map loading to avoid blocking
			map = await _load_map_from_path_async(path_to_load)

	if not map:
		push_error("LevelPlayController: Failed to load map")
		return false

	_finalize_map_loading(map)
	return true


## Finalize map loading after the map instance is ready
func _finalize_map_loading(map: Node3D) -> void:
	# Check if game map is still valid (might have been freed during async loading)
	if not is_instance_valid(_game_map):
		push_warning("LevelPlayController: GameMap was freed during async loading, discarding map")
		map.queue_free()
		return

	loaded_map_instance = map
	loaded_map_instance.name = "LevelMap"

	# Safety check: warn if transform chain is broken (non-Node3D intermediate parents)
	GlbUtils.validate_transform_chain(loaded_map_instance)

	# Extract environment settings from any embedded WorldEnvironment nodes
	# before adding the map to the viewport.
	_environment_manager.extract_and_strip_map_environment(loaded_map_instance)

	# Add to the dedicated MapContainer
	_game_map.map_container.add_child(loaded_map_instance)

	if active_level_data:
		loaded_map_instance.scale = active_level_data.map_scale
		loaded_map_instance.position = active_level_data.map_offset

	# Store original light energies for real-time intensity editing
	_environment_manager.store_original_light_energies(loaded_map_instance)

	# Apply environment settings from level data (map defaults used as a layer)
	if active_level_data:
		_environment_manager.apply_level_environment(active_level_data, _game_map.world_viewport)

	# Rebuild occlusion fade mesh cache now that map geometry is in the scene tree
	_game_map.notify_map_loaded()


## Get the environment manager (for external callers that need direct access).
func get_environment_manager() -> LevelEnvironmentManager:
	return _environment_manager


## Load a map file synchronously using the unified GlbUtils.load_map pipeline.
## Handles both res:// and user:// paths with full post-processing.
func _load_map_from_path(path: String) -> Node3D:
	return GlbUtils.load_map(path, true, _get_light_intensity_scale())


## Load a map file asynchronously using the unified GlbUtils.load_map_async pipeline.
## Handles both res:// and user:// paths with full post-processing.
func _load_map_from_path_async(path: String) -> Node3D:
	var result = await GlbUtils.load_map_async(path, true, _get_light_intensity_scale())
	if result.success:
		return result.scene
	return null


## Get the light intensity scale from the active level data (or 1.0 if none)
func _get_light_intensity_scale() -> float:
	if active_level_data:
		return active_level_data.light_intensity_scale
	return 1.0


## Apply a light intensity scale to all lights in the loaded map.
func apply_light_intensity_scale(intensity_scale: float) -> void:
	_environment_manager.apply_light_intensity_scale(intensity_scale, active_level_data)


## Apply environment settings to the live WorldEnvironment.
func apply_environment_settings(preset: String, overrides: Dictionary) -> void:
	_environment_manager.apply_environment_settings(preset, overrides)


## Get the live WorldEnvironment node (or null if not created yet).
func get_world_environment() -> WorldEnvironment:
	return _environment_manager.get_world_environment()


## Get the environment config extracted from the loaded map (empty if none).
func get_map_environment_config() -> Dictionary:
	return _environment_manager.get_map_environment_config()


## Get the Sky resource extracted from the loaded map (null if none).
func get_map_sky_resource() -> Sky:
	return _environment_manager.get_map_sky_resource()


## Get the GameMap reference.
func get_game_map() -> GameMap:
	return _game_map


## Get the cached map path for a level (if it exists)
func _get_cached_map_path(level_folder: String) -> String:
	return AssetManager.streamer.get_cached_map_path(level_folder)


## Request map download from host
func _request_map_download(level_folder: String) -> bool:
	if not AssetManager.streamer.is_enabled():
		push_error("LevelPlayController: P2P streaming is disabled")
		return false

	_pending_map_level_folder = level_folder
	AssetManager.streamer.request_map_from_host(level_folder)

	print("LevelPlayController: Requesting map download for level: " + level_folder)
	map_download_started.emit(level_folder)

	# Return true to indicate level loading will continue async
	return true


## Check if a map download is in progress
func is_map_downloading() -> bool:
	return _pending_map_level_folder != ""


## Check if level loading is in progress (async loading)
func is_loading() -> bool:
	return _is_loading


## Check if the controller is still valid for loading operations
## Returns false if GameMap has been freed or we're no longer in a valid state
func _is_valid_for_loading() -> bool:
	return is_instance_valid(_game_map) and is_inside_tree()


## Abort an in-progress async loading operation
func _abort_loading() -> void:
	push_warning("LevelPlayController: Aborting async loading (context no longer valid)")
	_is_loading = false
	level_loading_completed.emit()

	# Check if another level was queued during loading
	_process_queued_level()


## Process any level that was queued during loading
func _process_queued_level() -> void:
	if _queued_level_data:
		var queued = _queued_level_data
		_queued_level_data = null
		print("LevelPlayController: Loading queued level")
		# Use call_deferred to avoid recursion issues
		call_deferred("play_level", queued)


## Check if there's a level queued to load after current loading completes
func has_queued_level() -> bool:
	return _queued_level_data != null


## Track a spawned token
func _track_token(token: BoardToken, placement: TokenPlacement) -> void:
	spawned_tokens[placement.placement_id] = token

	# GM can interact with all tokens; players only with tokens they control
	var is_gm = NetworkManager.is_gm() or not NetworkManager.is_networked()
	var can_interact = is_gm
	if not can_interact and multiplayer.multiplayer_peer:
		can_interact = GameState.has_token_permission(
			token.network_id,
			multiplayer.get_unique_id(),
			TokenPermissions.Permission.CONTROL
		)
	token.set_interactive(can_interact)

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
	token.transform_changed.connect(func(): _on_token_transform_changed(token))
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
			token_controller.context_menu_requested.connect(
				_game_map._on_token_context_menu_requested
			)


## Clear any existing map models from the MapContainer
func _clear_existing_maps() -> void:
	if not _game_map or not is_instance_valid(_game_map.map_container):
		return

	for child in _game_map.map_container.get_children():
		child.queue_free()


## Spawn an asset token and add it to the current level
## Returns the created token, or null if spawning failed
## Supports remote assets - will show placeholder while downloading
## If the model isn't cached yet, a placeholder appears instantly and upgrades
## asynchronously once the model finishes loading (no main-thread stall).
func spawn_asset(pack_id: String, asset_id: String, variant_id: String = "default") -> BoardToken:
	if not _game_map or not active_level_data:
		push_warning("LevelPlayController: Cannot spawn asset - no GameMap or active level")
		return null

	# The factory returns the real token if the model is cached, or a placeholder
	# that auto-upgrades when the async load completes (see create_from_asset_async).
	var result = BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)
	var token = result.token as BoardToken

	if not token:
		push_error(
			"LevelPlayController: Failed to create board token for %s/%s" % [pack_id, asset_id]
		)
		return null

	if result.is_placeholder:
		print(
			"LevelPlayController: Spawning placeholder for %s/%s (loading...)" % [pack_id, asset_id]
		)

	_game_map.drag_and_drop_node.add_child(token)
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
	token.set_meta("pack_id", pack_id)
	token.set_meta("asset_id", asset_id)
	token.set_meta("variant_id", variant_id)
	spawned_tokens[placement.placement_id] = token

	# GM can interact with all tokens; players only with tokens they control
	var is_gm = NetworkManager.is_gm() or not NetworkManager.is_networked()
	var can_interact_new = is_gm
	if not can_interact_new and multiplayer.multiplayer_peer:
		can_interact_new = GameState.has_token_permission(
			token.network_id,
			multiplayer.get_unique_id(),
			TokenPermissions.Permission.CONTROL
		)
	token.set_interactive(can_interact_new)

	# Register with GameState for network synchronization
	if GameState.has_authority():
		GameState.register_token_from_board_token(token)
		_connect_token_state_signals(token)
		# Broadcast new token to clients (use full state so clients can create the token)
		if NetworkManager.is_host():
			NetworkStateSync.broadcast_full_state()


## Save current token positions to level data
func save_level() -> String:
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

	# Save the level — use folder format when the level came from a folder
	if active_level_data.level_folder != "":
		return LevelManager.save_level_folder(active_level_data)
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


# =============================================================================
# TOKEN PERMISSIONS
# =============================================================================


## Called when any token permission changes (grant or revoke).
## Updates interactivity for the affected token and manages client transform wiring.
func _on_permissions_changed(network_id: String, _peer_id: int) -> void:
	# If network_id is empty, it's a full permissions sync — update everything
	if network_id == "":
		_update_all_token_state()
		return

	# Update interactivity for the specific token
	var is_gm = NetworkManager.is_gm() or not NetworkManager.is_networked()
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0

	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
		if is_instance_valid(token) and token.network_id == network_id:
			var can_interact = is_gm
			if not can_interact and my_peer_id > 0:
				can_interact = GameState.has_token_permission(
					network_id, my_peer_id, TokenPermissions.Permission.CONTROL
				)
			token.set_interactive(can_interact)
			break

	# Update client-side transform signal wiring
	if not is_gm and NetworkManager.is_networked():
		_update_client_transform_wiring()


## Host-side: handle a permission request from a player.
## Shows a confirmation dialog to the DM.
func _on_token_permission_requested(
	network_id: String, peer_id: int, permission_type: int
) -> void:
	if not NetworkManager.is_host():
		return

	# Prevent duplicate requests
	var request_key = "%s:%d" % [network_id, peer_id]
	if _pending_permission_requests.has(request_key):
		return
	_pending_permission_requests[request_key] = true

	# Look up names for the dialog
	var player_name = "Player"
	var players = NetworkManager.get_players()
	if players.has(peer_id):
		player_name = players[peer_id].get("name", "Player")

	var token_name = "Unknown Token"
	var token_state = GameState.get_token_state(network_id)
	if token_state:
		token_name = token_state.token_name

	var permission_name = "Control"
	if permission_type == TokenPermissions.Permission.CONTROL:
		permission_name = "Control (move/rotate/scale)"

	# Show confirmation dialog to DM
	var dialog = UIManager.show_confirmation(
		"Token Control Request",
		"%s wants to control \"%s\".\n\nPermission: %s" % [player_name, token_name, permission_name],
		"Approve",
		"Deny",
		func():
			_approve_permission_request(network_id, peer_id, permission_type, request_key),
		func():
			_deny_permission_request(network_id, peer_id, permission_type, request_key),
	)
	# Clean up pending state if dialog is dismissed or destroyed (e.g., scene change)
	if dialog:
		if dialog.has_signal("closed"):
			dialog.closed.connect(
				func(_confirmed: bool):
					_pending_permission_requests.erase(request_key),
				CONNECT_ONE_SHOT,
			)
		dialog.tree_exiting.connect(
			func():
				_pending_permission_requests.erase(request_key),
			CONNECT_ONE_SHOT,
		)


## Host-side: approve a permission request.
func _approve_permission_request(
	network_id: String, peer_id: int, permission_type: int, request_key: String
) -> void:
	_pending_permission_requests.erase(request_key)

	# Guard: peer may have disconnected while DM was deciding
	if not NetworkManager.get_players().has(peer_id):
		UIManager.show_warning("Player disconnected before approval could be sent")
		return

	GameState.grant_token_permission(network_id, peer_id, permission_type)

	# Send response to the requesting client
	NetworkManager.send_permission_response(peer_id, network_id, permission_type, true)

	# Broadcast updated permissions to all clients
	NetworkManager.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)

	# Show toast on host
	var token_state = GameState.get_token_state(network_id)
	var token_name = token_state.token_name if token_state else "token"
	var players = NetworkManager.get_players()
	var player_name = players[peer_id].get("name", "Player") if players.has(peer_id) else "Player"
	UIManager.show_success("%s can now control \"%s\"" % [player_name, token_name])


## Host-side: deny a permission request.
func _deny_permission_request(
	network_id: String, peer_id: int, permission_type: int, request_key: String
) -> void:
	_pending_permission_requests.erase(request_key)
	# Only send denial if peer is still connected
	if NetworkManager.get_players().has(peer_id):
		NetworkManager.send_permission_response(peer_id, network_id, permission_type, false)


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

	# Apply transform to the host's local BoardToken (with interpolation)
	var token_found := false
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
		if is_instance_valid(token) and token.network_id == network_id:
			token.set_interpolation_target(pos, rot, scl)
			token_found = true
			break

	if not token_found:
		return  # Token doesn't exist on host — don't update GameState or broadcast

	# Update GameState
	GameState.update_token_property(network_id, "position", pos)
	GameState.update_token_property(network_id, "rotation", rot)
	GameState.update_token_property(network_id, "scale", scl)

	# Broadcast to all OTHER clients (not the sender)
	NetworkStateSync.broadcast_client_token_transform(network_id, pos, rot, scl, sender_id)


## Client-side: handle permission response from host.
func _on_permission_response_received(
	network_id: String, _permission_type: int, approved: bool
) -> void:
	if NetworkManager.is_host():
		return

	var token_state = GameState.get_token_state(network_id)
	var token_name = token_state.token_name if token_state else "token"

	if approved:
		UIManager.show_success("Control granted for \"%s\"!" % token_name)
	else:
		UIManager.show_warning("Control request for \"%s\" was denied" % token_name)


## Client-side: handle full permission sync from host.
func _on_permissions_received(permissions_dict: Dictionary) -> void:
	if NetworkManager.is_host():
		return
	GameState.apply_token_permissions(permissions_dict)


## Host-side: clean up permissions when a player disconnects.
func _on_player_left_permissions(peer_id: int, _player_info: Dictionary) -> void:
	if not NetworkManager.is_host():
		return

	# Check if the disconnected player had any permissions
	var controlled = GameState.get_controlled_tokens(peer_id, TokenPermissions.Permission.CONTROL)
	if controlled.is_empty():
		return

	# Revoke all permissions for the disconnected player
	GameState.clear_permissions_for_peer(peer_id)

	# Broadcast updated permissions to remaining clients
	NetworkManager.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)

	# Clean up any pending requests from this peer
	var keys_to_remove: Array[String] = []
	for key in _pending_permission_requests:
		if key.ends_with(":%d" % peer_id):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_pending_permission_requests.erase(key)


# =============================================================================
# CLIENT-SIDE TRANSFORM WIRING
# =============================================================================


## Dynamically connect/disconnect transform signals for tokens this client controls.
## Called when permissions change on the client side.
func _update_client_transform_wiring() -> void:
	if not multiplayer.multiplayer_peer:
		return
	var my_peer_id = multiplayer.get_unique_id()

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
	var token = _find_token_by_network_id(network_id)
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
	if NetworkManager.is_host() or not NetworkManager.is_networked():
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


## Find a token by its network_id in spawned_tokens.
func _find_token_by_network_id(network_id: String) -> BoardToken:
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id] as BoardToken
		if is_instance_valid(token) and token.network_id == network_id:
			return token
	return null


## Clear spawned tokens
func clear_level_tokens() -> void:
	for placement_id in spawned_tokens:
		var token = spawned_tokens[placement_id]
		if is_instance_valid(token):
			token.queue_free()

	spawned_tokens.clear()
	active_level_data = null

	# Clear permission-related state
	_pending_permission_requests.clear()
	_client_transform_throttle.clear()
	_client_connected_tokens.clear()

	# Clear GameState (also clears permissions)
	GameState.clear_all_tokens()


## Clear the loaded level map
func clear_level_map() -> void:
	# Clear occlusion fade state before freeing map geometry
	if _game_map:
		_game_map.notify_map_clearing()

	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.queue_free()
		loaded_map_instance = null

	# Clear environment state (lights, WorldEnvironment, map config)
	_environment_manager.clear()


## Clear everything from the current level
func clear_level() -> void:
	# Stop reconciliation timer
	if _reconciliation_timer:
		_reconciliation_timer.stop()

	# Clear network sync throttle state
	NetworkStateSync.clear_throttle_state()

	clear_level_tokens()
	clear_level_map()

	# Clear model cache to free memory
	AssetManager.clear_model_cache()

	level_cleared.emit()


## Reset all loading state (call when exiting PLAYING state)
func reset_loading_state() -> void:
	_is_loading = false
	_queued_level_data = null
	_pending_map_level_folder = ""
	is_editor_preview = false
	_disconnect_asset_streamer()


## Set map scale in real-time (used by gameplay UI and network sync)
func set_map_scale(uniform_scale: float) -> void:
	if is_instance_valid(loaded_map_instance):
		loaded_map_instance.scale = Vector3.ONE * uniform_scale
	if active_level_data:
		active_level_data.map_scale = Vector3.ONE * uniform_scale


## Called on clients when the host changes visual settings (map scale, lighting, environment, lo-fi)
func _on_visual_settings_received(settings: Dictionary) -> void:
	if settings.has("map_scale"):
		set_map_scale(settings["map_scale"])
	if settings.has("light_intensity"):
		apply_light_intensity_scale(settings["light_intensity"])
		if active_level_data:
			active_level_data.light_intensity_scale = settings["light_intensity"]
	if settings.has("environment_preset"):
		var preset: String = settings["environment_preset"]
		var overrides: Dictionary = settings.get("environment_overrides", {})
		apply_environment_settings(preset, overrides)
		if active_level_data:
			active_level_data.environment_preset = preset
			active_level_data.environment_overrides = overrides.duplicate()
	if settings.has("lofi_overrides"):
		var game_map = get_game_map()
		if game_map:
			game_map.apply_lofi_overrides(settings["lofi_overrides"])
		if active_level_data:
			active_level_data.lofi_overrides = settings["lofi_overrides"].duplicate()


## Check if a level is currently loaded
func has_active_level() -> bool:
	return active_level_data != null


## Get token count
func get_token_count() -> int:
	return spawned_tokens.size()
