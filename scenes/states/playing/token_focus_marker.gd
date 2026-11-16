class_name TokenFocusMarker
extends Control

## Shows a token the roster picked or is pointing at, on top of the board: a chalk ring on the
## ground around it and the token's portrait on a pin above it, each with an ink outline.
##
## The glow on the token itself (add_highlight) is a thin amber ring on the ground that a tree,
## a wall or a bright meadow hides (about 1.2:1 against grass), so this draws in screen space, in
## front of the world: the ring and the pin cannot be covered by what stands between the camera
## and the token, and the ink band under the chalk keeps 3:1 against any board. The pin is the
## same picture as the map pin (TokenPictures) and is drawn whatever the "Token pins" setting
## says, because the player just asked where this token is. Nothing here is saved or synced and it
## never takes the pointer. It lies under the drawers (the host puts it first among its siblings).
##
## A short ping (a ring that widens and fades) marks the moment a row is picked; Reduce motion
## drops it. A token off screen shows its pin held at the nearest edge.

const RING_POINTS := 56
## The ring's chalk and ink widths, in canvas units.
const CHALK_PX := 3.5
const INK_PX := 8.0
const HEAD_RADIUS := 22.0
const HEAD_GAP := 14.0
## The portrait fills the pin's inner disc (the chalk rim is 3 px of the head's 22 px radius).
const PICTURE_RADIUS := 19.0
const PICTURE_POINTS := 40
const EDGE_MARGIN := 34.0
const PING_S := 0.7

## Where the portraits come from; the roster sets it.
var pictures: TokenPictures = null

var _selected: BoardToken = null
var _hovered: BoardToken = null
var _ping_left: float = 0.0
var _extents: Dictionary = {}  ## instance id -> {"base", "top", "radius"} relative to the body


func _ready() -> void:
	name = "TokenFocusMarker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


## The token the roster picked (null for none). A new pick starts the ping.
func set_selected(token: BoardToken) -> void:
	if token != _selected and token != null:
		_ping_left = 0.0 if UiMotion.reduced() else PING_S
	_selected = token
	_refresh_state()


## The token under a roster row's pointer or focus (null for none).
func set_hovered(token: BoardToken) -> void:
	_hovered = token
	_refresh_state()


## Whether `token` is marked now (selected or hovered).
func is_marking(token: BoardToken) -> bool:
	return token != null and (token == _selected or token == _hovered)


## The ring's radius in metres for a footprint of `radius`: a little wider than the token so the
## chalk lies on the ground around it. Pure.
static func ring_radius(radius: float) -> float:
	return maxf(radius, 0.3) * 1.2 + 0.12


## The pin head's centre for a token whose top projects to `top` on a canvas of `canvas`: above
## the token, held inside the canvas (EDGE_MARGIN) so a token off screen still shows its pin at
## the nearest edge. Pure.
static func head_position(top: Vector2, canvas: Vector2) -> Vector2:
	var head := top + Vector2(0.0, -(HEAD_RADIUS + HEAD_GAP))
	return Vector2(
		clampf(head.x, EDGE_MARGIN, maxf(EDGE_MARGIN, canvas.x - EDGE_MARGIN)),
		clampf(head.y, EDGE_MARGIN, maxf(EDGE_MARGIN, canvas.y - EDGE_MARGIN))
	)


func _refresh_state() -> void:
	if _live(_selected):
		_extents.erase(_selected.get_instance_id())
	if _live(_hovered):
		_extents.erase(_hovered.get_instance_id())
	var any := _live(_selected) or _live(_hovered)
	set_process(any)
	visible = any
	queue_redraw()


## Whether `token` (possibly freed since it was set) can be drawn.
func _live(token: Variant) -> bool:
	return is_instance_valid(token) and (token as BoardToken).rigid_body != null


func _process(delta: float) -> void:
	if not _live(_selected):
		_selected = null
	if not _live(_hovered):
		_hovered = null
	if _selected == null and _hovered == null:
		_refresh_state()
		return
	_ping_left = maxf(0.0, _ping_left - delta)
	queue_redraw()


func _draw() -> void:
	if _live(_selected):
		_draw_token(_selected)
	if _live(_hovered) and _hovered != _selected:
		_draw_token(_hovered)


