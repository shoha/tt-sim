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
##     can meet it (a tail at or above the pond: join, inflow, a fall into it; a head at or below
##     it: an outlet) gains a stepped connector (_stepped): two reaches from the end into the pond,
##     the stream's side at the stream's level, the pond's side at the pond's, so the drop is a
##     riffle or, from a fall's height, a fall that WaterCarve and WaterFalls cut from the step as
##     they cut any stroke's. The pond's levels are the pinned node of the river tree
##     (WaterConditioner's pin_last); no level of the stream moves and no outline moves.
##  3. Anything else near the pond is only said (WaterHints): a head above the pond cannot be fed
##     from it (water does not climb): "perched_head"; an end too far to snap, or whose joins were
##     dropped: "end_near_water_below".
## The joins are all-or-nothing per pond and must pay for themselves: the field's events
## (film_run, bridged_run, end_near_water) and perched samples are counted before and after (two
## WaterField builds, on the worker's snapshot) and the joins are dropped unless no kind got worse
## and at least one event was removed. Off with WaterEdit.conditioning_enabled (the editor then
## does not call this); idempotent: once an end is inside the pond's water it has nothing to decide.

## The most a pond is dug below the level its rim gives it to meet a stream end (metres).
const LEVEL_BAND_M := 0.6
## The guard drops joins that remove no event (a join that changes nothing the field reports could
## still change what a later pond finds: measured, 2 of 40 fuzz maps without it) ...
static var strict := true
## ... and joins that add perched samples (wet samples over 0.3 m deep beside dry ground, the steep
## wall a channel cuts through a bank). Switches for the comparison probes.
static var perched_guard := true


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
## of the joined strokes, merged, WaterCarve goals), "hints" (WaterHints records), "joined" (ends
## joined), "moved" (the longest join, metres), "undone" (true when the guard dropped them)}. `doc`
## takes the connectors (new bodies; the stored ones are never touched) and the carve, so that the
## caller reads the result from it (WaterEditor.compute() does, on its snapshot).
static func join_ends(doc: MapDocument, pond: WaterBody) -> Dictionary:
	var out := {
		"goals": {"rect": Rect2i(), "goals": PackedFloat32Array()},
		"hints": [],
		"joined": 0,
		"moved": 0.0,
		"undone": false,
	}
	var hints_script: GDScript = load(WaterEdit.HINTS_PATH)
	var kept_bodies := doc.water_bodies.duplicate()
	var kept_heights := doc.heights.duplicate()
	var before := {}
	var joined_ends: Array[Dictionary] = []
	for end: Dictionary in open_ends(doc):
		var decision := _decide(doc, end)
		if decision.other_body != pond.id or decision.action == &"none":
			continue
		if before.is_empty():
			before = event_counts(doc)
		var tail := not bool(end.head)
		if decision.action == &"flag":
			var said: Array = hints_script.plan_hints(
				PackedVector2Array(), {}, {} if tail else decision, decision if tail else {}
			)
			out.hints.append_array(said)
			continue
		var chain := _stepped(doc, end, decision.target, pond)
		if chain.is_empty():
			continue
		var goals := WaterCarve.river_goals(doc, chain, doc.heights)
		lower(doc, goals)
		out.goals = merge_goals(out.goals, goals)
		out.joined += 1
		out.moved = maxf(float(out.moved), float(decision.displacement))
		joined_ends.append(end)
	if int(out.joined) > 0 and _worse(event_counts(doc), before):
		# The joins made the field worse, or did nothing it reports (a bank that no longer holds
		# the water, a steep channel wall): all of this pond's joins are dropped, as the river tool
		# keeps a plan as drawn that it cannot improve. The ends are said instead.
		var bodies: Array[WaterBody] = []
		bodies.assign(kept_bodies)
		doc.water_bodies = bodies
		doc.heights = kept_heights
		var fixes: Array[StringName] = [&"extend_to_water", &"carve_fall", &"keep"]
		if int(before[&"end_near_water"]) > 0:
			for end: Dictionary in joined_ends:
				out.hints.append(hints_script.make(&"end_near_water_below", end.at, fixes, {}))
		out.goals = {"rect": Rect2i(), "goals": PackedFloat32Array()}
		out.joined = 0
		out.moved = 0.0
		out.undone = true
	return out


## How many field events of each kind an author should decide (film_run, bridged_run,
## end_near_water) `doc`'s water raises, and its perched samples: {kind: count}, one WaterField
## build.
static func event_counts(doc: MapDocument) -> Dictionary:
	var counts := {&"film_run": 0, &"bridged_run": 0, &"end_near_water": 0, &"perched": 0}
	var field := WaterField.build(doc)
	for event in field.events:
		if counts.has(event.kind):
			counts[event.kind] += 1
	counts[&"perched"] = perched_count(field)
	return counts


