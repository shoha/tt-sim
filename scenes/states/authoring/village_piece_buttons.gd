class_name VillagePieceButtons
extends Control

## The Swap, Back and Remove buttons beside a picked village furnishing (topic villages5,
## docs/systems/villages.md section 14): the pane's three piece buttons again, where the eye
## already is. Each is a glass pill in the cursor's own language (MapOverlayUtils.draw_chip at
## VillageProps.PILL_PX), a constant size on screen whatever the zoom, set in a row just outside
## the piece and its ring: below it first, then above, right or left, the first that fits on the
## board an open drawer leaves free; never off the screen, and never over the piece when the
## screen has room. They are real buttons on the cursor's overlay, so a click on one is the GUI's
## and never reaches the brush: it cannot also move, pick or let go of the piece.
##
## VillageBrush owns one, places it every frame (place) and hides it while nothing is picked, while
## a press is held, and when the tool is put down. What a button does is the brush's (`acted`).

## A button was pressed: SWAP, BACK or REMOVE.
signal acted(action: StringName)

const SWAP := &"swap"
const BACK := &"back"
const REMOVE := &"remove"
## The words on each pill and its tooltip.
const WORDS := {SWAP: "Swap", BACK: "Back", REMOVE: "Remove"}
const TIPS := {
	SWAP: "Swap this piece for another that belongs in this kind of place",
	BACK: "Send this piece back to the spot the village's own rules give it",
	REMOVE: "Take this piece away (Delete)",
}
## The row stands this far outside the piece and its ring, its pills this far apart, and this far
## inside the free board's edges (the bottom keeps clear of the hint bar).
const GAP_PX := 10.0
const SPACING_PX := 6.0
const MARGIN_PX := 8.0
const BOTTOM_RESERVE_PX := 64.0

## The pills by action (PiecePill nodes named PieceSwap, PieceBack, PieceRemove).
var pills: Dictionary = {}
## Local bounds of each prop variant's mesh, by variant ref (the piece's screen box comes from it).
var _bounds_of: Dictionary = {}


## One pill: a flat button with no theme drawing of its own that draws a glass chip, its words
## turning gold under the pointer and while pressed.
class PiecePill:
	extends Button

	var words: String = ""

	func _init(action: StringName) -> void:
		name = "Piece" + str(WORDS[action]).capitalize()
		words = WORDS[action]
		tooltip_text = TIPS[action]
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	## The pill's size on screen.
	func chip() -> Vector2:
		return MapOverlayUtils.chip_size(self, words, VillageProps.PILL_PX)

	func _draw() -> void:
		var lit := is_hovered() or button_pressed
		var ink := VillageRings.READOUT_COLOR if lit else Color.TRANSPARENT
		MapOverlayUtils.draw_chip(self, Vector2.ZERO, words, ink, VillageProps.PILL_PX)


func _init() -> void:
	name = "VillagePieceButtons"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action: StringName in [SWAP, BACK, REMOVE]:
		var pill := PiecePill.new(action)
		pill.pressed.connect(acted.emit.bind(action))
		pills[action] = pill
		add_child(pill)
	visible = false


