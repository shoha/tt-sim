class_name WaterFalls
extends RefCounted

## Waterfalls (phase 4c): where a river falls rather than riffles, pure. Decided in two
## places that agree by construction: at plan time (WaterEdit.plan_river, from the ground
## profile along the stroke) and at runtime (is_fall(), from the bodies' levels and the ground
## as it is now). Summary: docs/ARCHITECTURE.md "Water model and flow bake", "Carving water".
##
## Plan time. The ground along the resampled control line is sampled every sample step (the
## "fine profile", fine_profile()); a drop is a maximal run of steps falling at FALL_SLOPE or
## more, grown over the rounded shoulder above it and the toe below it (drop_runs()), losing
## FALL_MIN_DROP_M or more in all. Each drop becomes n falls of about fall_target() each,
## their lips at least fall_spacing() apart along the run, lip 0 at the brink (plan_lips());
## a lip is never within the spacing's half of a free stroke end (a spring starts in its first
## pool; an end in other water, a confluence, carries its fall into that water) nor within
## LIP_MARGIN_M of either end. On a diagonal crossing of a tier the lip slides upstream
## until the whole cross-line (the half-width plus the bank either side) stands on ground at
## or above the upper level, so the notch is cut square to the flow and no upper water hangs
## past the brink (the set-back; a cross-line that can never stand clear, as on a hill flank,
## leaves the lip where it was). shape_line() then inserts the lips as control points and
## forced reach boundaries, below each lip a point of the channel's own width at the carved
## face's foot (WaterCarve.fall_foot) and a plunge-pool point PLUNGE_WIDEN wider half the
## plunge length past the foot (so the face keeps the stroke's width and only the pool below
## it widens, P4c-2b), and splits every segment outside a drop that falls more than
## WaterGeometry.REACH_DROP_M, so no step that is not a fall reaches FALL_MIN_DROP_M; the
## points of a drop are "free" of the reach rule (WaterGeometry.reach_ranges), so the reach
## below a lip takes in the whole face and the pool below it and its level is that pool's. A
## stroke drawn uphill is reversed first (orient()): water runs downhill, so falls face
## downstream; a rise inside a stroke is never a fall.
##
## Runtime. Reaches joined end to end (the upper's last point is the lower's first, as
## WaterMeshBuilder.cascades pairs them) are a fall when the upper level stands
## FALL_MIN_DROP_M or more over the lower (is_drop(); what the carve uses, since the ground
## is not carved yet) and the ground along the lower course near the joint has a stretch at
## FALL_FACE_SLOPE or steeper (is_fall(); the cliff rule's start, so every fall face reads
## as rock). New carves pass both; a v0.1.29 document gets a fall only where its ground is
## cliff-steep and keeps its draped riffle sheet elsewhere. Everything downstream (mesh,
## dressing, flow, crossings) derives from falls() and footprint(). Nothing is persisted.

## A drop shorter than this is a riffle: about half a 5 ft tier, clear of REACH_DROP_M.
const FALL_MIN_DROP_M := 0.75
## The profile slope (rise over run) from which a drop counts: just above the steepest a
## riffle can be carved (WaterCarve.RIFFLE_SLOPE at its smoothstep peak, 0.45).
const FALL_SLOPE := 0.5
## A fall face is at least as steep as the cliff rule's start, so it reads as rock.
const FALL_FACE_SLOPE := tan(deg_to_rad(TerrainRules.CLIFF_START_DEG))
## One fall is about one tier high, never under this.
const FALL_TARGET_MIN_M := 1.0
## The shortest pool between two falls: at least this, or this many half-widths.
const FALL_SPACING_MIN_M := 4.0
const FALL_SPACING_PER_HALF_WIDTH := 3.0
## The plunge pool below a fall: its length along the course per metre of drop (clamped) and
## how much wider than the channel its inserted point is; its extra depth (for the carve).
const PLUNGE_PER_DROP := 1.5
const PLUNGE_MIN_M := 1.5
const PLUNGE_MAX_M := 4.0
const PLUNGE_WIDEN := 1.35
const PLUNGE_DEPTH_PER_DROP := 0.3
const PLUNGE_DEPTH_MIN_M := 0.2
const PLUNGE_DEPTH_MAX_M := 0.9
## A drop run grows over its rounded shoulder and toe this far at most (a tier's lip plus the
## soft profile's tent), while the ground still falls at SHOULDER_FLAT_SLOPE or more and the
## slope keeps easing away from the run (convex above, concave below).
const SHOULDER_M := HeightBrush.TIER_LIP_WIDTH_M + HeightBrush.TIER_SOFTEN_M
const SHOULDER_FLAT_SLOPE := 0.05
## How far past the face's own run (drop / FALL_FACE_SLOPE) is_fall() looks for the steep
## stretch, beyond the lip set-back's reach.
const FACE_SEARCH_M := 1.0
## No lip within this of either stroke end: both reaches need a point of their own.
const LIP_MARGIN_M := 1.0
## An inserted point this close to an existing one merges into it.
const MERGE_M := 0.2
## The set-back slides a lip upstream by at most this many reaches (half-width plus bank).
const SETBACK_REACHES := 3.0


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


