class_name WaterBrush
extends BrushMode

## The Water tool's mode (phase 4, P4-4; WaterTool): what a Water press does (a river's line,
## a pond stroke, an erase), the width rule, and the previews drawn under the ring. BrushTool
## routes the tool's press, frames, release and cancel to it (the BrushMode hooks at the end of
## this file), and a refused press or release emits the brush's `refused` with the reason. What
## the water does to the map is WaterEditor's.
##
## River: the line tool's gesture (LineGesture, shared with Fire's Line, card F5e): the press
## starts the line, every frame records the pointer's ground point at the gesture's spacing for
## the river's width, the line ends where the pointer was let go and is Chaikin-smoothed for the
## preview and the carve, and the chip reads "River  Waist  40 ft". The release carves it
## (WaterEditor.carve_river, first point upstream), and the ribbon stays, faint, until the carve
## (on a worker) lands. The ribbon is the line tool's (LineRibbon) in the river's style
## (RIBBON_STYLE: the river's pale blue, an even translucent fill); its gradient and chevrons
## show the way the water will really run (flow_line(): a line drawn uphill is reversed, as the
## plan reverses it, WaterFallPlan.orient, P4c-5). Pond: the press starts a pond stroke (a press
## inside a pond extends it) whose dabs BrushTool paints like the Biome brush's, the dab growing
## with dwell (POND_DWELL_GROW); the painted dabs preview its area. Ctrl at the press (either
## tile): an erase stroke, whose touched river reaches are previewed (they go whole) as the line
## tool's erase ribbon (LineRibbon.erase_style: salmon edge and chevrons on ink, no wash), the
## water it removes showing through untouched, and the chip reads "Erase water  40 ft", the
## length of those reaches.
## The width is the brush size, never below the depth class's narrowest channel
## (radius_for()). A river may be drawn on past the map edge (P6-1): where the pointer leaves
## the ground there (the skirt has no collision), it meets the level of the last ground the
## line touched (hit_past_edge()), and the carve keeps those points as the river's course into
## the skirt (WaterEditor.carve_river).

enum Shape { RIVER, POND }

const TINT := Color(0.56, 0.84, 1.0)
## A river point is recorded once the pointer's ground point is this far (metres) from the
## last; the shortest line a release carves (StrokePath's, which every line shape shares).
const RIVER_DECIMATE_M := StrokePath.DECIMATE_M
const RIVER_MIN_LENGTH_M := StrokePath.MIN_LENGTH_M
## The pond dab's growth with dwell (1 + POND_DWELL_GROW at BrushTool.DWELL_MAX).
const POND_DWELL_GROW := 0.35
## The river's ribbon over the line tool's (LineRibbon.STYLE): its pale blue, the shared even
## fill (faint upstream, stronger downstream: the gradient shows the flow too). The river keeps
## the even fill where the fire line's rails stand at its edges: blue at partial coverage reads
## as water over any ground, where the fire's orange greyed to olive, and the even band shows the
## channel the carve will dig.
const RIBBON_STYLE := {"tint": TINT}
## An erase's interior (LineRibbon.erase_style): the erase salmon, the tint a wash would take.
## The erase has none: even a low salmon wash, the water's complement, greyed the river (F5g).
const ERASE_INTERIOR := {"tint": BrushCursor.CLEAR_TINT}
## The erase's chip: "Erase water", with the length of the rivers it will remove while a stroke
## touches any ("Erase water  40 ft", the line tool's erase pattern, as "Put out fire  40 ft").
const ERASE_TEXT := "Erase water"
## Refusal reasons (BrushTool.refused).
const NO_CARVE := (
	"Rivers and ponds carve the map's own ground: not on a Blender map."
	+ " Ctrl+drag erases water."
)
const NOTHING := "There is no water here to erase."
const FULL := "The map holds as much water as it can. Erase some to make room."
const IN_WATER := "That line lies in water already. Draw it from dry ground."
const DEPTH_LABELS: Array[String] = ["Ankle", "Waist", "Deep"]

## The tile (Shape), the depth class a stroke makes (WaterBody.Depth) and a river's flow
## speed (WaterBody speed).
var shape: int = Shape.RIVER
var depth: int = WaterBody.Depth.WAIST
var speed: float = WaterBody.DEFAULT_SPEED
## The river line being drawn (the line tool's gesture).
var gesture := LineGesture.new()
## True while a river is being drawn (the gesture's).
var drawing: bool:
	get:
		return gesture.drawing
	set(value):
		gesture.drawing = value
## The river's recorded points (world XZ; the gesture's).
var river: PackedVector2Array:
	get:
		return gesture.points