## The buttons the picked piece offers, in order, from VillageProps.pane_state: a field's piece
## only Remove; Swap when another prop belongs there; Back when it is pinned.
static func actions_for(state: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if not bool(state.get("picked", false)):
		return out
	if not bool(state.get("field", false)):
		if bool(state.get("swappable", false)):
			out.append(SWAP)
		if bool(state.get("pinned", false)):
			out.append(BACK)
	out.append(REMOVE)
	return out


## Where the pills of sizes `sizes` stand (one Rect2 each, left to right) beside `subject`, the
## screen box of the piece and its ring, inside `bounds`, the free board. Below the subject, above
## it, right of it, left of it: the first row that lies wholly inside `bounds` and clear of
## `subject` once slid along its side to fit. When none does, the row below, pushed inside.
static func layout(subject: Rect2, sizes: Array[Vector2], bounds: Rect2) -> Array[Rect2]:
	var row := Vector2(0.0, 0.0)
	for size in sizes:
		row.x += size.x
		row.y = maxf(row.y, size.y)
	row.x += SPACING_PX * maxf(sizes.size() - 1, 0)
	var inner := bounds.grow(-MARGIN_PX)
	var mid := subject.get_center()
	var tries: Array[Vector2] = [
		Vector2(mid.x - row.x * 0.5, subject.end.y + GAP_PX),
		Vector2(mid.x - row.x * 0.5, subject.position.y - GAP_PX - row.y),
		Vector2(subject.end.x + GAP_PX, mid.y - row.y * 0.5),
		Vector2(subject.position.x - GAP_PX - row.x, mid.y - row.y * 0.5),
	]
	var at := _inside(tries[0], row, inner)
	for k in tries.size():
		var slid := tries[k]
		if k < 2:
			slid.x = _slide(slid.x, row.x, inner.position.x, inner.end.x)
		else:
			slid.y = _slide(slid.y, row.y, inner.position.y, inner.end.y)
		var box := Rect2(slid, row)
		if inner.encloses(box) and not box.intersects(subject):
			at = slid
			break
	var out: Array[Rect2] = []
	var x := at.x
	for size in sizes:
		out.append(Rect2(Vector2(x, at.y + (row.y - size.y) * 0.5), size))
		x += size.x + SPACING_PX
	return out


## Whether the row shows for a piece whose screen box is `subject` on free board `bounds`: only
## while some of the piece is on the board (pills pinned to a screen corner for a piece out of
## sight would name nothing the author can see).
static func shows(subject: Rect2, bounds: Rect2) -> bool:
	return subject.size != Vector2.ZERO and bounds.intersects(subject)


static func _slide(start: float, length: float, low: float, high: float) -> float:
	return maxf(minf(start, high - length), low)


static func _inside(at: Vector2, size: Vector2, inner: Rect2) -> Vector2:
	return Vector2(
		_slide(at.x, size.x, inner.position.x, inner.end.x),
		_slide(at.y, size.y, inner.position.y, inner.end.y)
	)


## The free board on this control's screen: right of an open drawer, above the hint bar.
func board() -> Rect2:
	var view := get_viewport_rect().size
	var span := DrawerContainer.free_span(get_viewport())
	return Rect2(span.x, 0.0, span.y - span.x, view.y - BOTTOM_RESERVE_PX)


## Shows `actions` beside picked row `row` (VillageProps.picked_row) of `editor`'s map, seen by
## `camera`, its ring `ring_m` metres round; hides them when the piece is behind the camera.
func place(
	camera: Camera3D,
	editor: AuthoringEditor,
	row: Dictionary,
	ring_m: float,
	actions: Array[StringName]
) -> void:
	var subject := _subject(camera, editor, row, ring_m)
	var free := board()
	if actions.is_empty() or not shows(subject, free):
		hide_all()
		return
	var sizes: Array[Vector2] = []
	for action in actions:
		sizes.append((pills[action] as PiecePill).chip())
	var rects := layout(subject, sizes, free)
	for action: StringName in pills:
		var pill: PiecePill = pills[action]
		var k := actions.find(action)
		pill.visible = k >= 0
		if k >= 0:
			pill.position = rects[k].position
			pill.size = rects[k].size
	visible = true


func hide_all() -> void:
	visible = false


## The screen box of the piece (its mesh's bounds) and its ring; zero when it is behind the camera.
func _subject(
	camera: Camera3D, editor: AuthoringEditor, row: Dictionary, ring_m: float
) -> Rect2:
	if camera == null or editor == null or row.is_empty():
		return Rect2()
	var layer := VillageProps.layer_of(editor)
	var item: Dictionary = row["item"]
	var at: Vector2 = item["position"]
	var foot := editor.to_world(Vector3(at.x, float(row["y"]), at.y))
	if camera.is_position_behind(foot):
		return Rect2()
	var points := PackedVector2Array()
	for k in 12:
		var p := at + Vector2.from_angle(TAU * k / 12.0) * ring_m
		var ground := WaterGeometry.ground_at(editor.document, p)
		points.append(camera.unproject_position(editor.to_world(Vector3(p.x, ground, p.y))))
	if layer != null:
		var local := _mesh_bounds(layer, str(row.get("ref", "")))
		var place_at := layer.global_transform * SettlementBake.transform_of(
			item, float(row["y"]), row.get("normal", Vector3.UP)
		)
		for k in 8:
			var corner := place_at * local.get_endpoint(k)
			if not camera.is_position_behind(corner):
				points.append(camera.unproject_position(corner))
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


func _mesh_bounds(layer: AuthoredSettlements, ref: String) -> AABB:
	if _bounds_of.has(ref):
		return _bounds_of[ref]
	var out := AABB()
	var first := true
	if ref != "":
		for surface: Dictionary in layer.variant(ref).get("surfaces", []):
			var arrays: Array = surface["arrays"]
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				if first:
					out = AABB(vertex, Vector3.ZERO)
					first = false
				else:
					out = out.expand(vertex)
	_bounds_of[ref] = out
	return out
