class_name LevelPlayController
extends Node

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
var loaded_map_instance: Node3D = null
var is_editor_preview: bool = false  # True when playing a level from the level editor

## Read-only view onto TokenSpawner's storage (placement_id -> BoardToken) so
## external callers that pre-date the extraction (e.g. RootNetworkHandler)
## can keep using direct dictionary access unchanged.
var spawned_tokens: Dictionary:
	get:
		return _token_spawner.get_spawned_tokens()

var _game_map: GameMap = null
var _reconciliation_timer: Timer = null
var _is_loading: bool = false  # True while async loading is in progress
var _load_generation: int = 0  # Bumped on every new load / reset_loading_state() call.
# Lets a suspended _play_level_async coroutine detect that it has been
# superseded (e.g. Root exited/re-entered PLAYING with a new GameMap) so it
# can abort instead of mutating state that now belongs to a newer load.
var _environment_manager := LevelEnvironmentManager.new()  # Manages lighting/atmosphere
var _map_download_coordinator := MapDownloadCoordinator.new()  # Manages map downloads
var _token_spawner := TokenSpawner.new()  # Manages token spawning/tracking/clearing
var _permission_handler: TokenPermissionHandler = null

# Token permission state
var _client_transform_throttle: Dictionary = {}  # network_id -> last_send_time (client-side)
## network_id -> {"changed": Callable, "updated": Callable}
var _client_connected_tokens: Dictionary = {}

## Stores pending level data when a new level is requested during loading
var _queued_level_data: LevelData = null


## Initialize with a reference to the game map
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_environment_manager.setup(game_map)
	_game_map.setup_measure_tool()
	_game_map.setup_grid_overlay()
	_game_map.setup_drag_ruler()
	_setup_reconciliation_timer()
	_map_download_coordinator.setup(_load_map_from_path, _finalize_map_loading)
	_map_download_coordinator.connect_asset_streamer()
	if not _map_download_coordinator.map_download_started.is_connected(
		_on_coordinator_download_started
	):
		_map_download_coordinator.map_download_started.connect(_on_coordinator_download_started)
	if not _map_download_coordinator.map_download_progress.is_connected(
		_on_coordinator_download_progress
	):
		_map_download_coordinator.map_download_progress.connect(_on_coordinator_download_progress)
	if not _map_download_coordinator.map_download_completed.is_connected(
		_on_coordinator_download_completed
	):
		_map_download_coordinator.map_download_completed.connect(_on_coordinator_download_completed)
	if not _map_download_coordinator.map_download_failed.is_connected(
		_on_coordinator_download_failed
	):
		_map_download_coordinator.map_download_failed.connect(_on_coordinator_download_failed)

	_token_spawner.setup(game_map, _get_active_level_data)
	if not _token_spawner.token_added.is_connected(_on_token_spawner_token_added):
		_token_spawner.token_added.connect(_on_token_spawner_token_added)

	# Listen for network state changes to update token interactivity
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Listen for visual settings changes from the host (map scale, lighting, environment, lo-fi)
	if not NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.connect(_on_visual_settings_received)

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

	# Token permission handling (delegated to TokenPermissionHandler)
	if is_instance_valid(_permission_handler):
		_permission_handler.queue_free()
		_permission_handler = null
	_permission_handler = TokenPermissionHandler.new()
	_permission_handler.name = "TokenPermissionHandler"
	add_child(_permission_handler)
	_permission_handler.setup()

	# Connect action history for removal undo, and give it a way to look up
	# live tokens so property-change undo/redo can replay through the token's
	# real mutators (not just GameState) — see GameplayActionHistory.
	var history := _game_map.get_action_history()
	if history:
		if not history.removal_undo_requested.is_connected(
			_token_spawner._on_removal_undo_requested
		):
			history.removal_undo_requested.connect(_token_spawner._on_removal_undo_requested)
		history.set_token_lookup(_token_spawner.find_token_by_network_id)


func _exit_tree() -> void:
	# Disconnect network signals
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)
	if NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.disconnect(_on_visual_settings_received)

	# Disconnect permission signals
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

	# Disconnect AssetStreamer signals
	_map_download_coordinator.disconnect_asset_streamer()


## Relay MapDownloadCoordinator signals through this facade's own signals so
## external listeners connected to LevelPlayController are unaffected by the
## extraction.
func _on_coordinator_download_started(level_folder: String) -> void:
	map_download_started.emit(level_folder)


func _on_coordinator_download_progress(level_folder: String, progress: float) -> void:
	map_download_progress.emit(level_folder, progress)


