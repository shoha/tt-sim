class_name StructureBrush
extends BrushMode

## The Structure tool's mode (StructureTool): the ghost lot that follows the pointer, a click
## that drops it, a drag that sizes it, Q and E that turn it, R that re-rolls it, and the removal
## of the structure under the pointer. BrushTool routes the tool's press, frames, release and
## cancel to it (the BrushMode hooks below); what a lot may stand on and the plans it takes are
## StructurePlacement's rules, the edit is StructureEditor's (`AuthoringEditor.structures`).
##
## Gesture. With a structure picked (`ref`), the pointer carries a ghost lot at the recipe's
## default size: its footprint on the ground, the door marked on its front, its height as a ring
## over it. The ghost eases to the nearest legal spot (not on water, not on a steep bank, not on
## another building) instead of turning red, and slides there rather than jumping. A click lays
## it. A press and drag sizes it instead: the press is one corner, the pointer the opposite one,
## and the size clamps to the recipe's range (the ghost shows the clamp). The release lays the
## lot as one history entry. Q and E turn the lot 15 degrees (Shift a quarter), R draws the next
## lot's look afresh (or the structure under the pointer), RMB or Delete over a structure
## removes it, Ctrl and a click does too, and RMB or Escape during a drag drops it.
##
## A lot that fits nowhere within StructurePlacement.REACH_M says why in plain words beside the
## cursor; a release then lays nothing and says the same as a toast.
##
## Selection (card S5). A click on a building selects it (a tint and outline, a dot at each corner
## and a tab beside each side: StructureEdit's handles); Escape, the bar's Done, or another tool
## lets it go (the pick stays armed). Placing flows on over a selection (place_flow): the ghost
## still follows over bare ground, a click there lays a lot and selects it, a drag from bare ground
## sizes one, and over a building or a handle the ghost steps aside. A drag on the selection then
## carries out one gesture, each a single history entry: on a corner dot, resize (the plan keeps
## its square corners; Shift moves just that point); on a side tab, push that side out or in, and a
## plain click on it makes that side the front, where the door goes; on the building's body, move
## it (it settles on the nearest legal ground). The result is clamped, never refused: the sides
## keep to the recipe's range, the plan to ProcgenPlan's rules, the ground to the lot rules, and a
## stopped handle goes warm with a thin line to where the pointer is asking. The building itself
## follows the drag about ten times a second (StructureEditor.preview), the outline at once;
## Escape or a right click drops the drag, back to the plan it began with. Q and E turn the
## selected building, R draws it afresh, Ctrl+D copies it beside itself, Delete over it removes it.
## The pane (StructureToolPane) shows the variants, a floors stepper and the rest for the
## selection (`selection_changed`).

## The selection changed: the selected structure's id, or -1 for none.
signal selection_changed(structure_id: int)
## A gesture was done: its id in StructureHints (&"click", &"drag", &"turn", &"again", &"remove",
## &"edit", &"copy", &"esc"). The hint bar fades the key of one the player has done once.
signal gesture_done(id: StringName)

const YAW_STEP := deg_to_rad(15.0)
## A handle is picked within this many pixels of its dot, and a press that moves the pointer less
## than CLICK_PX pixels is a click on it.
const PICK_PX := 20.0
const CLICK_PX := 6.0
## The pick radius (document metres) when no camera can say how big a pixel is.
const PICK_FALLBACK_M := 0.6
## A dragged building is built again about this often (seconds).
const PREVIEW_S := 0.1
## The selection's tint, and the warm tint of a handle that has been stopped.
const SELECT_TINT := Color(1.0, 0.93, 0.62)
const CUE_TINT := Color(1.0, 0.72, 0.42)
const HANDLE_RADIUS := 6.5
## Plain words for the few hints and refusals of the selection.
const DOOR_HINT := "Click: door here. Drag: push this side."
const NO_TURN_TEXT := "There is no room to turn it here."
const NO_COPY_TEXT := "There is no room beside it for a copy."
## A press and release moving the pointer less than this (world metres) is a click.
const DRAG_MIN_M := 0.75
## The pointer's ground point moves this far (metres) before a drag's lot is planned again.
const REPLAN_M := 0.08
## A bracket key makes the size a click lays this much bigger or smaller (multiplicative, like the
## brush size), within SIZE_SCALE_RANGE of the recipe's default.
const SIZE_STEP := 1.1
const SIZE_SCALE_RANGE := Vector2(0.6, 2.5)
## The ghost slides to its target at this rate (per second, exponential).
const EASE_RATE := 22.0
## The door mark is this wide on the front edge (world metres); the footprint fill alpha.
const DOOR_MARK_M := 1.0
const FOOTPRINT_ALPHA := 0.3
## The ghost's edges are sampled this far apart along the ground (metres).
const LINE_STEP_M := 0.5
const FADE_M := 2.5
## Plain-words reasons a lot cannot be laid.
const WATER_TEXT := "Not on the water. Move onto dry ground."
const STEEP_TEXT := "That ground is too steep to build on."
const OFF_MAP_TEXT :="Keep the building on the map."
const OCCUPIED_TEXT := "There is a building here already."
const FULL_TEXT := "The map holds as many buildings as it can. Remove one to make room."
const UNKNOWN_TEXT := "That building is not in a library this map has."
const INVALID_TEXT := "A building cannot stand there."
const NOTHING := "There is no building here to remove."
const NONE_PICKED := "Pick a building to place."

