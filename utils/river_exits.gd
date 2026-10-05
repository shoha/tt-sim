class_name RiverExits
extends RefCounted

## Where a map's rivers leave it, and the course each one runs on past the edge (phase 6,
## P6-1). A river that reaches the map edge carries on into the ground skirt as scenery: a
## channel carved into the skirt along its continued course with the real water in it, both
## dissolving into the backdrop with the skirt (RiverExitMesh builds the geometry). Decoration
## only, like the skirt: no collision, no grid, no tokens. Pure; map XZ throughout.
##
## An exit is a river body's end (its first point, upstream, or its last, downstream) within
## WaterCarve.EDGE_MARGIN_M (1 m) of the map edge, which the carve already leaves open and
## untapered, and which is not shared with another river's end (the next reach of the same
## stroke). Its course past the edge is the body's drawn `beyond` (downstream) or `beyond_up`
## (upstream) polyline when the author drew one: the Water tool keeps the stroke's points past
## the edge (split_line(), attach()). Otherwise it is derived, never saved: the river's last
## heading carried on with one gentle bend whose size and side come from the map seed and the
## body (continuation()), turned out of the map if the river met the edge at a glancing angle.

enum End { UP, DOWN }

## A drawn course past the edge keeps at most this many points (WaterBody.MAX_BEYOND_POINTS),
## resampled no closer than BEYOND_SPACING_M.
const BEYOND_SPACING_M := 2.0
## The derived continuation: this long, a point every AUTO_STEP_M, turning by up to
## AUTO_BEND_RAD (at least AUTO_MIN_BEND_RAD) over its first half, then back the other way by
## AUTO_SECOND_BEND (a share, picked between its two values, of the first bend) over the
## second, as a hand-drawn river meanders instead of running on as a straight canal. The
## least bend swings the course about 3.5 m off its heading: at 0.2 rad (P6-1) a seed near the
## minimum drew under 2 m over 18 m, and the Valley's upper-left exit read straight between
## its long walls (P6-3).
const AUTO_LENGTH_M := 36.0
const AUTO_STEP_M := 3.0
const AUTO_BEND_RAD := 0.7
const AUTO_MIN_BEND_RAD := 0.4
const AUTO_SECOND_BEND := Vector2(0.45, 0.8)
## A course past the edge always heads out of the map at least this much (the cosine of its
## angle to the edge's outward normal).
const MIN_OUTWARD := 0.45
## Every course runs on until it is this far past the map, where the skirt has faded however
## far its noise stretches the fade (AuthoredTerrain.SKIRT_FADE_M / (1 - SKIRT_WOBBLE)).
const FADE_REACH_M := 43.7
## The river's heading at its end is the chord over this much of its smoothed course.
const HEADING_CHORD_M := 1.5
## Two river ends closer than this are one shared point (consecutive reaches).
const SHARED_END_M := 0.05
## A drawn course is attached to a planned body's end within this of where the stroke met the
## edge.
const ATTACH_M := 1.0
## Points kept this far inside the map edge, so a crossing point passes MapWaterIO's check.
const EDGE_INSET_M := 0.005


## The exits of `doc` (see the header): [{"id": body id, "end": End, "course":
## PackedVector2Array from the river's end point outward, "drawn": bool, "level": the body's
## level_m, "half_width": its half-width at that end, "depth": its depth in metres}].
static func exits(doc: MapDocument) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := doc.extent_m() * 0.5
	var ends: Array[Vector3] = []
	for body in doc.water_bodies:
		if body.is_river() and body.points.size() >= 2:
			ends.append(Vector3(body.points[0].x, body.points[0].y, body.id))
			ends.append(Vector3(body.points[-1].x, body.points[-1].y, body.id))
	for body in doc.water_bodies:
		if not body.is_river() or body.points.size() < 2:
			continue
		for end in [End.UP, End.DOWN]:
			var at: Vector2 = body.points[0] if end == End.UP else body.points[-1]
			if edge_distance(at, half) > WaterCarve.EDGE_MARGIN_M or _shared(at, body.id, ends):
				continue
			var drawn: PackedVector2Array = body.beyond_up if end == End.UP else body.beyond
			var course := PackedVector2Array([at])
			if drawn.is_empty():
				course.append_array(continuation(doc, body, end))
			else:
				course.append_array(drawn)
			course = carried_on(course, half)
			var widths := body.half_widths
			(
				out
				. append(
					{
						"id": body.id,
						"end": end,
						"course": course,
						"drawn": not drawn.is_empty(),
						"level": body.level_m,
						"half_width": widths[0] if end == End.UP else widths[-1],
						"depth": body.depth_m(),
					}
				)
			)
	return out