## The last river's smoothed line and half-width, drawn faintly while its carve computes.
var held := PackedVector2Array()
var held_radius: float = 0.0
## Pond stroke dabs painted so far, for the preview: Vector3(x, z, radius) world.
var pond_dabs := PackedVector3Array()

var _refusal: String = ""


func _init() -> void:
	fades = true


## The river half-width or pond brush radius for brush size `radius` and depth class
## `depth_class`: never below the narrowest channel that reaches the class's depth
## (WaterCarve.min_half_width: ankle 0.44 m, waist 1.33 m, deep 2.96 m) nor past the widest
## river (WaterBody.MAX_HALF_WIDTH_M). Pure.
static func radius_for(radius: float, depth_class: int) -> float:
	var narrowest := maxf(WaterCarve.min_half_width(depth_class), WaterBody.MIN_HALF_WIDTH_M)
	return clampf(radius, narrowest, WaterBody.MAX_HALF_WIDTH_M)


## The river line's decimation by distance (StrokePath.decimate). Pure.
static func decimate(points: PackedVector2Array, p: Vector2, spacing: float) -> PackedVector2Array:
	return StrokePath.decimate(points, p, spacing)


## A drawn river line smoothed for carving and preview (StrokePath.smooth_line: two Chaikin
## passes that keep both ends, so a shaky hand reads as a meander). Pure.
static func smooth_line(points: PackedVector2Array) -> PackedVector2Array:
	return StrokePath.smooth_line(points)


## The recorded line ended at the pointer's last point (StrokePath.with_tip). Pure.
static func with_tip(
	points: PackedVector2Array, tip: Vector2, spacing: float
) -> PackedVector2Array:
	return StrokePath.with_tip(points, tip, spacing)


## The line a release carves now (the gesture's line()).
func carve_line() -> PackedVector2Array:
	return gesture.line()


## The line the ribbon previews for a river drawn along `line` (world XZ): reversed when the
## stroke runs uphill (WaterFallPlan.is_uphill on the ground `ground_of` reads at its two ends,
## the plan's own reader, ground_reader()), since the water will run the other way; a flat or
## gently rising stroke keeps its drawn direction, as the plan keeps it. Pure.
static func flow_line(line: PackedVector2Array, ground_of: Callable) -> PackedVector2Array:
	if line.size() < 2:
		return line.duplicate()
	var ends := PackedFloat32Array([ground_of.call(line[0]), ground_of.call(line[-1])])
	return WaterFallPlan.orient(line, PackedFloat32Array(), ends)[0]


## The ground the preview orients by, at a world XZ point: the plan's reader
## (WaterEdit.water_ground_at: under existing water, that water's level plus the freeboard),
## so the ribbon and the carve agree on which way a stroke runs.
static func ground_reader(editor: AuthoringEditor) -> Callable:
	return func(xz: Vector2) -> float:
		var at := editor.to_map_xz(Vector3(xz.x, 0.0, xz.y))
		return WaterEdit.water_ground_at(editor.document, at)


## The length of a polyline (metres; StrokePath.line_length). Pure.
static func line_length(points: PackedVector2Array) -> float:
	return StrokePath.line_length(points)


