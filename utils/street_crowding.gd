class_name StreetCrowding
extends RefCounted

## Whether a street's houses would stand in another street's (card painter-roof-round4; owner on
## the guild test level, l51: "some buildings are colliding"). A street (a row wall) lays its lots
## on each side of its line, its setback plus a lot's depth out (5.5 to 7 m for the test species),
## so two streets drawn closer than their lots reach put houses through houses. WallEditor.plan
## nudges such a new street (nudge(), card painter-roof-round5, owner on round 4's refusal: "Nudge
## instead of refusing"): the whole line moves straight away from the street it crowds, square to
## that street's nearest side, just far enough that the lots only touch, and the Street tool's
## readout says it moved. Where the nudge would leave the map, lose houses to water, meet another
## street or move it further than MAX_NUDGE_M (a line drawn on top of a street was meant somewhere
## else), the street is refused with the reason (WallEditor.REFUSED_CROWDED and its kin).
##
## The model. Each row's lots are the ones it stands (WallGeometry.row_lots, the recipe's own
## plan), four corners each; two lots of different rows crowd each other when their quads overlap
## by more than OVERLAP_M (two backyards that only touch do not). Only rows whose reach
## (WallGeometry.clear_bounds) meets the new one's are planned. The nudge's distance is the least
## shift along its direction that opens a separating axis between every overlapping pair
## (separation()), taken again from the moved line's own lots up to NUDGE_TRIES times (a lot plan
## only shifts with its line, so the first try is usually the last). Frames: the map's. Pure and
## deterministic: the same document and line give the same nudge.

## Two lots crowd each other when they overlap by more than this (metres, along the axis where the
## overlap is least).
const OVERLAP_M := 0.1
## The farthest a new street is nudged (map metres): about a lot's depth. Further, the line was
## drawn into the other street and is refused rather than carried away from where it was drawn.
const MAX_NUDGE_M := 8.0
## How many times the nudge measures again from the moved line's lots.
const NUDGE_TRIES := 3
## Why a nudge() made no street (its "refusal"): the nudge would meet another street (or move it
## more than MAX_NUDGE_M), leave the map, or put houses in the water.
const BLOCKED_STREET := &"street"
const BLOCKED_EDGE := &"edge"
const BLOCKED_WATER := &"water"


## The id of the first row of `doc` (other than `wall` itself, by id) whose lots overlap the lots
## `wall` would stand, or -1 when none does (or `wall` is not a row).
static func crowded_by(doc: MapDocument, wall: Wall) -> int:
	if not wall.is_row():
		return -1
	var reach := WallGeometry.clear_bounds(wall)
	var mine: Array = []
	for other in doc.walls:
		if other.id == wall.id or not other.is_row():
			continue
		if not WallGeometry.clear_bounds(other).intersects(reach) or crosses(wall, other):
			continue
		if mine.is_empty():
			mine = quads(doc, wall)
			if mine.is_empty():
				return -1
		for theirs: PackedVector2Array in quads(doc, other):
			for quad: PackedVector2Array in mine:
				if quads_overlap(quad, theirs, OVERLAP_M):
					return other.id
	return -1


## New row `wall` moved clear of the row that crowds it (crowded_by): {"wall": the street to lay
## (`wall` itself when nothing crowds it, a moved copy when nudged, null when blocked), "moved_m":
## how far it moved (map metres), "from": the id of the row it moved away from (-1: none),
## "blocked": &"" or why it cannot be laid (BLOCKED_*)}. `extent` the map's size in metres
## (MapDocument.extent_m). Pure.
static func nudge(doc: MapDocument, wall: Wall, extent: Vector2) -> Dictionary:
	var result := {"wall": wall, "moved_m": 0.0, "from": -1, "blocked": &""}
	var other_id := crowded_by(doc, wall)
	if other_id < 0:
		return result
	var other := doc.wall(other_id)
	result["from"] = other_id
	result["wall"] = null
	result["blocked"] = BLOCKED_STREET
	var away := away_from(other, middle(wall))
	var theirs := quads(doc, other)
	var mine := quads(doc, wall)
	var standing := mine.size()
	var moved := wall
	var moved_m := 0.0
	for attempt in NUDGE_TRIES + 1:
		var step := 0.0
		for quad: PackedVector2Array in mine:
			for their: PackedVector2Array in theirs:
				if quads_overlap(quad, their, OVERLAP_M):
					step = maxf(step, separation(quad, their, away))
		if step <= 0.0:
			break
		if attempt == NUDGE_TRIES or moved_m + step > MAX_NUDGE_M:
			return result
		moved_m += step
		moved = shifted(wall, away * moved_m)
		mine = quads(doc, moved)
	result["moved_m"] = moved_m
	if MapWallIO.wall_problem(moved, extent) != "":
		result["blocked"] = BLOCKED_EDGE
		return result
	if mine.size() < standing and VillageDryGround.has_water(doc):
		result["blocked"] = BLOCKED_WATER
		return result
	if crowded_by(doc, moved) >= 0:
		return result
	for row in doc.walls:
		if row.is_row() and crosses(moved, row) and not crosses(wall, row):
			return result
	result["wall"] = moved
	result["blocked"] = &""
	return result


