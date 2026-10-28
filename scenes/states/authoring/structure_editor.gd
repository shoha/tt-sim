class_name StructureEditor
extends RefCounted

## AuthoringEditor's structure edits (reached as `AuthoringEditor.structures`): adding and removing
## structure records and putting a whole list into the document, each change one history entry
## holding the list before and after (structures are small values, replaced whole, never edited in
## place), as WallEditor does for walls. apply_list() is the one method the history's undo and
## redo and a live structures edit call: it sets the document's list, brings the map's
## AuthoredStructures up to it (a changed structure builds on a worker and appears when ready) and
## asks the scatter to regrow where a footprint changed. follow() and restore() make the nodes
## follow a sculpt or water edit of the ground under them. Frames: document (map XZ metres).
## Summary: docs/systems/structures.md.

## An edit reaches structures whose footprint comes within this of its area (metres).
const FOLLOW_REACH_M := 1.0

## Why the last add() made nothing (last_refusal).
const REFUSED_FULL := &"full"
const REFUSED_INVALID := &"invalid"

## Why the last add() made nothing, or &"".
var last_refusal: StringName = &""

## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> StructureEditor:
	var structures := StructureEditor.new()
	structures._owner = weakref(editor)
	return structures


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## Every structure of the document, as copies (in document order).
func list() -> Array[Structure]:
	var out: Array[Structure] = []
	for structure in _editor().document.structures:
		out.append(structure.copy())
	return out


## A copy of structure `structure_id`, or null.
func get_structure(structure_id: int) -> Structure:
	var found := _editor().document.structure(structure_id)
	return found.copy() if found != null else null


## Lays `structure` as one history entry: a structure whose id the document holds replaces it,
## any other is added under a free id. Returns its id, or -1 when the document is full or the
## writer would refuse it (last_refusal).
func add(structure: Structure) -> int:
	var doc := _editor().document
	last_refusal = &""
	var existing := doc.structure(structure.id)
	var laid := structure.copy()
	if existing == null:
		var structure_id := doc.next_structure_id()
		if structure_id < 0:
			last_refusal = REFUSED_FULL
			return -1
		laid.id = structure_id
	if MapStructureIO.structure_problem(laid, doc.extent_m()) != "":
		last_refusal = REFUSED_INVALID
		return -1
	var after: Array[Structure] = []
	for entry in doc.structures:
		after.append(laid if entry.id == laid.id else entry)
	if existing == null:
		after.append(laid)
	_change(("Change " if existing != null else "Place ") + _label(laid), after)
	return laid.id


## Removes structure `structure_id` as one history entry. False when there is none.
func remove(structure_id: int) -> bool:
	var doc := _editor().document
	var old := doc.structure(structure_id)
	if old == null:
		return false
	var after: Array[Structure] = []
	for entry in doc.structures:
		if entry.id != structure_id:
			after.append(entry)
	_change("Remove " + _label(old), after)
	return true


## Refreshes the structures near an edit of the ground or water over `area` (map XZ; an empty
## rectangle: everywhere), without a history entry of its own: AuthoredStructures rebuilds the
## structures whose ground changed. Returns what the edit's entry needs to refresh them again on
## undo and redo ({"area": area}), or {} when the edit reached no structure.
func follow(area: Rect2) -> Dictionary:
	for structure in _editor().document.structures:
		if (
			not area.has_area()
			or StructureGeometry.clear_bounds(structure).grow(FOLLOW_REACH_M).intersects(area)
		):
			apply_list(_current(), Rect2())
			return {"area": area}
	return {}


## Refreshes the structures again after an edit's undo or redo put its ground back (a follow()
## record). {} does nothing.
func restore(record: Dictionary, _redo: bool) -> void:
	if record.is_empty():
		return
	apply_list(_current(), Rect2())


## Puts `structures` into the document and refreshes the nodes (and the scatter over `area`, map
## XZ): the undo and redo of a structure edit, and a live structures edit.
func apply_list(structures: Array[Structure], area: Rect2) -> void:
	var e := _editor()
	var copied: Array[Structure] = []
	copied.assign(structures)
	e.document.structures = copied
	if is_instance_valid(e.map_root):
		AuthoredStructures.refresh_map(e.map_root, e.document)
	if is_instance_valid(e.scatter) and area.has_area():
		e.scatter.request_region(area)


## The area a change from `before` to `after` reaches: the footprints (grown) of every structure
## that was added, removed or changed.
static func _area_of(before: Array[Structure], after: Array[Structure]) -> Rect2:
	var area := Rect2()
	var kept := {}
	for structure in before:
		kept[structure.id] = structure
	var touched: Array[Structure] = []
	for structure in after:
		var old: Structure = kept.get(structure.id)
		if old == null or not old.same_as(structure):
			touched.append(structure)
			if old != null:
				touched.append(old)
		kept.erase(structure.id)
	touched.append_array(kept.values())
	for structure in touched:
		var bounds := StructureGeometry.clear_bounds(structure)
		area = bounds if not area.has_area() else area.merge(bounds)
	return area


## The document's structures as a new list of the same objects.
func _current() -> Array[Structure]:
	var out: Array[Structure] = []
	out.assign(_editor().document.structures)
	return out


## Sets the document's structures to `after` and records it.
func _change(label: String, after: Array[Structure]) -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()
	var before := _current()
	var area := _area_of(before, after)
	apply_list(after, area)
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": apply_list.bind(before, area),
				"redo": apply_list.bind(after, area),
				"bytes": 1024 * (before.size() + after.size()),
			}
		)
	)
	e.edited.emit()


static func _label(structure: Structure) -> String:
	return "structure " + structure.recipe.get_slice(":", 1)
