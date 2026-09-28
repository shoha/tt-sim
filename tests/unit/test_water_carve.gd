extends GutTest

## Carving water (phase 4, P4-3): the channel cross-section per depth class (shore and bank
## slopes, the bed, never raising ground, no bank steep enough to turn to rock), reach steps
## shaped as a crest and a riffle with the upper reach's water stopping at the crest, the
## pond basin, the wet dressing field, the rock policy, and the editor's carve, pond and
## erase: one history entry each, undo and redo exact, an erase leaving the ground carved.

const BIOME := "temperate_forest_summer_s1"

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


## Lets the water surface's worker land (AuthoredWater.refresh_map).
func _settle(editor: AuthoringEditor) -> void:
	editor.finish_height_work()
	var water := _map.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	if water != null:
		water.finish_refresh()


## Heights set by `shape` (Callable(Vector2 map XZ) -> float) at every sample.
func _shape(doc: MapDocument, shape: Callable) -> void:
	var heights := PackedFloat32Array()
	heights.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			heights[doc.sample_index(x, z)] = shape.call(doc.sample_to_world(Vector2(x, z)))
	doc.heights = heights


## A straight river along X at z = 0 with half-width `half`.
func _straight(doc: MapDocument, depth: WaterBody.Depth, half: float = 2.0) -> Array[WaterBody]:
	return WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]),
		PackedFloat32Array([half, half]),
		depth
	)


## Applies WaterCarve goals to `doc` (min with the ground).
func _carve(doc: MapDocument, goals: Dictionary) -> void:
	var rect: Rect2i = goals.rect
	var values: PackedFloat32Array = goals.goals
	var heights := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal := values[j * rect.size.x + i]
			var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
			if not is_inf(goal):
				heights[at] = minf(heights[at], goal)
	doc.heights = heights


func _height(doc: MapDocument, p: Vector2) -> float:
	return WaterGeometry.ground_at(doc, p)


# --- cross-section -----------------------------------------------------------------------


func test_cross_section_per_depth_class() -> void:
	for depth in [WaterBody.Depth.ANKLE, WaterBody.Depth.WAIST, WaterBody.Depth.DEEP]:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		# A valley rising 1:1 to 3 m on either side, so the banks are cut to their slope.
		_shape(doc, func(p: Vector2) -> float: return minf(absf(p.y), 3.0))
		var start := doc.heights.duplicate()
		var bodies := _straight(doc, depth)
		assert_eq(bodies.size(), 1, "flat along its line: one reach")
		var level := bodies[0].level_m
		assert_almost_eq(level, -WaterGeometry.FREEBOARD_M, 1e-4)
		_carve(doc, WaterCarve.river_goals(doc, bodies, start))
		var d := WaterBody.depth_for(depth)
		var name := WaterBody.DEPTH_NAMES[depth]
		var hw := bodies[0].half_widths[0]
		assert_almost_eq(hw, maxf(2.0, WaterCarve.min_half_width(depth)), 1e-4, "%s: width" % name)
		assert_almost_eq(_height(doc, Vector2(0, 0)), level - d, 0.03, "%s: bed depth" % name)
		assert_almost_eq(_height(doc, Vector2(0, hw)), level, 0.08, "%s: waterline" % name)
		# The shore under the water is soft for wading water, steeper for deep (and for a
		# channel too narrow to reach its bed at the class's slope).
		var shore := (_height(doc, Vector2(0, hw - 0.1)) - _height(doc, Vector2(0, hw - 0.4))) / 0.3
		var expected := clampf(
			d / (hw * (1.0 - WaterCarve.BED_SHARE)),
			WaterCarve.SHORE_SLOPE[depth],
			WaterCarve.MAX_SHORE_SLOPE
		)
		assert_almost_eq(shore, expected, 0.1, "%s: shore slope" % name)
		# The bank's slope away from the water, then no steeper than the cliff rule starts.
		var bank := (_height(doc, Vector2(0, hw + 1.0)) - _height(doc, Vector2(0, hw + 0.5))) / 0.5
		assert_almost_eq(bank, WaterCarve.BANK_SLOPE[depth], 0.06, "%s: bank slope" % name)
		var steepest := 0.0
		for k in 60:
			var z := k * 0.1
			var rise := absf(_height(doc, Vector2(0, z + 0.1)) - _height(doc, Vector2(0, z)))
			steepest = maxf(steepest, rise / 0.1)
		assert_lt(steepest, tan(deg_to_rad(TerrainRules.CLIFF_START_DEG)), "%s: no rock" % name)
		for i in doc.sample_count():
			assert_true(doc.heights[i] <= start[i] + 1e-6, "%s never raises ground" % name)
			if doc.heights[i] > start[i] + 1e-6:
				break


