class_name WaterPondFit
extends RefCounted

## The pond half of the water conditioner (card painter-water-pond; WaterEdit.plan_river and
## WaterConditioner are the river half). A pond is dug after the streams around it as often as
## before them, so the stream ends that stand beside it are met when the pond is painted, once, on
## the authoring peer, and what is decided is stored in the water bodies like any other stroke.
## Pure and static; WaterEditor.compute() ("pond") calls it, loaded by path (naming it there would
## join the start-up script graph, test_boot_graph).
##
## Three rules, each bounded and none able to make a map worse than as dug:
##  1. fit_level(): a pond never rises. When a stream's end stands beside it LEVEL_BAND_M or less
##     below it (the stream would have to climb into the pond), the pond is dug that much lower, to
##     the end's level, so the two join. A larger gap is left alone and flagged.
##  2. join_ends(): a stream end within WaterPorts.SEARCH_M of the pond's edge that WaterPorts says
##     can meet it at a riffle (a tail at or above the pond by less than a fall: join or inflow; a
##     head at or below it: an outlet) is extended into the pond: its end reach gains one point,
##     inside the pond (WaterPorts' snap, at most SNAP_PER_HALF_WIDTH half-widths plus the join
##     inset, 3 m at the widest), at the reach's own level, and its carve is cut through the bank.
##     The stream's other points, its levels and the pond's outline never move.
##  3. Anything else near the pond is only said (WaterHints): a head above the pond cannot be fed
##     from it (water does not climb): "perched_head"; an end above it by a fall or more, or too far
##     to snap: "end_near_water_below". Nothing is changed, as the river tool's flags.
## Off with WaterEdit.conditioning_enabled (the editor then does not call this), and idempotent:
## once an end is inside the pond's water it has nothing to decide.

## The most a pond is dug below the level its rim gives it to meet a stream end (metres).
const LEVEL_BAND_M := 0.6


## The level pond `pond` (already in `doc.water_bodies` at its rim level) is dug at: its own, or
## lower by at most LEVEL_BAND_M to meet the lowest stream tail standing beside it below it.
## `report` ("level_moved") is filled.
static func fit_level(doc: MapDocument, pond: WaterBody, report: Dictionary) -> float:
	var level := pond.level_m
	var lowest := level
	for end: Dictionary in open_ends(doc):
		if bool(end.head):
			continue
		var decision := _decide(doc, end)
		if decision.other_body != pond.id or decision.action != &"flag":
			continue
		if decision.kind == &"end_below_water" and float(decision.gap) <= LEVEL_BAND_M:
			lowest = minf(lowest, float(end.level))
	report["level_moved"] = level - lowest
	return lowest


## The stream ends beside pond `pond` (in `doc.water_bodies` at its final level, its basin already
## carved into `doc.heights`) joined or said (rules 2 and 3 of the header): {"goals" (the carve
## of the extended strokes, merged, WaterCarve goals), "hints" (WaterHints records), "joined" (ends
## extended), "moved" (the longest extension, metres)}. `doc` takes the extended bodies (copies;
## the stored ones are never touched) and the carve, so that the caller reads the result from it
## (WaterEditor.compute() does, on its snapshot).
static func join_ends(doc: MapDocument, pond: WaterBody) -> Dictionary:
	var out := {
		"goals": {"rect": Rect2i(), "goals": PackedFloat32Array()},
		"hints": [],
		"joined": 0,
		"moved": 0.0,
	}
	var hints_script: GDScript = load(WaterEdit.HINTS_PATH)
	var kept_bodies := doc.water_bodies.duplicate()
	var kept_heights := doc.heights.duplicate()
	var events_before := {}
	for end: Dictionary in open_ends(doc):
		var decision := _decide(doc, end)
		if decision.other_body != pond.id:
			continue
		var action: StringName = decision.action
		if action == &"none":
			continue
		if events_before.is_empty():
			events_before = event_counts(doc)
		var tail := not bool(end.head)
		if action == &"flag":
			var said: Array = hints_script.plan_hints(
				PackedVector2Array(), {}, {} if tail else decision, decision if tail else {}
			)
			out.hints.append_array(said)
			continue
		var riffle: bool = [&"join", &"inflow", &"outlet"].has(action)
		riffle = riffle and absf(float(decision.gap)) < WaterFalls.FALL_MIN_DROP_M
		if not riffle:
			var fixes: Array[StringName] = [&"extend_to_water", &"carve_fall", &"keep"]
			out.hints.append(
				hints_script.make(&"end_near_water_below", end.at, fixes, {"gap_m": float(decision.gap)})
			)
			continue
		var chain := _connector(doc, end, decision.target, pond)
		if chain.is_empty():
			continue
		var goals := WaterCarve.river_goals(doc, chain, doc.heights)
		lower(doc, goals)
		out.goals = merge_goals(out.goals, goals)
		out.joined += 1
		out.moved = maxf(float(out.moved), float(decision.displacement))
	if int(out.joined) > 0 and _worse(event_counts(doc), events_before):
		# The joins made the field worse (a bank that no longer holds the water, ...): all of
		# this pond's joins are dropped, as the river tool keeps a plan as drawn that it cannot
		# improve. The ends are said instead.
		var bodies: Array[WaterBody] = []
		bodies.assign(kept_bodies)
		doc.water_bodies = bodies
		doc.heights = kept_heights
		out.goals = {"rect": Rect2i(), "goals": PackedFloat32Array()}
		out.joined = 0
		out.moved = 0.0
		out["undone"] = true
	return out


