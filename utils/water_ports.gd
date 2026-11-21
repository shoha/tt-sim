class_name WaterPorts
extends RefCounted

## The ports and dig half of the water-conditioning spike (WaterConditioner has the levels,
## WaterCourseFit the course), pure and static, reading a MapDocument and never changing it unless
## a function says "apply":
##  - end_decision(): the endpoint snap or flag table of 04-input-conditioning 5.1 for one stroke
##    end near other water (a typed transition: join, inflow, fall into, or a flagged hint with the
##    fixes an author could take);
##  - graph(): the river and pond tree of a document (a reach drains into the next reach of its
##    stroke, the last into the water it ends in, a pond into the stroke that starts in it);
##  - condition_doc(): WaterConditioner.solve_tree() over that graph, the plan-time level solver
##    applied to a stored document (a probe: nothing calls it from a tool);
##  - audit(): the hydrology invariants of a document as counts (rises, tiny steps, outlets);
##  - refit_stroke(): the dig-aware re-fit of one stroke's reach levels under the ground as it is
##    now (what the field would call undermined is lowered until the banks hold it again).

## A stroke end within this of other water is looked at (WaterField.END_NEAR_M), or within its
## own snap reach when that is longer.
const SEARCH_M := WaterField.END_NEAR_M
## The snap reach of an end (snap_reach()): this many half-widths of its own stroke, at least
## MIN_SNAP_M. The search follows it (card painter-water-paths: under a constant 2 m search the
## widest strokes reached no further than a waist stream). 2 half-widths (the brush's whole
## width) was tried there: it joined f_end_short's 2.0 m gap, and over the fuzz maps the field
## events rose from 110 to 122 (off 103) and the pond fuzz's perched samples from 47 to 54, each
## extra join being a junction the field reports; kept at 1.5 until junctions are one bed.
## Card painter-water-junctions (junctions are one bed: a join no longer raises film or bridged
## runs) retried 2.
const SNAP_PER_HALF_WIDTH := 2.0
const MIN_SNAP_M := 1.0
## Hold slack of the dig re-fit: the banks must stand within this of the level.
const HOLD_M := WaterMeshBuilder.BANK_HOLD_M


## What to do with the end `at` of a stroke (half-width `half_width`, water level `level` there)
## near other water of `doc`; `head` is true for the stroke's upstream end. Bodies in `own` (ids)
## are the stroke's own and ignored. Returns {"action", "target" (the snapped end, `at` if none),
## "displacement", "other_body" (0 none), "gap" (the other water's level minus the end's),
## "distance" (to its edge), "kind" (the hint kind), "fixes" (what the author may do)}. Actions:
## &"none" (nothing near, or already inside water), &"join" (levels within the dead band: snap and
## join), &"inflow" (the other water is lower by a riffle: snap), &"fall_into" (lower by a fall:
## snap and plan the fall into it), &"outlet" (a head at a pond that can feed it: snap, level =
## the pond's), &"flag" (never changed: uphill, perched head, or too far to snap).
static func end_decision(
	doc: MapDocument,
	at: Vector2,
	level: float,
	half_width: float,
	head: bool,
	own: PackedInt32Array
) -> Dictionary:
	var out := {
		"action": &"none",
		"target": at,
		"displacement": 0.0,
		"other_body": 0,
		"gap": 0.0,
		"distance": INF,
		"kind": &"",
		"fixes": [],
	}
	var reach := snap_reach(half_width)
	var near := _nearest_water(doc, at, own, maxf(SEARCH_M, reach))
	# An end already inside other water (join_line put it there) has nothing to decide.
	if near.is_empty() or float(near.distance) <= 0.0 or _pond_at(doc, at) in _others(doc, own):
		return out
	var other: WaterBody = doc.water_body(near.id)
	var gap := other.level_m - level
	out.other_body = near.id
	out.gap = gap
	out.distance = near.distance
	var inside: Vector2 = near.point + (near.point - at).normalized() * WaterEdit.JOIN_INSET_M
	var in_reach: bool = near.distance <= reach
	if absf(gap) < WaterField.LEVEL_GAP_M:
		if in_reach:
			_snap(out, &"join", inside, at)
		return out
	if head:
		if gap >= -WaterGeometry.FREEBOARD_M and in_reach:
			_snap(out, &"outlet", inside, at)
		elif gap < 0.0:
			out.action = &"flag"
			out.kind = &"head_above_water"
			out.fixes = [&"carve_fall", &"move_head", &"keep_spring"]
		return out
	if gap > 0.0:
		out.action = &"flag"
		out.kind = &"end_below_water"
		out.fixes = [&"raise_end", &"make_outlet", &"keep"]
	elif in_reach:
		_snap(out, &"fall_into" if -gap >= WaterFalls.FALL_MIN_DROP_M else &"inflow", inside, at)
	else:
		out.action = &"flag"
		out.kind = &"end_near_water_below"
		out.fixes = [&"extend_to_water", &"carve_fall", &"keep"]
	return out


