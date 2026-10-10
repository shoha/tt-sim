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
## The authored-map lighting; see MapSourceLoader.AUTHORED_MAP_LIGHTING.
const AUTHORED_MAP_LIGHTING := MapSourceLoader.AUTHORED_MAP_LIGHTING

## The last Blender map grid ground fit (MapSourceLoader.fit_grid_ground_async), for
## measurement; {} for an authored map or a superseded load.
var grid_ground_fit: Dictionary = {}

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
			if placement.is_avatar():
				continue  # built from the kit, nothing to preload
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
	var cast_top := 0.0
	if total_tokens > 0:
		# Each token is set down on ground that moved since it was saved (TokenGrounding),
		# which needs the map's collision in the physics space.
		await _level_play_controller.get_tree().physics_frame
		if _should_abort_load(generation):
			return
		cast_top = TokenGrounding.cast_top(_level_play_controller._game_map)

	for placement in level_data.token_placements:
		# Check validity before spawning each batch
		if _should_abort_load(generation):
			return

		var token = BoardTokenFactory.create_from_placement_async(placement).token
		if token and is_instance_valid(drag_and_drop):
			drag_and_drop.add_child(token)
			# Before tracking, so GameState and every peer get the grounded position.
			TokenGrounding.reground(token, cast_top)
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


## Load the map from level data (async: file reads, GLB parsing and the document read run
## on worker threads, and the authored scatter is built over several frames).
##
## A level has a map.glb (map_path), an authored map.ttmap (map_document), or both. Each
## named file is taken from the level folder, else (a client) from the download cache when
## its content hash matches the host's, else a client downloads what is missing and
## MapDownloadCoordinator finishes the load once every file has arrived. A host missing
## its GLB fails; a host missing only its document loads the GLB and says so.
func _load_level_map_async(level_data: LevelData) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null
	_level_play_controller.loaded_map_document = null

	# Clear any existing map children from the game map
	_clear_existing_maps()

	if not level_data.has_map():
		push_error("LevelPlayLoader: No map path in level data")
		return false

	var sources := _resolve_map_sources(level_data)
	if sources["error"] != "":
		push_error("LevelPlayLoader: " + sources["error"])
		return false

	var missing: Array = sources["missing"]
	if not missing.is_empty():
		if NetworkManager.is_client():
			# Request the missing files from the host; the coordinator loads the map
			# once all of them are cached.
			return _level_play_controller._map_download_coordinator.request_map_download(
				level_data.level_folder, missing, sources["found"]
			)
		if Paths.LEVEL_MAP_VARIANT in missing:
			push_error("LevelPlayLoader: Map file not found: " + level_data.get_absolute_map_path())
			return false
		# Only the document is missing and there is a GLB: play the GLB without it.
		_report_document_problem(
			"Map document not found: " + level_data.get_absolute_map_document_path()
		)

	var found: Dictionary = sources["found"]
	var map := await load_map_sources_async(
		found.get(Paths.LEVEL_MAP_VARIANT, ""), found.get(Paths.LEVEL_MAP_DOCUMENT_VARIANT, "")
	)
	if not map:
		push_error("LevelPlayLoader: Failed to load map")
		return false

	await _finalize_map_loading(map)
	return true


## Where each map file of `level_data` can be loaded from: {"found": {variant id -> path},
## "missing": [variant ids with no usable copy here], "error": String}. A client ignores a
## local or cached copy whose hash differs from the one the host sent (a stale copy).
func _resolve_map_sources(level_data: LevelData) -> Dictionary:
	var found := {}
	var missing: Array = []
	if level_data.map_path != "":
		var map_path := level_data.get_absolute_map_path()
		if map_path == "":
			return {"found": found, "missing": missing, "error": "Cannot resolve map path"}
		if map_path.begins_with("res://"):
			found[Paths.LEVEL_MAP_VARIANT] = map_path
		else:
			_resolve_map_file(level_data, Paths.LEVEL_MAP_VARIANT, map_path, found, missing)
	if level_data.map_document != "":
		var document_path := level_data.get_absolute_map_document_path()
		if document_path == "":
			return {"found": found, "missing": missing, "error": "Cannot resolve map document path"}
		_resolve_map_file(
			level_data, Paths.LEVEL_MAP_DOCUMENT_VARIANT, document_path, found, missing
		)
	return {"found": found, "missing": missing, "error": ""}


