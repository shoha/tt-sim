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
## the table's live edits (LiveEdits) turn each into ops (LiveEditCodec.ops_of, the before
## side for an undo) without reaching into the stacks.
##
## Groups. Between begin_group() and end_group() every record() goes into one group instead
## of the stack, and end_group() records them as one entry whose "parts" are those entries in
## order: its redo runs theirs in order, its undo theirs in reverse, so one Ctrl+Z takes back
## a change made of several strokes (a fire: the burnt biome, then the ash).

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
## The entries of the open group (begin_group), or null when none is open.
var _group: Variant = null


## Records a done action. Clears the redo stack; drops the oldest entries past MAX_ENTRIES or
## max_bytes. Inside a group (begin_group) it joins the group instead.
func record(entry: Dictionary) -> void:
	if _group != null:
		(_group as Array).append(entry)
		return
	_undo.append(entry)
	_redo.clear()
	while _undo.size() > 1 and (_undo.size() > MAX_ENTRIES or held_bytes() > max_bytes):
		_undo.pop_front()
	recorded.emit(entry)
	changed.emit()


## Opens a group: the entries recorded until end_group() become one (see the header).
func begin_group() -> void:
	_group = []


## Closes the group and records its entries as one entry labelled `label`, {"label", "undo",
## "redo", "parts", "bytes"}, which it returns; a group with nothing in it records nothing
## and returns {}.
func end_group(label: String) -> Dictionary:
	var parts: Array = _group if _group != null else []
	_group = null
	if parts.is_empty():
		return {}
	var held := 0
	for part: Dictionary in parts:
		held += int(part.get("bytes", 0))
	var entry := {
		"label": label,
		"undo": run_parts.bind(parts, false),
		"redo": run_parts.bind(parts, true),
		"parts": parts,
		"bytes": held,
	}
	record(entry)
	return entry


## Runs the redo of every entry of `parts` in order (`redo`), or their undo in reverse.
static func run_parts(parts: Array, redo: bool) -> void:
	var ordered := parts.duplicate()
	if not redo:
		ordered.reverse()
	for part: Dictionary in ordered:
		var action: Callable = part.get("redo" if redo else "undo", Callable())
		if action.is_valid():
			action.call()


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


## True when `entry` is the one undo() would take back next (an undo toast's entry is undone
## only while nothing newer stands on it).
func is_newest(entry: Dictionary) -> bool:
	return not _undo.is_empty() and is_same(_undo.back(), entry)


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
