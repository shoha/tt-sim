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
	# half-width of 1 m): the smoothed course moves less than one half-width from it, and the
	# numbers are printed (the spike's cap is half a half-width after thinning).
	var doc := Cases.world(Cases._rolling)
	var line := _jitter_line()
	var report := {}
	WaterEdit.plan_river(doc, line, _widths(line, 1.0), WAIST, 1.0, true, report)
	assert_gt(float(report.max_disp), 0.0, "the course was smoothed")
	assert_lt(float(report.max_disp), 1.0, "by less than a half-width")
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
	assert_true(Cases.blocked, "kept as drawn")
	var kinds := _kinds(Cases.hints)
	assert_true(kinds.has(&"over_hill"), "over_hill: %s" % [kinds])
	var near := Cases.make("head_near_pond", true)
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
	assert_true(_kinds(editor.water.last_hints).has(&"over_hill"), "%s" % [editor.water.last_hints])
	assert_true(bool(editor.water.last_report.blocked))


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
