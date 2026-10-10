class_name CollapseMode
extends BrushMode

## The Drop bridge preset's gestures on the play brush (EventPresets): hovering outlines the
## bridge under the pointer in the presets' ochre (TINT, ToppleMode's ring colour: both events
## undo, so neither wears the danger confirm's madder, UI_TASTE C5), a thin chalk edge just
## inside the ochre (EDGE: the ochre alone vanished over a warm plank deck in daylight), and
## "Drop bridge" in a glass chip under the outline's lowest point, as Topple's chip sits under
## its ring; a click on one fires a bridge collapse (TerrainEvent) for PlayEvents to start.
## Stepping stones and fords do not fall: hovering one draws the small ring in chalk_soft
## (REFUSED_TINT, "is", since a click does nothing there) and says so, and a click off any
## bridge says so through the brush's `refused`. Its rays see crossings, so a deck is picked
## where it is drawn, as the Bridge tool picks one.

## A click asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

const TINT := ToppleMode.TINT
## The outline's inner edge: chalk, this far inside the deck's sides and this thick, which
## holds over 3:1 against a sunlit plank deck where the ochre alone did not.
const EDGE := ThemeColors.CHALK
const EDGE_INSET_M := 0.1
const EDGE_PX := 1.25
## The small ring's colour over a crossing that does not fall (cool: it only says what is).
const REFUSED_TINT := ThemeColors.CHALK_SOFT
const RING_M := 0.4
const RING_SEGMENTS := 24
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


## The small ring's colour over `crossing` (null: off any crossing): the presets' ochre, or
## REFUSED_TINT over a crossing that does not fall. Pure.
static func ring_tint(crossing: Crossing) -> Color:
	return REFUSED_TINT if crossing != null and not crossing.is_deck() else TINT


## The deck of `crossing` outlined on screen through `camera`, its sides `inset_m` inside the
## deck's edges, along its arch (BridgeBrush.draw_crossing's outline at inset 0), closed.
static func deck_outline(
	camera: Camera3D, editor: AuthoringEditor, crossing: Crossing, inset_m: float
) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var span := crossing.span_m()
	if span <= 0.0:
		return outline
	var half := maxf(crossing.width_m * 0.5 - inset_m, 0.0)
	var pieces := maxi(2, ceili(span / BridgeBrush.OUTLINE_STEP_M))
	var back := PackedVector2Array()
	for k in pieces + 1:
		var t := float(k) / pieces
		var u := lerpf(inset_m, span - inset_m, t)
		var y := CrossingGeometry.deck_y(crossing.levels, u / span)
		var left := CrossingGeometry.point(crossing, u, half, y)
		var right := CrossingGeometry.point(crossing, u, -half, y)
		outline.append(camera.unproject_position(editor.to_world(left)))
		back.append(camera.unproject_position(editor.to_world(right)))
	back.reverse()
	outline.append_array(back)
	outline.append(outline[0])
	return outline


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
	var crossing := editor.document.crossing(hover_id) if hover_id >= 0 else null
	if crossing != null and crossing.is_deck():
		BridgeBrush.draw_crossing(cursor.canvas, cursor.camera, editor, crossing, TINT, 1.0)
		var edge := deck_outline(cursor.camera, editor, crossing, EDGE_INSET_M)
		cursor.canvas.draw_polyline(edge, EDGE, EDGE_PX, true)
		cursor.draw_readout(DROP, deck_outline(cursor.camera, editor, crossing, 0.0))
		return
	if brush.hit == Vector3.INF:
		return
	var ring := _ring(cursor.camera, brush.hit)
	var tint := ring_tint(crossing)
	cursor.canvas.draw_polyline(ring, BrushCursor.SHADOW_COLOR, 4.0, true)
	cursor.canvas.draw_polyline(ring, tint, 2.0, true)
	cursor.draw_readout(pill_text(crossing), ring)


## A flat ring of RING_M round world point `at`, on screen (BrushCursor.draw_flat_ring's).
static func _ring(camera: Camera3D, at: Vector3) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in RING_SEGMENTS + 1:
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		var offset := Vector3(cos(angle) * RING_M, 0.05, sin(angle) * RING_M)
		points.append(camera.unproject_position(at + offset))
	return points
