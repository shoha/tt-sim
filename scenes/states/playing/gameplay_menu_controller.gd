extends Control

## Controller for the GameplayMenu UI.
## Handles gameplay-specific UI: asset browser, save positions, and level edit mode.
## Only active when a level is loaded.
## Adding tokens, saving positions, and editing level settings are only available to the GM.

## Emitted when the user clicks "Level Details..." in the edit drawer.
## Root wires this to AppMenuController.open_level_editor().
signal open_editor_requested

var _level_play_controller: LevelPlayController = null

# Original values snapshot for edit mode cancel/revert
var _original_map_scale: Vector3 = Vector3.ONE
var _original_light_intensity: float = 1.0
var _original_environment_preset: String = ""
var _original_environment_overrides: Dictionary = {}
var _original_lofi_overrides: Dictionary = {}

# Flag to distinguish save-close from cancel/tab-close
var _edit_saved: bool = false

@onready var save_level_button: Button = %SaveLevelButton
@onready var toggle_asset_browser_button: Button = %ToggleAssetBrowserButton
@onready var level_edit_panel: LevelEditPanel = %LevelEditPanel
@onready var player_list_drawer: PlayerListDrawer = %PlayerListDrawer


func _ready() -> void:
	# Connect to AssetBrowser's asset_selected signal
	var asset_browser: AssetBrowser = $AssetBrowserContainer/PanelContainer/VBox/AssetBrowser
	if asset_browser:
		asset_browser.asset_selected.connect(_on_asset_selected)

	# Connect level edit panel (drawer) signals
	if level_edit_panel:
		level_edit_panel.drawer_opened.connect(_on_edit_drawer_opened)
		level_edit_panel.drawer_closed.connect(_on_edit_drawer_closed)
		level_edit_panel.map_scale_changed.connect(_on_edit_map_scale_changed)
		level_edit_panel.intensity_changed.connect(_on_edit_intensity_changed)
		level_edit_panel.environment_changed.connect(_on_edit_environment_changed)
		level_edit_panel.lofi_changed.connect(_on_edit_lofi_changed)
		level_edit_panel.revert_to_map_defaults_requested.connect(_on_revert_to_map_defaults)
		level_edit_panel.save_requested.connect(_on_edit_save_requested)
		level_edit_panel.cancel_requested.connect(_on_edit_cancel_requested)
		level_edit_panel.open_editor_requested.connect(_on_open_editor_requested)

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


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Connect to level state changes to update UI
	_level_play_controller.level_loaded.connect(_on_level_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)
	_level_play_controller.token_added.connect(_on_token_added)

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
	if not NetworkManager.is_gm() and NetworkManager.is_networked():
		push_warning("GameplayMenuController: Only GM can save level")
		return

	if not _level_play_controller:
		return
	var path = _level_play_controller.save_level()
	if path == "":
		push_error("GameplayMenuController: Failed to save level")


func _update_save_level_button_visibility() -> void:
	if save_level_button:
		# Hide for non-GM players - only GM can save
		if not NetworkManager.is_gm() and NetworkManager.is_networked():
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
	# Close the edit drawer if open
	if level_edit_panel and level_edit_panel.is_open:
		_edit_saved = true  # Suppress revert on close — level was cleared
		level_edit_panel.close()


func _update_asset_browser_button_state() -> void:
	if toggle_asset_browser_button:
		# Hide for non-GM players - only GM can add tokens
		if not NetworkManager.is_gm() and NetworkManager.is_networked():
			toggle_asset_browser_button.visible = false
			return
		var has_level = _level_play_controller and _level_play_controller.has_active_level()
		toggle_asset_browser_button.visible = has_level


# --- Asset Selection Handling ---


func _on_asset_selected(pack_id: String, asset_id: String, variant_id: String) -> void:
	# Only GM can add tokens
	if not NetworkManager.is_gm() and NetworkManager.is_networked():
		UIManager.show_error("Only the GM can add tokens")
		return

	# Spawn the asset via LevelPlayController
	if _level_play_controller:
		var token = _level_play_controller.spawn_asset(pack_id, asset_id, variant_id)
		if not token:
			UIManager.show_error("Failed to add token — asset may still be downloading")
	else:
		UIManager.show_error("Cannot add token — no level is loaded")


func _on_token_added(_token: BoardToken) -> void:
	# Update save button visibility when a token is added
	_update_save_level_button_visibility()


# ============================================================================
# Edit Mode (Drawer)
# ============================================================================


## Reveal or conceal the edit drawer tab based on permissions.
## Visible during editor preview OR for the GM in a networked game.
func _update_edit_mode_drawer() -> void:
	if not level_edit_panel:
		return
	var has_level = _level_play_controller and _level_play_controller.has_active_level()
	var is_editor_preview = has_level and _level_play_controller.is_editor_preview
	var is_networked_gm = has_level and NetworkManager.is_networked() and NetworkManager.is_gm()
	if is_editor_preview or is_networked_gm:
		level_edit_panel.visible = true
		level_edit_panel.reveal()
	else:
		level_edit_panel.conceal()


