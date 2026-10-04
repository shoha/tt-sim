extends GutTest

## Waterfalls (phase 4c, P4c-1): the fall-or-riffle rule (WaterFalls) and the river plan it
## shapes (WaterEdit.plan_river: orient, fine profile, lips, plunge point, subdivision), on
## ground built with the project's own tier profile and ramps.

const GRASS := "grass"
## Ground shapes (the tier band, the ramp) and the carve, shared with the carve tests.
const Fixtures := preload("res://tests/unit/water_fixtures.gd")


## A 150 ft map at the default 0.25 m spacing (183 samples a side, tier 1.524 m).
func _doc(cells: int = 30) -> MapDocument:
	return MapDocument.create_flat(Vector2i(cells, cells), GRASS, "test", 5)


func _ground(doc: MapDocument, p: Vector2) -> float:
	return WaterGeometry.ground_at(doc, p)


## The first z from `from_z` upward where the ground at x = `x` has left the tier top (more
## than a centimetre below `top`).
func _brink_z(doc: MapDocument, x: float, from_z: float, top: float) -> float:
	var z := from_z
	while z < 20.0:
		if _ground(doc, Vector2(x, z)) < top - 0.01:
			return z
		z += 0.01
	return NAN


## A straight stroke from `from` to `to` with one half-width.
func _plan(
	doc: MapDocument, from: Vector2, to: Vector2, half: float, depth := WaterBody.Depth.WAIST
) -> Array[WaterBody]:
	return WaterEdit.plan_river(
		doc, PackedVector2Array([from, to]), PackedFloat32Array([half, half]), depth
	)


