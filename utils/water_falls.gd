class_name WaterFalls
extends RefCounted

## Waterfalls (phase 4c): where a river falls rather than riffles, pure. Decided in two
## places that agree by construction: at plan time (WaterFallPlan, run by WaterEdit.plan_river
## from the ground profile along the stroke) and at runtime (is_fall(), from the bodies'
## levels and the ground as it is now). This class holds the rule's constants and the
## runtime. Summary: docs/systems/waterfalls.md.
##
## Runtime. Reaches joined end to end (the upper's last point is the lower's first, as
## WaterMeshBuilder.cascades pairs them) are a fall when the upper level stands
## FALL_MIN_DROP_M or more over the lower (is_drop(); what the carve uses, since the ground
## is not carved yet) and the ground along the lower course near the joint has a stretch at
## FALL_FACE_SLOPE or steeper (is_fall(); the cliff rule's start, so every fall face reads
## as rock). New carves pass both; a v0.1.29 document gets a fall only where its ground is
## cliff-steep and keeps its draped riffle sheet elsewhere. Everything downstream (mesh,
## dressing, flow, crossings) derives from falls() and footprint(). Nothing is persisted.
##
## The plan-time half (the fine profile, drop runs, lips and the shaping of the stroke's
## control line) is WaterFallPlan.

## A drop shorter than this is a riffle: about half a 5 ft tier, clear of REACH_DROP_M.
const FALL_MIN_DROP_M := 0.75
## A fall face is at least as steep as the cliff rule's start, so it reads as rock.
const FALL_FACE_SLOPE := tan(deg_to_rad(TerrainRules.CLIFF_START_DEG))
## One fall is about one tier high, never under this.
const FALL_TARGET_MIN_M := 1.0
## The shortest pool between two falls: at least this, or this many half-widths.
const FALL_SPACING_MIN_M := 4.0
const FALL_SPACING_PER_HALF_WIDTH := 3.0
## The plunge pool below a fall: its length along the course per metre of drop (clamped) and
## its extra depth (for the carve). How much wider its point is: WaterFallPlan.PLUNGE_WIDEN.
const PLUNGE_PER_DROP := 1.5
const PLUNGE_MIN_M := 1.5
const PLUNGE_MAX_M := 4.0
const PLUNGE_DEPTH_PER_DROP := 0.3
const PLUNGE_DEPTH_MIN_M := 0.2
const PLUNGE_DEPTH_MAX_M := 0.9
## How far past the face's own run (drop / FALL_FACE_SLOPE) is_fall() looks for the steep
## stretch, beyond the lip set-back's reach.
const FACE_SEARCH_M := 1.0


## The drop one fall aims for on `doc`: one tier, never under FALL_TARGET_MIN_M.
static func fall_target(doc: MapDocument) -> float:
	return maxf(FALL_TARGET_MIN_M, doc.tier_height_m)


## The shortest pool between two falls of a channel `half_width` wide.
static func fall_spacing(half_width: float) -> float:
	return maxf(FALL_SPACING_MIN_M, FALL_SPACING_PER_HALF_WIDTH * half_width)


## How far below the lip the plunge pool of a `drop` metre fall reaches along the course.
static func plunge_length(drop: float) -> float:
	return clampf(PLUNGE_PER_DROP * drop, PLUNGE_MIN_M, PLUNGE_MAX_M)


## How much deeper than the bed the plunge pool of a `drop` metre fall is cut (the carve).
static func plunge_depth(drop: float) -> float:
	return clampf(PLUNGE_DEPTH_PER_DROP * drop, PLUNGE_DEPTH_MIN_M, PLUNGE_DEPTH_MAX_M)


## How far along the lower course from the joint is_fall() looks for the face: the face's
## own run at FALL_FACE_SLOPE, the search margin and the lip set-back's reach.
static func face_search(drop: float, half_width: float) -> float:
	return drop / FALL_FACE_SLOPE + FACE_SEARCH_M + half_width + WaterGeometry.RIVER_BANK_M


## True when reach `upper` stands FALL_MIN_DROP_M or more over reach `lower`: the drop
## test alone, what the carve uses before the ground is carved.
static func is_drop(upper: WaterBody, lower: WaterBody) -> bool:
	return upper.level_m - lower.level_m >= FALL_MIN_DROP_M


