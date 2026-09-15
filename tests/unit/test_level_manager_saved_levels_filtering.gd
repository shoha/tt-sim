extends GutTest

## Regression tests for LevelManager.get_saved_levels() excluding entries that
## can never be played -- most notably the "_autosave" scratch slot written by
## level_editor_history.gd's _perform_autosave(), which deliberately skips
## LevelData.validate() so it can capture an in-progress level before a map is
## chosen (see .superpowers/sdd/autosave-load-diagnosis.md). Before the fix,
## get_saved_levels() listed such an entry like any other, and
## tests/test_play_level.gd's auto-play (newest by modified_at, no loadability
## check) could pick it, causing LevelPlayLoader to push_error("No map path in
## level data") instead of playing anything.
##
## Fixtures are written under the REAL user://levels/ directory -- the path
## get_saved_levels() scans is a hardcoded constant, not injectable -- using
## names namespaced under "_gut_fixture_" so they can never collide with a
## real save or with the real "_autosave" slot, which this test must never
## touch (it may hold the user's actual in-progress work).

const _FIXTURE_NO_MAP := "_gut_fixture_no_map"
const _FIXTURE_VALID_OLD := "_gut_fixture_valid_old"
const _FIXTURE_VALID_NEW := "_gut_fixture_valid_new"

var _fixture_folders: Array[String] = [_FIXTURE_NO_MAP, _FIXTURE_VALID_OLD, _FIXTURE_VALID_NEW]


func before_each() -> void:
	# Newest by modified_at, but unloadable -- mirrors the real "_autosave" slot.
	_write_fixture(_FIXTURE_NO_MAP, "", 3000)
	_write_fixture(_FIXTURE_VALID_OLD, "res://assets/models/maps/fixture.tscn", 1000)
	_write_fixture(_FIXTURE_VALID_NEW, "res://assets/models/maps/fixture.tscn", 2000)


func after_each() -> void:
	for folder in _fixture_folders:
		_remove_fixture(folder)


func _write_fixture(folder: String, map_path: String, modified_at: int) -> void:
	var dir_path := Paths.get_level_folder(folder)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var data := {
		"level_name": folder,
		"map_path": map_path,
		"modified_at": modified_at,
		"level_folder": folder,
		"token_placements": [],
	}
	var file := FileAccess.open(Paths.get_level_json_path(folder), FileAccess.WRITE)
	assert_not_null(file, "Failed to create fixture level.json for " + folder)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _remove_fixture(folder: String) -> void:
	var json_path := Paths.get_level_json_path(folder)
	if FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(json_path)
	DirAccess.remove_absolute(Paths.get_level_folder(folder).trim_suffix("/"))


## Filter get_saved_levels() output down to just the fixtures this test wrote,
## so assertions aren't affected by whatever real levels (or the real
## "_autosave" slot) happen to exist on this machine.
func _fixture_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for level_info in LevelManager.get_saved_levels():
		if level_info.get("folder", "") in _fixture_folders:
			result.append(level_info)
	return result


func test_entry_with_empty_map_path_is_excluded() -> void:
	var folders: Array[String] = []
	for level_info in _fixture_levels():
		folders.append(level_info.folder)
	assert_false(
		_FIXTURE_NO_MAP in folders, "Unloadable fixture (empty map_path) must not be listed"
	)


func test_entry_with_valid_map_path_is_included() -> void:
	var folders: Array[String] = []
	for level_info in _fixture_levels():
		folders.append(level_info.folder)
	assert_true(_FIXTURE_VALID_OLD in folders, "Loadable fixture must be listed")
	assert_true(_FIXTURE_VALID_NEW in folders, "Loadable fixture must be listed")


func test_newest_valid_level_sorts_first_among_valid_entries() -> void:
	# _FIXTURE_NO_MAP has the highest modified_at of the three but must never
	# be chosen -- among the entries that CAN load, the newest one
	# (_FIXTURE_VALID_NEW) must still come first.
	var fixtures := _fixture_levels()
	assert_eq(fixtures.size(), 2, "Only the two loadable fixtures should remain")
	if fixtures.size() == 2:
		assert_eq(fixtures[0].folder, _FIXTURE_VALID_NEW, "Newest loadable fixture must sort first")
		assert_eq(fixtures[1].folder, _FIXTURE_VALID_OLD)
