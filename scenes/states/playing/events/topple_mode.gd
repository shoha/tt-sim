class_name ToppleMode
extends BrushMode

## The Topple trees preset's gestures on the play brush (EventPresets): a click fires a forest
## fall (TerrainEvent) over the brush ring around it, the trees falling away from the click; a
## drag from the press widens the ring to the pointer (up to TerrainEvent.MAX_RADIUS_M) and
## fires on release. The ring is the presets' ochre (TINT, CollapseMode's outline too) with
## "Topple trees" under it in a glass chip; [ ] and Shift+wheel size it as for every brush.
## PlayEvents starts the event; a spot with no tree says why in a toast.
##
## The trees that will fall are marked at their feet: a small ochre spot on the ground round
## each trunk's base, inside the ring, for exactly the trees ForestFall takes there
## (ForestFall.trees_near, the nearest MAX_TREES), so the GM sees which go before clicking. A
## spot grows with its tree (BASE_SHARE of its height), between BASE_MIN_PX and BASE_MAX_PX
## across. A blaze across the trunk a little above its foot (the second look) floated over
## the undergrowth where no trunk showed, and on a trunk standing near the ring's far edge it
## sat above the ring; a stroke up the trunk (the first) ran into the crowns as thin sticks.
## The search runs again when the ring moves or resizes by MARK_REFRESH_M, and every
## MARK_REFRESH_MS (a fallen stand's rebuild drops its marks).

## A click or drag asked for this event (PlayEvents starts it on the table's TerrainEvents).
signal fired(event: TerrainEvent)

## The presets' cursor colour: warm ochre, "do" (UI_TASTE C5), on both presets since both undo.
const TINT := ThemeColors.OCHRE_LIGHT
## The pill's words, and the preset tile's label (EventPresets).
const TEXT := "Topple trees"
const MARK_REFRESH_M := 0.3
const MARK_REFRESH_MS := 500
## A tree's ground spot: its radius against the tree's height (0.3 m round a 10 m tree), its
## least and greatest width on screen (at 4 % a tall tree's spot read as a plate), how many
## points draw it, and its fill's opacity under the rim.
const BASE_SHARE := 0.03
const BASE_MIN_PX := 9.0
const BASE_MAX_PX := 36.0
const BASE_SEGMENTS := 20
const BASE_FILL_ALPHA := 0.4

## A press is held: the event's centre (world) and how far the drag has reached from it.
var dragging: bool = false
var centre: Vector3 = Vector3.INF
var reach: float = 0.0

## The marked trees (base_marks: each base, world, and its spot's radius) and where they were
## found.
var _marks := PackedVector4Array()
var _marked_at: Vector3 = Vector3.INF
var _marked_radius: float = -1.0
var _marked_msec: int = 0


func _init() -> void:
	fades = true


## The ground marks of the trees a fall at world point `at` with world radius `radius` fells
## on `editor`'s map, one per tree: its base (world, xyz) and its spot's world radius (w,
## BASE_SHARE of the tree's height). Assets whose id starts with `skip` are passed over
## (ForestFall.trees_near).
static func base_marks(
	editor: AuthoringEditor, at: Vector3, radius: float, skip: String = ""
) -> PackedVector4Array:
	var out := PackedVector4Array()
	if editor == null or editor.scatter == null or at == Vector3.INF:
		return out
	var scale := maxf(editor.map_scale(), 0.001)
	var centre := editor.to_map_xz(at)
	var limit := ForestFall.MAX_TREES
	for tree in ForestFall.trees_near(editor.scatter, centre, radius / scale, limit, skip):
		var node := tree.node as MultiMeshInstance3D
		if not is_instance_valid(node) or node.multimesh == null or node.multimesh.mesh == null:
			continue
		var box := node.multimesh.mesh.get_aabb()
		var placed := node.global_transform * (tree.base as Transform3D)
		var base := placed.origin
		var height := (placed.basis * Vector3(0.0, box.size.y, 0.0)).length()
		out.append(Vector4(base.x, base.y, base.z, height * BASE_SHARE))
	return out


## The ring's radius: the brush size, or the drag's reach past it.
func stroke_radius(brush: BrushTool) -> float:
	return maxf(brush.get_radius(), reach) if dragging else brush.get_radius()


## The marked trees, as last found (base_marks).
func marks() -> PackedVector4Array:
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
	_marks = PackedVector4Array()
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


## An ochre spot on the ground round each marked tree's base: a soft fill under a rim, over a
## dark keyline as the ring has, lying flat as the ring does.
func _draw_marks(cursor: BrushCursor) -> void:
	var camera := cursor.camera
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var ahead := right.cross(Vector3.UP)
	for mark in _marks:
		var base := Vector3(mark.x, mark.y, mark.z)
		if camera.is_position_behind(base):
			continue
		var at := camera.unproject_position(base)
		var across := camera.unproject_position(base + right * mark.w) - at
		var deep := camera.unproject_position(base + ahead * mark.w) - at
		var wide := maxf(across.length() * 2.0, 0.01)
		var grow := clampf(wide, BASE_MIN_PX, BASE_MAX_PX) / wide
		var fill := PackedVector2Array()
		for i in BASE_SEGMENTS:
			var angle := TAU * float(i) / float(BASE_SEGMENTS)
			fill.append(at + (across * cos(angle) + deep * sin(angle)) * grow)
		var outline := fill.duplicate()
		outline.append(fill[0])
		cursor.canvas.draw_colored_polygon(fill, Color(TINT, BASE_FILL_ALPHA))
		cursor.canvas.draw_polyline(outline, BrushCursor.SHADOW_COLOR, 3.5, true)
		cursor.canvas.draw_polyline(outline, TINT, 1.75, true)


## Finds the marked trees again when the ring moved or resized past MARK_REFRESH_M, or the
## last search is older than MARK_REFRESH_MS.
func _refresh_marks(brush: BrushTool) -> void:
	var at := centre if dragging else brush.hit
	if brush.editor == null or at == Vector3.INF:
		_marks = PackedVector4Array()
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
	_marks = _find_marks(brush.editor, at, radius)


## The trees a click at world point `at` with world radius `radius` takes (base_marks).
func _find_marks(editor: AuthoringEditor, at: Vector3, radius: float) -> PackedVector4Array:
	return base_marks(editor, at, radius)


static func _scale(brush: BrushTool) -> float:
	return brush.editor.map_scale() if brush.editor != null else 1.0