func _draw_token(token: BoardToken) -> void:
	var camera := token.get_viewport().get_camera_3d()
	if camera == null:
		return
	var extent := _extent_of(token)
	var body := token.rigid_body.global_position
	var ink := ThemeColors.of(self, ThemeColors.SURFACE)
	ink.a = 0.95
	var chalk := ThemeColors.of(self, ThemeColors.TEXT)
	var ground := body + Vector3.UP * (float(extent["base"]) + 0.02)
	var radius := ring_radius(float(extent["radius"]))
	var ring := _ring_points(camera, ground, radius)
	if ring.size() > 2:
		draw_polyline(ring, ink, INK_PX, true)
		draw_polyline(ring, chalk, CHALK_PX, true)
		if _ping_left > 0.0 and token == _selected:
			var t := 1.0 - _ping_left / PING_S
			var wide := _ring_points(camera, ground, radius * (1.0 + t * 0.9))
			var fade := chalk
			fade.a = 1.0 - t
			if wide.size() > 2:
				draw_polyline(wide, fade, CHALK_PX, true)
	var top_world := body + Vector3.UP * float(extent["top"])
	if camera.is_position_behind(top_world):
		return
	var top := camera.unproject_position(top_world)
	var head := head_position(top, size)
	var held := head.is_equal_approx(top + Vector2(0.0, -(HEAD_RADIUS + HEAD_GAP)))
	_draw_pin(token, head, top if held else Vector2.INF, ink, chalk)


## The ring around `centre` on the ground, projected; empty when part of it is behind the camera.
func _ring_points(camera: Camera3D, centre: Vector3, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in RING_POINTS + 1:
		var angle := TAU * float(i) / float(RING_POINTS)
		var world := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if camera.is_position_behind(world):
			return PackedVector2Array()
		points.append(camera.unproject_position(world))
	return points


## The pin: an ink-outlined chalk disc holding the portrait, with a tail to the token's top
## (`tip`; INF when the pin is held at the edge and has no token to point at).
func _draw_pin(token: BoardToken, head: Vector2, tip: Vector2, ink: Color, chalk: Color) -> void:
	if tip.is_finite():
		var tail := PackedVector2Array(
			[head + Vector2(-9.0, HEAD_RADIUS - 4.0), head + Vector2(9.0, HEAD_RADIUS - 4.0), tip]
		)
		draw_colored_polygon(tail, chalk)
		draw_polyline(
			PackedVector2Array([tail[0], tail[2], tail[1]]), ink, 3.0, true
		)
	draw_circle(head, HEAD_RADIUS + 3.0, ink)
	draw_circle(head, HEAD_RADIUS, chalk)
	var fill := ink
	fill.a = 1.0
	draw_circle(head, HEAD_RADIUS - 3.0, fill)
	if pictures == null:
		return
	# texture_for asks for the picture the first time; the pin then fills the whole inner disc
	# with the tight crop (a textured circle, so a square picture needs no mask).
	var ready := pictures.texture_for(token) != null
	var uv := pictures.uv_rect_of(token)
	if not ready or uv.size == Vector2.ZERO:
		return
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in PICTURE_POINTS:
		var unit := Vector2.from_angle(TAU * float(i) / float(PICTURE_POINTS))
		points.append(head + unit * PICTURE_RADIUS)
		uvs.append(uv.get_center() + unit * uv.size * 0.5)
	draw_colored_polygon(points, Color.WHITE, uvs, pictures.atlas())


## The token's footprint relative to its body: the ground (`base`) and top heights in metres and
## the horizontal radius, from its meshes, read when the token is marked (set_selected and
## set_hovered forget the last reading).
func _extent_of(token: BoardToken) -> Dictionary:
	var id := token.get_instance_id()
	if _extents.has(id):
		return _extents[id]
	var found := false
	var box := AABB()
	for mesh_instance in TokenGhost.meshes_of(token.rigid_body):
		if not mesh_instance.is_inside_tree():
			continue
		var world_box := mesh_instance.global_transform * mesh_instance.get_aabb()
		box = world_box if not found else box.merge(world_box)
		found = true
	var origin := token.rigid_body.global_position
	var extent := {"base": 0.0, "top": 1.0, "radius": 0.4}
	if found:
		extent = {
			"base": box.position.y - origin.y,
			"top": box.end.y - origin.y,
			"radius": maxf(box.size.x, box.size.z) * 0.5,
		}
	_extents[id] = extent
	return extent
