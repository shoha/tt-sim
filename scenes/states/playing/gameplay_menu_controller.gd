extends Control

## Controller for the GameplayMenu UI.
## Handles gameplay-specific UI: asset browser, save positions, and level edit mode.
## Only active when a level is loaded.
## Adding tokens, saving positions, and editing level settings are only available to the GM.

signal drag_place_started(pack_id: String, asset_id: String, variant_id: String, icon: Texture2D)

var _level_play_controller: LevelPlayController = null

## Snapshot of every editable visual field, taken when the drawer opens and
## restored on Cancel. See LevelVisualState.
var _original_state: LevelVisualState = LevelVisualState.new()

## Coalesces per-tick visual-settings RPCs from the drawer into one send per interval.
var _visual_broadcast := VisualBroadcastThrottle.new()

@onready var save_level_button: Button = %SaveLevelButton
@onready var toggle_asset_browser_button: Button = %ToggleAssetBrowserButton
@onready var level_edit_panel: LevelEditPanel = %LevelEditPanel
@onready var player_list_drawer: PlayerListDrawer = %PlayerListDrawer


func _ready() -> void:
	# Connect to AssetBrowser's asset_selected signal
	var asset_browser: AssetBrowser = $AssetBrowserContainer/PanelContainer/VBox/AssetBrowser
	if asset_browser:
		asset_browser.asset_selected.connect(_on_asset_selected)

	var asset_browser_container = $AssetBrowserContainer
	if asset_browser_container and asset_browser_container.has_signal("asset_drag_started"):
		asset_browser_container.asset_drag_started.connect(_on_asset_drag_started)

	_visual_broadcast.name = "VisualBroadcastThrottle"
	_visual_broadcast.send = NetworkManager.broadcast_visual_settings
	add_child(_visual_broadcast)

	# Connect level edit panel (drawer) signals
	if level_edit_panel:
		level_edit_panel.drawer_opened.connect(_on_edit_drawer_opened)
		level_edit_panel.drawer_closed.connect(_on_edit_drawer_closed)
		level_edit_panel.intensity_changed.connect(_on_edit_intensity_changed)
		level_edit_panel.scale_config_changed.connect(_on_edit_scale_config_changed)
		level_edit_panel.environment_changed.connect(_on_edit_environment_changed)
		level_edit_panel.lofi_changed.connect(_on_edit_lofi_changed)
		level_edit_panel.weather_changed.connect(_on_edit_weather_changed)
		level_edit_panel.foliage_changed.connect(_on_edit_foliage_changed)
		level_edit_panel.sun_changed.connect(_on_edit_sun_changed)
		level_edit_panel.aim_sun_toggled.connect(_on_edit_aim_sun_toggled)
		level_edit_panel.water_changed.connect(_on_edit_water_changed)
		level_edit_panel.revert_to_map_defaults_requested.connect(_on_revert_to_map_defaults)
		level_edit_panel.save_requested.connect(_on_edit_save_requested)
		level_edit_panel.cancel_requested.connect(_on_edit_cancel_requested)

	# Connect to network state changes to show/hide host-only buttons
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Initially hide buttons since no level is loaded yet
	_update_asset_browser_button_state()
	_update_save_level_button_visibility()
	_update_edit_mode_drawer()
	_update_player_list_drawer()


func _exit_tree() -> void:
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)
	if InputProfile.profile_changed.is_connected(_on_input_profile_changed):
		InputProfile.profile_changed.disconnect(_on_input_profile_changed)
	UIManager.clear_hints()


func _on_input_profile_changed(_new_profile: InputProfile.Profile) -> void:
	_set_default_hints()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Connect to level state changes to update UI
	_level_play_controller.level_loaded.connect(_on_level_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)
	_level_play_controller.token_added.connect(_on_token_added)

	# Show default gameplay input hints
	_set_default_hints()
	InputProfile.profile_changed.connect(_on_input_profile_changed)

	# Update UI state
	_update_asset_browser_button_state()
	_update_save_level_button_visibility()
	_update_edit_mode_drawer()


# --- Network State Handling ---


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState,
	_new_state: NetworkManager.ConnectionState,
) -> void:
	_update_asset_browser_button_state()
	_update_save_level_button_visibility()
	_update_edit_mode_drawer()
	_update_player_list_drawer()


# --- Save Functionality ---


func _on_save_level_button_pressed() -> void:
	_save_level()