## The structure picked (`<library>:<id>`), "" before one is. Changing it drops the plan of a lot
## being sized and the ghost's remembered spot.
var ref: String = "":
	set(value):
		ref = value
		_planned_to = Vector3.INF
		_wanted = {}
		preview = null
## The turn of the next lot (radians from the map X axis; Q and E), and the size a click lays as
## a multiple of the recipe's default (the bracket keys).
var yaw: float = 0.0
var size_scale: float = 1.0
## The seed the next lot is drawn with (R; each lot laid takes the next one).
var seed_value: int = 4242
## A lot being sized: its first corner and the pointer's last ground point (world).
var drawing: bool = false
var from: Vector3 = Vector3.INF
var to: Vector3 = Vector3.INF
## The structure the drag would lay (map frame; null when no spot), and why not.
var preview: Structure = null
var refusal: String = ""
## The ghost lot's centre now (map XZ; INF before the pointer first reaches the ground), where
## it is easing to, whether that is not where the pointer is, and what stops it (a ground
## problem, "" when it can be laid).
var ghost_centre: Vector2 = Vector2.INF
var target_centre: Vector2 = Vector2.INF
var eased: bool = false
var problem: String = ""
## The note drawn beside the readout, {"text", "level"} (StructureNote.live, worked out again only
## when one of its inputs changes).
var note: Dictionary = {}
## The size of the lot the ghost shows (map metres) and its plan.
var ghost_size: Vector2 = Vector2.ZERO
## The structure under the pointer (its id), or -1.
var hover_id: int = -1
## The selected structure's id, or -1.
var selected_id: int = -1
## The handle under the pointer while one is selected (StructureEdit.pick_handle), or {}.
var hover_handle: Dictionary = {}
## The gesture on the selection in progress, or {}: "kind" (&"corner", &"edge" or &"move"),
## "handle", "before" (the structure as it was) and "before_list" (the document's list before the
## first preview), "start" (the press, map XZ), "grab" (the press's offset from the handle),
## "plan" (what the drag gives now), "clamped" (the pointer asks for more than it gets), "at" (the
## pointer, map XZ), "dragged" (it left the click's reach).
var edit: Dictionary = {}

## What the pointer's own spot fails on when the ghost eased away from it (StructurePlacement's
## "why"), the size asked for before the recipe's range held it, and what the note was made from.
var _why: String = ""
var _asked: Vector2 = Vector2.ZERO
var _note_key: Array = []
var _bar_key: Variant = null
var _single: bool = false
var _pick_radius_m: float = PICK_FALLBACK_M
## What the pointer is over on the screen: the camera, the pointer (INF before there is one) and
## the id of the structure whose roof or wall the pointer's ray meets (BrushTool.
## structure_under_pointer), or -1. Handles and buildings are picked by these.
var _camera: Camera3D = null
var _pointer: Vector2 = Vector2.INF
var _body_id: int = -1
var _shown_plan: PackedVector2Array = PackedVector2Array()
var _preview_ticks: int = 0
var _message: String = ""
var _planned_to: Vector3 = Vector3.INF
var _wanted: Dictionary = {}
var _last_ticks: int = 0
var _heights: Dictionary = {}
## For each lot laid over a selection: the id that was selected then (-1 for none).
var _came_from: Dictionary = {}


func _init() -> void:
	fades = true
	picks = true


# ============================================================================
# Pure helpers
# ============================================================================


## The reason a lot cannot be laid (a StructurePlacement problem, or an editor refusal), in plain
## words, or "". Pure.
static func refusal_text(reason: String) -> String:
	match reason:
		StructurePlacement.WATER:
			return WATER_TEXT
		StructurePlacement.STEEP:
			return STEEP_TEXT
		StructurePlacement.OFF_MAP:
			return OFF_MAP_TEXT
		StructurePlacement.OCCUPIED:
			return OCCUPIED_TEXT
		String(StructureEditor.REFUSED_FULL):
			return FULL_TEXT
		String(StructureEditor.REFUSED_UNKNOWN):
			return UNKNOWN_TEXT
		String(StructureEditor.REFUSED_INVALID):
			return INVALID_TEXT
	return ""


