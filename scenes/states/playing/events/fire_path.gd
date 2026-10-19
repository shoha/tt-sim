class_name FirePath
extends RefCounted

## A fire along a path (Start a fire's Path shape, TerrainEvent.path; design 3d): the line's
## geometry in one place for the motion (FireSweep), the change (TerrainEvents._burn) and the
## cursor (IgniteMode), so the three agree on which trees burn and where snags will stand.
##
## Along the line, a point's arc length (arcs(), project()) is where the front reaches it: the
## front runs from the first point to the last. The trees a path burns stand within its
## half-width of the line, in the capsules round its segments (trees_along(): every scatter
## cell a capsule touches read once, each tree kept once, with its arc and its distance off
## the line), sorted along the arc; past `limit` (MAX_TREES) as many spread evenly along the
## arc are kept (thin()), and the rest burn under the smoke unanimated, swapped to snags by
## the change.
##
## The forest spans (forest_spans()) are the arc ranges within reach of a tree found there
## (its arc, a half-width either way) widened by SPAN_WIDEN half-widths more: the burnt biome
## is painted over them only, so snags stand only where trees stood (design 7, Q3: a path
## crosses meadow far more often than a ring does), and the ash lies along the whole path.
## runs() splits a line into its forest and open stretches, which the cursor draws apart.
## Pure but for trees_along's scatter search.

## The most trees one path's motion animates (FireSweep's pools are sized for it).
const MAX_TREES := 96
## A search's limit that keeps every tree (the change's spans, the cursor's).
const ALL_TREES := 1 << 20
## A path's strokes (TerrainEvents._burn) are capsules a segment, each of radius CAPSULE_REACH
## times a circle's dab, each its share of the dab's seconds (capsule_seconds()).
const CAPSULE_REACH := 1.06
## How far a forest span runs past a tree's own reach, in half-widths.
const SPAN_WIDEN := 1.0


