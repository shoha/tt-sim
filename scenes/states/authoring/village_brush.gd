class_name VillageBrush
extends BrushMode

## The Village tool's mode (VillageTool): lays, sizes, picks and removes the plaza discs of the
## map's dressed villages (Settlement.plazas; docs/systems/villages.md section 10). BrushTool routes
## the tool's press, frames, release and cancel to it. Where a plaza goes and how it is paved is
## SettlementEditor's rule (add_plaza, resize_plaza, remove_plaza: one history entry each, the
## paving and the kit's plaza furnishings follow, a live-edit peer receives the usual `surface`
## and `settlements` ops); this only wires the gestures to it and draws the answer.
##
## Gestures.
## - A press on bare ground starts a new plaza at that point; the village it joins is the nearest
##   in reach (VillagePlazas.village_for), the picked one keeping a press that is only a few
##   metres nearer to another. A click lays a plaza of DEFAULT_RADIUS_M, a drag sizes it by how
##   far the pointer goes from the centre.
## - A press on a plaza's rim (the soft ring) grabs the edge: the drag sizes that plaza, the rim
##   following the pointer. A press inside a plaza picks it.
## - The release does the edit as one history entry; the ring drawn while dragging is the preview.
## - Delete or Backspace over a plaza, or the pane's Remove, removes it with its paving; the
##   brackets and Shift+wheel over a plaza step its radius by a metre; Escape lets go of the
##   picked plaza; RMB or Escape during a drag drops it.
## The first village is picked while none is, and a press near another village picks that one.

## The picked village or plaza changed.
signal selection_changed(village: int, plaza: int)
## Something the pane shows changed: the selection, or the villages and plazas of the document
## (an edit, an undo, a redo).
signal view_changed

## The gesture a held press is making.
const GESTURE_NEW := &"new"
const GESTURE_RESIZE := &"resize"
const GESTURE_PICK := &"pick"

## Ring tints: the picked plaza in the Wall tool's gold, the one under the pointer in warm chalk,
## the rest soft paper.
const TINT_PICKED := WallBrush.READOUT_COLOR
const TINT_HOVER := Color.IVORY
const TINT_CALM := Color.OLD_LACE
const TINT_REFUSED := BrushCursor.CLEAR_TINT
const SHADOW := BrushCursor.SHADOW_COLOR
const REFUSED_COLOR := WallBrush.REFUSED_COLOR
const READOUT_COLOR := WallBrush.READOUT_COLOR
## Points round a drawn ring, the pixels a rim grab reaches and the fill under a ring.
const RING_POINTS := 56
const RIM_PX := 10.0
const FILL_ALPHA := 0.13
const HANDLE_PX := 4.5
## The canopy fade's reach round a plaza (metres, before the brush's fade factor).
const FADE_M := 3.0
## Plain-words reasons a press makes nothing.
const NO_VILLAGE := "Dress a street with the Wall tool first: a plaza belongs to a village."
const FULL := "A village holds four plazas. Remove one to make room."
const REFUSED := "A plaza cannot go there."
## The words beside the cursor.
const HOVER_RIM := "Drag the edge to size this plaza"
const HOVER_INSIDE := "Plaza: click to pick, Delete removes it"
const IDLE := "Click for a plaza in the %s, or drag to size it"
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
var _centre: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _start_radius: float = 0.0
var _grabbed_at: float = 0.0
var _rim_m: float = VillagePlazas.RIM_BAND_M
var _message: String = ""
var _signature: String = ""


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


## Why the last press or edit made nothing, or "".
func message() -> String:
	return _message


## The radius the held gesture is making now (metres in the map frame), or 0 with none.
func preview_radius() -> float:
	match gesture:
		GESTURE_NEW:
			return VillagePlazas.radius_for_drag(_centre, _to)
		GESTURE_RESIZE:
			return VillagePlazas.radius_for_rim_drag(
				_start_radius, _grabbed_at, _centre.distance_to(_to)
			)
	return 0.0


