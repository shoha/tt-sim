class_name BrushCursor
extends RefCounted

## BrushTool's cursor: the overlay it is drawn on and the drawing every mode shares. The
## current BrushMode draws the cursor (BrushMode.draw_cursor) with these helpers; the default
## is draw_ring().
##
## The ring lies on the ground at the hit point with the brush radius, conforming to the
## ground (one downward ray per ring point, cached until the brush moves; with `live`, the
## document's own heights every frame, since the ground under a still ring moves while
## sculpting). It is drawn on its own layer (OVERLAY_LAYER) so it stays crisp above the lo-fi
## pass: a dark under-stroke and a light over-stroke read on any ground in either lo-fi theme.
## That layer is under every panel and drawer: the ring belongs to the board, so the glass over
## the board covers it as it covers the ground (it was on the measure overlay, over the glass).
## The tint is the mode's (BrushMode.cursor_tint). The ring is an outline only: a fill, drawn on
## this 2D layer, veiled the tree crowns standing in front of the ground it covered (the 2a
## critic). An inner ring brightens as dwell builds strength, and a mode's readout
## (BrushMode.cursor_text) sits in a small pill under the ring. fan_indices() stays for the
## Bridge tool's stone ghosts, filled as fans because a conformed outline can cross itself.

## Above the world viewport (LAYER_WORLD_VIEWPORT), under the drawers and panels
## (LAYER_GAMEPLAY_MENU, LAYER_AUTHORING), with the hint bar.
const OVERLAY_LAYER := Constants.LAYER_INPUT_HINTS
const RING_SEGMENTS := 48
## Ring points re-conform to the ground when the centre moves this fraction of the radius.
const RING_REFRESH := 0.04
const DOWNCAST_HEIGHT := 200.0
const SHADOW_COLOR := Color(0.05, 0.04, 0.05, 0.55)
## The erase tint (Clear, a Paint or Water erase, a Place footing warning).
const CLEAR_TINT := Color(1.0, 0.52, 0.42)
## The glass accent: the brush is drawn over the live table, where ember is the action colour.
const PLACE_TINT := ThemeColors.EMBER
## The readout under the ring (MapOverlayUtils.create_label_panel's look, smaller: it
## accompanies the cursor rather than reporting a measurement).
const READOUT_FONT_SIZE := 13
const READOUT_COLOR := Color(1.0, 0.95, 0.6)
const READOUT_GAP_PX := 14.0

## The control the cursor is drawn on, and the camera that projects it.
var canvas: Control = null
var camera: Camera3D = null

var _world_viewport: SubViewport = null
var _canvas_layer: CanvasLayer = null
var _readout_box: StyleBoxFlat = null
var _ring_world := PackedVector3Array()
var _ring_centre: Vector3 = Vector3.INF
var _ring_radius: float = -1.0


