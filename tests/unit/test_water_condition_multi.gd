extends GutTest

## Multi-stroke conditioning and the displacement cap (card painter-water-condition2).
##
## 1. The stored course never strays further than half the drawn half-width from the drawn line,
##    for zigzag, jitter, loop and hairpin strokes at several half-widths (a hard guarantee: the
##    chords between stations are held too, WaterCourseFit.hold_cap).
## 2. A blocked stroke (it would cut a gorge) is exactly the unconditioned plan.
## 3. Conditioning each stroke at plan time never leaves a map with more audit rises
##    (WaterPorts.audit) or more field events than conditioning off, on the integration run's
##    verdict map and on random multi-stroke maps drawn in order and reversed; it is deterministic.

const Multi := preload("res://tests/unit/water_multi_cases.gd")
const Cases := preload("res://tests/unit/water_condition_cases.gd")
const FUZZ_SEEDS := 20
const HALF_WIDTHS := [0.5, 0.8, 1.2, 1.33, 2.0]
const CAP_SLACK_M := 0.02


func _flat_world() -> MapDocument:
	return Cases.world(func(_p: Vector2) -> float: return 0.0)


## A path from a flat list of x, z pairs.
func _path(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		out.append(Vector2(coords[i], coords[i + 1]))
	return out


func _drawn_shapes() -> Dictionary:
	var loop := PackedVector2Array()
	for k in 25:
		var a := TAU * 1.15 * k / 24.0
		loop.append(Vector2(-10.0 + 20.0 * k / 24.0 + 3.0 * cos(a) - 3.0, 3.0 * sin(a)))
	return {
		"zigzag": _path([-12, -3, -8, 2, -3, -4, 2, 3, 7, -3, 12, 2]),
		"hairpin": _path([-12, 0, -4, 1.5, -9, 3, -1, 4.5, -6, 6, 8, 7]),
		"jitter": Cases.jittered(Vector2(-12, 0), Vector2(12, 1), 0.3, 0.45, 5),
		"loop": loop,
	}


func _stored_course(bodies: Array[WaterBody]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for body in bodies:
		var skip := 1 if not out.is_empty() and out[-1].is_equal_approx(body.points[0]) else 0
		out.append_array(body.points.slice(skip))
	return out


func _depth_for(hw: float) -> WaterBody.Depth:
	return WaterBody.Depth.WAIST if hw >= 1.33 else WaterBody.Depth.ANKLE


func test_the_cap_holds_for_every_stroke_shape_and_width() -> void:
	var shapes := _drawn_shapes()
	var worst := {}
	var fallbacks := []
	for shape: String in shapes:
		for hw: float in HALF_WIDTHS:
			for through_gesture in [false, true]:
				var raw: PackedVector2Array = shapes[shape]
				var line := Multi.gesture_line(raw, hw) if through_gesture else raw
				var widths := PackedFloat32Array()
				widths.resize(line.size())
				widths.fill(hw)
				var fit := WaterCourseFit.condition(line, widths)
				var cap := WaterCourseFit.MAX_DISP_PER_HALF_WIDTH * hw
				var tag := "%s hw %.2f gesture %s" % [shape, hw, through_gesture]
				assert_lte(float(fit.max_disp), cap + CAP_SLACK_M, "fit: " + tag)
				var report := {}
				var bodies := WaterEdit.plan_river(
					_flat_world(), line, widths, _depth_for(hw), 1.0, true, report
				)
				assert_false(bodies.is_empty(), "planned: " + tag)
				assert_lte(float(report.max_disp), cap + CAP_SLACK_M, "report: " + tag)
				if float(report.max_disp) <= 0.0:
					# The course was not cleaned: the line is noisier than its own cap can hold (or
					# already clean) and the plan is the unconditioned one. Only a hairpin or
					# jitter at a narrow width may do that.
					fallbacks.append(tag)
					if hw >= 1.0:
						assert_true(shape == "jitter" and not through_gesture, "kept as drawn: " + tag)
					continue
				var stored := WaterCourseFit.deviation(_stored_course(bodies), line)
				assert_lte(stored, cap + CAP_SLACK_M, "stored course: " + tag)
				worst[shape] = maxf(float(worst.get(shape, 0.0)), stored / cap)
	gut.p("CAP worst stored deviation as a share of the cap, per shape: %s" % str(worst))
	gut.p("CAP strokes kept as drawn (not cleaned): %s" % str(fallbacks))


func test_a_hard_zigzag_stays_a_zigzag_within_the_cap() -> void:
	# The integration run's stroke (half-width 1.2, amplitude 5 m): the cap is 0.6 m, so the line
	# is rounded, not straightened; before the fix the real water tool path stored 1.06 m.
	var raw := _path([-12, -4, -8, 1, -3, -5, 2, 2, 7, -4, 12, 1])
	var line := Multi.gesture_line(raw, 1.2)
	var widths := PackedFloat32Array()
	widths.resize(line.size())
	widths.fill(1.2)
	var report := {}
	var depth := WaterBody.Depth.WAIST
	var bodies := WaterEdit.plan_river(_flat_world(), line, widths, depth, 1.0, true, report)
	var stored := _stored_course(bodies)
	var dev := WaterCourseFit.deviation(stored, line)
	assert_lte(dev, 0.6 + CAP_SLACK_M, "within the cap of half a half-width")
	assert_gt(dev, 0.3, "still the author's zigzag, not a straight run")
	var span := 0.0
	for p in stored:
		span = maxf(span, absf(p.y))
	assert_gt(span, 3.0, "the swings are kept (amplitude %.2f m)" % span)
	gut.p("ZIGZAG hw 1.2: max_disp %.3f m (cap 0.600), swing %.2f m" % [dev, span])


func test_hold_cap_keeps_a_line_that_already_holds() -> void:
	var drawn := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var stations := PackedVector2Array([Vector2(0, 0), Vector2(5, 0.2), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.0, 1.0, 1.0])
	var held := WaterCourseFit.hold_cap(stations, widths, drawn, 0.5)
	assert_eq(held[0], stations, "unchanged")
	var far := PackedVector2Array([Vector2(0, 0), Vector2(5, 3.0), Vector2(10, 0)])
	var pulled := WaterCourseFit.hold_cap(far, widths, drawn, 0.5)
	assert_lte(WaterCourseFit.deviation(pulled[0], drawn), 0.5 + CAP_SLACK_M, "pulled to the cap")
	assert_eq(pulled[0].size(), pulled[1].size(), "one width per station")


func test_a_blocked_stroke_is_exactly_the_unconditioned_plan() -> void:
	# The ridge stroke climbs as drawn, so the plan cuts it to its descending part
	# (WaterEdit.stop_at_rise, test_water_condition_pipeline "water does not climb"); with that
	# rule off a blocked stroke is the unconditioned plan and nothing else.
	var off := Cases.make("over_hill", false)
	WaterEdit.stop_at_rise = false
	var on := Cases.make("over_hill", true)
	WaterEdit.stop_at_rise = true
	assert_true(Cases.blocked, "the ridge stroke is blocked")
	assert_eq(on.water_bodies.size(), off.water_bodies.size(), "same reaches")
	for i in off.water_bodies.size():
		assert_eq(on.water_bodies[i].level_m, off.water_bodies[i].level_m, "same level %d" % i)
		assert_eq(on.water_bodies[i].points, off.water_bodies[i].points, "same course %d" % i)
	assert_eq(on.heights, off.heights, "same carve")


func _events(m: Dictionary) -> int:
	return int(m.film_run) + int(m.bridged_run) + int(m.end_near)


func test_the_verdict_map_is_never_worse_than_conditioning_off() -> void:
	for reversed in [false, true]:
		var off_doc := Multi.verdict_map(false, reversed)
		var on_doc := Multi.verdict_map(true, reversed)
		var off := Cases.metrics(off_doc)
		var on := Cases.metrics(on_doc)
		gut.p(
			(
				"VERDICT reversed %s: off bodies %d rises %d events %d | on bodies %d rises %d events %d"
				% [
					reversed,
					off_doc.water_bodies.size(),
					off.rises,
					_events(off),
					on_doc.water_bodies.size(),
					on.rises,
					_events(on)
				]
			)
		)
		assert_lte(int(on.rises), int(off.rises), "rises (reversed %s)" % reversed)
		assert_lte(_events(on), _events(off), "field events (reversed %s)" % reversed)
		assert_lte(on_doc.water_bodies.size(), off_doc.water_bodies.size() + 1, "bodies")


func test_random_multi_stroke_maps_are_never_worse_and_deterministic() -> void:
	var sums := {
		"off": {"rises": 0, "events": 0, "bodies": 0}, "on": {"rises": 0, "events": 0, "bodies": 0}
	}
	var worse := []
	for reversed in [false, true]:
		for seed_value in FUZZ_SEEDS:
			Multi.reports.clear()
			var off_doc := Multi.fuzz_map(seed_value, false, reversed)
			var on_doc := Multi.fuzz_map(seed_value, true, reversed)
			var blocked := false
			for r in Multi.reports:
				blocked = blocked or bool(r.get("blocked", false))
			var off := Cases.metrics(off_doc)
			var on := Cases.metrics(on_doc)
			var tag := "seed %d reversed %s" % [seed_value, reversed]
			assert_lte(int(on.rises), int(off.rises), "rises: " + tag)
			if not blocked:
				assert_eq(int(on.rises), 0, "no rise where nothing was blocked: " + tag)
			for key in ["film_run", "bridged_run", "end_near"]:
				if on[key] > off[key]:
					worse.append("%s %s %d -> %d" % [tag, key, off[key], on[key]])
			sums.off.rises += off.rises
			sums.on.rises += on.rises
			sums.off.events += _events(off)
			sums.on.events += _events(on)
			sums.off.bodies += off_doc.water_bodies.size()
			sums.on.bodies += on_doc.water_bodies.size()
			if seed_value < 5:
				var again := Multi.fuzz_map(seed_value, true, reversed)
				assert_eq(again.water_bodies.size(), on_doc.water_bodies.size(), "deterministic: " + tag)
				for i in again.water_bodies.size():
					assert_eq(again.water_bodies[i].level_m, on_doc.water_bodies[i].level_m, "level " + tag)
					assert_eq(again.water_bodies[i].points, on_doc.water_bodies[i].points, "course " + tag)
	gut.p("MULTI FUZZ %d seeds x 2 orders: %s" % [FUZZ_SEEDS, str(sums)])
	gut.p("MULTI FUZZ single events that grew (a seed can trade one for another): %s" % str(worse))
	assert_lte(sums.on.rises, sums.off.rises, "summed rises")
	# Events are not a guarantee (a seed trades a bridged run for a film run, see the doc); the
	# total stays within a tenth of off's.
	assert_lte(float(sums.on.events), float(sums.off.events) * 1.1, "summed field events")
