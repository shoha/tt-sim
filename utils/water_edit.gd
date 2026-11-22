class_name WaterEdit
extends RefCounted

## Edits of a MapDocument's water model (water_bodies, pond_mask) for the carve and the
## Water tool, pure: a river stroke split into flat reaches, pond areas painted and erased on
## the sample grid, rivers cut where water is erased, and whole-model snapshots for history.
## The ground the water carves is WaterCarve's. Summary: docs/systems/water.md (Carving).
##
## Rivers. A stroke's line is resampled every RESAMPLE_M (a drawn line arrives with a point
## per frame; the reaches, the erase and the flow bake cost per point, and the course is
## Chaikin-smoothed anyway), then split into flat reaches by the ground along it
## (WaterGeometry.reach_ranges: no reach spans more than REACH_DROP_M), each a river body at
## its reach's level, consecutive reaches sharing their boundary point. A line that starts
## or ends in existing water joins it (join_line(): a confluence). Waterfalls (P4c,
## WaterFallPlan): a line drawn uphill is reversed so the water runs downhill; where the ground
## along it drops steeply the plan inserts a lip per fall (a forced reach boundary) and a
## widened plunge-pool point below it, and splits any other segment dropping more than
## REACH_DROP_M so no step that is not a fall reaches WaterFalls.FALL_MIN_DROP_M. A stroke
## with no drop run and no such segment plans exactly as before.
##
## Erasing (P4-4). A river the eraser touches goes whole: every reach of its stroke (the
## reaches joined end to end, river_chain()), never a piece of one. A hole cut mid-reach left
## two ends draining into a dry channel (P4-3), and so did one reach of a stroke erased on its
## own (the reach above spilled over its crest into the dry riffle); so do the streams that
## flow into it (their end in its water), which would spill into its dry channel. A pond loses
## the samples under the eraser, is dropped once it has none, and otherwise settles to the
## lowest ground on its new rim (erased_bodies()), so its water never stands against the
## erased part of its basin.

## Spacing of a river's control points (metres).
const RESAMPLE_M := 2.0
## A river joining other water ends this far past that water's edge (join_line()).
const JOIN_INSET_M := 0.6
## The most a conditioned reach is raised to stand at the level of water it crosses
## (_meet_crossed_water()): under WaterGeometry.FREEBOARD_M, so its own banks still hold it.
const JUNCTION_RAISE_M := 0.1
## The conditioner's parts load by path on first use: named as classes here they would join the
## start-up script graph (test_boot_graph).
const COURSE_FIT_PATH := "res://utils/water_course_fit.gd"
const CONDITIONER_PATH := "res://utils/water_conditioner.gd"
const PORTS_PATH := "res://utils/water_ports.gd"
const HINTS_PATH := "res://utils/water_hints.gd"
const REFIT_PATH := "res://utils/water_refit.gd"
const POND_FIT_PATH := "res://utils/water_pond_fit.gd"
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
## How many times a stroke that climbs is cut to its longest descending part (_descending()).
const MAX_DESCENT_TRIES := 4
## The most parts of one gesture over rises that are planned after its first (`report.rest`).
const MAX_PIECES := 8
## With stop_at_rise (the line split at its rises): the deepest cut into the drawn ground a part
## of `report.rest` may ask of the carve and still land (WaterEditor._compute_rest), what one flat
## reach spans. A line that is cut through its rises (cut_through, the rule) has no such parts.
const REST_CUT_M := WaterGeometry.REACH_DROP_M
## A rise deeper than this cut through by a stroke sets `report.cut`: where the carve's banks
## become a cut's (WaterCarve.CUT_FROM_M).
const CUT_SAID_M := WaterCarve.CUT_FROM_M
## An end is not joined to the water beside it when the joined line would cut this much deeper
## through a rise than the line as drawn (plan_river(): a head on a plateau beside a pond at its
## foot would dig a canal through the plateau).
const JOIN_CUT_M := WaterGeometry.REACH_DROP_M
## plan_on_cut applies over a rise higher than this (the conditioner's dead band).
const CUT_PLAN_FROM_M := 0.25
const REACH_DROP := WaterGeometry.REACH_DROP_M

## The conditioning off switch (card painter-water-condition): plan_river() conditions a stroke
## (smooths the course, WaterCourseFit; fits the reach levels, WaterConditioner; joins the ends,
## WaterPorts) unless this is false. On in every build; an A/B capture or a test of the drawn,
## unconditioned plan sets it false (render jobs: the `conditioning` flag).
static var conditioning_enabled: bool = true
## A river drawn over a rise cuts through it (card painter-water-cut, the owner's rule of
## 2026-11-22): the conditioned levels never climb (the running minimum along the line), the carve
## cuts the ground down to them however deep, and the stroke is ONE river along the drawn line.
## On in every build. False brings back the cut limit (cut_limit_m): a plan that would cut deeper
## is blocked, and stop_at_rise says what a blocked plan becomes.
static var cut_through: bool = true
## With cut_through on, falls and reach boundaries are planned on the ground the cut leaves
## (WaterFallPlan.cut_ground; card painter-water-cutband, docs/systems/water_field.md): a rise's
## face is no fall, no riffle crest bar at its foot, no plunge widening. False: as drawn (A/B).
static var plan_on_cut: bool = true
## With cut_through off: the deepest cut into the drawn ground a conditioned plan may ask of the
## carve before it is blocked (WaterConditioner.CUT_LIMIT_M); a test or probe may change it.
static var cut_limit_m: float = 1.5
## With cut_through off, what a blocked stroke that climbs as drawn becomes: true splits it at its
## rises (card painter-water-climb: the longest descending part, the others in `report.rest`,
## _descending()); false stores it as drawn, climbing (the plan before both rules, for an A/B
## table or a test of the field's `climb` event). Off by default: the rule is the cut.
static var stop_at_rise: bool = false
static var _descent_depth: int = 0


