class_name LevelPlayLoader

## Owns async level loading: the progressive load coroutine (map + token spawning with
## progress reporting), load-generation race protection, level queueing while a load is in
## progress, measure-tool/grid configuration from level data, and level/map clearing.
##
## Extracted from LevelPlayController -- this was the largest and highest-risk of the
## facade-splitting extractions (the async load coroutine alone spans the full progress
## lifecycle: map load, token model preload, staggered token spawn, and completion).
##
## active_level_data, loaded_map_instance, and is_editor_preview stay on LevelPlayController
## rather than moving here: external code depends on reading AND writing them directly on the
## LevelPlayController instance (e.g. app_menu_controller.gd does
## `_level_play_controller.is_editor_preview = true`, a direct external write that a
## getter-only computed property can't support). This class reaches those three fields, plus
## _game_map / _token_spawner / _network_token_sync / _environment_manager /
## _map_download_coordinator, through a back-reference to the owning LevelPlayController
## captured in setup() -- the same idea as GameMap's sub-components reading fields off their
## injected GameMap reference at call time.
##
## Plain-object sub-component (not a Node): constructed eagerly as a field default on
## LevelPlayController -- see TokenSpawner/MapDownloadCoordinator/NetworkTokenSync for the
## same pattern. Like NetworkTokenSync, it has no Node capabilities of its own (can't call
## get_tree(), is_inside_tree(), or await a process_frame), so it borrows those from the
## level_play_controller back-reference too.
##
## Named LevelPlayLoader (not LevelLoader) to avoid colliding with the pre-existing, unrelated
## global class_name LevelLoader at scenes/level_loader/level_loader.gd -- a legacy,
## apparently-unused Node3D-based level loading scene with no references anywhere else in the
## codebase. Godot requires globally unique class_name values, so reusing "LevelLoader" here
## would break project import.

signal level_loaded(level_data: LevelData)
signal level_cleared
signal token_spawned(token: BoardToken, placement: TokenPlacement)
signal level_loading_started
signal level_loading_progress(progress: float, status: String)
signal level_loading_completed

const TOKENS_PER_FRAME: int = 3  # How many tokens to spawn per frame during progressive loading

var _level_play_controller: LevelPlayController = null
var _is_loading: bool = false  # True while async loading is in progress
var _load_generation: int = 0  # Bumped on every new load / reset_loading_state() call.
# Lets a suspended _play_level_async coroutine detect that it has been
# superseded (e.g. Root exited/re-entered PLAYING with a new GameMap) so it
# can abort instead of mutating state that now belongs to a newer load.

## Stores pending level data when a new level is requested during loading
var _queued_level_data: LevelData = null


## Initialize with a back-reference to the owning LevelPlayController, used to reach
## _game_map, _token_spawner, _network_token_sync, _environment_manager,
## _map_download_coordinator, active_level_data, loaded_map_instance, is_editor_preview, and
## Node capabilities (get_tree(), is_inside_tree()) this plain object doesn't have itself.
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller


## Load and play a level (async version - does not block main thread)
## Returns true if loading started successfully, false on immediate failure
## Listen to level_loaded signal for completion
func play_level(level_data: LevelData) -> bool:
	if not _level_play_controller._game_map:
		push_error("LevelPlayLoader: No GameMap set. Call setup() first.")
		return false

	if _is_loading:
		# If we're already loading, queue this level to load after current completes/aborts
		# This handles cases like: host sends new level while client is still loading previous
		push_warning("LevelPlayLoader: Queueing level (currently loading)")
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
		await _level_play_controller.get_tree().process_frame

	# Check if we're still valid (user might have navigated away)
	if _should_abort_load(generation):
		return

	# Clear any previously loaded level first (also clears model cache)
	clear_level()

	# Yield after clearing to let freed nodes process
	await _level_play_controller.get_tree().process_frame

	# Check validity again after yield
	if _should_abort_load(generation):
		return

	# Store reference to active level
	_level_play_controller.active_level_data = level_data

	level_loading_progress.emit(0.05, "Loading map...")

	# Load the map model from level data (async)
	var map_loaded = await _load_level_map_async(level_data)

	# Check validity after async map load
	if _should_abort_load(generation):
		return

	if not map_loaded:
		push_error("LevelPlayLoader: Failed to load map")
		_abort_loading()
		return

	var drag_and_drop = _level_play_controller._game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("LevelPlayLoader: Could not find DragAndDrop3D node")
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
			_level_play_controller._token_spawner._track_token(token, placement)
			_level_play_controller._connect_token_context_menu(token)
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
			await _level_play_controller.get_tree().process_frame

	level_loading_progress.emit(1.0, "Complete")

	# Yield a couple frames to let all tokens render before hiding loading screen
	for i in range(2):
		await _level_play_controller.get_tree().process_frame

	# Final check before flipping shared state / notifying listeners
	if _should_abort_load(generation):
		return

	_is_loading = false
	level_loading_completed.emit()
	level_loaded.emit(level_data)

	# Start reconciliation timer for networked games
	_level_play_controller._network_token_sync.start_reconciliation_timer()

	# Check if another level was queued during loading
	_process_queued_level()