## The readout beside the cursor: the structure's name and its two sides ("Cottage  20 x 13 ft").
## Pure.
static func readout(
	title: String, along_m: float, across_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var a := roundi(ScaleUtils.world_to_display(along_m, cell_m, per_cell))
	var b := roundi(ScaleUtils.world_to_display(across_m, cell_m, per_cell))
	return "%s  %d x %d %s" % [title, a, b, label]


## `row` (a LibraryStructureStore row) with its sizes in document metres, for a map whose root is
## scaled `scale` (world metres per document metre): the tool's sizes are world metres, so a
## house keeps its size on a scaled map. Pure.
static func scaled_row(row: Dictionary, scale: float) -> Dictionary:
	var out := row.duplicate()
	for key in ["min_side_m", "max_side_m"]:
		if out.has(key):
			out[key] = float(out[key]) / scale
	if out.has("max_area_m2"):
		out["max_area_m2"] = float(out["max_area_m2"]) / (scale * scale)
	var size := StructurePlacement.default_size(row)
	out["default_size_m"] = [size.x / scale, size.y / scale]
	return out


## `colour` with its alpha set to `alpha`.
static func faded(colour: Color, alpha: float) -> Color:
	var out := colour
	out.a = alpha
	return out


# ============================================================================
# State
# ============================================================================


## Picks the structure `new_ref` to place (a ref the libraries serve; others are kept anyway and
## say so when laid).
func pick(new_ref: String) -> void:
	ref = new_ref
	ghost_centre = Vector2.INF


## The picked structure's palette row, {} when none is picked or no library serves it. With no
## pick yet, the first structure served is picked.
func row() -> Dictionary:
	if ref == "":
		var served := LibraryStructureStore.structures()
		if not served.is_empty():
			pick(String(served[0]["ref"]))
	return LibraryStructureStore.structure(ref) if ref != "" else {}


## The picked structure's name.
func title() -> String:
	return String(row().get("name", "Building"))


## The size (map metres) a click lays: the recipe's default times `size_scale`, clamped.
func default_size(editor: AuthoringEditor) -> Vector2:
	var found := row()
	if found.is_empty():
		return Vector2.ZERO
	var sized := scaled_row(found, editor.map_scale())
	return StructurePlacement.clamp_size(StructurePlacement.default_size(sized) * size_scale, sized)


## The size a click asks for before the recipe's range holds it: the recipe's default times
## `size_scale` (map metres). The ghost's note says when the range held it.
func _asked_size(editor: AuthoringEditor) -> Vector2:
	var found := row()
	if found.is_empty():
		return Vector2.ZERO
	var sized := scaled_row(found, editor.map_scale())
	return StructurePlacement.default_size(sized) * size_scale


## The ghost lot's footprint now (map XZ), or empty with no ghost.
func ghost_plan() -> PackedVector2Array:
	if ghost_centre == Vector2.INF or ghost_size == Vector2.ZERO:
		return PackedVector2Array()
	return StructurePlacement.lot_plan(
		ghost_centre, ghost_size, yaw, StructurePlacement.sides_of(row())
	)


## Starts a lot at world point `hit`.
func begin(hit: Vector3) -> void:
	drawing = true
	from = hit
	to = hit
	preview = null
	refusal = ""
	_planned_to = Vector3.INF
	hover_id = -1


## One frame with the pointer's ground point at `hit` (INF: none) and `delta` seconds since the
## last: while sized, the lot follows the pointer (planned again once it moved REPLAN_M);
## otherwise the idle ghost aims at the nearest legal spot under the pointer. Either way the
## ghost eases toward its target. With `erasing` (Ctrl held) the hover is for a removal.
func track(editor: AuthoringEditor, hit: Vector3, delta: float) -> void:
	if editor == null:
		return
	if not edit.is_empty():
		if hit != Vector3.INF:
			edit["at"] = editor.to_map_xz(hit)
		if edit["dragged"]:
			edit_to(editor, edit["at"], _single)
		return
	if drawing:
		if hit != Vector3.INF:
			to = hit
		if _planned_to == Vector3.INF or _planned_to.distance_to(to) >= REPLAN_M:
			_plan(editor)
		_ease(delta)
		return
	hover_id = _body_id
	if hover_id < 0 and hit != Vector3.INF:
		hover_id = editor.structures.structure_at(hit)
	if selected_id >= 0:
		hover_handle = {}
		var held := editor.document.structure(selected_id)
		if held == null:
			# Gone (an undo, a peer): the selection it replaced comes back if it stands.
			var back: int = _came_from.get(selected_id, -1)
			deselect()
			if back >= 0 and editor.document.structure(back) != null:
				select(back)
			return
		# An undo or redo (or a peer) changed what the bar shows: say so again.
		var key := [held.recipe, held.params]
		if key != _bar_key:
			_bar_key = key
			selection_changed.emit(selected_id)
		var at := editor.to_map_xz(hit) if hit != Vector3.INF else Vector2.INF
		hover_handle = _pick(editor, held.footprint, at)
		if hover_id >= 0 or not hover_handle.is_empty():
			ghost_centre = Vector2.INF
			target_centre = Vector2.INF
			return
	if hit == Vector3.INF or row().is_empty():
		return
	ghost_size = default_size(editor)
	_asked = _asked_size(editor)
	var want := editor.to_map_xz(hit)
	var sides := StructurePlacement.sides_of(row())
	var key := [StructurePlacement.snapped_centre(want), ghost_size, yaw, _signature(editor), sides]
	if _wanted.get("key") != key:
		var spot := StructurePlacement.nearest_legal(editor.document, want, ghost_size, yaw, sides)
		_wanted = {"key": key, "spot": spot}
	var found: Dictionary = _wanted["spot"]
	target_centre = found["centre"]
	eased = bool(found["moved"])
	problem = String(found["problem"])
	_why = String(found["why"])
	_ease(delta)


## Moves the ghost toward its target (`delta` seconds), straight there the first time.
func _ease(delta: float) -> void:
	if target_centre == Vector2.INF:
		return
	if ghost_centre == Vector2.INF:
		ghost_centre = target_centre
		return
	var gain := 1.0 - exp(-EASE_RATE * delta)
	ghost_centre = ghost_centre.lerp(target_centre, gain)
	if ghost_centre.distance_to(target_centre) < 0.01:
		ghost_centre = target_centre


## A value that changes when the structures standing do (the ghost's spot is asked again).
func _signature(editor: AuthoringEditor) -> int:
	var ids: Array = []
	for structure in editor.document.structures:
		ids.append([structure.id, structure.footprint])
	return hash(ids)


func _plan(editor: AuthoringEditor) -> void:
	_planned_to = to
	preview = null
	refusal = ""
	var found := row()
	if found.is_empty():
		refusal = NONE_PICKED
		return
	var scale := editor.map_scale()
	var a := editor.to_map_xz(from)
	var b := editor.to_map_xz(to)
	var sized := scaled_row(found, scale)
	var size := default_size(editor)
	var centre := a
	var sides := StructurePlacement.sides_of(found)
	_asked = _asked_size(editor)
	if a.distance_to(b) * scale >= DRAG_MIN_M:
		if sides > 0:
			# A round lot is drawn from its middle: the press is the centre, the pointer the rim.
			var diameter := a.distance_to(b) * 2.0
			_asked = Vector2(diameter, diameter)
			size = StructurePlacement.clamp_size(_asked, sized)
		else:
			var along := Vector2(cos(yaw), sin(yaw))
			var across := Vector2(-along.y, along.x)
			_asked = Vector2(absf((b - a).dot(along)), absf((b - a).dot(across)))
			var corners := StructurePlacement.corner_plan(a, b, yaw, sized)
			size = corners["size"]
			centre = corners["centre"]
	ghost_size = size
	var spot := StructurePlacement.nearest_legal(editor.document, centre, size, yaw, sides)
	target_centre = spot["centre"]
	eased = bool(spot["moved"])
	problem = String(spot["problem"])
	_why = String(spot["why"])
	if problem != "":
		refusal = problem
		return
	preview = editor.structures.lot(ref, spot["plan"], seed_value)
	if preview == null:
		refusal = String(editor.structures.last_refusal)


## Lays the lot being sized (the release): the structure's id, or -1 with message() saying why.
func finish(editor: AuthoringEditor) -> int:
	_message = ""
	if not drawing:
		return -1
	drawing = false
	if _planned_to != to or to == from:
		_plan(editor)
	var placed := -1
	if preview != null:
		placed = editor.structures.add(preview)
		if placed >= 0:
			seed_value = StructureEditor.next_seed(seed_value)
			_wanted = {}
			# The new building is the selection; the old one is remembered for an undo.
			var laid_over := selected_id >= 0
			_came_from[placed] = selected_id
			select(placed)
			if laid_over:
				gesture_done.emit(&"lay")
			gesture_done.emit(&"drag" if from.distance_to(to) >= DRAG_MIN_M else &"click")
		else:
			refusal = String(editor.structures.last_refusal)
	if placed < 0:
		_message = refusal_text(refusal)
	preview = null
	return placed


## Removes the structure under world point `hit` (a Ctrl press). False, with message() set, when
## there is none.
func erase_at(editor: AuthoringEditor, hit: Vector3, body: int = -1) -> bool:
	_message = ""
	var found := body if body >= 0 else editor.structures.structure_at(hit)
	if found < 0 or not editor.structures.remove(found):
		_message = NOTHING
		return false
	hover_id = -1
	_wanted = {}
	if found == selected_id:
		deselect()
	gesture_done.emit(&"remove")
	return true


# ============================================================================
# Selection and its gestures
# ============================================================================


## Selects structure `structure_id` (-1: none). The ghost lot steps aside while one is selected.
func select(structure_id: int) -> void:
	if structure_id == selected_id:
		return
	selected_id = structure_id
	_bar_key = null
	hover_handle = {}
	edit = {}
	_shown_plan = PackedVector2Array()
	ghost_centre = Vector2.INF
	target_centre = Vector2.INF
	_wanted = {}
	selection_changed.emit(structure_id)


func deselect() -> void:
	select(-1)


func has_selection() -> bool:
	return selected_id >= 0


## The selected structure in `editor`'s document (not a copy), or null.
func selected(editor: AuthoringEditor) -> Structure:
	return editor.document.structure(selected_id) if selected_id >= 0 else null


## How many document metres `pixels` screen pixels span at world point `at` (the handles are
## picked by what the author sees, not by metres). PICK_FALLBACK_M without a camera.
static func metres_for_pixels(camera: Camera3D, at: Vector3, pixels: float, scale: float) -> float:
	if camera == null or at == Vector3.INF:
		return PICK_FALLBACK_M
	var right := camera.global_transform.basis.x
	var one := camera.unproject_position(at).distance_to(camera.unproject_position(at + right))
	if one < 0.5:
		return PICK_FALLBACK_M
	return pixels / one / maxf(scale, 0.001)


## The handle of `plan` under the pointer: by screen distance (PICK_PX) when the brush has a
## camera, else (a test, a probe) by map distance from map point `at`.
func _pick(editor: AuthoringEditor, plan: PackedVector2Array, at: Vector2) -> Dictionary:
	if _camera == null or _pointer == Vector2.INF:
		return StructureEdit.pick_handle(plan, at, _pick_radius_m)
	var found := StructureEdit.handles(plan)
	var positions := PackedVector2Array()
	for handle in found:
		positions.append(StructureSelectionView.project(editor, _camera, handle["at"], 0.06))
	return StructureEdit.pick_among(found, positions, _pointer, PICK_PX)


## Aims the brush's picking at the pointer now (the camera, the pointer, the structure under it).
func _aim(brush: BrushTool) -> void:
	_camera = brush.cursor.camera
	_pointer = brush.pointer if brush.has_pointer else Vector2.INF
	_body_id = brush.structure_under_pointer()


## Begins a gesture on the selection at map point `at`: a handle's drag if one is within reach, a
## move if the pointer is on the body (`on_body`: the building's roof or wall is under it, else
## `at` inside the plan). False when it is neither. The `editor`'s list before is kept
## for the history entry (and for a cancel).
func begin_edit(editor: AuthoringEditor, at: Vector2, on_body: bool = false) -> bool:
	var held := selected(editor)
	if held == null:
		return false
	var handle := _pick(editor, held.footprint, at)
	var kind: StringName = &"move"
	if not handle.is_empty():
		kind = handle["kind"]
	elif not on_body and not Geometry2D.is_point_in_polygon(at, held.footprint):
		return false
	edit = {
		"kind": kind,
		"handle": handle,
		"before": held.copy(),
		"before_list": editor.structures.list(),
		"start": at,
		"grab": at - handle["at"] if not handle.is_empty() else Vector2.ZERO,
		"plan": held.footprint,
		"clamped": false,
		"at": at,
		"dragged": false,
	}
	_shown_plan = held.footprint
	_preview_ticks = 0
	return true


## The drag's plan with the pointer at map point `at` (Shift `single`: one point alone): the
## outline follows at once, the building about every PREVIEW_S.
func edit_to(editor: AuthoringEditor, at: Vector2, single: bool = false) -> void:
	if edit.is_empty():
		return
	var before: Structure = edit["before"]
	edit["dragged"] = true
	edit["at"] = at
	var found: Dictionary
	if edit["kind"] == &"move":
		var moved := StructureEdit.move_legal(
			editor.document, before.footprint, at - edit["start"], before.id
		)
		found = {"plan": moved["plan"], "clamped": moved["problem"] != ""}
	else:
		var sized := scaled_row(LibraryStructureStore.structure(before.recipe), editor.map_scale())
		found = StructureEdit.drag(
			before.footprint,
			edit["handle"],
			at - edit["grab"],
			sized,
			editor.document,
			before.id,
			single
		)
	edit["plan"] = found["plan"]
	edit["clamped"] = found["clamped"]
	var now := Time.get_ticks_msec()
	if found["plan"] != _shown_plan and now - _preview_ticks >= int(PREVIEW_S * 1000.0):
		_show(editor)
		_preview_ticks = now


## Builds the drag's plan now (the preview).
func _show(editor: AuthoringEditor) -> void:
	var changed: Structure = (edit["before"] as Structure).copy()
	changed.footprint = edit["plan"]
	if editor.structures.preview(changed):
		_shown_plan = edit["plan"]


## Ends the gesture in progress as one history entry: a drag that changed the plan commits it
## (resize, push or move), a plain click on a side tab makes that side the front. A drag that
## changed nothing puts the document back as it was. True when an entry was made.
func finish_edit(editor: AuthoringEditor) -> bool:
	if edit.is_empty():
		return false
	var info := edit
	edit = {}
	var before: Structure = info["before"]
	var before_list: Array[Structure] = []
	before_list.assign(info["before_list"])
	var committed := false
	if info["dragged"]:
		var plan: PackedVector2Array = info["plan"]
		if plan != before.footprint:
			var label := (
				{&"move": "Move", &"corner": "Resize", &"edge": "Push"}[info["kind"]] as String
			)
			committed = editor.structures.set_plan(before.id, plan, label, before_list)
	elif info["kind"] == &"edge" and int(info["handle"]["index"]) > 0:
		committed = editor.structures.set_front(before.id, int(info["handle"]["index"]))
	if not committed and _shown_plan != before.footprint:
		editor.structures.apply_list(before_list, Rect2())
	_shown_plan = PackedVector2Array()
	if committed:
		gesture_done.emit(&"edit")
	return committed


## Drops the gesture in progress, the document back as it was before it.
func abort_edit(editor: AuthoringEditor) -> void:
	if edit.is_empty():
		return
	var before_list: Array[Structure] = []
	before_list.assign(edit["before_list"])
	if editor != null and _shown_plan != (edit["before"] as Structure).footprint:
		editor.structures.apply_list(before_list, Rect2())
	edit = {}
	_shown_plan = PackedVector2Array()


## The pane's calls on the selection (each one history entry); false when it did nothing.
func swap_variant(editor: AuthoringEditor, new_ref: String) -> bool:
	return selected_id >= 0 and editor.structures.swap_recipe(selected_id, new_ref)


func step_selected(editor: AuthoringEditor, param: String, direction: int) -> bool:
	return selected_id >= 0 and editor.structures.step_param(selected_id, param, direction)


func door_next(editor: AuthoringEditor) -> bool:
	return selected_id >= 0 and editor.structures.set_front(selected_id, 1)


func duplicate_selected(editor: AuthoringEditor) -> bool:
	if selected_id < 0:
		return false
	var copy := editor.structures.duplicate(selected_id)
	if copy < 0:
		return false
	select(copy)
	gesture_done.emit(&"copy")
	return true


func delete_selected(editor: AuthoringEditor) -> bool:
	if selected_id < 0 or not editor.structures.remove(selected_id):
		return false
	deselect()
	gesture_done.emit(&"remove")
	return true


## Why the last finish() or erase_at() made nothing, or "".
func message() -> String:
	return _message


## Drops a lot being sized (a cancel, or after a release).
func reset() -> void:
	drawing = false
	preview = null
	refusal = ""
	_planned_to = Vector3.INF


## Turns the next lot `steps` notches of YAW_STEP (E clockwise on screen).
func turn(steps: int) -> void:
	yaw = wrapf(yaw + steps * YAW_STEP, 0.0, TAU)
	_planned_to = Vector3.INF
	_wanted = {}
	gesture_done.emit(&"turn")


## Draws the next lot afresh, or re-rolls the structure under world point `hit` (-1 for none).
func reroll_at(editor: AuthoringEditor, under: int) -> void:
	gesture_done.emit(&"again")
	if under >= 0 and editor != null:
		editor.structures.reroll(under)
		return
	seed_value = StructureEditor.next_seed(seed_value)


# ============================================================================
# BrushMode hooks
# ============================================================================


## Starts a lot, or with Ctrl erases the structure under the press (a miss says why).
func press(brush: BrushTool) -> bool:
	_aim(brush)
	if brush.press_ctrl:
		if not erase_at(brush.editor, brush.hit, _body_id):
			brush.refused.emit(message())
		return false
	var editor := brush.editor
	var at := editor.to_map_xz(brush.hit)
	# The selection's handles and body first, then any other building (selected, and carried
	# if the press turns into a drag), then bare ground: a selected building lets go first. A
	# building is what the pointer's ray meets (its roof, its wall), else the one whose plan
	# holds the ground point.
	if begin_edit(editor, at, _body_id >= 0 and _body_id == selected_id):
		return false
	var under := _body_id
	if under < 0:
		under = StructurePlacement.structure_at(editor.document, at)
	if under >= 0:
		select(under)
		begin_edit(editor, at, true)
		gesture_done.emit(&"choose")
		return false
	if row().is_empty():
		if selected_id >= 0:
			deselect()
		else:
			brush.refused.emit(NONE_PICKED)
		return false
	# Bare ground with a pick armed lays a lot, selection or not (finish selects it).
	begin(brush.hit)
	return false


## True when the press began a lot or a gesture on the selection (an erase is silent, as a
## prop's removal is).
func took_press() -> bool:
	return drawing or not edit.is_empty()


func has_target() -> bool:
	return hover_id >= 0


func frame(brush: BrushTool) -> void:
	_pick_radius_m = metres_for_pixels(
		brush.cursor.camera,
		brush.hit,
		PICK_PX,
		brush.editor.map_scale() if brush.editor != null else 1.0
	)
	_single = brush.shift
	_aim(brush)
	if not edit.is_empty() and brush.pressed:
		edit["dragged"] = (
			edit["dragged"] or brush.pointer.distance_to(brush.press_position) >= CLICK_PX
		)
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _last_ticks == 0 else minf(float(now - _last_ticks) / 1.0e6, 0.1)
	_last_ticks = now
	track(brush.editor, brush.hit, delta)


## Lays the lot being sized (a lot that fits nowhere says why).
func end(brush: BrushTool) -> void:
	if drawing and brush.editor != null:
		if finish(brush.editor) < 0:
			brush.refused.emit(message())
	if not edit.is_empty() and brush.editor != null:
		finish_edit(brush.editor)
	reset()


## RMB or Escape: a drag on the selection or a lot being sized is dropped; with neither, the
## selection lets go.
func cancel(brush: BrushTool) -> void:
	if not edit.is_empty():
		abort_edit(brush.editor)
	elif drawing:
		reset()
	else:
		if selected_id >= 0:
			gesture_done.emit(&"esc")
		deselect()


func leave(brush: BrushTool) -> void:
	abort_edit(brush.editor)
	deselect()
	reset()
	hover_id = -1
	ghost_centre = Vector2.INF
	target_centre = Vector2.INF
	_wanted = {}
	_came_from = {}
	_last_ticks = 0


## Shift+wheel over a building and the bracket keys: the size a click lays, a notch of SIZE_STEP
## each way (a drag still sizes a lot exactly).
func step(brush: BrushTool, steps: int) -> void:
	size_scale = stepped_scale(size_scale, steps)
	_planned_to = Vector3.INF
	_wanted = {}
	brush.redraw()


## `scale` stepped `steps` notches within SIZE_SCALE_RANGE. Pure.
static func stepped_scale(scale: float, steps: int) -> float:
	return clampf(scale * pow(SIZE_STEP, steps), SIZE_SCALE_RANGE.x, SIZE_SCALE_RANGE.y)


func rotates() -> bool:
	return true


## Q and E: the selected building turns (a notch each; no room to turn says so), else the next
## lot does.
func rotate(brush: BrushTool, steps: int) -> void:
	if selected_id >= 0 and brush.editor != null:
		if edit.is_empty():
			if brush.editor.structures.turn(selected_id, steps * YAW_STEP):
				gesture_done.emit(&"turn")
			else:
				brush.refused.emit(NO_TURN_TEXT)
	else:
		turn(steps)
	brush.redraw()


func rerolls() -> bool:
	return true


## R: the selected building is drawn afresh, else the one under the pointer, else the next lot.
func reroll(brush: BrushTool) -> void:
	reroll_at(brush.editor, selected_id if selected_id >= 0 else hover_id)
	_wanted = {}
	brush.redraw()


func duplicates() -> bool:
	return selected_id >= 0


## Ctrl+D: a copy of the selected building beside it, which is then the selection.
func duplicate(brush: BrushTool) -> void:
	if brush.editor != null and edit.is_empty() and not duplicate_selected(brush.editor):
		brush.refused.emit(NO_COPY_TEXT)
	brush.redraw()


## RMB or Delete over a structure.
func remove_target(brush: BrushTool) -> void:
	if brush.editor != null and not erase_at(brush.editor, brush.hit, _body_id):
		brush.refused.emit(message())


## The lot stays in view under a canopy: the focus is its middle.
func fade_focus(brush: BrushTool) -> Vector4:
	var centre := brush.hit
	if ghost_centre != Vector2.INF and brush.editor != null:
		var ground := WaterGeometry.ground_at(brush.editor.document, ghost_centre)
		centre = brush.editor.to_world(Vector3(ghost_centre.x, ground, ghost_centre.y))
	var reach := maxf(FADE_M, maxf(ghost_size.x, ghost_size.y) * 0.5 + 1.0)
	return Vector4(centre.x, centre.y, centre.z, reach)


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor == null:
		return
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	var erasing := brush.ctrl and not brush.pressed
	draw(cursor.canvas, cursor.camera, brush.editor, brush.hit, erasing, units)


# ============================================================================
# Drawing
# ============================================================================


## The cursor and previews on `canvas` (see the header), for the pointer's ground point `hit`
## with Ctrl `erasing`; the readout in the level's units.
func draw(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	erasing: bool,
	units: Array
) -> void:
	var cell_m: float = units[0]
	var per_cell: float = units[1]
	var label: String = units[2]
	var scale := editor.map_scale()
	var selecting := selected_id >= 0 and not drawing
	if selecting:
		StructureSelectionView.draw(self, canvas, camera, editor, units)
		# The ghost lot follows over bare ground; it steps aside over a building or a handle.
		if hover_id >= 0 and hover_id != selected_id:
			_draw_hovered(canvas, camera, editor, hit, erasing)
		if not edit.is_empty() or hover_id >= 0 or not hover_handle.is_empty():
			return
		if erasing:
			if hit != Vector3.INF:
				BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.ERASE_TINT)
			return
	elif not drawing and hover_id >= 0:
		_draw_hovered(canvas, camera, editor, hit, erasing)
		# A click on a building selects it, so no lot follows the pointer over one.
		return
	elif erasing and not drawing:
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.ERASE_TINT)
		return
	if row().is_empty():
		if selecting:
			return
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.STONE_TINT)
			BridgeBrush.draw_pill(
				canvas, camera.unproject_position(hit), NONE_PICKED, WallBrush.REFUSED_COLOR
			)
		return
	var plan := ghost_plan()
	if plan.is_empty():
		return
	var ok := problem == "" and (not drawing or preview != null)
	_refresh_note(scale, units, ok)
	var level: int = note["level"]
	var tint := StructureNote.ghost_tint(level)
	var high := height_of(ref) / scale
	StructurePlanView.draw_plan(canvas, camera, editor, plan, high, tint, 1.0 if drawing else 0.8)
	if drawing:
		for corner in [from, to]:
			BridgeBrush.draw_marker(canvas, camera, corner, tint)
	var ground := WaterGeometry.ground_at(editor.document, ghost_centre)
	var anchor := editor.to_world(Vector3(ghost_centre.x, ground, ghost_centre.y))
	var at := camera.unproject_position(anchor)
	var text := readout(title(), ghost_size.x * scale, ghost_size.y * scale, cell_m, per_cell, label)
	# The name and size always; a note (amber) or the reason a lot cannot stand (red) beneath.
	var lines: Array[Dictionary] = [{"text": text, "color": WallBrush.READOUT_COLOR}]
	if level != StructureNote.Level.NONE:
		lines.append({"text": note["text"], "color": StructureNote.colour(level)})
	StructurePlanView.draw_pills(canvas, at, lines)


