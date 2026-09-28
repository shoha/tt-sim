extends GutTest

## The Water tool (phase 4, P4-4): the drawn line's capture and smoothing, width clamps per
## depth class, the confluence rule, pond extension, erasing whole reaches, the tool on a
## dressed map, one history entry per gesture, the worker carve landing exactly what the
## synchronous one does, the soft pond shore and the rounded river ends.

const DEPTHS: Array[WaterBody.Depth] = [
	WaterBody.Depth.ANKLE, WaterBody.Depth.WAIST, WaterBody.Depth.DEEP
]

var _maps: Array[Node3D] = []


func _new_doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


## An editor over `doc` on a new map root with an AuthoredTerrain, scatter and props.
func _editor(doc: MapDocument, history: AuthoringHistory = null) -> AuthoringEditor:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	_maps.append(map)
	map.add_child(AuthoredTerrain.create(doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		map.add_child(node)
	var editor := AuthoringEditor.create(
		doc, map, history if history != null else AuthoringHistory.new()
	)
	editor.scatter.attach_document(doc)
	return editor


func _settle(editor: AuthoringEditor) -> void:
	editor.finish_height_work()
	var water := editor.map_root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	if water != null:
		water.finish_refresh()


func _line(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p[0], p[1]))
	return out


func _w(half_width: float) -> PackedFloat32Array:
	return PackedFloat32Array([half_width])


func _model(doc: MapDocument) -> Array:
	var out := []
	for body in doc.water_bodies:
		out.append([body.id, body.kind, body.depth, body.level_m, body.points, body.half_widths])
	return [out, doc.pond_mask]


func _pond(editor: AuthoringEditor, depth: WaterBody.Depth, dabs: Array, radius: float) -> bool:
	var first: Vector2 = dabs[0]
	if not editor.water.paint_pond_begin(depth, Vector3(first.x, 0, first.y)):
		return false
	var last := first
	for p: Vector2 in dabs:
		editor.stroke_dab(Vector3(last.x, 0, last.y), Vector3(p.x, 0, p.y), radius, 0.1)
		last = p
	return editor.end_stroke()


# --- the drawn line --------------------------------------------------------------------------


func test_the_line_is_decimated_by_distance_and_smoothed_keeping_its_ends() -> void:
	var line := PackedVector2Array()
	# A shaky hand: a point every 0.1 m with a 5 cm jitter.
	for k in 100:
		var jitter := 0.05 * (1.0 if k % 2 == 0 else -1.0)
		line = WaterBrush.decimate(line, Vector2(k * 0.1, jitter), WaterBrush.RIVER_DECIMATE_M)
	assert_eq(line[0], Vector2(0.0, 0.05), "the press is the first point")
	for i in line.size() - 1:
		assert_gte(line[i].distance_to(line[i + 1]), WaterBrush.RIVER_DECIMATE_M - 1e-4)
	assert_lt(line.size(), 20, "decimated")
	var smooth := WaterBrush.smooth_line(line)
	assert_eq(smooth[0], line[0], "the smoothed line starts where the press was")
	assert_eq(smooth[-1], line[-1], "and ends where the pointer was")
	var worst := 0.0
	for p in smooth.slice(1, smooth.size() - 1):
		worst = maxf(worst, absf(p.y))
	assert_lte(worst, 0.05 + 1e-6, "smoothing never exaggerates the jitter")
	var zigzag := WaterBrush.smooth_line(_line([[0, 0], [1, 1], [2, -1], [3, 1], [4, 0]]))
	for p in zigzag.slice(1, zigzag.size() - 1):
		assert_lt(absf(p.y), 1.0, "and softens every corner")
	assert_almost_eq(WaterBrush.line_length(_line([[0, 0], [3, 4], [3, 5]])), 6.0, 1e-5)


func test_the_readout_says_shape_depth_and_length() -> void:
	var text := WaterBrush.readout(
		WaterBrush.Shape.RIVER, WaterBody.Depth.WAIST, 12.2, 1.524, 5.0, "ft"
	)
	assert_eq(text, "River  Waist  40 ft")
	var pond := WaterBrush.readout(
		WaterBrush.Shape.POND, WaterBody.Depth.DEEP, 0.0, 1.524, 5.0, "ft"
	)
	assert_eq(pond, "Pond  Deep")
	var brush := WaterBrush.new()
	assert_eq(brush.readout_text(true, 1.524, 5.0, "ft"), "Erase water", "Ctrl held")


func test_width_clamps_to_the_narrowest_channel_of_each_depth() -> void:
	for depth in DEPTHS:
		var narrowest := WaterCarve.min_half_width(depth)
		assert_almost_eq(WaterBrush.radius_for(0.1, depth), narrowest, 1e-5)
		assert_almost_eq(WaterBrush.radius_for(20.0, depth), WaterBody.MAX_HALF_WIDTH_M, 1e-5)
		assert_almost_eq(WaterBrush.radius_for(5.0, depth), maxf(5.0, narrowest), 1e-5)
	# The brush itself may be narrower in the Water tool than the other tools allow.
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.set_mode(BrushTool.Mode.WATER)
	tool.water.depth = WaterBody.Depth.ANKLE
	tool.set_radius(0.3)
	assert_almost_eq(tool.water_radius(), WaterCarve.min_half_width(WaterBody.Depth.ANKLE), 1e-5)
	tool.water.depth = WaterBody.Depth.DEEP
	assert_almost_eq(tool.water_radius(), WaterCarve.min_half_width(WaterBody.Depth.DEEP), 1e-5)
	tool.set_mode(BrushTool.Mode.BIOME)
	assert_almost_eq(tool.get_radius(), BrushTool.MIN_RADIUS, 1e-5, "other tools start at 1 m")
	tool.set_radius(BrushTool.DEFAULT_RADIUS)
	assert_almost_eq(WaterCarve.min_half_width(WaterBody.Depth.ANKLE), 0.44, 0.01)
	assert_almost_eq(WaterCarve.min_half_width(WaterBody.Depth.WAIST), 1.33, 0.01)
	assert_almost_eq(WaterCarve.min_half_width(WaterBody.Depth.DEEP), 2.96, 0.01)


func test_the_pane_has_shape_and_depth_tiles_and_no_numbers_in_the_main_flow() -> void:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	var pane := panel.water_pane
	for id in [&"water_river", &"water_pond"]:
		assert_true(pane.shape_field.tiles.has_tile(id))
	for id in [&"water_ankle", &"water_waist", &"water_deep"]:
		assert_true(pane.depth_field.tiles.has_tile(id))
	assert_eq(pane.shape_field.tiles.selected, &"water_river", "River preselected")
	assert_eq(pane.depth_field.tiles.selected, &"water_waist", "waist deep preselected")
	var hint: Label = pane.get_node("WaterDepthHint")
	assert_string_contains(hint.text, "wade")
	var picked := []
	panel.water_depth_selected.connect(func(depth: int) -> void: picked.append(depth))
	(pane.depth_field.tiles.get_node("water_deep") as Button).toggled.emit(true)
	assert_eq(picked, [WaterBody.Depth.DEEP], "a depth tile says which")
	assert_string_contains(hint.text, "swim")
	var advanced: Foldout = pane.get_node("WaterAdvanced")
	assert_false(advanced.expanded, "exact width and flow are folded away")


# --- confluence --------------------------------------------------------------------------------


func test_a_river_ending_in_a_river_joins_it_at_its_level() -> void:
	var doc := _new_doc()
	var editor := _editor(doc)
	editor.water.carve_river(_line([[-12, 0], [12, 0]]), _w(2.0), WaterBody.Depth.WAIST)
	_settle(editor)
	var main := doc.water_bodies[0]
	# A tributary from the north that ends in the middle of the river (sparse points: the
	# junction is found at the river's edge whatever the spacing).
	var id := editor.water.carve_river(
		_line([[0, 12], [0, 6], [0, 0]]), _w(1.0), WaterBody.Depth.ANKLE
	)
	_settle(editor)
	assert_gt(id, 0, "carved")
	var last := doc.water_bodies[-1]
	var junction: Vector2 = last.points[-1]
	assert_true(
		junction.y > 0.3 and junction.y < 2.2, "cut where it enters the river: %s" % junction
	)
	assert_eq(WaterGeometry.level_at(doc, junction, last.id), main.level_m, "in the main river")
	assert_almost_eq(last.level_m, main.level_m, 1e-4, "the reach that meets it is at its level")
	# No dry lip: the tributary is wet all the way down its last metres into the river.
	var levels := WaterGeometry.levels(doc)
	for k in 8:
		var p := Vector2(0, junction.y + 0.25 * k)
		var s := doc.world_to_sample(p).round()
		var i := doc.sample_index(int(s.x), int(s.y))
		assert_lt(doc.heights[i], levels[i], "wet at %s" % p)
	# And no run-out sheet dropping under the river's surface at the junction.
	var sheets := WaterMeshBuilder.cascades(doc)
	var columns := doc.samples_x()
	for i: int in sheets:
		var p := doc.sample_to_world(Vector2(i % columns, floori(float(i) / columns)))
		if p.distance_to(junction) < 3.0:
			assert_gte(float(sheets[i]), main.level_m - 1e-4, "no sheet under the river")
	# Erasing the river takes the stream that flows into it too (it would spill into the dry
	# channel).
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(-9, 0, -2), Vector3(-9, 0, 2), 0.3, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_true(doc.water_bodies.is_empty(), "the river and its tributary")


func test_a_line_from_a_pond_flows_out_and_a_line_in_water_is_refused() -> void:
	var doc := _new_doc()
	var editor := _editor(doc)
	assert_true(_pond(editor, WaterBody.Depth.WAIST, [Vector2(-8, 0), Vector2(-7, 0)], 3.5))
	_settle(editor)
	var pond := doc.water_bodies[0]
	var id := editor.water.carve_river(
		_line([[-8, 0], [-2, 0], [8, 0]]), _w(1.0), WaterBody.Depth.ANKLE
	)
	_settle(editor)
	assert_gt(id, 0)
	var outflow := doc.water_body(id)
	assert_lt(outflow.points[0].x, -4.0, "starts in the pond")
	assert_gt(outflow.points[0].x, -7.5, "at its edge, not its middle")
	for body in doc.water_bodies:
		if body.is_river():
			assert_lte(body.level_m, pond.level_m + 1e-4, "never above the pond it leaves")
	var none := editor.water.carve_river(
		_line([[-8, 0], [-7, 0.5]]), _w(1.0), WaterBody.Depth.ANKLE
	)
	assert_eq(none, -1, "a line all in water makes nothing")
	assert_eq(editor.water.last_refusal, WaterEditor.REFUSED_IN_WATER, "and says why")


# --- ponds --------------------------------------------------------------------------------------


func test_a_second_stroke_from_inside_a_pond_extends_it() -> void:
	var doc := _new_doc()
	var history := AuthoringHistory.new()
	var editor := _editor(doc, history)
	assert_true(_pond(editor, WaterBody.Depth.WAIST, [Vector2(-4, 0), Vector2(-2, 0)], 3.0))
	_settle(editor)
	var id := doc.water_bodies[0].id
	var area := doc.pond_mask.count(id)
	assert_true(_pond(editor, WaterBody.Depth.WAIST, [Vector2(-1, 0), Vector2(5, 0)], 3.0))
	_settle(editor)
	assert_eq(doc.water_bodies.size(), 1, "one pond")
	assert_eq(doc.water_bodies[0].id, id, "the same one")
	assert_gt(doc.pond_mask.count(id), area + 100, "larger")
	assert_eq(history.undo_count(), 2, "one entry per stroke")


func test_a_pond_meets_its_shore_softly() -> void:
	var doc := _new_doc()
	var editor := _editor(doc)
	assert_true(_pond(editor, WaterBody.Depth.WAIST, [Vector2(0, 0), Vector2(0.5, 0)], 5.0))
	_settle(editor)
	var pond := doc.water_bodies[0]
	var level := pond.level_m
	# Along eight directions: where the ground crosses the level, it stays within a hand's
	# breadth of the water for 0.4 m either side (a beach; P4-3's bank rose 0.15 m and its
	# shore fell 0.16 m over that).
	for k in 8:
		var dir := Vector2.RIGHT.rotated(TAU * k / 8.0)
		var crossing := -1.0
		for n in 400:
			var r := n * 0.025
			if WaterGeometry.ground_at(doc, dir * r) >= level:
				crossing = r
				break
		assert_gt(crossing, 2.0, "the water reaches out (%d)" % k)
		for offset in [-0.4, -0.2, 0.2, 0.4]:
			var h := WaterGeometry.ground_at(doc, dir * (crossing + offset))
			assert_almost_eq(h, level, 0.1, "soft shore %d at %+.2f m" % [k, offset])
	# The surface never stands above the ground outside the water: every covered cell's dry
	# corner has ground at or above the level (less the bob) around the rim.
	var built := WaterMeshBuilder.build(doc)
	var vertices: PackedVector3Array = built.arrays[Mesh.ARRAY_VERTEX]
	for v in vertices:
		var ground := WaterGeometry.ground_at(doc, Vector2(v.x, v.z))
		if ground >= v.y:
			continue
		var s := doc.world_to_sample(Vector2(v.x, v.z)).round()
		var i := doc.sample_index(int(s.x), int(s.y))
		assert_eq(built.wet[i], 1, "water over ground only where it is wet")


# --- erasing -------------------------------------------------------------------------------------


func test_erase_takes_whole_reaches_and_settles_a_shrunk_pond() -> void:
	var doc := _new_doc()
	var editor := _editor(doc)
	editor.water.carve_river(_line([[-12, -6], [12, -6]]), _w(1.0), WaterBody.Depth.ANKLE)
	assert_true(_pond(editor, WaterBody.Depth.WAIST, [Vector2(0, 5), Vector2(1, 5)], 3.5))
	_settle(editor)
	var pond_id := doc.water_bodies[-1].id
	var pond_level := doc.water_bodies[-1].level_m
	var area := doc.pond_mask.count(pond_id)
	# One small dab on the river and one across the pond's east side.
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(3, 0, -6), Vector3(3, 0, -6), 0.4, 0.1)
	editor.stroke_dab(Vector3(4, 0, 2), Vector3(4, 0, 8), 1.2, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	for body in doc.water_bodies:
		assert_false(body.is_river(), "the river (one reach on flat ground) is gone, whole")
	assert_eq(doc.water_bodies.size(), 1)
	assert_lt(doc.pond_mask.count(pond_id), area, "the pond lost the erased area")
	assert_lt(doc.water_bodies[0].level_m, pond_level, "and settled to its new rim")


# --- dressed maps -------------------------------------------------------------------------------


func test_on_a_dressed_map_water_only_erases() -> void:
	var doc := _new_doc()
	doc.has_base_map = true
	var map := Node3D.new()
	add_child_autofree(map)
	var editor := AuthoringEditor.create(doc, map, AuthoringHistory.new())
	assert_false(editor.water.can_carve())
	var refused := editor.water.carve_river(
		_line([[-5, 0], [5, 0]]), _w(1.0), WaterBody.Depth.WAIST
	)
	assert_eq(refused, -1)
	assert_eq(editor.water.last_refusal, WaterEditor.REFUSED_NO_CARVE)
	assert_false(editor.water.paint_pond_begin(WaterBody.Depth.WAIST, Vector3.ZERO))
	# Water painted over it before (a river in the document) can still be erased.
	var widths := PackedFloat32Array([1.0, 1.0])
	var painted: Array[WaterBody] = [
		WaterBody.river(1, _line([[-5, 0], [5, 0]]), widths, WaterBody.Depth.ANKLE, -0.2)
	]
	doc.water_bodies = painted
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(0, 0, -2), Vector3(0, 0, 2), 1.0, 0.1)
	assert_true(editor.end_stroke())
	editor.finish_height_work()
	var surface := map.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	if surface != null:
		surface.finish_refresh()
	assert_true(doc.water_bodies.is_empty(), "erased")
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	var rail: IconRail = panel.get("_rail")
	var item: Button = (rail.get("_buttons") as Dictionary)[AuthoringPanel.TOOL_WATER]
	assert_false(item.disabled, "available by default")
	panel.set_water_available(false, false)
	assert_true(item.disabled, "nothing to carve or erase")
	assert_eq(item.tooltip_text, AuthoringPanel.WATER_UNAVAILABLE_TOOLTIP)
	panel.set_water_available(false, true)
	assert_false(item.disabled, "water to erase")
	var river: Button = panel.water_pane.shape_field.tiles.get_node("water_river")
	assert_true(river.disabled, "but no River tile")
	assert_eq(item.tooltip_text, AuthoringPanel.WATER_ERASE_ONLY_TOOLTIP, "and says why")
	panel.set_water_available(true, false)
	assert_false(river.disabled)