## Load the map model from level data (async version - does not block main thread)
## Uses threaded file I/O for GLB loading
func _load_level_map_async(level_data: LevelData) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null

	# Clear any existing map children from the game map
	_clear_existing_maps()

	# Check for valid map path
	if level_data.map_path == "":
		push_error("LevelPlayLoader: No map path in level data")
		return false

	# Get the absolute map path
	var map_path = level_data.get_absolute_map_path()
	if map_path == "":
		push_error("LevelPlayLoader: Cannot resolve map path")
		return false

	# Try to load the map from various sources
	var map: Node3D = null

	# 1. Check if it's a res:// path (legacy format)
	if map_path.begins_with("res://"):
		var result = await GlbUtils.load_map_async(
			map_path, true, _get_light_intensity_scale(), _get_foliage_overrides()
		)
		if result.success:
			map = result.scene

	# 2. Check if it's a user:// path (folder-based format)
	elif map_path.begins_with("user://"):
		var path_to_load = ""

		if FileAccess.file_exists(map_path):
			path_to_load = map_path
		else:
			# Check cache (for clients who downloaded from host)
			var cached_path = _level_play_controller._map_download_coordinator.get_cached_map_path(
				level_data.level_folder
			)
			if cached_path != "":
				path_to_load = cached_path
			elif NetworkManager.is_client():
				# Request map from host - this is already async
				return _level_play_controller._map_download_coordinator.request_map_download(
					level_data.level_folder
				)
			else:
				push_error("LevelPlayLoader: Map file not found: " + map_path)
				return false

		if path_to_load != "":
			# Use async map loading to avoid blocking
			map = await _load_map_from_path_async(path_to_load)

	if not map:
		push_error("LevelPlayLoader: Failed to load map")
		return false

	_finalize_map_loading(map)
	WaterGlbUtils.apply_water_style(level_data.water_style)
	return true


## Finalize map loading after the map instance is ready
func _finalize_map_loading(map: Node3D) -> void:
	# Check if game map is still valid (might have been freed during async loading)
	if not is_instance_valid(_level_play_controller._game_map):
		push_warning("LevelPlayLoader: GameMap was freed during async loading, discarding map")
		map.queue_free()
		return

	_level_play_controller.loaded_map_instance = map
	_level_play_controller.loaded_map_instance.name = "LevelMap"

	# Safety check: warn if transform chain is broken (non-Node3D intermediate parents)
	GlbUtils.validate_transform_chain(_level_play_controller.loaded_map_instance)

	# Extract environment settings from any embedded WorldEnvironment nodes
	# before adding the map to the viewport.
	_level_play_controller._environment_manager.extract_and_strip_map_environment(
		_level_play_controller.loaded_map_instance
	)

	# Add to the dedicated MapContainer
	_level_play_controller._game_map.map_container.add_child(
		_level_play_controller.loaded_map_instance
	)

	if _level_play_controller.active_level_data:
		_level_play_controller.loaded_map_instance.scale = (
			_level_play_controller.active_level_data.map_scale
		)
		_level_play_controller.loaded_map_instance.position = (
			_level_play_controller.active_level_data.map_offset
		)

	# Store original light energies for real-time intensity editing
	_level_play_controller._environment_manager.store_original_light_energies(
		_level_play_controller.loaded_map_instance
	)

	# Cache wind-sway materials for real-time foliage tuning
	_level_play_controller._environment_manager.store_wind_materials(
		_level_play_controller.loaded_map_instance
	)

	# Apply environment settings from level data (map defaults used as a layer)
	if _level_play_controller.active_level_data:
		_level_play_controller._environment_manager.apply_level_environment(
			_level_play_controller.active_level_data,
			_level_play_controller._game_map.world_viewport
		)

	# Set up weather renderer (must happen after environment is applied)
	var game_map = _level_play_controller.get_game_map()
	if game_map:
		game_map.setup_weather(_level_play_controller._environment_manager)
		if (
			_level_play_controller.active_level_data
			and _level_play_controller.active_level_data.weather_overrides.size() > 0
		):
			game_map.apply_weather_overrides(
				_level_play_controller.active_level_data.weather_overrides
			)

	# Rebuild occlusion fade mesh cache now that map geometry is in the scene tree
	_level_play_controller._game_map.notify_map_loaded()

	# Configure measure tool and grid with scale settings from level data
	_configure_measure_tool()
	_configure_grid()


