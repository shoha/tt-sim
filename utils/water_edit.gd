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

## The conditioning off switch (card painter-water-condition): plan_river() conditions a stroke
## (smooths the course, WaterCourseFit; fits the reach levels, WaterConditioner; joins the ends,
## WaterPorts) unless this is false. On in every build; an A/B capture or a test of the drawn,
## unconditioned plan sets it false (render jobs: the `conditioning` flag).
static var conditioning_enabled: bool = true
## The deepest cut into the drawn ground a conditioned plan may ask of the carve before the stroke
## is kept as drawn (WaterConditioner.CUT_LIMIT_M); a test or probe may change it.
static var cut_limit_m: float = 1.5


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
## the carve and the document store is a clean one. A plan that would cut a gorge is kept as
## drawn. `report` (filled when given) says what happened: {"conditioned", "max_disp" (metres
## the course moved), "max_cut", "level_moved" (metres a reach level moved), "blocked", "hints"
## (WaterHints records)}. Pure: conditioning runs here once, on the authoring peer; the result
## is stored in the WaterBody list and never recomputed.
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
		return _kept_as_drawn(doc, points, half_widths, depth, speed, report, head, tail)
	var line := points.duplicate()
	var moved := false
	for pair: Array in [[head, bodies[0].points[0]], [tail, bodies[-1].points[-1]]]:
		var decision: Dictionary = pair[0]
		if [&"join", &"inflow", &"fall_into", &"outlet"].has(decision.action):
			var end: Vector2 = pair[1]
			var last := line.size() - 1
			line[last if end.distance_to(line[last]) < end.distance_to(line[0]) else 0] = decision.target
			moved = true
	if moved:
		var again := _plan(doc, line, half_widths, depth, speed, true, report)
		if bool(report.blocked):
			return _kept_as_drawn(doc, points, half_widths, depth, speed, report, head, tail)
		if not again.is_empty():
			bodies = again
	var hints: Array = (report.get("fit_hints", []) as Array).duplicate()
	hints.append_array(load(HINTS_PATH).plan_hints(PackedVector2Array(), {}, head, tail))
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
	var ground_of := func(p: Vector2) -> float: return water_ground_at(doc, p, courses)
	var step := minf(doc.sample_step().x, doc.sample_step().y)
	var profile := WaterFallPlan.fine_profile(course, step, ground_of)
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
	var ranges := WaterGeometry.reach_ranges(
		ground, WaterGeometry.REACH_DROP_M, shaped.forced, shaped.free
	)
	var fitted := PackedFloat64Array()
	if condition:
		# The conditioning probe (WaterConditioner): levels that never climb, reaches pooled
		# across steps under the dead band, levels on the 5 cm lattice.
		var into := WaterGeometry.level_at(doc, course[-1], -1, courses)
		var opts := {"cut_limit": cut_limit_m}
		if free_ends.y == 0 and into != WaterGeometry.DRY:
			opts["pin_last"] = into
		var fit: Dictionary = load(CONDITIONER_PATH).condition_ranges(
			course, ground, ranges, shaped.forced, opts, shaped.free
		)
		ranges = fit.ranges
		fitted = fit.levels
		if not bool(fit.blocked):
			fitted = _meet_crossed_water(doc, course, ranges, fitted, courses)
		report["max_cut"] = float(fit.max_cut)
		report["blocked"] = bool(fit.blocked)
		report["level_moved"] = 0.0 if fit.blocked else float(fit.moved)
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
	# A fall's face counts as dry rock whatever is_wet_at says: level_at has no flush cut at a
	# reach's end, so within the half-width plus the bank of the lip the face reads the upper
	# pool's level, and an end there would join that pool over the rock.
	var falls := WaterFalls.falls(doc)
	var wet := PackedByteArray()
	wet.resize(points.size())
	var dry_first := -1
	var dry_last := -1
	for i in points.size():
		if WaterGeometry.is_wet_at(doc, points[i]) and _face_of(doc, falls, points[i]) < 0:
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
		line[0] = _junction(doc, points[first], points[first + 1])
	else:
		line[0] = _face_junction(doc, falls, points[first])
	if last > first:
		if wet[last] == 1:
			line[-1] = _junction(doc, points[last], points[last - 1])
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


## Where the segment from `wet` (a point in water) to `dry` enters the water, found by
## bisection, moved JOIN_INSET_M into it (never past `wet`).
static func _junction(doc: MapDocument, wet: Vector2, dry: Vector2) -> Vector2:
	var inside := wet
	var outside := dry
	for _step in 12:
		var middle := (inside + outside) * 0.5
		if WaterGeometry.is_wet_at(doc, middle):
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