## Wet samples over 0.3 m deep with a dry neighbour (water standing proud of its shore: the steep
## wall of a channel through a bank, the lip of a fall), the tests' "perched" metric.
static func perched_count(field: WaterField) -> int:
	var count := 0
	var w := field.size.x
	for i in field.depth.size():
		if field.depth[i] <= 0.3:
			continue
		var x := i % w
		for off in [-1, 1, -w, w]:
			var j: int = i + off
			if (off == -1 and x == 0) or (off == 1 and x == w - 1):
				continue
			if j >= 0 and j < field.depth.size() and field.depth[j] <= 0.0:
				count += 1
				break
	return count


## True when the joins must go: any event kind of `after` (event_counts()) is higher than in
## `before`, perched samples are (with `perched_guard`), or (with `strict`) no event was removed.
static func _worse(after: Dictionary, before: Dictionary) -> bool:
	var removed := 0
	var reported := 0
	for kind in before:
		if kind == &"perched":
			if perched_guard and int(after[kind]) > int(before[kind]):
				return true
			continue
		if int(after[kind]) > int(before[kind]):
			return true
		removed += int(before[kind]) - int(after[kind])
		reported += int(before[kind])
	return strict and reported > 0 and removed <= 0


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


## The stroke of `end` with a stepped connector added in `doc.water_bodies`: two reaches meeting at
## the pond's edge (the first point of the line from the end to `target` that lies in the pond), the
## stream's side at the stream's own level, the pond's side at the pond's, so the step between them
## is a riffle or, from a fall's height (WaterFalls.FALL_MIN_DROP_M), the lip of a fall that
## WaterCarve and WaterFalls cut as they cut any stroke's steps. For a fall the lip is the end
## itself
## (the bank the pond's carve eased down starts there; a lip at the edge would leave the stream's
## level floating over the bank). The connector starts (a tail) or ends (a head) at the stream's own
## end point so the two chain. The stroke's reaches in order; empty, with `doc` untouched, when the
## document has no room or the end already lies in the pond.
static func _stepped(
	doc: MapDocument, end: Dictionary, target: Vector2, pond: WaterBody
) -> Array[WaterBody]:
	var chain: Array[WaterBody] = []
	var rivers := 0
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	var first_id := doc.next_water_id()
	if (
		doc.water_bodies.size() + 2 > MapDocument.MAX_WATER_BODIES
		or rivers + 2 > MapDocument.MAX_RIVERS
		or first_id <= 0
		or first_id + 1 > WaterBody.MAX_ID
	):
		return chain
	var stream := doc.water_body(int(end.id))
	var at: Vector2 = end.at
	if _in_pond(doc, at, pond.id):
		return chain
	var outside := at
	var inside := target
	for _step in 12:
		var middle := (outside + inside) * 0.5
		if _in_pond(doc, middle, pond.id):
			inside = middle
		else:
			outside = middle
	var edge := inside
	var stream_level := float(end.level)
	var near_level := minf(stream_level, pond.level_m)
	if end.head:
		near_level = maxf(stream_level, pond.level_m)
	if absf(stream_level - near_level) >= WaterFalls.FALL_MIN_DROP_M or at.distance_to(edge) < 0.2:
		edge = at
	var hw := float(end.hw)
	var widths := PackedFloat32Array([hw, hw])
	var made: Array[WaterBody] = []
	var near_line := PackedVector2Array([edge, target])
	var far_line := PackedVector2Array([at, edge])
	if end.head:
		near_line = PackedVector2Array([target, edge])
		far_line = PackedVector2Array([edge, at])
	if edge != at:
		made.append(
			WaterBody.river(
				first_id, far_line, widths, stream.depth, stream_level, stream.speed
			)
		)
	var near := WaterBody.river(
		first_id + 1, near_line, widths, stream.depth, near_level, stream.speed
	)
	if end.head:
		made.push_front(near)
	else:
		made.append(near)
	doc.water_bodies = WaterEdit.with_bodies(doc, made)
	var own: PackedInt32Array = end.own
	for own_id in own:
		chain.append(doc.water_body(own_id))
	if end.head:
		made.append_array(chain)
		return made
	chain.append_array(made)
	return chain


## True when map point `p` lies on a sample of pond `id`.
static func _in_pond(doc: MapDocument, p: Vector2, id: int) -> bool:
	if doc.pond_mask.size() != doc.sample_count():
		return false
	var s := doc.world_to_sample(p).round()
	var x := clampi(int(s.x), 0, doc.samples_x() - 1)
	var z := clampi(int(s.y), 0, doc.samples_z() - 1)
	return doc.pond_mask[doc.sample_index(x, z)] == id


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
