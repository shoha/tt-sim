class_name SettlementGround
extends RefCounted

## Pure: the ground a Dress lays under a street (villages phase 2, docs/systems/settlements.md
## "Ground"). From a Settlement, its street and the kit's `ground` block ({"road", "door_path",
## "plaza"}: palette surface ids, ProcgenSettlement.ground_of) it plans Paint strokes: capsules
## {"role", "surface", "from", "to", "radius", "seconds"} in document metres that SettlementPaint
## writes through SurfaceStroke, so roads and paths are ordinary painted surfaces (they undo with
## the dressing, clear plants under them when the surface's role is `built`, tint their
## surroundings and travel as the existing `surface` live edit). Nothing here reads a scene.
##
## The road follows the street's centre line, resampled every ROAD_STEP_M, as wide as the street's
## profile asks (StreetProfile: its species and setback). A wide street (the modern row) also gets
## its pavements: one band per side from kerb to facade in the kit's door path surface, painted
## over the road's soft edge so the kerb reads (role "pavement", no slot of its own), and no door
## paths. A stretch is
## left unpainted where the road or its edges would be wet, too steep along or across, or would
## touch a building (a Structure's footprint), counted in `refused`. Each door of each lot is
## joined to the street by two short strokes bending a little (the bend is a hash of the street,
## side and lot, never the settlement's seed, so a re-dress moves no path) that end inside the
## road's edge; a door whose join would be wet, steep or blocked, or whose road stretch was
## refused, gets none. A plaza disc is filled by one stroke, unless its centre or most of its rim
## is wet or its ground is too steep. Strokes come out in paint order (road, plaza, door paths: the
## newest paint wins a sample), and only for the roles the map can afford: a kit names at most three
## surfaces, each takes a painted-surface slot unless the map already paints it (`affordable`).
##
## Deterministic: integer hashes and the document only; the same record on the same map plans the
## same strokes.

## The road is sampled this far apart along the centre line.
const ROAD_STEP_M := 1.5
## The road's half width is the street's profile's (StreetProfile); a lane street's limits.
const ROAD_HALF_MIN_M := StreetProfile.ROAD_HALF_MIN_M
const ROAD_HALF_MAX_M := StreetProfile.ROAD_HALF_MAX_M
## A wide street's pavement (StreetProfile `pavement`) is laid as one band per side whose full
## cover starts this share of the strip out from the kerb (the soft edge inside it reaches the
## kerb, over the road's own edge) and runs to the facade.
const PAVEMENT_KERB_SHARE := 0.15
## Rise over run limits: along the road, across it, along a door path or across a plaza.
const ROAD_MAX_SLOPE := 0.5
const CROSS_MAX_SLOPE := 0.7
const PATH_MAX_SLOPE := 0.6
const PLAZA_MAX_SLOPE := 0.45
## A door path's brush radius, and how far into the road's half width it ends.
const DOOR_RADIUS_M := 0.75
const DOOR_INTO_ROAD := 0.5
const DOOR_BEND_M := 0.25
## A brush radius is its full-cover half width times this: the rest is the soft edge.
const EDGE_REACH := 1.4
## Exposure of a stroke (SurfaceStroke.dab seconds): full cover over most of the width.
const ROAD_SECONDS := 1.2
const DOOR_SECONDS := 1.2
const PLAZA_SECONDS := 1.2
## Straight road segments merge into one stroke while each keeps within acos(MERGE_COS) of the
## first and the stroke stays under MERGE_MAX_M.
const MERGE_COS := 0.9976
const MERGE_MAX_M := 30.0
## A plaza is refused when this share of its rim is wet.
const PLAZA_WET_SHARE := 0.25
const PLAZA_RIM_POINTS := 8
## Roles in paint order, and in the order the slot budget serves them. Fields (VillageFields) go
## first, under the road; their surfaces are the kind's own, not the kit's, and take the slots left.
const PAINT_ORDER: Array[String] = ["field", "road", "pavement", "plaza", "door_path"]
const BUDGET_ORDER: Array[String] = ["road", "door_path", "plaza"]
## A field is refused when its centre is wet, this share of its rim is, or its ground is steeper.
const FIELD_MAX_SLOPE := 0.35


## The road's half width (full cover) for a street of species `preset` with setback `setback_m`
## (StreetProfile; preset 0, a lane street, by default).
static func road_half_width(setback_m: float, preset: int = 0) -> float:
	return float(StreetProfile.of(preset, setback_m)["road_half"])


