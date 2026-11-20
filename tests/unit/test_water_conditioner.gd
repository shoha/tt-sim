extends GutTest

## The water-conditioning spike (card painter-water-condition-spike; WaterConditioner,
## WaterCourseFit, WaterPorts): pure conditioning of a drawn river's course and levels, measured
## against the WaterField. Nothing here is wired into a tool: WaterEdit.plan_river takes the probe
## through its `condition` argument and WaterEdit.CONDITION_PROBE stays off.
##
## Pinned: the unit rules of the fit (never climbs, steps of at least the dead band or exactly
## equal, lattice levels, falls and cuts kept, idempotent), the course (moves within a fraction of
## the half-width, loops trimmed, near-idempotent), the end decision table, the tree solver, then a
## fuzzer of hydrology invariants over seeded random maps (conditioned strokes never climb,
## planning is deterministic) and the before-and-after table on the canonical fixture and the ten
## synthetic cases, printed with gut.p (the numbers are in
## docs/plans/handoffs/painter-water-condition-spike.md).

const Cases := preload("res://tests/unit/water_condition_cases.gd")
const CANONICAL := "res://tests/fixtures/water_field_canonical.ttmap"
const FUZZ_SEEDS := 14
const WAIST := WaterBody.Depth.WAIST


func _lengths(n: int, each: float = 1.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(n)
	out.fill(each)
	return out


func _fit(
	t: PackedFloat64Array, lengths: PackedFloat64Array, cuts: PackedByteArray, opts: Dictionary
) -> Dictionary:
	return WaterConditioner.fit_levels(lengths, t, t, cuts, opts)


func _on_lattice(level: float) -> bool:
	var k := level / WaterConditioner.QUANTUM_M
	return absf(k - roundf(k)) < 1e-6


func _canonical() -> MapDocument:
	return MapDocumentIO.read(CANONICAL).get("document")


func _river_chain(doc: MapDocument) -> Array[WaterBody]:
	var chain: Array[WaterBody] = []
	for body in doc.water_bodies:
		if body.is_river():
			chain.append(body)
	return chain


func _set_levels(chain: Array[WaterBody], levels: PackedFloat64Array) -> void:
	for k in chain.size():
		chain[k].level_m = levels[k]


func _count(events: Array[Dictionary], kind: StringName) -> int:
	var n := 0
	for e in events:
		n += 1 if e.kind == kind else 0
	return n


# --- the profile fit ---------------------------------------------------------------------------


func test_fit_never_climbs_and_steps_are_whole() -> void:
	var t := PackedFloat64Array(
		[10.0, 10.2, 9.9, 10.3, 9.6, 9.0, 9.1, 8.2, 8.3, 8.1, 7.0, 7.4, 6.2]
	)
	var fit := _fit(t, _lengths(t.size()), PackedByteArray(), {"min_len": 0.0})
	var lv: PackedFloat64Array = fit.levels
	var dead := WaterConditioner.DEAD_BAND_M - 1e-9
	for i in lv.size():
		assert_true(_on_lattice(lv[i]), "level %d is on the lattice" % i)
		assert_true(lv[i] <= t[i] + 1e-9, "never raised over its own cap")
		if i > 0:
			var step := lv[i - 1] - lv[i]
			assert_gte(step, -1e-9, "no rise at %d" % i)
			assert_true(step < 1e-9 or step >= dead, "no step under the dead band at %d" % i)


func test_fit_is_idempotent_and_deterministic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for round_n in 40:
		var lengths := PackedFloat64Array()
		var t := PackedFloat64Array()
		var level := rng.randf_range(0.0, 8.0)
		for i in rng.randi_range(2, 60):
			lengths.append(rng.randf_range(0.25, 3.0))
			level += rng.randfn(-0.05, 0.4)
			t.append(level)
		var opts := {"min_len": rng.randf_range(0.0, 4.0)}
		var a := _fit(t, lengths, PackedByteArray(), opts)
		var b := _fit(t, lengths, PackedByteArray(), opts)
		assert_eq(a.levels, b.levels, "round %d: deterministic" % round_n)
		var again := WaterConditioner.fit_levels(lengths, a.levels, t, PackedByteArray(), opts)
		assert_eq(a.levels, again.levels, "round %d: idempotent on its own output" % round_n)


func test_fit_keeps_falls_and_cuts() -> void:
	# A 3 m fall, a 0.8 m ankle fall, and a 0.2 m step across a pinned cut (a lip).
	var t := PackedFloat64Array([9.0, 9.0, 6.0, 6.0, 5.2, 5.2, 5.0, 5.0])
	var cuts := PackedByteArray([0, 0, 0, 0, 0, 1, 0])
	var lv: PackedFloat64Array = _fit(t, _lengths(8, 3.0), cuts, {}).levels
	assert_almost_eq(lv[1] - lv[2], 3.0, 1e-9, "the tall fall stays whole")
	assert_gte(lv[3] - lv[4], WaterFalls.FALL_MIN_DROP_M - 1e-9, "the ankle fall stays a fall")
	assert_almost_eq(lv[5] - lv[6], 0.2, 1e-9, "a step across a pinned cut is not pooled")


func test_fit_merges_short_reaches_but_not_across_falls() -> void:
	var t := PackedFloat64Array([5.0, 4.0, 4.0, 3.0, 0.0])
	var lengths := PackedFloat64Array([6.0, 0.8, 6.0, 0.8, 6.0])
	var fit := _fit(t, lengths, PackedByteArray(), {})
	assert_gt(fit.levels[3] - fit.levels[4], 2.0, "the 3 m fall below the short reach stays")
	assert_lt(fit.blocks.size(), 5, "a short reach merged away")


func test_cap_envelope_removes_a_hump() -> void:
	var t := PackedFloat64Array([5.0, 4.9, 6.5, 6.4, 3.0])
	var lv: PackedFloat64Array = _fit(t, _lengths(5, 4.0), PackedByteArray(), {}).levels
	for i in range(1, 5):
		assert_lte(lv[i], lv[i - 1] + 1e-9, "no climb at %d" % i)
	assert_lte(lv[2], 5.0, "the hump is cut down to the water upstream of it")


func test_explicit_levels_are_the_targets_and_are_reported() -> void:
	# The author set levels that climb (a bad gesture): they are fitted, and the move is reported.
	var t := PackedFloat64Array([4.0, 4.3, 4.2, 3.0])
	var caps := PackedFloat64Array([INF, INF, INF, INF])
	var lengths := _lengths(4, 5.0)
	var fit := WaterConditioner.fit_levels(lengths, t, caps, PackedByteArray(), {"min_len": 0.0})
	assert_gt(fit.moved, 0.0, "something moved")
	assert_lte(fit.levels[1], fit.levels[0] + 1e-9, "no climb")
	assert_lt(fit.moved, WaterConditioner.NUDGE_CAP_M, "within the nudge cap")


func test_profile_form_over_stations() -> void:
	var arc := PackedFloat32Array()
	var ground := PackedFloat32Array()
	for i in 60:
		arc.append(i * 0.25)
		ground.append(5.0 - 0.05 * i + 0.15 * sin(i * 0.9))
	var fit := WaterConditioner.fit_profile(arc, ground)
	assert_eq(fit.levels.size(), 60, "a level per station")
	for i in range(1, 60):
		assert_lte(fit.levels[i], fit.levels[i - 1] + 1e-9, "never climbs")
		assert_lte(fit.levels[i], ground[i] - WaterGeometry.FREEBOARD_M + 0.05, "under its banks")


# --- the tree solver ----------------------------------------------------------------------------


func test_tree_solver_pools_pins_and_is_idempotent() -> void:
	# 0 pond (pinned, 5.0); 1 reach 5.2 into it; 2 reach 7.0 (a fall above 1); 3 tributary 6.9
	# into 2; 4 reach 6.0 into 3 (it would have to climb: 3 is 0.9 above it).
	var lv := PackedFloat64Array([5.0, 5.2, 7.0, 6.9, 6.0])
	var parent := PackedInt32Array([-1, 0, 1, 2, 3])
	var pinned := PackedByteArray([1, 0, 0, 0, 0])
	var fit := WaterConditioner.solve_tree(lv, parent, pinned)
	var out: PackedFloat64Array = fit.levels
	assert_eq(out[0], 5.0, "the pond keeps its level bit for bit")
	assert_eq(out[1], 5.0, "the reach within the dead band of the pond pools into its level")
	for i in range(1, 5):
		assert_gte(out[i] - out[parent[i]], -1e-9, "node %d is not below its outlet" % i)
	assert_eq(out[3], out[4], "the climbing tributary pooled")
	var again := WaterConditioner.solve_tree(out, parent, pinned)
	assert_eq(out, again.levels, "idempotent")


func test_tree_solver_keeps_pinned_conflicts_as_data() -> void:
	# Two ponds, the upper one below the lower: unfixable, reported, nothing moves.
	var fit := WaterConditioner.solve_tree(
		PackedFloat64Array([5.0, 4.0]), PackedInt32Array([-1, 0]), PackedByteArray([1, 1])
	)
	assert_eq(fit.conflicts.size(), 1, "one conflict")
	assert_eq(fit.changed, 0, "no pond moved")


# --- the course -----------------------------------------------------------------------------------


func _jitter_line(sigma: float, seed_value: int) -> Array:
	var pts := Cases.jittered(Vector2(-13, 1), Vector2(13, -1), 0.3, sigma, seed_value)
	var widths := PackedFloat32Array()
	widths.resize(pts.size())
	widths.fill(1.0)
	return [pts, widths]


func test_course_moves_a_jittery_line_within_the_cap_and_keeps_its_ends() -> void:
	var line := _jitter_line(0.3, 5)
	var fit := WaterCourseFit.condition(line[0], line[1])
	assert_true(fit.changed, "a jittery line is conditioned")
	assert_eq(fit.points[0], line[0][0], "start kept")
	assert_eq(fit.points[-1], line[0][-1], "end kept")
	assert_lt(fit.max_disp, WaterCourseFit.MAX_DISP_PER_HALF_WIDTH + 0.25, "moved about the cap")
	assert_lt(fit.points.size(), line[0].size() / 3, "far fewer points")


func test_course_is_near_idempotent_and_leaves_a_clean_line_alone() -> void:
	var line := _jitter_line(0.3, 6)
	var once := WaterCourseFit.condition(line[0], line[1])
	var twice := WaterCourseFit.condition(once.points, once.widths)
	var moved := 0.0
	if twice.changed:
		moved = WaterCourseFit.hausdorff(once.points, twice.points)
	assert_lt(moved, 0.1, "a second pass moves it under 10 cm (changed=%s)" % twice.changed)
	var straight := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)])
	var clean := WaterCourseFit.condition(straight, PackedFloat32Array([1.0, 1.0, 1.0]))
	assert_false(clean.changed, "a straight line is returned as it is")


