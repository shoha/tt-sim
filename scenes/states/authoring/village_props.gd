class_name VillageProps
extends RefCounted

## The furnishing half of the Village tool's brush (VillageBrush owns one): which standing piece
## the pointer is over, which is picked, and the gestures that edit it (docs/systems/villages.md
## section 14). Hover a piece and it is outlined; click picks it; drag moves it and the release
## pins it where it is put (refused over water, a steep bank, a house, a bridge or another piece);
## Q and E turn it, R shows another draw of it (both pin it); Swap cycles the props that belong in
## that kind of place; Delete or Remove takes it away; Put back lets a pinned piece go back to its
## rule. The
## record is SettlementEditor's (remove_furnishing, pin_furnishing, swap_furnishing,
## unpin_furnishing, restore_furnishings: one history entry each), the rules VillageFurnishings'. A
## piece is found by its slot name, so it stays picked through the rebuilds an edit causes.

## A press on a piece, not yet dragged; and dragged past a click's distance.
const GESTURE_PICK := &"prop_pick"
const GESTURE_MOVE := &"prop_move"
## The words beside the cursor.
const HOVER := "Drag to move this piece, click to pick it"
const HOVER_FIELD := "Click to pick this piece, Delete removes it"
const HOVER_PICKED := "Drag to move it, Q and E turn it, Delete removes it"
const MOVE_HINT := "Release to put it here"

## False leaves every piece untouchable: the plaza and field tests of the older slices, whose
## coordinates were chosen on bare ground, set it so a stall there does not take the press.
static var touchable: bool = true

## The picked piece (a village and a slot name), the one under the pointer, and the held gesture.
var village: int = -1
var slot: String = ""
var hover_village: int = -1
var hover_slot: String = ""
var gesture: StringName = &""

var _pad_m: float = 0.0
var _press_at: Vector2 = Vector2.ZERO
var _offset: Vector2 = Vector2.ZERO
var _dest: Vector2 = Vector2.ZERO
var _reason: StringName = &""
var _plans: Array[PackedVector2Array] = []
var _rows: Array[Dictionary] = []
var _info: Dictionary = {}


## The layer that stands the furnishings of `editor`'s map, or null.
static func layer_of(editor: AuthoringEditor) -> AuthoredSettlements:
	if editor == null or not is_instance_valid(editor.map_root):
		return null
	return editor.map_root.get_node_or_null(AuthoredSettlements.NODE_NAME) as AuthoredSettlements


## The standing pieces of village `id` ({"item", "y", ...} rows).
static func rows_of(editor: AuthoringEditor, id: int) -> Array[Dictionary]:
	var layer := layer_of(editor)
	return layer.standing(id) if layer != null else ([] as Array[Dictionary])


## Whether a piece is picked, or under the pointer.
func has_picked() -> bool:
	return slot != ""


func has_hover() -> bool:
	return hover_slot != ""


## The picked piece's placement ({} when none stands), or village `id`'s piece `piece`.
func item(editor: AuthoringEditor, id: int = -2, piece: String = "") -> Dictionary:
	var want_village := village if id == -2 else id
	var want_slot := slot if piece == "" else piece
	for row in rows_of(editor, want_village):
		if str(row["item"]["slot"]) == want_slot:
			return row["item"]
	return {}


## Where the held move would put the piece (map XZ), the reason that place is refused (&"" none),
## and whether a move is held.
func destination() -> Vector2:
	return _dest


func refusal() -> StringName:
	return _reason if gesture == GESTURE_MOVE else &""


func moving() -> bool:
	return gesture == GESTURE_MOVE


## Lets go of the picked piece (not a held gesture).
func drop() -> void:
	village = -1
	slot = ""
	_info = {}


## Lets go of everything: the pick, the hover and a held gesture.
func clear() -> void:
	reset()
	drop()
	hover_village = -1
	hover_slot = ""


## Drops a held gesture.
func reset() -> void:
	gesture = &""
	_reason = &""
	_plans = []
	_rows = []


