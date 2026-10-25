class_name ResponseCurve
extends RefCounted

## The model behind the designer's response-curve editor: a rule's `response.<axis>` curve as a
## list of [x, y] points (LibraryContracts.RESPONSE_MIN_POINTS to RESPONSE_MAX_POINTS, x strictly
## ascending inside the axis range, y 0 to 1, piecewise linear, flat beyond the ends), the
## operations the widget performs on it (add, remove, move with snapping, preset shapes) and
## the sampling the engine does (ScatterPlan.curve_value). Pure: every function takes a points
## array and returns a new one, so the designer model can record the edit as a patch and undo
## it. The widget (scenes/ui/biome_designer/curve_editor.gd) draws and drags; the rules live here.

const PRESETS: Array[String] = ["flat", "ramp_up", "ramp_down", "bell", "band"]
const PRESET_LABELS := {
	"flat": "Flat",
	"ramp_up": "Ramp up",
	"ramp_down": "Ramp down",
	"bell": "Bell",
	"band": "Band",
}
## The span the editor shows per axis. The contract allows more (height -500 to 5000); a curve
## with points beyond it widens the view (display_range).
const DISPLAY_RANGE := {
	"slope": [0.0, 90.0],
	"height": [-2.0, 12.0],
	"wet": [0.0, 1.0],
	"water_dist": [0.0, 60.0],
}
## Snap step per axis for x, and the step of y.
const SNAP_X := {"slope": 1.0, "height": 0.25, "wet": 0.05, "water_dist": 1.0}
const SNAP_Y := 0.05
## The least gap between two neighbouring points, as a share of the displayed span.
const MIN_GAP_SHARE := 0.01
const AXIS_LABELS := {
	"slope": "Slope (degrees)",
	"height": "Height (m)",
	"wet": "Shore wetness",
	"water_dist": "Distance to water (m)",
}


## The axes the engine evaluates, in the order the editor lists them.
static func axes() -> Array[String]:
	var out: Array[String] = []
	for axis: String in LibraryContracts.RESPONSE_AXES:
		if not axis in LibraryContracts.RESPONSE_UNSUPPORTED:
			out.append(axis)
	return out


## The x span the editor draws for `axis`, widened to hold `points`.
static func display_range(axis: String, points: Array = []) -> Vector2:
	var base: Array = DISPLAY_RANGE.get(axis, [0.0, 1.0])
	var low := float(base[0])
	var high := float(base[1])
	for point: Variant in points:
		if point is Array and (point as Array).size() == 2:
			low = minf(low, float((point as Array)[0]))
			high = maxf(high, float((point as Array)[0]))
	return Vector2(low, high)


## The contract's allowed span for `axis`.
static func axis_range(axis: String) -> Vector2:
	var span: Array = LibraryContracts.RESPONSE_AXES.get(axis, [0.0, 1.0])
	return Vector2(float(span[0]), float(span[1]))


## The curve of a preset shape over the displayed span of `axis`.
static func preset(axis: String, shape: String) -> Array:
	var span := display_range(axis)
	var low := span.x
	var length := span.y - span.x
	var shape_points: Array = []
	match shape:
		"ramp_up":
			shape_points = [[0.0, 0.0], [1.0, 1.0]]
		"ramp_down":
			shape_points = [[0.0, 1.0], [1.0, 0.0]]
		"bell":
			shape_points = [[0.0, 0.0], [0.25, 0.75], [0.5, 1.0], [0.75, 0.75], [1.0, 0.0]]
		"band":
			shape_points = [
				[0.0, 0.0], [0.3, 0.0], [0.38, 1.0], [0.62, 1.0], [0.7, 0.0], [1.0, 0.0]
			]
		_:
			shape_points = [[0.0, 1.0], [1.0, 1.0]]
	var out: Array = []
	for point: Array in shape_points:
		out.append([_round(low + float(point[0]) * length), float(point[1])])
	return out


## The curve that changes nothing: 1 everywhere.
static func flat(axis: String) -> Array:
	return preset(axis, "flat")


## Whether `points` is a curve that leaves the density alone (every y is 1).
static func is_flat(points: Array) -> bool:
	for point: Variant in points:
		if not point is Array or float((point as Array)[1]) < 1.0:
			return false
	return true