func test_course_trims_a_self_loop() -> void:
	var pts := PackedVector2Array(
		[
			Vector2(0, 0),
			Vector2(4, 0),
			Vector2(8, 0),
			Vector2(8, 3),
			Vector2(5, 3),
			Vector2(5, -2),
			Vector2(12, -2),
			Vector2(16, -2)
		]
	)
	var widths := PackedFloat32Array()
	widths.resize(pts.size())
	widths.fill(1.0)
	var fit := WaterCourseFit.condition(pts, widths)
	assert_gte(fit.loops, 1, "the loop is found")
	assert_eq(WaterCourseFit.trim_loops(fit.points, fit.widths).loops, 0, "none left")


func test_course_adds_no_tight_bends() -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := i * 0.04
		var wobble := Vector2(0.15 * sin(i * 2.3), 0.1 * cos(i * 3.1))
		pts.append(Vector2(6.0 * cos(a), 6.0 * sin(a)) + wobble)
	var widths := PackedFloat32Array()
	widths.resize(pts.size())
	widths.fill(1.0)
	var fit := WaterCourseFit.condition(pts, widths)
	assert_lte(fit.bends_after, fit.bends_before, "no new tight bends")


# --- ends -----------------------------------------------------------------------------------------


func test_end_decision_table_on_the_f4_plateau() -> void:
	var doc := Cases.make("end_near_pond", false)
	var pond: WaterBody = null
	for body in doc.water_bodies:
		if not body.is_river():
			pond = body
	var none := PackedInt32Array()
	for body in doc.water_bodies:
		if body.is_river():
			none.append(body.id)
	# The stream's end stands 1.5 m from the pond, 3.9 m above it.
	var end_at := Vector2(0, -9)
	var high := pond.level_m + 3.9
	var fall := WaterPorts.end_decision(doc, end_at, high, 1.6, false, none)
	assert_eq(fall.action, &"fall_into", "an end in reach of a lower pond becomes a fall into it")
	assert_gt(fall.displacement, 0.0, "the end moved onto the pond")
	assert_true(WaterGeometry.is_wet_at(doc, fall.target), "to a point in its water")
	var far := WaterPorts.end_decision(doc, end_at, high, 0.5, false, none)
	assert_eq(far.action, &"flag", "a narrow stream is farther than its snap distance: flagged")
	assert_eq(far.kind, &"end_near_water_below", "with a kind")
	assert_true((far.fixes as Array).has(&"carve_fall"), "and the fixes an author can take")
	var up := WaterPorts.end_decision(doc, end_at, pond.level_m - 1.0, 1.6, false, none)
	assert_eq(up.action, &"flag", "a pond above the end cannot be drained into")
	assert_eq(up.kind, &"end_below_water", "kind")
	var head := WaterPorts.end_decision(doc, end_at, high, 1.6, true, none)
	assert_eq(head.action, &"flag", "a head perched over a pond is never changed")
	assert_eq(head.kind, &"head_above_water", "kind")
	var equal := WaterPorts.end_decision(doc, end_at, pond.level_m + 0.1, 1.6, false, none)
	assert_eq(equal.action, &"join", "levels within the dead band join")
	var spring := WaterPorts.end_decision(doc, end_at, pond.level_m - 1.0, 1.6, true, none)
	assert_eq(spring.action, &"outlet", "a head at a pond that can feed it snaps as its outlet")
	var out := WaterPorts.end_decision(doc, Vector2(12, 12), 0.0, 1.6, false, none)
	assert_eq(out.action, &"none", "far from water, nothing")


