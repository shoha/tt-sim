class_name SettlementEditor
extends RefCounted

## AuthoringEditor's settlement edits (the Street tool's "Dress this street" bar calls them
## through `AuthoringEditor.settlements`): dressing a street with a character, dressing it again
## (the next seed), changing the character, the wealth or the density, and clearing it. Every
## change is one history entry holding the settlement list before and after (records are small
## values, replaced whole), and refreshes the map's AuthoredSettlements. A live "settlements" edit
## carries the same list (LiveEditCodec). Summary: docs/systems/settlements.md.
##
## Ground (villages phases 2 and 3). A Dress, a re-dress, a change of character, `pave` and
## `add_plaza` also paint the kit's road, door paths and plaza into the map's painted surfaces
## (SettlementGround plans, SettlementPaint writes through SurfaceStroke), and the record keeps the
## strokes it laid (`Settlement.ground`). The paint and the record change are ONE history group, so
## a single undo takes back the dressing and its ground, and a peer receives the paint as ordinary
## `surface` ops and the record as a `settlements` op. A re-dress, a change of character and `pave`
## first take back the record's own strokes (SettlementUnpaint) and then lay the new plan, so the
## road follows street edits made since; Clear takes the record's strokes back with the record.
## Paint the author laid by hand is never named by the record and so is left alone. A feel change
## paints nothing.

## Why the last dress() or change made nothing (last_refusal).
const REFUSED_STREET := &"street"
const REFUSED_FULL := &"full"
const REFUSED_KIT := &"kit"
const REFUSED_INVALID := &"invalid"
const REFUSED_PLAZA := &"plaza"

var last_refusal: StringName = &""
## What the last paving did: SettlementGround.plan's result without its strokes ({} when nothing
## was planned): for the bar's note, the probes and the tests.
var last_ground: Dictionary = {}
## False dresses without painting (the A/B switch of the performance probe and of tests).
var lays_ground: bool = true
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
	return _replace(
		held,
		changed,
		"Re-dress street" if held != null else "Dress street",
		SettlementGround.PAINT_ORDER,
		null,
		held != null
	)


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
	return (
		_replace(held, changed, "Re-dress street", SettlementGround.PAINT_ORDER, null, true) > 0
	)


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
	return (
		_replace(
			held, changed, "Change village character", SettlementGround.PAINT_ORDER, null, true
		)
		> 0
	)


## Lays the road, door paths and plaza of settlement `settlement_id` (its kit's ground) as one
## history entry, after taking back the strokes it laid before: for a street dressed before the
## ground existed, or one whose road the author erased. False when it planned nothing or the
## record is unknown.
func pave(settlement_id: int) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null:
		return false
	_replace(held, held.copy(), "Pave village", SettlementGround.PAINT_ORDER, null, true)
	return not last_ground.get("roles", []).is_empty()


## Opens a plaza of `radius` metres at map XZ `at` for settlement `settlement_id`, paves it with
## the kit's plaza surface and lets the kit's plaza rules furnish it (the record keeps at most
## Settlement.MAX_PLAZAS). One history group. False (last_refusal) when the settlement is unknown,
## the disc is not allowed or the settlement holds four.
func add_plaza(settlement_id: int, at: Vector2, radius: float) -> bool:
	var held := _editor().document.settlement(settlement_id)
	last_refusal = &""
	if held == null:
		last_refusal = REFUSED_STREET
		return false
	var plaza := {
		"at": Vector2(snappedf(at.x, Settlement.PLAZA_STEP_M), snappedf(at.y, Settlement.PLAZA_STEP_M)),
		"radius": snappedf(radius, Settlement.PLAZA_STEP_M),
	}
	if held.plazas.size() >= Settlement.MAX_PLAZAS:
		last_refusal = REFUSED_FULL
		return false
	var changed := held.copy()
	changed.plazas.append(plaza)
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_PLAZA
		return false
	# Only the new disc is paved: the plan reads a copy that holds it alone.
	var only := held.copy()
	only.plazas = [plaza]
	var roles: Array[String] = ["plaza"]
	return _replace(held, changed, "Add plaza", roles, only) > 0


## Removes plaza `index` of settlement `settlement_id` with its paving (the one disc stroke the
## record lists for it, VillagePlazas.stroke_index; ground painted by hand stays) as one history
## entry. A plaza whose paving is not listed leaves the map's paint as it is.
func remove_plaza(settlement_id: int, index: int) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null or index < 0 or index >= held.plazas.size():
		return false
	var changed := held.copy()
	changed.plazas.remove_at(index)
	var paving := VillagePlazas.stroke_index(held.ground, held.plazas[index])
	return _replace(held, changed, "Remove plaza", [], null, false, PackedInt32Array([paving])) > 0


