extends GutTest

## The conditioning pipeline as shipped (card painter-water-condition): a committed river stroke
## is conditioned once, at plan time, before the carve, and the cleaned reaches are what the
## document stores (WaterEdit.plan_river with the off switch conditioning_enabled; the report and
## its WaterHints records), through the Water tool's editor (WaterEditor.carve_river: one history
## entry, undo and redo put the stored model back, the worker computes the same carve), and a
## stored map is re-fitted only on request (WaterEdit.refit_document, WaterEditor.refit_water).
## The unit rules of the conditioner itself are test_water_conditioner.gd's.

const Cases := preload("res://tests/unit/water_condition_cases.gd")
const CANONICAL := "res://tests/fixtures/water_field_canonical.ttmap"
const WAIST := WaterBody.Depth.WAIST

var _before_enabled := true


func before_each() -> void:
	_before_enabled = WaterEdit.conditioning_enabled


func after_each() -> void:
	WaterEdit.conditioning_enabled = _before_enabled
	_mode(true, false)


## How a climbing line is resolved (WaterEdit.cut_through, stop_at_rise): the rule is the cut
## (true, false); (false, true) splits the line at its rises, (false, false) stores it as drawn.
func _mode(cut: bool, split: bool) -> void:
	WaterEdit.cut_through = cut
	WaterEdit.stop_at_rise = split


func _jitter_line() -> PackedVector2Array:
	return Cases.jittered(Vector2(-13, 1), Vector2(13, -1), 0.3, 0.3, 11)


func _widths(line: PackedVector2Array, hw: float) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	widths.resize(line.size())
	widths.fill(hw)
	return widths


func _model(bodies: Array) -> Array:
	var out := []
	for body: WaterBody in bodies:
		out.append([body.id, body.level_m, body.points, body.half_widths])
	return out


func _editor(doc: MapDocument, history: AuthoringHistory) -> AuthoringEditor:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	map.add_child(AuthoredTerrain.create(doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		map.add_child(node)
	var editor := AuthoringEditor.create(doc, map, history)
	editor.scatter.attach_document(doc)
	return editor


func _settle(editor: AuthoringEditor) -> void:
	editor.finish_height_work()
	var water := editor.map_root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	if water != null:
		water.finish_refresh()


func _kinds(hints: Array) -> Array:
	var out := []
	for hint: Dictionary in hints:
		out.append(hint.kind)
	return out


# --- plan_river with the switch on and off ----------------------------------------------------


func test_plan_river_conditions_by_default_and_the_switch_turns_it_off() -> void:
	var doc := Cases.world(Cases._rolling)
	var line := _jitter_line()
	var widths := _widths(line, 1.0)
	var on_report := {}
	var on := WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, true, on_report)
	var off := WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, false)
	assert_true(on_report.conditioned, "conditioned by default")
	assert_lt(on.size(), off.size(), "the jitter reaches are pooled")
	WaterEdit.conditioning_enabled = false
	var report := {}
	var switched := WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, true, report)
	assert_false(report.conditioned, "the off switch wins over the argument")
	assert_eq(_model(switched), _model(off), "off is the drawn plan, byte for byte")
	WaterEdit.conditioning_enabled = true
	assert_eq(
		_model(WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, true)),
		_model(on),
		"conditioning is deterministic"
	)


func test_the_gesture_stays_the_users() -> void:
	# The jitter line zigzags 0.9 m either side of its trend (sigma 0.3 m at 0.3 m spacing, a
	# half-width of 1 m). The conditioned course never strays further than half a half-width from
	# the DRAWN line (the cap is on the total displacement, WaterCourseFit.deviation), however
	# much jitter it smooths away.
	var doc := Cases.world(Cases._rolling)
	var line := _jitter_line()
	var report := {}
	var bodies := WaterEdit.plan_river(doc, line, _widths(line, 1.0), WAIST, 1.0, true, report)
	assert_gt(float(report.max_disp), 0.0, "the course was smoothed")
	assert_lte(float(report.max_disp), 0.5 + 0.02, "by at most half a half-width")
	var course := PackedVector2Array()
	for body in bodies:
		course.append_array(body.points)
	var stray := WaterCourseFit.deviation(course, line)
	assert_lte(stray, 0.5 + 0.1, "and the stored course stays near it")
	assert_gte(float(report.level_moved), 0.0)
	gut.p(
		"GESTURE max displacement %.2f m, max level change %.2f m, max cut %.2f m"
		% [report.max_disp, report.level_moved, report.max_cut]
	)


func test_stored_bytes_are_not_larger() -> void:
	var doc := Cases.world(Cases._rolling)
	var line := _jitter_line()
	var widths := _widths(line, 1.0)
	var on := WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, true)
	var off := WaterEdit.plan_river(doc, line, widths, WAIST, 1.0, false)
	var bytes := func(bodies: Array[WaterBody]) -> int:
		var copy := Cases.world(Cases._rolling)
		copy.water_bodies = bodies
		return WaterEdit.model_bytes(WaterEdit.model_of(copy))
	assert_lte(bytes.call(on), bytes.call(off), "the cleaned reaches store no more")