# --- the plan hook ------------------------------------------------------------------


func test_the_probe_is_off_by_default_and_changes_nothing() -> void:
	assert_false(WaterEdit.CONDITION_PROBE, "the probe constant is off")
	var a := Cases.make("jitter", false)
	var b := Cases.make("jitter", false)
	assert_eq(a.water_bodies.size(), b.water_bodies.size(), "the default plan is deterministic")
	for i in a.water_bodies.size():
		assert_eq(a.water_bodies[i].level_m, b.water_bodies[i].level_m, "same levels")
		assert_eq(a.water_bodies[i].points, b.water_bodies[i].points, "same points")


func test_conditioned_plan_is_deterministic_and_never_climbs() -> void:
	for name in Cases.NAMES:
		var a := Cases.make(name, true)
		var b := Cases.make(name, true)
		assert_eq(a.water_bodies.size(), b.water_bodies.size(), "%s: same reaches" % name)
		for i in a.water_bodies.size():
			var x := a.water_bodies[i]
			var y := b.water_bodies[i]
			assert_eq(x.level_m, y.level_m, "%s: same level %d" % [name, i])
			assert_eq(x.points, y.points, "%s: same points %d" % [name, i])
			if not Cases.blocked:
				assert_true(not x.is_river() or _on_lattice(x.level_m), "%s: lattice" % name)
		if not Cases.blocked:
			assert_eq(WaterPorts.audit(a).rises, 0, "%s: no reach climbs" % name)


