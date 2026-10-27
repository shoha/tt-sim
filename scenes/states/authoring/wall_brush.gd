class_name WallBrush
extends BrushMode

## The Wall tool's mode (WallTool): the drawn side, its live preview, the refusal hint, the Ctrl
## erase hover and the height a Shift+wheel sets. BrushTool routes the tool's press, frames,
## release and cancel to it (the BrushMode hooks below), and a release or Ctrl press that makes
## nothing emits the brush's `refused` with the reason. Where a wall goes is WallEditor's rule
## (`AuthoringEditor.walls`: a drag starting at the free end of a wall of the same kind extends
## it, and ending at its other end closes it); this only wires the gesture to it.
##
## Gesture. A press on the ground starts a side; every frame the pointer moves at least
## REPLAN_M the wall it would make is planned again (WallEditor.plan, which changes nothing) and
## drawn as a ghost: the whole wall's line on the ground, its top, and a post every few metres.
## The release lays the plan as one history entry. A side that makes nothing is drawn red with
## the reason in plain words beside the cursor. Ctrl at the press erases the wall under the
## pointer (hovering with Ctrl held outlines it in red first). RMB or Escape drops a side being
## drawn.

const STONE_TINT := Color(0.88, 0.9, 0.86)
const FENCE_TINT := Color(0.98, 0.84, 0.58)
const ERASE_TINT := BrushCursor.CLEAR_TINT
const SHADOW := Color(0.05, 0.04, 0.05, 0.55)
## The readout's name per Wall.Kind.
const KIND_LABELS: Array[String] = ["Stone wall", "Fence"]
## The pointer's ground point moves this far (metres) before the preview is planned again.
const REPLAN_M := 0.08
## Height change per Shift+wheel notch or bracket key (multiplicative, like the brush size).
const HEIGHT_STEP := 1.1
## The ghost's line is sampled this far apart along the ground, and a post stands every POST_M.
const LINE_STEP_M := 0.5
const POST_M := 1.5
## Hover reach of the Ctrl erase around a wall's line (world metres).
const PICK_MARGIN_M := 0.5
const READOUT_COLOR := Color(1.0, 0.95, 0.6)
const REFUSED_COLOR := Color(1.0, 0.72, 0.62)
## Plain-words reasons a side makes no wall (refusal_text()).
const SHORT := "Drag a longer line to lay a wall."
const FULL := "The map holds as many walls as it can. Remove one to make room."
const LONG := "That wall is too long. End it and start another."
const POINTS := "That wall has as many corners as it can. End it and start another."
const INVALID := "A wall cannot stand there."
const NOTHING := "There is no wall here to remove."
## The canopy fade's reach around the cursor (metres, before the brush's fade factor).
const FADE_M := 2.5

## The tile picked (Wall.Kind).
var kind: int = Wall.Kind.STONE
## The height per kind (world metres) a new wall gets.
var heights: Array[float] = [
	Wall.DEFAULT_HEIGHT_M[Wall.Kind.STONE], Wall.DEFAULT_HEIGHT_M[Wall.Kind.FENCE]
]
## A side being drawn: its press point (world) and the pointer's last ground point.
var drawing: bool = false
var from: Vector3 = Vector3.INF
var to: Vector3 = Vector3.INF
## The wall the side makes now (map frame; null when refused), and why not.
var preview: Wall = null
var refusal: StringName = &""
## The wall under the pointer while Ctrl is held (its id), or -1.
var hover_id: int = -1
## Microseconds of the last plan, for measurement.
var last_plan_usec: int = 0

var _planned_to: Vector3 = Vector3.INF
var _message: String = ""


func _init() -> void:
	fades = true


## The reason a side makes no wall, in plain words. Pure.
static func refusal_text(reason: StringName) -> String:
	match reason:
		WallEditor.REFUSED_SHORT:
			return SHORT
		WallEditor.REFUSED_FULL:
			return FULL
		WallEditor.REFUSED_LONG:
			return LONG
		WallEditor.REFUSED_POINTS:
			return POINTS
		WallEditor.REFUSED_INVALID:
			return INVALID
	return ""


## `from_height` stepped `steps` notches (positive raises) within kind `wall_kind`'s range. Pure.
static func stepped_height(from_height: float, steps: int, wall_kind: int) -> float:
	return clampf(
		from_height * pow(HEIGHT_STEP, steps),
		Wall.MIN_HEIGHT_M[wall_kind],
		Wall.MAX_HEIGHT_M[wall_kind]
	)