## Sets the radius of plaza `index` of settlement `settlement_id` to `radius` metres (held to a
## hundredth) as one history entry: the old paving is taken back, the new disc laid, and the kit's
## plaza rules furnish the new size. False (last_refusal) when there is no such plaza, the radius
## is outside the plaza range or it changes nothing.
func resize_plaza(settlement_id: int, index: int, radius: float) -> bool:
	var held := _editor().document.settlement(settlement_id)
	last_refusal = &""
	if held == null or index < 0 or index >= held.plazas.size():
		last_refusal = REFUSED_STREET
		return false
	var wanted := snappedf(radius, Settlement.PLAZA_STEP_M)
	if is_equal_approx(wanted, float(held.plazas[index]["radius"])):
		return false
	var changed := held.copy()
	changed.plazas[index]["radius"] = wanted
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_PLAZA
		return false
	# Only the resized disc is paved: the plan reads a copy that holds it alone.
	var only := held.copy()
	only.plazas = [changed.plazas[index]]
	var roles: Array[String] = ["plaza"]
	var paving := PackedInt32Array([VillagePlazas.stroke_index(held.ground, held.plazas[index])])
	return _replace(held, changed, "Resize plaza", roles, only, false, paving) > 0


## Lays a field of `kind` (a Settlement.FIELD_KINDS entry) and `radius` metres at map XZ `at` for
## settlement `settlement_id`: its paint (VillageFields.strokes_of) goes into the record's ground,
## its furnishings follow from the record. One history group. False (last_refusal) when the
## settlement is unknown, holds Settlement.MAX_FIELDS, or the field is not allowed.
func add_field(settlement_id: int, at: Vector2, radius: float, kind: String) -> bool:
	var held := _editor().document.settlement(settlement_id)
	last_refusal = &""
	if held == null:
		last_refusal = REFUSED_STREET
		return false
	if held.fields.size() >= Settlement.MAX_FIELDS:
		last_refusal = REFUSED_FULL
		return false
	var field := {
		"at": Vector2(snappedf(at.x, Settlement.PLAZA_STEP_M), snappedf(at.y, Settlement.PLAZA_STEP_M)),
		"radius": snappedf(radius, Settlement.PLAZA_STEP_M),
		"kind": kind,
	}
	var changed := held.copy()
	changed.fields.append(field)
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_PLAZA
		return false
	return _replace(held, changed, "Add field", ["field"], _with_fields(held, [field])) > 0


## Removes field `index` of settlement `settlement_id` with its paint (the strokes the record lists
## for it, VillageFields.stroke_indices) as one history entry.
func remove_field(settlement_id: int, index: int) -> bool:
	var held := _editor().document.settlement(settlement_id)
	if held == null or index < 0 or index >= held.fields.size():
		return false
	var changed := held.copy()
	changed.fields.remove_at(index)
	var paint := VillageFields.stroke_indices(held.ground, held.fields[index], held.seed_value)
	return _replace(held, changed, "Remove field", [], null, false, paint) > 0


## Sets the radius of field `index` of settlement `settlement_id` to `radius` metres as one history
## entry: its old paint is taken back and the new size laid. False (last_refusal) as resize_plaza.
func resize_field(settlement_id: int, index: int, radius: float) -> bool:
	var held := _editor().document.settlement(settlement_id)
	last_refusal = &""
	if held == null or index < 0 or index >= held.fields.size():
		last_refusal = REFUSED_STREET
		return false
	var wanted := snappedf(radius, Settlement.PLAZA_STEP_M)
	if is_equal_approx(wanted, float(held.fields[index]["radius"])):
		return false
	var changed := held.copy()
	changed.fields[index]["radius"] = wanted
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_PLAZA
		return false
	var paint := VillageFields.stroke_indices(held.ground, held.fields[index], held.seed_value)
	var only := _with_fields(held, [changed.fields[index]])
	return _replace(held, changed, "Resize field", ["field"], only, false, paint) > 0


## A copy of `held` holding only `fields` and no plazas: what a field edit plans its paint on.
static func _with_fields(held: Settlement, fields: Array[Dictionary]) -> Settlement:
	var only := held.copy()
	only.plazas = []
	only.fields = fields
	return only


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


## Removes settlement `settlement_id` (and with it every furnishing and the paint its Dress laid,
## SettlementUnpaint) as one history entry; ground painted by hand stays.
func clear(settlement_id: int) -> bool:
	var e := _editor()
	var doc := e.document
	var held := doc.settlement(settlement_id)
	if held == null:
		return false
	var after: Array[Settlement] = []
	for entry in doc.settlements:
		if entry.id != settlement_id:
			after.append(entry)
	last_ground = {}
	if held.ground.is_empty() or not e.can_paint():
		_change("Clear village", after, [held])
		return true
	_settle()
	e.history.begin_group()
	var began := Time.get_ticks_usec()
	last_ground["unpaved"] = SettlementPaint.unlay(e, held.ground)
	last_ground["unpaint_ms"] = (Time.get_ticks_usec() - began) / 1000.0
	_change("Clear village", after, [held])
	e.history.end_group("Clear village")
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


