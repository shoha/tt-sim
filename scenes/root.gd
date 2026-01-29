extends Node3D

## Root scene controller - manages application state and scene transitions.
##
## Uses a state stack to support overlay states (like PAUSED on top of PLAYING).
## - change_state(): Replaces entire stack with a new base state
## - push_state(): Adds overlay state on top of current state
## - pop_state(): Removes top overlay state, returning to previous

const TITLE_SCREEN_SCENE := preload("res://scenes/title_screen.tscn")
const APP_MENU_SCENE := preload("res://scenes/ui/app_menu.tscn")
const GAME_MAP_SCENE := preload("res://scenes/templates/game_map.tscn")
const PAUSE_OVERLAY_SCENE := preload("res://scenes/ui/pause_overlay.tscn")

enum State {
	TITLE_SCREEN,
	PLAYING,
	PAUSED,
}

signal state_changed(old_state: State, new_state: State)

var _state_stack: Array[State] = []
var _title_screen: CanvasLayer = null
var _app_menu: CanvasLayer = null
var _game_map: GameMap = null
var _pause_overlay: CanvasLayer = null
var _level_play_controller: LevelPlayController = null
var _pending_level_data: LevelData = null


func _ready() -> void:
	# Setup core systems
	_setup_level_play_controller()
	_setup_app_menu()

	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Enter initial state
	push_state(State.TITLE_SCREEN)


func _setup_level_play_controller() -> void:
	_level_play_controller = LevelPlayController.new()
	add_child(_level_play_controller)
	_level_play_controller.level_loaded.connect(_on_level_play_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)


func _setup_app_menu() -> void:
	_app_menu = APP_MENU_SCENE.instantiate()
	add_child(_app_menu)

	# Get the controller and set it up
	var app_menu_controller = _app_menu.get_node("AppMenu")
	if app_menu_controller:
		app_menu_controller.setup(_level_play_controller)
		app_menu_controller.play_level_requested.connect(_on_play_level_requested)


func _on_play_level_requested(level_data: LevelData) -> void:
	# Store level data and transition to PLAYING state
	_pending_level_data = level_data
	change_state(State.PLAYING)


## Get the current (topmost) state
func get_current_state() -> State:
	if _state_stack.size() > 0:
		return _state_stack[-1]
	return State.TITLE_SCREEN


## Push a new state onto the stack (for overlay states like PAUSED)
func push_state(state: State) -> void:
	var old_state := get_current_state()
	_state_stack.push_back(state)
	_enter_state(state)
	state_changed.emit(old_state, state)


## Pop the top state from the stack (returns to previous state)
func pop_state() -> void:
	if _state_stack.size() <= 1:
		return # Don't pop the last state
	var old_state: State = _state_stack.pop_back()
	_exit_state(old_state)
	state_changed.emit(old_state, get_current_state())


## Replace the entire state stack with a new base state
func change_state(new_state: State) -> void:
	var old_state := get_current_state()
	if new_state == old_state and _state_stack.size() == 1:
		return

	# Exit all current states (top to bottom)
	while _state_stack.size() > 0:
		var state_to_exit: State = _state_stack.pop_back()
		_exit_state(state_to_exit)

	# Push the new base state
	_state_stack.push_back(new_state)
	_enter_state(new_state)

	state_changed.emit(old_state, new_state)


func _enter_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			_title_screen = TITLE_SCREEN_SCENE.instantiate()
			add_child(_title_screen)
		State.PLAYING:
			_enter_playing_state()
		State.PAUSED:
			_enter_paused_state()


func _enter_playing_state() -> void:
	# Instantiate GameMap
	_game_map = GAME_MAP_SCENE.instantiate()
	add_child(_game_map)

	# Setup bidirectional references between LevelPlayController and GameMap
	_level_play_controller.setup(_game_map)
	_game_map.setup(_level_play_controller)

	# Load the pending level if we have one
	if _pending_level_data:
		if not _level_play_controller.play_level(_pending_level_data):
			push_error("Root: Failed to play level")
		_pending_level_data = null


func _exit_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			if _title_screen:
				_title_screen.queue_free()
				_title_screen = null
		State.PLAYING:
			_exit_playing_state()
		State.PAUSED:
			_exit_paused_state()


func _exit_playing_state() -> void:
	# Clear the level first
	if _level_play_controller:
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	# Remove GameMap
	if _game_map:
		_game_map.queue_free()
		_game_map = null


func _enter_paused_state() -> void:
	# Pause the game tree (physics, _process, etc.)
	get_tree().paused = true
	
	# Show pause overlay
	_pause_overlay = PAUSE_OVERLAY_SCENE.instantiate()
	add_child(_pause_overlay)
	
	# Connect pause overlay signals
	if _pause_overlay.has_signal("resume_requested"):
		_pause_overlay.resume_requested.connect(_on_pause_resume_requested)
	if _pause_overlay.has_signal("main_menu_requested"):
		_pause_overlay.main_menu_requested.connect(_on_pause_main_menu_requested)


func _on_pause_resume_requested() -> void:
	pop_state()


func _on_pause_main_menu_requested() -> void:
	# First unpause, then return to title
	get_tree().paused = false
	change_state(State.TITLE_SCREEN)


func _exit_paused_state() -> void:
	# Hide pause overlay
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null
	
	# Resume the game tree
	get_tree().paused = false


func _on_level_loaded(_level_data: LevelData) -> void:
	_pending_level_data = _level_data
	change_state(State.PLAYING)


func _on_level_play_loaded(_level_data: LevelData) -> void:
	# Already in PLAYING state, no need to transition
	pass


func _on_level_cleared() -> void:
	# Don't transition if we're in the middle of loading a new level
	# (play_level() calls clear_level() internally before loading)
	if _pending_level_data:
		return
	change_state(State.TITLE_SCREEN)
