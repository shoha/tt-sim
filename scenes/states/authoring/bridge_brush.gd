class_name BridgeBrush
extends RefCounted

## The Bridge tool's half of BrushTool (phase 4b, P4b-2): the drawn line, its live preview,
## the refusal hint, the Ctrl erase hover and the width a Shift+wheel sets. BrushTool owns one
## (`BrushTool.bridge`), routes the Bridge mode's press, frames, release and cancel to it and
## emits `bridge_refused` with the reasons it gives. Where a crossing goes is
## CrossingPlacement's rule and what an edit does is CrossingEditor's
## (`AuthoringEditor.crossings`); this only wires the gesture to them.
##
## Gesture. A press on the map starts a line; every frame the pointer moves at least
## REPLAN_M the crossing it would make is planned again (CrossingEditor.plan, which changes
## nothing) and drawn as a ghost: the deck's outline along its arch with plank ticks, or the
## stones' outlines, and a dot at each bank anchor. A line that makes no crossing is drawn red
## with the reason in plain words beside the cursor (refusal_text()). The release places the
## last plan as one history entry; a refused release says why in a toast. Ctrl at the press
## erases the crossing under the pointer (hovering with Ctrl held outlines it in red first).
## RMB or Escape drops a line being drawn.

const TINT := Color(0.98, 0.84, 0.58)
const STONE_TINT := Color(0.88, 0.9, 0.86)
const ERASE_TINT := Color(1.0, 0.52, 0.42)
const SHADOW := Color(0.05, 0.04, 0.05, 0.55)
const KIND_LABELS: Array[String] = ["Plank bridge", "Stepping stones"]
## The pointer's ground point moves this far (metres) before the preview is planned again.
const REPLAN_M := 0.08
## Width change per Shift+wheel notch or bracket key (multiplicative, like the brush size).
const WIDTH_STEP := 1.12
## Deck outline resolution along the span, and the plank ticks' spacing on the ghost.
const OUTLINE_STEP_M := 0.4
const TICK_M := 0.8
## The drawn line (screen pixels): dash width (heavier when refused), dash length, and the
## dark keyline's margin each side.
const LINE_PX := 2.5
const LINE_REFUSED_PX := 3.5
const LINE_DASH_PX := 10.0
const LINE_KEY_PX := 1.5
## Hover reach of the Ctrl erase around a crossing's footprint (world metres).
const PICK_MARGIN_M := 0.35
const READOUT_FONT_SIZE := 13
const READOUT_COLOR := Color(1.0, 0.95, 0.6)
const REFUSED_COLOR := Color(1.0, 0.72, 0.62)
## Plain-words reasons a line makes no crossing (refusal_text()).
const SHORT := "Drag a line from one bank across the water to the other."
const NO_WATER := "No water to cross here. Drag from bank to bank over a river or pond."
const NO_BANK := "No dry bank to land on at one end. Try a narrower spot."
const FALL := "Too close to the waterfall. Bridges cross calm water."
const LONG := "Too wide to cross (at most %s). Try a narrower spot."
const FULL := "The map holds as many crossings as it can. Remove one to make room."
const INVALID := "A crossing cannot stand there."
const NOTHING := "There is no crossing here to remove."

static var _pill_box: StyleBoxFlat = null

## The tile picked (Crossing.Kind).
var kind: int = Crossing.Kind.PLANK
## The width per kind (metres): the deck's width, or a stone's typical size.
var widths: Array[float] = [Crossing.DEFAULT_WIDTH_M[0], Crossing.DEFAULT_WIDTH_M[1]]
## A line being drawn: its press point (world) and the pointer's last ground point.
var drawing: bool = false
var from: Vector3 = Vector3.INF
var to: Vector3 = Vector3.INF
## The crossing the line makes now (map frame; null when refused), and why not (a
## CrossingPlacement or CrossingEditor refusal, or &"").
var preview: Crossing = null
var refusal: StringName = &""
## The crossing under the pointer while Ctrl is held (its id), or -1.
var hover_id: int = -1
## Microseconds of the last plan (the preview's cost per pointer move), for measurement.
var last_plan_usec: int = 0

var _planned_to: Vector3 = Vector3.INF
var _message: String = ""


