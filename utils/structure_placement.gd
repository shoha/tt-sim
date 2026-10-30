class_name StructurePlacement
extends RefCounted

## Where a structure may stand and what plan a click or a drag gives it (the Structure tool,
## StructureBrush; docs/systems/structures.md "The tool"). Pure functions of the document, so
## the ghost, the tests and the editor agree. Frames: document (map XZ metres).
##
## Plans. A lot is a rectangle: `rect_plan` from a centre, a size and a turn, `corner_plan` from
## two opposite corners dragged out. Its edge 0 is the front and carries the door; at turn 0 the
## front faces +Z (toward the home camera) and a turn rotates the whole plan about its centre
## (the plan stays wound the way ProcgenPlan wants). Sizes clamp to the recipe's range instead of
## being refused (`clamp_size`): a lot can be made no smaller than its recipe's least side, no
## larger than its largest side or area, and keeps its shape as far as those allow.
##
## Ground. A lot is legal where no sampled point is under water and no sampled slope passes
## MAX_SLOPE (the 24 degree bank procgen's mesh check was run on). `nearest_legal` searches
## rings round the wanted centre for the closest legal spot, so a drop eases to ground that
## takes a house rather than failing.

## Round plans. A structure whose `plans` names ROUND_PLAN is a regular polygon of `sides_of(row)`
## sides (its `sides:<n>` tag): its lot is a circle of radius size.x / 2 (size is the diameter, a
## square Vector2, so every size rule below applies as it is), the front (edge 0) facing +Z at turn
## 0. It scales, moves and turns as one piece; `min_side_m` and `max_side_m` are its least and
## largest diameters.
const ROUND_PLAN := "round"
const SIDES_TAG := "sides:"
const DEFAULT_SIDES := 8
## A row whose least side is this or more is pinned at its default rectangle, not the 6 by 4 m one
## (the other rows' least sides are at most 6.8 m; the courtyards' is 9 m).
const PIN_DEFAULT_MIN_SIDE_M := 8.0

## Plan centres snap to this (metres), as the ghost shows.
const SNAP_M := 0.5
## The steepest ground a structure stands on: rise over run, tan of the 24 degree bank procgen's
## mesh check was tested on.
const MAX_SLOPE := 0.445
## How far (metres) nearest_legal looks for a legal spot, and the step between its rings.
const REACH_M := 7.0
const RING_STEP_M := 1.0
## Ground is sampled about this far apart across a plan, at most MAX_SAMPLES points.
const SAMPLE_STEP_M := 1.0
const MAX_SAMPLES := 80
## The slope at a point is read across this much (metres) either side.
const SLOPE_SPAN_M := 0.5

## Why a lot is not legal (ground_problem).
const WATER := "water"
const STEEP := "steep"
const OFF_MAP := "off_map"
const OCCUPIED := "occupied"
## Structures keep this much (metres) between them.
const GAP_M := 0.4


## Whether the library row (a LibraryStructureStore row) is a round structure.
static func is_round(row: Dictionary) -> bool:
	var plans: Variant = row.get("plans")
	return plans is Array and ROUND_PLAN in (plans as Array)


## The sides of a round row's polygon (its `sides:<n>` tag, 3..Structure.MAX_POINTS), 0 for any
## other row.
static func sides_of(row: Dictionary) -> int:
	if not is_round(row):
		return 0
	for tag: Variant in row.get("tags", []) as Array:
		var text := String(tag)
		if text.begins_with(SIDES_TAG) and text.trim_prefix(SIDES_TAG).is_valid_int():
			return clampi(int(text.trim_prefix(SIDES_TAG)), 3, Structure.MAX_POINTS)
	return DEFAULT_SIDES


## The regular polygon of `sides` corners on a circle of `radius` about `centre`, turned `yaw`
## radians (the front, edge 0, faces +Z at yaw 0), each point snapped to Structure.FOOTPRINT_STEP_M.
## Pure.
static func round_plan(
	centre: Vector2, radius: float, yaw: float, sides: int
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ProcgenPlan.regular_polygon(sides, radius, PI * 0.5 + yaw, centre):
		out.append(ProcgenPlan.snap(p, Structure.FOOTPRINT_STEP_M))
	return out


## The plan of a lot of `size` about `centre` turned `yaw`: the rectangle, or with `sides` above 0
## the regular polygon of diameter size.x.
static func lot_plan(
	centre: Vector2, size: Vector2, yaw: float, sides: int = 0
) -> PackedVector2Array:
	if sides > 0:
		return round_plan(centre, size.x * 0.5, yaw, sides)
	return rect_plan(centre, size, yaw)


## The default footprint of library row `row` about the origin: the rectangle of its
## `default_size_m`, or its regular polygon. What a pin, a tile and a verify build.
static func default_plan(row: Dictionary) -> PackedVector2Array:
	var size := default_size(row)
	return lot_plan(Vector2.ZERO, size, 0.0, sides_of(row))


## The footprint the starters' pins are built at (tools/export_core_structures.gd): a 6 by 4 m
## rectangle about the origin, or for a round row its default regular polygon. A row whose least
## side is 8 m or more (a courtyard: procgen shows the plain building under 9 by 8 m) is pinned at
## its default rectangle, since the 6 by 4 m one would pin the fallback.
static func pin_plan(row: Dictionary) -> PackedVector2Array:
	if is_round(row) or float(row.get("min_side_m", 0.0)) >= PIN_DEFAULT_MIN_SIDE_M:
		return default_plan(row)
	return PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])


