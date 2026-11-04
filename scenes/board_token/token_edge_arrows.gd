class_name TokenEdgeArrows
extends Control

## The eye view's off-screen token indicator (card eyepin, 2026-11-04): a token that is out of
## frame gets a coloured chevron on the screen edge that points toward it, with the distance in
## metres. A token ahead and off to one side lies on the line from the screen centre through where
## it would be; one behind the eye points to the side it is on (turn that way, Q or E), at the
## height its direction has in the view. Nothing is drawn for a token that is in frame (the model,
## its ghost or the far pin shows it) or nearer than the far pin's fade-out distance
## (TokenMarkers.eye_pin_fade): the arrow fades in over the same 9 to 18 m as the pin does.
##
## Stacking: tokens in nearly the same direction land on nearly the same spot of the edge, so the
## arrows fan out along it. The edge is one loop (the inset screen rectangle, measured from the
## bottom centre, clockwise); arrows closer than SPACING_PX along it form a run that is spread
## SPACING_PX apart, centred on where the run's members wanted to be, nearest in front. A run
## of more than FAN_MAX shows its FAN_MAX nearest, and the nearest carries a "+N" badge for the
## rest. Each chevron keeps pointing at its own token.
##
## Pointer: the arrow under the pointer is drawn last, a little larger, and is a click target:
## TokenMarkers turns the eye toward that token (CameraController `_turn_toward`). The sizes below
## are in screen pixels: the world viewport's pixels follow the window through the canvas_items
## stretch (a half-size window is half the pixels), so every size is multiplied by `ui_unit`
## and an arrow is as big in a 1280x720 window as in a 1920x1080 one. Owned by TokenMarkers
## (`eye_arrows`), which hands over the tokens' colours and the pointer; the local view only,
## nothing is synced.

## How far the chevron's tip stands inside the screen edge, screen pixels.
const MARGIN_PX := 32.0
## The chevron's length and half width.
const LENGTH_PX := 50.0
const HALF_WIDTH_PX := 34.0
const OUTLINE_PX := 4.0
const LABEL_SIZE := 24
const BADGE_SIZE := 20
## How far apart stacked arrows stand along the edge (a little more than a chevron is wide).
const SPACING_PX := 88.0
## The most arrows one run shows; the rest are a "+N" on the nearest.
const FAN_MAX := 3
## The hovered arrow is this much larger, about its tip.
const HOVER_SCALE := 1.15
## An arrow takes hover and clicks once its fade has brought it to this alpha.
const HIT_MIN_ALPHA := 0.5

## Set by the owner: Camera3D, and Callable(token) -> Color for a token's colour.
var camera: Camera3D = null
var colour_of: Callable = Callable()
## The pointer in viewport pixels, or null when it is not free to hover (outside the window, over
## interface or holding a token). Set by the owner each frame.
var pointer: Variant = null
## Viewport pixels per screen pixel (see `ui_unit`), read each frame.
var unit: float = 1.0
## This frame's arrows in draw order, far first:
## {"pos": Vector2, "dir": Vector2, "colour": Color, "metres": float, "id": int, "extra": int}.
var _arrows: Array[Dictionary] = []
## Index into `_arrows` of the arrow under the pointer, -1 for none.
var _hovered: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- pure rules ---


## How many viewport pixels one screen pixel is under the canvas_items stretch with the "expand"
## aspect: the design size over the window's, by the smaller ratio (1 at the design size, 2 in a
## half-size window). Clamped so a degenerate window cannot make an absurd arrow.
static func ui_unit(window_px: Vector2, design_px: Vector2) -> float:
	var scale := minf(window_px.x / maxf(design_px.x, 1.0), window_px.y / maxf(design_px.y, 1.0))
	return 1.0 / clampf(scale, 0.25, 4.0)


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


## The length of the edge loop (the inset rectangle's perimeter).
static func loop_length(size: Vector2, margin: float = MARGIN_PX) -> float:
	return 2.0 * ((size.x - 2.0 * margin) + (size.y - 2.0 * margin))


## How far along the edge loop the point `pos` (on the inset rectangle) is: 0 at the bottom
## centre, then clockwise on screen (up the left side, along the top, down the right side).
static func edge_param(pos: Vector2, size: Vector2, margin: float = MARGIN_PX) -> float:
	var left := margin
	var right := size.x - margin
	var top := margin
	var bottom := size.y - margin
	var w := right - left
	var h := bottom - top
	var d_left := absf(pos.x - left)
	var d_top := absf(pos.y - top)
	var d_right := absf(pos.x - right)
	var d_bottom := absf(pos.y - bottom)
	var nearest := minf(minf(d_left, d_top), minf(d_right, d_bottom))
	if nearest == d_left:
		return w * 0.5 + (bottom - pos.y)
	if nearest == d_top:
		return w * 0.5 + h + (pos.x - left)
	if nearest == d_right:
		return w * 0.5 + h + w + (pos.y - top)
	var cx := size.x * 0.5
	return cx - pos.x if pos.x <= cx else loop_length(size, margin) - (pos.x - cx)


