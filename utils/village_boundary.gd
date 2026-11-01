class_name VillageBoundary
extends RefCounted

## The pure rules of a village's boundary (villages phase 3, third slice, topic bounds;
## docs/systems/villages.md section 13): a low stone wall or a hedge drawn round the settlement's
## edge, with gates where its streets leave, so a village reads as one place at home zoom.
##
## The record holds only the kind (`Settlement.boundary`: "" for none, WALL, LOW_WALL or HEDGE),
## drawn by the Dress from the character and the seed (kind_for): a hill fort is always walled, a
## market town keeps a low wall on two seeds in three, a farming hamlet a hedge on one in two, a
## harbour town none. Everything else is derived on every peer from the record and the map:
##
## - The line (ring_of): the convex hull of the street's standing lots (their yards included), of
##   the street itself widened past its road, and of the plazas, grown by MARGIN_M with rounded
##   corners and sampled every STEP_M, so the boundary is one soft enclosing shape, never a fussy
##   trace of every yard.
## - The gaps (flags_of): a sample is a GATE where it lies on a street's road (the village's own
##   street reaches EXTEND_M past both ends, so its two ends are always gates) and BLOCKED where it
##   is wet, on a crossing or its landings, by a field, or on or by any building.
## - The runs (runs_of): the kept stretches between gaps, those under MIN_RUN_M dropped. A stone
##   kind becomes transient Wall records (walls_of: never in MapDocument.walls, so MAX_WALLS is
##   untouched) with a pier either side of each gate; a hedge becomes meadow bushes (hedge_of).
##
## Nothing here is saved or sent but the kind; no scene tree, no editor.

const WALL := "wall"
const LOW_WALL := "low_wall"
const HEDGE := "hedge"
const KINDS: Array[String] = [WALL, LOW_WALL, HEDGE]
## Per character: the kind its villages are bounded by and `skip`: none on one seed in `skip`
## (0: always). Not every village is walled (the suite's no-sameness rule). A kit not listed
## (harbour town) has no boundary.
const KIT_RULES := {
	"hill_fort_village": {"kind": WALL, "skip": 0},
	"market_town": {"kind": LOW_WALL, "skip": 3},
	"farming_hamlet": {"kind": HEDGE, "skip": 2},
}
## A stone kind's height and its gate piers' (metres), low and broad like the yards' walls.
## A 0.6 m low wall was a hairline at home zoom (bounds_look round 1).
const HEIGHT_M := {WALL: 1.0, LOW_WALL: 0.75}
const PIER_HEIGHT_M := {WALL: 1.55, LOW_WALL: 1.2}
const PIER_LENGTH_M := 0.7
## The line stands this far outside the hull (metres) and is sampled this often.
const MARGIN_M := 2.0
const STEP_M := 0.5
## The street enters the hull widened this far past its road's edge on both sides, so a street
## built on one side only still gets a line beyond its road.
const STREET_SIDE_M := 1.0
## The village's own street is taken this far past each end: its ends are the gates.
const EXTEND_M := 14.0
## A gate is the road's width plus this on each side.
const GATE_SIDE_M := 0.8
## The line keeps this far from a field's rim (past its hedgerow), a building's walls and a
## crossing's corridor.
const FIELD_KEEP_M := 1.6
const BUILDING_KEEP_M := 0.8
const CROSSING_KEEP_M := 0.5
## Runs shorter than this are dropped (a stub between two gaps reads as clutter).
const MIN_RUN_M := 2.0
## A wall record is at most this long (Wall.MAX_LENGTH_M is 120) and its line is simplified to
## this tolerance.
const CHUNK_M := 40.0
const SIMPLIFY_M := 0.08
## Hedge bushes: one this often along the line, at this scale, nudged this far across it.
const HEDGE_STEP_M := 1.0
const HEDGE_SCALE := Vector2(0.9, 1.2)
const HEDGE_NUDGE_M := 0.25
## How a sample of the line is treated.
const KEEP := 0
const GATE := 1
const BLOCKED := 2