func _save_level() -> void:
	# Only GM can save
	if NetworkManager.is_restricted_client():
		push_warning("GameplayMenuController: Only GM can save level")
		return

	if not _level_play_controller:
		return
	var path := _level_play_controller.save_level_with_thumbnail()
	if path != "":
		UIManager.show_success("Level saved")
	else:
		UIManager.show_error("Failed to save level")


func _update_save_level_button_visibility() -> void:
	if save_level_button:
		# Hide for non-GM players - only GM can save
		if NetworkManager.is_restricted_client():
			save_level_button.visible = false
			return
		var should_show = (
			_level_play_controller
			and _level_play_controller.has_active_level()
			and _level_play_controller.get_token_count() > 0
		)
		save_level_button.visible = should_show


# --- Level State Handling ---


func _on_level_loaded(_level_data: LevelData) -> void:
	_update_asset_browser_button_state()
	_update_save_level_button_visibility()
	_update_edit_mode_drawer()


func _on_level_cleared() -> void:
	_update_asset_browser_button_state()
	_update_save_level_button_visibility()
	_update_edit_mode_drawer()
	# Also untoggle the buttons if they were pressed
	if toggle_asset_browser_button:
		toggle_asset_browser_button.button_pressed = false
	# Close the edit drawer if open. The unsaved edits belonged to the level that
	# just went away, so there is nothing left to prompt about.
	if level_edit_panel:
		level_edit_panel.mark_clean()
		if level_edit_panel.is_open:
			level_edit_panel.close()


func _update_asset_browser_button_state() -> void:
	if toggle_asset_browser_button:
		# Hide for non-GM players - only GM can add tokens
		if NetworkManager.is_restricted_client():
			toggle_asset_browser_button.visible = false
			return
		var has_level = _level_play_controller and _level_play_controller.has_active_level()
		toggle_asset_browser_button.visible = has_level


# --- Asset Selection Handling ---


func _on_asset_selected(pack_id: String, asset_id: String, variant_id: String) -> void:
	print("GameplayMenuController: _on_asset_selected %s/%s/%s" % [pack_id, asset_id, variant_id])
	if NetworkManager.is_restricted_client():
		UIManager.show_error("Only the GM can add tokens")
		return

	if not _level_play_controller:
		UIManager.show_error("Cannot add token — no level is loaded")
		return

	# Spawn at camera ground position instead of world origin. That position is
	# a Y=0 plane intersection, so re-resolve the real surface height straight
	# down at its X/Z (same snap-then-resolve order drag-place uses) and spawn
	# with settle := true so the token lands on terrain instead of hovering.
	var spawn_pos := _get_camera_ground_position()
	var game_map := _level_play_controller.get_game_map()
	if game_map and game_map.world_viewport:
		# world_viewport.find_world_3d(), not this node's get_world_3d(): it reads
		# the world tokens actually live in. The world_3d property would be null
		# here because the SubViewport does not own its world (own_world_3d).
		var resolved := DragPlaceController.raycast_terrain_down(
			game_map.world_viewport.find_world_3d().direct_space_state, spawn_pos
		)
		if resolved != Vector3.INF:
			spawn_pos = resolved + Vector3(0, DragPlaceController.PLACE_CLEARANCE, 0)

	var token = _level_play_controller.spawn_asset(pack_id, asset_id, variant_id, spawn_pos, true)
	if not token:
		UIManager.show_error("Failed to add token — asset may still be downloading")


func _on_asset_drag_started(
	pack_id: String, asset_id: String, variant_id: String, icon: Texture2D
) -> void:
	if NetworkManager.is_restricted_client():
		return
	drag_place_started.emit(pack_id, asset_id, variant_id, icon)


## Get the world position where the camera center intersects the Y=0 ground plane.
## Uses math-only plane intersection (no physics query).
func _get_camera_ground_position() -> Vector3:
	if not _level_play_controller:
		return Vector3.ZERO
	var game_map := _level_play_controller.get_game_map()
	if not game_map or not game_map.camera_node or not game_map.world_viewport:
		return Vector3.ZERO

	var viewport_center := Vector2(game_map.world_viewport.size) / 2.0
	var origin := game_map.camera_node.project_ray_origin(viewport_center)
	var direction := game_map.camera_node.project_ray_normal(viewport_center)

	# Intersect ray with Y=0 plane
	if abs(direction.y) < 0.0001:
		# Ray is parallel to ground -- fallback to camera holder XZ
		return Vector3(
			game_map.cameraholder_node.global_position.x,
			0,
			game_map.cameraholder_node.global_position.z,
		)
	var t := -origin.y / direction.y
	if t < 0:
		# Ray points away from ground -- fallback
		return Vector3(
			game_map.cameraholder_node.global_position.x,
			0,
			game_map.cameraholder_node.global_position.z,
		)
	var ground_pos := origin + direction * t

	# Apply grid snap if enabled
	if game_map.drag_and_drop_node and game_map.drag_and_drop_node.grid_snap_enabled:
		ground_pos = (
			ScaleUtils
			. snap_to_grid(
				ground_pos,
				game_map.drag_and_drop_node.grid_cell_size,
				game_map.drag_and_drop_node.grid_origin,
			)
		)

	return ground_pos