## How many field events of each kind an author should decide (film_run, bridged_run,
## end_near_water) `doc`'s water raises: {kind: count}, one WaterField build.
static func event_counts(doc: MapDocument) -> Dictionary:
	var counts := {&"film_run": 0, &"bridged_run": 0, &"end_near_water": 0}
	for event in WaterField.build(doc).events:
		if counts.has(event.kind):
			counts[event.kind] += 1
	return counts


## True when any kind of `after` (event_counts()) is higher than in `before`.
static func _worse(after: Dictionary, before: Dictionary) -> bool:
	for kind in before:
		if int(after[kind]) > int(before[kind]):
			return true
	return false


## The open ends of `doc`'s strokes (each stroke's first and last point; RiverProfile.strokes):
## [{"head", "at", "level", "hw", "id" (the end reach's), "own" (the stroke's ids)}].
static func open_ends(doc: MapDocument) -> Array[Dictionary]:
	var ends: Array[Dictionary] = []
	for chain: Array in RiverProfile.strokes(doc.water_bodies):
		var own := PackedInt32Array()
		for reach: WaterBody in chain:
			own.append(reach.id)
		var first: WaterBody = chain[0]
		var last: WaterBody = chain[-1]
		ends.append(_end(first, true, own))
		ends.append(_end(last, false, own))
	return ends


## `a` and `b` (WaterCarve goals) as one: the union rectangle, the lower goal where both reach.
static func merge_goals(a: Dictionary, b: Dictionary) -> Dictionary:
	var ra: Rect2i = a.rect
	var rb: Rect2i = b.rect
	if not ra.has_area():
		return b
	if not rb.has_area():
		return a
	var rect := ra.merge(rb)
	var merged := PackedFloat32Array()
	merged.resize(rect.size.x * rect.size.y)
	merged.fill(INF)
	for part: Dictionary in [a, b]:
		var r: Rect2i = part.rect
		var values: PackedFloat32Array = part.goals
		for j in r.size.y:
			for i in r.size.x:
				var at := (
					(r.position.y - rect.position.y + j) * rect.size.x + r.position.x - rect.position.x + i
				)
				merged[at] = minf(merged[at], values[j * r.size.x + i])
	return {"rect": rect, "goals": merged}


## `doc`'s heights lowered to `goals` as WaterEditor.lower() does (a copy kept here so this
## module does not name the scene script).
static func lower(doc: MapDocument, goals: Dictionary) -> void:
	var rect: Rect2i = goals.get("rect", Rect2i())
	var values: PackedFloat32Array = goals.get("goals", PackedFloat32Array())
	if not rect.has_area() or values.size() != rect.size.x * rect.size.y:
		return
	var heights := doc.heights
	var width := doc.samples_x()
	var limit := MapDocument.MAX_ABS_HEIGHT_M
	for j in rect.size.y:
		var z := rect.position.y + j
		if z < 0 or z >= doc.samples_z():
			continue
		for i in rect.size.x:
			var x := rect.position.x + i
			if x < 0 or x >= width:
				continue
			var goal := values[j * rect.size.x + i]
			var at := z * width + x
			if is_inf(goal) or goal >= heights[at]:
				continue
			heights[at] = minf(heights[at], maxf(goal, -limit))
	doc.heights = heights


## The stroke of `end` with one reach added to it in `doc.water_bodies`: a straight connector from
## the end to `target` (inside `pond`), starting at the end's own point so the two chain as one
## stroke (RiverProfile.strokes). Its level is the pond's (the connector is where the stream drops
## into it), or the head's own when a head stands below the pond. The stroke's reaches in order;
## empty, with `doc` untouched, when the document has no room for another reach. The stored
## bodies are never changed.
static func _connector(
	doc: MapDocument, end: Dictionary, target: Vector2, pond: WaterBody
) -> Array[WaterBody]:
	var chain: Array[WaterBody] = []
	var rivers := 0
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	var id := doc.next_water_id()
	if doc.water_bodies.size() >= MapDocument.MAX_WATER_BODIES or rivers >= MapDocument.MAX_RIVERS:
		return chain
	if id <= 0 or id > WaterBody.MAX_ID:
		return chain
	var stream := doc.water_body(int(end.id))
	var hw := float(end.hw)
	var level := float(end.level) if end.head else minf(float(end.level), pond.level_m)
	var points := PackedVector2Array([target, end.at] if end.head else [end.at, target])
	var connector := WaterBody.river(
		id, points, PackedFloat32Array([hw, hw]), stream.depth, level, stream.speed
	)
	doc.water_bodies = WaterEdit.with_bodies(doc, [connector] as Array[WaterBody])
	var own: PackedInt32Array = end.own
	for own_id in own:
		chain.append(doc.water_body(own_id))
	if end.head:
		chain.push_front(connector)
	else:
		chain.append(connector)
	return chain


static func _end(reach: WaterBody, head: bool, own: PackedInt32Array) -> Dictionary:
	return {
		"head": head,
		"at": reach.points[0] if head else reach.points[-1],
		"level": reach.level_m,
		"hw": reach.half_widths[0] if head else reach.half_widths[-1],
		"id": reach.id,
		"own": own,
	}


static func _decide(doc: MapDocument, end: Dictionary) -> Dictionary:
	return WaterPorts.end_decision(doc, end.at, end.level, end.hw, end.head, end.own)