## How far the end of a stroke `half_width` wide reaches for other water to join: its own width
## (SNAP_PER_HALF_WIDTH half-widths), at least MIN_SNAP_M.
static func snap_reach(half_width: float) -> float:
	return maxf(SNAP_PER_HALF_WIDTH * half_width, MIN_SNAP_M)


## True when `at` lies in water of `doc` or within `reach` metres of its edge.
static func water_within(doc: MapDocument, at: Vector2, reach: float) -> bool:
	if WaterGeometry.is_wet_at(doc, at):
		return true
	return not _nearest_water(doc, at, PackedInt32Array(), reach).is_empty()


## The river and pond tree of `doc` for WaterConditioner.solve_tree(): {"parent" (per body in
## doc.water_bodies order, -1 an outlet), "pinned" (ponds), "weights" (reach length, a pond 1),
## "levels", "strokes" (Array of Array of body indices in order), "multi_outlet" (ponds with more
## than one stroke starting in them), "cycles" (links dropped because they closed a loop)}.
static func graph(doc: MapDocument) -> Dictionary:
	var bodies := doc.water_bodies
	var n := bodies.size()
	var index := {}
	for i in n:
		index[bodies[i].id] = i
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var pinned := PackedByteArray()
	pinned.resize(n)
	var weights := PackedFloat64Array()
	weights.resize(n)
	var levels := PackedFloat64Array()
	levels.resize(n)
	for i in n:
		levels[i] = bodies[i].level_m
		pinned[i] = 0 if bodies[i].is_river() else 1
		weights[i] = 1.0
		if bodies[i].is_river():
			weights[i] = _length(bodies[i].points)
	var strokes := []
	var multi := {}
	var cycles := 0
	var feeds := {}
	for chain in RiverProfile.strokes(bodies):
		var ids := PackedInt32Array()
		for reach: WaterBody in chain:
			ids.append(index[reach.id])
		strokes.append(ids)
		for k in ids.size() - 1:
			parent[ids[k]] = ids[k + 1]
		var first: WaterBody = chain[0]
		var last: WaterBody = chain[-1]
		var pond := _pond_at(doc, first.points[0])
		if pond > 0 and index.has(pond):
			feeds[pond] = int(feeds.get(pond, 0)) + 1
			if feeds[pond] == 1 and parent[index[pond]] < 0:
				parent[index[pond]] = ids[0]
			elif feeds[pond] > 1:
				multi[pond] = true
		var into := _body_at(doc, last.points[-1], chain, index)
		if into >= 0 and _would_loop(parent, ids[-1], into) == false:
			parent[ids[-1]] = into
		elif into >= 0:
			cycles += 1
	return {
		"parent": parent,
		"pinned": pinned,
		"weights": weights,
		"levels": levels,
		"strokes": strokes,
		"multi_outlet": multi.keys(),
		"cycles": cycles,
	}


## solve_tree() over graph(doc): water is only ever lowered (never raised over its own banks)
## except a reach that would run uphill into a pond, which takes the pond's level.
## {...solve_tree(), "graph"}.
static func condition_doc(doc: MapDocument, opts: Dictionary = {}) -> Dictionary:
	var g := graph(doc)
	var fit := WaterConditioner.solve_tree(g.levels, g.parent, g.pinned, PackedFloat64Array(), opts)
	fit["graph"] = g
	return fit