## True when a stroke whose ground along it is `ground` was drawn uphill: its last point
## stands FALL_MIN_DROP_M or more above its first. Flat and gently rising strokes keep their
## drawn direction.
static func is_uphill(ground: PackedFloat32Array) -> bool:
	return ground.size() >= 2 and ground[-1] - ground[0] >= FALL_MIN_DROP_M


## `points`, `widths` and `ground` reversed when the stroke is uphill (is_uphill()), as
## they are otherwise: [PackedVector2Array, PackedFloat32Array, PackedFloat32Array], copies.
static func orient(
	points: PackedVector2Array, widths: PackedFloat32Array, ground: PackedFloat32Array
) -> Array:
	var line := points.duplicate()
	var sizes := widths.duplicate()
	var heights := ground.duplicate()
	if is_uphill(ground):
		line.reverse()
		sizes.reverse()
		heights.reverse()
	return [line, sizes, heights]


## The ground along the polyline `points` every `step` metres of arc length (a little less,
## so both ends are samples): {"arc": PackedFloat32Array, "points": PackedVector2Array,
## "ground": PackedFloat32Array of `ground_of`(point)}; empty arrays for fewer than two
## points.
static func fine_profile(
	points: PackedVector2Array, step: float, ground_of: Callable
) -> Dictionary:
	var arc := PackedFloat32Array()
	var at := PackedVector2Array()
	var ground := PackedFloat32Array()
	var arcs := _arcs(points)
	if points.size() >= 2 and arcs[-1] > 1e-9:
		var total := arcs[-1]
		var count := maxi(1, ceili(total / maxf(step, 1e-3) - 1e-6))
		var interval := total / count
		for n in count + 1:
			var s := minf(n * interval, total)
			arc.append(s)
			at.append(_point_at(points, arcs, s))
	for p in at:
		ground.append(ground_of.call(p))
	return {"arc": arc, "points": at, "ground": ground}


## The drop runs of a fine profile (`arc`, `ground`): inclusive index ranges Vector2i(first,
## last) of maximal runs of steps falling at FALL_SLOPE or more, each grown over its shoulder
## and toe (see the header), that lose FALL_MIN_DROP_M or more from first to last.
static func drop_runs(arc: PackedFloat32Array, ground: PackedFloat32Array) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var n := mini(arc.size(), ground.size())
	var i := 0
	while i < n - 1:
		if _slope(arc, ground, i) < FALL_SLOPE:
			i += 1
			continue
		var last := i
		while last < n - 1 and _slope(arc, ground, last) >= FALL_SLOPE:
			last += 1
		var first := _shoulder(arc, ground, i)
		last = _toe(arc, ground, last, n)
		if ground[first] - ground[last] >= FALL_MIN_DROP_M:
			runs.append(Vector2i(first, last))
		i = last + 1
	return runs