## Load a map file synchronously using the unified GlbUtils.load_map pipeline.
## Handles both res:// and user:// paths with full post-processing.
func _load_map_from_path(path: String) -> Node3D:
	return GlbUtils.load_map(path, true, _get_light_intensity_scale(), _get_foliage_overrides())


## Load a map file asynchronously using the unified GlbUtils.load_map_async pipeline.
## Handles both res:// and user:// paths with full post-processing.
func _load_map_from_path_async(path: String) -> Node3D:
	var result = await GlbUtils.load_map_async(
		path, true, _get_light_intensity_scale(), _get_foliage_overrides()
	)
	if result.success:
		return result.scene
	return null


## Get the light intensity scale from the active level data (or 1.0 if none)
func _get_light_intensity_scale() -> float:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.light_intensity_scale
	return 1.0


## Get the foliage sway overrides from the active level data (or {} if none)
func _get_foliage_overrides() -> Dictionary:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.foliage_overrides
	return {}


## Pass current scale settings from level data to the measure tool.
func _configure_measure_tool() -> void:
	if not _level_play_controller._game_map:
		return
	var tool := _level_play_controller._game_map.get_measure_tool()
	if not tool or not _level_play_controller.active_level_data:
		return
	(
		tool
		. configure(
			_level_play_controller.active_level_data.grid_cell_size,
			_level_play_controller.active_level_data.display_unit,
			_level_play_controller.active_level_data.display_unit_per_cell,
		)
	)


## Configure grid overlay, grid snap, and drag ruler from level data.
func _configure_grid() -> void:
	if not _level_play_controller._game_map or not _level_play_controller.active_level_data:
		return
	_level_play_controller._game_map.configure_grid(_level_play_controller.active_level_data)


## Public: update measure tool and grid configuration (called when GM changes scale in UI).
func update_measure_tool_scale() -> void:
	_configure_measure_tool()
	_configure_grid()


## Deactivate the measure tool if it's active (called on level clear/load).
func _deactivate_measure_tool() -> void:
	if not _level_play_controller._game_map:
		return
	var tool := _level_play_controller._game_map.get_measure_tool()
	if tool and tool.is_active():
		tool.deactivate()


## Check if level loading is in progress (async loading)
func is_loading() -> bool:
	return _is_loading


## Check if the controller is still valid for loading operations
## Returns false if GameMap has been freed or we're no longer in a valid state
func _is_valid_for_loading() -> bool:
	return (
		is_instance_valid(_level_play_controller._game_map)
		and _level_play_controller.is_inside_tree()
	)


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
	push_warning("LevelPlayLoader: Aborting async loading (context no longer valid)")
	_is_loading = false
	level_loading_completed.emit()

	# Check if another level was queued during loading
	_process_queued_level()


## Process any level that was queued during loading
func _process_queued_level() -> void:
	if _queued_level_data:
		var queued = _queued_level_data
		_queued_level_data = null
		print("LevelPlayLoader: Loading queued level")
		# Use call_deferred to avoid recursion issues
		call_deferred("play_level", queued)


## Check if there's a level queued to load after current loading completes
func has_queued_level() -> bool:
	return _queued_level_data != null