## How far map point `p` is inside the map edge (negative outside), `half` the half extent.
static func edge_distance(p: Vector2, half: Vector2) -> float:
	return minf(half.x - absf(p.x), half.y - absf(p.y))


## How far map point `p` is outside the map rectangle (0 inside or on it).
static func outside_distance(p: Vector2, half: Vector2) -> float:
	return Vector2(maxf(absf(p.x) - half.x, 0.0), maxf(absf(p.y) - half.y, 0.0)).length()


## The outward normal of the map edge nearest `p` (the diagonal at a corner, where both edges
## are within the margin).
static func edge_normal(p: Vector2, half: Vector2) -> Vector2:
	var gap := Vector2(half.x - absf(p.x), half.y - absf(p.y))
	var normal := Vector2.ZERO
	if gap.x <= gap.y + WaterCarve.EDGE_MARGIN_M:
		normal.x = signf(p.x) if p.x != 0.0 else 1.0
	if gap.y <= gap.x + WaterCarve.EDGE_MARGIN_M:
		normal.y = signf(p.y) if p.y != 0.0 else 1.0
	return normal.normalized()


## The heading out of river `body` at `end`: from a point HEADING_CHORD_M back along its
## smoothed course (WaterGeometry.river_course, what the carve and the water follow) to its end
## point.
static func heading(body: WaterBody, end: End) -> Vector2:
	var points: PackedVector2Array = WaterGeometry.river_course(body)[0]
	if end == End.UP:
		points = points.duplicate()
		points.reverse()
	var tip := points[-1]
	var back := points[0]
	for i in range(points.size() - 2, -1, -1):
		back = points[i]
		if tip.distance_to(back) >= HEADING_CHORD_M:
			break
	var dir := tip - back
	return dir.normalized() if dir.length_squared() > 1e-10 else Vector2.RIGHT


## The derived course past the edge of river `body` at `end` (the points after its end point,
## see the header): AUTO_LENGTH_M along its heading, turned out of the map to at least
## MIN_OUTWARD, bending smoothly one way over its first half by an angle the map seed and the
## body pick, then back the other way, more gently, over its second (a meander).
## Deterministic.
static func continuation(doc: MapDocument, body: WaterBody, end: End) -> PackedVector2Array:
	var half := doc.extent_m() * 0.5
	var start: Vector2 = body.points[0] if end == End.UP else body.points[-1]
	var normal := edge_normal(start, half)
	var dir := outward(heading(body, end), normal)
	var seed_value := doc.map_seed & 0xFFFFFFFF
	var pick := _pick(seed_value, body.id * 2 + int(end))
	var side := -1.0 if pick < 0.5 else 1.0
	var bend := side * lerpf(AUTO_MIN_BEND_RAD, AUTO_BEND_RAD, absf(pick - 0.5) * 2.0)
	var share := _pick(seed_value, body.id * 2 + int(end) + 4096)
	var back := -bend * lerpf(AUTO_SECOND_BEND.x, AUTO_SECOND_BEND.y, share)
	var out := PackedVector2Array()
	var at := start
	var steps := roundi(AUTO_LENGTH_M / AUTO_STEP_M)
	for i in range(1, steps + 1):
		var s := (i - 0.5) * AUTO_STEP_M
		var first := _ease(s / (AUTO_LENGTH_M * 0.5))
		var second := _ease((s - AUTO_LENGTH_M * 0.5) / (AUTO_LENGTH_M * 0.5))
		var step_dir := outward(dir.rotated(bend * first + back * second), normal)
		at += step_dir * AUTO_STEP_M
		out.append(at)
	return out