## The fall plan of a stroke along the control line `points` (half-width per point
## `widths`) whose fine profile is `profile` (fine_profile()): {"lips": Array of {"arc": the
## lip's arc length along `points`, "drop": the fall's drop, "half_width": the channel there},
## in arc order, "zones": PackedVector2Array of arc ranges (a drop run with a lip, from its
## brink or its first lip to its foot) whose points are free of the reach rule}. `free_ends`
## (x: the start, y: the end; 1 = free, not in other water) keeps lips half a spacing clear
## of a free end. See the header for the rules; the set-back needs `doc`'s ground.
static func plan_lips(
	doc: MapDocument,
	points: PackedVector2Array,
	widths: PackedFloat32Array,
	profile: Dictionary,
	free_ends: Vector2i
) -> Dictionary:
	var lips: Array[Dictionary] = []
	var zones := PackedVector2Array()
	var arc: PackedFloat32Array = profile.get("arc", PackedFloat32Array())
	var ground: PackedFloat32Array = profile.get("ground", PackedFloat32Array())
	if arc.size() < 2:
		return {"lips": lips, "zones": zones}
	var arcs := _arcs(points)
	var total := arc[-1]
	var target := fall_target(doc)
	var half_extent := doc.extent_m() * 0.5 - Vector2.ONE * WaterCarve.EDGE_MARGIN_M
	var last_lip := -INF
	for run in drop_runs(arc, ground):
		var half := _width_at(widths, arcs, arc[run.x])
		var spacing := fall_spacing(half)
		# The margins a lip keeps: from the ends, from the previous fall; the set-back may
		# slide a lip upstream of its run's brink, but never past these.
		var floor_arc := maxf(LIP_MARGIN_M, last_lip + spacing)
		var ceiling_arc := total - LIP_MARGIN_M
		if free_ends.x != 0:
			floor_arc = maxf(floor_arc, spacing * 0.5)
		if free_ends.y != 0:
			ceiling_arc = minf(ceiling_arc, total - spacing * 0.5)
		var usable := Vector2(maxf(arc[run.x], floor_arc), minf(arc[run.y], ceiling_arc))
		if usable.y <= usable.x:
			continue
		var zone_start := arc[run.x]
		var any := false
		for planned in _lip_arcs(arc, ground, usable, spacing, target):
			if any:
				floor_arc = last_lip + spacing
			var s := _setback(doc, points, arcs, widths, planned.x, floor_arc)
			if s < last_lip + spacing or s > total - LIP_MARGIN_M:
				continue
			if not _on_map(_point_at(points, arcs, s), half_extent):
				continue
			lips.append({"arc": s, "drop": planned.y, "half_width": _width_at(widths, arcs, s)})
			last_lip = s
			zone_start = minf(zone_start, s)
			any = true
		if any:
			zones.append(Vector2(zone_start, arc[run.y]))
	return {"lips": lips, "zones": zones}


## The control line `points` (half-widths `widths`, ground per point `ground`) with the plan's
## lips, foot and plunge points inserted (`depth_m`, the stroke's water depth in metres,
## places the carved foot) and its over-steep non-fall segments subdivided (see the header):
## {"points", "widths", "ground" (per point; `ground_of`(point) for the new ones), "forced":
## PackedInt32Array of the lip indices (reach boundaries), "free": PackedByteArray per point,
## 1 inside a plan zone}. Without lips or over-steep segments the line comes back as it is
## (copies), so a gentle stroke plans as it always did.
static func shape_line(
	points: PackedVector2Array,
	widths: PackedFloat32Array,
	ground: PackedFloat32Array,
	plan: Dictionary,
	depth_m: float,
	ground_of: Callable
) -> Dictionary:
	var arcs := _arcs(points)
	var marks := _marks(plan, arcs[-1] if not arcs.is_empty() else 0.0, depth_m)
	var out_points := PackedVector2Array()
	var out_widths := PackedFloat32Array()
	var out_ground := PackedFloat32Array()
	var out_arcs := PackedFloat32Array()
	var lip := PackedByteArray()
	var m := 0
	for i in points.size():
		# Marks up to this point: a plunge point within MERGE_M of it (a lip only when it
		# coincides: a lip stays exactly where the plan put it) merges into the point, any other
		# is inserted before it.
		var widen := 1.0
		var is_lip := false
		while m < marks.size() and float(marks[m].arc) <= arcs[i] + _merge_of(marks[m]):
			var s: float = marks[m].arc
			if absf(s - arcs[i]) <= _merge_of(marks[m]):
				widen *= float(marks[m].widen)
				is_lip = is_lip or bool(marks[m].lip)
			else:
				var p := _point_at(points, arcs, s)
				out_points.append(p)
				out_widths.append(_width_at(widths, arcs, s) * float(marks[m].widen))
				out_ground.append(ground_of.call(p))
				out_arcs.append(s)
				lip.append(1 if marks[m].lip else 0)
			m += 1
		out_points.append(points[i])
		out_widths.append(widths[i] * widen)
		out_ground.append(ground[i])
		out_arcs.append(arcs[i])
		lip.append(1 if is_lip else 0)
	var free := _free_points(out_arcs, plan.get("zones", PackedVector2Array()))
	return _subdivided(out_points, out_widths, out_ground, out_arcs, lip, free, ground_of)


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
	var profile := fine_profile(_truncated(course, length), step, ground_of)
	var arc: PackedFloat32Array = profile.arc
	var ground: PackedFloat32Array = profile.ground
	var steepest := 0.0
	for k in arc.size() - 1:
		steepest = maxf(steepest, _slope(arc, ground, k))
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