## The rectangle `size` (x along the front edge, y deep) about `centre`, turned `yaw` radians,
## wound as ProcgenPlan wants, with the front (edge 0) facing +Z at yaw 0, each point snapped to
## Structure.FOOTPRINT_STEP_M. Pure.
static func rect_plan(centre: Vector2, size: Vector2, yaw: float) -> PackedVector2Array:
	var h := size * 0.5
	var local := PackedVector2Array(
		[Vector2(h.x, h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y), Vector2(h.x, -h.y)]
	)
	var out := PackedVector2Array()
	for p in local:
		out.append(ProcgenPlan.snap(centre + p.rotated(yaw), Structure.FOOTPRINT_STEP_M))
	return out


## The rectangle with opposite corners `a` and `b` whose sides run `yaw` radians from +X, as a
## plan (see rect_plan), and its size `clamped` to the recipe row's range. The drag's corners
## are kept as the nearest the clamp allows to the pointer's: the plan's centre is the middle of
## the corners, so a drag held past the largest size grows no further. Pure.
static func corner_plan(a: Vector2, b: Vector2, yaw: float, row: Dictionary) -> Dictionary:
	var u := Vector2(cos(yaw), sin(yaw))
	var v := Vector2(-u.y, u.x)
	var d := b - a
	var size := clamp_size(Vector2(absf(d.dot(u)), absf(d.dot(v))), row)
	# The corner the drag started at stays fixed; the other follows the pointer as far as the
	# clamp lets it.
	var sx := signf(d.dot(u)) if d.dot(u) != 0.0 else 1.0
	var sz := signf(d.dot(v)) if d.dot(v) != 0.0 else 1.0
	var centre := a + u * size.x * 0.5 * sx + v * size.y * 0.5 * sz
	# rect_plan puts the front on +Z at yaw 0; a drag's frame is (u, v) with v = u rotated a
	# quarter turn, which is rect_plan's turn by yaw as well, so the sizes map x -> u, y -> v.
	return {"plan": rect_plan(centre, size, yaw), "size": size, "centre": centre}


## `size` clamped to the recipe row's `min_side_m`, `max_side_m` and `max_area_m2`: each side
## into [min, max], then, when the area is over its limit, both scaled down together (the
## shape is kept) but never under the least side. Pure.
static func clamp_size(size: Vector2, row: Dictionary) -> Vector2:
	var low := float(row.get("min_side_m", LibraryStructures.DEFAULT_MIN_SIDE_M))
	var high := float(row.get("max_side_m", LibraryStructures.DEFAULT_MAX_SIDE_M))
	var area := float(row.get("max_area_m2", LibraryStructures.DEFAULT_MAX_AREA_M2))
	if is_round(row):
		# One diameter, whichever side was asked for; the polygon's own area is under its limit.
		var sides := sides_of(row)
		var diameter := clampf(maxf(size.x, size.y), low, high)
		var polygon := 0.5 * sides * pow(diameter * 0.5, 2.0) * sin(TAU / sides)
		if polygon > area:
			diameter = maxf(diameter * sqrt(area / polygon), low)
		return Vector2(diameter, diameter)
	var out := Vector2(clampf(size.x, low, high), clampf(size.y, low, high))
	if out.x * out.y > area:
		var shrink := sqrt(area / (out.x * out.y))
		out = Vector2(maxf(out.x * shrink, low), maxf(out.y * shrink, low))
	return out


## The row's default lot (its `default_size_m`, clamped). Pure.
static func default_size(row: Dictionary) -> Vector2:
	var raw: Variant = row.get("default_size_m", LibraryStructures.DEFAULT_SIZE_M)
	var size := LibraryStructures.DEFAULT_SIZE_M
	if raw is Array and (raw as Array).size() >= 2:
		size = Vector2(float(raw[0]), float(raw[1]))
	elif raw is Vector2:
		size = raw
	return clamp_size(size, row)


## `p` snapped to the placement grid.
static func snapped_centre(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, SNAP_M), snappedf(p.y, SNAP_M))