## The reason a line makes no crossing, in plain words for the hint beside the cursor and the
## toast (`reason`: CrossingPlacement.REFUSED_* or CrossingEditor.REFUSED_*; "" for none). The
## span limit is given in the level's units. Pure.
static func refusal_text(
	reason: StringName, cell_m: float, per_cell: float, label: String
) -> String:
	match reason:
		CrossingPlacement.REFUSED_SHORT:
			return SHORT
		CrossingPlacement.REFUSED_NO_WATER:
			return NO_WATER
		CrossingPlacement.REFUSED_NO_BANK:
			return NO_BANK
		CrossingPlacement.REFUSED_FALL:
			return FALL
		CrossingPlacement.REFUSED_LONG:
			var limit := roundi(ScaleUtils.world_to_display(Crossing.MAX_SPAN_M, cell_m, per_cell))
			return LONG % ("%d %s" % [limit, label])
		CrossingEditor.REFUSED_FULL:
			return FULL
		CrossingEditor.REFUSED_INVALID:
			return INVALID
	return ""


## The toast when an edit took `removed` crossings with their water (CrossingEditor.followed),
## or "" for none. Pure.
static func followed_text(removed: int) -> String:
	if removed <= 0:
		return ""
	if removed == 1:
		return "A crossing lost its water and was removed. Undo brings both back."
	return "%d crossings lost their water and were removed. Undo brings them back." % removed


## `width` stepped `steps` notches (positive widens) within kind `crossing_kind`'s range. Pure.
static func stepped_width(width: float, steps: int, crossing_kind: int) -> float:
	return clampf(
		width * pow(WIDTH_STEP, steps),
		Crossing.MIN_WIDTH_M[crossing_kind],
		Crossing.MAX_WIDTH_M[crossing_kind]
	)