## The face samples of every fall of `doc`: the samples within the channel's half-width of
## the lower course, from the lip to the face's foot (where the centreline ground first
## reaches the lower level, or the search length), ascending and unique. For the dressing
## and the flow bake.
static func footprint(doc: MapDocument) -> PackedInt32Array:
	var found := {}
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	var ground_of := func(p: Vector2) -> float: return WaterGeometry.ground_at(doc, p)
	for fall in falls(doc):
		var lower: WaterBody = doc.water_bodies[fall.lower_index]
		var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
		var arcs := _arcs(course)
		var half: float = fall.half_width
		var search := face_search(fall.top - fall.bottom, half)
		var profile := fine_profile(_truncated(course, search), step, ground_of)
		var foot := search
		for k in profile.arc.size():
			if profile.ground[k] <= fall.bottom:
				foot = profile.arc[k]
				break
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
					found[doc.sample_index(x, z)] = true
	var out := PackedInt32Array()
	for i: int in found:
		out.append(i)
	out.sort()
	return out


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


## The fall per metre of step `k` of a fine profile (positive where the ground falls).
static func _slope(arc: PackedFloat32Array, ground: PackedFloat32Array, k: int) -> float:
	return (ground[k] - ground[k + 1]) / maxf(arc[k + 1] - arc[k], 1e-6)


## The index the run starting at step `first` grows up to over its shoulder: upstream while
## each step still falls at SHOULDER_FLAT_SLOPE or more and no more steeply than the step
## below it (convex), within SHOULDER_M of `first`.
static func _shoulder(arc: PackedFloat32Array, ground: PackedFloat32Array, first: int) -> int:
	var k := first
	while k > 0 and arc[first] - arc[k - 1] <= SHOULDER_M + 1e-6:
		var above := _slope(arc, ground, k - 1)
		if above < SHOULDER_FLAT_SLOPE or above > _slope(arc, ground, k) + 1e-6:
			break
		k -= 1
	return k


## The index the run ending at point `last` (the first gentle step starts there) grows down to
## over its toe: downstream while each step still falls at SHOULDER_FLAT_SLOPE or more and no
## more steeply than the step above it (concave), within SHOULDER_M of `last`.
static func _toe(arc: PackedFloat32Array, ground: PackedFloat32Array, last: int, n: int) -> int:
	var k := last
	while k < n - 1 and arc[k + 1] - arc[last] <= SHOULDER_M + 1e-6:
		var below := _slope(arc, ground, k)
		if below < SHOULDER_FLAT_SLOPE or below > _slope(arc, ground, k - 1) + 1e-6:
			break
		k += 1
	return k


