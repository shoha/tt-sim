class_name AuthoringHistory
extends RefCounted

## Stroke-level undo and redo for authoring mode. The drawer's undo and redo items and
## Ctrl+Z / Ctrl+Y go through here, and are disabled while there is nothing to undo or redo.
##
## This is the seam the brush tools record into. An entry is {"label": String, "undo":
## Callable, "redo": Callable}: the brush stores whatever it needs (per-chunk mask diffs,
## per the design) in the two callables' bound arguments, and they re-apply it and
## regenerate the touched chunks. The stack itself never looks inside an entry, so the
## storage format stays the brush's to choose. Every undo and redo is an edit for
## AuthoringSession (the owner marks it), so undoing back to the saved state still counts
## as unsaved.

signal changed

const MAX_ENTRIES := 100

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


## Records a done action. Clears the redo stack; drops the oldest entry past MAX_ENTRIES.
func record(entry: Dictionary) -> void:
	_undo.append(entry)
	if _undo.size() > MAX_ENTRIES:
		_undo.pop_front()
	_redo.clear()
	changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Undoes the newest entry; returns its label, or "" when there was nothing to undo.
func undo() -> String:
	if _undo.is_empty():
		return ""
	var entry: Dictionary = _undo.pop_back()
	var action: Callable = entry.get("undo", Callable())
	if action.is_valid():
		action.call()
	_redo.append(entry)
	changed.emit()
	return String(entry.get("label", ""))


## Redoes the newest undone entry; returns its label, or "" when there was nothing to redo.
func redo() -> String:
	if _redo.is_empty():
		return ""
	var entry: Dictionary = _redo.pop_back()
	var action: Callable = entry.get("redo", Callable())
	if action.is_valid():
		action.call()
	_undo.append(entry)
	changed.emit()
	return String(entry.get("label", ""))


func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