## The engine's value at `x`: piecewise linear, flat beyond the ends; 1 for no curve.
static func sample(points: Array, x: float) -> float:
	if points.size() < 2:
		return 1.0
	var first: Array = points[0]
	if x <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var a: Array = points[i - 1]
		var b: Array = points[i]
		if x <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var t := (x - float(a[0])) / span if span > 0.0 else 1.0
			return lerpf(float(a[1]), float(b[1]), t)
	return float((points[points.size() - 1] as Array)[1])


## `value` rounded to a multiple of `step` (0 or less: unchanged).
static func snap(value: float, step: float) -> float:
	return value if step <= 0.0 else _round(roundf(value / step) * step)


## `points` with a new point at x (y: the curve's value there when -1). No change at the point
## limit or where a point already is.
static func add_point(axis: String, points: Array, x: float, y: float = -1.0) -> Array:
	var out := _copy(points)
	if out.size() >= LibraryContracts.RESPONSE_MAX_POINTS:
		return out
	var span := axis_range(axis)
	var at := clampf(snap(x, SNAP_X.get(axis, 0.0)), span.x, span.y)
	var gap := _min_gap(axis, points)
	for point: Array in out:
		if absf(float(point[0]) - at) < gap:
			return out
	var value := sample(points, at) if y < 0.0 else clampf(snap(y, SNAP_Y), 0.0, 1.0)
	var index := 0
	while index < out.size() and float((out[index] as Array)[0]) < at:
		index += 1
	out.insert(index, [at, value])
	return out


## `points` without point `index`; a curve keeps at least RESPONSE_MIN_POINTS.
static func remove_point(points: Array, index: int) -> Array:
	var out := _copy(points)
	if out.size() <= LibraryContracts.RESPONSE_MIN_POINTS or index < 0 or index >= out.size():
		return out
	out.remove_at(index)
	return out


## `points` with point `index` moved to (x, y): snapped, y held to 0..1, x held between its
## neighbours (a point never passes one) and inside the axis range. `snap_it` false moves
## freely.
static func move_point(
	axis: String, points: Array, index: int, x: float, y: float, snap_it: bool = true
) -> Array:
	var out := _copy(points)
	if index < 0 or index >= out.size():
		return out
	var span := axis_range(axis)
	var gap := _min_gap(axis, points)
	var low := span.x if index == 0 else float((out[index - 1] as Array)[0]) + gap
	var high := span.y if index == out.size() - 1 else float((out[index + 1] as Array)[0]) - gap
	var nx := snap(x, SNAP_X.get(axis, 0.0)) if snap_it else x
	var ny := snap(y, SNAP_Y) if snap_it else y
	if low > high:
		return out
	out[index] = [_round(clampf(nx, low, high)), clampf(ny, 0.0, 1.0)]
	return out


## Why the curve is not valid on `axis` ("" when it is): LibraryContracts.response_problem.
static func problem(axis: String, points: Array) -> String:
	return LibraryContracts.response_problem(axis, points)


## A short readable line for a curve: "flat", "4 points, 0 to 1".
static func describe(points: Array) -> String:
	if points.is_empty():
		return "off"
	if is_flat(points):
		return "flat"
	var low := 1.0
	var high := 0.0
	for point: Array in points:
		low = minf(low, float(point[1]))
		high = maxf(high, float(point[1]))
	return "%d points, %s to %s" % [points.size(), _text(low), _text(high)]


## Which preset shape `points` is (within tolerance), or "" for a custom curve.
static func preset_of(axis: String, points: Array) -> String:
	for shape in PRESETS:
		var candidate := preset(axis, shape)
		if candidate.size() != points.size():
			continue
		var same := true
		for i in candidate.size():
			var a: Array = candidate[i]
			var b: Array = points[i]
			same = (
				same
				and absf(float(a[0]) - float(b[0])) < 0.01
				and absf(float(a[1]) - float(b[1])) < 0.01
			)
		if same:
			return shape
	return ""


static func _copy(points: Array) -> Array:
	var out: Array = []
	for point: Variant in points:
		out.append([float((point as Array)[0]), float((point as Array)[1])])
	return out


static func _min_gap(axis: String, points: Array) -> float:
	var span := display_range(axis, points)
	return maxf((span.y - span.x) * MIN_GAP_SHARE, 0.0001)


static func _round(value: float) -> float:
	return snappedf(value, 0.0001)


static func _text(value: float) -> String:
	return str(snappedf(value, 0.01))