## The readout under the ring: "River  Waist  40 ft" while a river is drawn (`length_m` > 0,
## in the level's units; LineGesture.chip), "River  Waist" or "Pond  Deep" otherwise. Pure.
static func readout(
	shape_id: int, depth_class: int, length_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := "River" if shape_id == Shape.RIVER else "Pond"
	var text := "%s  %s" % [title, DEPTH_LABELS[clampi(depth_class, 0, 2)]]
	return LineGesture.chip(text, length_m, cell_m, per_cell, label)


## The width now for brush size `brush_radius` (radius_for()).
func radius(brush_radius: float) -> float:
	return radius_for(brush_radius, depth)


## A Water press at world point `hit` (Ctrl held: erase). Returns true when a pond or erase
## stroke began (BrushTool dabs it); false otherwise: a river line began (`drawing`), or the
## press was refused, with the reason in the return of refusal().
func begin(editor: AuthoringEditor, erase: bool, hit: Vector3) -> bool:
	_refusal = ""
	if erase:
		if not editor.water.erase_water_begin():
			_refusal = NOTHING
			return false
		return true
	if not editor.water.can_carve():
		_refusal = NO_CARVE
		return false
	if shape == Shape.POND:
		if not editor.water.paint_pond_begin(depth as WaterBody.Depth, hit):
			_refusal = FULL
			return false
		pond_dabs = PackedVector3Array()
		return true
	gesture.begin(hit)
	held = PackedVector2Array()
	return false


## Why the last begin() or carve() made nothing, or "".
func refusal() -> String:
	return _refusal


## One frame with the pointer's ground point at `hit` (INF: none), the river `half_width`
## wide: records the line (LineGesture.track), and drops the faint ribbon once its carve has
## landed.
func track(editor: AuthoringEditor, hit: Vector3, half_width: float) -> void:
	gesture.track(hit, half_width)
	if not held.is_empty() and (editor == null or not editor.water.is_working()):
		held = PackedVector2Array()


## Where the pointer ray from `origin` along `direction` (world) meets the height of the last
## point the river line recorded, while a river is being drawn: the line's ground past the
## map edge, where the ray finds no ground (BrushTool asks only then). Vector3.INF otherwise.
func hit_past_edge(origin: Vector3, direction: Vector3) -> Vector3:
	if not drawing or shape != Shape.RIVER or river.is_empty() or absf(direction.y) < 1e-4:
		return Vector3.INF
	var t := (gesture.height - origin.y) / direction.y
	return origin + direction * t if t > 0.0 else Vector3.INF


## Carves the river drawn so far (the release) with half-width `half_width`. Returns false
## when refused (refusal() says why; a line too short to carve is silently dropped).
func carve(editor: AuthoringEditor, half_width: float) -> bool:
	_refusal = ""
	var line := gesture.finish()
	if line.is_empty():
		return true
	var id := editor.water.carve_river(
		line, PackedFloat32Array([half_width]), depth as WaterBody.Depth, speed
	)
	if id < 0:
		var reasons := {
			WaterEditor.REFUSED_NO_CARVE: NO_CARVE,
			WaterEditor.REFUSED_FULL: FULL,
			WaterEditor.REFUSED_IN_WATER: IN_WATER,
		}
		_refusal = reasons.get(editor.water.last_refusal, "")
		return _refusal == ""
	held = flow_line(line, ground_reader(editor))
	held_radius = half_width
	return true


## Keeps a pond stroke's dab at `hit` of `radius` for its preview (a third of the radius
## apart).
func record_dab(hit: Vector3, dab_radius: float) -> void:
	var at := Vector3(hit.x, hit.z, dab_radius)
	if not pond_dabs.is_empty():
		var last := pond_dabs[-1]
		var moved := Vector2(last.x, last.y).distance_to(Vector2(at.x, at.y))
		if moved < dab_radius * 0.33 and absf(last.z - dab_radius) < 0.05:
			return
	pond_dabs.append(at)


## Drops a gesture's state (release or cancel).
func reset() -> void:
	gesture.reset()
	pond_dabs = PackedVector3Array()


## The readout text now: when `erasing`, ERASE_TEXT with `erased_m`, the length of the rivers
## the stroke will remove (erase_courses(); 0 at rest or with none touched: the label alone),
## else readout() with the line's length while a river is drawn (the gesture's: the line a
## release would carve).
func readout_text(
	erasing: bool, cell_m: float, per_cell: float, label: String, erased_m: float = 0.0
) -> String:
	if erasing:
		return LineGesture.chip(ERASE_TEXT, erased_m, cell_m, per_cell, label)
	return readout(shape, depth, gesture.length(), cell_m, per_cell, label)


## The river reaches the erase stroke in progress on `editor` will remove (they go whole), as
## [course, half-width] pairs: each course its world XZ line, first point upstream, and its
## half-width in metres. Empty with no erase stroke.
static func erase_courses(editor: AuthoringEditor) -> Array:
	var out: Array = []
	for body in editor.water.erase_touched():
		var course := PackedVector2Array()
		for p: Vector2 in WaterGeometry.river_course(body)[0]:
			var world := editor.to_world(Vector3(p.x, 0.0, p.y))
			course.append(Vector2(world.x, world.z))
		out.append([course, body.half_widths[0] * editor.map_scale()])
	return out


## The length of the rivers the erase stroke in progress on `editor` will remove (metres).
static func erased_length(editor: AuthoringEditor) -> float:
	var total := 0.0
	for pair: Array in erase_courses(editor):
		total += StrokePath.line_length(pair[0])
	return total


## The previews under the ring on `cursor` (see the header): the river being drawn up to the
## pointer at `hit` with half-width `half_width`, or the faint one whose carve computes; with
## a stroke held (`stroking`), the reaches an erase (`erasing`) will remove, or a pond's dabs.
func draw(
	cursor: BrushCursor,
	editor: AuthoringEditor,
	hit: Vector3,
	half_width: float,
	stroking: bool,
	erasing: bool
) -> void:
	var ground := LineRibbon.on_ground(cursor.camera, editor)
	if drawing and not river.is_empty():
		var flow := flow_line(gesture.live(hit), ground_reader(editor))
		LineRibbon.draw(cursor, ground, flow, half_width, RIBBON_STYLE)
	elif not held.is_empty():
		LineRibbon.draw(cursor, ground, held, held_radius, RIBBON_STYLE, 0.5)
	if not stroking:
		return
	if erasing:
		var style := LineRibbon.erase_style(ERASE_INTERIOR)
		for pair: Array in erase_courses(editor):
			LineRibbon.draw(cursor, ground, pair[0], pair[1], style)
	elif shape == Shape.POND:
		for dab in pond_dabs:
			_fill_disc(cursor.canvas, cursor.camera, editor, Vector2(dab.x, dab.y), dab.z)


## A flat disc of world `radius` at world XZ `at`, on the ground there, faintly filled.
static func _fill_disc(
	canvas: Control, camera: Camera3D, editor: AuthoringEditor, at: Vector2, radius: float
) -> void:
	var y := editor.ground_height_at(Vector3(at.x, 0.0, at.y)) + 0.05
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var p := Vector3(at.x + cos(angle) * radius, y, at.y + sin(angle) * radius)
		points.append(camera.unproject_position(p))
	points.append(camera.unproject_position(Vector3(at.x, y, at.y)))
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(Color(TINT, 0.1))
	var indices := PackedInt32Array()
	for i in 24:
		indices.append_array([24, i, (i + 1) % 24])
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), indices, points, colors
	)


