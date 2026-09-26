extends GutTest

## LevelManager with authored map documents: a level with only map.ttmap is listed, and
## duplicating a level copies whichever map files it has. Runs under a redirected
## levels_dir, like test_level_manager_cards.gd.

const TEMP_DIR := "user://test_levels_map_document/"


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


## Writes a level folder naming the given map files; each named file is written unless
## listed in `missing`.
func _write_level(folder: String, glb: bool, document: bool, missing: Array = []) -> void:
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
	var data := {
		"level_name": folder.capitalize(),
		"map_path": Paths.LEVEL_MAP_NAME if glb else "",
		"map_document": Paths.LEVEL_MAP_DOCUMENT_NAME if document else "",
		"modified_at": 100,
		"level_folder": folder,
		"token_placements": [],
	}
	_store(LevelManager.json_path(folder), JSON.stringify(data))
	if glb and not "glb" in missing:
		_store(LevelManager.map_path(folder), "glb-bytes")
	if document and not "ttmap" in missing:
		_store(LevelManager.map_document_path(folder), "ttmap-bytes")


func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _folders() -> Array:
	var folders := []
	for info in LevelManager.get_saved_levels():
		folders.append(info["folder"])
	return folders


func _copy_folder(new_path: String) -> String:
	for info in LevelManager.get_saved_levels():
		if info["path"] == new_path:
			return info["folder"]
	return ""


func test_listing_includes_document_only_glb_only_and_both() -> void:
	_write_level("authored", false, true)
	_write_level("blender", true, false)
	_write_level("dressed", true, true)
	_write_level("empty", false, false)
	var folders := _folders()
	assert_true("authored" in folders)
	assert_true("blender" in folders)
	assert_true("dressed" in folders)
	assert_false("empty" in folders)


func test_duplicate_copies_both_map_files() -> void:
	_write_level("dressed", true, true)
	var new_path := LevelManager.duplicate_level({"folder": "dressed"})
	assert_ne(new_path, "")
	var copy := _copy_folder(new_path)
	assert_ne(copy, "dressed")
	assert_eq(_read(LevelManager.map_path(copy)), "glb-bytes")
	assert_eq(_read(LevelManager.map_document_path(copy)), "ttmap-bytes")
	var level := LevelManager.load_level_folder(copy, false)
	assert_eq(level.map_path, Paths.LEVEL_MAP_NAME)
	assert_eq(level.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)


func test_duplicate_of_a_document_only_level() -> void:
	_write_level("authored", false, true)
	var copy := _copy_folder(LevelManager.duplicate_level({"folder": "authored"}))
	assert_ne(copy, "")
	assert_false(FileAccess.file_exists(LevelManager.map_path(copy)))
	assert_eq(_read(LevelManager.map_document_path(copy)), "ttmap-bytes")
	var level := LevelManager.load_level_folder(copy, false)
	assert_eq(level.map_path, "")
	assert_eq(level.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)


func test_duplicate_drops_a_named_file_that_is_missing() -> void:
	_write_level("dressed", true, true, ["glb"])
	var copy := _copy_folder(LevelManager.duplicate_level({"folder": "dressed"}))
	assert_ne(copy, "")
	var level := LevelManager.load_level_folder(copy, false)
	assert_eq(level.map_path, "")
	assert_eq(level.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)


func test_duplicate_refuses_a_level_whose_map_files_are_all_missing() -> void:
	_write_level("broken", true, true, ["glb", "ttmap"])
	assert_eq(LevelManager.duplicate_level({"folder": "broken"}), "")
	assert_eq(_folders(), ["broken"])
	assert_engine_error(1)
