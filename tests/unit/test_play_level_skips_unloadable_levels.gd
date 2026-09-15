extends GutTest

## Regression tests for tests/test_play_level.gd's auto-play graceful-failure
## path. Before this fix, _ready() called _play_level_at_index(0) (newest by
## modified_at) unconditionally; if that entry had no map assigned (e.g. the
## "_autosave" scratch slot -- see .superpowers/sdd/autosave-load-diagnosis.md)
## the scene sat on a bare push_error from LevelPlayLoader instead of trying
## another candidate or telling the user anything.
##
## These tests drive the real script directly (not the .tscn) with auto_play
## disabled and a hand-built _saved_levels list, so they can exercise the
## "every candidate is unloadable" path deterministically without depending on
## whatever levels actually exist on disk. The fixture used has an empty
## map_path and is loaded for real via LevelManager.load_level_folder(), so
## the guard being tested (level_data.map_path.is_empty()) runs against a real
## LevelData instance, not a mock.
##
## The "skips a bad candidate and successfully plays the next one" case is not
## covered here: a successful play instantiates the full GameMap scene and
## starts LevelPlayController's async load coroutine, which is exactly what
## the task's live validation-bridge run against test_play_level.tscn proves
## end-to-end. Reproducing that scene-instantiation weight in a headless unit
## test would just re-implement that integration test with mocks standing in
## for the thing being verified.

const _TEST_PLAY_LEVEL_SCRIPT := preload("res://tests/test_play_level.gd")
const _FIXTURE_FOLDER := "_gut_fixture_unplayable_autoplay"

var _play_level_node: Node3D = null


func before_each() -> void:
	_write_unplayable_fixture(_FIXTURE_FOLDER)

	_play_level_node = _TEST_PLAY_LEVEL_SCRIPT.new()
	_play_level_node.auto_play = false  # keep _ready() from touching real disk state
	add_child_autofree(_play_level_node)


func after_each() -> void:
	_remove_fixture(_FIXTURE_FOLDER)


func _write_unplayable_fixture(folder: String) -> void:
	var dir_path := Paths.get_level_folder(folder)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var data := {
		"level_name": folder,
		"map_path": "",
		"modified_at": 9999999,
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


func _fixture_info() -> Dictionary:
	return {
		"path": Paths.get_level_folder(_FIXTURE_FOLDER),
		"folder": _FIXTURE_FOLDER,
		"is_folder_based": true,
		"name": _FIXTURE_FOLDER,
		"description": "",
		"author": "",
		"modified_at": 9999999,
		"token_count": 0,
	}


## _saved_levels is declared Array[Dictionary] on the target script -- a plain
## array literal assigned across the object boundary is rejected at runtime as
## a type mismatch, so build a properly typed array here.
func _fixture_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = [_fixture_info()]
	return levels


## The fix under test deliberately push_warning()s when it skips an unloadable
## candidate or runs out of candidates -- that is the graceful-failure signal
## replacing the old bare push_error(). Mark it handled so GUT doesn't fail the
## test on an "unexpected" engine warning.
func _mark_expected_warnings_handled() -> void:
	for err in get_errors():
		err.handled = true


func test_play_level_at_index_returns_false_for_unloadable_entry() -> void:
	_play_level_node._saved_levels = _fixture_levels()
	var result: bool = _play_level_node._play_level_at_index(0)
	_mark_expected_warnings_handled()
	assert_false(result, "An entry with empty map_path must not report success")
	assert_null(
		_play_level_node._active_level_data,
		"Playback must not start for an entry with no map assigned"
	)


func test_auto_play_shows_message_when_every_candidate_is_unloadable() -> void:
	_play_level_node._saved_levels = _fixture_levels()
	_play_level_node._auto_play_first_valid_level()
	_mark_expected_warnings_handled()

	assert_null(_play_level_node._active_level_data, "No level should have started playing")
	assert_true(
		_play_level_node._selector_status_label.visible,
		"A status message must be shown instead of silently doing nothing"
	)
	assert_true(
		_play_level_node._selector_status_label.text.length() > 0,
		"The status message must not be blank"
	)


func test_selector_stays_visible_when_every_candidate_is_unloadable() -> void:
	_play_level_node._saved_levels = _fixture_levels()
	_play_level_node._auto_play_first_valid_level()
	_mark_expected_warnings_handled()

	assert_true(
		_play_level_node._selector_canvas.visible,
		"The selector UI must remain visible/usable, not be left in a stuck error state"
	)
