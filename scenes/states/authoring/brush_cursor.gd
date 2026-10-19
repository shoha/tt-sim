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
## pass: a dark under-stroke and a light over-stroke read on any ground in either lo-fi theme
## (the erase ring on the stronger ink every erase line shares, ring_strokes()).
## That layer is under every panel and drawer: the ring belongs to the board, so the glass over
## the board covers it as it covers the ground (it was on the measure overlay, over the glass).
## The tint is the mode's (BrushMode.cursor_tint). The ring is an outline only: a fill, drawn on
## this 2D layer, veiled the tree crowns standing in front of the ground it covered (the 2a
## critic). An inner ring brightens as dwell builds strength, and a mode's readout
## (BrushMode.cursor_text) sits in a glass chip under the ring. fan_indices() stays for the
## Bridge tool's stone ghosts, filled as fans because a conformed outline can cross itself.
## Under the canvas's own drawing lies a glow layer (glow_item()), blended premultiplied, where
## a fill lit by LineRibbon.lit_fill() adds light as well as covering (every line tool's ribbon
## fills there; the fire line's glows over green and a dark wood instead of greying); it is
## cleared at every
## drawing of the cursor, so what a mode lays there lasts one drawing as its lines do.

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
## Every erase line (the erase ring, a line tool's erase edge; its chevrons are the lay's, on the
## lay's ink, F5g): the salmon this
## wide over INK at this alpha and width, so it holds 3:1 over a pale wash, water and bright
## flames alike (at the shadow's 0.55, or 0.7, the salmon sank into a salmon wash and fell
## under 3:1 over flames; card F5f).
const ERASE_INK_ALPHA := 0.85
const ERASE_INK_WIDTH := 5.5
const ERASE_LINE_WIDTH := 2.5
## The glass accent: the brush is drawn over the live table, where ember is the action colour.
const PLACE_TINT := ThemeColors.EMBER
## The readout under the ring: a glass chip as the rulers' (MapOverlayUtils.draw_chip), this
## far below the ring's lowest point.
const READOUT_GAP_PX := 14.0

## The control the cursor is drawn on, and the camera that projects it.
var canvas: Control = null
var camera: Camera3D = null

var _world_viewport: SubViewport = null
var _canvas_layer: CanvasLayer = null
var _glow_layer: Control = null
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
		overlay_parent, OVERLAY_LAYER, _on_canvas_draw.bind(on_draw)
	)
	_canvas_layer = overlay.canvas_layer
	canvas = overlay.draw_control
	_glow_layer = Control.new()
	_glow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.show_behind_parent = true
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_glow_layer.material = blend
	canvas.add_child(_glow_layer)
	_canvas_layer.visible = false


## The glow layer's canvas item (the class header), or an invalid RID before setup().
func glow_item() -> RID:
	return _glow_layer.get_canvas_item() if _glow_layer else RID()


func set_visible(visible: bool) -> void:
	if _canvas_layer:
		_canvas_layer.visible = visible


func redraw() -> void:
	if canvas:
		canvas.queue_redraw()


## Every drawing of the canvas: the glow layer cleared, then the cursor drawn (`on_draw`).
func _on_canvas_draw(on_draw: Callable) -> void:
	if _glow_layer:
		RenderingServer.canvas_item_clear(_glow_layer.get_canvas_item())
	on_draw.call()


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


## Draws `text` in a glass chip (MapOverlayUtils.draw_chip: the hint bar's plum glass, chalk
## caption 14) just below the lowest point of `outline` on screen. The dark film it replaced
## took the board's colour (olive over leaves) and its 13 px text was under the caption floor.
func draw_readout(text: String, outline: PackedVector2Array) -> void:
	if text == "" or outline.is_empty():
		return
	var bottom := -INF
	var centre_x := 0.0
	for point in outline:
		bottom = maxf(bottom, point.y)
		centre_x += point.x
	centre_x /= float(outline.size())
	var size := MapOverlayUtils.chip_size(canvas, text)
	MapOverlayUtils.draw_chip(
		canvas, Vector2(centre_x - size.x * 0.5, bottom + READOUT_GAP_PX - 4.0), text
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
	for stroke: Array in ring_strokes(tint, width):
		canvas.draw_polyline(points, stroke[0], stroke[1], true)


## A ring's strokes in `tint` at `width` px, under to over: [colour, width] each. The erase
## tint draws as every erase line does (the edge of a line tool's erase ribbon,
## LineRibbon.ERASE_STYLE): ERASE_LINE_WIDTH over the erase's ink; any other tint over the
## shadow. Pure.
static func ring_strokes(tint: Color, width: float) -> Array:
	if tint == CLEAR_TINT:
		var ink := ThemeColors.INK
		ink.a = ERASE_INK_ALPHA
		return [[ink, ERASE_INK_WIDTH], [tint, ERASE_LINE_WIDTH]]
	return [[SHADOW_COLOR, width + 2.0], [tint, width]]