func test_a_climbing_stroke_reports_the_rise_it_removed() -> void:
	var doc := Cases.make("nonmonotone", true)
	assert_true(Cases.hints.is_empty() or _kinds(Cases.hints).has(&"rise_removed"))
	var report := {}
	var fresh := Cases.world(func(p: Vector2) -> float: return 1.2 * exp(-pow(p.x / 3.0, 2.0)))
	var line := PackedVector2Array([Vector2(-13, 0), Vector2(13, 0)])
	WaterEdit.plan_river(fresh, line, _widths(line, 0.9), WAIST, 1.0, true, report)
	var kinds := _kinds(report.hints)
	assert_true(kinds.has(&"rise_removed"), "the lowered rise is recorded: %s" % [kinds])
	assert_gt(doc.water_bodies.size(), 0)


func test_over_hill_and_perched_head_are_flagged_never_blocking() -> void:
	var hill := Cases.make("over_hill", true)
	assert_gt(hill.water_bodies.size(), 0, "the stroke is still made")
	var kinds := _kinds(Cases.hints)
	# The rule (card painter-water-cut): the river is cut through the ridge and says so.
	assert_true(kinds.has(&"cut_through"), "cut_through: %s" % [kinds])
	assert_false(Cases.blocked, "nothing blocks a cut")
	assert_eq(_rise(hill), 0.0, "and the water never climbs")
	# With the line split at its rises (card painter-water-climb) it is made up to the rise.
	_mode(false, true)
	Cases.make("over_hill", true)
	kinds = _kinds(Cases.hints)
	assert_true(kinds.has(&"stopped_at_rise"), "stopped_at_rise: %s" % [kinds])
	assert_false(kinds.has(&"over_hill"), "one hint per cause: %s" % [kinds])
	_mode(false, false)
	Cases.make("over_hill", true)
	assert_true(Cases.blocked, "before both rules: kept as drawn")
	assert_true(_kinds(Cases.hints).has(&"over_hill"), "over_hill: %s" % [Cases.hints])
	# The perched head's line starts up the tier's ramp, so as drawn it climbs too: the hints of
	# the plan kept as drawn are those of the rules off.
	var near := Cases.make("head_near_pond", true)
	_mode(true, false)
	assert_gt(near.water_bodies.size(), 1, "the stroke is still made")
	kinds = _kinds(Cases.hints)
	assert_true(kinds.has(&"perched_head"), "perched_head: %s" % [kinds])
	for hint: Dictionary in Cases.hints:
		assert_true(hint.has_all(["kind", "pos", "fixes", "detail"]), "a record: %s" % [hint])
	var text: String = WaterHints.toast_text(Cases.hints)
	assert_true(text.contains("You can"), "the toast says what to do: %s" % text)
	assert_true(text.contains("carve a fall"), text)


func test_a_stroke_end_near_a_pond_joins_it_and_says_so() -> void:
	var doc := Cases.make("end_near_pond", true)
	assert_gt(doc.water_bodies.size(), 1)
	assert_true(_kinds(Cases.hints).has(&"end_snapped"), "%s" % [_kinds(Cases.hints)])
	assert_eq(WaterHints.toast_text(Cases.hints), "", "a join is not worth a toast")


func test_hint_text() -> void:
	var fixes: Array[StringName] = [&"cut_ridge", &"keep"]
	var hint := WaterHints.make(&"over_hill", Vector2.ZERO, fixes)
	assert_eq(
		WaterHints.describe(hint),
		"%s You can cut the ridge with the Sculpt tool or keep it as drawn."
		% WaterHints.KIND_TEXT[&"over_hill"]
	)
	assert_eq(WaterHints.toast_text([]), "")
	assert_eq(
		WaterHints.toast_text([WaterHints.make(&"rise_removed", Vector2.ZERO)]), "", "notes are quiet"
	)


# --- through the editor -----------------------------------------------------------------------


func _carve(editor: AuthoringEditor, line: PackedVector2Array) -> int:
	return editor.water.carve_river(line, PackedFloat32Array([1.0]), WAIST)


