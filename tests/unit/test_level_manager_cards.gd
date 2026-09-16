extends GutTest

## LevelManager card support: level info carries thumbnail and preset, thumbnails
## save at 320x180, rename keeps the folder, duplicate copies map and thumbnail.
## Everything runs under a redirected levels_dir so real saves are never touched.

const TEMP_DIR := "user://test_levels/"


func before_each() -> void:
	LevelManager.levels_dir = TEMP_DIR
	_remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)


func after_each() -> void:
	_remove_tree(TEMP_DIR)
	LevelManager.levels_dir = Paths.LEVELS_DIR
	LevelManager.current_level = null
	LevelManager.current_level_path = ""


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child + "/")
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_level(folder: String, name: String, preset: String, modified_at: int) -> void:
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
	var data := {
		"level_name": name,
		"map_path": "map.glb",
		"modified_at": modified_at,
		"level_folder": folder,
		"environment_preset": preset,
		"token_placements": [{"asset_id": "a"}],
	}
	var file := FileAccess.open(LevelManager.json_path(folder), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var map := FileAccess.open(LevelManager.map_path(folder), FileAccess.WRITE)
	map.store_string("glb-bytes")
	map.close()


func _info(folder: String) -> Dictionary:
	for info in LevelManager.get_saved_levels():
		if info["folder"] == folder:
			return info
	return {}


func test_level_info_carries_preset_and_empty_thumbnail() -> void:
	_write_level("clearing", "Sandy Clearing", "outdoor_day", 100)
	var info := _info("clearing")
	assert_eq(info["environment_preset"], "outdoor_day")
	assert_eq(info["thumbnail"], "")
	assert_eq(info["token_count"], 1)


func test_save_thumbnail_writes_320x180_and_info_reports_it() -> void:
	_write_level("clearing", "Sandy Clearing", "outdoor_day", 100)
	var level := LevelManager.load_level_folder("clearing", false)
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	assert_true(LevelManager.save_thumbnail(level, image))
	var path := LevelManager.thumbnail_path("clearing")
	assert_true(FileAccess.file_exists(path))
	var saved := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_eq(saved.get_width(), 320)
	assert_eq(saved.get_height(), 180)
	assert_eq(_info("clearing")["thumbnail"], path)


func test_save_thumbnail_refuses_a_level_without_a_folder() -> void:
	var level := LevelData.new()
	assert_false(LevelManager.save_thumbnail(level, Image.create(2, 2, false, Image.FORMAT_RGB8)))
	assert_engine_error(1)


func test_rename_keeps_the_folder_and_changes_the_name() -> void:
	_write_level("clearing", "Sandy Clearing", "outdoor_day", 100)
	assert_true(LevelManager.rename_level(_info("clearing"), "Dusty Hollow"))
	var info := _info("clearing")
	assert_eq(info["name"], "Dusty Hollow")
	assert_eq(info["folder"], "clearing")
	assert_true(FileAccess.file_exists(LevelManager.map_path("clearing")))


func test_rename_of_a_legacy_tres_level_removes_the_old_file() -> void:
	var level := LevelData.new()
	level.level_name = "Old Camp"
	level.level_folder = ""
	level.map_path = "res://map.glb"
	var old_path := LevelManager.save_level(level)
	assert_true(FileAccess.file_exists(old_path))
	var info := _info_by_name("Old Camp")
	assert_true(LevelManager.rename_level(info, "New Camp"))
	var levels := LevelManager.get_saved_levels()
	assert_eq(levels.size(), 1)
	assert_eq(levels[0]["name"], "New Camp")
	assert_false(FileAccess.file_exists(old_path))


func _info_by_name(name: String) -> Dictionary:
	for info in LevelManager.get_saved_levels():
		if info["name"] == name:
			return info
	return {}


func test_rename_and_duplicate_do_not_move_the_current_level() -> void:
	_write_level("clearing", "Sandy Clearing", "outdoor_day", 100)
	LevelManager.current_level_path = "user://elsewhere/"
	LevelManager.current_level = null
	assert_true(LevelManager.rename_level(_info("clearing"), "Dusty Hollow"))
	assert_eq(LevelManager.current_level_path, "user://elsewhere/")
	assert_null(LevelManager.current_level)
	LevelManager.current_level_path = "user://elsewhere/"
	LevelManager.current_level = null
	assert_ne(LevelManager.duplicate_level(_info("clearing")), "")
	assert_eq(LevelManager.current_level_path, "user://elsewhere/")
	assert_null(LevelManager.current_level)


func test_duplicate_copies_map_and_thumbnail_into_a_new_folder() -> void:
	_write_level("clearing", "Sandy Clearing", "outdoor_day", 100)
	var level := LevelManager.load_level_folder("clearing", false)
	LevelManager.save_thumbnail(level, Image.create(4, 4, false, Image.FORMAT_RGB8))
	var new_path := LevelManager.duplicate_level(_info("clearing"))
	assert_ne(new_path, "")
	var levels := LevelManager.get_saved_levels()
	assert_eq(levels.size(), 2)
	var copy: Dictionary = {}
	for info in levels:
		if info["path"] == new_path:
			copy = info
	assert_eq(copy["name"], "Sandy Clearing (Copy)")
	assert_ne(copy["folder"], "clearing")
	assert_true(FileAccess.file_exists(LevelManager.map_path(copy["folder"])))
	assert_true(FileAccess.file_exists(LevelManager.thumbnail_path(copy["folder"])))
	assert_eq(copy["thumbnail"], LevelManager.thumbnail_path(copy["folder"]))
