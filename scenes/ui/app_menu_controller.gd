extends Control

## Controller for the AppMenu UI.
## Handles Level Editor button and lifecycle.
## The title hub has its own Level Editor action, so this floating button only
## appears in states that call show_editor_button() (currently none — kept for
## the editor's own flows) and is hidden during gameplay, where the edit drawer
## provides a "Level Details..." button instead.
## Level Editor is only available to the GM, not to regular players.

signal play_level_requested(level_data: LevelData)

const LevelEditorScene = preload("res://scenes/level_editor/level_editor.tscn")

var _level_editor_instance: LevelEditor = null
var _editor_canvas_layer: CanvasLayer = null
var _level_play_controller: LevelPlayController = null
var _force_hide_button: bool = false

@onready var _level_editor_button: Button = %LevelEditorButton


func _ready() -> void:
	# Connect to network state changes to show/hide level editor button
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	_update_level_editor_button_visibility()


func _exit_tree() -> void:
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState,
	_new_state: NetworkManager.ConnectionState,
) -> void:
	_update_level_editor_button_visibility()


## Hide the level editor button for non-GM players (only GM can edit levels).
## Also hidden when _force_hide_button is true (during gameplay).
func _update_level_editor_button_visibility() -> void:
	if _level_editor_button:
		if _force_hide_button:
			_level_editor_button.visible = false
			return
		_level_editor_button.visible = NetworkManager.has_gm_access()


## Show the Level Editor button (for title screen / non-gameplay states).
func show_editor_button() -> void:
	_force_hide_button = false
	_update_level_editor_button_visibility()


## Hide the Level Editor button (during gameplay, the edit drawer is used instead).
func hide_editor_button() -> void:
	_force_hide_button = true
	_update_level_editor_button_visibility()


# --- Level Editor Management ---


func _on_level_editor_button_pressed() -> void:
	open_level_editor()


## Open the level editor overlay.
## Called from the button press or externally (e.g. from the edit drawer via Root).
##
## `level_path` names a saved level to edit, as the title screen's per-card Edit action
## does. Empty (the default) keeps the original behaviour: edit whichever level is
## currently playing, if any.
func open_level_editor(level_path: String = "") -> void:
	# Only GM can access the level editor
	if NetworkManager.is_restricted_client():
		push_warning("AppMenuController: Level editor is only available to the GM")
		return

	if _level_editor_instance and is_instance_valid(_level_editor_instance):
		if not _load_editor_level(level_path):
			# Sync with active level if one is playing
			_sync_editor_with_active_level()
		_level_editor_instance.animate_in()
		# Re-register in case it was unregistered
		UIManager.register_overlay(_level_editor_instance)
		return

	# Create a dedicated CanvasLayer so the editor renders above gameplay UI
	if not _editor_canvas_layer:
		_editor_canvas_layer = CanvasLayer.new()
		_editor_canvas_layer.layer = Constants.LAYER_LEVEL_EDITOR
		add_child(_editor_canvas_layer)

	_level_editor_instance = LevelEditorScene.instantiate()
	_level_editor_instance.editor_closed.connect(_on_editor_closed)
	_level_editor_instance.play_level_requested.connect(_on_play_level_requested)
	_editor_canvas_layer.add_child(_level_editor_instance)

	# Register with UIManager for ESC handling
	UIManager.register_overlay(_level_editor_instance)

	# A named level wins; otherwise fall back to whatever is playing.
	if not _load_editor_level(level_path):
		_sync_editor_with_active_level()
	_level_editor_instance.animate_in()


## Load a named saved level into the editor. Returns false when there is nothing to
## load (no path given, or the level could not be read) so the caller can fall back to
## the active-level sync rather than opening the editor on nothing.
func _load_editor_level(level_path: String) -> bool:
	if level_path.is_empty() or not _level_editor_instance:
		return false
	# notify = false: LevelManager.level_loaded is what Root._on_level_loaded turns into
	# change_state(State.PLAYING). Editing a level is not playing it, so this load must
	# stay silent or the editor opens with the level starting up underneath it.
	var level_data := LevelManager.load_level(level_path, false)
	if level_data == null:
		UIManager.show_error("Could not open that level for editing")
		return false
	_level_editor_instance.set_level(level_data)
	return true


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
