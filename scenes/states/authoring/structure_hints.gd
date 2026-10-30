class_name StructureHints
extends RefCounted

## The Structure tool's keys on the hint bar (InputHints key caps): one cap and a few words per
## gesture, fading as the player does each gesture once. "Done once" is remembered per user in
## the settings file (UiPreferences, the [ui] section), so the bar thins out for good and a
## newcomer's first minutes keep every cap. The rows are pure (done list in, rows out) so tests
## call them directly; StructureBrush.gesture_done says when a gesture was done and
## StructureTool.key_hints turns it into the rows. docs/systems/structures.md "The tool".

## The gestures with a lot following the pointer, in the order the bar shows them: {"id", "key",
## "action"}. The cap is the key or mouse button, the action two or three words.
const PLACING: Array[Dictionary] = [
	{"id": &"click", "key": "Click", "action": "Put it down"},
	{"id": &"drag", "key": "Drag", "action": "Size it"},
	{"id": &"turn", "key": "Q / E", "action": "Turn it"},
	{"id": &"again", "key": "R", "action": "Draw it afresh"},
	{"id": &"remove", "key": "Del", "action": "Remove one"},
]
## The gestures with a building selected.
const SELECTED: Array[Dictionary] = [
	{"id": &"edit", "key": "Drag", "action": "Move or resize"},
	{"id": &"turn", "key": "Q / E", "action": "Turn it"},
	{"id": &"again", "key": "R", "action": "Draw it afresh"},
	{"id": &"copy", "key": "Ctrl+D", "action": "Copy it"},
	{"id": &"remove", "key": "Del", "action": "Remove it"},
	{"id": &"esc", "key": "Esc", "action": "Let go"},
]

## The gestures done once, as the settings file has them (read once, kept here).
static var _done: Array[String] = []
static var _loaded: bool = false


## The hint rows ({"key", "action"}) for the gestures not yet in `done`, for a lot following the
## pointer or, with `selected`, for a selected building. Pure.
static func rows(done: Array, selected: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gesture: Dictionary in SELECTED if selected else PLACING:
		if not done.has(String(gesture["id"])):
			out.append({"key": gesture["key"], "action": gesture["action"]})
	return out


## `done` with gesture `id` added (a new array; the same ids twice count once). Pure.
static func marked(done: Array, id: StringName) -> Array[String]:
	var out: Array[String] = []
	out.assign(done)
	if not out.has(String(id)):
		out.append(String(id))
	return out


## How many of the `selected` or placing gestures are done, as {"done", "total"}. Pure.
static func progress(done: Array, selected: bool) -> Dictionary:
	var total := 0
	var count := 0
	for gesture: Dictionary in SELECTED if selected else PLACING:
		total += 1
		if done.has(String(gesture["id"])):
			count += 1
	return {"done": count, "total": total}


## The gestures this user has done once (loaded from the settings file on first use).
static func done() -> Array[String]:
	if not _loaded:
		_loaded = true
		_done = UiPreferences.load_structure_hints_done()
	return _done


## Records gesture `id` as done, saving it when it is new. True when it was new.
static func mark(id: StringName) -> bool:
	if done().has(String(id)):
		return false
	_done = marked(_done, id)
	UiPreferences.save_structure_hints_done(_done)
	return true


## Forgets the cache (a test pointing UiPreferences at another file; "show the hints again").
static func reset(forget_saved: bool = false) -> void:
	_loaded = false
	_done = []
	if forget_saved:
		UiPreferences.save_structure_hints_done(_done)