## True when the step from reach `upper` into reach `lower` (joined end to end) is a fall on
## `doc`'s ground as it is: is_drop(), and the ground along the lower course within
## face_search() of the joint has a stretch at FALL_FACE_SLOPE or steeper.
static func is_fall(doc: MapDocument, upper: WaterBody, lower: WaterBody) -> bool:
	if not is_drop(upper, lower) or lower.points.size() < 2:
		return false
	if doc.heights.size() != doc.sample_count():
		return false
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var length := face_search(upper.level_m - lower.level_m, lower.half_widths[0])
	return steepest_within(doc, course, length) >= FALL_FACE_SLOPE


## The steepest fall per metre of `doc`'s ground between consecutive sample-step points along
## `course` over its first `length` metres (0 when it never falls).
static func steepest_within(doc: MapDocument, course: PackedVector2Array, length: float) -> float:
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var ground_of := func(p: Vector2) -> float: return WaterGeometry.ground_at(doc, p)
	var profile := WaterFallPlan.fine_profile(_truncated(course, length), step, ground_of)
	var arc: PackedFloat32Array = profile.arc
	var ground: PackedFloat32Array = profile.ground
	var steepest := 0.0
	for k in arc.size() - 1:
		steepest = maxf(steepest, WaterFallPlan.slope(arc, ground, k))
	return steepest