func test_editor_carve_stores_the_conditioned_reaches_and_undoes() -> void:
	var results := []
	for worker in [false, true]:
		var doc := Cases.world(Cases._rolling)
		var history := AuthoringHistory.new()
		var editor := _editor(doc, history)
		editor.water.use_worker = worker
		var start := doc.heights.duplicate()
		var id := _carve(editor, _jitter_line())
		_settle(editor)
		assert_gt(id, 0, "carved")
		assert_eq(history.undo_count(), 1, "one entry")
		var stored := _model(doc.water_bodies)
		var expected := WaterEdit.plan_river(
			Cases.world(Cases._rolling), _jitter_line(), _widths(_jitter_line(), 1.0), WAIST
		)
		assert_eq(stored.size(), expected.size(), "the stored reaches are the conditioned plan's")
		assert_eq(WaterPorts.audit(doc).rises, 0, "nothing climbs")
		var carved := doc.heights.duplicate()
		results.append([stored, carved])
		history.undo()
		_settle(editor)
		assert_eq(doc.heights, start, "undo restores the ground")
		assert_true(doc.water_bodies.is_empty(), "and the water")
		history.redo()
		_settle(editor)
		assert_eq(doc.heights, carved, "redo restores the carve")
		assert_eq(_model(doc.water_bodies), stored, "and exactly the stored reaches")
	assert_eq(results[1][0], results[0][0], "the worker stores the same reaches")
	assert_eq(results[1][1], results[0][1], "and carves the same ground")


func test_editor_says_the_hints_and_never_blocks() -> void:
	var ridge := func(p: Vector2) -> float: return -0.05 * p.x + 2.5 * exp(-pow(p.x / 2.5, 2.0))
	var doc := Cases.world(ridge)
	var editor := _editor(doc, AuthoringHistory.new())
	var id := editor.water.carve_river(
		PackedVector2Array([Vector2(-13, 0), Vector2(13, 0)]), PackedFloat32Array([0.9]), WAIST
	)
	_settle(editor)
	assert_gt(id, 0, "a stroke over a hill is still carved")
	var said := _kinds(editor.water.last_hints)
	assert_true(said.has(&"cut_through"), "%s" % [editor.water.last_hints])
	assert_true(bool(editor.water.last_report.cut))
	assert_true(WaterHints.worth_saying(editor.water.last_hints), "worth a toast")
	assert_true(WaterHints.toast_text(editor.water.last_hints).contains("cut through"))


# --- water does not climb (card painter-water-climb) --------------------------------------------


## The largest rise of any stroke of `doc`: a reach level over the lowest level upstream of it.
func _rise(doc: MapDocument) -> float:
	var worst := 0.0
	for chain in RiverProfile.strokes(doc.water_bodies):
		var low := INF
		for body: WaterBody in chain:
			worst = maxf(worst, body.level_m - low)
			low = minf(low, body.level_m)
	return worst


## Three walls 1.6 m high across a line along z (the verdict map's stepped stream in small): a
## raised head (z under -11), then walls 2 m wide on top at z -5, 1 and 7, flat ground between.
func _walls(p: Vector2) -> float:
	var h := 1.6 * clampf(-p.y - 10.0, 0.0, 1.0)
	for z: float in [-5.0, 1.0, 7.0]:
		h = maxf(h, 1.6 * clampf(2.0 - absf(p.y - z), 0.0, 1.0))
	return h


func _count_events(doc: MapDocument, kind: StringName) -> int:
	var count := 0
	for e in WaterField.build(doc).events:
		count += 1 if e.kind == kind else 0
	return count


func test_a_stroke_over_walls_stops_at_the_rise_and_never_climbs() -> void:
	var line := PackedVector2Array([Vector2(0, -13), Vector2(0, 12)])
	# Before the rule: the blocked plan is stored as drawn, the water stands up every wall, and
	# the field says so (one `climb` event per rise).
	Cases.blocked = false
	_mode(false, false)
	var before := Cases.world(_walls)
	Cases.add_stroke(before, line, 1.0, WAIST, true)
	_mode(false, true)
	assert_true(Cases.blocked, "levelling the walls would cut a gorge: blocked")
	assert_gt(_rise(before), 1.0, "as drawn the water climbs the walls")
	assert_eq(_count_events(before, &"climb"), 3, "the field reports each climb")
	var fit := WaterEdit.refit_document(before)
	WaterEdit.apply_refit(before, fit)
	assert_eq(_count_events(before, &"climb"), 0, "a re-fit removes them")
	# With it: the longest part that runs downhill, conditioned, and nothing else.
	var doc := Cases.world(_walls)
	var ground := doc.heights.duplicate()
	var made: Dictionary = Cases.add_stroke(doc, line, 1.0, WAIST, true)
	var report: Dictionary = made.report
	assert_gt(made.bodies.size(), 0, "a river is made")
	assert_eq(_rise(doc), 0.0, "no reach stands over the water upstream of it")
	assert_eq(_count_events(doc, &"climb"), 0)
	assert_true(bool(report.stopped), "the report says the line was cut")
	assert_lt(float(report.kept_m), float(report.drawn_m) - 4.0, "part of the line was not made")
	assert_gt(float(report.kept_m), 4.0, "the part kept is a river, not a stub")
	var kinds := _kinds(report.hints)
	assert_true(kinds.has(&"stopped_at_rise"), "%s" % [kinds])
	assert_true(WaterHints.toast_text(report.hints).contains("cannot climb"), "the toast says why")
	# The author's ground is never cut for the part not made: every sample the carve lowered lies
	# within reach of the stored course.
	var reach := 6.0
	var far := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			if doc.heights[i] == ground[i]:
				continue
			var p := doc.sample_to_world(Vector2(x, z))
			var nearest := INF
			for body: WaterBody in made.bodies:
				for q in body.points:
					nearest = minf(nearest, p.distance_to(q))
			far += 1 if nearest > reach else 0
	assert_eq(far, 0, "no ground is cut away from the river that was made")