## Picks village `village` and its plaza `plaza` (-1: the village alone).
func select(village: int, plaza: int) -> void:
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
	if selected_plaza < 0:
		return false
	return editor.settlements.resize_plaza(
		selected_village, selected_plaza, VillagePlazas.clamp_radius(radius)
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
	var found := VillagePlazas.pick(doc.settlements, p, _rim_m)
	if not found.is_empty():
		var village := int(found["settlement"])
		_grab_village = village
		_grab_plaza = int(found["index"])
		_centre = doc.settlement(village).plazas[_grab_plaza]["at"]
		_start_radius = float(doc.settlement(village).plazas[_grab_plaza]["radius"])
		_to = p
		_grabbed_at = _centre.distance_to(p)
		gesture = GESTURE_RESIZE if found["part"] == VillagePlazas.PART_RIM else GESTURE_PICK
		select(village, _grab_plaza)
		return false
	var target := VillagePlazas.village_for(doc, p, selected_village)
	if target < 0:
		_message = NO_VILLAGE
	elif doc.settlement(target).plazas.size() >= Settlement.MAX_PLAZAS:
		_message = FULL
	if _message != "":
		brush.refused.emit(_message)
		return false
	_grab_village = target
	_grab_plaza = -1
	_centre = p
	_to = p
	gesture = GESTURE_NEW
	select(target, -1)
	return false


func took_press() -> bool:
	return gesture != &""


## Follows the pointer: the gesture's end, or the plaza under it; keeps the pick and the pane
## in step with the document (an undo can take a picked plaza away).
func frame(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null:
		return
	_sync_selection(editor)
	if brush.hit == Vector3.INF:
		hover_village = -1
		hover_plaza = -1
	else:
		_rim_m = maxf(
			VillagePlazas.RIM_BAND_M,
			StructureBrush.metres_for_pixels(
				brush.cursor.camera if brush.cursor != null else null,
				brush.hit,
				RIM_PX,
				editor.map_scale()
			)
		)
		var p := editor.to_map_xz(brush.hit)
		if gesture != &"":
			_to = p
		else:
			var found := VillagePlazas.pick(editor.document.settlements, p, _rim_m)
			hover_village = int(found.get("settlement", -1))
			hover_plaza = int(found.get("index", -1))
			hover_part = found.get("part", &"")
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
func leave(_brush: BrushTool) -> void:
	reset()
	hover_village = -1
	hover_plaza = -1
	select(-1, -1)
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
		float(held.plazas[index]["radius"]) + steps * VillagePlazas.RADIUS_STEP_M
	)
	if not editor.settlements.resize_plaza(village, index, wanted):
		if editor.settlements.last_refusal != &"":
			brush.refused.emit(REFUSED)
		return
	select(village, index)
	brush.redraw()


func fade_focus(brush: BrushTool) -> Vector4:
	var reach := FADE_M
	var centre := brush.hit
	if gesture != &"" and brush.editor != null:
		reach += preview_radius() * brush.editor.map_scale()
		var y := WaterGeometry.ground_at(brush.editor.document, _centre)
		centre = brush.editor.to_world(Vector3(_centre.x, y, _centre.y))
	return Vector4(centre.x, centre.y, centre.z, reach)


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
		select(first, -1)
	elif selected_plaza >= held.plazas.size():
		select(selected_village, -1)
	if gesture != &"" and doc.settlement(_grab_village) == null:
		reset()


## Emits view_changed when what the pane shows differs from the last frame.
func _announce(editor: AuthoringEditor) -> void:
	var parts: Array = [selected_village, selected_plaza]
	for settlement in editor.document.settlements:
		parts.append([settlement.id, settlement.kit, settlement.plazas])
	var now := var_to_str(parts)
	if now != _signature:
		_signature = now
		view_changed.emit()


# ============================================================================
# Drawing
# ============================================================================


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	var editor := brush.editor
	if editor == null:
		return
	var canvas := cursor.canvas
	var camera := cursor.camera
	var doc := editor.document
	for settlement in doc.settlements:
		for index in settlement.plazas.size():
			var plaza := settlement.plazas[index]
			var radius := float(plaza["radius"])
			var picked := settlement.id == selected_village and index == selected_plaza
			var hovered := (
				gesture == &"" and settlement.id == hover_village and index == hover_plaza
			)
			var held := gesture == GESTURE_RESIZE and picked
			if held:
				radius = preview_radius()
			var tint := TINT_PICKED if picked else (TINT_HOVER if hovered else TINT_CALM)
			var strength := 1.0 if (picked or hovered) else 0.55
			draw_plaza(canvas, camera, editor, plaza["at"], radius, tint, strength, picked or hovered)
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	if gesture == GESTURE_NEW or gesture == GESTURE_RESIZE:
		var radius := preview_radius()
		if gesture == GESTURE_NEW:
			draw_plaza(canvas, camera, editor, _centre, radius, TINT_PICKED, 1.0, true)
		BridgeBrush.draw_pill(
			canvas,
			camera.unproject_position(brush.hit),
			readout(radius * editor.map_scale(), units),
			READOUT_COLOR
		)
		return
	if brush.hit == Vector3.INF or gesture == GESTURE_PICK:
		return
	var pill_at := camera.unproject_position(brush.hit)
	if hover_plaza >= 0:
		var rim := hover_part == VillagePlazas.PART_RIM
		BridgeBrush.draw_pill(canvas, pill_at, HOVER_RIM if rim else HOVER_INSIDE, READOUT_COLOR)
		return
	var p := editor.to_map_xz(brush.hit)
	var village := VillagePlazas.village_for(doc, p, selected_village)
	if village < 0:
		BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_REFUSED)
		BridgeBrush.draw_pill(canvas, pill_at, NO_VILLAGE_SHORT, REFUSED_COLOR)
	elif doc.settlement(village).plazas.size() >= Settlement.MAX_PLAZAS:
		BridgeBrush.draw_marker(canvas, camera, brush.hit, TINT_REFUSED)
		BridgeBrush.draw_pill(canvas, pill_at, FULL_SHORT, REFUSED_COLOR)
	else:
		draw_plaza(canvas, camera, editor, p, VillagePlazas.DEFAULT_RADIUS_M, TINT_HOVER, 0.7, false)
		var kit := VillagePlazas.kit_label(doc.settlement(village).kit).to_lower()
		BridgeBrush.draw_pill(canvas, pill_at, IDLE % kit, READOUT_COLOR)