## Why the plan cannot stand on the document's ground: WATER (a sampled point is under water),
## STEEP (a sampled slope is over MAX_SLOPE), OFF_MAP (a corner is outside the map), or "".
## `courses` is WaterGeometry.river_courses(doc, area) for an area holding the plan, or {} to
## make it here (cheaper to pass when asking about many plans).
static func ground_problem(
	doc: MapDocument, plan: PackedVector2Array, courses: Dictionary = {}
) -> String:
	if plan.size() < 3 or doc.heights.size() != doc.sample_count():
		return ""
	var half := doc.extent_m() * 0.5
	var bounds := Rect2(plan[0], Vector2.ZERO)
	for p in plan:
		if absf(p.x) > half.x or absf(p.y) > half.y:
			return OFF_MAP
		bounds = bounds.expand(p)
	var held := courses
	if held.is_empty() and not doc.water_bodies.is_empty():
		held = WaterGeometry.river_courses(doc, bounds.grow(2.0))
	var step := maxf(SAMPLE_STEP_M, sqrt(bounds.get_area() / MAX_SAMPLES))
	var points := PackedVector2Array(plan)
	var y := bounds.position.y + step * 0.5
	while y < bounds.end.y:
		var x := bounds.position.x + step * 0.5
		while x < bounds.end.x:
			var at := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(at, plan):
				points.append(at)
			x += step
		y += step
	var steepest := 0.0
	for p in points:
		if WaterGeometry.is_wet_at(doc, p, -1, held):
			return WATER
		var dx := (
			WaterGeometry.ground_at(doc, p + Vector2(SLOPE_SPAN_M, 0.0))
			- WaterGeometry.ground_at(doc, p - Vector2(SLOPE_SPAN_M, 0.0))
		)
		var dz := (
			WaterGeometry.ground_at(doc, p + Vector2(0.0, SLOPE_SPAN_M))
			- WaterGeometry.ground_at(doc, p - Vector2(0.0, SLOPE_SPAN_M))
		)
		steepest = maxf(steepest, Vector2(dx, dz).length() / (2.0 * SLOPE_SPAN_M))
	return STEEP if steepest > MAX_SLOPE else ""


## OCCUPIED when the plan comes within GAP_M of a structure already standing (other than
## `except_id`), else "".
static func occupied(doc: MapDocument, plan: PackedVector2Array, except_id: int = -1) -> String:
	var bounds := Rect2(plan[0], Vector2.ZERO)
	for p in plan:
		bounds = bounds.expand(p)
	bounds = bounds.grow(GAP_M)
	for structure in doc.structures:
		if structure.id == except_id or not structure.bounds().intersects(bounds):
			continue
		for grown: PackedVector2Array in Geometry2D.offset_polygon(structure.footprint, GAP_M):
			if not Geometry2D.intersect_polygons(plan, grown).is_empty():
				return OCCUPIED
	return ""


## Why a lot cannot stand on `plan`: ground_problem(), else occupied(), else "". The structure
## `except_id` (one being edited) is not counted as in the way.
static func lot_problem(
	doc: MapDocument, plan: PackedVector2Array, courses: Dictionary = {}, except_id: int = -1
) -> String:
	var ground := ground_problem(doc, plan, courses)
	return ground if ground != "" else occupied(doc, plan, except_id)


## The legal spot nearest `want` (a plan centre) for a lot of `size` turned `yaw`: {"centre",
## "plan", "moved" (it is not `want`), "problem" ("" when a legal spot was found, else the
## reason `want` itself fails)}. Searches rings of RING_STEP_M out to REACH_M, a dozen spots on
## each, on the SNAP_M grid, and takes the first ring's closest legal spot.
static func nearest_legal(
	doc: MapDocument, want: Vector2, size: Vector2, yaw: float, sides: int = 0
) -> Dictionary:
	# Everything is asked of the snapped centre, so a hover and the click after it give one answer.
	var centre := snapped_centre(want)
	want = centre
	var plan := lot_plan(centre, size, yaw, sides)
	var area := Rect2(want, Vector2.ZERO).grow(REACH_M + maxf(size.x, size.y))
	var courses := WaterGeometry.river_courses(doc, area) if not doc.water_bodies.is_empty() else {}
	var problem := lot_problem(doc, plan, courses)
	if problem == "":
		return {"centre": centre, "plan": plan, "moved": false, "problem": ""}
	var ring := RING_STEP_M
	while ring <= REACH_M:
		var best := Vector2.INF
		var best_distance := INF
		var spots := maxi(8, ceili(TAU * ring / RING_STEP_M))
		for k in spots:
			var at := snapped_centre(want + Vector2.from_angle(TAU * k / spots) * ring)
			var candidate := lot_plan(at, size, yaw, sides)
			if at.distance_to(want) < best_distance and lot_problem(doc, candidate, courses) == "":
				best = at
				best_distance = at.distance_to(want)
		if best != Vector2.INF:
			return {
				"centre": best,
				"plan": lot_plan(best, size, yaw, sides),
				"moved": true,
				"problem": ""
			}
		ring += RING_STEP_M
	return {"centre": centre, "plan": plan, "moved": false, "problem": problem}


## The id of the structure whose footprint holds map point `p` (the topmost, the last laid), or
## -1.
static func structure_at(doc: MapDocument, p: Vector2) -> int:
	for k in range(doc.structures.size() - 1, -1, -1):
		var structure := doc.structures[k]
		if (
			structure.bounds().has_point(p)
			and Geometry2D.is_point_in_polygon(p, structure.footprint)
		):
			return structure.id
	return -1
