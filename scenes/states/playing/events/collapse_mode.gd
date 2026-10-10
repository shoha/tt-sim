class_name CollapseMode
extends BrushMode

## The Drop bridge preset's gestures on the play brush (EventPresets): hovering outlines the
## bridge under the pointer in the presets' ochre (TINT, ToppleMode's ring colour: both events
## undo, so neither wears the danger confirm's madder, UI_TASTE C5) with "Drop bridge" beside
## it in a glass chip; a click on one fires a bridge collapse (TerrainEvent) for PlayEvents to
## start. Stepping stones and fords do not fall; hovering one says so, and a click off any
## bridge says so through the brush's `refused`. Its rays see crossings, so a deck is picked
## where it is drawn, as the Bridge tool picks one.

## A click asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

const TINT := ToppleMode.TINT
const PICK_MARGIN_M := 0.35
const HINT := "Click a bridge"
## The pill's words over a bridge, and the preset tile's label (EventPresets).
const DROP := "Drop bridge"
const NOT_A_BRIDGE := "Only a bridge falls"

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


## The cursor pill's words over `crossing` (null: off any crossing). Pure.
static func pill_text(crossing: Crossing) -> String:
	if crossing == null:
		return HINT
	return DROP if crossing.is_deck() else NOT_A_BRIDGE


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
	else:
		cursor.draw_flat_ring(brush.hit, 0.4, TINT, 2.0)
	BridgeBrush.draw_pill(cursor.canvas, at, pill_text(crossing))
