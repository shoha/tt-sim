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
const KIND_LABELS: Array[String] = ["Stone wall", "Fence", "Building", "Street"]
## A building turns this much per Q or E notch, and the idle ghost of one is this big (world
## metres: along its first side, across).
## The species' names in the readout (Wall.preset).
const ROW_PRESET_NAMES: Array[String] = ["Mixed", "Terrace", "Guild houses", "Village", "Cottages"]
const YAW_STEP := deg_to_rad(15.0)
const GHOST_SIZE_M := Vector2(4.0, 3.0)
## The door mark is this wide on the first side (metres), and the footprint fill alpha.
const DOOR_MARK_M := 1.0
const FOOTPRINT_ALPHA := 0.2
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
const SHORT_BUILDING := "Drag from one corner to the opposite one, at least 2 m each way."
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
	Wall.DEFAULT_HEIGHT_M[Wall.Kind.STONE],
	Wall.DEFAULT_HEIGHT_M[Wall.Kind.FENCE],
	Wall.DEFAULT_HEIGHT_M[Wall.Kind.BUILDING],
	Wall.DEFAULT_HEIGHT_M[Wall.Kind.ROW],
]
## A new street's side (0 left, 1 right, 2 both; Q and E) and variation seed (R).
var row_side: int = 2
var row_seed: int = 0
## A new street's species (Wall.preset).
var row_preset: int = 0
## The turn of a building footprint (radians from the map X axis; Q and E).
var yaw: float = 0.0
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
static func refusal_text(reason: StringName, wall_kind: int = Wall.Kind.STONE) -> String:
	match reason:
		WallEditor.REFUSED_SHORT:
			return SHORT_BUILDING if wall_kind == Wall.Kind.BUILDING else SHORT
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


## The readout beside the cursor for a building: its two sides ("Building  14 x 10 ft"). Pure.
static func readout_building(
	along_m: float, across_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var a := roundi(ScaleUtils.world_to_display(along_m, cell_m, per_cell))
	var b := roundi(ScaleUtils.world_to_display(across_m, cell_m, per_cell))
	return "Building  %d x %d %s" % [a, b, label]


## The readout beside the cursor for a street: how many buildings and on which side ("Street  11
## buildings, both sides"), or with no count (`buildings` < 0) its setback and the keys. Pure.
static func readout_row(
	buildings: int,
	side: int,
	setback_m: float,
	cell_m: float,
	per_cell: float,
	label: String,
	preset: int = 0
) -> String:
	var sides: String = ["left side", "right side", "both sides"][clampi(side, 0, 2)]
	var species := "" if preset <= 0 else "%s, " % ROW_PRESET_NAMES[clampi(preset, 0, 4)]
	if buildings >= 0:
		return "Street  %s%d buildings, %s" % [species, buildings, sides]
	var set_back := ScaleUtils.world_to_display(setback_m, cell_m, per_cell)
	return (
		"Street  %s%s %s back, %s  (Q/E side, R new mix)"
		% [species, BridgeBrush.short_number(set_back), label, sides]
	)


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
	preview = editor.walls.plan(
		kind as Wall.Kind,
		from,
		to,
		height(),
		yaw,
		{"seed": row_seed, "side": row_side, "preset": row_preset}
	)
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
		_message = refusal_text(refusal, kind)
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


## A building footprint turns with Q and E, and a street changes its side.
func rotates() -> bool:
	return kind == Wall.Kind.BUILDING or kind == Wall.Kind.ROW


## Q or E: a building footprint turns `steps` notches of YAW_STEP (E clockwise on screen); a
## street's side steps round left, right, both.
func rotate(brush: BrushTool, steps: int) -> void:
	if kind == Wall.Kind.ROW:
		row_side = posmod(row_side + signi(steps), Wall.ROW_SIDES)
	else:
		yaw = wrapf(yaw + steps * YAW_STEP, 0.0, TAU)
	_planned_to = Vector3.INF
	brush.redraw()


## R varies a street: the one under the pointer, else the next one laid.
func rerolls() -> bool:
	return kind == Wall.Kind.ROW


func reroll(brush: BrushTool) -> void:
	var editor := brush.editor
	if editor == null:
		return
	var under := editor.walls.wall_at(brush.hit, PICK_MARGIN_M) if brush.hit != Vector3.INF else -1
	if under >= 0 and editor.document.wall(under).is_row():
		editor.walls.reroll(under)
	else:
		row_seed = WallEditor.next_seed(row_seed)
		_planned_to = Vector3.INF
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
		var building := kind == Wall.Kind.BUILDING
		if building:
			# Two opposite corners: a dot on each, the rectangle between them.
			for corner in [from, to]:
				BridgeBrush.draw_marker(canvas, camera, corner, _kind_tint(kind))
		else:
			BridgeBrush.draw_drag_line(
				canvas, camera, from, to, _kind_tint(kind) if ok else ERASE_TINT, not ok
			)
		var text := refusal_text(refusal, kind)
		if ok and building:
			var scale := editor.map_scale()
			text = readout_building(
				preview.points[0].distance_to(preview.points[1]) * scale,
				preview.points[1].distance_to(preview.points[2]) * scale,
				cell_m,
				per_cell,
				label
			)
		elif ok and kind == Wall.Kind.ROW:
			text = readout_row(
				WallGeometry.row_lots(editor.document, preview).size(),
				preview.side,
				0.0,
				0.0,
				0.0,
				"",
				preview.preset
			)
		elif ok:
			text = readout(kind, from.distance_to(to), 0.0, cell_m, per_cell, label)
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
	if kind == Wall.Kind.BUILDING and hit != Vector3.INF:
		_draw_idle_building(canvas, camera, editor, hit)
	BridgeBrush.draw_marker(canvas, camera, hit, _kind_tint(kind))
	BridgeBrush.draw_pill(
		canvas,
		camera.unproject_position(hit),
		(
			readout_row(-1, row_side, height(), cell_m, per_cell, label, row_preset)
			if kind == Wall.Kind.ROW
			else readout(kind, 0.0, height(), cell_m, per_cell, label)
		),
		READOUT_COLOR
	)


## Pale stone for a wall, warm wood for a fence.
static func _kind_tint(wall_kind: int) -> Color:
	return FENCE_TINT if wall_kind == Wall.Kind.FENCE else STONE_TINT


## The footprint a building would have if it were pressed here at the default size and the
## brush turn, so the turn shows before the drag.
func _draw_idle_building(
	canvas: Control, camera: Camera3D, editor: AuthoringEditor, hit: Vector3
) -> void:
	var scale := editor.map_scale()
	var centre := editor.to_map_xz(hit)
	var u := Vector2(cos(yaw), sin(yaw))
	var v := Vector2(-u.y, u.x)
	var half := GHOST_SIZE_M * 0.5 / scale
	var corners := WallEditor.building_corners(
		centre - u * half.x - v * half.y, centre + u * half.x + v * half.y, yaw
	)
	var ghost := Wall.make(0, Wall.Kind.BUILDING, corners, true, height() / scale)
	draw_wall(canvas, camera, editor, ghost, _kind_tint(kind), 0.7)


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
	if wall.is_row():
		_draw_row(canvas, camera, editor, wall, tint, strength)
		return
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
	if wall.is_building() and count == Wall.BUILDING_POINTS:
		_draw_footprint(canvas, camera, editor, wall, tint, strength)


## A street's ghost: its line on the ground and every building's footprint with its door.
static func _draw_row(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	wall: Wall,
	tint: Color,
	strength: float
) -> void:
	var doc := editor.document
	var street := PackedVector2Array()
	for p in wall.points:
		var y := WaterGeometry.ground_at(doc, p) + 0.04
		street.append(camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y))))
	canvas.draw_polyline(street, Color(SHADOW, 0.6 * strength), 3.5, true)
	canvas.draw_polyline(street, Color(tint, 0.9 * strength), 1.75, true)
	for lot in WallGeometry.row_lots(doc, wall):
		var corners := PackedVector2Array()
		for q: Vector3 in lot.points:
			corners.append(Vector2(q.x, q.z))
		var house := Wall.make(0, Wall.Kind.BUILDING, corners, true, lot.height)
		var ring := PackedVector2Array()
		for p in corners:
			var y := WaterGeometry.ground_at(doc, p) + 0.04
			ring.append(camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y))))
		ring.append(ring[0])
		canvas.draw_polyline(ring, Color(SHADOW, 0.5 * strength), 3.0, true)
		canvas.draw_polyline(ring, Color(tint, 0.9 * strength), 1.5, true)
		_draw_footprint(canvas, camera, editor, house, tint, strength)


