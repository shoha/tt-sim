extends Control

## Controller for the GameplayMenu UI.
## Handles gameplay-specific UI: Pokemon list, save positions.
## Only active when a level is loaded.

var _level_play_controller: LevelPlayController = null

@onready var save_positions_button: Button = %SavePositionsButton
@onready var toggle_pokemon_list_button: Button = %TogglePokemonListButton


func _ready() -> void:
	# Listen for new tokens being created so we can add them to the active level
	EventBus.token_created.connect(_on_token_created)

	# Initially hide buttons since no level is loaded yet
	_update_pokemon_button_state()
	_update_save_button_visibility()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Connect to level state changes to update UI
	_level_play_controller.level_loaded.connect(_on_level_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)

	# Update UI state
	_update_pokemon_button_state()
	_update_save_button_visibility()


# --- Save Functionality ---

func _on_save_positions_button_pressed() -> void:
	_save_token_positions()


func _save_token_positions() -> void:
	if not _level_play_controller:
		return
	var path = _level_play_controller.save_token_positions()
	if path == "":
		push_error("GameplayMenuController: Failed to save level")


func _update_save_button_visibility() -> void:
	if save_positions_button:
		var should_show = _level_play_controller and _level_play_controller.has_active_level() and _level_play_controller.get_token_count() > 0
		save_positions_button.visible = should_show


# --- Level State Handling ---

func _on_level_loaded(_level_data: LevelData) -> void:
	_update_pokemon_button_state()
	_update_save_button_visibility()


func _on_level_cleared() -> void:
	_update_pokemon_button_state()
	_update_save_button_visibility()
	# Also untoggle the button if it was pressed
	if toggle_pokemon_list_button:
		toggle_pokemon_list_button.button_pressed = false


func _update_pokemon_button_state() -> void:
	if toggle_pokemon_list_button:
		var has_level = _level_play_controller and _level_play_controller.has_active_level()
		toggle_pokemon_list_button.visible = has_level


# --- Token Creation Handling ---

func _on_token_created(token: BoardToken, pokemon_number: String, is_shiny: bool) -> void:
	# Only track if we have an active level being played/edited
	if not _level_play_controller or not _level_play_controller.has_active_level():
		return

	_level_play_controller.add_token_to_level(token, pokemon_number, is_shiny)
	_update_save_button_visibility()


## Clear the current level (exposed for external use)
func clear_level() -> void:
	if _level_play_controller:
		_level_play_controller.clear_level()
	_update_save_button_visibility()