## Called when the drawer tab is clicked and the drawer opens.
## Snapshot current values and initialize the panel controls.
func _on_edit_drawer_opened() -> void:
	_edit_saved = false
	_enter_edit_mode()


## Called when the drawer finishes closing (via tab or programmatically).
## Reverts changes unless the user saved.
func _on_edit_drawer_closed() -> void:
	if not _edit_saved:
		_revert_edit_mode_values()
	_edit_saved = false


## Snapshot current level values and initialize the edit panel.
func _enter_edit_mode() -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	var level_data = _level_play_controller.active_level_data

	# Snapshot original values for cancel/revert
	_original_map_scale = level_data.map_scale
	_original_light_intensity = level_data.light_intensity_scale
	_original_environment_preset = level_data.environment_preset
	_original_environment_overrides = level_data.environment_overrides.duplicate()
	_original_lofi_overrides = level_data.lofi_overrides.duplicate()

	# Initialize the edit panel with current values
	var map_defaults = _level_play_controller.get_map_environment_config()
	var has_map_sky = _level_play_controller.get_map_sky_resource() != null
	(
		level_edit_panel
		. initialize(
			level_data.map_scale.x,
			level_data.light_intensity_scale,
			level_data.environment_preset,
			level_data.environment_overrides,
			level_data.lofi_overrides,
			map_defaults,
			has_map_sky,
		)
	)


## Revert all live changes to the original snapshot values.
func _revert_edit_mode_values() -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	var level_data = _level_play_controller.active_level_data

	# Restore original values to level data
	level_data.map_scale = _original_map_scale
	level_data.light_intensity_scale = _original_light_intensity
	level_data.environment_preset = _original_environment_preset
	level_data.environment_overrides = _original_environment_overrides.duplicate()
	level_data.lofi_overrides = _original_lofi_overrides.duplicate()

	# Re-apply original values to the live game
	_level_play_controller.set_map_scale(_original_map_scale.x)
	_level_play_controller.apply_light_intensity_scale(_original_light_intensity)
	_level_play_controller.apply_environment_settings(
		_original_environment_preset, _original_environment_overrides
	)

	var game_map = _level_play_controller.get_game_map()
	if game_map:
		# Always reset to full defaults first, then overlay the original overrides.
		# This ensures parameters that were added during editing but weren't in the
		# original set are properly reverted back to their default values.
		game_map.apply_lofi_overrides(Constants.LOFI_DEFAULTS)
		if _original_lofi_overrides.size() > 0:
			game_map.apply_lofi_overrides(_original_lofi_overrides)


# --- Edit Panel Signal Handlers ---


## Real-time map scale change from the edit panel
func _on_edit_map_scale_changed(new_value: float) -> void:
	if _level_play_controller:
		_level_play_controller.set_map_scale(new_value)
	# Broadcast to clients so they see the same scale
	if NetworkManager.is_networked() and NetworkManager.is_host():
		NetworkManager.broadcast_map_scale(new_value)


## Real-time light intensity change from the edit panel
func _on_edit_intensity_changed(new_scale: float) -> void:
	if _level_play_controller:
		_level_play_controller.apply_light_intensity_scale(new_scale)


## Real-time environment change from the edit panel
func _on_edit_environment_changed(preset: String, overrides: Dictionary) -> void:
	if _level_play_controller:
		_level_play_controller.apply_environment_settings(preset, overrides)


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

	# Update the panel's internal state and controls to match
	level_edit_panel.apply_environment_state("", {})


## Real-time lo-fi shader change from the edit panel
func _on_edit_lofi_changed(overrides: Dictionary) -> void:
	if _level_play_controller:
		var game_map = _level_play_controller.get_game_map()
		if game_map:
			game_map.apply_lofi_overrides(overrides)


## Save all edited values to level data and persist to disk
func _on_edit_save_requested(
	new_map_scale: float,
	new_intensity: float,
	new_preset: String,
	new_overrides: Dictionary,
	new_lofi_overrides: Dictionary,
) -> void:
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	var level_data = _level_play_controller.active_level_data

	# Apply all values to level data
	level_data.map_scale = Vector3.ONE * new_map_scale
	level_data.light_intensity_scale = new_intensity
	level_data.environment_preset = new_preset
	level_data.environment_overrides = new_overrides.duplicate()
	level_data.lofi_overrides = new_lofi_overrides.duplicate()

	# Save to disk — use folder format when the level came from a folder
	var save_path := ""
	if level_data.level_folder != "":
		save_path = LevelManager.save_level_folder(level_data)
	else:
		save_path = LevelManager.save_level(level_data)
	if save_path != "":
		UIManager.show_success("Level settings saved")
	else:
		UIManager.show_error("Failed to save level settings")

	# Mark as saved so the drawer close doesn't revert
	_edit_saved = true
	level_edit_panel.close()


## Cancel editing: revert and close the drawer
func _on_edit_cancel_requested() -> void:
	_revert_edit_mode_values()
	_edit_saved = true  # Already reverted — suppress revert on close
	level_edit_panel.close()


## Open the full Level Editor overlay. The drawer stays open — the editor
## renders on a higher CanvasLayer so there is no input conflict.
func _on_open_editor_requested() -> void:
	open_editor_requested.emit()


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