# --- history and the worker --------------------------------------------------------------------


func test_each_gesture_is_one_entry_and_undoes_exactly() -> void:
	var doc := _new_doc()
	var history := AuthoringHistory.new()
	var editor := _editor(doc, history)
	editor.water.use_worker = true
	var start := doc.heights.duplicate()
	var start_model := _model(doc)
	editor.water.carve_river(_line([[-12, 0], [0, 3], [12, 0]]), _w(1.5), WaterBody.Depth.WAIST)
	assert_true(editor.water.is_working(), "computing on a worker")
	assert_true(editor.has_height_work(), "so saves and autosaves wait")
	_settle(editor)
	assert_false(editor.water.is_working())
	assert_eq(history.undo_count(), 1)
	var carved := doc.heights.duplicate()
	var carved_model := _model(doc)
	var carved_dressing := doc.water_dressing.duplicate()
	assert_true(_pond(editor, WaterBody.Depth.DEEP, [Vector2(-6, -8), Vector2(-4, -8)], 3.0))
	_settle(editor)
	assert_eq(history.undo_count(), 2)
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(8, 0, -3), Vector3(8, 0, 3), 1.0, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(history.undo_count(), 3)
	var erased_model := _model(doc)
	history.undo()
	history.undo()
	_settle(editor)
	assert_eq(doc.heights, carved, "back to the river alone")
	assert_eq(_model(doc), carved_model)
	assert_eq(doc.water_dressing, carved_dressing, "and its dressing, exactly")
	history.undo()
	_settle(editor)
	assert_eq(doc.heights, start)
	assert_eq(_model(doc), start_model)
	assert_true(doc.water_dressing.is_empty())
	history.redo()
	history.redo()
	history.redo()
	_settle(editor)
	assert_eq(_model(doc), erased_model, "redo replays all three")