## The building under the pointer, tinted (a click selects it), or with Ctrl `erasing` red with a
## pill saying what a click removes.
func _draw_hovered(
	canvas: Control, camera: Camera3D, editor: AuthoringEditor, hit: Vector3, erasing: bool
) -> void:
	var hovered := editor.document.structure(hover_id)
	if hovered == null:
		return
	var strength := 1.0 if erasing else 0.45
	var tint := WallBrush.ERASE_TINT if erasing else WallBrush.STONE_TINT
	StructurePlanView.draw_plan(canvas, camera, editor, hovered.footprint, 0.0, tint, strength)
	if erasing:
		BridgeBrush.draw_pill(
			canvas,
			camera.unproject_position(hit),
			"Remove " + String(hovered.recipe.get_slice(":", 1)).replace("_", " "),
			WallBrush.REFUSED_COLOR
		)


## Works the ghost's note out again when something it reads changed (the spot's problem, what the
## lot was moved off, the size asked and given, the units, a lot being sized and why the editor
## refused it): the per-frame draw only reads the cached note.
func _refresh_note(scale: float, units: Array, ok: bool) -> void:
	var stop := refusal if drawing else problem
	if not ok and stop == "":
		stop = refusal if refusal != "" else String(StructureEditor.REFUSED_INVALID)
	var key := [stop, _why, eased, _asked, ghost_size, scale, units, ok]
	if key == _note_key:
		return
	_note_key = key
	var clamp := StructureNote.clamp_text(
		_asked * scale, ghost_size * scale, float(units[0]), float(units[1]), String(units[2])
	)
	note = StructureNote.live(stop if not ok else "", _why, eased, clamp)


## The recipe's default wall height in metres (cached per structure).
func height_of(structure_ref: String) -> float:
	if not _heights.has(structure_ref):
		var height := LibraryStructures.TILE_DEFAULT_HEIGHT_M
		var recipe := StructureRecipes.document(structure_ref)
		if recipe != null:
			for item: Dictionary in recipe.interface:
				if String(item.get("name", "")) == "height":
					height = float(item.get("default", height))
		_heights[structure_ref] = height
	return _heights[structure_ref]