# --- measurements (printed) -----------------------------------------------------------


func _row(m: Dictionary) -> String:
	var head := "reaches %2d falls %d rises %d (%.2f m) tiny %d" % [
		m.reaches, m.falls, m.rises, m.rise_m, m.tiny
	]
	var field := "film %d (%.1f m) bridged %d end_near %d perched %3d field_rise %.2f wet %5d" % [
		m.film_run, m.film_m, m.bridged_run, m.end_near, m.perched, m.field_rise_m, m.wet
	]
	return "%s | %s | build %.0f ms" % [head, field, m.ms]


func _dump(doc: MapDocument) -> String:
	var parts := []
	for body in doc.water_bodies:
		if body.is_river():
			var a: Vector2 = body.points[0]
			var b: Vector2 = body.points[-1]
			parts.append("#%d %.2f (%.1f,%.1f > %.1f,%.1f)" % [body.id, body.level_m, a.x, a.y, b.x, b.y])
		else:
			parts.append("pond#%d %.2f" % [body.id, body.level_m])
	return ", ".join(parts)


func test_synthetic_cases_before_and_after() -> void:
	var worse := 0
	for name in Cases.NAMES:
		var base_doc := Cases.make(name, false)
		var base_cut := Cases.worst_cut
		var cond_doc := Cases.make(name, true)
		var cond_cut := Cases.worst_cut
		var before := Cases.metrics(base_doc)
		var after := Cases.metrics(cond_doc)
		var kept := " BLOCKED (kept as drawn, flagged)" if Cases.blocked else ""
		assert_eq(base_cut, 0.0, "an unconditioned plan reports no cut")
		gut.p("CASE %s (conditioned plan's deepest cut %.2f m)%s" % [name, cond_cut, kept])
		gut.p("   base  %s\n   cond  %s" % [_row(before), _row(after)])
		gut.p("   base levels %s\n   cond levels %s" % [_dump(base_doc), _dump(cond_doc)])
		assert_lte(after.rises, before.rises, "%s: conditioning never adds a rise" % name)
		assert_lte(after.field_rise_m, before.field_rise_m + 0.15, "%s: field climbs no more" % name)
		worse += 1 if after.film_run > before.film_run else 0
	assert_lte(worse, 1, "conditioning adds film runs in at most one case")


