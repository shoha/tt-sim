class_name VillageBridges
extends RefCounted

## Where a dressed street crosses water, and the bridge a village lays there (villages phase 3,
## topic bridges; docs/systems/villages.md section 12). Pure: the document in, plain crossings out.
##
## The model. A street is a polyline (a row Wall). Walked every STEP_M along its arc, its samples
## are wet or dry (`WaterGeometry.is_wet_at`); wet samples separated by a dry gap under JOIN_GAP_M
## join one run (a sandbar mid-stream), and a run is a crossing only when it holds at least
## MIN_WET_M of wet street and has dry street on both sides: a street that touches a puddle, or
## that ends in a pond, gets nothing. Each run gets ONE crossing, planned by the Bridge tool's own
## placement (`CrossingPlacement.place`) along the street's chord from the last dry sample before
## the water to the first after it, so the deck lines up with the street and its anchors are
## snapped to the real banks exactly as a drawn bridge's are.
##
## The kind follows the character (`kinds_for`): planks for a farming hamlet and a harbour town,
## a stone arch for a market town and a hill fort, and a ford for a poor street (wealth under
## POOR_WEALTH) where the water is wadeable. Each kind falls back to the next when the placement
## refuses it (a ford over deep water becomes the kit's bridge, an arch that will not stand becomes
## planks). The width is the painted road's (`StreetProfile`), held to the kind's
## range. A run already crossed by a crossing the village did not lay (`own` ids) is left to it.
##
## SettlementEditor lays the plan through `CrossingEditor.swap` in the Dress's own history group
## and keeps the ids in `Settlement.bridges`, so Clear, Undo and a re-dress take back exactly them.

## Street samples are taken this far apart along its arc (metres).
const STEP_M := 0.25
## Wet samples across a dry gap shorter than this are one run (CrossingPlacement.MIN_ISLAND_M).
const JOIN_GAP_M := 0.8
## A run with less wet street than this is a puddle, not a crossing.
const MIN_WET_M := 1.0
## Wealth under this makes a poor street: a ford first.
const POOR_WEALTH := 0.25
## A crossing the village did not lay covers a run when it meets the run's chord or passes within
## this of the run's middle (beyond its half width).
const COVERED_M := 1.0
## Two runs whose crossings would stand closer than this (anchor to anchor) make one bridge.
const SAME_M := 1.0
## Why a run got no bridge, besides CrossingPlacement's reasons.
const REFUSED_FULL := &"full"


