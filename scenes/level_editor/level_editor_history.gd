class_name LevelEditorHistory

## Undo/redo stack and periodic autosave for the level editor.
##
## Extracted from LevelEditor to give history management a dedicated class.
## The owner provides its current LevelData via `get_level_callback` and
## is notified of restores via `restore_callback`.

const UNDO_HISTORY_MAX := 50
const AUTOSAVE_INTERVAL := 30.0
const AUTOSAVE_DIR := "user://levels/_autosave/"
const AUTOSAVE_FILE := "user://levels/_autosave/level.json"

## Undo / redo stacks — each entry is a serialized LevelData snapshot (Dictionary)
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

## Snapshot at last manual save — used to detect dirty state for autosave
var _last_saved_snapshot: Dictionary = {}

var _autosave_timer: Timer
var _get_level: Callable        # func() -> LevelData
var _restore_level: Callable    # func(level: LevelData) -> void
var _set_status: Callable       # func(msg: String) -> void


func _init(
	owner: Node,
	get_level_callback: Callable,
	restore_level_callback: Callable,
	set_status_callback: Callable,
) -> void:
	_get_level = get_level_callback
	_restore_level = restore_level_callback
	_set_status = set_status_callback

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	owner.add_child(_autosave_timer)
	_autosave_timer.start()


# =========================================================================
# Undo / Redo
# =========================================================================


## Call BEFORE mutating the level to push the current state onto the undo stack.
## Skips saving if the snapshot is identical to the top of the stack.
func save_undo_snapshot() -> void:
	var level: LevelData = _get_level.call()
	if not level:
		return
	var snapshot := level.to_dict()
	if not _undo_stack.is_empty() and _undo_stack.back() == snapshot:
		return
	_undo_stack.append(snapshot)
	if _undo_stack.size() > UNDO_HISTORY_MAX:
		_undo_stack.pop_front()
	_redo_stack.clear()


## Restore the most recent undo snapshot.
func undo() -> void:
	var level: LevelData = _get_level.call()
	if _undo_stack.is_empty() or not level:
		return
	_redo_stack.append(level.to_dict())
	var snapshot := _undo_stack.pop_back() as Dictionary
	_restore_level.call(LevelData.from_dict(snapshot))
	_set_status.call("Undo")


## Restore the most recent redo snapshot.
func redo() -> void:
	var level: LevelData = _get_level.call()
	if _redo_stack.is_empty() or not level:
		return
	_undo_stack.append(level.to_dict())
	var snapshot := _redo_stack.pop_back() as Dictionary
	_restore_level.call(LevelData.from_dict(snapshot))
	_set_status.call("Redo")


## Clear undo/redo history (e.g. when loading a new level).
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()


# =========================================================================
# Autosave
# =========================================================================


## Record the current state as the last-saved reference point and remove
## the autosave file.
func mark_saved() -> void:
	var level: LevelData = _get_level.call()
	if level:
		_last_saved_snapshot = level.to_dict()
	_clear_autosave_file()


## Set the initial "clean" snapshot (e.g. after loading a level).
func set_saved_snapshot(snapshot: Dictionary) -> void:
	_last_saved_snapshot = snapshot


## Check for an autosave file left over from a previous session.
## Returns true if one exists.
func has_autosave() -> bool:
	return FileAccess.file_exists(AUTOSAVE_FILE)


## Try to load the autosave file and restore it via the callback.
## Returns true on success.
func recover_autosave() -> bool:
	var file := FileAccess.open(AUTOSAVE_FILE, FileAccess.READ)
	if not file:
		_set_status.call("Failed to read autosave file")
		_clear_autosave_file()
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		_set_status.call("Autosave file is corrupted")
		_clear_autosave_file()
		return false

	var level := LevelData.from_dict(json.data)
	if not level:
		_set_status.call("Failed to parse autosave data")
		_clear_autosave_file()
		return false

	_restore_level.call(level)
	clear()
	_set_status.call("Recovered autosaved level: " + level.level_name)
	_clear_autosave_file()
	return true


## Discard the autosave file without recovering.
func discard_autosave() -> void:
	_clear_autosave_file()


# =========================================================================
# Internal
# =========================================================================


func _on_autosave_timeout() -> void:
	var level: LevelData = _get_level.call()
	if not level:
		return
	var snapshot := level.to_dict()
	if snapshot == _last_saved_snapshot:
		return
	_perform_autosave(snapshot)


func _perform_autosave(snapshot: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(AUTOSAVE_DIR):
		DirAccess.make_dir_recursive_absolute(AUTOSAVE_DIR)

	var json_string := JSON.stringify(snapshot, "\t")
	var file := FileAccess.open(AUTOSAVE_FILE, FileAccess.WRITE)
	if not file:
		push_warning("LevelEditorHistory: Autosave failed — could not open file")
		return
	file.store_string(json_string)
	file.close()
	_set_status.call("Autosaved")


func _clear_autosave_file() -> void:
	if FileAccess.file_exists(AUTOSAVE_FILE):
		DirAccess.remove_absolute(AUTOSAVE_FILE)