func test_dead_band_sweep_over_the_fuzz_maps() -> void:
	# The greedy plan's reach levels of the fuzz maps, fitted at several dead bands: reaches
	# left, falls made (steps of 0.75 m or more that were not), the largest and mean lowering.
	var chains := []
	for seed_value in FUZZ_SEEDS:
		for chain in RiverProfile.strokes(_fuzz_doc(seed_value, false).water_bodies):
			chains.append(chain)
	for dead in [0.1, 0.25, 0.35, 0.5]:
		var reaches := 0
		var before := 0
		var made := 0
		var worst := 0.0
		var total := 0.0
		var count := 0
		for chain: Array in chains:
			var lengths := PackedFloat64Array()
			var levels := PackedFloat64Array()
			var cuts := PackedByteArray()
			for k in chain.size():
				lengths.append(Cases.course_length(chain[k]))
				levels.append(chain[k].level_m)
				var next_drop := 0.0
				if k < chain.size() - 1:
					next_drop = chain[k].level_m - chain[k + 1].level_m
				cuts.append(1 if next_drop >= WaterFalls.FALL_MIN_DROP_M else 0)
			var opts := {"dead_band": dead}
			var fit := WaterConditioner.fit_levels(lengths, levels, levels, cuts, opts)
			before += chain.size()
			reaches += fit.blocks.size()
			for k in chain.size() - 1:
				var was: float = levels[k] - levels[k + 1]
				var now: float = fit.levels[k] - fit.levels[k + 1]
				made += 1 if now >= WaterFalls.FALL_MIN_DROP_M and was < WaterFalls.FALL_MIN_DROP_M else 0
			for k in chain.size():
				worst = maxf(worst, fit.lowered)
				total += levels[k] - fit.levels[k]
				count += 1
		gut.p(
			"SWEEP dead band %.2f: reaches %d -> %d, new falls %d, largest lowering %.2f m, mean %.3f m"
			% [dead, before, reaches, made, worst, total / maxf(count, 1)]
		)
	assert_gt(chains.size(), 0, "the fuzz maps have strokes")