## A copy of `doc`'s water model for history: {"bodies": Array[WaterBody] (deep copies),
## "pond_mask": the mask ZSTD-compressed (a mask is mostly zeros), "pond_size": its length}.
static func model_of(doc: MapDocument) -> Dictionary:
	var bodies: Array[WaterBody] = []
	for body in doc.water_bodies:
		bodies.append(body.copy())
	var mask := doc.pond_mask
	var packed := mask.compress(COMPRESSION) if not mask.is_empty() else PackedByteArray()
	return {"bodies": bodies, "pond_mask": packed, "pond_size": mask.size()}


## Puts a model_of() copy into `doc` (new arrays, never the stored ones, so history is not
## aliased).
static func apply_model(doc: MapDocument, model: Dictionary) -> void:
	var bodies: Array[WaterBody] = []
	for body: WaterBody in model.get("bodies", []):
		bodies.append(body.copy())
	doc.water_bodies = bodies
	var size: int = model.get("pond_size", 0)
	var packed: PackedByteArray = model.get("pond_mask", PackedByteArray())
	doc.pond_mask = packed.decompress(size, COMPRESSION) if size > 0 else PackedByteArray()


## Bytes a model_of() copy holds (for the history budget): the compressed mask and the
## rivers' points and widths.
static func model_bytes(model: Dictionary) -> int:
	var total: int = (model.get("pond_mask", PackedByteArray()) as PackedByteArray).size()
	for body: WaterBody in model.get("bodies", []):
		total += 64 + body.points.size() * 12 + (body.beyond.size() + body.beyond_up.size()) * 8
	return total


## `points` (with one half-width per point in `widths`) resampled every `spacing` metres of
## arc length, keeping both ends. [PackedVector2Array, PackedFloat32Array].
static func resample(
	points: PackedVector2Array, widths: PackedFloat32Array, spacing: float = RESAMPLE_M
) -> Array:
	var out_points := PackedVector2Array()
	var out_widths := PackedFloat32Array()
	if points.is_empty():
		return [out_points, out_widths]
	var sizes := widths
	if sizes.size() != points.size():
		sizes = PackedFloat32Array()
		sizes.resize(points.size())
		sizes.fill(widths[0] if not widths.is_empty() else WaterBody.MIN_HALF_WIDTH_M)
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	if total <= 1e-6:
		return [PackedVector2Array([points[0]]), PackedFloat32Array([sizes[0]])]
	var count := maxi(1, roundi(total / spacing))
	var interval := total / count
	var segment := 0
	var walked := 0.0
	for n in count + 1:
		var target := minf(n * interval, total)
		while segment < points.size() - 2:
			var step_length := points[segment].distance_to(points[segment + 1])
			if walked + step_length >= target:
				break
			walked += step_length
			segment += 1
		var length := points[segment].distance_to(points[segment + 1])
		var t := clampf((target - walked) / length, 0.0, 1.0) if length > 1e-9 else 0.0
		out_points.append(points[segment].lerp(points[segment + 1], t))
		out_widths.append(lerpf(sizes[segment], sizes[segment + 1], t))
	return [out_points, out_widths]


