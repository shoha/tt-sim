extends Control

## Controller for the AppMenu UI.
## Handles Level Editor button and lifecycle.
## Always visible regardless of game state.
## Level Editor is only available to the GM, not to regular players.

signal play_level_requested(level_data: LevelData)

const LevelEditorScene = preload("res://scenes/level_editor/level_editor.tscn")

@onready var _level_editor_button: Button = %LevelEditorButton

var _level_editor_instance: LevelEditor = null
var _level_play_controller: LevelPlayController = null


func _ready() -> void:
	# Connect to network state changes to show/hide level editor button
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	_update_level_editor_button_visibility()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, _new_state: NetworkManager.ConnectionState
) -> void:
	_update_level_editor_button_visibility()


## Hide the level editor button for non-GM players (only GM can edit levels)
func _update_level_editor_button_visibility() -> void:
	if _level_editor_button:
		_level_editor_button.visible = NetworkManager.is_gm() or not NetworkManager.is_networked()


# --- Level Editor Management ---


func _on_level_editor_button_pressed() -> void:
	_open_level_editor()


func _open_level_editor() -> void:
	# Only GM can access the level editor
	if not NetworkManager.is_gm() and NetworkManager.is_networked():
		push_warning("AppMenuController: Level editor is only available to the GM")
		return

	if _level_editor_instance and is_instance_valid(_level_editor_instance):
		# Sync with active level if one is playing
		_sync_editor_with_active_level()
		_level_editor_instance.animate_in()
		# Re-register in case it was unregistered
		UIManager.register_overlay(_level_editor_instance)
		return

	_level_editor_instance = LevelEditorScene.instantiate()
	_level_editor_instance.editor_closed.connect(_on_editor_closed)
	_level_editor_instance.play_level_requested.connect(_on_play_level_requested)
	add_child(_level_editor_instance)

	# Register with UIManager for ESC handling
	UIManager.register_overlay(_level_editor_instance)

	# If a level is already playing, load it into the editor
	_sync_editor_with_active_level()
	_level_editor_instance.animate_in()


func _sync_editor_with_active_level() -> void:
	if not _level_editor_instance:
		return

	if _level_play_controller and _level_play_controller.has_active_level():
		_level_editor_instance.set_level(_level_play_controller.active_level_data)
	else:
		# Just refresh token list if no active level
		_level_editor_instance._refresh_token_list()


func _on_editor_closed() -> void:
	if _level_editor_instance:
		UIManager.unregister_overlay(_level_editor_instance)
		_level_editor_instance.queue_free()
		_level_editor_instance = null


func _on_play_level_requested(level_data: LevelData) -> void:
	# Close the editor with animation
	if _level_editor_instance:
		_level_editor_instance.animate_out()

	# Mark as editor preview so gameplay UI shows scale controls
	if _level_play_controller:
		_level_play_controller.is_editor_preview = true

	# Emit signal for Root to handle
	play_level_requested.emit(level_data)