func test_a_line_drawn_up_a_ramp_starts_at_the_crest() -> void:
	# The fall spike's F4: the line starts on the tier's ramp, runs up it, across the top and
	# off the lip into the pond. As drawn the water climbed the ramp 3.4 m in nine reaches; now
	# the stream starts at the crest: the tier's top, the fall, the pond.
	_mode(false, true)
	var doc := Cases.make("head_near_pond", true)
	assert_true(_kinds(Cases.hints).has(&"stopped_at_rise"), "%s" % [_kinds(Cases.hints)])
	assert_eq(_rise(doc), 0.0)
	var rivers: Array[WaterBody] = []
	for body in doc.water_bodies:
		if body.is_river():
			rivers.append(body)
	assert_eq(rivers.size(), 2, "the top and the reach below the fall")
	assert_gt(rivers[0].level_m - rivers[1].level_m, 3.0, "the fall is kept whole")


func test_climbs_and_longest_descent() -> void:
	var levels := PackedFloat64Array([1.0, 0.6, 0.1, -0.15, 0.07, 0.47, 0.93, -0.15, 0.06])
	var found := WaterConditioner.climbs(levels)
	assert_eq(found.size(), 1, "one rise: 0.07 is within the dead band of the pool")
	assert_eq([int(found[0].from), int(found[0].to), int(found[0].low)], [5, 6, 3])
	assert_almost_eq(float(found[0].rise), 1.08, 1e-6)
	assert_eq(WaterConditioner.climbs(PackedFloat64Array([2.0, 1.0, 1.0, 0.2])).size(), 0)
	assert_eq(WaterConditioner.climbs(levels, 1e-6).size(), 2, "with no band the 0.07 counts")
	var ones := PackedFloat64Array([1, 1, 1, 1, 1, 1, 1, 1, 1])
	assert_eq(WaterConditioner.longest_descent(levels, ones), Vector2i(0, 4), "head to the pool")
	var long_top := PackedFloat64Array([1, 1, 1, 1, 1, 1, 9, 1, 1])
	assert_eq(
		WaterConditioner.longest_descent(levels, long_top), Vector2i(6, 8), "the crest heads its run"
	)
	var none := PackedFloat64Array()
	assert_eq(WaterConditioner.longest_descent(none, none), Vector2i(0, -1))


func test_monotone_parts() -> void:
	var levels := PackedFloat64Array([1.0, 0.6, 0.1, -0.15, 0.07, 0.47, 0.93, -0.15, 0.06])
	var want: Array[Vector3i] = [Vector3i(0, 4, -1), Vector3i(5, 5, 1), Vector3i(6, 8, -1)]
	assert_eq(WaterConditioner.monotone_parts(levels), want, "down, the climb between, down")
	var step_up := PackedFloat64Array([2.0, 0.0, 1.5, 0.0])
	want = [Vector3i(0, 1, -1), Vector3i(2, 3, -1)]
	assert_eq(WaterConditioner.monotone_parts(step_up), want, "one step up is no part of its own")
	var uphill := PackedFloat64Array([0.0, 0.1, 0.8, 1.6])
	want = [Vector3i(0, 3, 1)]
	assert_eq(WaterConditioner.monotone_parts(uphill), want, "a line drawn uphill is one climb")
	var ends_up := PackedFloat64Array([2.0, 0.0, 0.7, 1.4])
	want = [Vector3i(0, 1, -1), Vector3i(2, 3, 1)]
	assert_eq(WaterConditioner.monotone_parts(ends_up), want, "a climb at the end keeps its crest")
	var downhill := PackedFloat64Array([2.0, 1.0, 1.1, 0.2])
	want = [Vector3i(0, 3, -1)]
	assert_eq(WaterConditioner.monotone_parts(downhill), want)
	assert_eq(WaterConditioner.monotone_parts(PackedFloat64Array()).size(), 0)


# --- a river cuts through a rise (card painter-water-cut) ---------------------------------------


func _wall(p: Vector2, at: float, height: float) -> float:
	return height * clampf((2.0 - absf(p.y - at)) / 1.2, 0.0, 1.0)