## The readout of a plaza `radius_world` metres in radius: its width across in the level's units.
static func readout(radius_world: float, units: Array) -> String:
	var across := roundi(
		ScaleUtils.world_to_display(2.0 * radius_world, float(units[0]), float(units[1]))
	)
	return "Plaza  %d %s across" % [across, str(units[2])]


## A plaza ring on `canvas`: the disc faintly filled on the ground, a soft glow under a dark
## keyline under a bright line, and with `handles` four dots on the rim that say it can be
## dragged. Each point sits on the document's ground. `strength` scales every alpha.
static func draw_plaza(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	at: Vector2,
	radius: float,
	tint: Color,
	strength: float,
	handles: bool
) -> void:
	var doc := editor.document
	var screen := func(p: Vector2) -> Vector2:
		var y := WaterGeometry.ground_at(doc, p) + 0.06
		return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))
	var ring := PackedVector2Array()
	for k in RING_POINTS:
		ring.append(screen.call(at + Vector2.from_angle(TAU * k / RING_POINTS) * radius))
	ring.append(ring[0])
	var fan := ring.duplicate()
	fan.append(screen.call(at))
	var colors := PackedColorArray()
	colors.resize(fan.size())
	colors.fill(_alpha(tint, FILL_ALPHA * strength))
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), BrushCursor.fan_indices(ring.size()), fan, colors
	)
	var glow := _alpha(tint, BrushCursor.GLOW_ALPHA * strength)
	var ink := _alpha(SHADOW, BrushCursor.INK_ALPHA * 0.6 * strength)
	canvas.draw_polyline(ring, glow, BrushCursor.GLOW_WIDTH, true)
	canvas.draw_polyline(ring, ink, BrushCursor.INK_WIDTH, true)
	canvas.draw_polyline(ring, _alpha(tint, strength), BrushCursor.LINE_WIDTH, true)
	if not handles:
		return
	for k in 4:
		var dot: Vector2 = screen.call(at + Vector2.from_angle(TAU * k / 4.0 + 0.4) * radius)
		canvas.draw_circle(dot, HANDLE_PX + 1.5, _alpha(SHADOW, 0.8))
		canvas.draw_circle(dot, HANDLE_PX, tint)


## `color` with alpha `alpha`.
static func _alpha(color: Color, alpha: float) -> Color:
	var out := color
	out.a = alpha
	return out