## Sets the river levels of `doc` to `levels` (one per body, solve_tree()'s result).
static func apply_levels(doc: MapDocument, levels: PackedFloat64Array) -> void:
	for i in doc.water_bodies.size():
		doc.water_bodies[i].level_m = levels[i]


## The hydrology invariants of `doc`'s water as counts: {"rises" (steps along a stroke where the
## water climbs more than 1 mm), "rise_m" (their total), "tiny_steps" (drops under the dead band,
## not zero), "falls", "multi_outlet" (ponds fed by more than one stroke starting in them),
## "climb_to_outlet" (junction links where the upstream level is below the downstream one),
## "junctions" (links into other water)}.
static func audit(doc: MapDocument) -> Dictionary:
	var out := {
		"rises": 0,
		"rise_m": 0.0,
		"tiny_steps": 0,
		"falls": 0,
		"multi_outlet": 0,
		"climb_to_outlet": 0,
		"junctions": 0,
	}
	var g := graph(doc)
	out.multi_outlet = g.multi_outlet.size()
	var bodies := doc.water_bodies
	for i in bodies.size():
		var p: int = g.parent[i]
		if p < 0:
			continue
		var drop := bodies[i].level_m - bodies[p].level_m
		if bodies[i].is_river() and bodies[p].is_river() and _same_stroke(g.strokes, i, p):
			if drop < -0.001:
				out.rises += 1
				out.rise_m += -drop
			elif drop >= WaterFalls.FALL_MIN_DROP_M:
				out.falls += 1
			elif drop > 0.001 and drop < WaterConditioner.DEAD_BAND_M - 0.001:
				out.tiny_steps += 1
		else:
			out.junctions += 1
			if drop < -0.001:
				out.climb_to_outlet += 1
	return out


## The dig-aware re-fit of one stroke `chain` (river reaches in order) of `doc` as the ground is
## now: each reach's cap is the highest level its stations' banks (and bed) still hold, the
## fit keeps levels non-increasing under those caps. Returns {"levels" per reach, "lost" (stations
## the water cannot hold at the stored levels), "held" (after: 0 when the levels fixed it),
## "lowered" (largest drop in a level)}. Nothing in `doc` changes.
static func refit_stroke(doc: MapDocument, chain: Array[WaterBody]) -> Dictionary:
	var profile := RiverProfile.for_doc(doc, chain)
	var stations := profile.stations(doc, WaterFieldStroke.STATION_STEP)
	var count := chain.size()
	var caps := PackedFloat64Array()
	caps.resize(count)
	caps.fill(INF)
	var lost := 0
	var open_start := profile.taper.x == 0 and profile.run_off.x == 0
	var open_end := profile.taper.y == 0 and profile.run_off.y == 0
	var tail := WaterCarve.pool_tail(profile.depth)
	var centres: PackedVector2Array = stations.centre
	for i in centres.size():
		var s: float = stations.arc[i]
		var near_open := (open_start and s < tail) or (open_end and profile.total - s < tail)
		if near_open or not profile.fall_at(s).is_empty():
			continue
		var before := centres[maxi(i - 1, 0)]
		var after := centres[mini(i + 1, centres.size() - 1)]
		var side := (after - before).normalized().orthogonal()
		var reach: float = stations.half_width[i] + WaterMeshBuilder.BANK_MARGIN_M
		var level: float = stations.level[i]
		var offset: float = level - float(stations.bed[i])
		var hold := minf(
			WaterGeometry.ground_at(doc, centres[i] + side * reach),
			WaterGeometry.ground_at(doc, centres[i] - side * reach)
		)
		var cap := minf(
			hold + HOLD_M, WaterGeometry.ground_at(doc, centres[i]) + offset + WaterMeshBuilder.HOLD_SLACK_M
		)
		lost += 1 if cap < level - 1e-4 else 0
		var k := 0
		while k < count - 1 and s > profile.bounds[k]:
			k += 1
		caps[k] = minf(caps[k], cap)
	var lengths := PackedFloat64Array()
	var targets := PackedFloat64Array()
	for k in count:
		lengths.append(_length(chain[k].points))
		targets.append(chain[k].level_m)
	var fit := WaterConditioner.fit_levels(lengths, targets, caps, PackedByteArray(), {"min_len": 0.0})
	return {"levels": fit.levels, "lost": lost, "lowered": fit.lowered, "fit": fit}


