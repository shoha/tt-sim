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
const REFUSED_UNKNOWN := &"unknown"

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


## The structure a tool lays for recipe `ref` on `plan` (map XZ, StructurePlacement's plans), seed
## `seed_value`: a record with no id yet (add() takes one), its style the biome under the plan's
## middle. Null with last_refusal set when the document is full, the recipe is not served
## (REFUSED_UNKNOWN) or the plan is not one the writer takes. Changes nothing: the tool's preview
## and what add() lays.
func lot(ref: String, plan: PackedVector2Array, seed_value: int) -> Structure:
	var doc := _editor().document
	last_refusal = &""
	if doc.next_structure_id() < 0:
		last_refusal = REFUSED_FULL
		return null
	if not LibraryStructureStore.has(ref):
		last_refusal = REFUSED_UNKNOWN
		return null
	var middle := Vector2.ZERO
	for p in plan:
		middle += p / maxf(plan.size(), 1.0)
	var structure := Structure.make(
		doc.next_structure_id(),
		ref,
		plan,
		clampi(seed_value, 0, Structure.MAX_SEED),
		{},
		CrossingPlacement.style_at(doc, middle)
	)
	if MapStructureIO.structure_problem(structure, doc.extent_m()) != "":
		last_refusal = REFUSED_INVALID
		return null
	return structure


## The id of the structure whose footprint holds world point `point`, or -1.
func structure_at(point: Vector3) -> int:
	var e := _editor()
	return StructurePlacement.structure_at(e.document, e.to_map_xz(point))


## Gives structure `structure_id` a new seed (the next one in the repeatable series) as one
## history entry: the same plan and recipe, drawn afresh. False when there is none.
func reroll(structure_id: int) -> bool:
	var doc := _editor().document
	var old := doc.structure(structure_id)
	if old == null:
		return false
	var changed := old.copy()
	changed.seed_value = next_seed(old.seed_value)
	var after: Array[Structure] = []
	for entry in doc.structures:
		after.append(changed if entry.id == structure_id else entry)
	_change("Re-roll " + _label(old), after)
	return true


## The seed after `current` (a fixed step round the seed range, so a re-roll is repeatable).
static func next_seed(current: int) -> int:
	return (current * 7919 + 104729) % Structure.MAX_SEED


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


## Lays every structure of `laid` (each with its own free id, as StreetSplit.free_ids gives) as
## one history entry labelled `label`. False, with last_refusal set and nothing changed, when
## the document would hold too many, an id is taken or repeated, or the writer would refuse one.
func lay_all(laid: Array[Structure], label: String) -> bool:
	var doc := _editor().document
	last_refusal = &""
	if laid.is_empty() or doc.structures.size() + laid.size() > MapDocument.MAX_STRUCTURES:
		last_refusal = REFUSED_FULL
		return false
	var seen := {}
	for entry in doc.structures:
		seen[entry.id] = true
	var after: Array[Structure] = _current()
	for structure in laid:
		if (
			seen.has(structure.id)
			or (MapStructureIO.structure_problem(structure, doc.extent_m()) != "")
		):
			last_refusal = REFUSED_INVALID
			return false
		seen[structure.id] = true
		after.append(structure.copy())
	_change(label, after)
	return true


## Shows `changed` (a copy of a standing structure with a new plan, say) in the document and the
## nodes without a history entry: the live look of a handle being dragged. Pair it with edit() (the
## release, which records the whole gesture from `before`, the list taken before the first
## preview) or apply_list(before, Rect2()) (a cancel). False when the document holds no such id.
func preview(changed: Structure) -> bool:
	var doc := _editor().document
	if doc.structure(changed.id) == null:
		return false
	var after: Array[Structure] = []
	for entry in doc.structures:
		after.append(changed if entry.id == changed.id else entry)
	apply_list(after, Rect2())
	return true


## Puts `changed` in place of the structure with its id as one history entry labelled `label`. With
## `before` (the list from before a preview) the entry undoes to that list. False, with
## last_refusal set, when the document has no such structure or the writer would refuse it.
func edit(changed: Structure, label: String, before: Array[Structure] = []) -> bool:
	var doc := _editor().document
	last_refusal = &""
	if doc.structure(changed.id) == null:
		last_refusal = REFUSED_UNKNOWN
		return false
	if MapStructureIO.structure_problem(changed, doc.extent_m()) != "":
		last_refusal = REFUSED_INVALID
		return false
	var base: Array[Structure] = before if not before.is_empty() else _current()
	var after: Array[Structure] = []
	for entry in base:
		after.append(changed if entry.id == changed.id else entry)
	_change(label, after, base)
	return true