## The roles of `wanted` ({role: surface id}) a map can paint: a role whose surface the map already
## paints is free, and each different new surface takes one of the slots left of
## MapDocument.PAINT_SURFACE_LIMIT, served in BUDGET_ORDER (road, door paths, plaza). Returns
## {role: surface id}.
static func affordable(doc: MapDocument, wanted: Dictionary) -> Dictionary:
	var out := {}
	var free := MapDocument.PAINT_SURFACE_LIMIT - doc.surface_ids.size()
	var taken: Array[String] = []
	for role in BUDGET_ORDER:
		if not wanted.has(role):
			continue
		var surface := str(wanted[role])
		if surface in doc.surface_ids or taken.has(surface):
			out[role] = surface
		elif free > 0:
			free -= 1
			taken.append(surface)
			out[role] = surface
	return out


## The plan for `settlement` on `doc`: {"strokes": Array[Dictionary] in paint order, "roles":
## Array[String] of the roles that got strokes, "surfaces": Array[String] (distinct, in paint
## order), "road_m": metres of road, "doors": door paths laid, "refused": {"water", "slope",
## "building", "slots", "unknown"} counts}. `ground` is the kit's block; `known` the palette's
## surface table (PaletteLibrary.surfaces()): a surface it lacks is not painted. `roles` limits the
## plan to some roles (adding one plaza plans just "plaza").
static func plan(
	doc: MapDocument,
	settlement: Settlement,
	ground: Dictionary,
	known: Dictionary,
	roles: Array[String] = PAINT_ORDER
) -> Dictionary:
	var result := {
		"strokes": [] as Array[Dictionary],
		"roles": [] as Array[String],
		"surfaces": [] as Array[String],
		"road_m": 0.0,
		"doors": 0,
		"refused": {"water": 0, "slope": 0, "building": 0, "slots": 0, "unknown": 0},
	}
	var refused: Dictionary = result["refused"]
	var wanted := {}
	for role in PAINT_ORDER:
		if not ground.has(role) or not roles.has(role):
			continue
		if known.has(str(ground[role])):
			wanted[role] = ground[role]
		else:
			refused["unknown"] += 1
	var granted := affordable(doc, wanted)
	refused["slots"] = wanted.size() - granted.size()
	var fielding := roles.has("field") and not settlement.fields.is_empty()
	if (granted.is_empty() and not fielding) or doc.heights.size() != doc.sample_count():
		return result
	var world := _World.new(doc)
	var wall := doc.wall(settlement.source) if settlement.source > 0 else null
	var strokes: Array[Dictionary] = []
	var road_samples := PackedVector2Array()
	var road_kept: Array[bool] = []
	var half := 0.0
	# The surface each role paints: the kit's, and a wide street's pavement in its door paths' one
	# (no slot of its own).
	var surface_of := granted.duplicate()
	if wall != null and wall.is_row():
		var profile := StreetProfile.of_wall(wall)
		half = float(profile["road_half"])
		road_samples = resample(wall.points, ROAD_STEP_M)
		road_kept = _road_kept(world, road_samples, half, refused)
		if bool(profile["pavement"]) and roles.has("pavement") and granted.has("door_path"):
			surface_of["pavement"] = granted["door_path"]
	for role in PAINT_ORDER:
		if role == "field":
			if not fielding:
				continue
			var laid := _field_strokes(world, doc, settlement, known, granted, refused)
			for stroke in laid:
				var held := stroke.duplicate()
				held["role"] = role
				strokes.append(held)
				if not (result["surfaces"] as Array[String]).has(str(stroke["surface"])):
					(result["surfaces"] as Array[String]).append(str(stroke["surface"]))
			if not laid.is_empty():
				(result["roles"] as Array[String]).append(role)
			continue
		if not surface_of.has(role):
			continue
		var made: Array[Dictionary] = []
		match role:
			"road":
				made = _road_strokes(world, road_samples, road_kept, half, refused)
				result["road_m"] = _length_of(made)
			"pavement":
				made = _pavement_strokes(world, wall, refused)
			"plaza":
				made = _plaza_strokes(world, settlement, refused)
			"door_path":
				# A paved pavement already joins every door to the kerb; a path would only push
				# its paving into the road (it ends inside the road's edge).
				if wall != null and wall.is_row() and not surface_of.has("pavement"):
					made = _door_strokes(
						world, doc, wall, road_samples, road_kept, granted.has("road"), half, refused
					)
					result["doors"] = int(made.size() * 0.5)
		for stroke in made:
			stroke["surface"] = surface_of[role]
			# Held to a hundredth (SettlementGroundIO), so the record and the paint agree.
			var held := SettlementGroundIO.snapped_stroke(stroke)
			held["role"] = role
			strokes.append(held)
		if not made.is_empty():
			(result["roles"] as Array[String]).append(role)
			if not (result["surfaces"] as Array[String]).has(surface_of[role]):
				(result["surfaces"] as Array[String]).append(str(surface_of[role]))
	result["strokes"] = strokes
	return result


