class_name LineGesture
extends RefCounted

## What every line tool does while a line is drawn (card F5e: Water's River and Fire's Line),
## in one place so the two cannot drift. The press begins the line at the pointer's ground point
## (begin()); every frame records the pointer once it lies spacing() from the last point
## (StrokePath.DECIMATE_M, or WIDTH_DECIMATE half-widths for a wide line, whose wiggles finer
## than its width would only crease it; track()). The line a release makes is the recorded
## points ended at the pointer (StrokePath.with_tip) and Chaikin-smoothed (line()), and the
## preview draws that same line out to the pointer (live()); a release under
## StrokePath.MIN_LENGTH_M makes nothing (finish()); Esc or RMB mid-drag drops the line (the
## mode's cancel calls reset()), the tool staying armed; and the chip under the ring reads
## "<label>  N <unit>", the line's length in the level's units, while it is drawn (chip()).
## What a release does with the line (a river's carve, a line of fire's lay), the ring's width
## (the mode's stroke_radius) and the ribbon's style (LineRibbon) are the tool's own.

## A wide line records a point every this many half-widths (never closer than DECIMATE_M).
const WIDTH_DECIMATE := 0.6

## The recorded points (world XZ), and whether a line is being drawn.
var points := PackedVector2Array()
var drawing: bool = false
## The pointer's last ground point (world XZ; Vector2.INF: none), which the line ends at
## whether or not decimation recorded it, and that point's height (world).
var tip: Vector2 = Vector2.INF
var height: float = 0.0


## The capture spacing for a line `half_width` metres wide. Pure.
static func spacing(half_width: float) -> float:
	return maxf(StrokePath.DECIMATE_M, half_width * WIDTH_DECIMATE)


## True when `drawn` is long enough for a release to make anything of. Pure.
static func long_enough(drawn: PackedVector2Array) -> bool:
	return StrokePath.line_length(drawn) >= StrokePath.MIN_LENGTH_M


## The chip under the ring: `label`, then while a line `length_m` long is drawn (above 0) two
## spaces and its length in the level's units (`cell_m` metres a cell, `per_cell` units a cell,
## named `unit`): "Line of fire  40 ft". Pure.
static func chip(
	label: String, length_m: float, cell_m: float, per_cell: float, unit: String
) -> String:
	if length_m <= 0.0:
		return label
	var shown := roundi(ScaleUtils.world_to_display(length_m, cell_m, per_cell))
	return "%s  %d %s" % [label, shown, unit]


## Begins a line at the pointer's ground point `hit`.
func begin(hit: Vector3) -> void:
	var at := Vector2(hit.x, hit.z)
	points = PackedVector2Array([at])
	tip = at
	height = hit.y
	drawing = true


## One frame with the pointer's ground point at `hit` (Vector3.INF: none) on a line
## `half_width` metres wide: a point once it lies spacing() from the last.
func track(hit: Vector3, half_width: float) -> void:
	if not drawing or hit == Vector3.INF:
		return
	var at := Vector2(hit.x, hit.z)
	points = StrokePath.decimate(points, at, spacing(half_width))
	tip = at
	height = hit.y


## The line a release makes now: the recorded points ended at the pointer, smoothed.
func line() -> PackedVector2Array:
	return StrokePath.smooth_line(StrokePath.with_tip(points, tip, StrokePath.DECIMATE_M))


## The line the preview draws with the pointer at `hit` (Vector3.INF: where it last was): the
## line a release there would make.
func live(hit: Vector3) -> PackedVector2Array:
	var at := tip if hit == Vector3.INF else Vector2(hit.x, hit.z)
	return StrokePath.smooth_line(StrokePath.with_tip(points, at, StrokePath.DECIMATE_M))


## The length of the line a release makes now (metres; 0 while none is drawn).
func length() -> float:
	return StrokePath.line_length(line()) if drawing else 0.0


## The chip for `label` now on `brush` (its level's units; chip()).
func readout(label: String, brush: BrushTool) -> String:
	return chip(label, length(), brush.unit_cell_m, brush.unit_per_cell, brush.unit_label)


## Ends the line (a release): the line it makes, or an empty one when none was drawn or it is
## under StrokePath.MIN_LENGTH_M. The gesture is reset either way.
func finish() -> PackedVector2Array:
	var out := line() if drawing else PackedVector2Array()
	reset()
	return out if long_enough(out) else PackedVector2Array()


## Drops the line (a cancel, or after a release).
func reset() -> void:
	drawing = false
	points = PackedVector2Array()
	tip = Vector2.INF
