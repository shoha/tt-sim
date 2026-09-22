extends GutTest

## Opening a saved level from the title screen's per-card Edit action must load it INTO
## the editor without announcing it as a level to play. LevelManager.load_level() notifies
## by default, and Root._on_level_loaded turns that notification into
## change_state(State.PLAYING) -- so the default would open the editor and start playing
## the level underneath it at the same time. Regression coverage for that.

const CONTROLLER := preload("res://scenes/ui/app_menu_controller.gd")
const EDITOR_SCENE := preload("res://scenes/level_editor/level_editor.tscn")
const TEMP_DIR := "user://test_levels_editor_load/"

var _path: String = ""


func before_each() -> void:
	LevelManager.levels_dir = TEMP_DIR
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var level := LevelData.new()
	level.level_name = "Editable"
	_path = LevelManager.save_level(level)


func after_each() -> void:
	var dir := DirAccess.open(TEMP_DIR)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				LevelManager.delete_level_folder(TEMP_DIR + entry + "/")
			elif not dir.current_is_dir():
				DirAccess.remove_absolute(TEMP_DIR + entry)
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(TEMP_DIR)
	LevelManager.levels_dir = Paths.LEVELS_DIR


## Built bare rather than through its scene: _load_editor_level touches only
## _level_editor_instance and LevelManager, and staying out of the tree keeps the
## controller's @onready button lookup and _ready() network wiring out of the test.
func _controller() -> Node:
	var ctrl = CONTROLLER.new()
	var editor: LevelEditor = EDITOR_SCENE.instantiate()
	editor.check_autosave_on_ready = false
	add_child_autofree(editor)
	ctrl._level_editor_instance = editor
	return ctrl


func test_loading_a_level_for_editing_does_not_announce_it_as_played() -> void:
	var ctrl := _controller()
	watch_signals(LevelManager)

	var loaded: bool = ctrl._load_editor_level(_path)

	assert_true(loaded, "the level should load")
	assert_signal_not_emitted(LevelManager, "level_loaded")
	ctrl.free()


func test_the_named_level_reaches_the_editor() -> void:
	var ctrl := _controller()

	ctrl._load_editor_level(_path)

	assert_eq(ctrl._level_editor_instance.current_level.level_name, "Editable")
	ctrl.free()


## Empty path is the Level Editor button and the pause menu: nothing named, so the
## caller falls back to syncing with whatever is playing.
func test_an_empty_path_loads_nothing() -> void:
	var ctrl := _controller()

	assert_false(ctrl._load_editor_level(""))
	ctrl.free()