## A building footprint: the rectangle filled faintly on the ground and the door marked on its
## first side (a bar the door width, and a tick out from it).
static func _draw_footprint(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	wall: Wall,
	tint: Color,
	strength: float
) -> void:
	var doc := editor.document
	var screen := func(p: Vector2, lift: float) -> Vector2:
		var y := WaterGeometry.ground_at(doc, p) + lift
		return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))
	var ring := PackedVector2Array()
	for p in wall.points:
		ring.append(screen.call(p, 0.04))
	var centre := (ring[0] + ring[1] + ring[2] + ring[3]) * 0.25
	var fan := ring.duplicate()
	fan.append(centre)
	var colors := PackedColorArray()
	colors.resize(fan.size())
	colors.fill(Color(tint, FOOTPRINT_ALPHA * strength))
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), BrushCursor.fan_indices(ring.size()), fan, colors
	)
	var side := wall.points[1] - wall.points[0]
	var mid := (wall.points[0] + wall.points[1]) * 0.5
	var along := side.normalized()
	var middle_of_all := (wall.points[0] + wall.points[1] + wall.points[2] + wall.points[3]) * 0.25
	var out := Vector2(-along.y, along.x)
	if out.dot(middle_of_all - mid) > 0.0:
		out = -out
	var door := DOOR_MARK_M / editor.map_scale()
	var left: Vector2 = screen.call(mid - along * door * 0.5, 0.05)
	var right: Vector2 = screen.call(mid + along * door * 0.5, 0.05)
	var step: Vector2 = screen.call(mid + out * door * 0.6, 0.05)
	var middle: Vector2 = screen.call(mid, 0.05)
	canvas.draw_line(left, right, Color(SHADOW, 0.8 * strength), 7.0, true)
	canvas.draw_line(left, right, Color(1.0, 1.0, 1.0, strength), 4.0, true)
	canvas.draw_line(middle, step, Color(SHADOW, 0.8 * strength), 5.0, true)
	canvas.draw_line(middle, step, Color(1.0, 1.0, 1.0, strength), 2.5, true)