func test_narrow_channels_widen_to_reach_their_depth() -> void:
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.DEEP, 0.8)
	var narrowest := WaterCarve.min_half_width(WaterBody.Depth.DEEP)
	assert_almost_eq(bodies[0].half_widths[0], narrowest, 1e-4, "widened")
	_carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	var bed := bodies[0].level_m - WaterBody.depth_for(WaterBody.Depth.DEEP)
	assert_almost_eq(_height(_doc, Vector2(0, 0)), bed, 0.06, "a deep river is deep")
	var shore := _height(_doc, Vector2(0, narrowest - 0.2)) - _height(_doc, Vector2(0, 1.0))
	shore /= narrowest - 1.2
	assert_lt(shore, WaterCarve.MAX_SHORE_SLOPE + 0.02, "and its shore is no rock face")


func test_carve_never_raises_uneven_ground() -> void:
	_shape(_doc, func(p: Vector2) -> float: return sin(p.x * 0.7) * 0.4 + cos(p.y * 1.3) * 0.3)
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.WAIST)
	var goals := WaterCarve.river_goals(_doc, bodies, start)
	var rect: Rect2i = goals.rect
	var raised := 0
	for j in rect.size.y:
		for i in rect.size.x:
			var goal: float = goals.goals[j * rect.size.x + i]
			var at := (rect.position.y + j) * _doc.samples_x() + rect.position.x + i
			if not is_inf(goal) and goal > start[at]:
				raised += 1
	assert_eq(raised, 0)


# --- reach steps ---------------------------------------------------------------------------


func test_reach_steps_are_a_crest_and_a_riffle() -> void:
	# Ground falling 0.12 m per metre along the river: several flat reaches.
	_shape(_doc, func(p: Vector2) -> float: return -0.12 * p.x)
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.WAIST)
	assert_gt(bodies.size(), 2, "the drop splits the stroke into reaches")
	_carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	_doc.water_bodies = bodies
	# At each shared point the ground stands just under the upper level: its pool runs
	# shallow over the crest to the line where its area stops.
	for b in bodies.size() - 1:
		var joint: Vector2 = bodies[b].points[-1]
		assert_almost_eq(bodies[b + 1].points[0].distance_to(joint), 0.0, 1e-6)
		var crest := _height(_doc, joint)
		assert_gt(crest, bodies[b].level_m - 0.1, "crest %d just under the upper water" % b)
		assert_lt(crest, bodies[b].level_m + 0.02, "crest %d" % b)
	# The riffle below each crest carries a sheet of white water between the two levels.
	var sheets := WaterMeshBuilder.cascades(_doc)
	assert_false(sheets.is_empty(), "cascades over the riffles")
	var reach_levels := {}
	for body in bodies:
		reach_levels[snappedf(body.level_m, 1e-4)] = true
	for i: int in sheets:
		var sheet := float(sheets[i])
		# Over its ground, or clamped at a reach's level (buried under a crest there).
		var clamped := reach_levels.has(snappedf(sheet, 1e-4))
		assert_true(sheet > _doc.heights[i] or clamped, "a sheet over its ground")
		assert_lt(sheet, bodies[0].level_m + 1e-4, "and under the top level")
	# Down the centreline the bed never drops faster than a riffle, no vertical lip.
	var worst := 0.0
	for k in 80:
		var x := -10.0 + k * 0.25
		var drop := _height(_doc, Vector2(x, 0)) - _height(_doc, Vector2(x + 0.25, 0))
		worst = maxf(worst, drop / 0.25)
	assert_lt(worst, 2.0 * WaterCarve.RIFFLE_SLOPE, "riffles, not a lip (slope %.2f)" % worst)
	# The upper reach's area stops flush at the shared point: just below it, it is not wet.
	var levels := WaterGeometry.levels(_doc)
	var below: Vector2 = bodies[0].points[-1] + Vector2(1.0, 0)
	var s := _doc.world_to_sample(below).round()
	var level := levels[_doc.sample_index(int(s.x), int(s.y))]
	assert_lt(level, bodies[0].level_m - 0.01, "the upper water does not reach past its crest")


