class_name FireBrush
extends BrushMode

## The Fire tool's mode (FireTool), with two shapes as Water has River and Pond (design
## section 2), Tab switching them (toggle_shape()):
##   Area   an LMB drag lays persistent ground fire with Paint's falloff and dwell, the fire
##          mask approaching the pane's intensity (BrushTool dabs the stroke).
##   Line   the press starts a line captured as a river's (StrokePath: a point every
##          StrokePath.DECIMATE_M, or every WaterBrush.WIDTH_DECIMATE radii for a wide brush,
##          the release point added, Chaikin-smoothed), previewed while dragging with the
##          river's own ribbon (WaterBrush.draw_ribbon: gradient fill, edges, chevrons) at the
##          brush width in ember orange (user, 2026-10-11: the same affordance as driving a
##          river, orange for fire). The release lays it (lay_line()): resampled evenly every
##          LINE_SPACING radii and dabbed segment by segment as capsules at a fixed exposure
##          per segment, so a line is even whatever the drawing speed. A release under
##          StrokePath.MIN_LENGTH_M lays nothing; Esc or RMB mid-drag drops the line.
## Both shapes lay through AuthoringEditor.begin_fire_stroke, so a lay is one history entry
## "Lay fire" with its burnt forest and ash (FireEditor), synced and undoable in play as any
## stroke. Ctrl at the press puts fire out instead (the area, or along the line), leaving its
## ash and snags. The ring is ember orange, red to put out; so is the line's ribbon.

enum Shape { LINE, AREA }

const ERASE_TEXT := "Put out fire"
const LINE_TEXT := "Line of fire"
## The pane's intensity tiles, as mask bytes (design section 2).
const EMBERS := 96
const FLAMES := 176
const BLAZE := 255
const TINT := ThemeColors.EMBER
## A laid line's dabs: one capsule every LINE_SPACING brush radii along the line, each with
## LINE_SECONDS of exposure (times the brush's flow). Along the centre a sample gathers about
## 5.3 dabs' worth, about 1.2 s: 97 % of the way to the intensity, the edges falling off as
## an Area stroke's do. MAX_LINE_DABS bounds a very long line's work.
const LINE_SPACING := 0.25
const LINE_SECONDS := 0.22
const MAX_LINE_DABS := 4096

## The mask byte a lay approaches (EMBERS, FLAMES or BLAZE).
var intensity: int = FLAMES
## The shape a press draws (Shape; Area until Tab or the pane picks Line).
var shape: int = Shape.AREA
## A line being drawn: its recorded points (world XZ).
var line := PackedVector2Array()
var drawing: bool = false

## The pointer's last ground point while a line is drawn (world XZ; Vector2.INF: none): the
## release point, which the line ends at whether or not decimation recorded it.
var _tip: Vector2 = Vector2.INF


func _init() -> void:
	fades = true


## The dabs that lay `path` (world XZ, already smoothed) with a brush of `radius` metres at
## `flow`: [from: Vector3, to: Vector3, seconds: float] each, world space on the plane y = 0
## (the fire mask reads XZ alone). The path is resampled evenly (StrokePath.resample) about
## LINE_SPACING radii apart, and each segment's exposure is LINE_SECONDS scaled by its length
## over that spacing, so the exposure per metre, and with it the mask, does not depend on how
## the line was captured. Pure.
static func line_dabs(path: PackedVector2Array, radius: float, flow: float) -> Array:
	var spacing := maxf(radius * LINE_SPACING, 0.05)
	var points := StrokePath.resample(path, MAX_LINE_DABS + 1, spacing)
	var dabs: Array = []
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length <= 0.0:
			continue
		var from := Vector3(points[i].x, 0.0, points[i].y)
		var to := Vector3(points[i + 1].x, 0.0, points[i + 1].y)
		dabs.append([from, to, LINE_SECONDS * flow * length / spacing])
	return dabs