## A value in [0, 1] hashed from the map seed and `key`.
static func _pick(seed_value: int, key: int) -> float:
	return float(TerrainRules.pcg2d_x(seed_value, key)) / 4294967295.0


## Smoothstep of `t` clamped to [0, 1].
static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## `course` (from a river's end outward) carried on along its last heading, out of the map by
## at least MIN_OUTWARD, until it is FADE_REACH_M past the map: a drawn course that stops
## short would end in the open where the skirt still shows. Derived, never saved.
static func carried_on(course: PackedVector2Array, half: Vector2) -> PackedVector2Array:
	var out := course.duplicate()
	if out.size() < 2:
		return out
	var normal := edge_normal(out[0], half)
	for _i in roundi(FADE_REACH_M / AUTO_STEP_M) + 1:
		if outside_distance(out[-1], half) >= FADE_REACH_M:
			break
		var dir := (out[-1] - out[-2]).normalized()
		out.append(out[-1] + outward(dir, normal) * AUTO_STEP_M)
	return out


## `dir` turned toward `normal` just enough that it heads out along it by MIN_OUTWARD.
static func outward(dir: Vector2, normal: Vector2) -> Vector2:
	var along := dir.dot(normal)
	if along >= MIN_OUTWARD:
		return dir
	var tangent := dir - normal * along
	if tangent.length_squared() < 1e-10:
		tangent = Vector2(-normal.y, normal.x)
	return tangent.normalized() * sqrt(1.0 - MIN_OUTWARD * MIN_OUTWARD) + normal * MIN_OUTWARD


## A drawn river line (map XZ, `widths` one per point or one for all) split at the map
## rectangle of half extent `half`: {"inside": the line from where it enters the map to where
## it leaves (the crossing points kept EDGE_INSET_M inside; outside points between them
## clamped onto the rectangle), "widths": its half-widths, "up": the points before it entered,
## "down": the points after it left, each ordered outward from the edge, cut at `reach` metres
## past the map and resampled to at most WaterBody.MAX_BEYOND_POINTS}. All empty when no
## point is inside.
static func split_line(
	line: PackedVector2Array, widths: PackedFloat32Array, half: Vector2, reach: float
) -> Dictionary:
	var out := {
		"inside": PackedVector2Array(),
		"widths": PackedFloat32Array(),
		"up": PackedVector2Array(),
		"down": PackedVector2Array(),
	}
	var first := -1
	var last := -1
	for i in line.size():
		if edge_distance(line[i], half) >= 0.0:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return out
	var width_of := func(i: int) -> float:
		if widths.is_empty():
			return WaterBody.MIN_HALF_WIDTH_M
		return (
			widths[clampi(i, 0, widths.size() - 1)] if widths.size() == line.size() else widths[0]
		)
	var inner := half - Vector2.ONE * EDGE_INSET_M
	var inside := PackedVector2Array()
	var inside_widths := PackedFloat32Array()
	if first > 0:
		inside.append(crossing(line[first - 1], line[first], half).clamp(-inner, inner))
		inside_widths.append(width_of.call(first))
	for i in range(first, last + 1):
		inside.append(line[i].clamp(-inner, inner))
		inside_widths.append(width_of.call(i))
	if last < line.size() - 1:
		inside.append(crossing(line[last + 1], line[last], half).clamp(-inner, inner))
		inside_widths.append(width_of.call(last))
	out.inside = inside
	out.widths = inside_widths
	var up := PackedVector2Array()
	for i in range(first - 1, -1, -1):
		up.append(line[i])
	var down := line.slice(last + 1)
	out.up = beyond_of(inside[0], up, half, reach)
	out.down = beyond_of(inside[-1], down, half, reach)
	return out