## The readout beside the cursor: the kind, and the span of the planned crossing while a line
## is drawn ("Plank bridge  20 ft"), else its width ("Plank bridge  5 ft wide"). Pure.
static func readout(
	crossing_kind: int, span_m: float, width_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := KIND_LABELS[clampi(crossing_kind, 0, KIND_LABELS.size() - 1)]
	if span_m > 0.0:
		var span := roundi(ScaleUtils.world_to_display(span_m, cell_m, per_cell))
		return "%s  %d %s" % [title, span, label]
	var wide := ScaleUtils.world_to_display(width_m, cell_m, per_cell)
	return "%s  %s %s wide" % [title, _short_number(wide), label]


## `value` to the nearest half ("5", "3.5"; whole from 10 up).
static func _short_number(value: float) -> String:
	var half := roundf(value * 2.0) * 0.5
	if value >= 10.0:
		return "%d" % roundi(value)
	if is_equal_approx(half, roundf(half)):
		return "%d" % roundi(half)
	return "%.1f" % half


## The picked kind's width (metres).
func width() -> float:
	return widths[kind]


## Steps the picked kind's width `steps` notches (Shift+wheel, [ and ]).
func step_width(steps: int) -> void:
	widths[kind] = stepped_width(widths[kind], steps, kind)
	_planned_to = Vector3.INF


## Starts a line at world point `hit`.
func begin(hit: Vector3) -> void:
	drawing = true
	from = hit
	to = hit
	preview = null
	refusal = CrossingPlacement.REFUSED_SHORT
	_planned_to = Vector3.INF
	hover_id = -1


## One frame with the pointer's ground point at `hit` (INF: none): while drawing, the line's
## end follows it and the preview is planned again once it moved REPLAN_M; with `erasing`
## (Ctrl held, not drawing) the crossing under it is looked up for the hover outline.
func track(editor: AuthoringEditor, hit: Vector3, erasing: bool) -> void:
	if editor == null:
		return
	if drawing:
		if hit != Vector3.INF:
			to = hit
		if _planned_to == Vector3.INF or _planned_to.distance_to(to) >= REPLAN_M:
			_plan(editor)
		return
	hover_id = (
		editor.crossings.crossing_at(hit, PICK_MARGIN_M) if erasing and hit != Vector3.INF else -1
	)


func _plan(editor: AuthoringEditor) -> void:
	var started := Time.get_ticks_usec()
	preview = editor.crossings.plan(kind as Crossing.Kind, from, to, width())
	refusal = editor.crossings.last_refusal
	last_plan_usec = Time.get_ticks_usec() - started
	_planned_to = to


## Places the line being drawn (the release): the crossing's id, or -1 with message() saying
## why in plain words. Plans once more first unless the preview is of the final pointer.
func finish(editor: AuthoringEditor, cell_m: float, per_cell: float, label: String) -> int:
	_message = ""
	if not drawing:
		return -1
	drawing = false
	if _planned_to != to or to == from:
		_plan(editor)
	var placed := -1
	if preview != null:
		placed = editor.crossings.add(preview)
		if placed < 0:
			refusal = editor.crossings.last_refusal
	if placed < 0:
		_message = refusal_text(refusal, cell_m, per_cell, label)
	preview = null
	return placed


## Erases the crossing under world point `hit` (a Ctrl press). False, with message() set,
## when there is none.
func erase_at(editor: AuthoringEditor, hit: Vector3) -> bool:
	_message = ""
	var crossing_id := editor.crossings.crossing_at(hit, PICK_MARGIN_M)
	if crossing_id < 0 or not editor.crossings.remove(crossing_id):
		_message = NOTHING
		return false
	hover_id = -1
	return true


## Why the last finish() or erase_at() made nothing, or "".
func message() -> String:
	return _message


## Drops a line being drawn (a cancel, or after a release).
func reset() -> void:
	drawing = false
	preview = null
	refusal = &""
	_planned_to = Vector3.INF


# ============================================================================
# Drawing
# ============================================================================


## The cursor and previews on `canvas` (see the header), for the pointer's ground point `hit`
## with Ctrl `erasing`; the readout in the level's units.
func draw(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	erasing: bool,
	units: Array
) -> void:
	var cell_m: float = units[0]
	var per_cell: float = units[1]
	var label: String = units[2]
	if drawing:
		var ok := preview != null
		if ok:
			draw_crossing(canvas, camera, editor, preview, _kind_tint(preview.kind), 1.0)
		_draw_line(canvas, camera, from, to, TINT if ok else ERASE_TINT, not ok)
		var text := (
			readout(kind, preview.span_m() * editor.map_scale(), 0.0, cell_m, per_cell, label)
			if ok
			else refusal_text(refusal, cell_m, per_cell, label)
		)
		draw_pill(
			canvas, camera.unproject_position(to), text, READOUT_COLOR if ok else REFUSED_COLOR
		)
		return
	if erasing:
		var hovered := editor.document.crossing(hover_id) if hover_id >= 0 else null
		if hovered != null:
			draw_crossing(canvas, camera, editor, hovered, ERASE_TINT, 1.0)
			draw_pill(
				canvas,
				camera.unproject_position(hit),
				"Remove " + KIND_LABELS[hovered.kind].to_lower(),
				REFUSED_COLOR
			)
			return
		_draw_marker(canvas, camera, hit, ERASE_TINT)
		return
	_draw_marker(canvas, camera, hit, _kind_tint(kind))
	draw_pill(
		canvas,
		camera.unproject_position(hit),
		readout(kind, 0.0, width(), cell_m, per_cell, label),
		READOUT_COLOR
	)


static func _kind_tint(crossing_kind: int) -> Color:
	return TINT if crossing_kind == Crossing.Kind.PLANK else STONE_TINT


## A crossing's ghost (map frame) on `canvas`: a plank deck's outline along its arch, filled
## faintly, with ticks every TICK_M; stepping stones' outlines at their tops; a dot at each
## bank anchor. Drawn with explicit indices, never triangulated.
static func draw_crossing(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	crossing: Crossing,
	tint: Color,
	strength: float
) -> void:
	var span := crossing.span_m()
	if span <= 0.0:
		return
	var screen := func(local: Vector3) -> Vector2:
		return camera.unproject_position(editor.to_world(local))
	if crossing.is_plank():
		var half := crossing.width_m * 0.5
		var pieces := maxi(2, ceili(span / OUTLINE_STEP_M))
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for k in pieces + 1:
			var u := span * k / pieces
			var y := CrossingGeometry.deck_y(crossing.levels, float(k) / pieces)
			left.append(screen.call(CrossingGeometry.point(crossing, u, half, y)))
			right.append(screen.call(CrossingGeometry.point(crossing, u, -half, y)))
		_fill_band(canvas, left, right, Color(tint, 0.22 * strength))
		var ticks := floori(span / TICK_M)
		for k in range(1, ticks + 1):
			var u := span * k / (ticks + 1)
			var y := CrossingGeometry.deck_y(crossing.levels, u / span)
			var a: Vector2 = screen.call(CrossingGeometry.point(crossing, u, half, y))
			var b: Vector2 = screen.call(CrossingGeometry.point(crossing, u, -half, y))
			canvas.draw_line(a, b, Color(tint, 0.35 * strength), 1.0, true)
		var outline := left.duplicate()
		var back := right.duplicate()
		back.reverse()
		outline.append_array(back)
		outline.append(left[0])
		canvas.draw_polyline(outline, Color(SHADOW, 0.6 * strength), 3.5, true)
		canvas.draw_polyline(outline, Color(tint, 0.9 * strength), 1.75, true)
	else:
		for stone in CrossingGeometry.stone_layout(editor.document, crossing):
			_draw_stone(canvas, screen, stone, tint, strength)
	for anchor in [crossing.start, crossing.end]:
		var ground := WaterGeometry.ground_at(editor.document, anchor)
		var at: Vector2 = screen.call(Vector3(anchor.x, ground + 0.03, anchor.y))
		canvas.draw_circle(at, 4.5, Color(SHADOW, 0.7 * strength))
		canvas.draw_circle(at, 3.0, Color(tint, strength))


static func _draw_stone(
	canvas: Control, screen: Callable, stone: Dictionary, tint: Color, strength: float
) -> void:
	var at: Vector2 = stone.at
	var radius: float = stone.radius
	var aspect: float = stone.aspect
	var yaw: float = stone.yaw
	var top: float = stone.top
	var points := PackedVector2Array()
	for k in 17:
		var angle := TAU * k / 16.0
		var o := Vector2(cos(angle) * radius * sqrt(aspect), sin(angle) * radius / sqrt(aspect))
		o = o.rotated(yaw)
		points.append(screen.call(Vector3(at.x + o.x, top + 0.02, at.y + o.y)))
	var centre: Vector2 = screen.call(Vector3(at.x, top + 0.02, at.y))
	var fan := points.duplicate()
	fan.append(centre)
	var colors := PackedColorArray()
	colors.resize(fan.size())
	colors.fill(Color(tint, 0.25 * strength))
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), BrushTool.fan_indices(points.size()), fan, colors
	)
	canvas.draw_polyline(points, Color(SHADOW, 0.6 * strength), 3.5, true)
	canvas.draw_polyline(points, Color(tint, 0.9 * strength), 1.75, true)


