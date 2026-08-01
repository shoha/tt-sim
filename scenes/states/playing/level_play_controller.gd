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
var _environment_manager := LevelEnvironmentManager.new()  # Manages lighting/atmosphere
var _map_download_coordinator := MapDownloadCoordinator.new()  # Manages map downloads
var _token_spawner := TokenSpawner.new()  # Manages token spawning/tracking/clearing
## Manages network sync (reconciliation, client transforms, drag locks, permission-driven
## interactivity). Takes _token_spawner by direct reference at construction time (not via
## setup()) so _on_client_transform_received() keeps working on a bare, unconfigured
## LevelPlayController -- see NetworkTokenSync._init().
var _network_token_sync := NetworkTokenSync.new(_token_spawner)
## Manages async level loading: the load coroutine, progress reporting, load queueing, and
## level/map clearing. Reaches _game_map/_token_spawner/_network_token_sync/
## _environment_manager/_map_download_coordinator and active_level_data/loaded_map_instance/
## is_editor_preview through the back-reference given in its setup() -- see LevelPlayLoader's
## class doc comment for why those three fields aren't owned by it directly.
var _level_loader := LevelPlayLoader.new()
var _permission_handler: TokenPermissionHandler = null


## Initialize with a reference to the game map
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_environment_manager.setup(game_map)
	_game_map.setup_measure_tool()
	_game_map.setup_grid_overlay()
	_game_map.setup_drag_ruler()
	_level_loader.setup(self)
	_map_download_coordinator.setup(
		_level_loader._load_map_from_path, _level_loader._finalize_map_loading
	)
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

	# Network sync: reconciliation timer, client transforms, drag locks, and
	# permission-driven token interactivity (delegated to NetworkTokenSync).
	_network_token_sync.setup(self)

	if not _level_loader.level_loaded.is_connected(_on_level_loader_level_loaded):
		_level_loader.level_loaded.connect(_on_level_loader_level_loaded)
	if not _level_loader.level_cleared.is_connected(_on_level_loader_level_cleared):
		_level_loader.level_cleared.connect(_on_level_loader_level_cleared)
	if not _level_loader.token_spawned.is_connected(_on_level_loader_token_spawned):
		_level_loader.token_spawned.connect(_on_level_loader_token_spawned)
	if not _level_loader.level_loading_started.is_connected(_on_level_loader_loading_started):
		_level_loader.level_loading_started.connect(_on_level_loader_loading_started)
	if not _level_loader.level_loading_progress.is_connected(_on_level_loader_loading_progress):
		_level_loader.level_loading_progress.connect(_on_level_loader_loading_progress)
	if not _level_loader.level_loading_completed.is_connected(_on_level_loader_loading_completed):
		_level_loader.level_loading_completed.connect(_on_level_loader_loading_completed)

	# Listen for visual settings changes from the host (map scale, lighting, environment, lo-fi)
	if not NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.connect(_on_visual_settings_received)

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
	if NetworkManager.visual_settings_received.is_connected(_on_visual_settings_received):
		NetworkManager.visual_settings_received.disconnect(_on_visual_settings_received)

	# Disconnect network sync signals (reconciliation, client transforms, drag locks, permissions)
	_network_token_sync.teardown()

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


## Relay LevelPlayLoader's signals through this facade's own same-named signals so
## external listeners connected to LevelPlayController (scenes/root.gd,
## gameplay_menu_controller.gd, tests/test_play_level.gd) are unaffected by the extraction.
func _on_level_loader_level_loaded(level_data: LevelData) -> void:
	level_loaded.emit(level_data)


func _on_level_loader_level_cleared() -> void:
	level_cleared.emit()


func _on_level_loader_token_spawned(token: BoardToken, placement: TokenPlacement) -> void:
	token_spawned.emit(token, placement)


func _on_level_loader_loading_started() -> void:
	level_loading_started.emit()


func _on_level_loader_loading_progress(progress: float, status: String) -> void:
	level_loading_progress.emit(progress, status)


func _on_level_loader_loading_completed() -> void:
	level_loading_completed.emit()