## The lips of one drop over the fine profile between the arcs `usable`: Vector2(arc, drop)
## per fall, n = clamp(round(total / target), 1, min(floor(length / spacing), floor(total /
## FALL_MIN_DROP_M))) falls of total / n each, lip j where the profile first crosses
## top - j * total / n, lip 0 at the brink; none when the usable part drops less than
## FALL_MIN_DROP_M.
static func _lip_arcs(
	arc: PackedFloat32Array,
	ground: PackedFloat32Array,
	usable: Vector2,
	spacing: float,
	target: float
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var top := _ground_at_arc(arc, ground, usable.x)
	var total := top - _ground_at_arc(arc, ground, usable.y)
	if total < FALL_MIN_DROP_M:
		return out
	var by_spacing := maxi(floori((usable.y - usable.x) / spacing), 1)
	var by_drop := floori(total / FALL_MIN_DROP_M)
	var n := clampi(roundi(total / target), 1, mini(by_spacing, by_drop))
	var drop := total / n
	for j in n:
		var s := usable.x if j == 0 else _first_crossing(arc, ground, usable, top - j * drop)
		out.append(Vector2(s, drop))
	return out


## The ground of a fine profile at arc `s`, linear between its samples.
static func _ground_at_arc(arc: PackedFloat32Array, ground: PackedFloat32Array, s: float) -> float:
	var k := 0
	while k < arc.size() - 2 and arc[k + 1] < s:
		k += 1
	var span := arc[k + 1] - arc[k]
	var t := clampf((s - arc[k]) / span, 0.0, 1.0) if span > 1e-9 else 0.0
	return lerpf(ground[k], ground[k + 1], t)


## The first arc in `usable` where the fine profile falls to `level`, linear between
## samples; usable.y when it never does.
static func _first_crossing(
	arc: PackedFloat32Array, ground: PackedFloat32Array, usable: Vector2, level: float
) -> float:
	var previous_arc := usable.x
	var previous := _ground_at_arc(arc, ground, usable.x)
	for k in arc.size():
		if arc[k] <= usable.x:
			continue
		if arc[k] > usable.y:
			break
		if ground[k] <= level:
			var fall := previous - ground[k]
			var t := clampf((previous - level) / fall, 0.0, 1.0) if fall > 1e-9 else 1.0
			return lerpf(previous_arc, arc[k], t)
		previous_arc = arc[k]
		previous = ground[k]
	return usable.y


## The lip planned at arc `s` slid upstream (never below `floor_arc`, never more than
## SETBACK_REACHES reaches) to the first arc whose cross-line stands clear (see the header);
## `s` itself when it stands clear there or never does within reach.
static func _setback(
	doc: MapDocument,
	points: PackedVector2Array,
	arcs: PackedFloat32Array,
	widths: PackedFloat32Array,
	s: float,
	floor_arc: float
) -> float:
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var reach := _width_at(widths, arcs, s) + WaterGeometry.RIVER_BANK_M
	var lowest := maxf(floor_arc, s - SETBACK_REACHES * reach)
	var at := s
	while at >= lowest - 1e-6:
		if _cross_line_clear(doc, points, arcs, widths, at, step):
			return at
		if at <= lowest + 1e-6:
			break
		at = maxf(at - step, lowest)
	return s


## True when every point of the cross-line at arc `at` (square to the control line, the
## half-width plus the bank either side, every `step`) stands on ground at or above the
## level a reach ending there would take (its ground minus the freeboard).
static func _cross_line_clear(
	doc: MapDocument,
	points: PackedVector2Array,
	arcs: PackedFloat32Array,
	widths: PackedFloat32Array,
	at: float,
	step: float
) -> bool:
	var where := _locate(arcs, at)
	var segment := int(where.x)
	var direction := (points[segment + 1] - points[segment]).normalized()
	if direction == Vector2.ZERO:
		return true
	var p := points[segment].lerp(points[segment + 1], where.y)
	var across := direction.orthogonal()
	var reach := _width_at(widths, arcs, at) + WaterGeometry.RIVER_BANK_M
	var level := WaterGeometry.ground_at(doc, p) - WaterGeometry.FREEBOARD_M
	var count := ceili(reach / maxf(step, 1e-3))
	for k in range(-count, count + 1):
		var w := clampf(k * step, -reach, reach)
		if WaterGeometry.ground_at(doc, p + across * w) < level - 1e-3:
			return false
	return true


## True when map point `p` lies within `half_extent` of the origin on both axes.
static func _on_map(p: Vector2, half_extent: Vector2) -> bool:
	return absf(p.x) < half_extent.x and absf(p.y) < half_extent.y


## The insertion marks of a plan over a line `total` long for water `depth_m` deep, in arc
## order: each lip ({"arc", "lip": true, "widen": 1}), then the carved face's foot
## (WaterCarve.fall_foot() below the lip, the channel's own width: the face is never widened)
## and the plunge point (half the plunge length past the foot, PLUNGE_WIDEN wide), both only
## when the plunge point does not run into the next lip or the end.
static func _marks(plan: Dictionary, total: float, depth_m: float) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var lips: Array = plan.get("lips", [])
	for lip: Dictionary in lips:
		var s: float = lip.arc
		marks.append({"arc": s, "lip": true, "widen": 1.0})
		var limit := total - MERGE_M
		for other: Dictionary in lips:
			if float(other.arc) > s:
				limit = minf(limit, float(other.arc) - 2.0 * MERGE_M)
		var drop := float(lip.drop)
		var foot := s + WaterCarve.fall_foot(drop, depth_m)
		var plunge := foot + plunge_length(drop) * 0.5
		if plunge <= limit:
			marks.append({"arc": foot, "lip": false, "widen": 1.0})
			marks.append({"arc": plunge, "lip": false, "widen": PLUNGE_WIDEN})
	marks.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a.arc) < float(b.arc)
	)
	return marks


## How close to an existing point a mark merges into it: a plunge point within MERGE_M, a
## lip only where it coincides.
static func _merge_of(mark: Dictionary) -> float:
	return 1e-4 if bool(mark.lip) else MERGE_M