## The steps between consecutive reaches of one stroke (upper level minus lower level).
func _steps(bodies: Array[WaterBody]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for b in bodies.size() - 1:
		out.append(bodies[b].level_m - bodies[b + 1].level_m)
	return out


## Every field of every body, for byte-for-byte comparisons.
func _model(bodies: Array[WaterBody]) -> Array:
	var out := []
	for body in bodies:
		out.append(
			[
				body.id,
				body.kind,
				body.depth,
				body.level_m,
				body.speed,
				body.points,
				body.half_widths
			]
		)
	return out


## WaterEdit.plan_river exactly as v0.1.29 shipped it (join, resample, clamp, ground with the
## water-level override, reach_ranges, bodies), frozen here so the regression below compares
## the new plan against the old one by value rather than against invariants the old code
## happened to satisfy: a frozen copy fails the moment any field of any body differs, where
## invariants (step sizes, point spacing) could all hold while the bodies drifted. It calls
## the shared helpers (join_line, resample, reach_ranges with its defaults, reach_level),
## which P4c-1 leaves unchanged for these arguments.
func _plan_river_v0_1_29(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	if doc.heights.size() != doc.sample_count():
		return bodies
	var joined := WaterEdit.join_line(doc, points, half_widths)
	var line: Array = WaterEdit.resample(joined[0], joined[1])
	var course: PackedVector2Array = line[0]
	var widths: PackedFloat32Array = line[1]
	if course.size() < 2:
		return bodies
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	for i in widths.size():
		widths[i] = clampf(widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
	var ground := WaterGeometry.ground_along(doc, course)
	for i in course.size():
		var level := WaterGeometry.level_at(doc, course[i])
		if level != WaterGeometry.DRY and ground[i] < level:
			ground[i] = level + WaterGeometry.FREEBOARD_M
	var ranges := WaterGeometry.reach_ranges(ground)
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
	for reach in ranges:
		while next > 0 and next <= WaterBody.MAX_ID and used.has(next):
			next += 1
		if next <= 0 or next > WaterBody.MAX_ID:
			bodies.clear()
			return bodies
		used[next] = true
		bodies.append(
			WaterBody.river(
				next,
				course.slice(reach.x, reach.y + 1),
				widths.slice(reach.x, reach.y + 1),
				depth,
				WaterGeometry.reach_level(ground, reach),
				clampf(speed, 0.0, WaterBody.MAX_SPEED)
			)
		)
	return bodies


# --- gentle strokes are unchanged ----------------------------------------------------------


func test_gentle_slope_plans_as_in_v0_1_29_with_no_fall() -> void:
	# A 0.2 slope (11 degrees): under FALL_SLOPE everywhere and under REACH_DROP_M per 2 m
	# segment, so nothing of the fall plan triggers and the bodies must match the old plan
	# byte for byte. A gentle bend, so the resampling and smoothing are exercised too.
	var doc := _doc()
	Fixtures.shape(doc, func(p: Vector2) -> float: return -0.2 * p.x + 0.02 * p.y)
	var points := PackedVector2Array(
		[Vector2(-18, -3), Vector2(-4, 1), Vector2(8, -2), Vector2(18, 2)]
	)
	var widths := PackedFloat32Array([1.2, 1.5, 1.4, 1.1])
	var old := _plan_river_v0_1_29(doc, points, widths, WaterBody.Depth.WAIST, 0.8)
	var bodies := WaterEdit.plan_river(doc, points, widths, WaterBody.Depth.WAIST, 0.8)
	assert_gt(bodies.size(), 3, "a long gentle slope still splits into several reaches")
	assert_eq(_model(bodies), _model(old), "byte-identical to the v0.1.29 plan")
	for step in _steps(bodies):
		assert_true(step <= WaterGeometry.REACH_DROP_M + 1e-5, "every step at most 0.5 m")
	assert_eq(WaterFalls.drops(bodies).size(), 0, "no drop")
	doc.water_bodies = bodies
	assert_eq(WaterFalls.falls(doc).size(), 0, "no fall")
	assert_eq(WaterFalls.fall_flags(bodies).count(1), 0, "no fall flag for the carve")


func test_a_small_steep_bump_stays_a_riffle() -> void:
	# A 0.6 m step built with the tier profile: steep, but under FALL_MIN_DROP_M. No fall,
	# and the step is split so no riffle step reaches 0.75 m either.
	var doc := _doc()
	Fixtures.tier(doc, Vector2(-30, -10), Vector2(30, -10), 10.0, 0.6)
	var bodies := _plan(doc, Vector2(0, -12), Vector2(0, 12), 1.0)
	assert_gt(bodies.size(), 1, "the bump splits the stroke")
	assert_eq(WaterFalls.drops(bodies).size(), 0, "a 0.6 m drop is no fall")
	doc.water_bodies = bodies
	assert_eq(WaterFalls.falls(doc).size(), 0)
	for step in _steps(bodies):
		assert_lt(step, WaterFalls.FALL_MIN_DROP_M, "no step reaches the fall drop")
		assert_true(
			step <= WaterGeometry.REACH_DROP_M + 1e-4, "riffle steps stay at 0.5 m or under"
		)


# --- the rule ------------------------------------------------------------------------------


func test_reach_ranges_with_forced_boundaries_and_free_points() -> void:
	var ground := PackedFloat32Array([2.0, 2.0, 2.0, 1.9, 1.0, 0.3, 0.3, 0.2, 0.3])
	assert_eq(
		WaterGeometry.reach_ranges(ground),
		[Vector2i(0, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 8)] as Array[Vector2i],
		"without a plan the face is a staircase of steps, as before"
	)
	var free := PackedByteArray([0, 0, 0, 1, 1, 1, 0, 0, 0])
	var ranges := WaterGeometry.reach_ranges(
		ground, WaterGeometry.REACH_DROP_M, PackedInt32Array([3]), free
	)
	assert_eq(
		ranges,
		[Vector2i(0, 3), Vector2i(3, 8)] as Array[Vector2i],
		"the lip ends the upper reach; the face and the pool below are one reach"
	)
	assert_almost_eq(
		WaterGeometry.reach_level(ground, ranges[1]), 0.2 - 0.15, 1e-6, "the pool's level"
	)
	var flat := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0])
	assert_eq(
		WaterGeometry.reach_ranges(flat, 0.5, PackedInt32Array([2])),
		[Vector2i(0, 2), Vector2i(2, 4)] as Array[Vector2i],
		"a forced boundary splits flat ground too"
	)


func test_drop_runs_find_steep_losses_only() -> void:
	var arc := PackedFloat32Array()
	var ground := PackedFloat32Array()
	# Flat at 5 for 2 m, a 1:1 slope losing 3 m, flat at 2 for 2 m, a 0.4 slope losing 1 m,
	# then a 1:1 step of 0.6 m.
	var s := 0.0
	while s <= 12.0 + 1e-6:
		arc.append(s)
		var g := 5.0
		if s > 2.0:
			g = 5.0 - minf(s - 2.0, 3.0)
		if s > 7.0:
			g -= 0.4 * minf(s - 7.0, 2.5)
		if s > 10.5:
			g -= minf(s - 10.5, 0.6)
		ground.append(g)
		s += 0.25
	var runs := WaterFalls.drop_runs(arc, ground)
	assert_eq(runs.size(), 1, "the 0.4 slope and the 0.6 m step are no drops: %s" % str(runs))
	if runs.size() == 1:
		assert_almost_eq(arc[runs[0].x], 2.0, 1e-5, "from the brink")
		assert_almost_eq(arc[runs[0].y], 5.0, 1e-5, "to the foot")
	assert_eq(WaterFalls.drop_runs(PackedFloat32Array([0.0]), PackedFloat32Array([1.0])).size(), 0)
	assert_almost_eq(
		WaterFalls.FALL_FACE_SLOPE, tan(deg_to_rad(44.0)), 1e-6, "the cliff rule's start"
	)
	assert_true(WaterFalls.is_uphill(PackedFloat32Array([0.0, 0.5, 0.8])))
	assert_false(WaterFalls.is_uphill(PackedFloat32Array([0.0, 0.9, 0.7])), "a hump is not uphill")


@warning_ignore("integer_division")
func test_tier_stroke_falls_once_at_the_brink() -> void:
	var doc := _doc()
	Fixtures.tier_band(doc)
	var top := doc.tier_height_m
	var half := 1.0
	var bodies := _plan(doc, Vector2(0, -12), Vector2(0, 12), half)
	assert_eq(
		bodies.size(), 2, "the pool on the top and the pool below: %d reaches" % bodies.size()
	)
	var drops := WaterFalls.drops(bodies)
	assert_eq(drops.size(), 1, "one drop")
	doc.water_bodies = bodies
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1, "one fall: the face is cliff-steep")
	if falls.is_empty():
		return
	var fall: Dictionary = falls[0]
	var lip: Vector2 = fall.lip
	var brink := _brink_z(doc, 0.0, -12.0, top)
	assert_almost_eq(lip.y, brink, 0.3, "the lip within 0.3 m of the brink (brink z %.2f)" % brink)
	assert_almost_eq(lip.x, 0.0, 1e-4, "on the line")
	assert_eq(lip, bodies[1].points[0], "the lip is the shared point")
	assert_almost_eq(float(fall.top), top - WaterGeometry.FREEBOARD_M, 0.05, "the pool on the top")
	assert_almost_eq(float(fall.bottom), -WaterGeometry.FREEBOARD_M, 1e-4, "the pool below")
	assert_true(Vector2(fall.dir).is_equal_approx(Vector2(0, 1)), "facing downstream")
	assert_almost_eq(float(fall.half_width), WaterCarve.min_half_width(WaterBody.Depth.WAIST), 1e-4)
	assert_eq(WaterFalls.fall_flags(bodies), PackedByteArray([1]), "the carve's flag")
	# The plunge point sits about half the plunge length below the lip, PLUNGE_WIDEN wider.
	var lower := bodies[1]
	var widest := 0.0
	var widest_at := Vector2.ZERO
	for i in lower.points.size():
		if lower.half_widths[i] > widest:
			widest = lower.half_widths[i]
			widest_at = lower.points[i]
	var expected_width := WaterCarve.min_half_width(WaterBody.Depth.WAIST) * WaterFalls.PLUNGE_WIDEN
	assert_almost_eq(widest, expected_width, 1e-4, "the plunge point is widened")
	var plunge: float = fall.plunge
	assert_almost_eq(widest_at.y - lip.y, plunge * 0.5, 0.25, "about half the plunge length below")
	assert_true(widest_at.y > lip.y, "below the lip")
	# The footprint: the face samples under the channel between the lip and the foot.
	var footprint := WaterFalls.footprint(doc)
	assert_gt(footprint.size(), 10, "the face has samples")
	var course: PackedVector2Array = WaterGeometry.river_course(lower)[0]
	for i in footprint:
		var p := doc.sample_to_world(Vector2(i % doc.samples_x(), i / doc.samples_x()))
		assert_true(
			WaterGeometry.nearest_on_polyline(course, p).x <= half * 1.4 + 1e-3, "in the channel"
		)
		assert_true(p.y >= lip.y - 1e-6, "downstream of the lip")
		assert_true(doc.heights[i] <= top + 1e-4, "on the face or in the pool, never over the top")