## Getter injected into TokenSpawner so it can read the currently active level
## data (owned here, reassigned on every level load) without a direct field
## reference.
func _get_active_level_data() -> LevelData:
	return active_level_data


## Load and play a level (async version - does not block main thread)
## Returns true if loading started successfully, false on immediate failure
## Listen to level_loaded signal for completion
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## scenes/root.gd and tests call this directly on the LevelPlayController instance.
func play_level(level_data: LevelData) -> bool:
	return _level_loader.play_level(level_data)


## Get the environment manager (for external callers that need direct access).
func get_environment_manager() -> LevelEnvironmentManager:
	return _environment_manager


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


## Public: update measure tool and grid configuration (called when GM changes scale in UI).
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## gameplay_menu_controller.gd calls this directly.
func update_measure_tool_scale() -> void:
	_level_loader.update_measure_tool_scale()


## Check if level loading is in progress (async loading)
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## scenes/root.gd, root_network_handler.gd, and game_map.gd call this directly.
func is_loading() -> bool:
	return _level_loader.is_loading()


## Check if there's a level queued to load after current loading completes
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## scenes/root.gd calls this directly.
func has_queued_level() -> bool:
	return _level_loader.has_queued_level()


## Connect token's context menu signal and other per-token signals to game map.
## Forwards to TokenSpawner -- kept as a same-named method here since
## RootNetworkHandler calls this directly on the LevelPlayController instance.
func _connect_token_context_menu(token: BoardToken) -> void:
	_token_spawner._connect_token_context_menu(token)


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
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## gameplay_menu_controller.gd calls this directly.
func save_level() -> String:
	return _level_loader.save_level()


# =============================================================================
# TOKEN PERMISSIONS
# =============================================================================


## Host-side: handle a client-sent token transform. Forwards to
## NetworkTokenSync -- kept as a same-named method here since
## tests/unit/test_level_play_controller_transform_validation.gd calls this
## directly on a bare, unconfigured LevelPlayController (never setup(), never
## added to the tree). _network_token_sync holds a direct TokenSpawner
## reference injected at construction time (not via setup()) specifically so
## this keeps working in that scenario -- see NetworkTokenSync._init().
func _on_client_transform_received(
	sender_id: int,
	network_id: String,
	pos: Vector3,
	rot: Vector3,
	scl: Vector3,
) -> void:
	_network_token_sync._on_client_transform_received(sender_id, network_id, pos, rot, scl)


## Clear spawned tokens. Forwards the token-storage cleanup to TokenSpawner
## and the network sync state cleanup (client transform signals, throttle) to
## NetworkTokenSync; GameState clearing is not part of either extraction and
## stays here.
func clear_level_tokens() -> void:
	_token_spawner.clear_level_tokens()
	active_level_data = null

	_network_token_sync.reset()

	# Clear GameState (also clears permissions)
	GameState.clear_all_tokens()


## Clear the loaded level map
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## scenes/root.gd calls this directly.
func clear_level_map() -> void:
	_level_loader.clear_level_map()


## Clear everything from the current level
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## gameplay_menu_controller.gd calls this directly, and the "Deactivated by
## LevelPlayController.clear_level()" contract documented in docs/ARCHITECTURE.md and
## .cursor/skills/godot-ttsim/SKILL.md still holds.
func clear_level() -> void:
	_level_loader.clear_level()


## Reset all loading state (call when exiting PLAYING state)
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## scenes/root.gd calls this directly.
func reset_loading_state() -> void:
	_level_loader.reset_loading_state()


## Called on clients when the host changes visual settings (map scale, lighting, environment, lo-fi)
func _on_visual_settings_received(settings: Dictionary) -> void:
	if settings.has("map_scale"):
		_level_loader.set_map_scale(settings["map_scale"])
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
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## app_menu_controller.gd and gameplay_menu_controller.gd call this directly.
func has_active_level() -> bool:
	return _level_loader.has_active_level()


## Get token count. Forwards to TokenSpawner -- kept as a same-named method
## here since gameplay_menu_controller.gd calls this directly.
func get_token_count() -> int:
	return _token_spawner.get_token_count()
