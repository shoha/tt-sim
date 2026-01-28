extends Node3D

## Root scene controller - manages placeholder display until a level is loaded.

@onready var title_screen: CanvasLayer = $TitleScreen
@onready var game_map: GameMap = $GameMap

var _level_play_controller: LevelPlayController = null


func _ready() -> void:
	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Defer connection to level play controller to ensure it's initialized
	call_deferred("_connect_level_play_controller")

	# Show placeholder initially
	_show_placeholder(true)


func _connect_level_play_controller() -> void:
	# Find the map menu controller and get its level play controller
	var map_menu = game_map.get_node_or_null("MapMenu/MapMenu")
	if map_menu and map_menu.has_method("get_level_play_controller"):
		_level_play_controller = map_menu.get_level_play_controller()
		if _level_play_controller:
			_level_play_controller.level_loaded.connect(_on_level_play_loaded)
			_level_play_controller.level_cleared.connect(_on_level_cleared)


func _on_level_loaded(_level_data: LevelData) -> void:
	_show_placeholder(false)


func _on_level_play_loaded(_level_data: LevelData) -> void:
	_show_placeholder(false)


func _on_level_cleared() -> void:
	_show_placeholder(true)


func _show_placeholder(should_show: bool) -> void:
	if title_screen:
		title_screen.visible = should_show
