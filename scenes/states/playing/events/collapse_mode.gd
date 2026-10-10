class_name CollapseMode
extends BrushMode

## The Collapse preset's gestures on the play brush (EventPresets): hovering outlines the
## bridge under the pointer in madder with "Collapse plank bridge" beside it; a click on one
## fires a bridge collapse (TerrainEvent) for PlayEvents to start. Stepping stones and fords do
## not collapse; a click off any bridge says so through the brush's `refused`. Its rays see
## crossings, so a deck is picked where it is drawn, as the Bridge tool picks one.

## A click asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

const TINT := BrushCursor.CLEAR_TINT
const PICK_MARGIN_M := 0.35
const HINT := "Click a bridge"
const NOT_A_BRIDGE := "Only a bridge collapses"

## The crossing under the pointer (its id), or -1.
var hover_id: int = -1


func _init() -> void:
	sees_crossings = true
	fades = true


## The bridge (a deck crossing) under world point `hit` on `editor`'s map, or null.
static func bridge_at(editor: AuthoringEditor, hit: Vector3) -> Crossing:
	if editor == null or hit == Vector3.INF:
		return null
	var id := editor.crossings.crossing_at(hit, PICK_MARGIN_M)
	var crossing := editor.document.crossing(id) if id >= 0 else null
	return crossing if crossing != null and crossing.is_deck() else null


func frame(brush: BrushTool) -> void:
	hover_id = -1
	if brush.editor != null and brush.hit != Vector3.INF:
		hover_id = brush.editor.crossings.crossing_at(brush.hit, PICK_MARGIN_M)


func press(brush: BrushTool) -> bool:
	var crossing := bridge_at(brush.editor, brush.hit)
	if crossing == null:
		brush.refused.emit(TerrainEvents.NO_BRIDGE)
		return false
	var middle := (crossing.start + crossing.end) * 0.5
	fired.emit(TerrainEvent.bridge_collapse(crossing.id, middle, randi()))
	return false


func leave(_brush: BrushTool) -> void:
	hover_id = -1


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	var editor := brush.editor
	if editor == null:
		return
	var at := cursor.camera.unproject_position(brush.hit)
	var crossing := editor.document.crossing(hover_id) if hover_id >= 0 else null
	if crossing != null and crossing.is_deck():
		BridgeBrush.draw_crossing(cursor.canvas, cursor.camera, editor, crossing, TINT, 1.0)
		var label := "Collapse " + BridgeBrush.kind_label(crossing.kind).to_lower()
		BridgeBrush.draw_pill(cursor.canvas, at, label, BridgeBrush.REFUSED_COLOR)
		return
	cursor.draw_flat_ring(brush.hit, 0.4, TINT, 2.0)
	var text := NOT_A_BRIDGE if crossing != null else HINT
	BridgeBrush.draw_pill(cursor.canvas, at, text, BridgeBrush.READOUT_COLOR)