func test_flush_ends_only_where_a_reach_continues() -> void:
	var widths := PackedFloat32Array([1.0, 1.0])
	var ankle := WaterBody.Depth.ANKLE
	var a := WaterBody.river(
		1, PackedVector2Array([Vector2(0, 0), Vector2(4, 0)]), widths, ankle, 0.0
	)
	var b := WaterBody.river(
		2, PackedVector2Array([Vector2(4, 0), Vector2(8, 0)]), widths, ankle, -0.5
	)
	var bodies: Array[WaterBody] = [a, b]
	assert_eq(WaterGeometry.flush_ends(bodies, a), Vector2i(0, 1))
	assert_eq(WaterGeometry.flush_ends(bodies, b), Vector2i(1, 0))
	var alone: Array[WaterBody] = [a]
	assert_eq(WaterGeometry.flush_ends(alone, a), Vector2i.ZERO)


# --- ponds -----------------------------------------------------------------------------------


func test_pond_basin_is_a_bowl_with_a_soft_shore() -> void:
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if _doc.sample_to_world(Vector2(x, z)).length() < 7.0:
				mask[_doc.sample_index(x, z)] = 3
	_doc.pond_mask = mask
	var level := WaterGeometry.pond_rim_level(_doc, 3)
	var body := WaterBody.pond(3, WaterBody.Depth.WAIST, level)
	var start := _doc.heights.duplicate()
	_carve(_doc, WaterCarve.pond_goals(_doc, body, start))
	var d := body.depth_m()
	var centre := _height(_doc, Vector2.ZERO)
	assert_lt(centre, level - d, "deeper than the depth class in the middle")
	assert_gt(centre, level - d * (1.0 + WaterCarve.POND_CENTRE_EXTRA) - 0.05)
	assert_lt(centre, _height(_doc, Vector2(4.5, 0)), "a bowl: shallower toward the shore")
	assert_almost_eq(_height(_doc, Vector2(7.0, 0)), level, 0.1, "the waterline at the rim")
	assert_almost_eq(_height(_doc, Vector2(9.5, 0)), 0.0, 1e-6, "the ground beyond untouched")


# --- dressing --------------------------------------------------------------------------------


func test_dressing_beds_the_water_and_fades_the_shore() -> void:
	assert_true(WaterDressing.refresh(_doc).is_empty(), "no water, no dressing")
	var start := _doc.heights.duplicate()
	var bodies := _straight(_doc, WaterBody.Depth.WAIST)
	_carve(_doc, WaterCarve.river_goals(_doc, bodies, start))
	_doc.water_bodies = bodies
	var field := WaterDressing.refresh(_doc)
	assert_eq(field.size(), _doc.sample_count() * WaterDressing.CHANNELS)
	assert_eq(_doc.water_dressing, field)
	var at := func(p: Vector2) -> Vector3:
		return WaterDressing.sample(
			field, _doc.samples_x(), _doc.samples_z(), _doc.world_to_sample(p)
		)
	var middle: Vector3 = at.call(Vector2(0, 0))
	assert_almost_eq(middle.x, 1.0, 0.01, "bed under the water")
	assert_almost_eq(middle.z, WaterBody.depth_for(WaterBody.Depth.WAIST) + 0.0, 0.05, "depth")
	var bank: Vector3 = at.call(Vector2(0, 2.8))
	assert_lt(bank.x, 0.05, "no bed on the bank")
	assert_gt(bank.y, 0.5, "the wet shore just above the water")
	var field_side: Vector3 = at.call(Vector2(0, 6.0))
	assert_eq(field_side, Vector3.ZERO, "the biome ground farther out")
	var fading := [
		at.call(Vector2(0, 2.4)).y, at.call(Vector2(0, 3.4)).y, at.call(Vector2(0, 4.4)).y
	]
	assert_true(fading[0] >= fading[1] and fading[1] >= fading[2], "fading out: %s" % str(fading))


func test_compose_water_shares_and_paths_yield_to_the_bed() -> void:
	for yielding in [0.0, 0.4, 1.0]:
		for held in [0.0, 0.3]:
			if yielding + held > 1.0:
				continue
			for rule in [Vector2.ZERO, Vector2(0.5, 0.1)]:
				for water in [Vector2.ZERO, Vector2(0.6, 0.5), Vector2(1.0, 1.0)]:
					var s := TerrainRules.compose_water(yielding, held, rule, water)
					var total: float = s[0] + s[1] + s[2] + s[4] + s[5] + yielding * s[3] + held
					assert_almost_eq(total, 1.0, 1e-5, "shares add up")
	var under := TerrainRules.compose_water(1.0, 0.0, Vector2.ZERO, Vector2(1.0, 0.0))
	assert_almost_eq(under[3], 0.0, 1e-6, "a path under water keeps nothing")
	assert_almost_eq(under[4], 1.0, 1e-6, "the bed shows")
	var rock := TerrainRules.compose_water(0.0, 1.0, Vector2.ZERO, Vector2(1.0, 0.0))
	assert_almost_eq(rock[4], 0.0, 1e-6, "painted rock holds under water")
	var dry := TerrainRules.compose_water(0.5, 0.0, Vector2(0.3, 0.1), Vector2.ZERO)
	var paint := TerrainRules.compose_paint(0.5, 0.0, Vector2(0.3, 0.1))
	assert_eq(Vector4(dry[0], dry[1], dry[2], dry[3]), paint, "no water: compose_paint")


