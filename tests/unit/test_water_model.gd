extends GutTest

## The water model: WaterBody, MapDocument's water helpers and WaterGeometry (courses,
## distance to a polyline, areas, wet samples, levels and the level rules). The flow bake
## is in test_water_flow_baker.gd, the document entries in test_map_document_water.gd.

const LEVEL := -0.2
const BED := -1.0


## A flat 20 x 20 cell map (30.48 m, 123 samples a side) with a straight channel carved
## to BED along X over -10..10 m, 1.5 m either side of Z = 0, and a river body in it.
func _channel_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	doc.water_bodies.append(_straight_river(1))
	return doc


func _straight_river(body_id: int) -> WaterBody:
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5, 1.5])
	return WaterBody.river(body_id, line, widths, WaterBody.Depth.WAIST, LEVEL)


## A pond basin carved to BED over samples x 20..39, z 90..109 (well clear of the
## channel's reach), masked with `body_id`.
func _add_pond(doc: MapDocument, body_id: int, level: float) -> void:
	var heights := doc.heights.duplicate()
	var mask := doc.pond_mask.duplicate()
	if mask.is_empty():
		mask.resize(doc.sample_count())
	for z in range(90, 110):
		for x in range(20, 40):
			heights[doc.sample_index(x, z)] = BED
			mask[doc.sample_index(x, z)] = body_id
	doc.heights = heights
	doc.pond_mask = mask
	doc.water_bodies.append(WaterBody.pond(body_id, WaterBody.Depth.DEEP, level))


# --- WaterBody and MapDocument ----------------------------------------------------------


func test_depth_classes() -> void:
	assert_eq(WaterBody.DEPTH_M.size(), WaterBody.Depth.size())
	assert_eq(WaterBody.DEPTH_NAMES.size(), WaterBody.Depth.size())
	assert_true(WaterBody.is_wadeable(WaterBody.Depth.ANKLE))
	assert_true(WaterBody.is_wadeable(WaterBody.Depth.WAIST))
	assert_false(WaterBody.is_wadeable(WaterBody.Depth.DEEP), "tokens float in deep water")
	var last := 0.0
	for depth_class in WaterBody.Depth.values():
		assert_gt(WaterBody.depth_for(depth_class), last, "deeper classes are deeper")
		last = WaterBody.depth_for(depth_class)
	var pond := WaterBody.pond(4, WaterBody.Depth.DEEP, 1.0)
	assert_eq(pond.depth_m(), WaterBody.DEPTH_M[WaterBody.Depth.DEEP])
	assert_false(pond.is_river())
	assert_eq(pond.speed, 0.0, "ponds are still")


func test_copy_is_deep() -> void:
	var river := _straight_river(2)
	var copy := river.copy()
	copy.points[0] = Vector2(5, 5)
	copy.half_widths[0] = 3.0
	assert_eq(river.points[0], Vector2(-10, 0))
	assert_eq(river.half_widths[0], 1.5)
	assert_eq([copy.id, copy.kind, copy.depth, copy.level_m], [2, river.kind, river.depth, LEVEL])


func test_ids_are_stable_and_bounded() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	assert_eq(doc.next_water_id(), 1)
	doc.water_bodies.append(_straight_river(1))
	doc.water_bodies.append(_straight_river(5))
	assert_eq(doc.next_water_id(), 6, "one past the highest")
	assert_eq(doc.water_body(5).id, 5)
	assert_null(doc.water_body(2))
	doc.water_bodies.append(_straight_river(WaterBody.MAX_ID))
	assert_eq(doc.next_water_id(), 2, "the lowest free id once the top is taken")
	while doc.water_bodies.size() < MapDocument.MAX_WATER_BODIES:
		doc.water_bodies.append(_straight_river(doc.next_water_id()))
	assert_eq(doc.next_water_id(), -1, "full")


# --- courses and distance -------------------------------------------------------------


func test_chaikin_matches_terrain_paint() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4)])
	var widths := PackedFloat32Array([1, 2, 3])
	var once: Array = WaterGeometry.chaikin(line, widths, 1)
	# terrain-paint: [p0, 3/4 of segment 0, 1/4 of segment 1, p_last].
	var expected := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 4)])
	assert_eq(once[0], expected)
	assert_eq(once[1], PackedFloat32Array([1, 1.75, 2.25, 3]))
	var twice: Array = WaterGeometry.chaikin(line, widths)
	assert_eq(twice[0].size(), 6, "each pass maps n points to 2n - 2")
	assert_eq(twice[0][0], line[0], "starts upstream")
	assert_eq(twice[0][5], line[2], "ends at the mouth")
	var two := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	var unchanged: Array = WaterGeometry.chaikin(two, PackedFloat32Array([1, 1]))
	assert_eq(unchanged[0], two, "a two-point line is unchanged")