## The point `s` along the edge loop (the inverse of `edge_param`; wraps around).
static func edge_point(s: float, size: Vector2, margin: float = MARGIN_PX) -> Vector2:
	var left := margin
	var right := size.x - margin
	var top := margin
	var bottom := size.y - margin
	var w := right - left
	var h := bottom - top
	var d := fposmod(s, loop_length(size, margin))
	if d <= w * 0.5:
		return Vector2(size.x * 0.5 - d, bottom)
	d -= w * 0.5
	if d <= h:
		return Vector2(left, bottom - d)
	d -= h
	if d <= w:
		return Vector2(left + d, top)
	d -= w
	if d <= h:
		return Vector2(right, top + d)
	d -= h
	return Vector2(right - d, bottom)


## `arrows` ({"pos", "dir", "metres", ...} as `place` made them, with any extra keys) spread so
## no two stand closer than `spacing` along the edge, in draw order (far first, so the nearest
## token's arrow lies on top). A run of more than `fan_max` keeps its `fan_max` nearest and the
## nearest gets "extra", how many were left out (0 for the rest).
static func stack(
	arrows: Array[Dictionary],
	size: Vector2,
	margin: float = MARGIN_PX,
	spacing: float = SPACING_PX,
	fan_max: int = FAN_MAX
) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for arrow in arrows:
		var item := arrow.duplicate()
		item["s"] = edge_param(arrow["pos"], size, margin)
		item["extra"] = 0
		items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])
	# Runs of arrows that overlap, merged until they do not (a run's centre is the mean of where
	# its members wanted to be).
	var runs: Array[Dictionary] = []
	for item in items:
		runs.append({"items": [item], "sum": float(item["s"])})
		while runs.size() > 1:
			var prev: Dictionary = runs[runs.size() - 2]
			if not _runs_overlap(prev, runs[runs.size() - 1], spacing, fan_max):
				break
			var last: Dictionary = runs.pop_back()
			prev = runs[runs.size() - 1]
			(prev["items"] as Array).append_array(last["items"])
			prev["sum"] = float(prev["sum"]) + float(last["sum"])
	var out: Array[Dictionary] = []
	for run in runs:
		var members: Array = run["items"]
		var centre := float(run["sum"]) / members.size()
		var left_out := maxi(members.size() - fan_max, 0)
		if left_out > 0:
			members = _nearest(members, fan_max)
			var front: Dictionary = members[0]
			for member: Dictionary in members:
				if float(member["metres"]) < float(front["metres"]):
					front = member
			front["extra"] = left_out
		for k in members.size():
			var member: Dictionary = members[k]
			var s := centre + (float(k) - float(members.size() - 1) * 0.5) * spacing
			member["pos"] = edge_point(s, size, margin)
			out.append(member)
	out.sort_custom(_farther)
	return out


## Whether `next` (the run after `prev` along the edge) lies closer than `spacing` to it.
static func _runs_overlap(prev: Dictionary, next: Dictionary, spacing: float, fan_max: int) -> bool:
	var prev_n := mini((prev["items"] as Array).size(), fan_max)
	var next_n := mini((next["items"] as Array).size(), fan_max)
	var prev_c := float(prev["sum"]) / (prev["items"] as Array).size()
	var next_c := float(next["sum"]) / (next["items"] as Array).size()
	var prev_hi := prev_c + float(prev_n - 1) * 0.5 * spacing
	var next_lo := next_c - float(next_n - 1) * 0.5 * spacing
	return next_lo - prev_hi < spacing - 0.001


static func _farther(a: Dictionary, b: Dictionary) -> bool:
	return a["metres"] > b["metres"]


static func _nearer(a: Dictionary, b: Dictionary) -> bool:
	return a["metres"] < b["metres"]


## The `count` entries of `members` (in edge order) with the smallest "metres", in edge order.
static func _nearest(members: Array, count: int) -> Array:
	var by_distance := members.duplicate()
	by_distance.sort_custom(_nearer)
	var keep := by_distance.slice(0, count)
	var out: Array = []
	for member in members:
		if keep.has(member):
			out.append(member)
	return out


## The chevron's three corners for a tip at `pos` pointing along `dir`, `grow` times the size.
static func chevron(pos: Vector2, dir: Vector2, grow: float = 1.0) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	var back := pos - dir * LENGTH_PX * grow
	return PackedVector2Array(
		[pos, back + side * HALF_WIDTH_PX * grow, back - side * HALF_WIDTH_PX * grow]
	)


## The click target of an arrow at `pos` pointing along `dir`: the chevron's middle and a radius
## that covers its body.
static func hit_circle(pos: Vector2, dir: Vector2, grow: float = 1.0) -> Dictionary:
	return {"centre": pos - dir * LENGTH_PX * 0.5 * grow, "radius": HALF_WIDTH_PX * 0.9 * grow}