func test_hill_gives_spaced_falls_of_a_tier_each() -> void:
	# A 35 degree ramp (slope 0.7) losing 7 m over 10 m, flat above and below.
	var doc := _doc()
	Fixtures.ramp(doc)
	var bodies := _plan(doc, Vector2(-14, 0), Vector2(14, 0), 1.0)
	var drops := WaterFalls.drops(bodies)
	var spacing := WaterFalls.fall_spacing(WaterCarve.min_half_width(WaterBody.Depth.WAIST))
	assert_eq(drops.size(), 2, "two falls fit a 10 m run at %.1f m spacing" % spacing)
	var last_lip := -INF
	for drop in drops:
		var fall: Dictionary = drop
		assert_true(
			float(fall.top) - float(fall.bottom) >= WaterFalls.FALL_MIN_DROP_M, "each a fall"
		)
		var lip: Vector2 = fall.lip
		if last_lip > -INF:
			assert_true(lip.x - last_lip >= spacing - 1e-4, "lips at least a spacing apart")
		last_lip = lip.x
		assert_true(lip.x >= -5.5 and lip.x <= 4.0, "on the ramp (x %.2f)" % lip.x)
	assert_almost_eq(float(drops[0].lip.x), -5.0, 0.6, "lip 0 at the brink")
	assert_almost_eq(float(drops[0].top) - float(drops[0].bottom), 3.5, 0.3, "half the hill each")
	# Before the carve a 35 degree slope is no rock face, so the runtime rule sees no fall yet.
	doc.water_bodies = bodies
	assert_eq(WaterFalls.falls(doc).size(), 0, "the face comes from the carve (P4c-2)")
	assert_eq(WaterFalls.fall_flags(bodies), PackedByteArray([1, 1]))