## Lays the line `path` (world XZ, smoothed) on `editor` with a brush of `radius` metres: fire
## toward `target` (0..1 of 255), or with `erase` put out along it, as one stroke (one history
## entry, FireEditor). A path under StrokePath.MIN_LENGTH_M lays nothing. True when the fire
## changed.
static func lay_line(
	editor: AuthoringEditor,
	path: PackedVector2Array,
	radius: float,
	target: float,
	erase: bool,
	flow: float = 1.0
) -> bool:
	if StrokePath.line_length(path) < StrokePath.MIN_LENGTH_M:
		return false
	if not editor.begin_fire_stroke(target, erase):
		return false
	for dab: Array in line_dabs(path, radius, flow):
		editor.stroke_dab(dab[0], dab[1], radius, dab[2])
	editor.flush()
	return editor.end_stroke()


## The line a release lays now: the recorded points ended at the pointer
## (StrokePath.with_tip), smoothed (StrokePath.smooth_line).
func laid_line() -> PackedVector2Array:
	return StrokePath.smooth_line(StrokePath.with_tip(line, _tip, StrokePath.DECIMATE_M))


## Drops a line's state (release or cancel).
func reset() -> void:
	drawing = false
	line = PackedVector2Array()
	_tip = Vector2.INF


## Area: a fire stroke for the brush to dab. Line: the line begins (the release lays it).
func press(brush: BrushTool) -> bool:
	if shape == Shape.AREA:
		return brush.editor.begin_fire_stroke(intensity / 255.0, brush.press_ctrl)
	var at := Vector2(brush.hit.x, brush.hit.z)
	line = StrokePath.decimate(PackedVector2Array(), at, StrokePath.DECIMATE_M)
	_tip = at
	drawing = true
	return false


## Records the line under the pointer, a point once it lies the capture spacing from the last.
func frame(brush: BrushTool) -> void:
	if not drawing or brush.hit == Vector3.INF:
		return
	var at := Vector2(brush.hit.x, brush.hit.z)
	var spacing := maxf(StrokePath.DECIMATE_M, brush.get_radius() * WaterBrush.WIDTH_DECIMATE)
	line = StrokePath.decimate(line, at, spacing)
	_tip = at


## Lays the line being drawn (the release, or a tool switch or undo before it).
func end(brush: BrushTool) -> void:
	if not drawing:
		return
	var path := laid_line()
	reset()
	if brush.editor != null:
		var target := intensity / 255.0
		lay_line(brush.editor, path, brush.get_radius(), target, brush.press_ctrl, brush.get_flow())


func cancel(_brush: BrushTool) -> void:
	reset()


func has_shapes() -> bool:
	return true


## Tab: Area to Line and back (the pane's tiles and the hint bar follow,
## BrushTool.shape_toggled).
func toggle_shape(brush: BrushTool) -> bool:
	shape = Shape.LINE if shape == Shape.AREA else Shape.AREA
	brush.redraw()
	return true


## Red while putting out: Ctrl held at the press during a gesture, else Ctrl held now.
func cursor_tint(brush: BrushTool) -> Color:
	return BrushCursor.CLEAR_TINT if _erasing(brush) else TINT


## The red ring names its erase under it ("Put out fire"), as Paint's "Erase paint"; the Line
## shape says so ("Line of fire"), with the line's length in the level's units while drawn.
func cursor_text(brush: BrushTool) -> String:
	if _erasing(brush):
		return ERASE_TEXT
	if shape == Shape.AREA:
		return ""
	if not drawing:
		return LINE_TEXT
	var length := StrokePath.line_length(laid_line())
	var shown := ScaleUtils.world_to_display(length, brush.unit_cell_m, brush.unit_per_cell)
	return "%s  %d %s" % [LINE_TEXT, roundi(shown), brush.unit_label]


## The line being drawn as the river's ribbon up to the pointer (ember, red to put out), then
## the ring.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if drawing and not line.is_empty() and brush.editor != null:
		var live := line.duplicate()
		if brush.hit != Vector3.INF:
			var tip := Vector2(brush.hit.x, brush.hit.z)
			if live[-1].distance_to(tip) > 0.05:
				live.append(tip)
		var erasing := _erasing(brush)
		WaterBrush.draw_ribbon(
			cursor.canvas,
			WaterBrush.on_ground(cursor.camera, brush.editor),
			StrokePath.smooth_line(live),
			brush.get_radius(),
			BrushCursor.CLEAR_TINT if erasing else TINT,
			1.0,
			not erasing
		)
	super.draw_cursor(brush, cursor)


func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if (brush.stroking or brush.pressed) else brush.ctrl
