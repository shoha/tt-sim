class_name SettlementEditor
extends RefCounted

## AuthoringEditor's settlement edits (the Street tool's "Dress this street" bar calls them
## through `AuthoringEditor.settlements`): dressing a street with a character, dressing it again
## (the next seed), changing the character, the wealth or the density, and clearing it. Every
## change is one history entry holding the settlement list before and after (records are small
## values, replaced whole), and refreshes the map's AuthoredSettlements. A live "settlements" edit
## carries the same list (LiveEditCodec). Summary: docs/systems/settlements.md.

## Why the last dress() or change made nothing (last_refusal).
const REFUSED_STREET := &"street"
const REFUSED_FULL := &"full"
const REFUSED_KIT := &"kit"
const REFUSED_INVALID := &"invalid"

var last_refusal: StringName = &""
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> SettlementEditor:
	var settlements := SettlementEditor.new()
	settlements._owner = weakref(editor)
	return settlements


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## Every settlement of the document, as copies.
func list() -> Array[Settlement]:
	var out: Array[Settlement] = []
	for settlement in _editor().document.settlements:
		out.append(settlement.copy())
	return out


## A copy of the settlement dressing street `wall_id`, or null.
func of_street(wall_id: int) -> Settlement:
	var found := _editor().document.settlement_of_street(wall_id)
	return found.copy() if found != null else null


## Dresses street `wall_id` with character `kit` as one history entry: a street with no settlement
## gets one (a fresh seed drawn from the map seed and the street), one that has one takes the next
## seed ("Re-dress") and the new character. Returns the settlement's id, or -1 (last_refusal).
func dress(wall_id: int, kit: String, wealth: float = -1.0, density: float = -1.0) -> int:
	var e := _editor()
	var doc := e.document
	last_refusal = &""
	var wall := doc.wall(wall_id)
	if wall == null or not wall.is_row():
		last_refusal = REFUSED_STREET
		return -1
	if not Settlement.KIND_NAMES.has(kit):
		last_refusal = REFUSED_KIT
		return -1
	var held := doc.settlement_of_street(wall_id)
	var changed: Settlement
	if held == null:
		var settlement_id := doc.next_settlement_id()
		if settlement_id < 0:
			last_refusal = REFUSED_FULL
			return -1
		changed = Settlement.make(
			settlement_id, kit, wall_id, first_seed(doc.map_seed, wall_id, wall.seed_value)
		)
	else:
		changed = held.copy()
		changed.kit = kit
		changed.seed_value = next_seed(held.seed_value)
		changed.removed = PackedStringArray()
		changed.pinned = {}
		changed.swapped = {}
	if wealth >= 0.0:
		changed.wealth = clampf(snappedf(wealth, Settlement.WEALTH_STEP), 0.0, 1.0)
	if density >= 0.0:
		changed.density = clampf(
			snappedf(density, Settlement.WEALTH_STEP), 0.0, Settlement.MAX_DENSITY
		)
	return _replace(held, changed, "Re-dress street" if held != null else "Dress street")


## Gives settlement `settlement_id` the next seed (its overrides are dropped: they named slots
## of the old seed). False when there is none.
func redress(settlement_id: int) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null:
		return false
	var changed := held.copy()
	changed.seed_value = next_seed(held.seed_value)
	changed.removed = PackedStringArray()
	changed.pinned = {}
	changed.swapped = {}
	return _replace(held, changed, "Re-dress street") > 0


## Sets the character of settlement `settlement_id`, keeping its seed (the same street, furnished
## by another kit; its overrides are dropped).
func set_kit(settlement_id: int, kit: String) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null or not Settlement.KIND_NAMES.has(kit) or held.kit == kit:
		return false
	var changed := held.copy()
	changed.kit = kit
	changed.removed = PackedStringArray()
	changed.pinned = {}
	changed.swapped = {}
	return _replace(held, changed, "Change village character") > 0