func _on_token_added(_token: BoardToken) -> void:
	# Update save button visibility when a token is added
	_update_save_level_button_visibility()


# ============================================================================
# Edit Mode (Drawer)
# ============================================================================


## Reveal or conceal the edit drawer tab based on permissions.
## Visible whenever the local player has GM-like control:
##   - Local (non-networked) play: always the GM
##   - Networked play: only the host/GM
func _update_edit_mode_drawer() -> void:
	if not level_edit_panel:
		return
	var has_level = _level_play_controller and _level_play_controller.has_active_level()
	var can_edit = has_level and NetworkManager.has_gm_access()
	if can_edit:
		level_edit_panel.visible = true
		level_edit_panel.reveal()
	else:
		level_edit_panel.conceal()


## Called when the drawer tab is clicked and the drawer opens.
## Snapshot current values so the Cancel button can revert to them.
func _on_edit_drawer_opened() -> void:
	_enter_edit_mode()


## Called when the drawer finishes closing (via tab or programmatically).
## Changes are kept — the user can Cancel to revert, or Save to persist to disk.
## Also deactivates the sun gizmo so it cannot outlive the drawer.
func _on_edit_drawer_closed() -> void:
	_deactivate_sun_gizmo()


## The gizmo is an aiming mode, not a setting: it must not outlive the drawer
## closing or survive a Save that ends the editing pass.
func _deactivate_sun_gizmo() -> void:
	var gizmo := _get_sun_gizmo()
	if gizmo and gizmo.is_active():
		gizmo.deactivate()


## Snapshot current level values and initialize the edit panel.
func _enter_edit_mode() -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	var level_data = _level_play_controller.active_level_data

	# Snapshot original values for cancel/revert, but never over a snapshot that
	# still has unsaved edits standing against it. The tab now vetoes a dirty
	# close, so this guards the routes that bypass the prompt: conceal() when GM
	# access is lost mid-edit (the drawer hides without reverting), and any
	# programmatic reopen while dirty. In both cases Cancel must still return to
	# the state the level had before the first of those edits.
	if not level_edit_panel.is_dirty():
		_original_state = LevelVisualState.from_level_data(level_data)

	# Initialize the edit panel with current values
	var map_defaults = _level_play_controller.get_map_environment_config()
	var has_map_sky = _level_play_controller.get_map_sky_resource() != null
	level_edit_panel.initialize(level_data, map_defaults, has_map_sky)


## Revert all live changes to the snapshot taken when the drawer opened.
func _revert_edit_mode_values() -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return
	var level_data: LevelData = _level_play_controller.active_level_data
	# Level data first: update_measure_tool_scale() below re-reads the grid fields
	# from it; apply_visual_state() itself takes the state object.
	_original_state.apply_to_level_data(level_data)
	_level_play_controller.apply_visual_state(_original_state)
	# apply_visual_state() does not touch the grid fields. The measure tool, snap
	# and overlay read them at configure time, so they must be re-applied
	# explicitly here.
	_level_play_controller.update_measure_tool_scale()
	# A pending partial batch must not land after this full snapshot.
	_visual_broadcast.drop()
	if NetworkManager.is_networked() and NetworkManager.is_host():
		NetworkManager.broadcast_visual_settings(_original_state.to_broadcast_dict())


# --- Edit Panel Signal Handlers ---


## Real-time scale config change from the edit panel.
## Keeps level_data in sync so changes survive drawer close/reopen.
## Also updates the measure tool so distance readouts reflect the new units.
func _on_edit_scale_config_changed(
	grid_cell_size: float, display_unit: String, display_unit_per_cell: float
) -> void:
	if _level_play_controller and _level_play_controller.active_level_data:
		var ld = _level_play_controller.active_level_data
		ld.grid_cell_size = grid_cell_size
		ld.display_unit = display_unit
		ld.display_unit_per_cell = display_unit_per_cell
		_level_play_controller.update_measure_tool_scale()


