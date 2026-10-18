class_name StrokePath
extends RefCounted

## A line drawn on the ground, captured and shaped: what a press, a drag and a release become
## when a brush draws a line instead of painting dabs (the Water tool's river, the Fire tool's
## Line, Start a fire's path). Lifted out of WaterBrush (card F5), which still calls it, so
## every line shape records, ends and smooths the same way. Pure: world XZ points in, points
## out.
##
## Capture. While the pointer drags, decimate() records its ground point once it lies a
## spacing from the last (DECIMATE_M for a river); with_tip() ends the line at the release
## point, which decimation usually dropped; smooth_line() runs two Chaikin passes that keep
## both ends, so a shaky hand or a corner reads as a curve and the line still starts and ends
## where the author pressed and released; line_length() measures it.
##
## Laying. resample() spaces a line evenly by arc length (at most a number of points, at least
## a spacing apart), so what a line lays depends on its shape, never on how fast or how
## finely it was drawn; capped() cuts a line at a length (Start a fire's path stops growing at
## MAX_LENGTH_M, about a 200 ft map's width). Design:
## docs/plans/2026-10-11-fire-features/design.md sections 2 and 3c.

## A point is recorded once the pointer's ground point lies this far (metres) from the last.
const DECIMATE_M := 0.6
## The shortest line a release makes anything of (a river's carve, a line of fire).
const MIN_LENGTH_M := 2.0
## The longest fire path, and the most points it is resampled to (at least 1 m apart).
const MAX_LENGTH_M := 64.0
const MAX_POINTS := 64
const MIN_SPACING_M := 1.0


## `points` with `p` appended when it lies at least `spacing` from the last point (always
## when empty): a drawn line's decimation by distance.
static func decimate(points: PackedVector2Array, p: Vector2, spacing: float) -> PackedVector2Array:
	var out := points.duplicate()
	if out.is_empty() or out[-1].distance_to(p) >= spacing:
		out.append(p)
	return out


## A drawn line smoothed for laying and preview: two Chaikin passes (WaterGeometry.chaikin),
## which keep both ends, so a shaky hand or a corner reads as a curve and the line still
## starts and ends where the author pressed and released.
static func smooth_line(points: PackedVector2Array) -> PackedVector2Array:
	var widths := PackedFloat32Array()
	widths.resize(points.size())
	return WaterGeometry.chaikin(points, widths, 2)[0]


## The recorded line `points` ended at the pointer's last point `tip` (Vector2.INF: none):
## decimation records a point only `spacing` from the last, so the release point itself was
## usually dropped, up to `spacing` plus a frame's travel short of where the author let go
## (P6-3: an ankle stream released 0.36 m inside the map edge ended over 1 m inside it and got
## no exit). A tip closer than half the spacing replaces the last point instead of crowding
## it.
static func with_tip(
	points: PackedVector2Array, tip: Vector2, spacing: float
) -> PackedVector2Array:
	var out := points.duplicate()
	if tip == Vector2.INF or out.is_empty() or out[-1].distance_to(tip) < 1e-4:
		return out
	if out.size() >= 2 and out[-1].distance_to(tip) < spacing * 0.5:
		out[-1] = tip
	else:
		out.append(tip)
	return out


## The length of a polyline (metres).
static func line_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


## `points` resampled evenly by arc length: the same two ends, and as many points as fit at
## least `min_spacing` apart (metres; 0: no floor), never more than `max_points` nor fewer
## than two, all the same distance apart along the line. A line shorter than its spacing keeps
## its two ends; one with fewer than two points, or no length, comes back as it was.
static func resample(
	points: PackedVector2Array, max_points: int, min_spacing: float
) -> PackedVector2Array:
	var total := line_length(points)
	if points.size() < 2 or total <= 0.0:
		return points.duplicate()
	var count := max_points
	if min_spacing > 0.0:
		count = mini(floori(total / min_spacing) + 1, max_points)
	count = maxi(count, 2)
	var step := total / float(count - 1)
	var out := PackedVector2Array([points[0]])
	var segment := 0
	var walked := 0.0
	var length := points[0].distance_to(points[1])
	for k in range(1, count - 1):
		var at := step * k
		while segment < points.size() - 2 and walked + length < at:
			walked += length
			segment += 1
			length = points[segment].distance_to(points[segment + 1])
		var t := clampf((at - walked) / length, 0.0, 1.0) if length > 0.0 else 0.0
		out.append(points[segment].lerp(points[segment + 1], t))
	out.append(points[-1])
	return out


## `points` cut at `max_length` metres along the line (the last point moved back onto it), or
## the whole line when it is no longer.
static func capped(points: PackedVector2Array, max_length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	var walked := 0.0
	for i in range(1, points.size()):
		var length := points[i - 1].distance_to(points[i])
		if walked + length > max_length:
			var t := (max_length - walked) / length if length > 0.0 else 0.0
			out.append(points[i - 1].lerp(points[i], clampf(t, 0.0, 1.0)))
			return out
		walked += length
		out.append(points[i])
	return out