## Reshapes structure `structure_id` to `plan` (a drag of a handle, a move): one history entry.
func set_plan(
	structure_id: int, plan: PackedVector2Array, label: String, before: Array[Structure] = []
) -> bool:
	var old := _editor().document.structure(structure_id)
	if old == null:
		return false
	var changed := old.copy()
	changed.footprint = plan
	return edit(changed, label + " " + _label(old), before)


## Makes edge `edge` of structure `structure_id` its front (the door side): the point order is
## rotated, so the building is otherwise the same. False when there is no such edge.
func set_front(structure_id: int, edge: int) -> bool:
	var old := _editor().document.structure(structure_id)
	if old == null or edge <= 0 or edge >= old.footprint.size():
		return false
	return set_plan(structure_id, StructureEdit.front_to(old.footprint, edge), "Door of")


## Turns structure `structure_id` about its middle by `radians`, settling on the nearest legal
## ground if the turned plan would not stand where it is. False when there is nowhere legal.
func turn(structure_id: int, radians: float) -> bool:
	var doc := _editor().document
	var old := doc.structure(structure_id)
	if old == null:
		return false
	var found := StructureEdit.move_legal(
		doc, StructureEdit.turned(old.footprint, radians), Vector2.ZERO, structure_id
	)
	if found["problem"] != "":
		return false
	return set_plan(structure_id, found["plan"], "Turn")


## Gives structure `structure_id` another recipe of its family (`ref`), keeping its plan (brought
## within the new recipe's sizes), seed and the parameters the new recipe also declares. False
## when no served library offers `ref` or the structure is gone.
func swap_recipe(structure_id: int, ref: String) -> bool:
	var doc := _editor().document
	var old := doc.structure(structure_id)
	var row := LibraryStructureStore.structure(ref)
	var recipe := StructureRecipes.document(ref)
	if old == null or row.is_empty() or recipe == null:
		return false
	if old.recipe == ref:
		return true
	var changed := old.copy()
	changed.recipe = ref
	changed.params = StructureEdit.kept_params(old.params, recipe.interface)
	changed.footprint = StructureEdit.refit(
		old.footprint, StructureBrush.scaled_row(row, _editor().map_scale())
	)
	return edit(changed, "Restyle " + _label(old))


## Steps parameter `param` of structure `structure_id` one notch (direction 1 or -1) within the
## recipe's range. False when the recipe does not declare it or it is already at its limit.
func step_param(structure_id: int, param: String, direction: int) -> bool:
	var old := _editor().document.structure(structure_id)
	var recipe := StructureRecipes.document(old.recipe) if old != null else null
	if recipe == null:
		return false
	var params := StructureEdit.stepped_params(old.params, recipe.interface, param, direction)
	if params == old.params:
		return false
	var changed := old.copy()
	changed.params = params
	return edit(changed, "Change " + param.replace("_", " ") + " of " + _label(old))


## Gives structure `structure_id` the ornaments `kinds` (StructureOrnaments; the ivy at `ivy`, or
## its own amount when negative) as one history entry labelled `label`. They ride in the record's
## params, so they save, undo, copy and sync like any parameter. False when nothing would change
## or the structure is gone.
func set_ornaments(structure_id: int, kinds: Array, label: String, ivy: float = -1.0) -> bool:
	var old := _editor().document.structure(structure_id)
	if old == null:
		return false
	var params := StructureOrnaments.with_kinds(old.params, kinds)
	if ivy >= 0.0:
		params = StructureOrnaments.with_ivy_amount(params, ivy)
	if params == old.params:
		return false
	var changed := old.copy()
	changed.params = params
	return edit(changed, label + " " + _label(old))


## Adds a copy of structure `structure_id` beside it (the same look: recipe, seed, parameters and
## style), as one history entry; its id, or -1 when there is nowhere within reach or the document
## is full.
func duplicate(structure_id: int) -> int:
	var doc := _editor().document
	var old := doc.structure(structure_id)
	last_refusal = &""
	if old == null:
		return -1
	var plan := StructureEdit.beside(doc, old)
	if plan.is_empty():
		last_refusal = REFUSED_INVALID
		return -1
	var copy := old.copy()
	copy.id = 0
	copy.footprint = plan
	return add(copy)


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
		AuthoredSettlements.refresh_map(e.map_root, e.document)
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


## Sets the document's structures to `after` and records it. `from` is the list the entry undoes
## to (the document's now when empty; a gesture that previewed passes the list before it).
func _change(label: String, after: Array[Structure], from: Array[Structure] = []) -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()
	var before: Array[Structure] = from if not from.is_empty() else _current()
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