## Plans and carves `line` (along z at x = 0) over `ground` and checks the rule: ONE river along
## the drawn line, its stored levels never climbing (the conditioner's own climbs(), band 0), no
## `climb` event, water in the channel all the way, and the hint that says it was cut.
func _cut_through(ground: Callable, line: PackedVector2Array, label: String) -> Dictionary:
	var doc := Cases.world(ground)
	var start := doc.heights.duplicate()
	var made: Dictionary = Cases.add_stroke(doc, line, 1.0, WAIST, true)
	var report: Dictionary = made.report
	var strokes: Array = RiverProfile.strokes(doc.water_bodies)
	assert_eq(strokes.size(), 1, "%s: one river" % label)
	var levels := PackedFloat64Array()
	var first: Vector2 = made.bodies[0].points[0]
	var last: Vector2 = made.bodies[-1].points[-1]
	for b in made.bodies.size():
		var body: WaterBody = made.bodies[b]
		levels.append(body.level_m)
		for p in body.points:
			assert_lt(absf(p.x), 1.0, "%s: the course stays on the drawn line" % label)
			var inside := minf(p.distance_to(first), p.distance_to(last)) > 4.0
			# Below a step the bed is the riffle, under the sheet that runs down from the reach above.
			var on_riffle: bool = b > 0 and p.distance_to(body.points[0]) < 3.0
			var level: float = made.bodies[b - 1].level_m if on_riffle else body.level_m
			if inside and WaterGeometry.ground_at(doc, p) >= level:
				fail_test("%s: the channel is dry at %s" % [label, p])
	assert_eq(WaterConditioner.climbs(levels, 0.0).size(), 0, "%s: no level climbs" % label)
	assert_eq(_count_events(doc, &"climb"), 0, "%s: no climb event" % label)
	assert_gt(first.distance_to(last), line[0].distance_to(line[-1]) - 2.5, "%s: whole line" % label)
	assert_false(bool(report.blocked), "%s: never blocked" % label)
	assert_false(report.has("rest"), "%s: never split" % label)
	return {"doc": doc, "report": report, "bodies": made.bodies, "start": start}


func test_a_line_over_rises_is_one_river_cut_through_them() -> void:
	var line := PackedVector2Array([Vector2(0, -13), Vector2(0, 12)])
	var grounds := {
		"one wall": func(p: Vector2) -> float: return -0.03 * p.y + _wall(p, 0.0, 1.6),
		"three walls": _walls,
		"mound": func(p: Vector2) -> float: return -0.03 * p.y + 2.0 * exp(-p.length_squared() / 9.0),
		"long hill": func(p: Vector2) -> float: return -0.03 * p.y + 3.0 * exp(-pow(p.y / 7.0, 2.0)),
	}
	for label: String in grounds:
		var made := _cut_through(grounds[label], line, label)
		var report: Dictionary = made.report
		assert_true(bool(report.cut), "%s: the report says it cut" % label)
		assert_gt(float(report.rise_cut), 1.4, "%s: the rise it cut through" % label)
		var text: String = WaterHints.toast_text(report.hints)
		assert_true(text.contains("cut through"), "%s: the toast says so: %s" % [label, text])
		assert_almost_eq(made.bodies[0].points[0].y, -13.0, 0.01, "%s: drawn direction" % label)


func test_a_rise_at_the_map_edge_is_cut_and_the_river_runs_off() -> void:
	var ground := func(p: Vector2) -> float: return -0.03 * p.y + _wall(p, 12.5, 1.5)
	var line := PackedVector2Array([Vector2(0, 2), Vector2(0, 15)])
	var made := _cut_through(ground, line, "edge")
	assert_true(bool(made.report.cut))
	var doc: MapDocument = made.doc
	var last: WaterBody = made.bodies[-1]
	assert_almost_eq(last.points[-1].y, 15.0, 0.01, "the river ends on the map edge")
	# The wall is cut down to the water right up to the edge: no sill left to dam the exit.
	var at_edge := WaterGeometry.ground_at(doc, Vector2(0.0, 14.5))
	assert_lt(at_edge, last.level_m, "the bed at the edge is under the water")


func test_a_line_drawn_low_to_high_runs_down_from_its_high_end() -> void:
	# The direction rule: the flow follows the ends' ground. A line whose last point stands a
	# fall's height or more over its first is turned round (as every line drawn uphill always
	# was), so the whole line is not dug as a trench at its low start's level.
	var slope := func(p: Vector2) -> float: return 0.12 * p.y
	var line := PackedVector2Array([Vector2(0, -12), Vector2(0, 12)])
	var made := _cut_through(slope, line, "uphill")
	assert_almost_eq(made.bodies[0].points[0].y, 12.0, 0.01, "the source is the high end")
	assert_false(bool(made.report.cut), "a plain slope is not cut")
	assert_lt(float(made.report.rise_cut), WaterEdit.CUT_SAID_M)
	# With a wall on that slope the line still runs down from the top, through the wall.
	var walled := func(p: Vector2) -> float: return 0.12 * p.y + _wall(p, 0.0, 1.6)
	made = _cut_through(walled, line, "uphill over a wall")
	assert_almost_eq(made.bodies[0].points[0].y, 12.0, 0.01)
	assert_true(bool(made.report.cut))