## The arc length at each point of `line` (metres from the first; the last is its length).
## Pure.
static func arcs(line: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(line.size())
	var walked := 0.0
	for i in line.size():
		if i > 0:
			walked += line[i - 1].distance_to(line[i])
		out[i] = walked
	return out


## The point of `line` (its arcs `along`) nearest map point `p`: x its arc length, y the
## distance to it. A point past either end is measured to that end. Pure.
static func project(line: PackedVector2Array, along: PackedFloat32Array, p: Vector2) -> Vector2:
	if line.size() < 2:
		return Vector2(0.0, p.distance_to(line[0]) if not line.is_empty() else INF)
	var best := Vector2(0.0, INF)
	for i in line.size() - 1:
		var a := line[i]
		var ab := line[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		var distance := p.distance_to(a + ab * t)
		if distance < best.y:
			best = Vector2(lerpf(along[i], along[i + 1], t), distance)
	return best


## The point of `line` (its arcs `along`) `s` metres along it and its direction there: x, y
## the point, z, w the unit tangent. Pure.
static func frame_at(line: PackedVector2Array, along: PackedFloat32Array, s: float) -> Vector4:
	var n := line.size()
	if n < 2:
		return Vector4(line[0].x, line[0].y, 1.0, 0.0) if n == 1 else Vector4(0, 0, 1, 0)
	var i := 0
	while i < n - 2 and along[i + 1] < s:
		i += 1
	var span := maxf(along[i + 1] - along[i], 1e-6)
	var t := clampf((s - along[i]) / span, 0.0, 1.0)
	var at := line[i].lerp(line[i + 1], t)
	var tangent := (line[i + 1] - line[i]).normalized()
	return Vector4(at.x, at.y, tangent.x, tangent.y)


## The part of `line` (its arcs `along`) from arc `from` to arc `to`, its ends cut onto the
## line. Pure.
static func span_line(
	line: PackedVector2Array, along: PackedFloat32Array, from: float, to: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line.size() < 2 or to <= from:
		return out
	var start := frame_at(line, along, from)
	out.append(Vector2(start.x, start.y))
	for i in line.size():
		if along[i] > from and along[i] < to:
			out.append(line[i])
	var end := frame_at(line, along, to)
	out.append(Vector2(end.x, end.y))
	return out


## The seconds of exposure one capsule `length` metres long and `radius` wide takes in a line
## of such capsules, so that the line's centre gathers what one dab of `seconds` gives its
## centre. Every capsule a sample is within reach of adds its whole falloff (MaskStroke.dab:
## (1 - d^2 / r^2)^2 of its distance to the segment), so a sample on the centre line of a line
## of capsules gathers about 1 + 16 r / (15 length) dabs' worth: its own segment's, and the
## falloff's integral along the line over the segments' spacing. Across the line that sum falls
## as u^2.5 against a dab's u^2 (u = 1 - d^2 / r^2), so CAPSULE_REACH widens the capsule for
## the rim at the half-width to take a dab's there. Pure.
static func capsule_seconds(seconds: float, length: float, radius: float) -> float:
	if length <= 0.0:
		return seconds
	return seconds / (1.0 + 16.0 * radius / (15.0 * length))


## The drawn trees of `scatter` within `half_width` of `line` (map XZ), assets whose id starts
## with `skip` passed over (a fire's own snags), sorted along the line and thinned to `limit`
## (thin()): ForestFall.trees_near's entries with "distance" off the line and "arc" along it.
static func trees_along(
	scatter: AuthoredScatter,
	line: PackedVector2Array,
	half_width: float,
	skip: String = "",
	limit: int = MAX_TREES
) -> Array[Dictionary]:
	if scatter == null or line.is_empty():
		return []
	var cells := {}
	if line.size() == 1:
		ForestFall.add_cells(cells, Rect2(line[0], Vector2.ZERO).grow(half_width))
	for i in line.size() - 1:
		ForestFall.add_cells(cells, Rect2(line[i], Vector2.ZERO).expand(line[i + 1]).grow(half_width))
	var along := arcs(line)
	var measure := func(at: Vector2) -> float:
		var off := project(line, along, at).y
		return off if off <= half_width else -1.0
	var found := ForestFall.trees_in(scatter, cells, measure, skip)
	for tree in found:
		var base: Transform3D = tree.base
		tree.arc = project(line, along, Vector2(base.origin.x, base.origin.z)).x
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.arc < b.arc)
	return thin(found, limit)


## `found` (sorted along the line) cut to `limit` entries spread evenly along it: the first and
## the last kept, the rest at even steps between. Pure.
static func thin(found: Array[Dictionary], limit: int) -> Array[Dictionary]:
	if found.size() <= limit:
		return found
	var kept: Array[Dictionary] = []
	if limit <= 0:
		return kept
	if limit == 1:
		kept.append(found[0])
		return kept
	var last := found.size() - 1
	for k in limit:
		kept.append(found[roundi(float(k) * float(last) / float(limit - 1))])
	return kept


## The arc ranges of a path `total` metres long within reach of the trees at arcs `tree_arcs`
## (one half-width either way, widened by SPAN_WIDEN half-widths more), merged where they
## meet, in order along the path, each cut to the path: x from, y to. Pure.
static func forest_spans(
	tree_arcs: PackedFloat32Array, half_width: float, total: float
) -> PackedVector2Array:
	var sorted := tree_arcs.duplicate()
	sorted.sort()
	var reach := half_width * (1.0 + SPAN_WIDEN)
	var spans := PackedVector2Array()
	for arc in sorted:
		var span := Vector2(maxf(arc - reach, 0.0), minf(arc + reach, total))
		if not spans.is_empty() and span.x <= spans[-1].y:
			spans[-1] = Vector2(spans[-1].x, maxf(spans[-1].y, span.y))
		else:
			spans.append(span)
	return spans


## A path `total` metres long cut by its forest `spans` into stretches in order: [from, to,
## true over a forest span, false over open ground], together covering the whole path. Pure.
static func runs(spans: PackedVector2Array, total: float) -> Array:
	var out: Array = []
	var at := 0.0
	for span in spans:
		if span.x > at:
			out.append([at, span.x, false])
		if span.y > maxf(span.x, at):
			out.append([maxf(span.x, at), span.y, true])
		at = maxf(at, span.y)
	if at < total:
		out.append([at, total, false])
	return out