## Clear any existing map models from the MapContainer
func _clear_existing_maps() -> void:
	var game_map := _level_play_controller._game_map
	if not game_map or not is_instance_valid(game_map.map_container):
		return

	for child in game_map.map_container.get_children():
		child.queue_free()


## Save current token positions to level data
func save_level() -> String:
	if not _level_play_controller.active_level_data:
		push_error("LevelPlayLoader: No active level to save")
		return ""

	# Update map position and scale from the loaded map instance
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.active_level_data.map_scale = (
			_level_play_controller.loaded_map_instance.scale
		)
		_level_play_controller.active_level_data.map_offset = (
			_level_play_controller.loaded_map_instance.position
		)

	# Update each placement with current token position
	var tokens := _level_play_controller._token_spawner.get_spawned_tokens()
	for placement in _level_play_controller.active_level_data.token_placements:
		if tokens.has(placement.placement_id):
			var token = tokens[placement.placement_id] as BoardToken
			if is_instance_valid(token):
				_level_play_controller._token_spawner._sync_placement_from_token(placement, token)
				# Also sync to GameState
				if GameState.has_authority():
					GameState.sync_from_board_token(token)

	# Broadcast updated state to clients
	if NetworkManager.is_host():
		NetworkStateSync.broadcast_full_state()

	# Save the level — use folder format when the level came from a folder
	if _level_play_controller.active_level_data.level_folder != "":
		return LevelManager.save_level_folder(_level_play_controller.active_level_data)
	return LevelManager.save_level(_level_play_controller.active_level_data)


## Clear the loaded level map
func clear_level_map() -> void:
	# Clear occlusion fade state before freeing map geometry
	if _level_play_controller._game_map:
		_level_play_controller._game_map.notify_map_clearing()

	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null

	# Clear weather effects before environment state
	var game_map = _level_play_controller.get_game_map()
	if game_map:
		game_map.clear_weather()

	# Clear environment state (lights, WorldEnvironment, map config)
	_level_play_controller._environment_manager.clear()


## Clear everything from the current level
func clear_level() -> void:
	_deactivate_measure_tool()
	if _level_play_controller._game_map:
		_level_play_controller._game_map.reset_grid_state()

	# Stop reconciliation timer
	_level_play_controller._network_token_sync.stop_reconciliation_timer()

	# Clear network sync throttle state
	NetworkStateSync.clear_throttle_state()
	GameState.clear_all_drag_locks()

	# Clear undo history (stale network_ids would be meaningless)
	if _level_play_controller._game_map:
		var history := _level_play_controller._game_map.get_action_history()
		if history:
			history.clear()

	_level_play_controller.clear_level_tokens()
	clear_level_map()

	# Clear model cache to free memory
	AssetManager.clear_model_cache()

	level_cleared.emit()


## Reset all loading state (call when exiting PLAYING state)
func reset_loading_state() -> void:
	_is_loading = false
	_queued_level_data = null
	_level_play_controller.is_editor_preview = false
	# Invalidate any in-flight _play_level_async coroutine still suspended on
	# an await — its captured generation will no longer match, so it will
	# abort at its next checkpoint instead of mutating state for a level it
	# no longer owns (see _should_abort_load()).
	_load_generation += 1
	_level_play_controller._map_download_coordinator.reset()


## Set map scale in real-time (used by gameplay UI and network sync)
func set_map_scale(uniform_scale: float) -> void:
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.scale = Vector3.ONE * uniform_scale
	if _level_play_controller.active_level_data:
		_level_play_controller.active_level_data.map_scale = Vector3.ONE * uniform_scale


## Check if a level is currently loaded
func has_active_level() -> bool:
	# _level_play_controller stays null until LevelPlayController.setup(game_map) runs,
	# which only happens once Root actually enters State.PLAYING -- but
	# app_menu_controller.gd hands this loader's owning LevelPlayController to the App
	# Menu at startup (Root._setup_app_menu(), before any state transition), and the
	# Level Editor button is reachable from the title screen specifically so a map can
	# be tested before hosting/joining a game. Calling has_active_level() from there
	# used to crash with "Invalid access ... on a base object of type 'Nil'" instead of
	# just correctly reporting "no active level" -- which is exactly what's true at
	# that point.
	return _level_play_controller != null and _level_play_controller.active_level_data != null