## Sets how rich (0 shabby .. 1 wealthy) and how busy (0 sparse .. MAX_DENSITY) settlement
## `settlement_id` is. Values equal to the held ones change nothing.
func set_feel(settlement_id: int, wealth: float, density: float) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null:
		return false
	var changed := held.copy()
	changed.wealth = clampf(snappedf(wealth, Settlement.WEALTH_STEP), 0.0, 1.0)
	changed.density = clampf(snappedf(density, Settlement.WEALTH_STEP), 0.0, Settlement.MAX_DENSITY)
	if changed.wealth == held.wealth and changed.density == held.density:
		return false
	return _replace(held, changed, "Change village feel") > 0


## Removes settlement `settlement_id` (and with it every furnishing) as one history entry.
func clear(settlement_id: int) -> bool:
	var doc := _editor().document
	var held := doc.settlement(settlement_id)
	if held == null:
		return false
	var after: Array[Settlement] = []
	for entry in doc.settlements:
		if entry.id != settlement_id:
			after.append(entry)
	_change("Clear village", after, [held])
	return true


## Freezes the frontage of street `wall_id` into the settlement that dresses it, which then
## belongs to no street (source 0): the furnishings stay where they were when the street is split
## into buildings. A history entry of its own (WallEditor.split_street groups it with the split).
## False when the street has no settlement or no frontage.
func freeze_street(wall_id: int) -> bool:
	var doc := _editor().document
	var held := doc.settlement_of_street(wall_id)
	var wall := doc.wall(wall_id)
	if held == null or wall == null:
		return false
	var frozen: Array[Dictionary] = []
	# No neighbour discs: the buildings the split just made stand where the street's lots were.
	for frontage in SettlementFrontage.from_lots(wall, WallGeometry.row_lots(doc, wall)):
		frozen.append(frontage.to_dict())
	if frozen.is_empty():
		return false
	var changed := held.copy()
	changed.frozen = frozen
	changed.source = 0
	return _replace(held, changed, "Keep village furnishings") > 0


## Puts `settlements` into the document and refreshes the nodes: the undo and redo of a settlement
## edit, and a live settlements edit.
func apply_list(settlements: Array[Settlement], _area: Rect2) -> void:
	var e := _editor()
	var copied: Array[Settlement] = []
	copied.assign(settlements)
	e.document.settlements = copied
	if is_instance_valid(e.map_root):
		AuthoredSettlements.refresh_map(e.map_root, e.document)
	e.edited.emit()


## The seed a street's first dressing uses (from the map seed, the street and its seed).
static func first_seed(map_seed: int, wall_id: int, wall_seed: int) -> int:
	return absi(hash([map_seed, wall_id, wall_seed, "settlement"])) % Settlement.MAX_SEED


## The seed after `current` (a fixed step round the seed range, so a re-dress is repeatable).
static func next_seed(current: int) -> int:
	return (current * 7919 + 104729) % Settlement.MAX_SEED


func _replace(held: Settlement, changed: Settlement, label: String) -> int:
	var doc := _editor().document
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_INVALID
		return -1
	var after: Array[Settlement] = []
	var found := false
	for entry in doc.settlements:
		if held != null and entry.id == held.id:
			after.append(changed)
			found = true
		else:
			after.append(entry)
	if not found:
		after.append(changed)
	_change(label, after, [])
	return changed.id


func _current() -> Array[Settlement]:
	var out: Array[Settlement] = []
	out.assign(_editor().document.settlements)
	return out


## Sets the document's settlements to `after` and records it as one history entry.
func _change(label: String, after: Array[Settlement], _touched: Array[Settlement]) -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()
	var before := _current()
	apply_list(after, Rect2())
	(
		e
		. history
		. record(
			{
				"label": label,
				"undo": apply_list.bind(before, Rect2()),
				"redo": apply_list.bind(after, Rect2()),
				"bytes": 1024 * (before.size() + after.size()),
			}
		)
	)