func test_cut_banks_stand_sloped_and_uneven_and_leave_other_strokes_alone() -> void:
	var line := PackedVector2Array([Vector2(0, -13), Vector2(0, 12)])
	var tall := func(p: Vector2) -> float:
		return -0.03 * p.y + 6.0 * clampf((4.0 - absf(p.y)) / 2.5, 0.0, 1.0)
	var steepest := {}
	var spread := 0.0
	for banks: bool in [true, false]:
		WaterCarve.cut_banks = banks
		var doc := Cases.world(tall)
		Cases.add_stroke(doc, line, 1.0, WAIST, true)
		# Across the cut at the wall's crest (z = 0): the steepest step between samples 0.5 m apart.
		var worst := 0.0
		var heights := PackedFloat32Array()
		for k in range(-28, 29):
			heights.append(WaterGeometry.ground_at(doc, Vector2(k * 0.5, 0.0)))
			if heights.size() > 1:
				worst = maxf(worst, absf(heights[-1] - heights[-2]) / 0.5)
		steepest[banks] = worst
		if banks:
			# Uneven: at one distance from the line the two sides and two stations differ.
			var low := INF
			var high := -INF
			for q in [Vector2(-4, -0.75), Vector2(4, -0.75), Vector2(-4, 0.75), Vector2(4, 0.75)]:
				var h := WaterGeometry.ground_at(doc, q as Vector2)
				low = minf(low, h)
				high = maxf(high, h)
			spread = high - low
	WaterCarve.cut_banks = true
	gut.p(
		"CUT banks: steepest across %.2f (ordinary banks %.2f), spread %.2f m"
		% [steepest[true], steepest[false], spread]
	)
	assert_lt(float(steepest[true]), 2.0, "the cut's banks stand at a slope, not a slot")
	assert_gt(float(steepest[false]), 3.0, "the ordinary banks ended in a wall at their reach")
	assert_gt(spread, 0.1, "the two sides are not ruled copies")
	# A stroke that crosses no rise is carved exactly as before: no cut, the same goals.
	var plain := Cases.world(Cases._rolling)
	var bodies := WaterEdit.plan_river(plain, _jitter_line(), _widths(_jitter_line(), 1.0), WAIST)
	var profile := RiverProfile.for_doc(plain, bodies)
	assert_true(WaterCarve.cut_stations(plain, profile, plain.heights).is_empty(), "no rise, no cut")
	var with := WaterCarve.river_goals(plain, bodies, plain.heights)
	WaterCarve.cut_banks = false
	var without := WaterCarve.river_goals(plain, bodies, plain.heights)
	WaterCarve.cut_banks = true
	assert_eq(with.rect, without.rect)
	assert_eq(with.goals, without.goals, "bit for bit the ordinary carve")


func test_a_cut_is_one_history_entry_and_says_so_when_it_lands() -> void:
	for worker in [false, true]:
		var doc := Cases.world(_walls)
		var history := AuthoringHistory.new()
		var editor := _editor(doc, history)
		editor.water.use_worker = worker
		watch_signals(editor.water)
		var start := doc.heights.duplicate()
		var id := _carve(editor, PackedVector2Array([Vector2(0, -13), Vector2(0, 12)]))
		_settle(editor)
		assert_gt(id, 0, "carved")
		assert_signal_emitted(editor.water, "river_hints_landed")
		assert_true(_kinds(editor.water.last_hints).has(&"cut_through"))
		assert_eq(history.undo_count(), 1, "one entry for the river and its cut")
		assert_eq(RiverProfile.strokes(doc.water_bodies).size(), 1, "one river")
		assert_eq(_rise(doc), 0.0)
		assert_lt(WaterGeometry.ground_at(doc, Vector2(0, 1)), 0.0, "the middle wall is cut")
		var carved := doc.heights.duplicate()
		history.undo()
		_settle(editor)
		assert_eq(doc.heights, start, "undo restores the walls")
		assert_true(doc.water_bodies.is_empty(), "and removes the river")
		history.redo()
		_settle(editor)
		assert_eq(doc.heights, carved, "redo cuts them again")


func test_a_refit_cuts_a_stored_climb_and_never_turns_a_stream_round() -> void:
	var line := PackedVector2Array([Vector2(0, -13), Vector2(0, 12)])
	_mode(false, false)
	var doc := Cases.world(_walls)
	Cases.add_stroke(doc, line, 1.0, WAIST, true)
	_mode(true, false)
	assert_gt(_rise(doc), 1.0, "stored as drawn, the water climbs the walls")
	var heads := []
	for body in doc.water_bodies:
		heads.append(body.points[0])
	var fit := WaterEdit.refit_document(doc)
	assert_eq(int(fit.reversed), 0)
	assert_gte(int(fit.cut), 1)
	WaterEdit.apply_refit(doc, fit)
	assert_eq(_rise(doc), 0.0, "no reach stands over the water upstream of it")
	assert_eq(_count_events(doc, &"climb"), 0)
	for i in doc.water_bodies.size():
		assert_eq(doc.water_bodies[i].points[0], heads[i], "reach %d keeps its direction" % i)
	assert_lt(WaterGeometry.ground_at(doc, Vector2(0, 1)), doc.water_bodies[-1].level_m + 0.5, "cut")


