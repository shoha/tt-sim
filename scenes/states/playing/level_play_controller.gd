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

## Fallback spawn offset (world units) for duplicate_token() when no level is
## loaded (active_level_data null, so grid_cell_size isn't available).
const DUPLICATE_OFFSET_FALLBACK := 1.5

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
	_game_map.setup_sun_gizmo()
	_game_map.setup_grid_overlay()
	_game_map.setup_drag_ruler()
	_game_map.setup_performance_overlay()
	_game_map.setup_debug_render_toggles()
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
		history.set_rename_callable(_token_spawner.rename_token)
		history.set_remove_callable(_token_spawner.remove_token)


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


## Apply foliage sway overrides to all cached wind materials in the loaded map.
func apply_foliage_overrides(overrides: Dictionary) -> void:
	_environment_manager.apply_foliage_overrides(overrides)


## Apply sun light overrides to the live level (mode + time of day).
func apply_sun_settings(settings: SunSettings) -> void:
	_environment_manager.apply_sun_settings(settings)


## Apply a water style ("stylized"/"realistic") to the live level's water
## meshes. Real-time reflections (SSR) are a separate, purely global Settings
## toggle now (see LevelEnvironmentManager.apply_rendering_toggles()) --
## Water Style no longer has any SSR-specific behavior of its own.
func apply_water_style_setting(style: String) -> void:
	WaterGlbUtils.apply_water_style(style)


## Apply environment settings to the live WorldEnvironment.
func apply_environment_settings(preset: String, overrides: Dictionary) -> void:
	_environment_manager.apply_environment_settings(preset, overrides)
	# The environment apply overwrote fog_density/fog_enabled from config; give
	# the weather renderer its fog contribution back.
	var game_map := get_game_map()
	if game_map:
		game_map.rebase_weather_fog()


## Apply a whole LevelVisualState to the running level. This is the single live
## apply path: the Visuals drawer's Cancel and Save, and the client receive path,
## all go through here. Applies the live visual fields only -- light intensity,
## environment, foliage, sun, water style, lo-fi, weather. It does not write
## level data, except that apply_light_intensity_scale() mirrors the scale into
## active_level_data (already the same value for every caller). Grid scale
## (grid_cell_size, display_unit, display_unit_per_cell) is not networked -- it
## never appears in the broadcast payload -- so it is not re-applied here.
## Callers that change those fields on level data (the drawer's Cancel path)
## call update_measure_tool_scale() themselves.
func apply_visual_state(state: LevelVisualState) -> void:
	# The client receive path can arrive before a level is loaded (e.g. a
	# throttled broadcast landing during the load window); silently no-op
	# rather than applying visual settings against no active level.
	if not has_active_level():
		return
	apply_light_intensity_scale(state.light_intensity_scale)
	apply_environment_settings(state.environment_preset, state.environment_overrides)
	apply_foliage_overrides(state.foliage.to_dict())
	apply_sun_settings(state.sun.copy_settings())
	apply_water_style_setting(state.water_style)
	var game_map := get_game_map()
	if game_map:
		# Merge over the full defaults so the three non-editable lo-fi parameters
		# are reset too (LofiSettings carries only the editable seven).
		var lofi_config := Constants.LOFI_DEFAULTS.duplicate()
		lofi_config.merge(state.lofi.to_dict(), true)
		game_map.apply_lofi_overrides(lofi_config)
		game_map.apply_weather_overrides(state.weather.to_dict())


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


## Register a token created from network state so TokenSpawner's reverse index
## can find it (drag locks, permissions, undo). See RootNetworkHandler.
func track_network_token(token: BoardToken) -> void:
	_token_spawner.track_network_token(token)


## Forget a network-tracked token after the host removed it. See TokenSpawner.untrack_network_token.
func untrack_network_token(network_id: String) -> void:
	_token_spawner.untrack_network_token(network_id)


## O(1) lookup by network id through TokenSpawner's reverse index. Use this
## rather than reading spawned_tokens, which is keyed by placement id.
func find_token_by_network_id(network_id: String) -> BoardToken:
	return _token_spawner.find_token_by_network_id(network_id)


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
	settle: bool = false,
) -> BoardToken:
	return _token_spawner.spawn_asset(pack_id, asset_id, variant_id, spawn_position, settle)


