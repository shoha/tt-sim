class_name PathLay
extends RefCounted

## The switch-off Path release, spread over frames (card terraform-p2-path-polish). With the terrain
## core off a drawn path is one Paint stroke along the line: capsules of half the width plus a soft
## edge, one per LAY_SPACING metres (PathBrush.lay). Its SurfaceStroke dabs are GDScript, about
## 0.3 ms each, so a 54 m path laid in its release frame cost 27-35 ms of dabs alone and a 68 ms
## frame in all (quiet, 320 ft map). A PathLay holds the stroke's dabs and applies them a frame at a
## time: each frame up to `budget_usec` of dabs (at least one), then the frame's ground update
## (AuthoringEditor.flush over the rect those dabs changed); the frame that applies the last dab
## also ends the stroke when time is left, else the next one does. The dabs are the same, in the
## same order, on the same document, so the bytes and the history entry equal the at-once release.
##
## The stroke stays open meanwhile (AuthoringEditor.is_stroking), so anything that ends strokes
## (a new press, undo, a save, the height-work drain) drains the rest at once and ends it first
## (AuthoringEditor._end_surface_stroke calls drain()). Nothing waits on a worker.

## A frame's dab budget (microseconds). About 13 dabs at 320 ft: a 54 m path lands in 8-9 frames.
const BUDGET_USEC := 4000

var _editor_ref: WeakRef = null
## Per dab (dabs_of()): from x, z, to x, z (world), radius, seconds; 6 floats a dab.
var _dabs := PackedFloat32Array()
var _next := 0


## A lay of `dabs` (dabs_of()) on `editor`, whose surface stroke is already begun.
static func create(editor: AuthoringEditor, dabs: PackedFloat32Array) -> PathLay:
	var lay := PathLay.new()
	lay._editor_ref = weakref(editor)
	lay._dabs = dabs
	return lay


## The dabs of a switch-off path along `points` (world XZ, resampled every `spacing` metres) of
## capsule `radius`, `seconds` of exposure per `spacing` metres: from.x, from.z, to.x, to.z, radius,
## seconds per dab. Pure.
static func dabs_of(
	points: PackedVector2Array, radius: float, seconds: float, spacing: float
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length <= 0.0:
			continue
		out.append_array(
			PackedFloat32Array(
				[
					points[i].x,
					points[i].y,
					points[i + 1].x,
					points[i + 1].y,
					radius,
					seconds * length / spacing,
				]
			)
		)
	return out


## One frame of `editor`'s lay in progress (AuthoringEditor.path_lay; the release frame and then
## AuthoringEditor.step_height_work): its step(), and once it is done the stroke's end.
static func frame(editor: AuthoringEditor) -> void:
	var lay := editor.path_lay
	if lay != null and lay.step():
		editor.path_lay = null
		editor.end_stroke()


## Dabs not yet applied.
func remaining() -> int:
	@warning_ignore("integer_division")
	return (_dabs.size() - _next) / 6


## One frame: applies dabs for up to `budget_usec` (at least one) and flushes them to the ground.
## Returns true when every dab is applied and time is left in the budget to end the stroke now.
func step(budget_usec: int = BUDGET_USEC) -> bool:
	var editor := _editor()
	if editor == null:
		return true
	var started := Time.get_ticks_usec()
	var applied := false
	while _next < _dabs.size():
		if applied and Time.get_ticks_usec() - started >= budget_usec:
			break
		_apply(editor)
		applied = true
	if applied:
		editor.flush()
	return _next >= _dabs.size() and Time.get_ticks_usec() - started < budget_usec


## Applies every dab left at once (the stroke is about to end).
func drain() -> void:
	var editor := _editor()
	if editor == null:
		return
	while _next < _dabs.size():
		_apply(editor)


func _apply(editor: AuthoringEditor) -> void:
	var d := _dabs.slice(_next, _next + 6)
	_next += 6
	editor.stroke_dab(Vector3(d[0], 0.0, d[1]), Vector3(d[2], 0.0, d[3]), d[4], d[5])


func _editor() -> AuthoringEditor:
	return _editor_ref.get_ref() as AuthoringEditor if _editor_ref != null else null
