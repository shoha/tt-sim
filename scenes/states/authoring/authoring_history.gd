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
##
## Memory. An entry may carry "bytes", the size of what its callables hold (a brush
## stroke's compressed mask diff, typically 2 to 20 KB). The oldest entries are dropped
## while the stack holds more than MAX_ENTRIES entries or more than max_bytes in total, so
## a long session of huge strokes cannot grow without bound. The newest entry always stays.
##
## Observers. recorded, undone and redone carry the entry itself, after its action has run:
## the table's live edits (LiveEdits) turn each into one op (LiveEditCodec.op_of, the before
## side for an undo) without reaching into the stacks.

signal changed
## A new entry went onto the undo stack (record()).
signal recorded(entry: Dictionary)
## `entry`'s undo has run (undo()).
signal undone(entry: Dictionary)
## `entry`'s redo has run (redo()).
signal redone(entry: Dictionary)

const MAX_ENTRIES := 100
## Default memory cap across both stacks.
const MAX_BYTES := 64 * 1024 * 1024

var max_bytes: int = MAX_BYTES

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


## Records a done action. Clears the redo stack; drops the oldest entries past MAX_ENTRIES or
## max_bytes.
func record(entry: Dictionary) -> void:
	_undo.append(entry)
	_redo.clear()
	while _undo.size() > 1 and (_undo.size() > MAX_ENTRIES or held_bytes() > max_bytes):
		_undo.pop_front()
	recorded.emit(entry)
	changed.emit()


## Bytes held by every entry that says how much it holds.
func held_bytes() -> int:
	var total := 0
	for stack in [_undo, _redo]:
		for entry in stack:
			total += int(entry.get("bytes", 0))
	return total


func undo_count() -> int:
	return _undo.size()


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
	undone.emit(entry)
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
	redone.emit(entry)
	changed.emit()
	return String(entry.get("label", ""))


func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