func _resolve_map_file(
	level_data: LevelData, variant: String, local_path: String, found: Dictionary, missing: Array
) -> void:
	var expected: String = level_data.map_hashes.get(variant, "")
	if FileAccess.file_exists(local_path):
		# The host's own file, or a client's same-named level; a client trusts that only
		# when it is the host's content.
		if (
			not NetworkManager.is_client()
			or expected == ""
			or MapFileHash.hash_file_cached(local_path) == expected
		):
			found[variant] = local_path
			return
	var cached := _level_play_controller._map_download_coordinator.get_cached_map_file(
		level_data.level_folder, variant, expected
	)
	if cached != "":
		found[variant] = cached
	else:
		missing.append(variant)


## Builds the map root from its files, ready for _finalize_map_loading(), through the
## shared MapSourceLoader (see MapSourceLoader.load_async: the GLB with its scatter
## filtered by the document's erase mask, or terrain when there is no GLB, plus one
## AuthoredScatter holding the document's scatter and props). Returns null on failure, or
## when a newer load or a reset superseded this one while it was waiting. The shared seam
## of the direct load and the client download path.
func load_map_sources_async(glb_path: String, document_path: String) -> Node3D:
	var generation := _load_generation
	var loader := MapSourceLoader.new(_level_play_controller.get_tree())
	loader.light_intensity_scale = _get_light_intensity_scale()
	loader.foliage_overrides = _get_foliage_overrides()
	loader.is_superseded = func() -> bool: return _superseded(generation)
	var root := await loader.load_async(glb_path, document_path)
	if root != null:
		_level_play_controller.loaded_map_document = loader.document
	return root


## True when a newer load (or a reset) replaced the one that captured `generation`, or the
## controller left the tree; the caller drops whatever it built. A freed GameMap is caught
## by _finalize_map_loading, which discards the map.
func _superseded(generation: int) -> bool:
	return generation != _load_generation or not _level_play_controller.is_inside_tree()


## A document problem that does not stop the map from loading (there is a GLB to play):
## logged, and shown to the player once.
func _report_document_problem(message: String) -> void:
	MapSourceLoader.report_document_problem(message)


## Finalize map loading after the map instance is ready: the shared install
## (MapSourceLoader.install: environment, water, weather, camera bounds, measure tool and
## grid, late-species wiring), then this controller's bookkeeping and the density toast,
## then a Blender map's grid ground sampled from its collision
## (MapSourceLoader.fit_grid_ground_async, a few frames). The direct load awaits it under the
## loading screen; the client download path calls it without awaiting, so there the grid
## keeps the fixed band for those frames.
func _finalize_map_loading(map: Node3D) -> void:
	# Check if game map is still valid (might have been freed during async loading)
	if not is_instance_valid(_level_play_controller._game_map):
		push_warning("LevelPlayLoader: GameMap was freed during async loading, discarding map")
		map.queue_free()
		return

	_level_play_controller.loaded_map_instance = map
	MapSourceLoader.install(
		map,
		_level_play_controller._game_map,
		_level_play_controller._environment_manager,
		_level_play_controller.active_level_data
	)
	_apply_foliage_density_and_notify(map)
	var generation := _load_generation
	var loader := MapSourceLoader.new(_level_play_controller.get_tree())
	loader.is_superseded = func() -> bool: return _superseded(generation)
	grid_ground_fit = await loader.fit_grid_ground_async(map, _level_play_controller._game_map)


## Applies the player's foliage density setting to a freshly loaded map, and tells them
## once if the map exceeded their budget. FoliageBudget.describe() names the density
## percentage and the setting as the cause; this function's only addition is appending a
## pointer to where the setting lives. Shown as an informational toast, not a warning --
## a user-configured setting behaving exactly as configured isn't a warning, and nothing
## here is a one-time, unrecoverable loss any more: the player can raise the dial back up
## without a reload.
func _apply_foliage_density_and_notify(map: Node3D) -> void:
	if not map:
		return
	var budget := FoliageDensityController.budget_from_settings()
	var report := FoliageDensityController.apply(map, budget)
	if report.thinned:
		UIManager.show_toast(
			"%s Adjust Foliage Density in Settings > Graphics." % FoliageBudget.describe(report),
			UIManager.TOAST_INFO,
			6.0
		)


## Get the light intensity scale from the active level data (or 1.0 if none)
func _get_light_intensity_scale() -> float:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.light_intensity_scale
	return 1.0


## Get the foliage sway overrides from the active level data (or {} if none)
func _get_foliage_overrides() -> Dictionary:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.foliage.to_dict()
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
	return LevelManager.save_level_in_place(_level_play_controller.active_level_data)


## Clear the loaded level map
func clear_level_map() -> void:
	# Clear occlusion fade state before freeing map geometry
	if _level_play_controller._game_map:
		_level_play_controller._game_map.notify_map_clearing()

	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null
	_level_play_controller.loaded_map_document = null

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