## The ids of the ponds of `doc` that are not in `own`.
static func _others(doc: MapDocument, own: PackedInt32Array) -> Array[int]:
	var ids: Array[int] = []
	for body in doc.water_bodies:
		if not body.is_river() and not own.has(body.id):
			ids.append(body.id)
	return ids


static func _snap(out: Dictionary, action: StringName, target: Vector2, at: Vector2) -> void:
	out.action = action
	out.target = target
	out.displacement = at.distance_to(target)


static func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


static func _same_stroke(strokes: Array, a: int, b: int) -> bool:
	for ids: PackedInt32Array in strokes:
		if ids.has(a) and ids.has(b):
			return true
	return false


## The pond id under map point `p` (0 none).
static func _pond_at(doc: MapDocument, p: Vector2) -> int:
	if doc.pond_mask.size() != doc.sample_count():
		return 0
	var s := doc.world_to_sample(p).round()
	var x := clampi(int(s.x), 0, doc.samples_x() - 1)
	var z := clampi(int(s.y), 0, doc.samples_z() - 1)
	return doc.pond_mask[doc.sample_index(x, z)]


## The index of the body a stroke ending at `p` runs into: the pond under it, else the nearest
## reach of another stroke whose water covers `p`; -1 when none.
static func _body_at(doc: MapDocument, p: Vector2, chain: Array, index: Dictionary) -> int:
	var pond := _pond_at(doc, p)
	if pond > 0 and index.has(pond):
		return index[pond]
	var own := {}
	for reach: WaterBody in chain:
		own[reach.id] = true
	var best := -1
	var best_d := INF
	for body in doc.water_bodies:
		if not body.is_river() or own.has(body.id) or body.points.size() < 2:
			continue
		var near := WaterGeometry.nearest_on_polyline(body.points, p)
		var hw := WaterGeometry.width_at(body.half_widths, int(near.y), near.z) if near.y >= 0 else 0.0
		if near.x <= hw + 0.2 and near.x < best_d:
			best_d = near.x
			best = index[body.id]
	return best


static func _would_loop(parent: PackedInt32Array, from: int, to: int) -> bool:
	var at := to
	var guard := parent.size()
	while at >= 0 and guard > 0:
		if at == from:
			return true
		at = parent[at]
		guard -= 1
	return false


## The nearest other water within `search` metres of `at` (outside `own` ids): {"id", "distance"
## to its edge, "point" (the nearest water point)}, or {}.
static func _nearest_water(
	doc: MapDocument, at: Vector2, own: PackedInt32Array, search: float = SEARCH_M
) -> Dictionary:
	var best := {}
	var best_d := search
	var step := doc.sample_step()
	if doc.pond_mask.size() == doc.sample_count():
		var c := doc.world_to_sample(at).round()
		var reach := int(ceil(search / minf(step.x, step.y)))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := int(c.x) + dx
				var z := int(c.y) + dz
				if x < 0 or z < 0 or x >= doc.samples_x() or z >= doc.samples_z():
					continue
				var id := doc.pond_mask[doc.sample_index(x, z)]
				if id == 0 or own.has(id):
					continue
				var point := doc.sample_to_world(Vector2(x, z))
				var d := point.distance_to(at)
				if d < best_d:
					best_d = d
					best = {"id": id, "distance": d, "point": point}
	for body in doc.water_bodies:
		if not body.is_river() or own.has(body.id) or body.points.size() < 2:
			continue
		var near := WaterGeometry.nearest_on_polyline(body.points, at)
		if near.y < 0.0:
			continue
		var edge := near.x - WaterGeometry.width_at(body.half_widths, int(near.y), near.z)
		if edge < best_d:
			var segment := int(near.y)
			var point := body.points[segment].lerp(body.points[segment + 1], near.z)
			best_d = maxf(edge, 0.0)
			best = {"id": body.id, "distance": maxf(edge, 0.0), "point": point}
	return best