# --- rocks -----------------------------------------------------------------------------------


func test_rock_policy_keeps_rocks_breaking_the_surface() -> void:
	var row := func(y: float, scale: float) -> PackedFloat32Array:
		return PackedFloat32Array([0, y, 0, 0, 0, 0, 1, scale, scale, scale])
	var level := 0.0
	assert_true(WaterCarve.keeps_rock(row.call(0.2, 1.0), 0.5, 0.3, level, 4.0), "on the bank")
	assert_true(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 0.6, 0.3, level, 4.0), "edge foam")
	assert_false(WaterCarve.keeps_rock(row.call(-0.9, 1.0), 0.6, 0.3, level, 4.0), "submerged")
	assert_false(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 1.5, 1.2, level, 4.0), "blocking")
	assert_true(WaterCarve.keeps_rock(row.call(-0.3, 1.0), 1.5, 1.2, level, 0.0), "a pond's")
	assert_true(WaterCarve.keeps_rock(row.call(-5.0, 1.0), 0.5, 0.3, WaterGeometry.DRY, 0.0))


# --- editor ----------------------------------------------------------------------------------


func _model(doc: MapDocument) -> Array:
	var out := []
	for body in doc.water_bodies:
		out.append([body.id, body.kind, body.depth, body.level_m, body.points, body.half_widths])
	return [out, doc.pond_mask]