## Finds the piece under map point `p` (`pad_m` metres of extra reach from the camera) among every
## village's standing pieces. Sets hover_village and hover_slot, or clears them.
func hover(editor: AuthoringEditor, p: Vector2, pad_m: float = 0.0) -> void:
	_pad_m = pad_m
	var all: Array[Dictionary] = []
	if not touchable:
		hover_village = -1
		hover_slot = ""
		return
	for settlement in editor.document.settlements:
		for row in rows_of(editor, settlement.id):
			if VillageFurnishings.is_centre_piece(settlement.kit, str(row["item"]["slot"])):
				continue
			all.append({"item": row["item"], "village": settlement.id})
	var found := VillageFurnishings.pick(all, p, pad_m)
	hover_village = int(found.get("village", -1))
	hover_slot = str(found["item"]["slot"]) if not found.is_empty() else ""


## A press at map point `p`: picks the piece under it and starts the gesture. False over none.
func press(editor: AuthoringEditor, p: Vector2) -> bool:
	hover(editor, p, _pad_m)
	if hover_slot == "":
		return false
	village = hover_village
	slot = hover_slot
	var held := item(editor)
	if held.is_empty():
		drop()
		return false
	gesture = GESTURE_PICK
	_press_at = p
	_offset = (held["position"] as Vector2) - p
	_dest = held["position"]
	_reason = &""
	return true


## Follows the pointer to map point `p` while a gesture is held: a press dragged past a click's
## distance on a movable piece becomes a move, and the place it would go is judged each time it
## changes.
func track(editor: AuthoringEditor, p: Vector2) -> void:
	var held := item(editor)
	if held.is_empty():
		reset()
		return
	var field := VillageFurnishings.is_field_piece(slot)
	if gesture == GESTURE_PICK and not field and VillagePlazas.is_move(_press_at, p):
		gesture = GESTURE_MOVE
		_plans = VillageFieldGround.footprints(editor.document)
		_rows = rows_of(editor, village)
	if gesture != GESTURE_MOVE:
		return
	var at := VillagePlazas.moved_to(p, _offset)
	if at.is_equal_approx(_dest):
		return
	_dest = at
	if at.is_equal_approx(held["position"]):
		_reason = &""
		return
	_reason = VillageFurnishings.problem(
		editor.document,
		village,
		_rows,
		slot,
		str(held["prop"]),
		float(held["scale"]),
		at,
		_plans
	)


## The release: a move pins the piece at its new place unless that place is refused. Returns the
## words of a refusal to toast, or "".
func end(editor: AuthoringEditor) -> String:
	var message := ""
	if gesture == GESTURE_MOVE:
		var held := item(editor)
		if _reason != &"":
			message = VillageFurnishings.reason_text(_reason)
		elif not held.is_empty() and not _dest.is_equal_approx(held["position"]):
			var moved := held.duplicate()
			moved["position"] = _dest
			message = _pin(editor, village, slot, SettlementPlan.pin_of(moved))
	reset()
	return message


# --- the edits (one history entry each; a returned string is a refusal's words) ---------------


## The piece an edit acts on: a key acts on the one under the pointer, else the picked one; a pane
## button (`hovered_first` false) on the picked one.
func _target(hovered_first: bool = true) -> Array:
	if hovered_first and hover_slot != "":
		return [hover_village, hover_slot]
	if slot != "":
		return [village, slot]
	return [hover_village, hover_slot]


## Takes the target piece away (Delete, the pane's Remove).
func remove(editor: AuthoringEditor, hovered_first: bool = true) -> String:
	var target := _target(hovered_first)
	if str(target[1]) == "":
		return ""
	if editor.settlements.remove_furnishing(int(target[0]), str(target[1])):
		if int(target[0]) == village and str(target[1]) == slot:
			drop()
		hover_slot = ""
		hover_village = -1
		return ""
	return VillageFurnishings.reason_text(editor.settlements.last_refusal)


## Turns the target piece `steps` notches (a notch is 15 degrees), pinning it.
func turn(editor: AuthoringEditor, steps: int) -> String:
	var target := _target()
	var held := item(editor, int(target[0]), str(target[1]))
	if held.is_empty() or VillageFurnishings.is_field_piece(str(held["slot"])):
		return ""
	var turned := held.duplicate()
	turned["yaw"] = float(held["yaw"]) + steps * VillageFurnishings.TURN_STEP
	return _pin(editor, int(target[0]), str(held["slot"]), SettlementPlan.pin_of(turned))