func test_nearest_on_polyline() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(4, 0), Vector2(4, 4)])
	var near := WaterGeometry.nearest_on_polyline(line, Vector2(1, 2))
	assert_almost_eq(near.x, 2.0, 1e-5, "distance")
	assert_eq(int(near.y), 1, "the degenerate first segment is skipped")
	assert_almost_eq(near.z, 0.25, 1e-5, "t along the segment")
	var corner := WaterGeometry.nearest_on_polyline(line, Vector2(6, -2))
	assert_almost_eq(corner.x, sqrt(8.0), 1e-5)
	assert_eq(int(corner.y), 1, "a tie goes to the earlier segment")
	var none := WaterGeometry.nearest_on_polyline(PackedVector2Array([Vector2.ONE]), Vector2.ZERO)
	assert_eq(none, Vector3(INF, -1, 0))
	var widths := PackedFloat32Array([1, 1, 3, 5])
	assert_almost_eq(WaterGeometry.width_at(widths, 1, 0.25), 1.5, 1e-6)


func test_nearest_field_agrees_with_the_brute_force() -> void:
	var course: Array = WaterGeometry.chaikin(
		PackedVector2Array([Vector2(-5, -3), Vector2(0, 2), Vector2(4, -1)]),
		PackedFloat32Array([0.5, 1.0, 2.0])
	)
	var origin := Vector2(-8, -8)
	var step := Vector2(0.5, 0.5)
	var field := WaterGeometry.nearest_field(
		course[0], course[1], origin, step, Vector2i(33, 33), 1.0
	)
	var rect: Rect2i = field["rect"]
	var checked := 0
	for j in rect.size.y:
		for i in rect.size.x:
			var p := origin + Vector2(rect.position.x + i, rect.position.y + j) * step
			var near := WaterGeometry.nearest_on_polyline(course[0], p)
			var k := j * rect.size.x + i
			if near.x > 3.0:
				continue
			checked += 1
			assert_almost_eq(field["distance"][k], near.x, 1e-4)
			var width := WaterGeometry.width_at(course[1], int(near.y), near.z)
			assert_almost_eq(field["half_width"][k], width, 1e-4)
	assert_gt(checked, 100, "every cell within the widest reach was compared")


# --- areas, wet samples and levels ----------------------------------------------------

@warning_ignore("integer_division")
func test_wet_samples_of_a_river() -> void:
	var doc := _channel_doc()
	var river := doc.water_bodies[0]
	var wet := WaterGeometry.wet_samples(doc, river)
	var expected := PackedInt32Array()
	for i in doc.sample_count():
		if doc.heights[i] == BED:
			expected.append(i)
	assert_eq(wet, expected, "exactly the carved channel: the flat ground is above the level")
	var area := WaterGeometry.body_area(doc, river)
	assert_gt(area.size(), wet.size(), "the area includes the dry banks")
	for i in area:
		var p := doc.sample_to_world(Vector2(i % doc.samples_x(), i / doc.samples_x()))
		var near := WaterGeometry.nearest_on_polyline(river.points, p)
		assert_true(near.x <= 1.5 + WaterGeometry.RIVER_BANK_M + 1e-4, "area within the reach")


func test_wet_samples_of_a_pond() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	_add_pond(doc, 9, LEVEL)
	var pond := doc.water_body(9)
	assert_eq(WaterGeometry.body_area(doc, pond).size(), 400)
	assert_eq(WaterGeometry.wet_samples(doc, pond).size(), 400, "the whole basin is below")
	pond.level_m = BED - 0.5
	assert_eq(WaterGeometry.wet_samples(doc, pond).size(), 0, "a level below the bed is dry")
	var heights := doc.heights.duplicate()
	heights[doc.sample_index(25, 95)] = 1.0
	doc.heights = heights
	pond.level_m = LEVEL
	assert_eq(WaterGeometry.wet_samples(doc, pond).size(), 399, "an island stays dry")