## Triangle-fan indices filling a closed outline of `outline_count` points (the last one
## repeating the first, as the ring's do) around a centre vertex at index `outline_count`:
## drawn with explicit indices, so it never needs triangulating. Pure.
static func fan_indices(outline_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in outline_count - 1:
		indices.append_array([outline_count, i, i + 1])
	return indices


## Creates the overlay under `overlay_parent`, hidden; `on_draw` draws the cursor on `canvas`.
func setup(
	cam: Camera3D, viewport: SubViewport, overlay_parent: Node, on_draw: Callable
) -> void:
	camera = cam
	_world_viewport = viewport
	var overlay: Dictionary = MapOverlayUtils.create_overlay(
		overlay_parent, OVERLAY_LAYER, on_draw
	)
	_canvas_layer = overlay.canvas_layer
	canvas = overlay.draw_control
	_canvas_layer.visible = false


func set_visible(visible: bool) -> void:
	if _canvas_layer:
		_canvas_layer.visible = visible


func redraw() -> void:
	if canvas:
		canvas.queue_redraw()


## The brush ring at `brush.hit` with the stroke radius in `tint`, `text` under it when not
## "", conformed to the document's heights every frame when `live`.
func draw_ring(brush: BrushTool, tint: Color, text: String, live: bool) -> void:
	_conform_ring(brush, brush.hit, brush.mode.stroke_radius(brush), live)
	var outline := _project(_ring_world, Vector3.ZERO, 1.0)
	_stroke_ring(outline, tint, 2.0)
	if brush.stroking:
		# The half-strength contour, brightening as dwell builds strength.
		var strength := clampf(brush.dwell / BrushTool.DWELL_MAX, 0.0, 1.0)
		var inner := _project(_ring_world, brush.hit, 0.54)
		canvas.draw_polyline(inner, Color(tint, 0.25 + 0.6 * strength), 1.5, true)
	var centre := camera.unproject_position(brush.hit)
	canvas.draw_circle(centre, 2.5, SHADOW_COLOR)
	canvas.draw_circle(centre, 1.5, tint)
	if text != "":
		draw_readout(text, outline)


## Draws `text` in a small dark pill just below the lowest point of `outline` on screen.
func draw_readout(text: String, outline: PackedVector2Array) -> void:
	var font := canvas.get_theme_default_font()
	if font == null:
		return
	var bottom := -INF
	var centre_x := 0.0
	for point in outline:
		bottom = maxf(bottom, point.y)
		centre_x += point.x
	centre_x /= maxf(1.0, float(outline.size()))
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE)
	var pad := Vector2(7.0, 3.0)
	var box := Rect2(
		Vector2(centre_x - size.x * 0.5, bottom + READOUT_GAP_PX) - pad, size + pad * 2.0
	)
	if _readout_box == null:
		_readout_box = StyleBoxFlat.new()
		_readout_box.bg_color = Color(0.0, 0.0, 0.0, 0.6)
		_readout_box.set_corner_radius_all(4)
	canvas.draw_style_box(_readout_box, box)
	var baseline := box.position + pad + Vector2(0.0, font.get_ascent(READOUT_FONT_SIZE))
	canvas.draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE, READOUT_COLOR
	)


## A flat ring of world `radius` at `centre` (a prop's footprint or the Place marker).
func draw_flat_ring(centre: Vector3, radius: float, tint: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in RING_SEGMENTS + 1:
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		points.append(
			camera.unproject_position(
				centre + Vector3(cos(angle), 0.05, sin(angle)) * Vector3(radius, 1.0, radius)
			)
		)
	_stroke_ring(points, tint, width)


## Re-conforms the ring's world points to the ground when the brush moved or resized; with
## `live`, every frame from the document's heights (the ground moves under a still ring while
## sculpting, and the collision only catches up when the stroke ends).
func _conform_ring(brush: BrushTool, centre: Vector3, radius: float, live: bool) -> void:
	if live:
		_ring_world.resize(RING_SEGMENTS + 1)
		for i in RING_SEGMENTS + 1:
			var angle := TAU * float(i % RING_SEGMENTS) / float(RING_SEGMENTS)
			var point := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
			point.y = brush.editor.ground_height_at(point) + 0.05
			_ring_world[i] = point
		# Forces the cached path to re-conform when the tool changes.
		_ring_radius = -1.0
		return
	if (
		_ring_world.size() == RING_SEGMENTS + 1
		and is_equal_approx(radius, _ring_radius)
		and _ring_centre.distance_to(centre) < radius * RING_REFRESH
	):
		return
	_ring_centre = centre
	_ring_radius = radius
	_ring_world.resize(RING_SEGMENTS + 1)
	var space := _world_viewport.find_world_3d().direct_space_state
	for i in RING_SEGMENTS + 1:
		var angle := TAU * float(i % RING_SEGMENTS) / float(RING_SEGMENTS)
		var point := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var ground := DragPlaceController.raycast_terrain_down(
			space, point, centre.y + DOWNCAST_HEIGHT
		)
		_ring_world[i] = (ground if ground != Vector3.INF else point) + Vector3.UP * 0.05


## The ring's points on screen, scaled about `pivot` by `scale` (1: the ring itself).
func _project(points: PackedVector3Array, pivot: Vector3, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		var at := point if scale == 1.0 else pivot + (point - pivot) * scale
		out.append(camera.unproject_position(at))
	return out


func _stroke_ring(points: PackedVector2Array, tint: Color, width: float) -> void:
	canvas.draw_polyline(points, SHADOW_COLOR, width + 2.0, true)
	canvas.draw_polyline(points, tint, width, true)