## Real-time light intensity change from the edit panel
func _on_edit_intensity_changed(new_scale: float) -> void:
	if _level_play_controller:
		_level_play_controller.apply_light_intensity_scale(new_scale)
	# Broadcast to clients so they see the same intensity
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"light_intensity": new_scale})


## Real-time environment change from the edit panel
func _on_edit_environment_changed(preset: String, overrides: Dictionary) -> void:
	if _level_play_controller:
		_level_play_controller.apply_environment_settings(preset, overrides)
		# Keep level_data in sync so changes survive drawer close/reopen
		if _level_play_controller.active_level_data:
			_level_play_controller.active_level_data.environment_preset = preset
			_level_play_controller.active_level_data.environment_overrides = overrides.duplicate()
	# Broadcast to clients so they see the same environment
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"environment_preset": preset, "environment_overrides": overrides})


## Revert environment to the map's original embedded settings.
## Clears preset and overrides so the map defaults layer takes effect.
func _on_revert_to_map_defaults() -> void:
	if not _level_play_controller:
		return
	var map_config = _level_play_controller.get_map_environment_config()
	if map_config.is_empty():
		return

	# Apply with empty preset and overrides — map defaults layer does the work
	_level_play_controller.apply_environment_settings("", {})

	# Keep level_data in sync
	if _level_play_controller.active_level_data:
		_level_play_controller.active_level_data.environment_preset = ""
		_level_play_controller.active_level_data.environment_overrides = {}

	# Broadcast to clients so they also revert to map defaults
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"environment_preset": "", "environment_overrides": {}})

	# Update the panel's internal state and controls to match
	level_edit_panel.apply_environment_state("", {})

	UIManager.show_info("Environment reset to the map's defaults; overrides cleared.")


## Real-time lo-fi shader change from the edit panel
func _on_edit_lofi_changed(overrides: Dictionary) -> void:
	if _level_play_controller:
		var game_map = _level_play_controller.get_game_map()
		if game_map:
			game_map.apply_lofi_overrides(overrides)
		# Keep level_data in sync so changes survive drawer close/reopen
		if _level_play_controller.active_level_data:
			_level_play_controller.active_level_data.lofi = LofiSettings.from_dict(overrides)
	# Broadcast to clients so they see the same lo-fi settings
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"lofi_overrides": overrides})


## Real-time weather change from the edit panel
func _on_edit_weather_changed(overrides: Dictionary) -> void:
	if _level_play_controller:
		var game_map = _level_play_controller.get_game_map()
		if game_map:
			game_map.apply_weather_overrides(overrides)
		if _level_play_controller.active_level_data:
			_level_play_controller.active_level_data.weather = WeatherSettings.from_dict(overrides)
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"weather_overrides": overrides})


## Real-time foliage sway change from the edit panel
func _on_edit_foliage_changed(overrides: Dictionary) -> void:
	if _level_play_controller:
		_level_play_controller.apply_foliage_overrides(overrides)
		if _level_play_controller.active_level_data:
			_level_play_controller.active_level_data.foliage = FoliageSettings.from_dict(overrides)
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"foliage_overrides": overrides})


## Real-time sun change from the edit panel
func _on_edit_sun_changed(settings: SunSettings) -> void:
	if _level_play_controller:
		_level_play_controller.apply_sun_settings(settings)
		var level_data = _level_play_controller.active_level_data
		if level_data:
			level_data.visual_settings.sun = settings.copy_settings()
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"sun_settings": settings.to_dict()})


## Toggle the sun-aiming gizmo, and keep the panel's numeric fields and toggle
## button in step with it. The gizmo is created per level load, so it is looked
## up on demand rather than cached.
func _on_edit_aim_sun_toggled(active: bool) -> void:
	var gizmo := _get_sun_gizmo()
	if not gizmo:
		return
	if active:
		var sun: SunSettings = _level_play_controller.active_level_data.visual_settings.sun
		gizmo.set_direction(sun.azimuth_degrees, sun.elevation_degrees)
		if not gizmo.direction_changed.is_connected(_on_sun_gizmo_direction_changed):
			gizmo.direction_changed.connect(_on_sun_gizmo_direction_changed)
			gizmo.toggled.connect(_on_sun_gizmo_toggled_externally)
	if gizmo.is_active() != active:
		gizmo.toggle()


func _on_sun_gizmo_direction_changed(azimuth_degrees: float, elevation_degrees: float) -> void:
	if level_edit_panel:
		level_edit_panel.set_sun_direction_from_gizmo(azimuth_degrees, elevation_degrees)