## The boundary a village of `kit` dressed with seed `seed_value` gets ("" for none).
static func kind_for(kit: String, seed_value: int) -> String:
	var rule: Dictionary = KIT_RULES.get(kit, {})
	if rule.is_empty():
		return ""
	var skip := int(rule["skip"])
	if skip > 0 and absi(hash([seed_value, "boundary"])) % skip == 0:
		return ""
	return str(rule["kind"])


## True for the kinds built of stone (walls_of), false for a hedge and none.
static func is_stone(kind: String) -> bool:
	return HEIGHT_M.has(kind)


## The points the line encloses: the corners of every lot of `lots` (building and yard), the
## street `street` widened to `half_m` each side, and eight points round each plaza of `plazas`.
static func hull_points(
	street: PackedVector2Array, half_m: float, lots: Array[Dictionary], plazas: Array[Dictionary]
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for lot in lots:
		for key in ["points", "plot"]:
			for corner: Vector3 in lot.get(key, PackedVector3Array()):
				out.append(Vector2(corner.x, corner.z))
	for k in street.size():
		var before := street[maxi(k - 1, 0)]
		var after := street[mini(k + 1, street.size() - 1)]
		var along := (after - before).normalized()
		var across := Vector2(-along.y, along.x)
		out.append(street[k] + across * half_m)
		out.append(street[k] - across * half_m)
	for plaza in plazas:
		var at: Vector2 = plaza["at"]
		for k in 8:
			out.append(at + Vector2.from_angle(TAU * k / 8.0) * float(plaza["radius"]))
	return out


## The closed line round `points`: their convex hull grown by `margin` with rounded corners,
## sampled every `step` (counter-clockwise in map XZ, the first sample not repeated). Empty when
## the points enclose no area.
static func ring_of(
	points: PackedVector2Array, margin: float = MARGIN_M, step: float = STEP_M
) -> PackedVector2Array:
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		return PackedVector2Array()
	var area := 0.0
	for k in hull.size():
		area += hull[k].cross(hull[(k + 1) % hull.size()])
	if absf(area) < 0.01:
		return PackedVector2Array()
	if area < 0.0:
		hull.reverse()
	# The outline: each side pushed out along its normal, joined by an arc round each corner.
	var outline := PackedVector2Array()
	var count := hull.size()
	for k in count:
		var a := hull[k]
		var b := hull[(k + 1) % count]
		var c := hull[(k + 2) % count]
		var out_ab := _outward(a, b)
		var out_bc := _outward(b, c)
		outline.append(a + out_ab * margin)
		outline.append(b + out_ab * margin)
		var from := out_ab.angle()
		var turn := wrapf(out_bc.angle() - from, 0.0, TAU)
		var arcs := ceili(turn / 0.2)
		for s in range(1, arcs):
			outline.append(b + Vector2.from_angle(from + turn * s / arcs) * margin)
	return _resample(outline, step)


## Per sample of `ring`, KEEP, GATE (within `half` of a corridor of `gates`, each
## {"from", "to", "half"}) or BLOCKED (`wet[i]` set, or `blocked`, a callable p -> bool, true).
## Pure.
static func gate_flags(
	ring: PackedVector2Array,
	gates: Array[Dictionary],
	blocked: Callable,
	wet: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ring.size())
	for i in ring.size():
		if VillageDryGround.in_corridors(ring[i], gates):
			out[i] = GATE
		elif (i < wet.size() and wet[i] != 0) or blocked.call(ring[i]):
			out[i] = BLOCKED
	return out


## The kept stretches of `ring` (flags from gate_flags): [{"points", "closed", "gate_start",
## "gate_end"}], each at least `min_run` long; `gate_start` and `gate_end` say a gate lies at that
## end. A ring with no gap is one closed run. Pure.
static func runs_of(
	ring: PackedVector2Array, flags: PackedByteArray, min_run: float = MIN_RUN_M
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := ring.size()
	if n < 3:
		return out
	var first := -1
	for i in n:
		if flags[i] != KEEP:
			first = i
			break
	if first < 0:
		out.append({"points": ring, "closed": true, "gate_start": false, "gate_end": false})
		return out
	var run := PackedVector2Array()
	var opened := first
	for s in range(1, n + 1):
		var i := (first + s) % n
		if flags[i] == KEEP:
			if run.is_empty():
				opened = (i - 1 + n) % n
			run.append(ring[i])
			continue
		if run.size() >= 2 and _length(run) >= min_run:
			out.append(
				{
					"points": run,
					"closed": false,
					"gate_start": flags[opened] == GATE,
					"gate_end": flags[i] == GATE,
				}
			)
		run = PackedVector2Array()
	return out


## The boundary of `settlement` on `doc`: {"kind", "runs": runs_of's list, "gates": how many gate
## gaps}, or {"kind": "", "runs": []} for a village with none or with no street.
static func plan(doc: MapDocument, settlement: Settlement) -> Dictionary:
	var none := {"kind": "", "runs": [] as Array[Dictionary], "gates": 0}
	if settlement == null or not KINDS.has(settlement.boundary) or settlement.source <= 0:
		return none
	var wall := doc.wall(settlement.source)
	if wall == null or not wall.is_row() or wall.points.size() < 2:
		return none
	var road := SettlementGround.road_half_width(wall.height_m)
	var points := hull_points(
		wall.points, road + STREET_SIDE_M, WallGeometry.row_lots(doc, wall), settlement.plazas
	)
	var ring := ring_of(points)
	if ring.is_empty():
		return none
	var flags := flags_of(doc, settlement, wall, ring)
	var runs := runs_of(ring, flags)
	var gates := 0
	for i in ring.size():
		if flags[i] == GATE and flags[(i + 1) % ring.size()] != GATE:
			gates += 1
	return {"kind": settlement.boundary, "runs": runs, "gates": gates}


## gate_flags for `ring` round `settlement` (street `wall`) on `doc`: the gates are every street's
## road (the own street reaching EXTEND_M past both ends); a sample is blocked when wet, on a
## crossing's corridor, by one of the village's fields or on or by any building.
static func flags_of(
	doc: MapDocument, settlement: Settlement, wall: Wall, ring: PackedVector2Array
) -> PackedByteArray:
	var gates: Array[Dictionary] = []
	for street in doc.walls:
		if not street.is_row() or street.points.size() < 2:
			continue
		var line := extended(street.points) if street.id == wall.id else street.points
		var half := SettlementGround.road_half_width(street.height_m) + GATE_SIDE_M
		for k in line.size() - 1:
			gates.append({"from": line[k], "to": line[k + 1], "half": half})
	var near := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		near = near.expand(p)
	var wet := VillageDryGround.wet_flags(doc, ring, near.grow(1.0))
	var crossings := VillageDryGround.crossing_corridors(doc)
	var plans := VillageFieldGround.footprints(doc)
	var fields := settlement.fields
	var blocked := func(p: Vector2) -> bool:
		if VillageDryGround.in_corridors(p, crossings, CROSSING_KEEP_M):
			return true
		for field in fields:
			if p.distance_to(field["at"]) < float(field["radius"]) + FIELD_KEEP_M:
				return true
		return near_building(plans, p, BUILDING_KEEP_M)
	return gate_flags(ring, gates, blocked, wet)


## True when `p` lies in one of `plans` (map XZ polygons) or within `keep` of its walls. Pure.
static func near_building(plans: Array[PackedVector2Array], p: Vector2, keep: float) -> bool:
	for plan_poly in plans:
		if Geometry2D.is_point_in_polygon(p, plan_poly):
			return true
		for k in plan_poly.size():
			var a := plan_poly[k]
			var b := plan_poly[(k + 1) % plan_poly.size()]
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < keep:
				return true
	return false


## `line` with its first and last sides reaching `reach` further. Pure.
static func extended(line: PackedVector2Array, reach: float = EXTEND_M) -> PackedVector2Array:
	var out := line.duplicate()
	var n := out.size()
	if n < 2:
		return out
	out[0] = line[0] + (line[0] - line[1]).normalized() * reach
	out[n - 1] = line[n - 1] + (line[n - 1] - line[n - 2]).normalized() * reach
	return out


## The transient stone walls of `planned` (plan()): each run simplified and cut into lines of at
## most CHUNK_M, then a pier PIER_LENGTH_M long at each end that meets a gate. Ids from 1, the
## record's kind and height; never put in a document. [] for a hedge or none.
static func walls_of(planned: Dictionary) -> Array[Wall]:
	var out: Array[Wall] = []
	var kind := str(planned.get("kind", ""))
	if not is_stone(kind):
		return out
	var height := float(HEIGHT_M[kind])
	var pier := float(PIER_HEIGHT_M[kind])
	for run: Dictionary in planned["runs"]:
		var points: PackedVector2Array = run["points"]
		var closed: bool = run["closed"]
		var chunks := chunks_of(simplified(points, closed), closed)
		# A closed run cut into chunks is a chain of open lines.
		var whole := closed and chunks.size() == 1
		for chunk in chunks:
			out.append(Wall.make(out.size() + 1, Wall.Kind.STONE, chunk, whole, height))
		if bool(run["gate_start"]):
			out.append(_pier(out.size() + 1, points, pier, false))
		if bool(run["gate_end"]):
			out.append(_pier(out.size() + 1, points, pier, true))
	return out


## `points` simplified (Ramer-Douglas-Peucker) to SIMPLIFY_M; a closed line keeps at least three
## points. Pure.
static func simplified(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	if points.size() < 3:
		return points
	if closed:
		var half := points.size() >> 1
		var a := _rdp(points.slice(0, half + 1))
		var b := _rdp(points.slice(half) + PackedVector2Array([points[0]]))
		a.remove_at(a.size() - 1)
		b.remove_at(b.size() - 1)
		return a + b
	return _rdp(points)


## `points` cut into lines of at most CHUNK_M and Wall.MAX_POINTS points, each starting where the
## last ended (a closed line is kept whole when it fits, else cut and its end joined to its start).
static func chunks_of(points: PackedVector2Array, closed: bool) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var line := points
	if closed:
		if _length(points) + points[0].distance_to(points[points.size() - 1]) <= CHUNK_M:
			out.append(points)
			return out
		line = points + PackedVector2Array([points[0]])
	var chunk := PackedVector2Array([line[0]])
	var run := 0.0
	for k in range(1, line.size()):
		run += line[k - 1].distance_to(line[k])
		chunk.append(line[k])
		if (run >= CHUNK_M or chunk.size() >= Wall.MAX_POINTS) and k < line.size() - 1:
			out.append(chunk)
			chunk = PackedVector2Array([line[k]])
			run = 0.0
	if chunk.size() >= 2:
		out.append(chunk)
	return out


## The hedge of `planned` (plan(), kind HEDGE) with seed `seed_value`: bushes HEDGE_STEP_M apart
## along every run, as VillageFields' plants ({"asset", "at", "yaw", "scale"}). [] otherwise.
static func hedge_of(planned: Dictionary, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if str(planned.get("kind", "")) != HEDGE:
		return out
	var every := maxi(roundi(HEDGE_STEP_M / STEP_M), 1)
	var shrubs := VillageFields.HEDGE_SHRUBS
	for run: Dictionary in planned["runs"]:
		var points: PackedVector2Array = run["points"]
		for k in range(0, points.size(), every):
			var p := points[k]
			var along := (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
			var h := absi(hash([seed_value, roundi(p.x * 100.0), roundi(p.y * 100.0), "bounds"]))
			var nudge := (float(h % 101) / 100.0 - 0.5) * 2.0 * HEDGE_NUDGE_M
			out.append(
				{
					"asset": shrubs[(h >> 8) % shrubs.size()],
					"at": p + Vector2(-along.y, along.x) * nudge,
					"yaw": float((h >> 4) % 6283) / 1000.0,
					"scale": lerpf(HEDGE_SCALE.x, HEDGE_SCALE.y, float((h >> 14) % 101) / 100.0),
				}
			)
	return out


## The scatter clearance along every boundary of `doc`: each side of each run as a plank-like
## Crossing as wide as a wall's (a hedge's a little wider), so no wild bush or tree stands in it.
static func clearance_crossings(doc: MapDocument) -> Array[Crossing]:
	var out: Array[Crossing] = []
	for settlement in doc.settlements:
		if not KINDS.has(settlement.boundary):
			continue
		var planned := plan(doc, settlement)
		var width := WallGeometry.CLEAR_WIDTH_M * (2.0 if planned["kind"] == HEDGE else 1.0)
		for run: Dictionary in planned["runs"]:
			var line := simplified(run["points"], run["closed"])
			var count := line.size()
			var sides := count if run["closed"] else count - 1
			for k in sides:
				out.append(
					Crossing.make(
						0, Crossing.Kind.PLANK, line[k], line[(k + 1) % count], Vector3.ZERO, width
					)
				)
	return out


## The map area whose plants a change of the settlement list from `before` to `after` on `doc`
## regrows for their boundaries: round the street of each settlement that has a boundary in either
## version and whose record changed. An empty Rect2 when none did.
static func area_of(doc: MapDocument, before: Array[Settlement], after: Array[Settlement]) -> Rect2:
	var old := {}
	for settlement in before:
		old[settlement.id] = settlement
	var now := {}
	for settlement in after:
		now[settlement.id] = settlement
	var area := Rect2()
	for id: int in _merged_keys(old, now):
		var was: Settlement = old.get(id)
		var is_now: Settlement = now.get(id)
		var bounded := (was != null and was.boundary != "") or (is_now != null and is_now.boundary != "")
		if not bounded or (was != null and was.same_as(is_now)):
			continue
		for held: Settlement in [was, is_now]:
			if held == null or doc.wall(held.source) == null:
				continue
			var reach := MARGIN_M + STREET_SIDE_M + VillageFieldGround.REGROW_M
			var bounds := WallGeometry.clear_bounds(doc.wall(held.source)).grow(reach)
			for plaza in held.plazas:
				var r := float(plaza["radius"]) + reach
				bounds = bounds.merge(Rect2(plaza["at"] - Vector2(r, r), Vector2(r, r) * 2.0))
			area = bounds if not area.has_area() else area.merge(bounds)
	return area


static func _merged_keys(a: Dictionary, b: Dictionary) -> Array:
	var out := a.keys()
	for key: Variant in b.keys():
		if not out.has(key):
			out.append(key)
	return out


## A gate pier: a short tall wall along the start (or with `at_end`, the end) of `points`.
static func _pier(id: int, points: PackedVector2Array, height: float, at_end: bool) -> Wall:
	var line := points.duplicate()
	if at_end:
		line.reverse()
	var from := line[0]
	var to := from
	for p in line:
		to = p
		if p.distance_to(from) >= PIER_LENGTH_M:
			break
	if to.distance_to(from) < Wall.MIN_SEGMENT_M:
		to = from + Vector2.RIGHT * PIER_LENGTH_M
	to = from + (to - from).normalized() * PIER_LENGTH_M
	return Wall.make(id, Wall.Kind.STONE, PackedVector2Array([from, to]), false, height)


## The outward normal of side a -> b of a counter-clockwise polygon.
static func _outward(a: Vector2, b: Vector2) -> Vector2:
	var along := (b - a).normalized()
	return Vector2(along.y, -along.x)


## The closed `outline` resampled every `step` along its length.
static func _resample(outline: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var loop := outline + PackedVector2Array([outline[0]])
	var total := _length(loop)
	var count := maxi(ceili(total / step), 3)
	var spacing := total / count
	var k := 0
	var walked := 0.0
	for s in count:
		var want := s * spacing
		while k < loop.size() - 2 and walked + loop[k].distance_to(loop[k + 1]) < want:
			walked += loop[k].distance_to(loop[k + 1])
			k += 1
		var side := loop[k].distance_to(loop[k + 1])
		var t := 0.0 if side <= 0.0 else clampf((want - walked) / side, 0.0, 1.0)
		out.append(loop[k].lerp(loop[k + 1], t))
	return out


static func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(1, points.size()):
		total += points[k - 1].distance_to(points[k])
	return total


static func _rdp(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var a := points[0]
	var b := points[points.size() - 1]
	var worst := -1.0
	var at := 0
	for k in range(1, points.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(points[k], a, b).distance_to(points[k])
		if d > worst:
			worst = d
			at = k
	if worst <= SIMPLIFY_M:
		return PackedVector2Array([a, b])
	var left := _rdp(points.slice(0, at + 1))
	var right := _rdp(points.slice(at))
	left.remove_at(left.size() - 1)
	return left + right
