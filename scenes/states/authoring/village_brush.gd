class_name VillageBrush
extends BrushMode

## The Village tool's mode (VillageTool): lays, sizes, picks and removes the plaza discs of the
## map's dressed villages (Settlement.plazas; docs/systems/villages.md section 10). BrushTool routes
## the tool's press, frames, release and cancel to it. Where a plaza goes and how it is paved is
## SettlementEditor's rule (add_plaza, resize_plaza, remove_plaza: one history entry each, the
## paving and the kit's plaza furnishings follow, a live-edit peer receives the usual `surface`
## and `settlements` ops); this only wires the gestures to it. VillageRings draws the answer.
##
## Gestures.
## - A press on bare ground starts a new plaza at that point; the village it joins is the nearest
##   in reach (VillagePlazas.village_for), the picked one keeping a press that is only a few
##   metres nearer to another. A click lays a plaza of DEFAULT_RADIUS_M, a drag sizes it by how
##   far the pointer goes from the centre.
## - A press on a plaza's rim (the soft ring, or near one of its handle dots) grabs the edge: the
##   drag sizes that plaza, the rim following the pointer. A press inside a plaza picks it.
## - The release does the edit as one history entry; the ring drawn while dragging is the preview.
## - Delete or Backspace over a plaza, or the pane's Remove, removes it with its paving; the
##   brackets and Shift+wheel over a plaza step its radius by a metre; Escape lets go of the
##   picked plaza; RMB or Escape during a drag drops it.
##
## The picked village is what the pane shows. Until the author picks one (a press, a plaza, the
## pane's village row) it follows the pointer: the village a press there would join, so the pane,
## the ghost and its hint always name the same village. Once picked it stays until the author
## picks again.

## The picked village or plaza changed.
signal selection_changed(village: int, plaza: int)
## Something the pane shows changed: the selection, the size a held drag is making, or the
## villages and plazas of the document (an edit, an undo, a redo).
signal view_changed

## The gesture a held press is making.
const GESTURE_NEW := &"new"
const GESTURE_RESIZE := &"resize"
const GESTURE_PICK := &"pick"

## The pixels a rim grab reaches each side of the edge, and round a handle dot (the dots are the
## S6 target, 44 px across).
const RIM_PX := 12.0
const HANDLE_HIT_PX := 22.0
## The canopy fade's reach round a plaza (metres, before the brush's fade factor).
const FADE_M := 3.0
## Plain-words reasons a press makes nothing.
const NO_VILLAGE := "Dress a street with the Wall tool first: a plaza belongs to a village."
const FULL := "A village holds four plazas. Remove one to make room."
const REFUSED := "A plaza cannot go there."
## The words beside the cursor.
const HOVER_RIM := "Drag the edge to size this plaza"
const HOVER_INSIDE := "Plaza: click to pick, Delete removes it"
const HOVER_PICKED := "Drag the edge to size it, Delete removes it"
const IDLE := "Click for a plaza, or drag to size it"
const IDLE_IN := "Click for a plaza in %s, or drag to size it"
const NO_VILLAGE_SHORT := "Dress a street first"
const FULL_SHORT := "Four plazas already"

## The picked village (a Settlement id) and plaza (an index in its plazas), or -1.
var selected_village: int = -1
var selected_plaza: int = -1
## The plaza under the pointer: its village, index and part (VillagePlazas.PART_*), or -1.
var hover_village: int = -1
var hover_plaza: int = -1
var hover_part: StringName = &""
## The held press's gesture (GESTURE_*), or empty.
var gesture: StringName = &""

var _grab_village: int = -1
var _grab_plaza: int = -1
var _grab_kit: String = ""
var _centre: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _start_radius: float = 0.0
var _grabbed_at: float = 0.0
var _rim_m: float = VillagePlazas.RIM_BAND_M
var _handle_m: float = 0.0
var _explicit: bool = false
var _message: String = ""
var _signature: String = ""
## True after leave() paused the map's StructureWarmup; the next frame() resumes it.
var _warm_paused: bool = false


func _init() -> void:
	picks = true
	fades = true


## The reason a plaza edit made nothing, in plain words. Pure.
static func refusal_text(reason: StringName) -> String:
	match reason:
		SettlementEditor.REFUSED_FULL:
			return FULL
		SettlementEditor.REFUSED_STREET:
			return NO_VILLAGE
	return REFUSED


## The words beside the ghost of a plaza that would join village `village` of `doc`: the village
## is named once the map has two or more.
static func ghost_hint(doc: MapDocument, village: int) -> String:
	if doc.settlements.size() < 2:
		return IDLE
	return IDLE_IN % VillagePlazas.village_name(village).to_lower()


## Why the last press or edit made nothing, or "".
func message() -> String:
	return _message