func _on_coordinator_download_completed(level_folder: String) -> void:
	map_download_completed.emit(level_folder)


func _on_coordinator_download_failed(level_folder: String, error: String) -> void:
	map_download_failed.emit(level_folder, error)


## Relay TokenSpawner's token_added signal through this facade's own signal so
## external listeners connected to LevelPlayController are unaffected by the
## extraction.
func _on_token_spawner_token_added(token: BoardToken) -> void:
	token_added.emit(token)


## Getter injected into TokenSpawner so it can read the currently active level
## data (owned here, reassigned on every level load) without a direct field
## reference.
func _get_active_level_data() -> LevelData:
	return active_level_data


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
	var is_gm = NetworkManager.has_gm_access()
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0

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


## Load and play a level (async version - does not block main thread)
## Returns true if loading started successfully, false on immediate failure
## Listen to level_loaded signal for completion
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
	# Bump the generation and capture it locally. If reset_loading_state() (or
	# another _play_level_async call) bumps _load_generation again while this
	# coroutine is suspended on an await, the captured value goes stale and
	# every checkpoint below will abort instead of mutating shared state.
	_load_generation += 1
	var generation: int = _load_generation

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
	if _should_abort_load(generation):
		return

	# Clear any previously loaded level first (also clears model cache)
	clear_level()

	# Yield after clearing to let freed nodes process
	await get_tree().process_frame

	# Check validity again after yield
	if _should_abort_load(generation):
		return

	# Store reference to active level
	active_level_data = level_data

	level_loading_progress.emit(0.05, "Loading map...")

	# Load the map model from level data (async)
	var map_loaded = await _load_level_map_async(level_data)

	# Check validity after async map load
	if _should_abort_load(generation):
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
			var loaded_count = await AssetManager.preload_models(
				assets_to_preload,
				func(loaded: int, total: int):
					var model_progress = 0.2 + (0.4 * loaded / max(total, 1))
					level_loading_progress.emit(
						model_progress, "Loading models... (%d/%d)" % [loaded, total]
					),
				false  # create_static_bodies
			)

		# Check validity after async model preload
		if _should_abort_load(generation):
			return

	# Now spawn tokens - this is fast since models are already cached
	var spawned_count = 0
	level_loading_progress.emit(0.6, "Spawning tokens...")

	for placement in level_data.token_placements:
		# Check validity before spawning each batch
		if _should_abort_load(generation):
			return

		var token = BoardTokenFactory.create_from_placement_async(placement).token
		if token and is_instance_valid(drag_and_drop):
			drag_and_drop.add_child(token)
			_token_spawner._track_token(token, placement)
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

	# Final check before flipping shared state / notifying listeners
	if _should_abort_load(generation):
		return

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
			var cached_path = _map_download_coordinator.get_cached_map_path(level_data.level_folder)
			if cached_path != "":
				path_to_load = cached_path
			elif NetworkManager.is_client():
				# Request map from host - this is already async
				return _map_download_coordinator.request_map_download(level_data.level_folder)
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

	# Set up weather renderer (must happen after environment is applied)
	var game_map = get_game_map()
	if game_map:
		game_map.setup_weather(_environment_manager)
		if active_level_data and active_level_data.weather_overrides.size() > 0:
			game_map.apply_weather_overrides(active_level_data.weather_overrides)

	# Rebuild occlusion fade mesh cache now that map geometry is in the scene tree
	_game_map.notify_map_loaded()

	# Configure measure tool and grid with scale settings from level data
	_configure_measure_tool()
	_configure_grid()


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


## Pass current scale settings from level data to the measure tool.
func _configure_measure_tool() -> void:
	if not _game_map:
		return
	var tool := _game_map.get_measure_tool()
	if not tool or not active_level_data:
		return
	(
		tool
		. configure(
			active_level_data.grid_cell_size,
			active_level_data.display_unit,
			active_level_data.display_unit_per_cell,
		)
	)


## Configure grid overlay, grid snap, and drag ruler from level data.
func _configure_grid() -> void:
	if not _game_map or not active_level_data:
		return
	_game_map.configure_grid(active_level_data)


## Public: update measure tool and grid configuration (called when GM changes scale in UI).
func update_measure_tool_scale() -> void:
	_configure_measure_tool()
	_configure_grid()


## Deactivate the measure tool if it's active (called on level clear/load).
func _deactivate_measure_tool() -> void:
	if not _game_map:
		return
	var tool := _game_map.get_measure_tool()
	if tool and tool.is_active():
		tool.deactivate()


