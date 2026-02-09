extends Control

## Controller for the GameplayMenu UI.
## Handles gameplay-specific UI: asset browser, save positions.
## Only active when a level is loaded.
## Adding tokens and saving positions are only available to the GM, not to regular players.

var _level_play_controller: LevelPlayController = null

@onready var save_positions_button: Button = %SavePositionsButton
@onready var toggle_asset_browser_button: Button = %ToggleAssetBrowserButton
@onready var asset_browser: AssetBrowser = $AssetBrowserContainer/PanelContainer/VBox/AssetBrowser
@onready var editor_scale_panel: PanelContainer = %EditorScalePanel
@onready var map_scale_slider_spin: SliderSpinBox = %MapScaleSliderSpin
@onready var player_list_drawer: PlayerListDrawer = %PlayerListDrawer


func _ready() -> void:
	# Connect to AssetBrowser's asset_selected signal
	if asset_browser:
		asset_browser.asset_selected.connect(_on_asset_selected)

	# Connect map scale slider
	if map_scale_slider_spin:
		map_scale_slider_spin.value_changed.connect(_on_map_scale_changed)

	# Connect to network state changes to show/hide host-only buttons
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Initially hide buttons since no level is loaded yet
	_update_asset_browser_button_state()
	_update_save_button_visibility()
	_update_editor_scale_panel()
	_update_player_list_drawer()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Connect to level state changes to update UI
	_level_play_controller.level_loaded.connect(_on_level_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)
	_level_play_controller.token_added.connect(_on_token_added)

	# Update UI state
	_update_asset_browser_button_state()
	_update_save_button_visibility()


# --- Network State Handling ---


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	_update_asset_browser_button_state()
	_update_save_button_visibility()
	_update_editor_scale_panel()
	_update_player_list_drawer()


# --- Save Functionality ---


func _on_save_positions_button_pressed() -> void:
	_save_token_positions()


func _save_token_positions() -> void:
	# Only GM can save positions
	if not NetworkManager.is_gm() and NetworkManager.is_networked():
		push_warning("GameplayMenuController: Only GM can save positions")
		return

	if not _level_play_controller:
		return
	var path = _level_play_controller.save_token_positions()
	if path == "":
		push_error("GameplayMenuController: Failed to save level")


func _update_save_button_visibility() -> void:
	if save_positions_button:
		# Hide for non-GM players - only GM can save positions
		if not NetworkManager.is_gm() and NetworkManager.is_networked():
			save_positions_button.visible = false
			return
		var should_show = (
			_level_play_controller
			and _level_play_controller.has_active_level()
			and _level_play_controller.get_token_count() > 0
		)
		save_positions_button.visible = should_show


# --- Level State Handling ---


func _on_level_loaded(level_data: LevelData) -> void:
	_update_asset_browser_button_state()
	_update_save_button_visibility()
	_update_editor_scale_panel()

	# Initialize slider from level data scale
	if map_scale_slider_spin and level_data:
		map_scale_slider_spin.set_value_no_signal(level_data.map_scale.x)


func _on_level_cleared() -> void:
	_update_asset_browser_button_state()
	_update_save_button_visibility()
	_update_editor_scale_panel()
	# Also untoggle the button if it was pressed
	if toggle_asset_browser_button:
		toggle_asset_browser_button.button_pressed = false


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
		push_warning("GameplayMenuController: Only GM can add tokens")
		return

	# Spawn the asset via LevelPlayController
	if _level_play_controller:
		_level_play_controller.spawn_asset(pack_id, asset_id, variant_id)


func _on_token_added(_token: BoardToken) -> void:
	# Update save button visibility when a token is added
	_update_save_button_visibility()


## Show/hide the map scale panel.
## Visible during editor preview OR for the GM in a networked game.
func _update_editor_scale_panel() -> void:
	if not editor_scale_panel:
		return
	var has_level = _level_play_controller and _level_play_controller.has_active_level()
	var is_editor_preview = has_level and _level_play_controller.is_editor_preview
	var is_networked_gm = has_level and NetworkManager.is_networked() and NetworkManager.is_gm()
	editor_scale_panel.visible = is_editor_preview or is_networked_gm


## Handle real-time map scale changes from the slider
func _on_map_scale_changed(new_value: float) -> void:
	if _level_play_controller:
		_level_play_controller.set_map_scale(new_value)
	# Broadcast to clients so they see the same scale
	if NetworkManager.is_networked() and NetworkManager.is_host():
		NetworkManager.broadcast_map_scale(new_value)


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
	_update_save_button_visibility()