func test_the_worker_carve_lands_exactly_what_the_synchronous_one_does() -> void:
	var results := []
	for worker in [false, true]:
		var doc := _new_doc()
		var heights := doc.heights.duplicate()
		for i in heights.size():
			heights[i] = sin(i * 0.013) * 0.3
		doc.heights = heights
		var editor := _editor(doc)
		editor.water.use_worker = worker
		editor.water.carve_river(
			_line([[-12, -2], [-3, 3], [4, -1], [12, 2]]), _w(1.6), WaterBody.Depth.WAIST
		)
		assert_true(_pond(editor, WaterBody.Depth.ANKLE, [Vector2(-6, 8), Vector2(-3, 8)], 2.5))
		assert_true(editor.water.erase_water_begin())
		editor.stroke_dab(Vector3(10, 0, 0), Vector3(10, 0, 4), 0.5, 0.1)
		editor.end_stroke()
		_settle(editor)
		results.append([doc.heights, doc.water_dressing, _model(doc)])
	assert_eq(results[1][0], results[0][0], "the same ground")
	assert_eq(results[1][1], results[0][1], "the same dressing")
	assert_eq(results[1][2], results[0][2], "the same water")


# --- rounded ends -------------------------------------------------------------------------------


func test_a_river_ends_in_a_rounded_head() -> void:
	var doc := _new_doc()
	var editor := _editor(doc)
	editor.water.carve_river(_line([[-6, 0], [10, 0]]), _w(2.0), WaterBody.Depth.WAIST)
	_settle(editor)
	var level := doc.water_bodies[0].level_m
	# Half the width of the water across the channel at x (ground below the level).
	var wet_half_width := func(x: float) -> float:
		var widest := 0.0
		for n in 60:
			var z := n * 0.05
			if WaterGeometry.ground_at(doc, Vector2(x, z)) < level:
				widest = z
		return widest
	var full: float = wet_half_width.call(2.0)
	assert_gt(full, 1.5, "the channel is full width in the middle")
	var tip: float = wet_half_width.call(-5.7)
	assert_gt(tip, 0.05, "water within 0.3 m of the upstream end")
	assert_lt(tip, 0.6 * full, "narrowing toward it")
	var head: float = wet_half_width.call(-5.0)
	assert_gt(head, tip, "a rounded head, widening away from the tip")
	assert_lt(head, 0.95 * full, "not a straight line across the channel")
	assert_gt(wet_half_width.call(9.7), 0.05, "the downstream end is rounded too")