## Replaces `held` (null: adds) with `changed` as one history entry. `roles`
## (SettlementGround roles) also paves those roles of the kit's ground first, planned on `paved`
## (default `changed`); the paint and the record go into one history group. With `replaces`, the
## strokes `held` laid are taken back first (and the new plan replaces them in `changed.ground`);
## otherwise the new strokes are added to the ones `changed` already lists. `drops` (indices into
## `held.ground`; negatives ignored) takes back those strokes alone, and forgets them in
## `changed.ground`: a removed or resized plaza's paving or field's paint.
func _replace(
	held: Settlement,
	changed: Settlement,
	label: String,
	roles: Array[String] = [],
	paved: Settlement = null,
	replaces: bool = false,
	drops: PackedInt32Array = PackedInt32Array()
) -> int:
	var e := _editor()
	var doc := e.document
	if MapSettlementIO.settlement_problem(changed) != "":
		last_refusal = REFUSED_INVALID
		return -1
	last_ground = {}
	var dropped := PackedInt32Array()
	if held != null:
		for index in drops:
			if index >= 0 and index < held.ground.size() and not dropped.has(index):
				dropped.append(index)
	dropped.sort()
	var dropping := not dropped.is_empty()
	var laying := lays_ground and (not roles.is_empty() or dropping) and e.can_paint()
	var strokes: Array[Dictionary] = []
	if laying:
		_settle()
		e.history.begin_group()
		# The take-back and the new paving cover one street: one ground and scatter update for
		# both (released after the lay below).
		e.hold_ground()
		if replaces and held != null and not held.ground.is_empty():
			var unpaving := Time.get_ticks_usec()
			var taken := SettlementPaint.unlay(e, held.ground)
			var unpaint_ms := (Time.get_ticks_usec() - unpaving) / 1000.0
			last_ground = {"unpaved": taken, "unpaint_ms": unpaint_ms}
		elif dropping:
			var gone: Array[Dictionary] = []
			for index in dropped:
				gone.append(held.ground[index])
			last_ground = {"unpaved": SettlementPaint.unlay(e, gone)}
			for k in range(dropped.size() - 1, -1, -1):
				changed.ground.remove_at(dropped[k])
		var began := Time.get_ticks_usec()
		var planned: Dictionary = {}
		if not roles.is_empty():
			planned = _plan_ground(paved if paved != null else changed, roles)
		planned["plan_ms"] = (Time.get_ticks_usec() - began) / 1000.0
		last_ground.merge(planned, true)
		strokes.assign(last_ground.get("strokes", []))
		last_ground.erase("strokes")
		var tracked: Array[Dictionary] = []
		if not replaces:
			tracked.assign(changed.ground)
		var room := SettlementGroundIO.MAX_STROKES - tracked.size()
		if strokes.size() > room:
			strokes.resize(room)
		for stroke in strokes:
			tracked.append(SettlementGroundIO.snapped_stroke(stroke))
		changed.ground = tracked
		if MapSettlementIO.settlement_problem(changed) != "":
			changed.ground = []
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
	if not laying:
		_change(label, after, [])
		return changed.id
	var painting := Time.get_ticks_usec()
	last_ground["entries"] = SettlementPaint.lay(e, strokes)
	e.release_ground()
	last_ground["paint_ms"] = (Time.get_ticks_usec() - painting) / 1000.0
	last_ground["strokes"] = strokes.size()
	_change(label, after, [])
	e.history.end_group(label)
	return changed.id


## The strokes that pave `settlement`'s `roles` with its kit's ground: SettlementGround.plan's
## result (empty when the kit names none).
func _plan_ground(settlement: Settlement, roles: Array[String]) -> Dictionary:
	var e := _editor()
	var ground := ProcgenSettlement.ground_of(ProcgenSettlement.kit_named(settlement.kit))
	return SettlementGround.plan(
		e.document, settlement, ground, PaletteLibrary.surfaces(e.palette_root), roles
	)


## What a change finishes before it reads or writes the map: a prop edit, a stroke, height work.
func _settle() -> void:
	var e := _editor()
	e.commit_prop_edit()
	if e.is_stroking():
		e.end_stroke()
	e.finish_height_work()


func _current() -> Array[Settlement]:
	var out: Array[Settlement] = []
	out.assign(_editor().document.settlements)
	return out


## Sets the document's settlements to `after` and records it as one history entry.
func _change(label: String, after: Array[Settlement], _touched: Array[Settlement]) -> void:
	var e := _editor()
	_settle()
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