## Check if level loading is in progress (async loading)
func is_loading() -> bool:
	return _is_loading


## Check if the controller is still valid for loading operations
## Returns false if GameMap has been freed or we're no longer in a valid state
func _is_valid_for_loading() -> bool:
	return is_instance_valid(_game_map) and is_inside_tree()


## Checkpoint for _play_level_async: returns true if the calling coroutine's
## captured generation no longer matches _load_generation (superseded by a
## newer load or reset_loading_state()) or if the GameMap context is no
## longer valid. Callers must return immediately when this returns true —
## a stale coroutine must never mutate shared state (spawned_tokens,
## active_level_data, _game_map's children, etc.) after this point, since
## that state may already belong to a different load.
func _should_abort_load(generation: int) -> bool:
	if generation != _load_generation:
		# Superseded — another invocation (or reset_loading_state()) now owns
		# _is_loading and shared state. Abort silently without touching them.
		return true
	if not _is_valid_for_loading():
		_abort_loading()
		return true
	return false


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


## Connect token's context menu signal and other per-token signals to game map.
## Forwards to TokenSpawner -- kept as a same-named method here since
## RootNetworkHandler calls this directly on the LevelPlayController instance.
func _connect_token_context_menu(token: BoardToken) -> void:
	_token_spawner._connect_token_context_menu(token)


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
## Forwards to TokenSpawner -- kept as a same-named method here since
## DragPlaceController (via game_map.gd) binds this as a string Callable on
## this LevelPlayController instance.
func spawn_asset(
	pack_id: String,
	asset_id: String,
	variant_id: String = "default",
	spawn_position: Vector3 = Vector3.ZERO,
) -> BoardToken:
	return _token_spawner.spawn_asset(pack_id, asset_id, variant_id, spawn_position)


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
	var tokens := _token_spawner.get_spawned_tokens()
	for placement in active_level_data.token_placements:
		if tokens.has(placement.placement_id):
			var token = tokens[placement.placement_id] as BoardToken
			if is_instance_valid(token):
				_token_spawner._sync_placement_from_token(placement, token)
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
	var is_gm = NetworkManager.has_gm_access()
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0

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


## Clear spawned tokens. Forwards the token-storage cleanup to TokenSpawner;
## the remaining state below (_client_connected_tokens, throttle, GameState)
## is not part of the TokenSpawner extraction and stays here.
func clear_level_tokens() -> void:
	_token_spawner.clear_level_tokens()
	active_level_data = null

	# Disconnect client transform signals before clearing
	for network_id in _client_connected_tokens.keys():
		_disconnect_client_transform_signals(network_id)

	# Clear permission-related state
	_client_transform_throttle.clear()

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

	# Clear weather effects before environment state
	var game_map = get_game_map()
	if game_map:
		game_map.clear_weather()

	# Clear environment state (lights, WorldEnvironment, map config)
	_environment_manager.clear()


## Clear everything from the current level
func clear_level() -> void:
	_deactivate_measure_tool()
	if _game_map:
		_game_map.reset_grid_state()

	# Stop reconciliation timer
	if _reconciliation_timer:
		_reconciliation_timer.stop()

	# Clear network sync throttle state
	NetworkStateSync.clear_throttle_state()
	GameState.clear_all_drag_locks()

	# Clear undo history (stale network_ids would be meaningless)
	if _game_map:
		var history := _game_map.get_action_history()
		if history:
			history.clear()

	clear_level_tokens()
	clear_level_map()

	# Clear model cache to free memory
	AssetManager.clear_model_cache()

	level_cleared.emit()


## Reset all loading state (call when exiting PLAYING state)
func reset_loading_state() -> void:
	_is_loading = false
	_queued_level_data = null
	is_editor_preview = false
	# Invalidate any in-flight _play_level_async coroutine still suspended on
	# an await — its captured generation will no longer match, so it will
	# abort at its next checkpoint instead of mutating state for a level it
	# no longer owns (see _should_abort_load()).
	_load_generation += 1
	_map_download_coordinator.reset()


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
	if settings.has("weather_overrides"):
		var game_map = get_game_map()
		if game_map:
			game_map.apply_weather_overrides(settings["weather_overrides"])
		if active_level_data:
			active_level_data.weather_overrides = settings["weather_overrides"].duplicate()


## Check if a level is currently loaded
func has_active_level() -> bool:
	return active_level_data != null


## Get token count. Forwards to TokenSpawner -- kept as a same-named method
## here since gameplay_menu_controller.gd calls this directly.
func get_token_count() -> int:
	return _token_spawner.get_token_count()