## Shows the target piece as another draw (the next of ProcgenSettlement.VARIANTS), pinning it.
func reroll(editor: AuthoringEditor) -> String:
	var target := _target()
	var held := item(editor, int(target[0]), str(target[1]))
	if held.is_empty() or VillageFurnishings.is_field_piece(str(held["slot"])):
		return ""
	var drawn := held.duplicate()
	drawn["seed"] = (int(held["seed"]) + 1) % ProcgenSettlement.VARIANTS
	return _pin(editor, int(target[0]), str(held["slot"]), SettlementPlan.pin_of(drawn))


## Swaps the picked piece for the next prop that belongs in that kind of place and fits where it
## stands (the pane's Swap).
func swap(editor: AuthoringEditor) -> String:
	var held := item(editor)
	var settlement := editor.document.settlement(village)
	if held.is_empty() or settlement == null:
		return ""
	var choices := VillageFurnishings.swap_choices(settlement.kit, held)
	var rows := rows_of(editor, village)
	var plans := VillageFieldGround.footprints(editor.document)
	var fits := func(prop: String) -> bool:
		return (
			VillageFurnishings.problem(
				editor.document,
				village,
				rows,
				slot,
				prop,
				float(held["scale"]),
				held["position"],
				plans
			)
			== &""
		)
	var prop := VillageFurnishings.next_choice(choices, str(held["prop"]), fits)
	if prop == "":
		return "Nothing else fits here."
	if editor.settlements.swap_furnishing(village, slot, prop):
		return ""
	return VillageFurnishings.reason_text(editor.settlements.last_refusal)


## Lets the picked pinned piece go back to where its rule puts it (the pane's Put back).
func unpin(editor: AuthoringEditor) -> void:
	if slot != "":
		editor.settlements.unpin_furnishing(village, slot)


## Puts every removed piece of village `id` back.
func restore(editor: AuthoringEditor, id: int) -> void:
	editor.settlements.restore_furnishings(id)


func _pin(editor: AuthoringEditor, id: int, piece: String, pin: Dictionary) -> String:
	if editor.settlements.pin_furnishing(id, piece, pin):
		return ""
	return VillageFurnishings.reason_text(editor.settlements.last_refusal)


# --- state kept in step with the document -----------------------------------------------------


## Lets go of a pick an undo or an edit took away, and refreshes what the pane shows of the picked
## piece. Called every frame by VillageBrush.
func sync(editor: AuthoringEditor) -> void:
	if slot == "":
		_info = {}
		return
	var held := item(editor)
	if held.is_empty():
		if gesture == &"":
			drop()
		return
	var settlement := editor.document.settlement(village)
	var choices: Array[String] = []
	if settlement != null:
		choices = VillageFurnishings.swap_choices(settlement.kit, held)
	_info = {
		"label": VillageFurnishings.label_of(str(held["prop"])),
		"pinned": bool(held["pinned"]),
		"field": VillageFurnishings.is_field_piece(slot),
		"swappable": choices.size() > 1,
	}


## What the pane shows of the furnishings of village `id` of `doc`: {"picked", "label", "pinned",
## "field", "swappable", "removed" (how many pieces the village has had taken away)}.
func pane_state(doc: MapDocument, id: int) -> Dictionary:
	var held := doc.settlement(id) if id > 0 else null
	var out := {
		"picked": slot != "" and not _info.is_empty() and village == id,
		"label": str(_info.get("label", "")),
		"pinned": bool(_info.get("pinned", false)),
		"field": bool(_info.get("field", false)),
		"swappable": bool(_info.get("swappable", false)),
		"removed": held.removed.size() if held != null else 0,
	}
	return out


## A short string that changes when the pick, the hover or the pane's view of the piece changes.
func signature() -> String:
	return "%d|%s|%s|%s" % [village, slot, str(gesture), var_to_str(_info)]
