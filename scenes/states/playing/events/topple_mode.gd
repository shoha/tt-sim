class_name ToppleMode
extends BrushMode

## The Topple trees preset's gestures on the play brush (EventPresets): a click fires a forest
## fall (TerrainEvent) over the brush ring around it, the trees falling away from the click; a
## drag from the press widens the ring to the pointer (up to TerrainEvent.MAX_RADIUS_M) and
## fires on release. The ring is the presets' ochre (TINT, CollapseMode's outline too) with
## "Topple trees" under it in a glass chip; [ ] and Shift+wheel size it as for every brush.
## PlayEvents starts the event; a spot with no tree says why in a toast.
##
## The trees that will fall are marked as a forester marks them: a short ochre blaze across
## each trunk a little above its foot, for exactly the trees ForestFall takes there
## (ForestFall.trees_near, the nearest MAX_TREES), so the GM sees which go before clicking. A
## stroke up the trunk instead (the first look) ran up into the crowns as thin sticks. The
## search runs again when the ring moves or resizes by MARK_REFRESH_M, and every
## MARK_REFRESH_MS (a fallen stand's rebuild drops its marks).

## A click or drag asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

## The presets' cursor colour: warm ochre, "do" (UI_TASTE C5), on both presets since both undo.
const TINT := ThemeColors.OCHRE_LIGHT
## The pill's words, and the preset tile's label (EventPresets).
const TEXT := "Topple trees"
const MARK_REFRESH_M := 0.3
const MARK_REFRESH_MS := 500
## A blaze sits this share of the tree's height up its trunk (about breast height on a
## 10 m tree), and is this long and thick on screen.
const MARK_HEIGHT := 0.12
const MARK_LENGTH_PX := 11.0
const MARK_PX := 3.5

## A press is held: the event's centre (world) and how far the drag has reached from it.
var dragging: bool = false
var centre: Vector3 = Vector3.INF
var reach: float = 0.0

## The marked trunks (world: the blaze, then a point above it on the trunk, per tree) and
## where they were found.
var _marks := PackedVector3Array()
var _marked_at: Vector3 = Vector3.INF
var _marked_radius: float = -1.0
var _marked_msec: int = 0


func _init() -> void:
	fades = true


## The trunk marks (world points in pairs: a tree's blaze, MARK_HEIGHT up its trunk, then a
## point higher up the trunk that gives the trunk's direction on screen) of the trees a fall at
## world point `at` with world radius `radius` fells on `editor`'s map.
static func trunk_marks(editor: AuthoringEditor, at: Vector3, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if editor == null or editor.scatter == null or at == Vector3.INF:
		return out
	var scale := maxf(editor.map_scale(), 0.001)
	for tree in ForestFall.trees_near(editor.scatter, editor.to_map_xz(at), radius / scale):
		var node := tree.node as MultiMeshInstance3D
		if not is_instance_valid(node) or node.multimesh == null or node.multimesh.mesh == null:
			continue
		var box := node.multimesh.mesh.get_aabb()
		var local := tree.base as Transform3D
		var blaze := Vector3(0.0, box.position.y + box.size.y * MARK_HEIGHT, 0.0)
		var above := blaze + Vector3(0.0, box.size.y * MARK_HEIGHT, 0.0)
		out.append(node.global_transform * (local * blaze))
		out.append(node.global_transform * (local * above))
	return out


## The ring's radius: the brush size, or the drag's reach past it.
func stroke_radius(brush: BrushTool) -> float:
	return maxf(brush.get_radius(), reach) if dragging else brush.get_radius()


## The marked trunks, as last found (trunk_marks).
func marks() -> PackedVector3Array:
	return _marks


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
	_refresh_marks(brush)


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
	_marks = PackedVector3Array()
	_marked_at = Vector3.INF


func fade_focus(brush: BrushTool) -> Vector4:
	var at := centre if dragging else brush.hit
	return Vector4(at.x, at.y, at.z, stroke_radius(brush))


func cursor_tint(_brush: BrushTool) -> Color:
	return TINT


func cursor_text(_brush: BrushTool) -> String:
	return TEXT


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	_draw_marks(cursor)
	if not dragging:
		cursor.draw_ring(brush, TINT, TEXT, false)
		return
	cursor.draw_flat_ring(centre, stroke_radius(brush), TINT, 2.0)
	var at := cursor.camera.unproject_position(centre)
	cursor.canvas.draw_circle(at, 2.5, BrushCursor.SHADOW_COLOR)
	cursor.canvas.draw_circle(at, 1.5, TINT)


## An ochre blaze across each marked trunk, over a dark keyline as the ring has.
func _draw_marks(cursor: BrushCursor) -> void:
	for i in range(0, _marks.size() - 1, 2):
		if cursor.camera.is_position_behind(_marks[i]):
			continue
		var at := cursor.camera.unproject_position(_marks[i])
		var up := cursor.camera.unproject_position(_marks[i + 1]) - at
		var across := Vector2(-up.y, up.x).normalized() * MARK_LENGTH_PX * 0.5
		if across == Vector2.ZERO:
			across = Vector2(MARK_LENGTH_PX * 0.5, 0.0)
		var keyline := across.normalized() * (MARK_LENGTH_PX * 0.5 + 1.0)
		cursor.canvas.draw_line(at - keyline, at + keyline, BrushCursor.SHADOW_COLOR, MARK_PX + 2.0)
		cursor.canvas.draw_line(at - across, at + across, TINT, MARK_PX)


## Finds the marked trunks again when the ring moved or resized past MARK_REFRESH_M, or the
## last search is older than MARK_REFRESH_MS.
func _refresh_marks(brush: BrushTool) -> void:
	var at := centre if dragging else brush.hit
	if brush.editor == null or at == Vector3.INF:
		_marks = PackedVector3Array()
		_marked_at = Vector3.INF
		return
	var radius := stroke_radius(brush)
	var now := Time.get_ticks_msec()
	if (
		_marked_at != Vector3.INF
		and at.distance_to(_marked_at) < MARK_REFRESH_M
		and absf(radius - _marked_radius) < MARK_REFRESH_M
		and now - _marked_msec < MARK_REFRESH_MS
	):
		return
	_marked_at = at
	_marked_radius = radius
	_marked_msec = now
	_marks = trunk_marks(brush.editor, at, radius)


static func _scale(brush: BrushTool) -> float:
	return brush.editor.map_scale() if brush.editor != null else 1.0
