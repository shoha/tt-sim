class_name PauseOverlay
extends AnimatedCanvasLayerPanel

## Pause menu overlay with resume, settings, and return to title options.

signal resume_requested
signal main_menu_requested
signal change_level_requested(level_info: Dictionary)
## The host chose to return everyone to the room (Root.return_to_room)
signal room_requested

const LEVEL_PICKER_SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")

var header: MenuHeader
var resume_button: Button
var edit_level_button: Button
var change_level_button: Button
var settings_button: Button
var room_button: Button
var main_menu_button: Button
var quit_game_button: Button


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	header.setup("Paused", "Esc to resume")

	resume_button = UiActions.primary("Resume", "player-play", "", box)
	resume_button.pressed.connect(_on_resume_pressed)
	# The Level Editor and the level picker, by their player-facing names (W5).
	edit_level_button = UiActions.secondary("Open the Map editor", "wand", box)
	edit_level_button.pressed.connect(_on_edit_level_pressed)
	change_level_button = UiActions.secondary("Change map", "map", box)
	change_level_button.pressed.connect(_on_change_level_pressed)
	settings_button = UiActions.secondary("Settings", "settings", box)
	settings_button.pressed.connect(_on_settings_pressed)
	box.add_child(HSeparator.new())
	# Leaving is quiet here; the confirmation that follows carries the red.
	room_button = UiActions.secondary("Return everyone to the room", "users", box)
	room_button.set_meta("ui_silent", true)
	room_button.pressed.connect(_on_room_pressed)
	room_button.visible = NetworkManager.is_host()
	main_menu_button = UiActions.secondary("Return to title", "home", box)
	main_menu_button.set_meta("ui_silent", true)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_game_button = UiActions.secondary("Quit game", "logout", box)
	quit_game_button.set_meta("ui_silent", true)
	quit_game_button.pressed.connect(_on_quit_game_pressed)

	# Only show the Map editor and Change map for the GM / local player
	edit_level_button.visible = NetworkManager.has_gm_access()
	change_level_button.visible = NetworkManager.has_gm_access()


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children($CenterContainer/PanelContainer/VBoxContainer)


func _on_after_animate_in() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()
	# Root will handle the actual unpause via pop_state


func _on_edit_level_pressed() -> void:
	# Resume first, then open the editor via EventBus. Empty path: edit the level
	# that is currently playing, which is the only one reachable from the pause menu.
	resume_requested.emit()
	EventBus.open_editor_requested.emit("")


func _on_change_level_pressed() -> void:
	var picker: LevelPickerDialog = LEVEL_PICKER_SCENE.instantiate()
	picker.setup("Change map", LevelManager.current_level_path)
	picker.level_chosen.connect(_on_level_picked)
	get_tree().root.add_child(picker)
	# Returning to the title (or otherwise leaving the tree) while the picker
	# is still open must not strand it floating over the title screen.
	tree_exiting.connect(picker.queue_free)


func _on_level_picked(info: Dictionary) -> void:
	change_level_requested.emit(info)


func _on_settings_pressed() -> void:
	UIManager.open_settings()


## Confirm first: the table goes away for every player, and what moved on it is not kept.
func _on_room_pressed() -> void:
	UIManager.show_confirmation(
		"Return everyone to the room?",
		"The table is put away for every player. Tokens moved on it are not kept.",
		"Return to the room",
		"Cancel",
		func(): room_requested.emit(),
	)


## Confirm first (W2: the action and its consequence, on the button too); a danger dialog
## opens with Cancel focused, so Enter keeps the table.
func _on_main_menu_pressed() -> void:
	UIManager.show_confirmation(
		"Return to the title?",
		leave_consequence(NetworkManager.is_networked(), NetworkManager.is_host()),
		"Return to title",
		"Cancel",
		func(): main_menu_requested.emit(),
		Callable(),
		"Danger",
		&"leave_game",
	)


func _on_quit_game_pressed() -> void:
	UIManager.show_confirmation(
		"Quit the game?",
		leave_consequence(NetworkManager.is_networked(), NetworkManager.is_host()),
		"Quit game",
		"Cancel",
		func(): get_tree().quit(),
		Callable(),
		"Danger",
	)


## What leaving the table costs: the host's leaving ends the session for everyone, a
## player's leaves it to the others, and token moves not saved to the map are lost.
static func leave_consequence(networked: bool, host: bool) -> String:
	if networked and host:
		return "The session ends for every player. Token moves not saved to the map are lost."
	if networked:
		return "You leave the session; the others play on."
	return "Token moves not saved to the map are lost."
