class_name IgniteMode
extends ToppleMode

## The Start a fire preset's gestures on the play brush (EventPresets): Topple's ring and
## gestures (a click fires over the brush ring around it, a drag from the press widens the
## ring up to TerrainEvent.MAX_RADIUS_M and fires on release; [ ] and Shift+wheel size it),
## firing a fire (TerrainEvent.fire) that spreads out from the click. The ring is the presets'
## ochre with "Start a fire" under it in a glass chip, and no marks: the whole forest in the
## ring burns, not a counted set of trees.
##
## Only a forest burns: the ring searches for trees as Topple's marks do (the burnt forest's
## own snags passed over, FireSweep.burnable), and where none stands it is drawn in chalk_soft
## (CollapseMode.REFUSED_TINT: a click does nothing there) with "Only a forest burns" in its
## chip, and a click there says so through the brush's `refused` instead of firing.

## The pill's words, and the preset tile's label (EventPresets). (ToppleMode's TEXT is the
## parent's, so this one has a name of its own.)
const IGNITE_TEXT := "Start a fire"
const NOT_A_FOREST := "Only a forest burns"


## The ring's colour and words while the ring holds a forest (`has_forest`) or not. Pure.
static func ring_look(has_forest: bool) -> Dictionary:
	if has_forest:
		return {"tint": TINT, "text": IGNITE_TEXT}
	return {"tint": CollapseMode.REFUSED_TINT, "text": NOT_A_FOREST}


func end(brush: BrushTool) -> void:
	if not dragging:
		return
	dragging = false
	if brush.editor == null or centre == Vector3.INF:
		return
	var editor := brush.editor
	var radius := maxf(brush.get_radius(), reach) / _scale(brush)
	reach = 0.0
	var at := editor.to_map_xz(centre)
	if FireSweep.burnable(editor.scatter, at, radius, editor.palette_root, 1).is_empty():
		brush.refused.emit(TerrainEvents.NO_FOREST)
		return
	fired.emit(TerrainEvent.fire(at, radius, randi()))


func cursor_tint(_brush: BrushTool) -> Color:
	return ring_look(not marks().is_empty()).tint


func cursor_text(_brush: BrushTool) -> String:
	return ring_look(not marks().is_empty()).text


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	var look := ring_look(not marks().is_empty())
	if not dragging:
		cursor.draw_ring(brush, look.tint, look.text, false)
		return
	cursor.draw_flat_ring(centre, stroke_radius(brush), look.tint, 2.0)
	var at := cursor.camera.unproject_position(centre)
	cursor.canvas.draw_circle(at, 2.5, BrushCursor.SHADOW_COLOR)
	cursor.canvas.draw_circle(at, 1.5, look.tint)


## The trees a fire at world point `at` with world radius `radius` burns, as Topple's marks
## (never drawn: they say only whether a forest stands in the ring).
func _find_marks(editor: AuthoringEditor, at: Vector3, radius: float) -> PackedVector4Array:
	if editor == null:
		return PackedVector4Array()
	var burnt := FireSweep.burnt_biome(editor.palette_root)
	return base_marks(editor, at, radius, burnt + "/" if burnt != "" else "")