## One byte per arc of `arcs`: 1 where it lies in one of `zones` (inclusive, a hair of slack).
static func _free_points(arcs: PackedFloat32Array, zones: PackedVector2Array) -> PackedByteArray:
	var free := PackedByteArray()
	free.resize(arcs.size())
	for i in arcs.size():
		for zone in zones:
			if arcs[i] >= zone.x - 1e-4 and arcs[i] <= zone.y + 1e-4:
				free[i] = 1
	return free


## The shaped line with every segment that starts at a point not `free` and changes ground
## by more than REACH_DROP_M split into pieces that each change by no more than that
## (ground from `ground_of`), as shape_line() returns it.
static func _subdivided(
	points: PackedVector2Array,
	widths: PackedFloat32Array,
	ground: PackedFloat32Array,
	arcs: PackedFloat32Array,
	lip: PackedByteArray,
	free: PackedByteArray,
	ground_of: Callable
) -> Dictionary:
	var out_points := PackedVector2Array()
	var out_widths := PackedFloat32Array()
	var out_ground := PackedFloat32Array()
	var out_free := PackedByteArray()
	var forced := PackedInt32Array()
	for i in points.size():
		if lip[i] != 0:
			forced.append(out_points.size())
		out_points.append(points[i])
		out_widths.append(widths[i])
		out_ground.append(ground[i])
		out_free.append(free[i])
		if i == points.size() - 1 or free[i] != 0:
			continue
		var change := absf(ground[i + 1] - ground[i])
		if change <= WaterGeometry.REACH_DROP_M or arcs[i + 1] - arcs[i] <= MERGE_M:
			continue
		var pieces := _pieces(points[i], points[i + 1], ground[i], ground[i + 1], ground_of)
		for piece: Dictionary in pieces:
			out_points.append(piece.point)
			out_widths.append(lerpf(widths[i], widths[i + 1], float(piece.t)))
			out_ground.append(piece.ground)
			out_free.append(0)
	return {
		"points": out_points,
		"widths": out_widths,
		"ground": out_ground,
		"forced": forced,
		"free": out_free,
	}


## The interior points that split the segment `a`-`b` (ground `ga` to `gb`) into pieces each
## changing ground by at most REACH_DROP_M: {"point", "t", "ground"} each, the fewest equal
## pieces that do (one more while the ground between is too uneven, up to 16).
static func _pieces(a: Vector2, b: Vector2, ga: float, gb: float, ground_of: Callable) -> Array:
	var count := maxi(2, ceili(absf(gb - ga) / WaterGeometry.REACH_DROP_M - 1e-6))
	var pieces := []
	while count <= 16:
		pieces = []
		var previous := ga
		var even := true
		for k in range(1, count):
			var t := float(k) / count
			var p := a.lerp(b, t)
			var g: float = ground_of.call(p)
			if absf(g - previous) > WaterGeometry.REACH_DROP_M + 1e-6:
				even = false
				break
			pieces.append({"point": p, "t": t, "ground": g})
			previous = g
		if even and absf(gb - previous) <= WaterGeometry.REACH_DROP_M + 1e-6:
			break
		count += 1
	return pieces


## Arc length at each point of `points`.
static func _arcs(points: PackedVector2Array) -> PackedFloat32Array:
	var arcs := PackedFloat32Array()
	var total := 0.0
	for i in points.size():
		if i > 0:
			total += points[i - 1].distance_to(points[i])
		arcs.append(total)
	return arcs


## Where arc `s` falls on a line with point arcs `arcs`: Vector2(segment, t along it 0..1).
static func _locate(arcs: PackedFloat32Array, s: float) -> Vector2:
	var k := 0
	while k < arcs.size() - 2 and arcs[k + 1] < s:
		k += 1
	var span := arcs[k + 1] - arcs[k]
	var t := clampf((s - arcs[k]) / span, 0.0, 1.0) if span > 1e-9 else 0.0
	return Vector2(k, t)


## The point of `points` (arcs `arcs`) at arc `s`.
static func _point_at(points: PackedVector2Array, arcs: PackedFloat32Array, s: float) -> Vector2:
	var where := _locate(arcs, s)
	var k := int(where.x)
	return points[k].lerp(points[k + 1], where.y)


## The half-width of `widths` (arcs `arcs`) at arc `s`.
static func _width_at(widths: PackedFloat32Array, arcs: PackedFloat32Array, s: float) -> float:
	var where := _locate(arcs, s)
	var k := int(where.x)
	return lerpf(widths[k], widths[k + 1], where.y)


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