# ============================================================================
# BrushMode hooks
# ============================================================================


## A brook may be narrower than the other brushes allow.
func min_radius() -> float:
	return WaterBody.MIN_HALF_WIDTH_M


## The water radius (a Ctrl erase keeps the plain brush size), a pond's growing with dwell.
func stroke_radius(brush: BrushTool) -> float:
	if _erasing(brush):
		return brush.get_radius()
	var width := radius(brush.get_radius())
	if brush.stroking and shape == Shape.POND:
		width *= 1.0 + POND_DWELL_GROW * clampf(brush.dwell / BrushTool.DWELL_MAX, 0.0, 1.0)
	return width


## A pond or erase stroke for the brush to dab, or a river's line; a refusal says why.
func press(brush: BrushTool) -> bool:
	if begin(brush.editor, brush.press_ctrl, brush.hit):
		return true
	if refusal() != "":
		brush.refused.emit(refusal())
	return false


func frame(brush: BrushTool) -> void:
	track(brush.editor, brush.hit, radius(brush.get_radius()))


## Keeps a pond stroke's dab for its preview.
func dabbed(brush: BrushTool) -> void:
	if not brush.press_ctrl and shape == Shape.POND:
		record_dab(brush.hit, stroke_radius(brush))


## Carves a river being drawn (a refusal says why).
func end(brush: BrushTool) -> void:
	if drawing and brush.editor != null and not carve(brush.editor, radius(brush.get_radius())):
		brush.refused.emit(refusal())
	reset()


func cancel(_brush: BrushTool) -> void:
	reset()


func has_shapes() -> bool:
	return true


## Tab: River to Pond and back (the pane's tiles follow, BrushTool.shape_toggled).
func toggle_shape(brush: BrushTool) -> bool:
	shape = Shape.POND if shape == Shape.RIVER else Shape.RIVER
	brush.redraw()
	return true


## From the size the ring shows, so a notch always changes it visibly; with Ctrl held (the
## erase ring), the plain brush size.
func step(brush: BrushTool, steps: int) -> void:
	if brush.ctrl:
		super.step(brush, steps)
		return
	brush.set_radius(radius(radius(brush.get_radius()) * pow(BrushTool.RADIUS_STEP, steps)))


## The river's blue, or the erase salmon every brush erases in.
func cursor_tint(brush: BrushTool) -> Color:
	return BrushCursor.CLEAR_TINT if _erasing(brush) else TINT


## The chip (readout_text()), an erase stroke's with the length of the rivers it will remove.
func cursor_text(brush: BrushTool) -> String:
	var erasing := _erasing(brush)
	var erased := 0.0
	if erasing and brush.stroking and brush.editor != null:
		erased = erased_length(brush.editor)
	return readout_text(
		erasing, brush.unit_cell_m, brush.unit_per_cell, brush.unit_label, erased
	)


## The previews (draw()) under the ring.
func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor != null:
		var width := radius(brush.get_radius())
		var erasing := _erasing(brush)
		draw(cursor, brush.editor, brush.hit, width, brush.stroking, erasing)
	super.draw_cursor(brush, cursor)


## True while Ctrl erases: held at the press during a gesture, else held now.
func _erasing(brush: BrushTool) -> bool:
	return brush.press_ctrl if (brush.stroking or brush.pressed) else brush.ctrl