## The index in `arrows` of the arrow whose hit circle (at `grow` times the size) holds `point`,
## the nearest centre when several do, or -1.
static func pick(arrows: Array[Dictionary], point: Vector2, grow: float = 1.0) -> int:
	var best := -1
	var best_d2 := INF
	for i in arrows.size():
		var circle := hit_circle(arrows[i]["pos"], arrows[i]["dir"], grow)
		var d2 := (circle["centre"] as Vector2).distance_squared_to(point)
		var r: float = circle["radius"]
		if d2 <= r * r and d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## The distance label, whole metres.
static func label_of(metres: float) -> String:
	return "%d m" % int(round(metres))


# --- per frame ---


func _process(_delta: float) -> void:
	_arrows.clear()
	_hovered = -1
	if camera != null and is_instance_valid(camera):
		var size := Vector2(camera.get_viewport().size)
		var root := get_tree().root
		unit = ui_unit(Vector2(root.size), Vector2(root.content_scale_size))
		var raw := _raw_arrows(size)
		_arrows = stack(raw, size, MARGIN_PX * unit, SPACING_PX * unit)
		if pointer != null:
			var hittable: Array[Dictionary] = []
			var index: Array[int] = []
			for i in _arrows.size():
				if float(_arrows[i]["alpha"]) >= HIT_MIN_ALPHA:
					hittable.append(_arrows[i])
					index.append(i)
			var picked := pick(hittable, pointer, unit)
			_hovered = index[picked] if picked >= 0 else -1
	queue_redraw()


## The token an arrow press at `point` hits, or null.
func token_at(point: Vector2) -> BoardToken:
	var hittable: Array[Dictionary] = []
	for arrow in _arrows:
		if float(arrow["alpha"]) >= HIT_MIN_ALPHA:
			hittable.append(arrow)
	var i := pick(hittable, point, unit)
	if i < 0:
		return null
	var token := instance_from_id(int(hittable[i]["id"])) as BoardToken
	return token if token != null and is_instance_valid(token) else null


## The arrows of this frame before stacking: one per token out of frame and far enough for the
## pin's fade to have begun.
func _raw_arrows(size: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inverse := camera.global_transform.affine_inverse()
	for node in get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
			continue
		if not token.rigid_body.visible or not token.is_visible_to_players:
			continue
		var head := token.rigid_body.global_position + Vector3.UP * 0.9
		var local := inverse * head
		var alpha := TokenMarkers.eye_pin_fade(local.length())
		if alpha <= 0.0:
			continue
		var screen := Vector2.ZERO
		if local.z < 0.0:
			screen = camera.unproject_position(head)
		var placed := place(local, screen, size, MARGIN_PX * unit)
		if placed.is_empty():
			continue
		placed["colour"] = colour_of.call(token) if colour_of.is_valid() else Color.WHITE
		placed["metres"] = local.length()
		placed["alpha"] = alpha
		placed["id"] = token.get_instance_id()
		out.append(placed)
	return out


func _draw() -> void:
	# The hovered arrow last, in front of the rest.
	for i in _arrows.size():
		if i != _hovered:
			_draw_arrow(_arrows[i], unit)
	if _hovered >= 0:
		_draw_arrow(_arrows[_hovered], unit * HOVER_SCALE, true)


## One arrow at `grow` times its screen-pixel size (the viewport pixels per screen pixel, times
## HOVER_SCALE for the hovered one).
func _draw_arrow(arrow: Dictionary, grow: float, hover: bool = false) -> void:
	var font := ThemeDB.fallback_font
	var pos: Vector2 = arrow["pos"]
	var dir: Vector2 = arrow["dir"]
	var alpha: float = arrow["alpha"]
	var corners := chevron(pos, dir, grow)
	var colour: Color = arrow["colour"]
	if hover:
		colour = colour.lightened(0.2)
	var closed := corners + PackedVector2Array([corners[0]])
	draw_colored_polygon(corners, Color(colour, 0.96 * alpha))
	draw_polyline(closed, Color(0.08, 0.07, 0.1, 0.9 * alpha), OUTLINE_PX * grow, true)
	# The label stands inboard of the chevron's base, clear of it whichever edge it is on.
	var text := label_of(arrow["metres"])
	var label_size := roundi(LABEL_SIZE * grow)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size)
	var inboard := LENGTH_PX * grow + 10.0 * grow
	inboard += absf(dir.x) * extent.x * 0.5 + absf(dir.y) * extent.y * 0.5
	var centre := pos - dir * inboard
	var at := centre - Vector2(extent.x * 0.5, -extent.y * 0.28)
	var ink := Color(0.08, 0.07, 0.1, 0.92 * alpha)
	var outline := roundi(7.0 * grow)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, outline, ink)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(1, 1, 1, alpha))
	var extra: int = arrow["extra"]
	if extra > 0:
		var badge := "+%d" % extra
		var badge_px := roundi(BADGE_SIZE * grow)
		var badge_size := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_px)
		var badge_at := pos - dir * LENGTH_PX * 0.62 * grow
		draw_circle(badge_at, 17.0 * grow, Color(0.08, 0.07, 0.1, 0.92 * alpha))
		var text_at := badge_at - Vector2(badge_size.x * 0.5, -badge_size.y * 0.28)
		draw_string(
			font, text_at, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_px, Color(1, 1, 1, alpha)
		)