## The radius the held gesture is making now (metres in the map frame), or 0 with none.
func preview_radius() -> float:
	match gesture:
		GESTURE_NEW:
			return VillagePlazas.radius_for_drag(_centre, _to, _grab_kit)
		GESTURE_RESIZE:
			# A plaza already under its kit's floor is never pushed up by a grab alone.
			var floor_m := minf(VillagePlazas.min_radius(_grab_kit), _start_radius)
			return VillagePlazas.radius_for_rim_drag(
				_start_radius, _grabbed_at, _centre.distance_to(_to), floor_m
			)
	return 0.0


## The held gesture's plaza centre (map XZ).
func centre() -> Vector2:
	return _centre


## Whether a held drag is sizing a plaza (a new one or a grabbed rim).
func sizing() -> bool:
	return gesture == GESTURE_NEW or gesture == GESTURE_RESIZE


## The village a press at map point `p` would join (the ghost's), or -1.
func ghost_village(editor: AuthoringEditor, p: Vector2) -> int:
	return VillagePlazas.village_for(editor.document, p, selected_village)


## Picks village `village` and its plaza `plaza` (-1: the village alone). `explicit` false is the
## mode's own pick (the first village, or the one the pointer is over) that the next frame may
## move; an author's pick stays.
func select(village: int, plaza: int, explicit: bool = true) -> void:
	_explicit = explicit and village > 0
	if village == selected_village and plaza == selected_plaza:
		return
	selected_village = village
	selected_plaza = plaza
	selection_changed.emit(village, plaza)
	view_changed.emit()


## Removes plaza `index` of village `village` with its paving, keeping the pick pointing at the
## same plaza. False when the editor refuses.
func remove(editor: AuthoringEditor, village: int, index: int) -> bool:
	if not editor.settlements.remove_plaza(village, index):
		return false
	hover_village = -1
	hover_plaza = -1
	if village == selected_village and selected_plaza >= 0:
		if selected_plaza == index:
			select(village, -1)
		elif selected_plaza > index:
			select(village, selected_plaza - 1)
	return true


## Removes the picked plaza (the pane's Remove).
func remove_selected(editor: AuthoringEditor) -> bool:
	if selected_plaza < 0:
		return false
	return remove(editor, selected_village, selected_plaza)


## Sets the picked plaza's radius to `radius` metres (the pane's slider). False when it changes
## nothing or the editor refuses.
func set_selected_radius(editor: AuthoringEditor, radius: float) -> bool:
	var held := editor.document.settlement(selected_village) if selected_village > 0 else null
	if selected_plaza < 0 or held == null:
		return false
	return editor.settlements.resize_plaza(
		selected_village, selected_plaza, VillagePlazas.clamp_radius(radius, held.kit)
	)


# ============================================================================
# BrushMode hooks
# ============================================================================


func has_target() -> bool:
	return hover_plaza >= 0


## A press on a plaza's rim grabs the edge, inside it picks the plaza, on bare ground starts a
## new plaza of the picked (or nearest) village. The edit is the release's.
func press(brush: BrushTool) -> bool:
	_message = ""
	var editor := brush.editor
	var doc := editor.document
	var p := editor.to_map_xz(brush.hit)
	var found := VillagePlazas.pick(doc.settlements, p, _rim_m, _handle_m)
	if not found.is_empty():
		var village := int(found["settlement"])
		_grab_village = village
		_grab_kit = doc.settlement(village).kit
		_grab_plaza = int(found["index"])
		_centre = doc.settlement(village).plazas[_grab_plaza]["at"]
		_start_radius = float(doc.settlement(village).plazas[_grab_plaza]["radius"])
		_to = p
		_grabbed_at = _centre.distance_to(p)
		gesture = GESTURE_RESIZE if found["part"] == VillagePlazas.PART_RIM else GESTURE_PICK
		select(village, _grab_plaza)
		return false
	var target := ghost_village(editor, p)
	if target < 0:
		_message = NO_VILLAGE
	elif doc.settlement(target).plazas.size() >= Settlement.MAX_PLAZAS:
		_message = FULL
	if _message != "":
		brush.refused.emit(_message)
		return false
	_grab_village = target
	_grab_kit = doc.settlement(target).kit
	_grab_plaza = -1
	_centre = p
	_to = p
	gesture = GESTURE_NEW
	select(target, -1)
	return false


func took_press() -> bool:
	return gesture != &""