## The river bodies a stroke along `points` (map XZ, upstream first; `half_widths` per
## point) of depth class `depth` and flow `speed` becomes on `doc` as it is now: resampled,
## split into flat reaches (see the header), ids after the document's. Empty when the line
## is shorter than two points, the document has no room for them (MAX_WATER_BODIES,
## MAX_RIVERS) or no heights. Half-widths are clamped to WaterBody's range and to at least
## the depth class's WaterCarve.min_half_width() (ankle 0.44 m, waist 1.33 m, deep 2.96 m).
##
## Conditioning (card painter-water-condition; on unless `condition` is false or
## conditioning_enabled is): the course is smoothed within half a half-width of the drawn line
## (loops trimmed, widths slope-limited), the reach levels are fitted so the water never climbs
## and steps only by whole falls, and a stroke end near other water is joined to it, so the plan
## the carve and the document store is a clean one.
##
## A line over a rise cuts through it (cut_through, card painter-water-cut): the stroke is one
## river along the drawn line, its levels the running minimum, so the reach that meets a rise
## runs flat through it at the level of the water above it and the ground's own drops beyond stay
## falls and steps (cut, then fall; never a staircase of cuts). The carve's banks there are a
## cut's (WaterCarve.cut_stations). The flow direction is the drawn one unless the last point's
## ground stands a fall's height or more over the first's (WaterFallPlan.is_uphill): then the line
## is turned round, as every line drawn uphill always was, so a line from low ground up a hill
## runs down it from the top and is cut only where it still has to climb. An end is not joined to
## water beside it when that would dig through a rise the line does not cross (JOIN_CUT_M).
## `report` (filled when given) says what happened: {"conditioned", "max_disp" (metres the course
## moved), "max_cut", "rise_cut" (the deepest rise cut through, metres, at "rise_pos"), "cut"
## (that passes CUT_SAID_M; not said to the author), "level_moved" (metres a reach level moved),
## "blocked" (only with cut_through off), "hints" (WaterHints records)}. Pure: conditioning runs
## here once, on the authoring peer; the result is stored in the WaterBody list and never
## recomputed.
static func plan_river(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED,
	condition: bool = true,
	report: Dictionary = {}
) -> Array[WaterBody]:
	var on := condition and conditioning_enabled
	report["conditioned"] = on
	report["hints"] = []
	report["fit_hints"] = []
	report["max_disp"] = 0.0
	report["max_cut"] = 0.0
	report["level_moved"] = 0.0
	report["blocked"] = false
	if on and not _long_enough(doc, points, half_widths, depth, report):
		# A line too short to hold water is refused whole and said: it carved ground and landed
		# a sliver of water or none.
		var nothing: Array[WaterBody] = []
		return nothing
	var bodies := _plan(doc, points, half_widths, depth, speed, on, report)
	if not on or bodies.is_empty():
		return bodies
	# The ends: one that stops near other water joins it (a trial plan told its level), the
	# others are only said. The line is planned again with the joined end.
	var ports: GDScript = load(PORTS_PATH)
	var none := PackedInt32Array()
	var head_hw: float = bodies[0].half_widths[0]
	var tail_hw: float = bodies[-1].half_widths[-1]
	var head: Dictionary = ports.end_decision(
		doc, bodies[0].points[0], bodies[0].level_m, head_hw, true, none
	)
	var tail: Dictionary = ports.end_decision(
		doc, bodies[-1].points[-1], bodies[-1].level_m, tail_hw, false, none
	)
	if bool(report.blocked):
		var drawn := _kept_as_drawn(doc, points, half_widths, depth, speed, report, head, tail)
		return _descending(doc, points, half_widths, depth, speed, report, drawn)
	var line := points.duplicate()
	var moved := false
	for pair: Array in [[head, bodies[0].points[0]], [tail, bodies[-1].points[-1]]]:
		var decision: Dictionary = pair[0]
		if [&"join", &"inflow", &"fall_into", &"outlet"].has(decision.action):
			var end: Vector2 = pair[1]
			var last := line.size() - 1
			line[last if end.distance_to(line[last]) < end.distance_to(line[0]) else 0] = decision.target
			moved = true
	var unjoined := false
	if moved:
		var first := report.duplicate()
		var again := _plan(doc, line, half_widths, depth, speed, true, report)
		if bool(report.blocked):
			var drawn := _kept_as_drawn(doc, points, half_widths, depth, speed, report, head, tail)
			return _descending(doc, points, half_widths, depth, speed, report, drawn)
		var dug := float(report.get("rise_cut", 0.0)) - float(first.get("rise_cut", 0.0))
		if cut_through and dug > JOIN_CUT_M:
			# The joined end would dig through a rise the drawn line does not cross (a head on a
			# plateau snapped into the pond at its foot): the line stays as drawn, the end is said.
			for key: Variant in first:
				report[key] = first[key]
			unjoined = true
		elif not again.is_empty():
			bodies = again
	var hints: Array = (report.get("fit_hints", []) as Array).duplicate()
	for hint: Dictionary in load(HINTS_PATH).plan_hints(PackedVector2Array(), {}, head, tail):
		if unjoined and hint.kind == &"end_snapped":
			var at_head: bool = hint.pos == head.get("target", Vector2.INF)
			hint.kind = &"perched_head" if at_head else &"end_near_water_below"
			hint.fixes = [&"carve_fall", &"move_head", &"keep"] as Array[StringName]
		hints.append(hint)
	# A line cut through a rise is not said (the owner, 2026-11-22: "The hint is unwanted"); the
	# report still records it.
	report["cut"] = float(report.get("rise_cut", 0.0)) > CUT_SAID_M
	report["hints"] = hints
	return bodies


## The shortest a river of depth class `depth` with `free_ends` tapered ends (0 to 2: ends on
## dry ground, not at the map edge) can be and still hold water: each tapered end's bed rises to
## the surface over WaterCarve.pool_tail() of that depth (ankle 1.5 m, waist 2.7 m, deep 5 m),
## so under half a tail per end the bed never reaches half the class's depth (ankle 1.5 m, waist
## 2.7 m, deep 5 m with two free ends: for waist and deep about the channel's own width).
## Measured (card painter-water-paths): a 0.9 m stroke of any class carved 15 to 17 samples of
## ground and landed 1 or 2 wet ones; a 2 m waist stroke landed 0.24 m of its 0.9 m depth.
static func min_river_length(depth: WaterBody.Depth, free_ends: int = 2) -> float:
	return WaterCarve.pool_tail(WaterBody.depth_for(depth)) * free_ends * 0.5


