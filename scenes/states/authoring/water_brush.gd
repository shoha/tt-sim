class_name WaterBrush
extends RefCounted

## The Water tool's half of BrushTool (phase 4, P4-4): what a Water press does (a river's
## line, a pond stroke, an erase), the line's capture and smoothing, the width rule, and the
## previews drawn under the ring. BrushTool owns one (`BrushTool.water`), routes the Water
## mode's press, frames, release and cancel to it and emits `water_refused` with the reasons
## it gives. What the water does to the map is WaterEditor's.
##
## River: the press starts the line; every frame the pointer's ground point is recorded once
## it lies RIVER_DECIMATE_M from the last (decimate()); the line is Chaikin-smoothed
## (smooth_line()) for the preview and the carve; the release carves it
## (WaterEditor.carve_river, first point upstream), and the ribbon stays, faint, until the
## carve (on a worker) lands. The ribbon's gradient and chevrons show the way the water will
## really run (flow_line(): a line drawn uphill is reversed, as the plan reverses it,
## WaterFallPlan.orient, P4c-5). Pond: the press starts a pond stroke (a press inside a pond
## extends it) whose dabs BrushTool paints like the Biome brush's, the dab growing with
## dwell (POND_DWELL_GROW); the painted dabs preview its area. Ctrl at the press (either
## tile): an erase stroke, whose touched river reaches are previewed in red (they go whole).
## The width is the brush size, never below the depth class's narrowest channel
## (radius_for()).

enum Shape { RIVER, POND }

const TINT := Color(0.56, 0.84, 1.0)
const ERASE_TINT := Color(1.0, 0.52, 0.42)
const SHADOW := Color(0.05, 0.04, 0.05, 0.55)
## A river point is recorded once the pointer's ground point is this far (metres) from the
## last; the shortest line a release carves.
const RIVER_DECIMATE_M := 0.6
const WIDTH_DECIMATE := 0.6
const RIVER_MIN_LENGTH_M := 2.0
## The pond dab's growth with dwell (1 + POND_DWELL_GROW at BrushTool.DWELL_MAX).
const POND_DWELL_GROW := 0.35
## The ribbon's chevron spacing, and its fill's alpha upstream and downstream (the gradient
## shows the flow too).
const RIBBON_ARROW_M := 2.5
const RIBBON_ALPHA_UP := 0.12
const RIBBON_ALPHA_DOWN := 0.34
## Refusal reasons (BrushTool.water_refused).
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
## A river being drawn: its recorded points (world XZ).
var river := PackedVector2Array()
var drawing: bool = false
## The last river's smoothed line and half-width, drawn faintly while its carve computes.
var held := PackedVector2Array()
var held_radius: float = 0.0
## Pond stroke dabs painted so far, for the preview: Vector3(x, z, radius) world.
var pond_dabs := PackedVector3Array()

var _refusal: String = ""


## The river half-width or pond brush radius for brush size `radius` and depth class
## `depth_class`: never below the narrowest channel that reaches the class's depth
## (WaterCarve.min_half_width: ankle 0.44 m, waist 1.33 m, deep 2.96 m) nor past the widest
## river (WaterBody.MAX_HALF_WIDTH_M). Pure.
static func radius_for(radius: float, depth_class: int) -> float:
	var narrowest := maxf(WaterCarve.min_half_width(depth_class), WaterBody.MIN_HALF_WIDTH_M)
	return clampf(radius, narrowest, WaterBody.MAX_HALF_WIDTH_M)


## `points` with `p` appended when it lies at least `spacing` from the last point (always
## when empty): the river line's decimation by distance. Pure.
static func decimate(points: PackedVector2Array, p: Vector2, spacing: float) -> PackedVector2Array:
	var out := points.duplicate()
	if out.is_empty() or out[-1].distance_to(p) >= spacing:
		out.append(p)
	return out