func test_points_drawn_on_a_rise_land_where_the_author_pointed() -> void:
	# A wall 3 m high across the line, seen along a ray that runs 1 m across (along -x) per metre
	# it descends: the pointer met the wall's top 3 m short of the ground behind it.
	var ground := func(p: Vector2) -> float: return 3.0 * clampf((2.0 - absf(p.y)) / 1.0, 0.0, 1.0)
	var slant := func(_at: Vector3) -> Vector2: return Vector2(1.0, 0.0)
	var hits := PackedVector2Array()
	for k in range(-20, 21):
		var z := k * 0.5
		hits.append(Vector2(-float(ground.call(Vector2(0.0, z))), z))
	var seen := func(p: Vector2) -> float: return ground.call(Vector2(0.0, p.y))
	var out := WaterBrush.through_rises(hits, seen, slant)
	for i in out.size():
		var high: bool = float(seen.call(hits[i])) >= WaterCarve.CUT_FROM_M
		if high or is_zero_approx(hits[i].x):
			assert_almost_eq(out[i].x, 0.0, 1e-4, "point %d lies on the line as seen" % i)
	var down := func(p: Vector2) -> float: return -0.2 * p.y
	var straight := PackedVector2Array([Vector2(0, -5), Vector2(0, 0), Vector2(0, 5)])
	assert_eq(WaterBrush.through_rises(straight, down, slant), straight, "no rise, no move")
	assert_eq(WaterBrush.through_rises(hits, seen, Callable()), hits, "no view, no move")


func test_a_gesture_over_walls_lands_every_part_in_one_entry() -> void:
	# Card painter-water-climb-2: the author's gesture is not lost. The line over three walls lands
	# as several streams, each running down from a crest, in ONE history entry.
	var line := PackedVector2Array([Vector2(0, -13), Vector2(0, 12)])
	_mode(false, true)
	var single := Cases.world(_walls)
	var one: Dictionary = Cases.add_stroke(single, line, 1.0, WAIST, true)
	assert_gt((one.report.rest as Array).size(), 1, "the plan lists the line's other parts")
	for worker in [false, true]:
		var doc := Cases.world(_walls)
		var history := AuthoringHistory.new()
		var editor := _editor(doc, history)
		editor.water.use_worker = worker
		var ground := doc.heights.duplicate()
		var id := editor.water.carve_river(line, PackedFloat32Array([1.0]), WAIST)
		_settle(editor)
		assert_gt(id, 0, "carved")
		assert_eq(history.undo_count(), 1, "one entry for the whole gesture")
		var strokes := RiverProfile.strokes(doc.water_bodies)
		var pieces := int(editor.water.last_report.pieces)
		gut.p(
			(
				"walls gesture: %d parts landed, %d strokes, %.1f m dropped, kept %.1f of %.1f m"
				% [
					pieces,
					strokes.size(),
					float(editor.water.last_report.dropped_m),
					float(editor.water.last_report.kept_m),
					float(editor.water.last_report.drawn_m)
				]
			)
		)
		assert_gt(pieces, 1, "more than the longest part lands")
		assert_gt(doc.water_bodies.size(), one.bodies.size(), "more water than the one part")
		assert_eq(_rise(doc), 0.0, "no reach of any part stands over the water upstream of it")
		assert_eq(_count_events(doc, &"climb"), 0, "the field reports no climb")
		# No ground cut: nothing is lowered by more than a channel's own depth below the walls.
		var deepest := 0.0
		for i in doc.heights.size():
			deepest = maxf(deepest, ground[i] - doc.heights[i])
		var alone := 0.0
		for i in single.heights.size():
			alone = maxf(alone, ground[i] - single.heights[i])
		gut.p("deepest carve: the gesture %.2f m, its longest part alone %.2f m" % [deepest, alone])
		assert_lt(deepest, alone + 0.5, "no part cuts deeper than a fall's own pool: no gorge")
		# Pools at the feet are one level: every part that ends in a valley ends at the same water.
		var feet := {}
		for chain in strokes:
			var last: WaterBody = chain[chain.size() - 1]
			var end: Vector2 = last.points[last.points.size() - 1]
			for z: float in [-8.0, -2.0, 4.0]:
				if absf(end.y - z) < 2.0:
					if feet.has(z):
						assert_almost_eq(last.level_m, float(feet[z]), 0.01, "one pool at z %.0f" % z)
					feet[z] = last.level_m
		history.undo()
		_settle(editor)
		assert_eq(doc.heights, ground, "one undo restores the ground")
		assert_true(doc.water_bodies.is_empty(), "and removes every part")
		history.redo()
		_settle(editor)
		assert_eq(RiverProfile.strokes(doc.water_bodies).size(), strokes.size(), "redo lands them")