func test_canonical_map_before_and_after() -> void:
	var doc := _canonical()
	var before := Cases.metrics(doc)
	var solved := WaterPorts.condition_doc(doc)
	var out: PackedFloat64Array = solved.levels
	var g: Dictionary = solved.graph
	gut.p(
		"CANON tree solve changed %d of %d bodies, max move %.2f m, over cap %d, conflicts %d, "
		% [solved.changed, out.size(), solved.moved, solved.over_cap, solved.conflicts.size()]
		+ "cycles %d, multi-outlet %d" % [g.cycles, g.multi_outlet.size()]
	)
	var rises := []
	for ids: PackedInt32Array in g.strokes:
		for k in ids.size() - 1:
			var a := doc.water_bodies[ids[k]]
			var b := doc.water_bodies[ids[k + 1]]
			if b.level_m > a.level_m + 0.001:
				rises.append("#%d %.2f -> #%d %.2f" % [a.id, a.level_m, b.id, b.level_m])
	gut.p("   canonical rises: %s" % ", ".join(rises))
	var copy := _canonical()
	WaterPorts.apply_levels(copy, out)
	var after := Cases.metrics(copy)
	gut.p("   base  %s\n   cond  %s" % [_row(before), _row(after)])
	assert_eq(after.rises, 0, "no stroke climbs after the solve")
	assert_lte(after.rises, before.rises, "never more rises")
	var again := WaterPorts.condition_doc(copy)
	assert_eq(again.changed, 0, "the solve is idempotent on its own output")
	gut.p("   largest move %.2f m (nudge cap %.1f m)" % [solved.moved, WaterConditioner.NUDGE_CAP_M])


func test_canonical_st_refit_after_the_films() -> void:
	# The st stroke (bodies 11..26) has three film runs (st_o). The dig-aware re-fit lowers the
	# levels the banks cannot hold; count the films after.
	var doc := _canonical()
	var chain: Array[WaterBody] = []
	for body in doc.water_bodies:
		if body.id >= 11 and body.id <= 26:
			chain.append(body)
	var t0 := Time.get_ticks_usec()
	var fit := WaterPorts.refit_stroke(doc, chain)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var films_before := _count(WaterField.build(doc).events, &"film_run")
	_set_levels(chain, fit.levels)
	var films_after := _count(WaterField.build(doc).events, &"film_run")
	gut.p(
		"CANON st refit: %d lost stations, largest level drop %.2f m, film runs %d -> %d, %.1f ms"
		% [fit.lost, fit.lowered, films_before, films_after, ms]
	)
	assert_lte(films_after, films_before, "the re-fit does not add films")


func _dig(doc: MapDocument, variant: String) -> void:
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x < -2.0 or p.x > 6.0:
				continue
			if variant == "bed" and absf(p.y) < 0.6:
				heights[doc.sample_index(x, z)] -= 1.0
			elif variant == "trench" and absf(p.y - 1.9) < 0.7:
				heights[doc.sample_index(x, z)] -= 1.5
	doc.heights = heights


func test_dig_dry_run_on_a_stream() -> void:
	# A stream down a slope, then a dig: (a) the bed under 8 m of it, (b) a trench beside it.
	for variant in ["bed", "trench"]:
		var doc := Cases.make("tiny_kink", true)
		var chain := _river_chain(doc)
		_dig(doc, variant)
		var films := _count(WaterField.build(doc).events, &"film_run")
		var t0 := Time.get_ticks_usec()
		var fit := WaterPorts.refit_stroke(doc, chain)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var wet_before: int = Cases.metrics(doc).wet
		_set_levels(chain, fit.levels)
		var after := Cases.metrics(doc)
		gut.p(
			"DIG %s: lost %d stations, films %d -> %d, level drop %.2f m, wet %d -> %d, %.1f ms"
			% [variant, fit.lost, films, after.film_run, fit.lowered, wet_before, after.wet, ms]
		)
		assert_lte(after.film_run, films, "%s: the re-fit does not add films" % variant)