## True when the drawn line `points` is at least min_river_length() long for its free ends (an
## end in or within snap reach of other water, or at the map edge, does not taper). Else false,
## with `report` "refused" (&"too_short") and the hint (WaterHints "too_short"): the stroke is
## refused whole, nothing is planned and nothing carved.
static func _long_enough(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	report: Dictionary
) -> bool:
	if points.size() < 2 or half_widths.size() != points.size():
		return true
	var ports: GDScript = load(PORTS_PATH)
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	var edge := doc.extent_m() * 0.5 - Vector2.ONE * WaterCarve.EDGE_MARGIN_M
	var free: Array[int] = []
	for i: int in [0, points.size() - 1]:
		var p := points[i]
		var hw := clampf(half_widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
		var at_edge := absf(p.x) >= edge.x or absf(p.y) >= edge.y
		if not at_edge and not ports.water_within(doc, p, ports.snap_reach(hw)):
			free.append(i)
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	var need := min_river_length(depth, free.size())
	if length >= need:
		return true
	var fixes: Array[StringName] = [&"draw_longer", &"shallower", &"paint_pond"]
	var middle := (points[0] + points[points.size() - 1]) * 0.5
	var detail := {"length_m": length, "need_m": need}
	report["refused"] = &"too_short"
	report["hints"] = [load(HINTS_PATH).make(&"too_short", middle, fixes, detail)]
	return false


## The plan of a stroke whose conditioning was blocked (it would cut a gorge, see
## WaterConditioner.CUT_LIMIT_M): exactly the unconditioned plan, so a blocked stroke is never
## worse than conditioning off (neither a smoothed course nor a joined end rides along with the
## levels as drawn), with the blocking hints and what the ends said (`head`, `tail`: end_decision
## results, only said, never acted on).
static func _kept_as_drawn(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float,
	report: Dictionary,
	head: Dictionary,
	tail: Dictionary
) -> Array[WaterBody]:
	report["max_disp"] = 0.0
	report["level_moved"] = 0.0
	var hints: Array = (report.get("fit_hints", []) as Array).duplicate()
	for hint: Dictionary in load(HINTS_PATH).plan_hints(PackedVector2Array(), {}, head, tail):
		# An end that was not snapped (the plan is as drawn) is not reported as snapped.
		if hint.kind != &"end_snapped":
			hints.append(hint)
	report["hints"] = hints
	return _plan(doc, points, half_widths, depth, speed, false, {})


## Water does not climb (docs/systems/water_field.md "Water does not climb"). `drawn` is a blocked
## stroke's plan as drawn (_kept_as_drawn()): when its reach levels only descend it is returned
## as it is. When they climb (the line crosses a rise the conditioner will not cut a gorge
## through), the stroke becomes the longest part of the line that runs downhill
## (WaterConditioner.longest_descent), planned as a stroke of its own: conditioned, its ends
## joined or tapered, so the river ends in a pool at the foot of the rise instead of standing up
## it as a wall of water. The hint `stopped_at_rise` says so (`report.stopped` is true, `kept_m`
## and `drawn_m` the lengths). The author's ground is never cut for it. A part too short to hold
## water is refused like any short line.
## The rest of the gesture is not lost: `report.rest` lists the line's other parts between its
## troughs and crests (WaterConditioner.monotone_parts) as [points, half_widths] lines that each
## run downhill, a climbing part turned round so it runs down from its crest. plan_river() returns
## one stroke, so the caller plans each of them on the document as it stands once the parts before
## it are carved (WaterEditor.compute does, in the same history entry; at most MAX_PIECES).
static func _descending(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float,
	report: Dictionary,
	drawn: Array[WaterBody]
) -> Array[WaterBody]:
	var levels := PackedFloat64Array()
	for body in drawn:
		levels.append(body.level_m)
	var conditioner: GDScript = load(CONDITIONER_PATH)
	var found: Array[Dictionary] = conditioner.climbs(levels)
	if not stop_at_rise:
		return drawn
	if found.is_empty():
		# A rise within the dead band drops onto the lowest level upstream (water is only lowered):
		# even 0.2 m of climb draws as a step along the field's samples.
		var low := INF
		for body in drawn:
			low = minf(low, body.level_m)
			body.level_m = low
		return drawn
	var rise_at: Vector2 = drawn[int(found[0].from)].points[0]
	# The line's parts between its troughs and crests, each as a line that runs downhill (a
	# climbing part turned round). The longest part that descends as drawn is the stroke planned
	# here; the others are `report.rest`, for the caller to plan and land after it.
	var part: Array = []
	var best := -1.0
	var rest: Array = []
	for found_part: Vector3i in conditioner.monotone_parts(levels):
		var from: Vector2 = drawn[found_part.x].points[0]
		var piece := sub_line(points, half_widths, from, drawn[found_part.y].points[-1])
		var length := polyline_length(piece[0])
		if found_part.z > 0:
			var turned_points: PackedVector2Array = piece[0]
			var turned_sizes: PackedFloat32Array = piece[1]
			turned_points.reverse()
			turned_sizes.reverse()
			piece = [turned_points, turned_sizes]
			# A part as drawn is preferred to any turned one.
			length *= 1e-3
		if length > best:
			if not part.is_empty():
				rest.append(part)
			part = piece
			best = length
		else:
			rest.append(piece)
	var sub := {}
	var bodies: Array[WaterBody] = []
	# The part is strictly shorter than the line, so this ends; the guard is for a plan that
	# keeps finding a rise in ever shorter parts.
	if _descent_depth < MAX_DESCENT_TRIES:
		_descent_depth += 1
		bodies = plan_river(doc, part[0], part[1], depth, speed, true, sub)
		_descent_depth -= 1
	var hints: Array = [
		load(HINTS_PATH).make(
			&"stopped_at_rise",
			rise_at,
			[&"draw_from_top", &"cut_ridge", &"reroute"] as Array[StringName],
			{"rise_m": float(found[0].rise), "rises": found.size()}
		)
	]
	hints.append_array(sub.get("hints", []))
	for key: Variant in sub:
		report[key] = sub[key]
	# The part planned here may have crossed a rise of its own: its rest follows this line's.
	rest.append_array(sub.get("rest", []))
	report["rest"] = rest
	report["hints"] = hints
	report["stopped"] = true
	report["drawn_m"] = polyline_length(points)
	report["kept_m"] = polyline_length(part[0])
	return bodies


## The length of polyline `points` (metres).
static func polyline_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	return length


## The part of the polyline `points` (a value of `sizes` per point) between the places on it
## nearest `a` and `b`, in the polyline's own order: [points, sizes], its ends interpolated.
static func sub_line(
	points: PackedVector2Array, sizes: PackedFloat32Array, a: Vector2, b: Vector2
) -> Array:
	var from := _place_on(points, a)
	var to := _place_on(points, b)
	if from > to:
		var swap := from
		from = to
		to = swap
	var out_points := PackedVector2Array()
	var out_sizes := PackedFloat32Array()
	var last := points.size() - 1
	for place: float in [from, to]:
		var i := mini(int(place), last - 1)
		var t := place - i
		if place == to:
			# The whole points strictly between the two places, then the far end.
			for k in range(int(from) + 1, int(ceil(to))):
				out_points.append(points[k])
				out_sizes.append(sizes[k])
		out_points.append(points[i].lerp(points[i + 1], t))
		out_sizes.append(lerpf(sizes[i], sizes[i + 1], t))
	return [out_points, out_sizes]


## Where on the polyline `points` the point nearest `p` lies: segment index plus the share along it.
static func _place_on(points: PackedVector2Array, p: Vector2) -> float:
	var best := 0.0
	var nearest := INF
	for i in points.size() - 1:
		var seg := points[i + 1] - points[i]
		var len_sq := seg.length_squared()
		var t := clampf((p - points[i]).dot(seg) / len_sq, 0.0, 1.0) if len_sq > 1e-12 else 0.0
		var d := p.distance_squared_to(points[i] + seg * t)
		if d < nearest:
			nearest = d
			best = i + t
	return best


## plan_river() once, without the end joins: `condition` runs the course and level fit.
static func _plan(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float,
	condition: bool,
	report: Dictionary
) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	if doc.heights.size() != doc.sample_count():
		return bodies
	var joined := join_line(doc, points, half_widths)
	var line: Array = resample(joined[0], joined[1])
	if condition:
		# WaterCourseFit: the course smoothed within a fraction of its width, loops trimmed,
		# widths slope-limited.
		var fit: Dictionary = load(COURSE_FIT_PATH).condition(joined[0], joined[1])
		report["max_disp"] = float(fit.max_disp)
		if fit.changed:
			line = [fit.points, fit.widths]
	var course: PackedVector2Array = line[0]
	var widths: PackedFloat32Array = line[1]
	if course.size() < 2:
		return bodies
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	for i in widths.size():
		widths[i] = clampf(widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
	var courses := WaterGeometry.river_courses(doc, WaterGeometry.bounds(course, 0.01))
	var ground := water_ground(doc, course, courses)
	# Water runs downhill: a line drawn uphill is reversed, so its falls face downstream.
	var oriented := WaterFallPlan.orient(course, widths, ground)
	course = oriented[0]
	widths = oriented[1]
	ground = oriented[2]
	# The fall plan (WaterFallPlan): lips, plunge points and the subdivision of other steep
	# segments, on the ground sampled every sample step along the line.
	var ground_of := WaterGeometry.water_ground_reader(doc, courses)
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var profile := WaterFallPlan.fine_profile(course, step, ground_of)
	# Over a rise, falls and reaches are planned on the ground the cut leaves (plan_on_cut).
	var on_cut := condition and cut_through and plan_on_cut
	var cut := WaterFallPlan.cut_ground(profile.ground, CUT_PLAN_FROM_M if on_cut else INF)
	on_cut = not cut.is_empty()
	profile["ground"] = cut if on_cut else profile.ground
	var free_ends := Vector2i(
		0 if WaterGeometry.is_wet_at(doc, course[0]) else 1,
		0 if WaterGeometry.is_wet_at(doc, course[-1]) else 1
	)
	var plan := WaterFallPlan.plan_lips(doc, course, widths, profile, free_ends)
	var shaped := WaterFallPlan.shape_line(
		course, widths, ground, plan, WaterBody.depth_for(depth), ground_of
	)
	course = shaped.points
	widths = shaped.widths
	ground = shaped.ground
	var split := WaterFallPlan.cut_ground(ground, -1.0) if on_cut else ground
	var ranges := WaterGeometry.reach_ranges(split, REACH_DROP, shaped.forced, shaped.free)
	var fitted := PackedFloat64Array()
	if condition:
		# The conditioning probe (WaterConditioner): levels that never climb, reaches pooled
		# across steps under the dead band, levels on the 5 cm lattice.
		var into := WaterGeometry.level_at(doc, course[-1], -1, courses)
		# A line over a rise is cut through it (cut_through): no cut is too deep for the plan.
		var opts := {"cut_limit": INF if cut_through else cut_limit_m}
		if free_ends.y == 0 and into != WaterGeometry.DRY:
			opts["pin_last"] = into
		var fit: Dictionary = load(CONDITIONER_PATH).condition_ranges(
			course, ground, ranges, shaped.forced, opts, shaped.free
		)
		ranges = fit.ranges
		fitted = fit.levels
		if not bool(fit.blocked):
			fitted = _meet_crossed_water(doc, course, ranges, fitted, courses)
		# The deepest rise on the line: ground standing over the lowest ground upstream of it,
		# which the water cannot climb and the carve cuts through (WaterCarve.cut_stations).
		var low := INF
		var rise := 0.0
		for i in ground.size():
			low = minf(low, ground[i])
			if ground[i] - low > rise:
				rise = ground[i] - low
				report["rise_pos"] = course[i]
		report["rise_cut"] = rise
		report["max_cut"] = float(fit.max_cut)
		report["blocked"] = bool(fit.blocked)
		report["level_moved"] = 0.0 if fit.blocked else float(fit.moved)
		if on_cut:
			# The note `rise_removed` counts the drawn reaches' climb (a cut ground's never climb).
			var drawn := WaterGeometry.reach_ranges(ground, REACH_DROP, shaped.forced, shaped.free)
			fit.merge(WaterFallPlan.drawn_rises(ground, drawn), true)
		report["fit_hints"] = load(HINTS_PATH).plan_hints(course, fit, {}, {})
	var rivers := 0
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	if (
		doc.water_bodies.size() + ranges.size() > MapDocument.MAX_WATER_BODIES
		or rivers + ranges.size() > MapDocument.MAX_RIVERS
	):
		return bodies
	var next := doc.next_water_id()
	var used := {}
	for body in doc.water_bodies:
		used[body.id] = true
	for k in ranges.size():
		var reach := ranges[k]
		while next > 0 and next <= WaterBody.MAX_ID and used.has(next):
			next += 1
		if next <= 0 or next > WaterBody.MAX_ID:
			bodies.clear()
			return bodies
		used[next] = true
		var river := WaterBody.river(
			next,
			course.slice(reach.x, reach.y + 1),
			widths.slice(reach.x, reach.y + 1),
			depth,
			fitted[k] if condition else WaterGeometry.reach_level(ground, reach),
			clampf(speed, 0.0, WaterBody.MAX_SPEED)
		)
		bodies.append(river)
	return bodies


## The reach levels `levels` (one per range of `ranges` over `course`) with each reach that
## crosses existing water of `doc` standing AT that water's level (a junction is one water at one
## level, card painter-water-junctions). The plan reads crossed water as ground a freeboard over
## its level (water_ground()), so a reach is at or below it already; one that fell short by
## JUNCTION_RAISE_M or less (the 5 cm lattice, a low spot elsewhere on the reach) is raised to it,
## which keeps at least a third of the freeboard everywhere, and never above the reach upstream.
## A reach further below is left: the two do not meet at one level and the field says so.
static func _meet_crossed_water(
	doc: MapDocument,
	course: PackedVector2Array,
	ranges: Array,
	levels: PackedFloat64Array,
	courses: Dictionary
) -> PackedFloat64Array:
	var out := levels.duplicate()
	for k in mini(ranges.size(), out.size()):
		var reach: Vector2i = ranges[k]
		var crossed := INF
		for i in range(reach.x, reach.y + 1):
			var level := WaterGeometry.level_at(doc, course[i], -1, courses)
			if level != WaterGeometry.DRY and WaterGeometry.ground_at(doc, course[i]) < level:
				crossed = minf(crossed, level)
		if is_inf(crossed):
			continue
		var short := crossed - out[k]
		var ceiling := out[k - 1] if k > 0 else INF
		if short > 1e-4 and short <= JUNCTION_RAISE_M and crossed <= ceiling:
			out[k] = crossed
	return out


## What re-fitting `doc`'s stored water would do (WaterRefit.refit(): strokes that climb
## downstream reversed, the river and pond tree solved, the strokes carved again), as a result
## dictionary; the document is untouched. apply_refit() puts it in. Documents load as drawn: only
## this call (the editor's "re-fit water", a render job) conditions water that is already stored.
static func refit_document(doc: MapDocument) -> Dictionary:
	return load(REFIT_PATH).refit(doc)


## Puts a refit_document() result into `doc`: the new bodies and the re-carved ground.
static func apply_refit(doc: MapDocument, result: Dictionary) -> void:
	var bodies: Array[WaterBody] = []
	bodies.assign(result.bodies)
	doc.water_bodies = bodies
	doc.heights = result.heights


## The ground a river plan reads along `points` of `doc`: WaterGeometry.ground_along(), except
## that under existing water the line reads that water's level plus the freeboard (a
## confluence: the reach that meets it is at its level or below, never down on its bed, see
## join_line()). `courses` (WaterGeometry.river_courses()) saves the smoothing per call.
static func water_ground(
	doc: MapDocument, points: PackedVector2Array, courses: Dictionary = {}
) -> PackedFloat32Array:
	var ground := WaterGeometry.ground_along(doc, points)
	for i in points.size():
		var level := WaterGeometry.level_at(doc, points[i], -1, courses)
		if level != WaterGeometry.DRY and ground[i] < level:
			ground[i] = level + WaterGeometry.FREEBOARD_M
	return ground


## water_ground() at one map point `p`.
static func water_ground_at(doc: MapDocument, p: Vector2, courses: Dictionary = {}) -> float:
	var ground := WaterGeometry.ground_at(doc, p)
	var level := WaterGeometry.level_at(doc, p, -1, courses)
	if level != WaterGeometry.DRY and ground < level:
		return level + WaterGeometry.FREEBOARD_M
	return ground


## A river line (map XZ, upstream first, with one half-width per point, or one for all) cut
## where it runs into existing water of `doc` (WaterGeometry.is_wet_at): a line that starts
## inside a river or pond keeps only its last point in the water before it leaves it (an
## outflow), and one that ends inside water keeps only its first point in it (an inflow, a
## confluence). That point, just past the other water's edge, is where the new channel meets
## it: the carve leaves that end open (no taper, WaterCarve.river_goals) and plan_river reads
## the other water's level there, so the two meet without a dry lip or a gap. Points in the
## water between two dry stretches (a line crossing a river) stay. A dry end on a
## waterfall's face (the rock between the lip and the plunge pool, WaterFalls.on_face; P4c-5)
## moves into the pool below it, just past the carved face's foot (WaterFalls.pool_point), so
## a tributary drawn into a fall ends in its pool, not on the rock. [PackedVector2Array,
## PackedFloat32Array]; fewer than two points when the whole line lies in water.
static func join_line(
	doc: MapDocument, points: PackedVector2Array, half_widths: PackedFloat32Array
) -> Array:
	var widths := half_widths
	if widths.size() != points.size():
		widths = PackedFloat32Array()
		widths.resize(points.size())
		widths.fill(half_widths[0] if not half_widths.is_empty() else WaterBody.MIN_HALF_WIDTH_M)
	if doc.water_bodies.is_empty() or points.size() < 2:
		return [points, widths]
	# A fall's face is dry rock whatever is_wet_at says: level_at has no flush cut at a reach's end,
	# so the face reads the upper pool's level, and an end there would join it over the rock.
	var falls := WaterFalls.falls(doc)
	var wet_of := WaterGeometry.wet_reader(doc)
	var wet := PackedByteArray()
	wet.resize(points.size())
	var dry_first := -1
	var dry_last := -1
	for i in points.size():
		if wet_of.call(points[i]) and _face_of(doc, falls, points[i]) < 0:
			wet[i] = 1
		elif dry_first < 0:
			dry_first = i
		if wet[i] == 0:
			dry_last = i
	if dry_first < 0:
		return [PackedVector2Array(), PackedFloat32Array()]
	var first := maxi(dry_first - 1, 0)
	var last := mini(dry_last + 1, points.size() - 1)
	var line := points.slice(first, last + 1)
	# The joining point just past the other water's edge, however far apart the drawn points;
	# a dry end (the first or last drawn point) on a fall's face joins the pool below it.
	if wet[first] == 1:
		line[0] = _junction(wet_of, points[first], points[first + 1])
	else:
		line[0] = _face_junction(doc, falls, points[first])
	if last > first:
		if wet[last] == 1:
			line[-1] = _junction(wet_of, points[last], points[last - 1])
		else:
			line[-1] = _face_junction(doc, falls, points[last])
	return [line, widths.slice(first, last + 1)]


## `p` (a dry stroke end) moved into the plunge pool of the fall of `falls` (WaterFalls.falls)
## whose face it lies on (_face_of()): the pool point JOIN_INSET_M past the carved face's
## foot; `p` itself when it lies on no face.
static func _face_junction(doc: MapDocument, falls: Array[Dictionary], p: Vector2) -> Vector2:
	var k := _face_of(doc, falls, p)
	if k < 0:
		return p
	return WaterFalls.pool_point(doc, falls[k], JOIN_INSET_M)


## The index in `falls` (WaterFalls.falls) of the fall whose face holds map point `p`
## (WaterFalls.on_face), or -1.
static func _face_of(doc: MapDocument, falls: Array[Dictionary], p: Vector2) -> int:
	for k in falls.size():
		if WaterFalls.on_face(doc, falls[k], p):
			return k
	return -1


## Where the segment from `wet` (a point in water) to `dry` enters the water (`wet_of`,
## WaterGeometry.wet_reader()), found by bisection, moved JOIN_INSET_M into it (never past `wet`).
static func _junction(wet_of: Callable, wet: Vector2, dry: Vector2) -> Vector2:
	var inside := wet
	var outside := dry
	for _step in 12:
		var middle := (inside + outside) * 0.5
		if wet_of.call(middle):
			inside = middle
		else:
			outside = middle
	var inward := wet - inside
	if inward.length() <= JOIN_INSET_M:
		return wet
	return inside + inward.normalized() * JOIN_INSET_M


## `doc`'s bodies with `added` appended, as a new array.
static func with_bodies(doc: MapDocument, added: Array[WaterBody]) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	bodies.assign(doc.water_bodies)
	bodies.append_array(added)
	return bodies


## The id a new pond painted from map point `at` gets: the pond already under it (so a
## stroke from inside a pond extends it), else a new id; -1 when there is no room.
static func pond_id_at(doc: MapDocument, at: Vector2) -> int:
	if doc.pond_mask.size() == doc.sample_count():
		var s := doc.world_to_sample(at).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var id := doc.pond_mask[doc.sample_index(x, z)]
		if id != 0 and doc.water_body(id) != null:
			return id
	return doc.next_water_id()


## Writes `value` into `mask` (a pond mask of `doc`'s grid) for every sample within `radius`
## of the segment `from`-`to` (map XZ) whose byte is in `over` (bytes that may be replaced),
## marking each byte it replaced in `replaced` (byte -> true). Returns the rectangle of
## samples changed.
static func stamp(
	doc: MapDocument,
	mask: PackedByteArray,
	from: Vector2,
	to: Vector2,
	radius: float,
	value: int,
	over: PackedByteArray,
	replaced: Dictionary = {}
) -> Rect2i:
	var rect := MaskBrush.capsule_rect(doc, from, to, radius)
	var changed := Rect2i()
	if not rect.has_area() or mask.size() != doc.sample_count():
		return changed
	var replace := {}
	for b in over:
		replace[b] = true
	var width := doc.samples_x()
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2(origin.x + x * step.x, origin.y + z * step.y) - from
			var t := clampf(p.dot(segment) / length_sq, 0.0, 1.0) if length_sq > 0.0 else 0.0
			if (p - segment * t).length_squared() >= radius_sq:
				continue
			var i := z * width + x
			if mask[i] == value or not replace.has(mask[i]):
				continue
			replaced[mask[i]] = true
			mask[i] = value
			changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	return changed


## Marks in `touched` (body id -> true) every river reach of `doc` whose water the eraser
## capsule from `from` to `to` (map XZ) of `radius` reaches (its course, river_course(), comes
## within `radius` plus the half-width there), with the whole river it belongs to
## (river_chain()) and the rivers ending in it (_touch_tributaries()). Returns true when a
## reach was newly marked.
static func touch_rivers(
	doc: MapDocument, touched: Dictionary, from: Vector2, to: Vector2, radius: float
) -> bool:
	var any := false
	for body in doc.water_bodies:
		if not body.is_river() or touched.has(body.id):
			continue
		var course := WaterGeometry.river_course(body)
		var line: PackedVector2Array = course[0]
		var widths: PackedFloat32Array = course[1]
		for s in line.size() - 1:
			var hit := segment_distance(from, to, line[s], line[s + 1])
			if hit.x <= radius + lerpf(widths[s], widths[s + 1], hit.y):
				for id in river_chain(doc.water_bodies, body.id):
					touched[id] = true
				any = true
				break
	if any:
		_touch_tributaries(doc, touched)
	return any


## Adds to `touched` every river (whole, river_chain()) with an end in the water of a
## touched one: a stream that flowed into an erased river would end spilling into its dry
## channel.
static func _touch_tributaries(doc: MapDocument, touched: Dictionary) -> void:
	var grew := true
	while grew:
		grew = false
		for body in doc.water_bodies:
			if not body.is_river() or touched.has(body.id) or body.points.size() < 2:
				continue
			for end in [body.points[0], body.points[-1]]:
				if _in_touched(doc, touched, end):
					for id in river_chain(doc.water_bodies, body.id):
						touched[id] = true
					grew = true
					break


## True when map point `p` lies in the area of a river in `touched` (its half-width plus the
## bank of its course).
static func _in_touched(doc: MapDocument, touched: Dictionary, p: Vector2) -> bool:
	for body in doc.water_bodies:
		if not touched.has(body.id):
			continue
		var course := WaterGeometry.river_course(body)
		var near := WaterGeometry.nearest_on_polyline(course[0], p)
		if near.y < 0:
			continue
		var half := WaterGeometry.width_at(course[1], int(near.y), near.z)
		if near.x <= half + WaterGeometry.RIVER_BANK_M:
			return true
	return false


## The ids of the river `id` and every reach joined to it end to end (the reaches of one
## stroke share their boundary points, WaterGeometry.flush_ends), upstream and downstream.
static func river_chain(bodies: Array[WaterBody], id: int) -> PackedInt32Array:
	var chain := PackedInt32Array([id])
	var grew := true
	while grew:
		grew = false
		for body in bodies:
			if not body.is_river() or body.points.size() < 2 or chain.has(body.id):
				continue
			for other in bodies:
				if not chain.has(other.id) or not other.is_river() or other.points.size() < 2:
					continue
				var joined := (
					(
						other.points[-1].distance_squared_to(body.points[0])
						< WaterGeometry.JOIN_EPSILON_SQ
					)
					or (
						other.points[0].distance_squared_to(body.points[-1])
						< WaterGeometry.JOIN_EPSILON_SQ
					)
				)
				if joined:
					chain.append(body.id)
					grew = true
					break
	return chain


## The shortest distance between segments a0-a1 and b0-b1 and where it falls on b0-b1:
## Vector2(distance, t along b 0..1).
static func segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	# Each end against the other segment; crossing segments meet at distance 0.
	for k in 4:
		var p: Vector2 = [a0, a1, b0, b1][k]
		var on_b := k < 2
		var s0 := b0 if on_b else a0
		var s1 := b1 if on_b else a1
		var d := s1 - s0
		var t := (
			clampf((p - s0).dot(d) / d.length_squared(), 0.0, 1.0) if d != Vector2.ZERO else 0.0
		)
		var dist := p.distance_to(s0 + d * t)
		if dist < best.x:
			# On b: where a's end projects; b's own ends are at 0 and 1.
			best = Vector2(dist, t if on_b else float(k - 2))
	var hit: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit is Vector2:
		var db := b1 - b0
		var along := clampf(((hit as Vector2) - b0).dot(db) / db.length_squared(), 0.0, 1.0)
		best = Vector2(0.0, along if db != Vector2.ZERO else 0.0)
	return best


## `doc`'s bodies after an erase (see the header): without the river reaches in `touched`
## (body id -> true), and with the ponds that still hold a sample of `doc.pond_mask`; a
## pond in `shrunk` (id -> true: the eraser took some of its samples) settles to the level of
## its new rim (WaterGeometry.pond_rim_level on `doc`'s heights, a copy of the body). A new
## array.
static func erased_bodies(
	doc: MapDocument, touched: Dictionary, shrunk: Dictionary = {}
) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var present := PackedInt32Array()
	present.resize(WaterBody.MAX_ID + 1)
	for id in doc.pond_mask:
		present[id] += 1
	for body in doc.water_bodies:
		if body.is_river():
			if not touched.has(body.id):
				out.append(body)
			continue
		if present[body.id] == 0:
			continue
		if shrunk.has(body.id):
			var level := WaterGeometry.pond_rim_level(doc, body.id)
			if not is_nan(level):
				var settled := body.copy()
				settled.level_m = minf(level, body.level_m)
				out.append(settled)
				continue
		out.append(body)
	return out


## The map XZ bounds of every river of `bodies` grown by its widest half-width plus the
## bank (the area its water and dressing can reach), merged; empty with no river.
static func rivers_bounds(bodies: Array[WaterBody], pad: float) -> Rect2:
	var out := Rect2()
	var any := false
	for body in bodies:
		if not body.is_river() or body.points.is_empty():
			continue
		var widest := 0.0
		for w in body.half_widths:
			widest = maxf(widest, w)
		var box := WaterGeometry.bounds(body.points, widest + pad)
		out = box if not any else out.merge(box)
		any = true
	return out