# --- re-fitting a stored document ---------------------------------------------------------------


func _row(m: Dictionary) -> String:
	return (
		"rises %d film %d bridged %d perched %d field_rise %.2f wet %d"
		% [m.rises, m.film_run, m.bridged_run, m.perched, m.field_rise_m, m.wet]
	)


func _canonical() -> MapDocument:
	return MapDocumentIO.read(CANONICAL).get("document")


func test_refit_document_cleans_the_canonical_map() -> void:
	var doc := _canonical()
	var before := Cases.metrics(doc)
	var bodies_before := _model(doc.water_bodies)
	var fit := WaterEdit.refit_document(doc)
	assert_eq(_model(doc.water_bodies), bodies_before, "refit_document does not touch the document")
	assert_gt(int(fit.before.rises), 0, "the canonical map stores rises")
	assert_eq(int(fit.after.rises), 0, "none after")
	assert_eq(int(fit.reversed), 0, "a re-fit never turns a stream round")
	assert_gte(int(fit.cut), 1, "the chains stored rising downstream are cut through instead")
	assert_true(_kinds(fit.hints).has(&"cut_through"), "and said: %s" % [_kinds(fit.hints)])
	assert_eq(fit.bodies.size(), doc.water_bodies.size(), "no body added or lost")
	for i in doc.water_bodies.size():
		if not doc.water_bodies[i].is_river():
			assert_eq(fit.bodies[i].level_m, doc.water_bodies[i].level_m, "ponds never move")
	WaterEdit.apply_refit(doc, fit)
	var after := Cases.metrics(doc)
	gut.p(
		"REFIT canonical: reversed %d, changed %d, max move %.2f m"
		% [fit.reversed, fit.changed, fit.moved]
	)
	gut.p("   before %s" % [_row(before)])
	gut.p("   after  %s" % [_row(after)])
	assert_eq(after.rises, 0)
	assert_lte(after.field_rise_m, before.field_rise_m + 0.01, "the field climbs no more")
	var again := WaterEdit.refit_document(doc)
	assert_eq(int(again.changed), 0, "a second re-fit changes nothing")
	assert_eq(int(again.reversed), 0)


func test_reverse_chain_turns_points_widths_and_skirt_courses() -> void:
	var a := WaterBody.river(
		1, PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]), PackedFloat32Array([1.0, 2.0]), WAIST, 5.0
	)
	var b := WaterBody.river(
		2, PackedVector2Array([Vector2(1, 0), Vector2(2, 0)]), PackedFloat32Array([2.0, 3.0]), WAIST, 6.0
	)
	a.beyond_up = PackedVector2Array([Vector2(-1, 0)])
	b.beyond = PackedVector2Array([Vector2(3, 0)])
	var chain: Array[WaterBody] = [a, b]
	WaterRefit.reverse_chain(chain)
	assert_eq(chain[0], b, "the order flips")
	assert_eq(b.points, PackedVector2Array([Vector2(2, 0), Vector2(1, 0)]))
	assert_eq(b.half_widths, PackedFloat32Array([3.0, 2.0]))
	assert_eq(b.beyond_up, PackedVector2Array([Vector2(3, 0)]), "the skirt course follows its end")
	assert_eq(a.beyond, PackedVector2Array([Vector2(-1, 0)]))
	assert_eq(a.points[0], Vector2(1, 0))
	assert_eq(RiverProfile.strokes([a, b] as Array[WaterBody]).size(), 1, "still one stroke")


func test_refit_water_is_one_undoable_edit() -> void:
	# A stroke stored rising downstream (as the canonical chains are), re-fitted through the editor.
	var doc := Cases.world(Cases._rolling)
	var history := AuthoringHistory.new()
	var editor := _editor(doc, history)
	WaterEdit.conditioning_enabled = false
	var line := PackedVector2Array([Vector2(13, 0), Vector2(-13, 0)])
	_carve(editor, line)
	_settle(editor)
	WaterEdit.conditioning_enabled = true
	var drawn := _model(doc.water_bodies)
	var carved := doc.heights.duplicate()
	var rises: int = WaterPorts.audit(doc).rises
	assert_true(editor.water.refit_water(), "something to re-fit")
	_settle(editor)
	assert_eq(history.undo_count(), 2, "one more entry")
	assert_lte(WaterPorts.audit(doc).rises, rises, "no more rises")
	var refitted := _model(doc.water_bodies)
	var ground := doc.heights.duplicate()
	history.undo()
	_settle(editor)
	assert_eq(_model(doc.water_bodies), drawn, "undo puts the drawn water back")
	assert_eq(doc.heights, carved, "and the ground")
	history.redo()
	_settle(editor)
	assert_eq(_model(doc.water_bodies), refitted, "redo")
	assert_eq(doc.heights, ground)
	var empty := _editor(Cases.world(func(_p: Vector2) -> float: return 0.0), AuthoringHistory.new())
	assert_false(empty.water.refit_water(), "no rivers, no re-fit")