## The drops of `bodies` (rivers joined end to end, the lower one FALL_MIN_DROP_M or more
## below the upper, is_drop()), as falls() describes them; the ground is not consulted.
static func drops(bodies: Array[WaterBody]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in bodies.size():
		var upper := bodies[a]
		if not upper.is_river() or upper.points.size() < 2:
			continue
		for b in bodies.size():
			var lower := bodies[b]
			if b == a or not lower.is_river() or lower.points.size() < 2:
				continue
			if not is_drop(upper, lower):
				continue
			if (
				upper.points[-1].distance_squared_to(lower.points[0])
				< WaterGeometry.JOIN_EPSILON_SQ
			):
				out.append(_entry(bodies, a, b))
	return out


## Every fall of `doc` (is_fall() over the joined pairs of its rivers): {"upper_index",
## "lower_index" (into doc.water_bodies), "lip": Vector2 (the shared point), "dir": the
## lower course's unit direction there, "half_width": the channel at the lip, "top",
## "bottom": the two levels, "face_run": the face's horizontal run at FALL_FACE_SLOPE,
## "plunge": plunge_length() of the drop}.
static func falls(doc: MapDocument) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for drop in drops(doc.water_bodies):
		var upper: WaterBody = doc.water_bodies[drop.upper_index]
		var lower: WaterBody = doc.water_bodies[drop.lower_index]
		if is_fall(doc, upper, lower):
			out.append(drop)
	return out


## One flag per step of a stroke's reaches `bodies` (in order, as WaterCarve.joined_course
## takes them): 1 where the step is a fall by the drop test (is_drop()), for the carve.
static func fall_flags(bodies: Array[WaterBody]) -> PackedByteArray:
	var out := PackedByteArray()
	for k in bodies.size() - 1:
		out.append(1 if is_drop(bodies[k], bodies[k + 1]) else 0)
	return out


## The face samples of every fall of `doc` (footprint_of() of each, merged), ascending and
## unique. For the dressing and the flow bake.
static func footprint(doc: MapDocument) -> PackedInt32Array:
	var found := {}
	for fall in falls(doc):
		for i in footprint_of(doc, fall):
			found[i] = true
	var out := PackedInt32Array()
	for i: int in found:
		out.append(i)
	out.sort()
	return out


## The face samples of one fall of `doc` (a falls() entry): the samples within the channel's
## half-width of the lower course, from the lip to the face's foot (face_foot()), ascending
## and unique.
static func footprint_of(doc: MapDocument, fall: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var arcs := WaterFallPlan.arcs(course)
	var half: float = fall.half_width
	var foot := face_foot(doc, fall)
	var lip: Vector2 = fall.lip
	var direction: Vector2 = fall.dir
	var box := Vector2.ONE * (foot + half)
	var first := doc.world_to_sample(lip - box).floor().clamp(Vector2.ZERO, last)
	var stop := doc.world_to_sample(lip + box).ceil().clamp(Vector2.ZERO, last)
	for z in range(int(first.y), int(stop.y) + 1):
		for x in range(int(first.x), int(stop.x) + 1):
			var p := doc.sample_to_world(Vector2(x, z))
			if (p - lip).dot(direction) < 0.0:
				continue
			var near := WaterGeometry.nearest_on_polyline(course, p)
			if near.y < 0 or near.x > half:
				continue
			var s := int(near.y)
			var along := lerpf(arcs[s], arcs[s + 1], near.z)
			if along <= foot:
				out.append(doc.sample_index(x, z))
	return out


## How far down the lower course from the lip the face of `fall` (a falls() entry of `doc`)
## reaches on the ground as it is: where the centreline ground first reaches the lower level,
## or face_search() when it never does. The footprint's and the foam ring's foot (the
## carved foot, WaterCarve.fall_foot, lies a little further: the pool is deepest there).
static func face_foot(doc: MapDocument, fall: Dictionary) -> float:
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var ground_of := func(p: Vector2) -> float: return WaterGeometry.ground_at(doc, p)
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var search := face_search(fall.top - fall.bottom, fall.half_width)
	var profile := WaterFallPlan.fine_profile(_truncated(course, search), step, ground_of)
	for k in profile.arc.size():
		if profile.ground[k] <= fall.bottom:
			return profile.arc[k]
	return search


## True when map point `p` lies on the face of `fall` (a falls() entry of `doc`): within the
## channel's half-width of the lower course, from the lip down to the carved face's foot
## (WaterCarve.fall_foot). The rock a stroke's end can land on without being wet.
static func on_face(doc: MapDocument, fall: Dictionary, p: Vector2) -> bool:
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var near := WaterGeometry.nearest_on_polyline(course, p)
	if near.y < 0 or near.x > float(fall.half_width):
		return false
	var arcs := WaterFallPlan.arcs(course)
	var along := lerpf(arcs[int(near.y)], arcs[int(near.y) + 1], near.z)
	var foot := WaterCarve.fall_foot(float(fall.top) - float(fall.bottom), lower.depth_m())
	return along >= 0.0 and along <= foot


## The point of the plunge pool of `fall` (a falls() entry of `doc`) a stroke ending on its
## face joins: the lower course `past` metres beyond the carved face's foot
## (WaterCarve.fall_foot), where the pool is deepest; the course's last point when it is
## shorter.
static func pool_point(doc: MapDocument, fall: Dictionary, past: float) -> Vector2:
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	var arcs := WaterFallPlan.arcs(course)
	var foot := WaterCarve.fall_foot(float(fall.top) - float(fall.bottom), lower.depth_m())
	return WaterFallPlan.point_at(course, arcs, minf(foot + past, arcs[-1]))


## falls() entry for the step from `bodies[a]` into `bodies[b]`.
static func _entry(bodies: Array[WaterBody], a: int, b: int) -> Dictionary:
	var upper := bodies[a]
	var lower := bodies[b]
	var drop := upper.level_m - lower.level_m
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	return {
		"upper_index": a,
		"lower_index": b,
		"lip": lower.points[0],
		"dir": WaterGeometry.end_direction(course, false),
		"half_width": lower.half_widths[0],
		"top": upper.level_m,
		"bottom": lower.level_m,
		"face_run": drop / FALL_FACE_SLOPE,
		"plunge": plunge_length(drop),
	}


## `course` cut to its first `length` metres of arc, the last point interpolated.
static func _truncated(course: PackedVector2Array, length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var walked := 0.0
	for i in course.size():
		if i == 0:
			out.append(course[0])
			continue
		var segment := course[i - 1].distance_to(course[i])
		if walked + segment >= length:
			var t := clampf((length - walked) / segment, 0.0, 1.0) if segment > 1e-9 else 0.0
			out.append(course[i - 1].lerp(course[i], t))
			break
		walked += segment
		out.append(course[i])
	return out