## The unit direction square to the side of `wall`'s line nearest `p`, pointing from that side
## toward `p` (the side's left normal when `p` lies on it). Pure.
static func away_from(wall: Wall, p: Vector2) -> Vector2:
	var best := INF
	var out := Vector2.RIGHT
	for i in wall.points.size() - 1:
		var a := wall.points[i]
		var b := wall.points[i + 1]
		if a.distance_squared_to(b) < 1e-8:
			continue
		var near := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_squared_to(near)
		if d < best:
			best = d
			var along := (b - a).normalized()
			out = Vector2(-along.y, along.x)
			if out.dot(p - near) < 0.0:
				out = -out
	return out


## The mean of `wall`'s points (a drawn street's middle). Pure.
static func middle(wall: Wall) -> Vector2:
	var sum := Vector2.ZERO
	for p in wall.points:
		sum += p
	return sum / maxf(float(wall.points.size()), 1.0)


## A copy of `wall` with every point moved by `by`. Pure.
static func shifted(wall: Wall, by: Vector2) -> Wall:
	var out := wall.copy()
	var pts := PackedVector2Array()
	for p in wall.points:
		pts.append(p + by)
	out.points = pts
	return out


## The least distance convex polygon `a` moves along unit `dir` before it and `b` only touch
## (some side's axis separates them), 0 when they already do; INF when no move along `dir` ever
## separates them. Pure.
static func separation(a: PackedVector2Array, b: PackedVector2Array, dir: Vector2) -> float:
	var least := INF
	for poly: PackedVector2Array in [a, b]:
		for k in poly.size():
			var e := poly[(k + 1) % poly.size()] - poly[k]
			if e.length_squared() < 1e-8:
				continue
			var axis := Vector2(-e.y, e.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p in a:
				amin = minf(amin, p.dot(axis))
				amax = maxf(amax, p.dot(axis))
			for p in b:
				bmin = minf(bmin, p.dot(axis))
				bmax = maxf(bmax, p.dot(axis))
			if amax <= bmin or bmax <= amin:
				return 0.0
			var rate := dir.dot(axis)
			if rate > 1e-4:
				least = minf(least, (bmax - amin) / rate)
			elif rate < -1e-4:
				least = minf(least, (amax - bmin) / -rate)
	return least


## Whether the lines of walls `a` and `b` cross: a crossroads is drawn on purpose, so it is never
## refused here (its corner lots still meet; docs/systems/walls.md). Pure.
static func crosses(a: Wall, b: Wall) -> bool:
	for i in a.points.size() - 1:
		for j in b.points.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(
				a.points[i], a.points[i + 1], b.points[j], b.points[j + 1]
			)
			if hit != null:
				return true
	return false


## The lots `wall` stands (WallGeometry.row_lots), each as its corners in the map frame.
static func quads(doc: MapDocument, wall: Wall) -> Array:
	var out: Array = []
	for lot: Dictionary in WallGeometry.row_lots(doc, wall):
		var pts := PackedVector2Array()
		for p: Variant in lot.get("points", []):
			pts.append(Vector2(p.x, p.y) if p is Vector2 else Vector2(p.x, p.z))
		if pts.size() >= 3:
			out.append(pts)
	return out


## Whether convex polygons `a` and `b` overlap by more than `margin` metres on every axis of
## their sides (separating axes). Pure.
static func quads_overlap(a: PackedVector2Array, b: PackedVector2Array, margin: float) -> bool:
	for poly: PackedVector2Array in [a, b]:
		for k in poly.size():
			var e := poly[(k + 1) % poly.size()] - poly[k]
			if e.length_squared() < 1e-8:
				continue
			var axis := Vector2(-e.y, e.x).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for p in a:
				amin = minf(amin, p.dot(axis))
				amax = maxf(amax, p.dot(axis))
			for p in b:
				bmin = minf(bmin, p.dot(axis))
				bmax = maxf(bmax, p.dot(axis))
			if amax < bmin + margin or bmax < amin + margin:
				return false
	return true
