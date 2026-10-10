extends GutTest

## LevelData's map_document field and map_hashes: a level can have map.glb, map.ttmap, or
## both. Round trips, validate() for each combination, untrusted-input handling of the two
## fields, and duplicate_level().
##
## validate() resolves files through Paths.LEVELS_DIR (the GUT run's own test data root), so
## the fixture folder below is created there and removed after each test.

const FOLDER := "_gut_t4_map_document"
const HASH_A := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))


func after_each() -> void:
	for path in [Paths.get_level_map_path(FOLDER), Paths.get_level_map_document_path(FOLDER)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(Paths.get_level_folder(FOLDER).trim_suffix("/"))


func _touch(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("bytes")
	file.close()


func _level(glb: bool, document: bool) -> LevelData:
	var level := LevelData.new()
	level.level_name = "Fixture"
	level.level_folder = FOLDER
	level.map_path = Paths.LEVEL_MAP_NAME if glb else ""
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME if document else ""
	return level


func _round_trip(level: LevelData) -> LevelData:
	return LevelData.from_dict(JSON.parse_string(JSON.stringify(level.to_dict())))


func test_round_trip_glb_only() -> void:
	var back := _round_trip(_level(true, false))
	assert_eq(back.map_path, Paths.LEVEL_MAP_NAME)
	assert_eq(back.map_document, "")
	assert_true(back.has_map())


func test_round_trip_document_only() -> void:
	var back := _round_trip(_level(false, true))
	assert_eq(back.map_path, "")
	assert_eq(back.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	assert_true(back.has_map())


func test_round_trip_both() -> void:
	var back := _round_trip(_level(true, true))
	assert_eq(back.map_path, Paths.LEVEL_MAP_NAME)
	assert_eq(back.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)


func test_old_level_without_the_field_loads_with_no_document() -> void:
	var data := _level(true, false).to_dict()
	data.erase("map_document")
	var back := LevelData.from_dict(data)
	assert_eq(back.map_document, "")
	assert_eq(back.format_version, LevelData.FORMAT_VERSION)


func test_unexpected_document_names_are_refused() -> void:
	for bad in ["../../secrets.ttmap", "map.glb", "x/map.ttmap", 7, ["map.ttmap"]]:
		var data := _level(true, false).to_dict()
		data["map_document"] = bad
		assert_eq(LevelData.from_dict(data).map_document, "", "refused: %s" % str(bad))
	assert_engine_error(5)


func test_validate_glb_only() -> void:
	var level := _level(true, false)
	assert_eq(level.validate(), ["Map file does not exist: " + Paths.get_level_map_path(FOLDER)])
	_touch(Paths.get_level_map_path(FOLDER))
	assert_eq(level.validate(), [])


func test_validate_document_only() -> void:
	var level := _level(false, true)
	var document_path := Paths.get_level_map_document_path(FOLDER)
	assert_eq(level.validate(), ["Map document does not exist: " + document_path])
	_touch(document_path)
	assert_eq(level.validate(), [])


func test_validate_both_needs_both_files() -> void:
	var level := _level(true, true)
	_touch(Paths.get_level_map_path(FOLDER))
	assert_eq(level.validate().size(), 1)
	_touch(Paths.get_level_map_document_path(FOLDER))
	assert_eq(level.validate(), [])


func test_validate_neither_is_an_error() -> void:
	var level := _level(false, false)
	assert_true("Map file is required" in level.validate())
	assert_false(level.has_map())


func test_document_path_needs_a_folder() -> void:
	var level := _level(false, true)
	assert_eq(level.get_absolute_map_document_path(), Paths.get_level_map_document_path(FOLDER))
	level.level_folder = ""
	assert_eq(level.get_absolute_map_document_path(), "")
	assert_eq(level.validate().size(), 1)


func test_duplicate_keeps_the_document() -> void:
	var copy := _level(true, true).duplicate_level()
	assert_eq(copy.map_document, Paths.LEVEL_MAP_DOCUMENT_NAME)
	assert_eq(copy.level_folder, "")


func test_hashes_are_not_written_when_empty() -> void:
	assert_false(_level(true, true).to_dict().has(MapFileHash.HASHES_KEY))


func test_hashes_round_trip_and_malformed_ones_are_dropped() -> void:
	var data := _level(true, true).to_dict()
	data[MapFileHash.HASHES_KEY] = {
		"map": HASH_A,
		"ttmap": HASH_A.to_upper(),
		"../level.json": HASH_A,
	}
	var back := LevelData.from_dict(data)
	assert_eq(back.map_hashes, {"map": HASH_A})
	assert_eq(back.to_dict()[MapFileHash.HASHES_KEY], {"map": HASH_A})
	data[MapFileHash.HASHES_KEY] = "not a dictionary"
	assert_eq(LevelData.from_dict(data).map_hashes, {})