## Remove a token from the level. Forwards to TokenSpawner -- kept as a
## same-named method here for the context menu (game_map.gd) to call directly
## on this LevelPlayController instance. Does not record undo -- callers that
## want undo support must record it themselves before calling this.
func remove_token(token: BoardToken) -> bool:
	return _token_spawner.remove_token(token)


## Rename a token. Forwards to TokenSpawner -- kept as a same-named method
## here for the context menu (game_map.gd) and GameplayActionHistory's rename
## undo replay to call directly on this LevelPlayController instance.
func rename_token(token: BoardToken, new_name: String) -> void:
	_token_spawner.rename_token(token, new_name)


## Duplicate a token: spawns a fresh copy of the same asset one grid cell over
## from the source token, then copies its name, health, rotation, scale and
## player visibility across. Permissions are deliberately not copied -- the copy
## starts GM-only, like any freshly spawned token.
##
## No trailing notify_token_properties_changed() call is needed here --
## rename_token() already calls it internally for the name, set_max_health()/
## heal()/take_damage() all unconditionally emit health_changed, and
## set_visible_to_players() emits token_visibility_changed, all of which
## TokenSpawner._connect_token_state_signals() (wired up by spawn_asset() ->
## add_token_to_level() for every authoritative peer) already routes to the same
## handler. The transform is the exception: set_transform_immediate() emits
## nothing, so transform_changed is emitted explicitly afterwards -- the same
## thing BoardTokenController._reset_rotation_and_scale() does.
##
## Returns null without authority (mirrors remove_token()).
func duplicate_token(token: BoardToken) -> BoardToken:
	if not GameState.has_authority():
		return null
	if not token.rigid_body:
		return null

	var offset: float = (
		active_level_data.grid_cell_size if active_level_data else DUPLICATE_OFFSET_FALLBACK
	)
	var spawn_position: Vector3 = token.rigid_body.global_position + Vector3(offset, 0, 0)
	var source_rotation: Vector3 = token.rigid_body.global_rotation
	var source_scale: Vector3 = token.rigid_body.scale
	var new_token := spawn_asset(token.pack_id, token.asset_id, token.variant_id, spawn_position)
	if not new_token:
		return null

	rename_token(new_token, token.token_name)
	new_token.set_max_health(token.max_health)
	var health_diff: int = token.current_health - new_token.current_health
	if health_diff > 0:
		new_token.heal(health_diff)
	elif health_diff < 0:
		new_token.take_damage(health_diff)

	new_token.set_transform_immediate(spawn_position, source_rotation, source_scale)
	# Sync GameState and the network from the copied transform first: the pop-in
	# tween below starts at near-zero scale, and a sync taken mid-tween would
	# record that instead of the real scale.
	new_token.transform_changed.emit()
	# spawn_asset() already started the pop-in tween towards the default scale;
	# restart it so it targets the copied scale instead of snapping back to 1.
	new_token.play_spawn_animation()
	# A hidden source produces a hidden copy. Goes through the setter so the
	# visibility visuals update and the network sees it.
	new_token.set_visible_to_players(token.is_visible_to_players)
	return new_token


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


## Called on clients when the host changes visual settings. Partial payloads are
## patched onto a snapshot of the current level state and the whole state is
## re-applied, so every key goes through the one apply path.
func _on_visual_settings_received(settings: Dictionary) -> void:
	if settings.has("map_scale"):
		_level_loader.set_map_scale(settings["map_scale"])
	if not active_level_data:
		return
	var state := LevelVisualState.from_level_data(active_level_data)
	state.patch_from_broadcast_dict(settings)
	state.apply_to_level_data(active_level_data)
	apply_visual_state(state)


## Check if a level is currently loaded
## Forwards to LevelPlayLoader -- kept as a same-named method here since
## app_menu_controller.gd and gameplay_menu_controller.gd call this directly.
func has_active_level() -> bool:
	return _level_loader.has_active_level()


## Get token count. Forwards to TokenSpawner -- kept as a same-named method
## here since gameplay_menu_controller.gd calls this directly.
func get_token_count() -> int:
	return _token_spawner.get_token_count()
