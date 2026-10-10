class_name PauseOverlay
extends AnimatedCanvasLayerPanel

## Pause menu overlay with resume, settings, and return to title options.
##
## Leaving the table (Return to title, Quit game) asks first, and the question names the
## action as its button does (W2). What leaving costs depends on the role and on the tokens:
## the host's leaving ends the session for everyone, and token moves not yet saved to the map
## are lost, which is said only when there are some (tokens_unsaved). A confirm that loses
## something is a danger confirm with Cancel focused and, when this player can save
## (save_map), offers Save first beside it. Return everyone to the room asks nothing here: it
## is a table move (TableMover), which asks only when the table changed and keeps the
## changes for the session by default, and its notice's Stay here undoes it. There is no
## Change map: the table moves to another map from the room drawer (Tab).

signal resume_requested
signal main_menu_requested
## The host chose to return everyone to the room (Root.return_to_room)
signal room_requested

## The cost of leaving with unsaved token moves, shown only when there are some.
const TOKENS_LOST := "Token moves you have not saved to the map will be lost."
## The leave confirm's save offer: save the tokens to the map, then leave.
const SAVE_FIRST := "Save first"

## Returns whether the table's tokens differ from the map as saved; Root sets it
## (LevelPlayController.has_unsaved_tokens). Unset, there are none.
var tokens_unsaved: Callable = Callable()
## Saves the table's tokens to the map and returns whether that worked (it toasts either
## way); Root sets it for a player who can save. Unset, leaving offers no save.
var save_map: Callable = Callable()

var header: MenuHeader
var resume_button: Button
var edit_level_button: Button
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
	# The Level Editor by its player-facing name (W5), the title's own words for it, here
	# acting on the map on the table.
	edit_level_button = UiActions.secondary(
		TitleScreen.SET_UP_TOKENS, TitleScreen.SET_UP_TOKENS_ICON, box
	)
	edit_level_button.pressed.connect(_on_edit_level_pressed)
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
	quit_game_button = UiActions.secondary(TitleScreen.QUIT, TitleScreen.QUIT_ICON, box)
	quit_game_button.set_meta("ui_silent", true)
	quit_game_button.pressed.connect(_on_quit_game_pressed)

	# Only show Set up tokens for the GM / local player
	edit_level_button.visible = NetworkManager.has_gm_access()


## Leaving reads the tokens on `table` (Root passes it as the menu opens): it names lost
## token moves only when there are some, and offers to save them to a player who can.
func watch_table(table: LevelPlayController) -> void:
	tokens_unsaved = table.has_unsaved_tokens
	if not NetworkManager.is_restricted_client():
		save_map = _save_table.bind(table)


## Save the table's tokens to its map as the play HUD's Save map does, and say so. Returns
## whether it saved, so a failed save keeps the table.
func _save_table(table: LevelPlayController) -> bool:
	var saved := not table.save_level_with_thumbnail().is_empty()
	if saved:
		UIManager.show_success("Map saved")
	else:
		UIManager.show_error(
			preload("res://scenes/states/playing/gameplay_menu_controller.gd").SAVE_ERROR
		)
	return saved


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


func _on_settings_pressed() -> void:
	UIManager.open_settings()


## A table move to the room (Root.return_to_room, TableMover): it asks only when the table
## changed, and its notice can be called off.
func _on_room_pressed() -> void:
	room_requested.emit()


## Confirm first (W2: the action and its consequence, on the button too).
func _on_main_menu_pressed() -> void:
	_confirm_leaving(
		"Return to title?",
		_leave_message(),
		"Return to title",
		_leaving_loses_work(),
		func() -> void: main_menu_requested.emit(),
		&"leave_game",
	)


func _on_quit_game_pressed() -> void:
	_confirm_leaving(
		"Quit game?",
		_leave_message(),
		"Quit game",
		_leaving_loses_work(),
		func() -> void: get_tree().quit(),
		&"confirm",
	)


## Ask before leaving by `action`. A leave that loses something is a danger confirm (Cancel
## focused, so Enter keeps the table); with unsaved token moves and a way to save, the
## dialog also offers Save first, which saves and then leaves, and stays when the save
## fails (short, so three buttons fit the 420 sheet).
func _confirm_leaving(
	title: String,
	message: String,
	action: String,
	loses_work: bool,
	leave: Callable,
	sound: StringName,
) -> Node:
	var dialog: Node = UIManager.show_confirmation(
		title,
		message,
		action,
		"Cancel",
		leave,
		Callable(),
		"Danger" if loses_work else "Primary",
		sound,
	)
	if _unsaved() and save_map.is_valid():
		dialog.add_alternate_action(SAVE_FIRST, _save_then.bind(leave))
	return dialog


func _save_then(leave: Callable) -> void:
	if bool(save_map.call()):
		leave.call()


func _unsaved() -> bool:
	return tokens_unsaved.is_valid() and bool(tokens_unsaved.call())


## Whether leaving the table loses something: the session for everyone (the host), or
## token moves this player could have saved.
func _leaving_loses_work() -> bool:
	var networked := NetworkManager.is_networked()
	if networked and NetworkManager.is_host():
		return true
	return not networked and _unsaved()


func _leave_message() -> String:
	var networked := NetworkManager.is_networked()
	var host := NetworkManager.is_host()
	return leave_consequence(networked, host, (host or not networked) and _unsaved())


## What leaving the table costs: the host's leaving ends the session for everyone, a
## player's leaves it to the others, and token moves not saved to the map are lost, said
## only when `unsaved`.
static func leave_consequence(networked: bool, host: bool, unsaved: bool) -> String:
	if networked and not host:
		return "You leave the session; the others play on."
	var lines: Array[String] = []
	if networked:
		lines.append("The session ends for every player.")
	lines.append(TOKENS_LOST if unsaved else "Your tokens are saved to the map.")
	return " ".join(lines)