## The readout's name for `wall_kind`. Pure.
static func kind_label(wall_kind: int) -> String:
	return KIND_LABELS[clampi(wall_kind, 0, KIND_LABELS.size() - 1)]


## The readout beside the cursor: the kind and the planned wall's length while a side is drawn
## ("Stone wall  20 ft"), else its height ("Stone wall  3 ft high"). Pure.
static func readout(
	wall_kind: int, length_m: float, height_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := kind_label(wall_kind)
	if length_m > 0.0:
		var length := roundi(ScaleUtils.world_to_display(length_m, cell_m, per_cell))
		return "%s  %d %s" % [title, length, label]
	var high := ScaleUtils.world_to_display(height_m, cell_m, per_cell)
	return "%s  %s %s high" % [title, BridgeBrush.short_number(high), label]


## The picked kind's height (world metres).
func height() -> float:
	return heights[kind]


## Steps the picked kind's height `steps` notches (Shift+wheel, [ and ]).
func step_height(steps: int) -> void:
	heights[kind] = stepped_height(heights[kind], steps, kind)
	_planned_to = Vector3.INF


## Starts a side at world point `hit`.
func begin(hit: Vector3) -> void:
	drawing = true
	from = hit
	to = hit
	preview = null
	refusal = WallEditor.REFUSED_SHORT
	_planned_to = Vector3.INF
	hover_id = -1


## One frame with the pointer's ground point at `hit` (INF: none): while drawing, the side's end
## follows it and the preview is planned again once it moved REPLAN_M; with `erasing` (Ctrl held,
## not drawing) the wall under it is looked up for the hover outline.
func track(editor: AuthoringEditor, hit: Vector3, erasing: bool) -> void:
	if editor == null:
		return
	if drawing:
		if hit != Vector3.INF:
			to = hit
		if _planned_to == Vector3.INF or _planned_to.distance_to(to) >= REPLAN_M:
			_plan(editor)
		return
	hover_id = editor.walls.wall_at(hit, PICK_MARGIN_M) if erasing and hit != Vector3.INF else -1


func _plan(editor: AuthoringEditor) -> void:
	var started := Time.get_ticks_usec()
	preview = editor.walls.plan(kind as Wall.Kind, from, to, height())
	refusal = editor.walls.last_refusal
	last_plan_usec = Time.get_ticks_usec() - started
	_planned_to = to


## Lays the side being drawn (the release): the wall's id, or -1 with message() saying why.
func finish(editor: AuthoringEditor) -> int:
	_message = ""
	if not drawing:
		return -1
	drawing = false
	if _planned_to != to or to == from:
		_plan(editor)
	var placed := -1
	if preview != null:
		placed = editor.walls.add(preview)
		if placed < 0:
			refusal = editor.walls.last_refusal
	if placed < 0:
		_message = refusal_text(refusal)
	preview = null
	return placed


## Erases the wall under world point `hit` (a Ctrl press). False, with message() set, when
## there is none.
func erase_at(editor: AuthoringEditor, hit: Vector3) -> bool:
	_message = ""
	var wall_id := editor.walls.wall_at(hit, PICK_MARGIN_M)
	if wall_id < 0 or not editor.walls.remove(wall_id):
		_message = NOTHING
		return false
	hover_id = -1
	return true


## Why the last finish() or erase_at() made nothing, or "".
func message() -> String:
	return _message


## Drops a side being drawn (a cancel, or after a release).
func reset() -> void:
	drawing = false
	preview = null
	refusal = &""
	_planned_to = Vector3.INF


# ============================================================================
# BrushMode hooks
# ============================================================================


## Starts a side, or with Ctrl erases the wall under the press (a miss says why).
func press(brush: BrushTool) -> bool:
	if not brush.press_ctrl:
		begin(brush.hit)
	elif not erase_at(brush.editor, brush.hit):
		brush.refused.emit(message())
	return false


## True when the press began a side (an erase is silent, as a prop's removal is).
func took_press() -> bool:
	return drawing


## Ctrl held while hovering (not pressed) looks up the wall to outline.
func frame(brush: BrushTool) -> void:
	track(brush.editor, brush.hit, brush.ctrl and not brush.pressed)


## Lays the side being drawn (a side that makes nothing says why).
func end(brush: BrushTool) -> void:
	if drawing and brush.editor != null:
		if finish(brush.editor) < 0:
			brush.refused.emit(message())
	reset()


func cancel(_brush: BrushTool) -> void:
	reset()


## Shift+wheel or a bracket key: the picked kind's height.
func step(brush: BrushTool, steps: int) -> void:
	step_height(steps)
	brush.redraw()


## The side being drawn stays in view under a canopy: the focus is its middle.
func fade_focus(brush: BrushTool) -> Vector4:
	var centre := (from + brush.hit) * 0.5 if drawing else brush.hit
	var reach := maxf(FADE_M, centre.distance_to(brush.hit) + 1.0)
	return Vector4(centre.x, centre.y, centre.z, reach)


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor == null:
		return
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	var erasing := brush.ctrl and not brush.pressed
	draw(cursor.canvas, cursor.camera, brush.editor, brush.hit, erasing, units)


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
			draw_wall(canvas, camera, editor, preview, _kind_tint(preview.kind), 1.0)
		BridgeBrush.draw_drag_line(
			canvas, camera, from, to, _kind_tint(kind) if ok else ERASE_TINT, not ok
		)
		var text := (
			readout(kind, from.distance_to(to), 0.0, cell_m, per_cell, label)
			if ok
			else refusal_text(refusal)
		)
		BridgeBrush.draw_pill(
			canvas, camera.unproject_position(to), text, READOUT_COLOR if ok else REFUSED_COLOR
		)
		return
	if erasing:
		var hovered := editor.document.wall(hover_id) if hover_id >= 0 else null
		if hovered != null:
			draw_wall(canvas, camera, editor, hovered, ERASE_TINT, 1.0)
			BridgeBrush.draw_pill(
				canvas,
				camera.unproject_position(hit),
				"Remove " + kind_label(hovered.kind).to_lower(),
				REFUSED_COLOR
			)
			return
		BridgeBrush.draw_marker(canvas, camera, hit, ERASE_TINT)
		return
	BridgeBrush.draw_marker(canvas, camera, hit, _kind_tint(kind))
	BridgeBrush.draw_pill(
		canvas,
		camera.unproject_position(hit),
		readout(kind, 0.0, height(), cell_m, per_cell, label),
		READOUT_COLOR
	)


## Pale stone for a wall, warm wood for a fence.
static func _kind_tint(wall_kind: int) -> Color:
	return FENCE_TINT if wall_kind == Wall.Kind.FENCE else STONE_TINT


## A wall's ghost (map frame) on `canvas`: its line on the ground, its top a height above, and a
## post joining them every POST_M, with a dot at each corner. Each point sits on the document's
## ground.
static func draw_wall(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	wall: Wall,
	tint: Color,
	strength: float
) -> void:
	var count := wall.points.size()
	if count < 2:
		return
	var doc := editor.document
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	var sides := count if wall.closed else count - 1
	var posts := PackedVector2Array()
	for k in sides:
		var a := wall.points[k]
		var b := wall.points[(k + 1) % count]
		var pieces := maxi(1, ceili(a.distance_to(b) / LINE_STEP_M))
		var post_every := maxi(1, roundi(POST_M / LINE_STEP_M))
		for s in pieces + (1 if k == sides - 1 else 0):
			var xz := a.lerp(b, float(s) / pieces)
			var y := WaterGeometry.ground_at(doc, xz)
			var low := camera.unproject_position(editor.to_world(Vector3(xz.x, y, xz.y)))
			var high := camera.unproject_position(
				editor.to_world(Vector3(xz.x, y + wall.height_m, xz.y))
			)
			base.append(low)
			top.append(high)
			if s % post_every == 0:
				posts.append(low)
				posts.append(high)
	if wall.closed:
		base.append(base[0])
		top.append(top[0])
	for k in range(0, posts.size(), 2):
		canvas.draw_line(posts[k], posts[k + 1], Color(tint, 0.3 * strength), 1.0, true)
	for line in [base, top]:
		canvas.draw_polyline(line, Color(SHADOW, 0.6 * strength), 3.5, true)
		canvas.draw_polyline(line, Color(tint, 0.9 * strength), 1.75, true)
	for p in wall.points:
		var ground := WaterGeometry.ground_at(doc, p)
		var at := camera.unproject_position(editor.to_world(Vector3(p.x, ground + 0.03, p.y)))
		canvas.draw_circle(at, 4.5, Color(SHADOW, 0.7 * strength))
		canvas.draw_circle(at, 3.0, Color(tint, strength))