## Follows the pointer: the gesture's end, or the plaza under it; keeps the pick and the pane
## in step with the document (an undo can take a picked plaza away) and, until the author has
## picked a village, with the village under the pointer.
func frame(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null:
		return
	if _warm_paused:
		_warm_paused = false
		StructureWarmup.resume_map(editor.map_root)
	_sync_selection(editor)
	if brush.hit == Vector3.INF:
		hover_village = -1
		hover_plaza = -1
	else:
		var camera := brush.cursor.camera if brush.cursor != null else null
		var scale := editor.map_scale()
		_rim_m = maxf(
			VillagePlazas.RIM_BAND_M,
			StructureBrush.metres_for_pixels(camera, brush.hit, RIM_PX, scale)
		)
		_handle_m = maxf(
			_rim_m, StructureBrush.metres_for_pixels(camera, brush.hit, HANDLE_HIT_PX, scale)
		)
		var p := editor.to_map_xz(brush.hit)
		if gesture != &"":
			_to = p
		else:
			var found := VillagePlazas.pick(editor.document.settlements, p, _rim_m, _handle_m)
			hover_village = int(found.get("settlement", -1))
			hover_plaza = int(found.get("index", -1))
			hover_part = found.get("part", &"")
			if not _explicit:
				var target := hover_village if hover_plaza >= 0 else ghost_village(editor, p)
				if target > 0 and target != selected_village:
					select(target, -1, false)
	_announce(editor)


## The release: lays the new plaza, or sizes the grabbed one, as one history entry.
func end(brush: BrushTool) -> void:
	var editor := brush.editor
	if gesture == &"" or editor == null:
		reset()
		return
	var radius := preview_radius()
	var done := true
	if gesture == GESTURE_NEW:
		done = editor.settlements.add_plaza(_grab_village, _centre, radius)
		if done:
			select(_grab_village, editor.document.settlement(_grab_village).plazas.size() - 1)
	elif gesture == GESTURE_RESIZE and absf(radius - _start_radius) >= 0.1:
		done = editor.settlements.resize_plaza(_grab_village, _grab_plaza, radius)
	if not done:
		_message = refusal_text(editor.settlements.last_refusal)
		brush.refused.emit(_message)
	reset()


## Escape or RMB: drops a held gesture, else lets go of the picked plaza.
func cancel(_brush: BrushTool) -> void:
	if gesture != &"":
		reset()
	elif selected_plaza >= 0:
		select(selected_village, -1)


## Escape with no press held is the brush's while a plaza is picked.
func has_selection() -> bool:
	return selected_plaza >= 0


## The tool is put down or another is picked.
func leave(brush: BrushTool) -> void:
	StructureWarmup.pause_map(brush.editor.map_root if brush.editor != null else null)
	_warm_paused = true
	reset()
	hover_village = -1
	hover_plaza = -1
	select(-1, -1, false)
	_signature = ""


## Drops a held gesture.
func reset() -> void:
	gesture = &""
	_grab_village = -1
	_grab_plaza = -1


## Delete or Backspace over a plaza.
func remove_target(brush: BrushTool) -> void:
	if brush.editor != null and hover_plaza >= 0:
		if not remove(brush.editor, hover_village, hover_plaza):
			brush.refused.emit(REFUSED)


## Shift+wheel over a plaza or a bracket key: the plaza under the pointer (else the picked one)
## grows or shrinks a metre a notch.
func step(brush: BrushTool, steps: int) -> void:
	var editor := brush.editor
	if editor == null or gesture != &"":
		return
	var village := hover_village if hover_plaza >= 0 else selected_village
	var index := hover_plaza if hover_plaza >= 0 else selected_plaza
	var held := editor.document.settlement(village) if village > 0 and index >= 0 else null
	if held == null or index >= held.plazas.size():
		return
	var wanted := VillagePlazas.clamp_radius(
		float(held.plazas[index]["radius"]) + steps * VillagePlazas.RADIUS_STEP_M, held.kit
	)
	if not editor.settlements.resize_plaza(village, index, wanted):
		if editor.settlements.last_refusal != &"":
			brush.refused.emit(REFUSED)
		return
	select(village, index)
	brush.redraw()


func fade_focus(brush: BrushTool) -> Vector4:
	var reach := FADE_M
	var at := brush.hit
	if gesture != &"" and brush.editor != null:
		reach += preview_radius() * brush.editor.map_scale()
		var y := WaterGeometry.ground_at(brush.editor.document, _centre)
		at = brush.editor.to_world(Vector3(_centre.x, y, _centre.y))
	return Vector4(at.x, at.y, at.z, reach)


# ============================================================================
# State kept in step with the document
# ============================================================================


## Lets go of a pick an undo took away, and picks the first village when none is picked, so the
## pane's character tiles are live from the first frame.
func _sync_selection(editor: AuthoringEditor) -> void:
	var doc := editor.document
	var held := doc.settlement(selected_village) if selected_village > 0 else null
	if held == null:
		var first: int = doc.settlements[0].id if not doc.settlements.is_empty() else -1
		select(first, -1, false)
	elif selected_plaza >= held.plazas.size():
		select(selected_village, -1, _explicit)
	if gesture != &"" and doc.settlement(_grab_village) == null:
		reset()


## Emits view_changed when what the pane shows differs from the last frame (a held drag's size
## included, so the pane's size reads it live).
func _announce(editor: AuthoringEditor) -> void:
	var parts: Array = [selected_village, selected_plaza, preview_radius() if sizing() else 0.0]
	for settlement in editor.document.settlements:
		parts.append([settlement.id, settlement.kit, settlement.plazas])
	var now := var_to_str(parts)
	if now != _signature:
		_signature = now
		view_changed.emit()


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor != null:
		VillageRings.draw(brush, cursor, self)