## The gizmo can deactivate without the panel asking (RMB, or the measure tool
## taking over), so mirror its state back onto the toggle button.
func _on_sun_gizmo_toggled_externally(active: bool) -> void:
	if level_edit_panel:
		level_edit_panel.set_aim_sun_pressed(active)


func _get_sun_gizmo() -> SunGizmoTool:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return null
	var game_map = _level_play_controller.get_game_map()
	return game_map.get_sun_gizmo() if game_map else null


## Real-time water change from the edit panel
func _on_edit_water_changed(overrides: Dictionary) -> void:
	if _level_play_controller:
		_level_play_controller.apply_water_settings(overrides)
		var level_data: LevelData = _level_play_controller.active_level_data
		if level_data:
			level_data.water = WaterSettings.from_dict(overrides)
			level_data.water_style = level_data.water.matching_look()
	if NetworkManager.is_networked() and NetworkManager.is_host():
		_visual_broadcast.queue({"water_overrides": overrides})


## Save all edited values to level data and persist to disk
func _on_edit_save_requested(state: LevelVisualState) -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	var level_data: LevelData = _level_play_controller.active_level_data
	state.apply_to_level_data(level_data)

	# Re-broadcast the saved values so the host's late-joiner snapshot
	# (_current_level_dict) is guaranteed to reflect what was just saved, even
	# if this save wasn't preceded by a live-edit broadcast for every field.
	# A pending partial batch must not land after this full snapshot.
	_visual_broadcast.drop()
	if NetworkManager.is_networked() and NetworkManager.is_host():
		NetworkManager.broadcast_visual_settings(state.to_broadcast_dict())

	# Save to disk — use folder format when the level came from a folder
	var thumbnail := _level_play_controller.capture_thumbnail() if _level_play_controller else null
	var save_path := LevelManager.save_level_in_place(level_data)
	if save_path != "":
		if thumbnail:
			LevelManager.save_thumbnail(level_data, thumbnail)
		UIManager.show_success("Level settings saved")

		# The drawer no longer closes on Save, so the revert snapshot has to
		# advance with it -- otherwise a later Cancel would undo work already
		# written to disk.
		_original_state = state.copy()

		# The drawer stays open after a save so tuning can continue; only the
		# unsaved-changes flag is cleared. Save still ends the editing pass,
		# though, so the aiming gizmo goes away exactly as it would on a close.
		level_edit_panel.mark_clean()
	else:
		UIManager.show_error("Failed to save level settings")
		# The disk write failed: the panel stays dirty and the revert snapshot
		# is left untouched so Cancel still reverts to the last known-good state.

	_deactivate_sun_gizmo()


## Cancel editing: revert to the snapshot taken when the drawer was opened
func _on_edit_cancel_requested() -> void:
	_revert_edit_mode_values()
	level_edit_panel.mark_clean()
	level_edit_panel.close()


## Run on_ready once the Visuals drawer's unsaved changes are settled: straight
## away when clean, after the user confirms discarding otherwise.
func request_level_change(on_ready: Callable) -> void:
	if not level_edit_panel or not level_edit_panel.is_dirty():
		on_ready.call()
		return
	UIManager.show_danger_confirmation(
		"Unsaved visual changes",
		"Discard the changes made in the Visuals drawer and change the level?",
		func() -> void:
			level_edit_panel.mark_clean()
			level_edit_panel.close()
			on_ready.call(),
		"Discard and change",
		"Keep editing"
	)


# --- Player List ---


## Show/hide the player list drawer based on network state.
## The drawer manages its own reveal/conceal animation internally;
## we just need to ensure the node is in the tree and trigger visibility.
func _update_player_list_drawer() -> void:
	if not player_list_drawer:
		return
	if NetworkManager.is_networked():
		player_list_drawer.visible = true
		player_list_drawer.reveal()
	else:
		player_list_drawer.conceal()


## Clear the current level (exposed for external use)
func clear_level() -> void:
	if _level_play_controller:
		_level_play_controller.clear_level()
	_update_save_level_button_visibility()


## Display the default gameplay input hints
func _set_default_hints() -> void:
	(
		UIManager
		. set_hints(
			[
				{"key": InputProfile.label(&"pause"), "action": "Pause"},
				{"key": InputProfile.label(&"wasd"), "action": "Pan"},
				{"key": InputProfile.label(&"zoom"), "action": "Zoom"},
				{"key": InputProfile.label(&"reset_camera"), "action": "Reset Camera"},
				{"key": InputProfile.label(&"measure"), "action": "Measure"},
				{"key": InputProfile.label(&"grid"), "action": "Grid"},
				{"key": "F1", "action": "Help"},
			]
		)
	)