## The wet runs of polyline `points` (map XZ) under `is_wet` (a Callable(Vector2) -> bool): each
## {"from": the last dry sample before the water, "to": the first dry sample after it, "middle":
## the middle wet sample, "wet_m": metres of wet street}, in order along the street. Runs joined
## over dry gaps under `join_gap`; runs with less than `min_wet` of wet street, or that reach either
## end of the street, are left out. Pure.
static func wet_runs(
	points: PackedVector2Array,
	is_wet: Callable,
	step: float = STEP_M,
	min_wet: float = MIN_WET_M,
	join_gap: float = JOIN_GAP_M
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var samples := SettlementGround.resample(points, step)
	if samples.size() < 3:
		return out
	var wet: Array[bool] = []
	var arc := PackedFloat32Array()
	var travelled := 0.0
	for i in samples.size():
		if i > 0:
			travelled += samples[i - 1].distance_to(samples[i])
		arc.append(travelled)
		wet.append(bool(is_wet.call(samples[i])))
	# Index pairs [first wet, last wet] of each raw run, then joined over short dry gaps.
	var runs: Array[Vector2i] = []
	var i := 0
	while i < samples.size():
		if not wet[i]:
			i += 1
			continue
		var first := i
		while i + 1 < samples.size() and wet[i + 1]:
			i += 1
		if not runs.is_empty() and arc[first] - arc[runs[-1].y] < join_gap:
			runs[runs.size() - 1] = Vector2i(runs[-1].x, i)
		else:
			runs.append(Vector2i(first, i))
		i += 1
	for run in runs:
		if run.x == 0 or run.y == samples.size() - 1:
			continue
		var wet_m := 0.0
		for k in range(run.x, run.y + 1):
			if wet[k]:
				var before := arc[k] - arc[k - 1]
				var after := arc[k + 1] - arc[k]
				wet_m += (before + after) * 0.5
		if wet_m < min_wet:
			continue
		var middle := run.x
		var half := (arc[run.x] + arc[run.y]) * 0.5
		while middle < run.y and arc[middle] < half:
			middle += 1
		out.append(
			{
				"from": samples[run.x - 1],
				"to": samples[run.y + 1],
				"middle": samples[middle],
				"wet_m": wet_m,
			}
		)
	return out


## The crossing kinds a village of character `kit` and `wealth` tries, best first.
static func kinds_for(kit: String, wealth: float) -> Array[Crossing.Kind]:
	var main: Crossing.Kind = Crossing.Kind.PLANK
	# A town's road crosses on a built span (a modern town's too: the arch is the only one).
	if kit == "market_town" or kit == "hill_fort_village" or kit == "modern_town":
		main = Crossing.Kind.ARCH
	var out: Array[Crossing.Kind] = []
	if wealth < POOR_WEALTH:
		out.append(Crossing.Kind.FORD)
	out.append(main)
	if main != Crossing.Kind.PLANK:
		out.append(Crossing.Kind.PLANK)
	return out


## The width (metres) of a `kind` crossing on a street of species `preset` (a lane street by
## default) with setback `setback_m`: the painted road's full width (StreetProfile) held to the
## kind's range (a ford's width runs along the river, as the road's).
static func width_for(kind: Crossing.Kind, setback_m: float, preset: int = 0) -> float:
	var road := 2.0 * SettlementGround.road_half_width(setback_m, preset)
	return clampf(road, Crossing.MIN_WIDTH_M[kind], Crossing.MAX_WIDTH_M[kind])


## The bridges settlement `settlement` lays over street `wall` on `doc`, `own` being the ids of the
## crossings it laid before (they never cover a run): {"crossings": Array[Crossing] (id 0, in street
## order), "runs": wet runs found, "crossed": runs left to a crossing already there, "refused":
## Array[StringName], one reason per run that got no bridge}. Pure.
static func plan(
	doc: MapDocument, settlement: Settlement, wall: Wall, own: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var result := {
		"crossings": [] as Array[Crossing],
		"runs": 0,
		"crossed": 0,
		"refused": [] as Array[StringName],
	}
	if wall == null or not wall.is_row() or doc.water_bodies.is_empty():
		return result
	if doc.heights.size() != doc.sample_count():
		return result
	var box := Rect2(wall.points[0], Vector2.ZERO)
	for p in wall.points:
		box = box.expand(p)
	var courses := WaterGeometry.river_courses(doc, box.grow(1.0))
	var is_wet := func(p: Vector2) -> bool: return WaterGeometry.is_wet_at(doc, p, -1, courses)
	var runs := wet_runs(wall.points, is_wet)
	result["runs"] = runs.size()
	var laid: Array[Crossing] = result["crossings"]
	for run in runs:
		if covered(doc, run, own):
			result["crossed"] += 1
			continue
		var made: Variant = _bridge(doc, settlement, wall, run)
		if made is StringName:
			(result["refused"] as Array[StringName]).append(made)
			continue
		var crossing: Crossing = made
		var twin := false
		for other in laid:
			if (
				other.start.distance_to(crossing.start) < SAME_M
				and other.end.distance_to(crossing.end) < SAME_M
			):
				twin = true
		if not twin:
			laid.append(crossing)
	return result


## True when a crossing of `doc` the village did not lay (`own`) already crosses `run`.
static func covered(doc: MapDocument, run: Dictionary, own: PackedInt32Array) -> bool:
	var from: Vector2 = run["from"]
	var to: Vector2 = run["to"]
	var middle: Vector2 = run["middle"]
	for crossing in doc.crossings:
		if own.has(crossing.id):
			continue
		if Geometry2D.segment_intersects_segment(crossing.start, crossing.end, from, to) != null:
			return true
		var nearest := Geometry2D.get_closest_point_to_segment(
			middle, crossing.start, crossing.end
		)
		if nearest.distance_to(middle) <= crossing.width_m * 0.5 + COVERED_M:
			return true
	return false


## The words of a toast for the runs of a plan that got no bridge, or "" when every run got one.
static func refusal_text(refused: Array[StringName]) -> String:
	if refused.is_empty():
		return ""
	var reason: StringName = refused[0]
	match reason:
		REFUSED_FULL:
			return "No bridge where the street meets water: the map holds as many crossings as it can"
		CrossingPlacement.REFUSED_LONG:
			return "No bridge where the street meets water: the crossing is too long to span"
		CrossingPlacement.REFUSED_FALL:
			return "No bridge where the street meets water: it is too close to a waterfall"
		CrossingPlacement.REFUSED_NO_BANK:
			return "No bridge where the street meets water: there is no dry bank to stand on"
	return "No bridge where the street meets water there"


## The crossing `run` gets, trying the village's kinds in turn, or the last refusal (StringName).
static func _bridge(
	doc: MapDocument, settlement: Settlement, wall: Wall, run: Dictionary
) -> Variant:
	var from: Vector2 = run["from"]
	var to: Vector2 = run["to"]
	var style := CrossingPlacement.style_at(doc, run["middle"])
	var refusal: StringName = CrossingPlacement.REFUSED_NO_WATER
	for kind in kinds_for(settlement.kit, settlement.wealth):
		var placed := CrossingPlacement.place(
			doc, from, to, kind, width_for(kind, wall.height_m, wall.preset), style
		)
		if placed.crossing != null:
			return placed.crossing
		refusal = placed.refusal
	return refusal