func test_uphill_is_reversed_flat_keeps_its_direction() -> void:
	var doc := _doc()
	Fixtures.shape(doc, func(p: Vector2) -> float: return 0.3 * p.x + 5.0)
	var uphill := _plan(doc, Vector2(-10, 0), Vector2(10, 0), 1.0)
	assert_false(uphill.is_empty())
	assert_almost_eq(uphill[0].points[0].x, 10.0, 1e-4, "the drawn end is the source")
	assert_almost_eq(uphill[-1].points[-1].x, -10.0, 1e-4, "the drawn start is the mouth")
	for step in _steps(uphill):
		assert_gt(step, 0.0, "every step runs downhill")
	var flat := _doc()
	var level := _plan(flat, Vector2(-10, 0), Vector2(10, 0), 1.0)
	assert_eq(level.size(), 1)
	assert_almost_eq(level[0].points[0].x, -10.0, 1e-4, "flat: the drawn direction")
	Fixtures.shape(flat, func(p: Vector2) -> float: return 0.03 * p.x)
	var gentle := _plan(flat, Vector2(-10, 0), Vector2(10, 0), 1.0)
	assert_almost_eq(gentle[0].points[0].x, -10.0, 1e-4, "a rise under the fall drop keeps it too")


func test_down_then_up_has_no_upward_fall() -> void:
	# A V valley: a 35 degree descent to x = 0 and the same ascent, flat beyond.
	var doc := _doc()
	Fixtures.shape(doc, func(p: Vector2) -> float: return minf(0.7 * absf(p.x), 4.0))
	var bodies := _plan(doc, Vector2(-10, 0), Vector2(10, 0), 1.0)
	assert_almost_eq(bodies[0].points[0].x, -10.0, 1e-4, "ends level: not reversed")
	var drops := WaterFalls.drops(bodies)
	assert_gt(drops.size(), 0, "the descent falls")
	for drop in drops:
		var fall: Dictionary = drop
		assert_lt(float(fall.lip.x), 0.0, "every fall is on the descent")
		assert_gt(float(fall.top), float(fall.bottom))
		assert_true(float(fall.dir.x) > 0.0, "and faces downstream")
	for step in _steps(bodies):
		assert_lt(absf(minf(step, 0.0)), WaterFalls.FALL_MIN_DROP_M, "no upward step is fall-sized")
	assert_true(bodies.size() <= MapDocument.MAX_RIVERS)


func test_tributary_off_a_tier_falls_into_the_river() -> void:
	var doc := _doc()
	Fixtures.tier_band(doc)
	var start := doc.heights.duplicate()
	var main := _plan(doc, Vector2(-15, 6), Vector2(15, 6), 1.5)
	assert_eq(main.size(), 1)
	Fixtures.carve(doc, WaterCarve.river_goals(doc, main, start))
	doc.water_bodies = main
	assert_true(WaterGeometry.is_wet_at(doc, Vector2(0, 6)), "the river holds water")
	var tributary := WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(0, -8), Vector2(0, 6)]),
		PackedFloat32Array([0.8]),
		WaterBody.Depth.ANKLE
	)
	assert_eq(tributary.size(), 2, "the pool on the top and the stub into the river")
	var last := tributary[-1]
	assert_true(last.level_m <= main[0].level_m + 1e-4, "the stub never stands above the river")
	assert_almost_eq(last.level_m, main[0].level_m, 0.2, "the stub is at the river's level")
	assert_true(WaterGeometry.is_wet_at(doc, last.points[-1]), "and ends in its water")
	doc.water_bodies = WaterEdit.with_bodies(doc, tributary)
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1, "the tributary falls off the tier")
	if falls.is_empty():
		return
	var fall: Dictionary = falls[0]
	assert_eq(doc.water_bodies[fall.lower_index], last, "into its last reach")
	assert_almost_eq(float(fall.bottom), last.level_m, 1e-6)
	assert_true(float(fall.lip.y) > -2.0 and float(fall.lip.y) < 0.0, "the lip at the brink")


