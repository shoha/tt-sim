extends Control

## Controller for the MapMenu UI.
## Handles button presses, level editor integration, and coordinates level playback.
## Delegates level loading/management to LevelPlayController.

var _level_editor_instance: Control = null
var _level_play_controller: LevelPlayController = null

const LevelEditorScene = preload("res://scenes/level_editor/level_editor.tscn")

@onready var save_positions_button: Button = %SavePositionsButton


func _ready() -> void:
	_setup_level_play_controller()

	# Listen for new tokens being created so we can add them to the active level
	EventBus.token_created.connect(_on_token_created)


func _setup_level_play_controller() -> void:
	_level_play_controller = LevelPlayController.new()
	add_child(_level_play_controller)

	# Find and setup the game map
	var game_map = _find_game_map()
	if game_map:
		_level_play_controller.setup(game_map)
	else:
		push_warning("MapMenuController: Could not find GameMap during setup")


# --- Level Editor Management ---

func _on_level_editor_button_pressed() -> void:
	_open_level_editor()


func _open_level_editor() -> void:
	if _level_editor_instance and is_instance_valid(_level_editor_instance):
		# Refresh the token list in case tokens were added during play
		_level_editor_instance._refresh_token_list()
		_level_editor_instance.show()
		return

	_level_editor_instance = LevelEditorScene.instantiate()
	_level_editor_instance.editor_closed.connect(_on_editor_closed)
	_level_editor_instance.play_level_requested.connect(_on_play_level_requested)
	add_child(_level_editor_instance)


func _on_editor_closed() -> void:
	if _level_editor_instance:
		_level_editor_instance.queue_free()
		_level_editor_instance = null


# --- Level Playback ---

func _on_play_level_requested(level_data: LevelData) -> void:
	# Close the editor
	if _level_editor_instance:
		_level_editor_instance.hide()

	# Delegate level loading to the play controller
	if _level_play_controller.play_level(level_data):
		_update_save_button_visibility()
	else:
		push_error("MapMenuController: Failed to play level")


# --- Save Functionality ---

func _on_save_positions_button_pressed() -> void:
	_save_token_positions()


func _save_token_positions() -> void:
	var path = _level_play_controller.save_token_positions()
	if path == "":
		push_error("MapMenuController: Failed to save level")


func _update_save_button_visibility() -> void:
	if save_positions_button:
		var should_show = _level_play_controller.has_active_level() and _level_play_controller.get_token_count() > 0
		save_positions_button.visible = should_show


# --- Token Creation Handling ---

func _on_token_created(token: BoardToken, pokemon_number: String, is_shiny: bool) -> void:
	# Only track if we have an active level being played/edited
	if not _level_play_controller.has_active_level():
		return

	_level_play_controller.add_token_to_level(token, pokemon_number, is_shiny)
	_update_save_button_visibility()


# --- Utility ---

func _find_game_map() -> GameMap:
	# Navigate up to find the GameMap
	var parent = get_parent()
	while parent:
		if parent is GameMap:
			return parent
		# Check siblings
		for sibling in parent.get_children():
			if sibling is GameMap:
				return sibling
		parent = parent.get_parent()

	# Try finding by tree
	var root = get_tree().root
	return _find_game_map_recursive(root)


func _find_game_map_recursive(node: Node) -> GameMap:
	if node is GameMap:
		return node
	for child in node.get_children():
		var result = _find_game_map_recursive(child)
		if result:
			return result
	return null


## Clear the current level (exposed for external use)
func clear_level() -> void:
	_level_play_controller.clear_level()
	_update_save_button_visibility()


## Get the level play controller (for external connections)
func get_level_play_controller() -> LevelPlayController:
	return _level_play_controller