func test_levels_and_wet_mask() -> void:
	var doc := _channel_doc()
	_add_pond(doc, 2, -0.5)
	var at_level := WaterGeometry.levels(doc)
	var wet := WaterGeometry.wet_mask(doc, at_level)
	var centre := doc.sample_index(61, 61)
	assert_almost_eq(at_level[centre], LEVEL, 1e-6, "the river's level on its course")
	assert_eq(wet[centre], 1)
	var pond_sample := doc.sample_index(30, 100)
	assert_eq(at_level[pond_sample], -0.5)
	assert_eq(wet[pond_sample], 1)
	var far := doc.sample_index(2, 2)
	assert_eq(at_level[far], WaterGeometry.DRY, "no body covers a far corner")
	assert_eq(wet[far], 0)
	var bank := doc.sample_index(61, 61 + 8)
	assert_almost_eq(at_level[bank], LEVEL, 1e-6, "the bank is in the river's area")
	assert_eq(wet[bank], 0, "but above its level")
	assert_eq(WaterGeometry.wet_mask(doc), wet, "levels() by default")


func test_overlapping_bodies_take_the_highest_level() -> void:
	var doc := _channel_doc()
	var higher := _straight_river(2)
	higher.level_m = 0.5
	doc.water_bodies.append(higher)
	var at_level := WaterGeometry.levels(doc)
	assert_eq(at_level[doc.sample_index(61, 61)], 0.5)


func test_pond_mask_of_a_missing_body_is_dry() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	_add_pond(doc, 9, LEVEL)
	doc.water_bodies.clear()
	var covered := 0
	for level in WaterGeometry.levels(doc):
		if level != WaterGeometry.DRY:
			covered += 1
	assert_eq(covered, 0, "mask bytes naming no body are not water")


# --- level rules ------------------------------------------------------------------------


func test_ground_at_is_bilinear_and_clamped() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			heights[doc.sample_index(x, z)] = x * 0.1 + z * 0.01
	doc.heights = heights
	var p := doc.sample_to_world(Vector2(10.5, 20.25))
	assert_almost_eq(WaterGeometry.ground_at(doc, p), 1.05 + 0.2025, 1e-4)
	var corner := doc.sample_index(doc.samples_x() - 1, doc.samples_z() - 1)
	assert_almost_eq(WaterGeometry.ground_at(doc, Vector2(99, 99)), heights[corner], 1e-5)
	var along := WaterGeometry.ground_along(doc, PackedVector2Array([p, Vector2(99, 99)]))
	assert_eq(along.size(), 2)


func test_reaches_split_a_sloped_centreline() -> void:
	var flat := PackedFloat32Array([1.0, 1.1, 0.9, 1.0])
	assert_eq(WaterGeometry.reach_ranges(flat, 0.5), [Vector2i(0, 3)] as Array[Vector2i])
	var slope := PackedFloat32Array([3.0, 2.8, 2.6, 2.4, 2.2, 2.0, 1.8])
	var ranges := WaterGeometry.reach_ranges(slope, 0.5)
	assert_eq(ranges, [Vector2i(0, 2), Vector2i(2, 4), Vector2i(4, 6)] as Array[Vector2i])
	for reach in ranges:
		var low := INF
		var high := -INF
		for i in range(reach.x, reach.y + 1):
			low = minf(low, slope[i])
			high = maxf(high, slope[i])
		assert_true(high - low <= 0.5 + 1e-6, "no reach spans more than the drop")
	assert_almost_eq(
		WaterGeometry.reach_level(slope, ranges[1]), 2.2 - WaterGeometry.FREEBOARD_M, 1e-6
	)
	var cliff := PackedFloat32Array([5.0, 5.0, 1.0, 1.0])
	assert_eq(
		WaterGeometry.reach_ranges(cliff, 0.5),
		[Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)] as Array[Vector2i],
		"a cliff step is its own two-point reach"
	)
	assert_eq(WaterGeometry.reach_ranges(PackedFloat32Array([1.0]), 0.5).size(), 0)


func test_pond_rim_level() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	_add_pond(doc, 9, LEVEL)
	var heights := doc.heights.duplicate()
	for i in heights.size():
		heights[i] = 1.0
	heights[doc.sample_index(20, 100)] = 0.4
	heights[doc.sample_index(30, 100)] = -3.0
	doc.heights = heights
	assert_almost_eq(
		WaterGeometry.pond_rim_level(doc, 9),
		0.4 - WaterGeometry.FREEBOARD_M,
		1e-6,
		"the lowest rim sample; the deeper interior one does not count"
	)
	assert_true(is_nan(WaterGeometry.pond_rim_level(doc, 8)), "no area")