func test_stability_under_redraw() -> void:
	# The same gesture drawn three times with different hand jitter: how far apart are the
	# stored levels along it.
	var rows := []
	for conditioned in [false, true]:
		var docs := []
		for seed_value in [11, 12, 13]:
			var doc := Cases.world(Cases._rolling)
			var line := Cases.jittered(Vector2(-13, 1), Vector2(13, -1), 0.3, 0.3, seed_value)
			Cases.add_stroke(doc, line, 1.0, WAIST, conditioned)
			docs.append(doc)
		var worst := 0.0
		for x in range(-11, 12, 2):
			var levels := []
			for doc in docs:
				var l := WaterGeometry.level_at(doc, Vector2(x, 0.0))
				levels.append(l if l != WaterGeometry.DRY else NAN)
			for a: float in levels:
				for b: float in levels:
					worst = maxf(worst, absf(a - b)) if is_finite(a) and is_finite(b) else worst
		var counts := docs.map(func(d: MapDocument) -> int: return d.water_bodies.size())
		rows.append(
			"REDRAW %s: levels of three redraws differ by up to %.2f m, reaches %s"
			% ["conditioned" if conditioned else "baseline", worst, str(counts)]
		)
	gut.p("\n".join(rows))
	assert_eq(rows.size(), 2, "both variants measured")


func test_costs() -> void:
	var line := _jitter_line(0.3, 5)
	var reps := 20
	var t0 := Time.get_ticks_usec()
	for _i in reps:
		WaterCourseFit.condition(line[0], line[1])
	var course_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	var doc := Cases.make("jitter", false)
	t0 = Time.get_ticks_usec()
	for _i in reps:
		WaterEdit.plan_river(doc, line[0], line[1], WAIST, 1.0, false)
	var base_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	t0 = Time.get_ticks_usec()
	for _i in reps:
		WaterEdit.plan_river(doc, line[0], line[1], WAIST, 1.0, true)
	var cond_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	var canonical := _canonical()
	t0 = Time.get_ticks_usec()
	for _i in reps:
		WaterPorts.condition_doc(canonical)
	var tree_ms := (Time.get_ticks_usec() - t0) / 1000.0 / reps
	gut.p(
		"COST ms: course fit %.2f (%d points), plan_river %.2f -> %.2f, tree solve (31 bodies) %.2f"
		% [course_ms, line[0].size(), base_ms, cond_ms, tree_ms]
	)
	assert_lt(course_ms, 50.0, "a course fit stays far under the edit budget")
	assert_lt(cond_ms - base_ms, 50.0, "so does the conditioned plan")


# --- the fuzzer ---------------------------------------------------------------------


func _fuzz_ground(rng: RandomNumberGenerator) -> Callable:
	var slope := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.12)
	var amp := rng.randf_range(0.0, 0.4)
	var wave := rng.randf_range(3.0, 9.0)
	var hill := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(0.8, 2.5))
	var has_hill := rng.randf() < 0.5
	return func(p: Vector2) -> float:
		var h := slope.dot(p) + amp * sin(p.x * TAU / wave) * cos(p.y * TAU / (wave * 1.3))
		if has_hill:
			h += hill.z * exp(-p.distance_squared_to(Vector2(hill.x, hill.y)) / 9.0)
		return h


