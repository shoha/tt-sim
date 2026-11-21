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
	# It climbs the ridge as drawn, so it is made up to the rise (water does not climb, below).
	assert_true(kinds.has(&"stopped_at_rise"), "stopped_at_rise: %s" % [kinds])
	assert_false(kinds.has(&"over_hill"), "one hint per cause: %s" % [kinds])
	WaterEdit.stop_at_rise = false
	Cases.make("over_hill", true)
	WaterEdit.stop_at_rise = true
	assert_true(Cases.blocked, "before that rule: kept as drawn")
	assert_true(_kinds(Cases.hints).has(&"over_hill"), "over_hill: %s" % [Cases.hints])
	# The perched head's line starts up the tier's ramp, so as drawn it climbs too: the hints of
	# the plan kept as drawn are those of the rule off.
	WaterEdit.stop_at_rise = false
	var near := Cases.make("head_near_pond", true)
	WaterEdit.stop_at_rise = true
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
	assert_true(said.has(&"stopped_at_rise"), "%s" % [editor.water.last_hints])
	assert_true(bool(editor.water.last_report.stopped))
	assert_true(WaterHints.worth_saying(editor.water.last_hints), "worth a toast")


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
	WaterEdit.stop_at_rise = false
	var before := Cases.world(_walls)
	Cases.add_stroke(before, line, 1.0, WAIST, true)
	WaterEdit.stop_at_rise = true
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
	assert_gte(int(fit.reversed), 1, "the chains stored rising downstream are reversed")
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
