extends Node3D

## Root scene controller - manages application state and scene transitions.

const TITLE_SCREEN_SCENE := preload("res://scenes/title_screen.tscn")
const APP_MENU_SCENE := preload("res://scenes/ui/app_menu.tscn")
const GAME_MAP_SCENE := preload("res://scenes/templates/game_map.tscn")

enum State {
	TITLE_SCREEN,
	PLAYING,
}

signal state_changed(old_state: State, new_state: State)

var _current_state: State = State.TITLE_SCREEN
var _title_screen: CanvasLayer = null
var _app_menu: CanvasLayer = null
var _game_map: GameMap = null
var _level_play_controller: LevelPlayController = null
var _pending_level_data: LevelData = null


func _ready() -> void:
	# Setup core systems
	_setup_level_play_controller()
	_setup_app_menu()

	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Enter initial state
	_enter_state(_current_state)


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
	_change_state(State.PLAYING)


func _change_state(new_state: State) -> void:
	if new_state == _current_state:
		return

	var old_state := _current_state

	# Exit current state
	_exit_state(_current_state)

	# Enter new state
	_current_state = new_state
	_enter_state(new_state)

	state_changed.emit(old_state, new_state)


func _enter_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			_title_screen = TITLE_SCREEN_SCENE.instantiate()
			add_child(_title_screen)
		State.PLAYING:
			_enter_playing_state()


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


func _exit_playing_state() -> void:
	# Clear the level first
	if _level_play_controller:
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	# Remove GameMap
	if _game_map:
		_game_map.queue_free()
		_game_map = null


func _on_level_loaded(_level_data: LevelData) -> void:
	_pending_level_data = _level_data
	_change_state(State.PLAYING)


func _on_level_play_loaded(_level_data: LevelData) -> void:
	# Already in PLAYING state, no need to transition
	pass


func _on_level_cleared() -> void:
	# Don't transition if we're in the middle of loading a new level
	# (play_level() calls clear_level() internally before loading)
	if _pending_level_data:
		return
	_change_state(State.TITLE_SCREEN)