## `points` (a polyline) resampled about every `step` metres of arc: every vertex stays (a corner
## is never cut) and each segment is divided evenly.
static func resample(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	for k in range(1, points.size()):
		var count := maxi(ceili(points[k - 1].distance_to(points[k]) / step), 1)
		for n in range(1, count + 1):
			out.append(points[k - 1].lerp(points[k], float(n) / count))
	return out


# --- road --------------------------------------------------------------------------------------


## Per sample: the road may be laid there (centre and both edges dry, not across a steep slope,
## clear of buildings).
static func _road_kept(
	world: _World, samples: PackedVector2Array, half: float, refused: Dictionary
) -> Array[bool]:
	var kept: Array[bool] = []
	for i in samples.size():
		var tangent := _tangent(samples, i)
		var side := Vector2(-tangent.y, tangent.x) * half
		var cause := world.problem_at(samples[i], half)
		if cause == "":
			cause = world.problem_at(samples[i] + side, 0.0)
		if cause == "":
			cause = world.problem_at(samples[i] - side, 0.0)
		if cause == "":
			var across := maxf(
				absf(world.height(samples[i] + side) - world.height(samples[i])),
				absf(world.height(samples[i] - side) - world.height(samples[i]))
			)
			if across / half > CROSS_MAX_SLOPE:
				cause = "slope"
		if cause != "":
			refused[cause] += 1
		kept.append(cause == "")
	return kept


static func _road_strokes(
	world: _World,
	samples: PackedVector2Array,
	kept: Array[bool],
	half: float,
	refused: Dictionary
) -> Array[Dictionary]:
	# The laid segments as index pairs (i - 1, i), then runs of nearly straight ones merged into one
	# capsule each: a dab costs by the area of its capsule, and short overlapping capsules along a
	# straight street cost about five times one long one.
	var laid: Array[int] = []
	for i in range(1, samples.size()):
		if not kept[i - 1] or not kept[i]:
			continue
		var between := (samples[i - 1] + samples[i]) * 0.5
		var cause := world.problem_at(between, half)
		if cause == "" and world.slope(samples[i - 1], samples[i]) > ROAD_MAX_SLOPE:
			cause = "slope"
		if cause != "":
			refused[cause] += 1
			continue
		laid.append(i)
	var out: Array[Dictionary] = []
	var k := 0
	while k < laid.size():
		var first := laid[k]
		var heading := (samples[first] - samples[first - 1]).normalized()
		var last := first
		while (
			k + 1 < laid.size()
			and laid[k + 1] == last + 1
			and samples[first - 1].distance_to(samples[last + 1]) <= MERGE_MAX_M
			and heading.dot((samples[last + 1] - samples[last]).normalized()) >= MERGE_COS
		):
			k += 1
			last = laid[k]
		out.append(
			{
				"from": samples[first - 1],
				"to": samples[last],
				"radius": half * EDGE_REACH,
				"seconds": ROAD_SECONDS,
			}
		)
		k += 1
	return out


# --- pavement ----------------------------------------------------------------------------------


## A wide street's pavements: per side, a band along the centre line pushed out so that its full
## cover runs from PAVEMENT_KERB_SHARE of the strip past the kerb to the facade, its soft inner edge
## reaching back to the kerb. Laid where the band is dry and not too steep, as the road is.
static func _pavement_strokes(world: _World, wall: Wall, refused: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var profile := StreetProfile.of_wall(wall)
	var kerb := float(profile["road_half"])
	var strip := float(profile["strip"])
	# Full cover kerb + share * strip .. kerb + strip; the soft edge (EDGE_REACH) ends at the kerb.
	var band := strip * (1.0 - PAVEMENT_KERB_SHARE) * 0.5
	var centre := kerb + strip - band
	band = minf(band, (centre - kerb) / EDGE_REACH)
	for side in [1, -1]:
		var line := SettlementFrontage.facade_line(wall.points, centre, side)
		var samples := resample(line, ROAD_STEP_M)
		var kept := _road_kept(world, samples, band, refused)
		out.append_array(_road_strokes(world, samples, kept, band, refused))
	return out


# --- door paths --------------------------------------------------------------------------------


static func _door_strokes(
	world: _World,
	doc: MapDocument,
	wall: Wall,
	road: PackedVector2Array,
	road_kept: Array[bool],
	road_planned: bool,
	half: float,
	refused: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach := half * DOOR_INTO_ROAD
	for frontage in SettlementFrontage.of_street(doc, wall):
		for lot in frontage.lots:
			for door: Dictionary in lot["doors"]:
				var at := frontage.point_at(float(door["s"]))
				var near := _closest_on(wall.points, at)
				var gap := at.distance_to(near)
				if gap < 0.2:
					continue
				var dir := (near - at) / gap
				var length := maxf(gap - reach, 0.4)
				var end := at + dir * length
				var wobble := _bend(wall.id, frontage.key, str(lot["id"]))
				var mid := at + dir * length * 0.5 + Vector2(-dir.y, dir.x) * wobble
				if road_planned and not _road_reaches(road, road_kept, near):
					continue
				var cause := world.problem_at(mid, DOOR_RADIUS_M)
				if cause == "":
					cause = world.problem_at(end, DOOR_RADIUS_M)
				if cause == "" and world.slope(at, end) > PATH_MAX_SLOPE:
					cause = "slope"
				if cause != "":
					refused[cause] += 1
					continue
				for pair in [[at, mid], [mid, end]]:
					out.append(
						{
							"from": pair[0],
							"to": pair[1],
							"radius": DOOR_RADIUS_M * EDGE_REACH,
							"seconds": DOOR_SECONDS,
						}
					)
	return out


## A deterministic sideways bend of a door path, -DOOR_BEND_M..DOOR_BEND_M, to a millimetre.
static func _bend(wall_id: int, side_key: String, lot_id: String) -> float:
	var h := absi(hash([wall_id, side_key, lot_id, "door_bend"])) % 2001
	return snappedf((float(h) / 1000.0 - 1.0) * DOOR_BEND_M, 0.001)


## True when the road sample nearest `near` was kept.
static func _road_reaches(
	road: PackedVector2Array, kept: Array[bool], near: Vector2
) -> bool:
	var best := INF
	var index := -1
	for i in road.size():
		var d := road[i].distance_squared_to(near)
		if d < best:
			best = d
			index = i
	return index >= 0 and kept[index]


# --- plazas ------------------------------------------------------------------------------------


static func _plaza_strokes(
	world: _World, settlement: Settlement, refused: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plaza in settlement.plazas:
		var at: Vector2 = plaza["at"]
		var radius := float(plaza["radius"])
		var cause := _plaza_cause(world, at, radius)
		if cause != "":
			refused[cause] += 1
			continue
		out.append({"from": at, "to": at, "radius": radius * 1.12, "seconds": PLAZA_SECONDS})
	return out


## The map as the planner asks about it (water, ground height, buildings), built once for a run of
## plaza_problem calls such as a held drag's.
static func world_of(doc: MapDocument) -> RefCounted:
	return _World.new(doc)


## Why a plaza of `radius` at map point `at` would not be paved: "water" (its centre is wet or a
## quarter of its rim), "building" (its centre is in a footprint) or "slope" (the ground across it
## is too steep), else "". `world` is world_of's.
static func plaza_problem(world: RefCounted, at: Vector2, radius: float) -> String:
	return _plaza_cause(world as _World, at, radius)


static func _plaza_cause(world: _World, at: Vector2, radius: float) -> String:
	var cause := world.problem_at(at, 0.0)
	var wet := 0
	var low := world.height(at)
	var high := low
	for k in PLAZA_RIM_POINTS:
		var rim := at + Vector2.from_angle(TAU * k / PLAZA_RIM_POINTS) * radius
		if world.problem_at(rim, 0.0) == "water":
			wet += 1
		low = minf(low, world.height(rim))
		high = maxf(high, world.height(rim))
	if cause == "" and float(wet) / PLAZA_RIM_POINTS > PLAZA_WET_SHARE:
		cause = "water"
	if cause == "" and (high - low) / (2.0 * radius) > PLAZA_MAX_SLOPE:
		cause = "slope"
	return cause


# --- fields ------------------------------------------------------------------------------------


## The strokes of `settlement`'s fields (VillageFields.strokes_of), a whole field left out when its
## centre or a quarter of its rim is wet or its ground is too steep, and a stroke left out when the
## palette lacks its surface or the map has no slot left for it (after the kit's `granted` roles).
static func _field_strokes(
	world: _World,
	doc: MapDocument,
	settlement: Settlement,
	known: Dictionary,
	granted: Dictionary,
	refused: Dictionary
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var used: Array[String] = []
	for surface: Variant in granted.values():
		if not doc.surface_ids.has(str(surface)) and not used.has(str(surface)):
			used.append(str(surface))
	var free := MapDocument.PAINT_SURFACE_LIMIT - doc.surface_ids.size() - used.size()
	for field in settlement.fields:
		var at: Vector2 = field["at"]
		var radius := float(field["radius"])
		var cause := world.problem_at(at, 0.0)
		var wet := 0
		var low := world.height(at)
		var high := low
		for k in PLAZA_RIM_POINTS:
			var rim := at + Vector2.from_angle(TAU * k / PLAZA_RIM_POINTS) * radius
			if world.problem_at(rim, 0.0) == "water":
				wet += 1
			low = minf(low, world.height(rim))
			high = maxf(high, world.height(rim))
		if cause == "" and float(wet) / PLAZA_RIM_POINTS > PLAZA_WET_SHARE:
			cause = "water"
		if cause == "" and (high - low) / (2.0 * radius) > FIELD_MAX_SLOPE:
			cause = "slope"
		if cause != "":
			refused[cause] += 1
			continue
		for stroke in VillageFields.strokes_of(field, settlement.seed_value):
			var surface := str(stroke["surface"])
			if not known.has(surface):
				refused["unknown"] += 1
				continue
			if not doc.surface_ids.has(surface) and not used.has(surface):
				if free <= 0:
					refused["slots"] += 1
					continue
				free -= 1
				used.append(surface)
			out.append(stroke)
	return out


# --- helpers -----------------------------------------------------------------------------------


static func _tangent(samples: PackedVector2Array, i: int) -> Vector2:
	var a := samples[maxi(i - 1, 0)]
	var b := samples[mini(i + 1, samples.size() - 1)]
	var t := (b - a).normalized()
	return t if t.length() > 0.5 else Vector2.RIGHT


static func _closest_on(line: PackedVector2Array, p: Vector2) -> Vector2:
	var best := line[0]
	var best_d := INF
	for k in range(1, line.size()):
		var c := Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _length_of(strokes: Array[Dictionary]) -> float:
	var total := 0.0
	for stroke in strokes:
		total += (stroke["from"] as Vector2).distance_to(stroke["to"])
	return snappedf(total, 0.01)


## The map as the planner asks about it: water, ground height and buildings.
class _World:
	extends RefCounted

	var doc: MapDocument
	var courses: Dictionary
	## [Rect2, PackedVector2Array] per structure with a usable footprint.
	var buildings: Array = []

	func _init(document: MapDocument) -> void:
		doc = document
		courses = WaterGeometry.river_courses(document)
		for structure in document.structures:
			if structure.footprint.size() < 3:
				continue
			var box := Rect2(structure.footprint[0], Vector2.ZERO)
			for p in structure.footprint:
				box = box.expand(p)
			buildings.append([box, structure.footprint])

	func height(p: Vector2) -> float:
		return WaterGeometry.ground_at(doc, p)

	func slope(a: Vector2, b: Vector2) -> float:
		return absf(height(b) - height(a)) / maxf(a.distance_to(b), 0.01)

	## "water", "building" or "": why a brush of `radius` at `p` is not wanted there.
	func problem_at(p: Vector2, radius: float) -> String:
		if WaterGeometry.is_wet_at(doc, p, -1, courses):
			return "water"
		for entry in buildings:
			var box: Rect2 = entry[0]
			if not box.grow(radius).has_point(p):
				continue
			var plan: PackedVector2Array = entry[1]
			if Geometry2D.is_point_in_polygon(p, plan):
				return "building"
			if radius > 0.0 and _near_edge(plan, p, radius):
				return "building"
		return ""

	func _near_edge(plan: PackedVector2Array, p: Vector2, radius: float) -> bool:
		for k in plan.size():
			var c := Geometry2D.get_closest_point_to_segment(p, plan[k], plan[(k + 1) % plan.size()])
			if c.distance_to(p) < radius:
				return true
		return false