func test_diagonal_tier_crossing_keeps_the_upper_water_on_the_top() -> void:
	# A tier whose edge runs at 45 degrees to the stroke (the top is z > x - 1.3 or so).
	var doc := _doc()
	Fixtures.tier(doc, Vector2(-45, -20), Vector2(25, 50), 20.0, doc.tier_height_m)
	var top := doc.tier_height_m
	var bodies := _plan(doc, Vector2(-12, 0), Vector2(12, 0), 1.0)
	assert_eq(bodies.size(), 2, "one fall")
	doc.water_bodies = bodies
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1)
	if falls.is_empty():
		return
	var upper := bodies[0]
	var lip: Vector2 = falls[0].lip
	assert_gt(_ground(doc, lip), top - 0.05, "the lip stands on the top (set back from the brink)")
	assert_lt(lip.x, 0.5, "upstream of the straight-on brink")
	var below := 0
	var wet := WaterGeometry.wet_samples(doc, upper)
	for i in wet:
		if doc.heights[i] < top - 0.5:
			below += 1
	assert_eq(below, 0, "no upper-level wet sample below the brink (%d wet in all)" % wet.size())


func test_old_documents_fall_only_where_the_ground_is_steep() -> void:
	# v0.1.29 planned a cliff as a single two-point step. Over a tier the step's ground is
	# cliff-steep: a fall. Over a 0.8 slope (39 degrees, under the cliff rule's 44) the same
	# sized step keeps its draped riffle sheet.
	var tiered := _doc()
	Fixtures.tier_band(tiered)
	var line := PackedVector2Array([Vector2(0, -12), Vector2(0, 12)])
	var widths := PackedFloat32Array([1.0, 1.0])
	var old := _plan_river_v0_1_29(tiered, line, widths, WaterBody.Depth.WAIST)
	assert_gt(old.size(), 1)
	var largest := 0.0
	for step in _steps(old):
		largest = maxf(largest, step)
	assert_true(
		largest >= WaterFalls.FALL_MIN_DROP_M, "a large single-segment step (%.2f m)" % largest
	)
	tiered.water_bodies = old
	assert_gt(WaterFalls.falls(tiered).size(), 0, "the tier face makes it a fall")
	var ramp := _doc()
	Fixtures.shape(ramp, func(p: Vector2) -> float: return clampf(0.4 - 0.8 * p.x, 0.0, 0.8))
	var old_ramp := _plan_river_v0_1_29(
		ramp, PackedVector2Array([Vector2(-9, 0), Vector2(9, 0)]), widths, WaterBody.Depth.WAIST
	)
	var drops := WaterFalls.drops(old_ramp)
	assert_eq(drops.size(), 1, "an 0.8 m step by the levels")
	ramp.water_bodies = old_ramp
	assert_eq(WaterFalls.falls(ramp).size(), 0, "but no cliff-steep ground: a riffle sheet")


func test_a_long_hillside_stays_under_the_caps() -> void:
	# A 61 m map (40 cells) with a 35 degree hillside most of the way across.
	var doc := _doc(40)
	Fixtures.shape(doc, func(p: Vector2) -> float: return 0.7 * (28.0 - clampf(p.x, -28.0, 28.0)))
	var bodies := _plan(doc, Vector2(-29.5, 0), Vector2(29.5, 0), 1.0)
	assert_false(bodies.is_empty(), "the stroke is planned, not refused")
	assert_lt(bodies.size(), MapDocument.MAX_RIVERS, "%d reaches" % bodies.size())
	assert_lt(bodies.size(), MapDocument.MAX_WATER_BODIES)
	var drops := WaterFalls.drops(bodies)
	assert_gt(drops.size(), 5, "a cascade of falls: %d" % drops.size())
	var spacing := WaterFalls.fall_spacing(WaterCarve.min_half_width(WaterBody.Depth.WAIST))
	var previous := -INF
	for drop in drops:
		var x := float(drop.lip.x)
		assert_true(x - previous >= spacing - 1e-4, "spaced")
		previous = x
	for body in bodies:
		assert_true(body.points.size() <= MapDocument.MAX_RIVER_POINTS)
	gut.p("hillside: %d reaches, %d falls" % [bodies.size(), drops.size()])
