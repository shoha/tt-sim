class_name TokenEdgeArrows
extends Control

## The eye view's off-screen token indicator (card eyepin, an option, off by default): a token
## that is out of frame gets a coloured chevron on the screen edge that points toward it, with
## the distance in metres. A token ahead and off to one side lies on the line from the screen
## centre through where it would be; one behind the eye points to the side it is on (turn that
## way, Q or E), at the height its direction has in the view. Nothing is drawn for a token that
## is in frame (the model, its ghost or the far pin shows it). Owned by TokenMarkers
## (`eye_arrows`), which hands over the tokens' colours; the local view only, nothing is synced.

## How far the chevron's tip stands inside the screen edge, viewport pixels.
const MARGIN_PX := 36.0
## The chevron's length and half width.
const LENGTH_PX := 26.0
const HALF_WIDTH_PX := 17.0
const OUTLINE_PX := 3.0
const LABEL_SIZE := 16

## Set by the owner: Camera3D, and Callable(token) -> Color for a token's colour.
var camera: Camera3D = null
var colour_of: Callable = Callable()
## This frame's arrows: {"pos": Vector2, "dir": Vector2, "colour": Color, "metres": float}.
var _arrows: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Where the chevron for a point at `local` (camera space: x right, y up, -z ahead) goes, or an
## empty Dictionary when the point is in frame. `screen` is the point's screen position
## (viewport px) when it is ahead of the camera, else ignored; `size` the viewport size;
## `margin` the inset of the tip. The result has "pos" (the tip, on the inset rectangle) and
## "dir" (unit, screen space, y down).
static func place(
	local: Vector3, screen: Vector2, size: Vector2, margin: float = MARGIN_PX
) -> Dictionary:
	var centre := size * 0.5
	var behind := local.z >= 0.0
	var dir: Vector2
	if behind:
		# Toward the side it is on, at the height its direction has: a point right behind goes right.
		var side := 1.0 if local.x >= 0.0 else -1.0
		dir = Vector2(side, -local.y / maxf(local.length(), 0.001)).normalized()
	else:
		if Rect2(Vector2.ONE * margin, size - Vector2.ONE * margin * 2.0).has_point(screen):
			return {}
		dir = (screen - centre).normalized()
		if dir == Vector2.ZERO:
			return {}
	var half := centre - Vector2.ONE * margin
	var scale_x := half.x / absf(dir.x) if absf(dir.x) > 0.0001 else INF
	var scale_y := half.y / absf(dir.y) if absf(dir.y) > 0.0001 else INF
	return {"pos": centre + dir * minf(scale_x, scale_y), "dir": dir}


## The chevron's three corners for a tip at `pos` pointing along `dir`.
static func chevron(pos: Vector2, dir: Vector2) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	var back := pos - dir * LENGTH_PX
	return PackedVector2Array([pos, back + side * HALF_WIDTH_PX, back - side * HALF_WIDTH_PX])


## The distance label, whole metres.
static func label_of(metres: float) -> String:
	return "%d m" % int(round(metres))


func _process(_delta: float) -> void:
	_arrows.clear()
	if camera != null and is_instance_valid(camera):
		var size := Vector2(camera.get_viewport().size)
		var inverse := camera.global_transform.affine_inverse()
		for node in get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
			var token := node as BoardToken
			if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
				continue
			if not token.rigid_body.visible or not token.is_visible_to_players:
				continue
			var head := token.rigid_body.global_position + Vector3.UP * 0.9
			var local := inverse * head
			var screen := Vector2.ZERO
			if local.z < 0.0:
				screen = camera.unproject_position(head)
			var placed := place(local, screen, size)
			if placed.is_empty():
				continue
			placed["colour"] = colour_of.call(token) if colour_of.is_valid() else Color.WHITE
			placed["metres"] = local.length()
			_arrows.append(placed)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for arrow in _arrows:
		var pos: Vector2 = arrow.pos
		var dir: Vector2 = arrow.dir
		var corners := chevron(pos, dir)
		var colour: Color = arrow.colour
		var closed := corners + PackedVector2Array([corners[0]])
		draw_colored_polygon(corners, Color(colour, 0.95))
		draw_polyline(closed, Color(0.08, 0.07, 0.1, 0.85), OUTLINE_PX, true)
		var text := label_of(arrow.metres)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var at := pos - dir * (LENGTH_PX + 12.0) - Vector2(width * 0.5, -LABEL_SIZE * 0.35)
		var align := HORIZONTAL_ALIGNMENT_LEFT
		var ink := Color(0.08, 0.07, 0.1, 0.9)
		draw_string_outline(font, at, text, align, -1, LABEL_SIZE, 5, ink)
		draw_string(font, at, text, align, -1, LABEL_SIZE, Color(1, 1, 1, 0.97))
