class_name ToppleMode
extends BrushMode

## The Topple preset's gestures on the play brush (EventPresets): a click fires a forest fall
## (TerrainEvent) over the brush ring around it, the trees falling away from the click; a drag
## from the press widens the ring to the pointer (up to TerrainEvent.MAX_RADIUS_M) and fires
## on release. The ring is warm ochre with "Topple trees" under it; [ ] and Shift+wheel size
## it as for every brush. PlayEvents starts the event; a spot with no tree says why in a toast.

## A click or drag asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

const TINT := Color(1.0, 0.8, 0.46)
const TEXT := "Topple trees"

## A press is held: the event's centre (world) and how far the drag has reached from it.
var dragging: bool = false
var centre: Vector3 = Vector3.INF
var reach: float = 0.0


func _init() -> void:
	fades = true


## The ring's radius: the brush size, or the drag's reach past it.
func stroke_radius(brush: BrushTool) -> float:
	return maxf(brush.get_radius(), reach) if dragging else brush.get_radius()


func press(brush: BrushTool) -> bool:
	dragging = true
	centre = brush.hit
	reach = 0.0
	return false


func frame(brush: BrushTool) -> void:
	if dragging and brush.hit != Vector3.INF:
		var flat := Vector2(brush.hit.x - centre.x, brush.hit.z - centre.z)
		var most := TerrainEvent.MAX_RADIUS_M * _scale(brush)
		reach = minf(flat.length(), most)


func end(brush: BrushTool) -> void:
	if not dragging:
		return
	dragging = false
	if brush.editor == null or centre == Vector3.INF:
		return
	var editor := brush.editor
	var radius := maxf(brush.get_radius(), reach) / _scale(brush)
	fired.emit(TerrainEvent.forest_fall(editor.to_map_xz(centre), radius, randi()))
	reach = 0.0


func cancel(_brush: BrushTool) -> void:
	dragging = false
	reach = 0.0


func leave(brush: BrushTool) -> void:
	cancel(brush)


func fade_focus(brush: BrushTool) -> Vector4:
	var at := centre if dragging else brush.hit
	return Vector4(at.x, at.y, at.z, stroke_radius(brush))


func cursor_tint(_brush: BrushTool) -> Color:
	return TINT


func cursor_text(_brush: BrushTool) -> String:
	return TEXT


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if not dragging:
		cursor.draw_ring(brush, TINT, TEXT, false)
		return
	cursor.draw_flat_ring(centre, stroke_radius(brush), TINT, 2.0)
	var at := cursor.camera.unproject_position(centre)
	cursor.canvas.draw_circle(at, 2.5, BrushCursor.SHADOW_COLOR)
	cursor.canvas.draw_circle(at, 1.5, TINT)


static func _scale(brush: BrushTool) -> float:
	return brush.editor.map_scale() if brush.editor != null else 1.0