func _fuzz_doc(seed_value: int, conditioned: bool) -> MapDocument:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	Cases.blocked = false
	var doc := Cases.world(_fuzz_ground(rng))
	var heading := rng.randf() * TAU
	var pos := Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
	var sigma := rng.randf_range(0.0, 0.4)
	var trunk := PackedVector2Array([pos])
	for _i in rng.randi_range(25, 55):
		heading += rng.randfn(0.0, 0.12)
		pos += Vector2.from_angle(heading) * 0.4
		if absf(pos.x) > 13.0 or absf(pos.y) > 13.0:
			break
		trunk.append(pos + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma)))
	if trunk.size() < 4:
		return doc
	var hw := rng.randf_range(0.6, 1.4)
	if rng.randf() < 0.4:
		var beyond := trunk[-1] + Vector2.from_angle(heading) * rng.randf_range(1.0, 3.0)
		Cases.add_pond(doc, beyond, rng.randf_range(2.0, 3.5))
	var depth := rng.randi_range(0, 2) as WaterBody.Depth
	Cases.add_stroke(doc, trunk, hw, depth, conditioned)
	if rng.randf() < 0.4 and trunk.size() > 8:
		var join := trunk[roundi(trunk.size() * rng.randf_range(0.3, 0.7))]
		var away := Vector2.from_angle(heading + rng.randf_range(0.6, 2.5))
		var start := (join + away * rng.randf_range(5.0, 9.0)).clamp(Vector2(-13, -13), Vector2(13, 13))
		var branch := PackedVector2Array([start, (start + join) * 0.5, join])
		Cases.add_stroke(doc, branch, hw * 0.7, depth, conditioned)
	return doc


func _check_tree(seed_value: int, doc: MapDocument) -> Dictionary:
	var solved := WaterPorts.condition_doc(doc)
	var g: Dictionary = solved.graph
	for i in solved.levels.size():
		var p: int = g.parent[i]
		if p >= 0:
			var gap: float = solved.levels[i] - solved.levels[p]
			assert_gte(gap, -1e-9, "seed %d: node %d does not climb" % [seed_value, i])
		if g.pinned[i] != 0:
			assert_eq(solved.levels[i], g.levels[i], "seed %d: a pond is not moved" % seed_value)
	var copy := _fuzz_doc(seed_value, true)
	WaterPorts.apply_levels(copy, solved.levels)
	assert_eq(WaterPorts.condition_doc(copy).changed, 0, "seed %d: idempotent" % seed_value)
	return solved


func test_fuzz_hydrology_invariants() -> void:
	var keys := ["rises", "rise_m", "tiny", "film_run", "film_m", "end_near", "perched"]
	var sums := {"base": {}, "cond": {}}
	for tag in sums:
		for key in keys + ["field_rise_m"]:
			sums[tag][key] = 0.0
	var tree_moved := 0.0
	var tree_changed := 0
	var blocked_maps := 0
	for seed_value in FUZZ_SEEDS:
		var cond_doc := _fuzz_doc(seed_value, true)
		var was_blocked := Cases.blocked
		var base := Cases.metrics(_fuzz_doc(seed_value, false))
		var cond := Cases.metrics(cond_doc)
		if cond.field_rise_m > 0.2:
			gut.p("FUZZ seed %d: field climbs %.2f m (base %.2f): %s" % [
				seed_value, cond.field_rise_m, base.field_rise_m, _dump(cond_doc)
			])
		for key in keys + ["field_rise_m"]:
			sums.base[key] += float(base[key])
			sums.cond[key] += float(cond[key])
		if was_blocked:
			blocked_maps += 1
		else:
			assert_eq(cond.rises, 0, "seed %d: no reach of a conditioned stroke climbs" % seed_value)
		assert_lte(cond.field_rise_m, base.field_rise_m + 0.05, "seed %d: field climbs" % seed_value)
		var again := _fuzz_doc(seed_value, true)
		assert_eq(again.water_bodies.size(), cond_doc.water_bodies.size(), "seed %d" % seed_value)
		for i in again.water_bodies.size():
			var same := again.water_bodies[i].level_m == cond_doc.water_bodies[i].level_m
			assert_true(same, "seed %d: deterministic level %d" % [seed_value, i])
		var solved := _check_tree(seed_value, cond_doc)
		tree_moved = maxf(tree_moved, solved.moved)
		tree_changed += solved.changed
	gut.p("FUZZ %d maps, summed base %s" % [FUZZ_SEEDS, str(sums.base)])
	gut.p("FUZZ %d maps, summed cond %s" % [FUZZ_SEEDS, str(sums.cond)])
	gut.p("FUZZ tree solve: %d levels moved, largest %.2f m" % [tree_changed, tree_moved])
	gut.p("FUZZ maps kept as drawn because the cut would pass the limit: %d" % blocked_maps)