## A band between two screen polylines of equal length, filled with `color`.
static func _fill_band(
	canvas: Control, left: PackedVector2Array, right: PackedVector2Array, color: Color
) -> void:
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in left.size():
		points.append(left[k])
		points.append(right[k])
		if k > 0:
			var a := 2 * (k - 1)
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), indices, points, colors
	)


## The drawn line from `a` to `b` (world, on the ground where pressed and pointed): dashes
## over a solid dark keyline, in screen pixels, so it reads over dark foliage and bright sand
## alike at any zoom (P4b-3: a 1.75 px dash alone was lost over a forest floor). A refused
## line (`refused`) is drawn heavier still: it is the one thing on screen that says why
## nothing will be placed.
static func _draw_line(
	canvas: Control, camera: Camera3D, a: Vector3, b: Vector3, tint: Color, refused: bool
) -> void:
	var sa := camera.unproject_position(a)
	var sb := camera.unproject_position(b)
	var width := LINE_REFUSED_PX if refused else LINE_PX
	canvas.draw_line(sa, sb, Color(SHADOW, 0.7), width + 2.5 * LINE_KEY_PX, true)
	canvas.draw_dashed_line(sa, sb, Color(tint, 0.95), width, LINE_DASH_PX, true, true)
	canvas.draw_circle(sa, width + LINE_KEY_PX + 1.5, Color(SHADOW, 0.7))
	canvas.draw_circle(sa, width + 1.0, tint)
	if refused:
		canvas.draw_circle(sb, width + LINE_KEY_PX + 1.5, Color(SHADOW, 0.7))
		canvas.draw_circle(sb, width + 1.0, tint)


## A small ring on the ground at `at` (the idle cursor).
static func _draw_marker(canvas: Control, camera: Camera3D, at: Vector3, tint: Color) -> void:
	var points := PackedVector2Array()
	for k in 25:
		var angle := TAU * k / 24.0
		points.append(camera.unproject_position(at + Vector3(cos(angle), 0.05, sin(angle)) * 0.4))
	canvas.draw_polyline(points, SHADOW, 4.0, true)
	canvas.draw_polyline(points, tint, 2.0, true)


## `text` in a small dark pill beside screen point `at` (below and right of the cursor).
static func draw_pill(canvas: Control, at: Vector2, text: String, color: Color) -> void:
	var font := canvas.get_theme_default_font()
	if font == null or text == "":
		return
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE)
	var pad := Vector2(7.0, 3.0)
	var box := Rect2(at + Vector2(16.0, 14.0), size + pad * 2.0)
	# Kept on screen: flipped to the cursor's left near the right edge.
	var view := canvas.get_viewport_rect().size
	if box.end.x > view.x - 4.0:
		box.position.x = at.x - 16.0 - box.size.x
	if box.end.y > view.y - 4.0:
		box.position.y = at.y - 14.0 - box.size.y
	if _pill_box == null:
		_pill_box = StyleBoxFlat.new()
		_pill_box.bg_color = Color(0.0, 0.0, 0.0, 0.6)
		_pill_box.set_corner_radius_all(4)
	canvas.draw_style_box(_pill_box, box)
	var baseline := box.position + pad + Vector2(0.0, font.get_ascent(READOUT_FONT_SIZE))
	canvas.draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE, color
	)
