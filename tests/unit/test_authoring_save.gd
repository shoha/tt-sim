extends GutTest

## Authoring's disk side: saving a map into a level folder (AuthoringController.write_level),
## the autosave slot and its recovery (AuthoringAutosave), and LevelManager never listing
## the autosave slot. Everything writes under a temp levels directory.

const TEMP_DIR := "user://test_authoring_save/"


func before_each() -> void:
	LevelManager.levels_dir = TEMP_DIR
	AuthoringAutosave.directory = TEMP_DIR + "_autosave/"
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)


func after_each() -> void:
	_remove_tree(TEMP_DIR)
	LevelManager.levels_dir = Paths.LEVELS_DIR
	AuthoringAutosave.directory = Paths.LEVELS_DIR + "_autosave/"


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub) + "/")
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path.trim_suffix("/"))


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 11)
	doc.scatter = {"a/Rock": PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])}
	return doc


func test_a_new_map_saves_into_a_new_folder_with_document_level_and_thumbnail() -> void:
	var level := AuthoringController.new_level()
	level.level_name = "Glade Test"
	var image := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	assert_true(AuthoringController.write_level(level, _doc(), image))
	assert_eq(level.level_folder, "glade_test")
	assert_eq(level.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	assert_true(FileAccess.file_exists(LevelManager.map_document_path("glade_test")))
	assert_true(FileAccess.file_exists(LevelManager.thumbnail_path("glade_test")))
	var read := MapDocumentIO.read(LevelManager.map_document_path("glade_test"))
	assert_not_null(read["document"])
	assert_eq(read["document"].scatter.keys(), ["a/Rock"])
	var listed := LevelManager.get_saved_levels()
	assert_eq(listed.size(), 1, "a document-only level is listed")
	assert_eq(listed[0]["name"], "Glade Test")
	assert_ne(listed[0]["thumbnail"], "")


func test_saving_again_keeps_the_folder() -> void:
	var level := AuthoringController.new_level()
	assert_true(AuthoringController.write_level(level, _doc(), null))
	var folder := level.level_folder
	level.level_name = "Renamed"
	assert_true(AuthoringController.write_level(level, _doc(), null))
	assert_eq(level.level_folder, folder, "the folder name never changes")
	assert_eq(LevelManager.get_saved_levels().size(), 1)


func test_a_dressed_glb_level_gains_its_document_on_first_save() -> void:
	var level := LevelData.new()
	level.level_name = "River"
	level.level_folder = "river"
	level.map_path = Paths.LEVEL_MAP_NAME
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path("river"))
	var doc := NewMap.create_dressing(AABB(Vector3(-5, 0, -5), Vector3(10, 1, 10)), 2)
	assert_true(AuthoringController.write_level(level, doc, null))
	assert_eq(level.map_path, Paths.LEVEL_MAP_NAME, "the GLB stays the base")
	assert_eq(level.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	var read: MapDocument = MapDocumentIO.read(LevelManager.map_document_path("river"))["document"]
	assert_true(read.has_base_map)


func test_an_unwritable_document_leaves_a_new_level_folderless() -> void:
	var level := AuthoringController.new_level()
	var broken := _doc()
	broken.heights = PackedFloat32Array()
	assert_false(AuthoringController.write_level(level, broken, null))
	assert_eq(level.level_folder, "")
	assert_eq(level.map_document, "")
	assert_false(DirAccess.dir_exists_absolute(LevelManager.folder_path("untitled_map")))
	assert_engine_error(1)


func test_autosave_round_trip_and_discard() -> void:
	assert_false(AuthoringAutosave.exists())
	var level := AuthoringController.new_level()
	level.level_name = "Half Done"
	assert_eq(AuthoringAutosave.write(_doc(), level), OK)
	assert_true(AuthoringAutosave.exists())
	var recovered := AuthoringAutosave.read_level()
	assert_eq(recovered.level_name, "Half Done")
	assert_eq(recovered.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	var read: MapDocument = MapDocumentIO.read(AuthoringAutosave.document_path())["document"]
	assert_eq(read.map_seed, 11)
	AuthoringAutosave.discard()
	assert_false(AuthoringAutosave.exists())


func test_autosave_slot_is_never_listed_even_with_a_map() -> void:
	var level := AuthoringController.new_level()
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	assert_eq(AuthoringAutosave.write(_doc(), level), OK)
	# The Level Editor's own autosave file in the same slot, naming a map.
	var file := FileAccess.open(AuthoringAutosave.directory + "level.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"level_name": "Editor", "map_document": "map.ttmap"}))
	file.close()
	assert_eq(LevelManager.get_saved_levels(), [])


func test_a_corrupt_autosave_level_reads_as_none() -> void:
	DirAccess.make_dir_recursive_absolute(AuthoringAutosave.directory)
	var file := FileAccess.open(AuthoringAutosave.level_path(), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	assert_null(AuthoringAutosave.read_level())