func test_carve_river_is_one_entry_and_undoes_exactly() -> void:
	var editor := _editor()
	var start := _doc.heights.duplicate()
	var start_model := _model(_doc)
	var id := editor.water.carve_river(
		PackedVector2Array([Vector2(-10, -3), Vector2(0, 2), Vector2(10, -1)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.WAIST
	)
	_settle(editor)
	assert_gt(id, 0)
	assert_eq(_history.undo_count(), 1)
	assert_ne(_doc.heights, start, "carved")
	assert_false(_doc.water_bodies.is_empty())
	assert_false(_doc.water_dressing.is_empty(), "dressed")
	assert_not_null(editor.terrain.get_water_texture())
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	var water := _map.get_node(AuthoredWater.NODE_NAME) as AuthoredWater
	assert_true(water.has_water(), "the surface is built")
	_history.undo()
	_settle(editor)
	assert_eq(_doc.heights, start, "undo restores the ground")
	assert_eq(_model(_doc), start_model, "and the water model")
	assert_true(_doc.water_dressing.is_empty())
	assert_false(water.has_water())
	_history.redo()
	_settle(editor)
	assert_eq(_doc.heights, carved, "redo")
	assert_eq(_model(_doc), carved_model)
	assert_true(water.has_water())


func test_pond_stroke_carves_a_basin_and_undoes_exactly() -> void:
	var editor := _editor()
	var start := _doc.heights.duplicate()
	var start_model := _model(_doc)
	assert_true(editor.water.paint_pond_begin(WaterBody.Depth.DEEP, Vector3(0, 0, 0)))
	editor.stroke_dab(Vector3(-2, 0, 0), Vector3(2, 0, 0), 3.0, 0.1)
	editor.flush()
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_history.undo_count(), 1)
	assert_eq(_doc.water_bodies.size(), 1)
	var pond := _doc.water_bodies[0]
	assert_false(pond.is_river())
	assert_eq(pond.depth, WaterBody.Depth.DEEP)
	assert_gt(_doc.pond_mask.count(pond.id), 100)
	# A small deep pond is a bowl whose shores meet before the full depth (its soft beach,
	# P4-4, takes a little more of it; still deeper than waist-deep water).
	var middle := _height(_doc, Vector2.ZERO)
	assert_lt(middle, pond.level_m - 0.7 * pond.depth_m(), "a deep basin")
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	_history.undo()
	_settle(editor)
	assert_eq(_doc.heights, start)
	assert_eq(_model(_doc), start_model)
	_history.redo()
	_settle(editor)
	assert_eq(_doc.heights, carved)
	assert_eq(_model(_doc), carved_model)
	# A second stroke from inside the pond extends it.
	assert_true(editor.water.paint_pond_begin(WaterBody.Depth.DEEP, Vector3(3, 0, 0)))
	editor.stroke_dab(Vector3(3, 0, 0), Vector3(6, 0, 0), 2.0, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_doc.water_bodies.size(), 1, "the same pond, larger")


func test_erase_water_leaves_the_ground_carved() -> void:
	var editor := _editor()
	# Ground falling along the river: several flat reaches.
	_shape(_doc, func(p: Vector2) -> float: return -0.12 * p.x)
	editor.terrain.queue_heights(Rect2i(0, 0, _doc.samples_x(), _doc.samples_z()))
	editor.finish_height_work()
	editor.water.carve_river(
		PackedVector2Array([Vector2(-11, 0), Vector2(13, 0)]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.ANKLE
	)
	_settle(editor)
	var reaches := _doc.water_bodies.size()
	assert_gt(reaches, 2, "a stroke over sloped ground makes several reaches")
	# A second river, its own stroke, across the slope.
	editor.water.carve_river(
		PackedVector2Array([Vector2(-11, 9), Vector2(-11, 13)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.ANKLE
	)
	_settle(editor)
	var other: WaterBody = _doc.water_bodies[-1]
	var carved := _doc.heights.duplicate()
	var carved_model := _model(_doc)
	# A small dab on one reach in the middle of the first river.
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(-1, 0, -3), Vector3(-1, 0, 3), 0.3, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_eq(_doc.heights, carved, "the channel stays")
	assert_eq(_doc.water_bodies.size(), 1, "the touched river goes, every reach of it")
	assert_eq(_doc.water_bodies[0].id, other.id, "the other river stays")
	assert_eq(_doc.water_bodies[0].points, other.points, "untouched")
	var erased_model := _model(_doc)
	_history.undo()
	_settle(editor)
	assert_eq(_model(_doc), carved_model, "undo brings the river back")
	assert_eq(_doc.heights, carved)
	_history.redo()
	_settle(editor)
	assert_eq(_model(_doc), erased_model)
	# Erasing everything leaves no water and no dressing.
	assert_true(editor.water.erase_water_begin())
	editor.stroke_dab(Vector3(-14, 0, 11), Vector3(-8, 0, 11), 1.0, 0.1)
	assert_true(editor.end_stroke())
	_settle(editor)
	assert_true(_doc.water_bodies.is_empty())
	assert_true(_doc.water_dressing.is_empty())
	assert_eq(_doc.heights, carved)


func test_carving_refused_without_authored_ground() -> void:
	var editor := AuthoringEditor.create(_doc, _map, _history)
	var id := editor.water.carve_river(
		PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	assert_eq(id, -1)
	assert_false(editor.water.paint_pond_begin(WaterBody.Depth.WAIST, Vector3.ZERO))
	assert_eq(_history.undo_count(), 0)


func test_placed_rocks_under_the_water_go_and_come_back_on_undo() -> void:
	var editor := _editor()
	var rule := editor.species_rule(BIOME, "boulder")
	if rule.is_empty():
		pending("no boulder in the palette")
		return
	var handle := editor.place_prop(rule, Vector3(0, 0, 0), Vector3.UP)
	editor.commit_prop_edit()
	var far := editor.place_prop(rule, Vector3(8, 0, 8), Vector3.UP)
	editor.commit_prop_edit()
	var before := editor.props.rows_by_asset()
	editor.water.carve_river(
		PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]),
		PackedFloat32Array([3.0]),
		WaterBody.Depth.DEEP
	)
	_settle(editor)
	var rows: PackedFloat32Array = editor.props.rows_by_asset().get(
		handle.asset_id, PackedFloat32Array()
	)
	var near_left := false
	for r in rows.size() / MapDocument.ROW_STRIDE:
		if Vector2(rows[r * 10], rows[r * 10 + 2]).length() < 0.5:
			near_left = true
	assert_false(near_left, "the boulder in the deep channel is gone")
	assert_true(editor.prop_at(Vector3(8, 0, 8)).size() > 0 or far.is_empty(), "the far one stays")
	_history.undo()
	_settle(editor)
	assert_eq(editor.props.rows_by_asset(), before, "undo puts it back")
