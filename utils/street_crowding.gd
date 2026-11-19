class_name StreetCrowding
extends RefCounted

## Whether a street's houses would stand in another street's (card painter-roof-round4; owner on
## the guild test level, l51: "some buildings are colliding"). A street (a row wall) lays its lots
## on each side of its line, its setback plus a lot's depth out (5.5 to 7 m for the test species),
## so two streets drawn closer than their lots reach put houses through houses. WallEditor.plan
## refuses such a street (WallEditor.REFUSED_CROWDED) while it is drawn, so the Street tool's
## readout says so before the release; the author draws it further away. Nothing is nudged: a
## street is a line the author drew, and moving it sideways would put it where they did not.
##
## The model. Each row's lots are the ones it stands (WallGeometry.row_lots, the recipe's own
## plan), four corners each; two lots of different rows crowd each other when their quads overlap
## by more than OVERLAP_M (two backyards that only touch do not). Only rows whose reach
## (WallGeometry.clear_bounds) meets the new one's are planned. Frames: the map's. Pure.

## Two lots crowd each other when they overlap by more than this (metres, along the axis where the
## overlap is least).
const OVERLAP_M := 0.1


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