## A drawn river line smoothed for carving and preview: two Chaikin passes
## (WaterGeometry.chaikin), which keep both ends, so a shaky hand or a corner reads as a
## meander and the flow still starts and ends where the author pressed and released. Pure.
static func smooth_line(points: PackedVector2Array) -> PackedVector2Array:
	var widths := PackedFloat32Array()
	widths.resize(points.size())
	return WaterGeometry.chaikin(points, widths, 2)[0]


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


## The three world points of a chevron at `at` pointing along `tangent` (unit), `size` metres
## across: a barb either side behind, the tip ahead. Pure.
static func chevron(at: Vector2, tangent: Vector2, size: float) -> PackedVector2Array:
	var normal := Vector2(-tangent.y, tangent.x)
	return PackedVector2Array(
		[
			at - tangent * size * 0.2 + normal * size * 0.45,
			at + tangent * size * 0.3,
			at - tangent * size * 0.2 - normal * size * 0.45,
		]
	)


## The length of a polyline (metres). Pure.
static func line_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


## The readout under the ring: "River  Waist  40 ft" while a river is drawn (`length_m` > 0,
## in the level's units), "River  Waist" or "Pond  Deep" otherwise. Pure.
static func readout(
	shape_id: int, depth_class: int, length_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := "River" if shape_id == Shape.RIVER else "Pond"
	var text := "%s  %s" % [title, DEPTH_LABELS[clampi(depth_class, 0, 2)]]
	if length_m > 0.0:
		var value := roundi(ScaleUtils.world_to_display(length_m, cell_m, per_cell))
		text += "  %d %s" % [value, label]
	return text


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
	drawing = true
	river = decimate(PackedVector2Array(), Vector2(hit.x, hit.z), RIVER_DECIMATE_M)
	held = PackedVector2Array()
	return false


## Why the last begin() or carve() made nothing, or "".
func refusal() -> String:
	return _refusal


## One frame with the pointer's ground point at `hit` (INF: none), the river `half_width`
## wide: records the line (a point every RIVER_DECIMATE_M, or every WIDTH_DECIMATE
## half-widths for a wide river, whose wiggles finer than its width would only crease it),
## and drops the faint ribbon once its carve has landed.
func track(editor: AuthoringEditor, hit: Vector3, half_width: float) -> void:
	if drawing and hit != Vector3.INF:
		var spacing := maxf(RIVER_DECIMATE_M, half_width * WIDTH_DECIMATE)
		river = decimate(river, Vector2(hit.x, hit.z), spacing)
	if not held.is_empty() and (editor == null or not editor.water.is_working()):
		held = PackedVector2Array()


## Carves the river drawn so far (the release) with half-width `half_width`. Returns false
## when refused (refusal() says why; a line too short to carve is silently dropped).
func carve(editor: AuthoringEditor, half_width: float) -> bool:
	_refusal = ""
	drawing = false
	var line := smooth_line(river)
	river = PackedVector2Array()
	if line_length(line) < RIVER_MIN_LENGTH_M:
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
	drawing = false
	river = PackedVector2Array()
	pond_dabs = PackedVector3Array()


## The readout text now: "Erase water" when `erasing`, else readout() with the line's length
## while a river is drawn.
func readout_text(erasing: bool, cell_m: float, per_cell: float, label: String) -> String:
	if erasing:
		return "Erase water"
	var length := line_length(river) if drawing else 0.0
	return readout(shape, depth, length, cell_m, per_cell, label)


## The previews under the ring on `canvas` (see the header): the river being drawn up to the
## pointer at `hit` with half-width `half_width`, or the faint one whose carve computes; with
## a stroke held (`stroking`), the reaches an erase (`erasing`) will remove, or a pond's dabs.
func draw(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	half_width: float,
	stroking: bool,
	erasing: bool
) -> void:
	var ground := func(xz: Vector2) -> Vector2:
		var p := Vector3(xz.x, 0.0, xz.y)
		p.y = editor.ground_height_at(p) + 0.05
		return camera.unproject_position(p)
	if drawing and not river.is_empty():
		var live := river.duplicate()
		var tip := Vector2(hit.x, hit.z)
		if live[-1].distance_to(tip) > 0.05:
			live.append(tip)
		var flow := flow_line(smooth_line(live), ground_reader(editor))
		draw_ribbon(canvas, ground, flow, half_width, TINT, 1.0, true)
	elif not held.is_empty():
		draw_ribbon(canvas, ground, held, held_radius, TINT, 0.5, true)
	if not stroking:
		return
	if erasing:
		for body in editor.water.erase_touched():
			var course := PackedVector2Array()
			for p: Vector2 in WaterGeometry.river_course(body)[0]:
				var world := editor.to_world(Vector3(p.x, 0.0, p.y))
				course.append(Vector2(world.x, world.z))
			var half := body.half_widths[0] * editor.map_scale()
			draw_ribbon(canvas, ground, course, half, ERASE_TINT, 1.0, false)
	elif shape == Shape.POND:
		for dab in pond_dabs:
			_fill_disc(canvas, camera, editor, Vector2(dab.x, dab.y), dab.z)


## A band `radius` either side of `line` (world XZ; `ground` maps a point to the screen on
## the ground), filled with a gradient from upstream (faint) to downstream (stronger) and
## edged; with `arrows`, chevrons every RIBBON_ARROW_M point the way the water will flow.
## `strength` scales every alpha. Drawn with explicit indices, never triangulated.
static func draw_ribbon(
	canvas: Control,
	ground: Callable,
	line: PackedVector2Array,
	radius: float,
	tint: Color,
	strength: float,
	arrows: bool
) -> void:
	var n := line.size()
	if n < 2:
		return
	var total := line_length(line)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var walked := 0.0
	var last_l := Vector2.INF
	var last_r := Vector2.INF
	for i in n:
		if i > 0:
			walked += line[i - 1].distance_to(line[i])
		var tangent := (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var world_l := line[i] + normal * radius
		var world_r := line[i] - normal * radius
		# The inside of a bend tighter than the ribbon never runs backwards (no twisted quads).
		if last_l != Vector2.INF and (world_l - last_l).dot(tangent) < 0.0:
			world_l = last_l
		if last_r != Vector2.INF and (world_r - last_r).dot(tangent) < 0.0:
			world_r = last_r
		last_l = world_l
		last_r = world_r
		var l: Vector2 = ground.call(world_l)
		var r: Vector2 = ground.call(world_r)
		left.append(l)
		right.append(r)
		points.append(l)
		points.append(r)
		var alpha := lerpf(RIBBON_ALPHA_UP, RIBBON_ALPHA_DOWN, walked / maxf(total, 0.001))
		colors.append(Color(tint, alpha * strength))
		colors.append(Color(tint, alpha * strength))
	var indices := PackedInt32Array()
	for i in n - 1:
		var a := 2 * i
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), indices, points, colors
	)
	for edge in [left, right]:
		canvas.draw_polyline(edge, Color(SHADOW, 0.4 * strength), 3.0, true)
		canvas.draw_polyline(edge, Color(tint, 0.85 * strength), 1.5, true)
	if not arrows:
		return
	var next := RIBBON_ARROW_M * 0.5
	walked = 0.0
	for i in n - 1:
		var length := line[i].distance_to(line[i + 1])
		var tangent := (line[i + 1] - line[i]) / maxf(length, 0.0001)
		var size := minf(radius, 1.5)
		while next <= walked + length:
			var at := line[i] + tangent * (next - walked)
			var arrow := PackedVector2Array()
			for p in chevron(at, tangent, size):
				arrow.append(ground.call(p))
			canvas.draw_polyline(arrow, Color(SHADOW, 0.3 * strength), 3.5, true)
			canvas.draw_polyline(arrow, Color(1.0, 1.0, 1.0, 0.7 * strength), 2.0, true)
			next += RIBBON_ARROW_M
		walked += length


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
