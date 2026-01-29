extends Node3D

## Root scene controller - manages application state and scene transitions.

const TITLE_SCREEN_SCENE := preload("res://scenes/title_screen.tscn")

enum State {
	TITLE_SCREEN,
	PLAYING,
}

signal state_changed(old_state: State, new_state: State)

@onready var game_map: GameMap = $GameMap

var _current_state: State = State.TITLE_SCREEN
var _title_screen: CanvasLayer = null
var _level_play_controller: LevelPlayController = null


func _ready() -> void:
	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Defer connection to level play controller to ensure it's initialized
	call_deferred("_connect_level_play_controller")

	# Enter initial state
	_enter_state(_current_state)


func _connect_level_play_controller() -> void:
	# Find the map menu controller and get its level play controller
	var map_menu = game_map.get_node_or_null("MapMenu/MapMenu")
	if map_menu and map_menu.has_method("get_level_play_controller"):
		_level_play_controller = map_menu.get_level_play_controller()
		if _level_play_controller:
			_level_play_controller.level_loaded.connect(_on_level_play_loaded)
			_level_play_controller.level_cleared.connect(_on_level_cleared)


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
			pass # GameMap is always present, nothing extra needed


func _exit_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			if _title_screen:
				_title_screen.queue_free()
				_title_screen = null
		State.PLAYING:
			pass # Cleanup handled by level manager


func _on_level_loaded(_level_data: LevelData) -> void:
	_change_state(State.PLAYING)


func _on_level_play_loaded(_level_data: LevelData) -> void:
	_change_state(State.PLAYING)


func _on_level_cleared() -> void:
	_change_state(State.TITLE_SCREEN)