## The drawn course past the edge from `start` (the river's end, on the edge) through
## `points` (outward), cut where it gets `reach` metres past the map and resampled (without
## `start`) to at most WaterBody.MAX_BEYOND_POINTS points BEYOND_SPACING_M or more apart.
static func beyond_of(
	start: Vector2, points: PackedVector2Array, half: Vector2, reach: float
) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var line := PackedVector2Array([start])
	for p in points:
		if outside_distance(p, half) > reach:
			var prev := line[-1]
			var lo := 0.0
			var hi := 1.0
			for _i in 24:
				var mid := (lo + hi) * 0.5
				if outside_distance(prev.lerp(p, mid), half) > reach:
					hi = mid
				else:
					lo = mid
			line.append(prev.lerp(p, lo))
			break
		line.append(p)
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	if total < 0.5:
		return PackedVector2Array()
	var spacing := maxf(BEYOND_SPACING_M, total / WaterBody.MAX_BEYOND_POINTS)
	var resampled: PackedVector2Array = (
		WaterEdit.resample(line, PackedFloat32Array([1.0]), spacing)[0]
	)
	return resampled.slice(1, WaterBody.MAX_BEYOND_POINTS + 1)


## Gives the planned reaches `bodies` (upstream first) the drawn courses of split_line()'s
## `split`: the course before the stroke entered the map goes to the end the stroke entered
## at, and the one after it left to the end it left at, whichever way plan_river oriented the
## water (a line drawn uphill is reversed). An end that moved (it joined other water) keeps
## none.
static func attach(bodies: Array[WaterBody], split: Dictionary) -> void:
	if bodies.is_empty():
		return
	var inside: PackedVector2Array = split.inside
	if inside.size() < 2:
		return
	var entry := inside[0]
	var leave := inside[-1]
	var up: PackedVector2Array = split.up
	var down: PackedVector2Array = split.down
	var first := bodies[0]
	var last := bodies[-1]
	var head := first.points[0]
	var tail := last.points[-1]
	if head.distance_to(entry) <= ATTACH_M:
		first.beyond_up = up.duplicate()
	elif head.distance_to(leave) <= ATTACH_M:
		first.beyond_up = down.duplicate()
	if tail.distance_to(leave) <= ATTACH_M:
		last.beyond = down.duplicate()
	elif tail.distance_to(entry) <= ATTACH_M:
		last.beyond = up.duplicate()


## The CPU twin of the skirt shader's fade (shaders/skirt_fade.gdshaderinc skirt_alpha): 1
## on the map, 0 from `fade` metres out, the distance stretched by `wobble` with the seeded
## value noise (TerrainRules.value_noise is the shader's).
static func skirt_alpha(
	xz: Vector2, half: Vector2, fade: float, wobble: float, seed_value: int
) -> float:
	var d := outside_distance(xz, half)
	if d <= 0.0:
		return 1.0
	var p := xz / 11.0
	var n := (
		TerrainRules.value_noise(p + Vector2(3.7, -8.2), seed_value) * 0.7
		+ TerrainRules.value_noise(p * 2.3 + Vector2(-5.1, 2.9), seed_value) * 0.3
	)
	d *= 1.0 + (n - 0.5) * 2.0 * wobble
	var t := clampf(d / fade, 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## Where the segment from `outside` to `inside` crosses onto the map rectangle (bisection).
static func crossing(outside: Vector2, inside: Vector2, half: Vector2) -> Vector2:
	var a := outside
	var b := inside
	for _i in 30:
		var m := (a + b) * 0.5
		if edge_distance(m, half) >= 0.0:
			b = m
		else:
			a = m
	return b


static func _shared(at: Vector2, id: int, ends: Array[Vector3]) -> bool:
	for e in ends:
		if int(e.z) != id and at.distance_to(Vector2(e.x, e.y)) <= SHARED_END_M:
			return true
	return false
