extends GutTest

## The Lakeshore recipe (P5-2): the same seed draws the same map, seeds pick the corner,
## every draw has one deep pond whose level lies below every sample round its rim and whose
## mask leaves the stage and the islet's top dry, forty seeds draw the stream and the stones
## near their chances and never break the map, the stream ends in the lake, the stones stand
## on the stream, the stage is dry and near the centre.

const BIOME := "temperate_forest_summer_s1"
const SEEDS := 40


func _lakeshore(size_ft: int, seed_value: int, biome: String = BIOME) -> Dictionary:
	var doc := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(size_ft), NewMap.cells_for_feet(size_ft)),
		"grass",
		"",
		seed_value
	)
	var shaped := StartingLandform.apply(doc, StartingLandform.LAKESHORE, seed_value, biome)
	shaped["doc"] = doc
	return shaped


func _pond(doc: MapDocument) -> WaterBody:
	for body in doc.water_bodies:
		if not body.is_river():
			return body
	return null


## The lowest ground just outside pond `id`'s mask (its 4-neighbours outside the area), the
## stream's own channel apart (its bed runs under the lake's level into the mouth).
func _lowest_outside_rim(doc: MapDocument, id: int) -> float:
	var lowest := INF
	var width := doc.samples_x()
	for z in doc.samples_z():
		for x in width:
			var i := doc.sample_index(x, z)
			if doc.pond_mask[i] == id:
				continue
			if (
				WaterGeometry.level_at(doc, doc.sample_to_world(Vector2(x, z)), id)
				!= WaterGeometry.DRY
			):
				continue
			for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + n.x
				var nz: int = z + n.y
				if nx < 0 or nz < 0 or nx >= width or nz >= doc.samples_z():
					continue
				if doc.pond_mask[doc.sample_index(nx, nz)] == id:
					lowest = minf(lowest, doc.heights[i])
					break
	return lowest


func test_same_seed_same_map() -> void:
	var a := _lakeshore(150, 3)
	var b := _lakeshore(150, 3)
	assert_eq(a.stage, b.stage)
	assert_eq(a.report, b.report)
	assert_eq((a.doc as MapDocument).heights, (b.doc as MapDocument).heights, "heights")
	assert_eq((a.doc as MapDocument).pond_mask, (b.doc as MapDocument).pond_mask, "mask")


func test_seeds_pick_the_corner() -> void:
	var corners := {}
	for seed_value in range(1, 13):
		var frame := LandformLakeshore.lakeshore_frame(
			22.86, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		corners[frame.corner] = true
	assert_gt(corners.size(), 1, "several corners over twelve seeds")
	assert_ne(
		(_lakeshore(100, 2).doc as MapDocument).heights,
		(_lakeshore(100, 3).doc as MapDocument).heights
	)


func test_the_lake_is_never_in_the_cameras_corner() -> void:
	# P5-4b: a lake in the corner StartingLandform.NEAR points to lies at the bottom of the
	# view, cut by the foreground.
	var near := StartingLandform.NEAR
	var corners := {}
	for seed_value in range(1, SEEDS + 1):
		var frame := LandformLakeshore.lakeshore_frame(
			22.86, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var centre: Vector2 = frame.centre
		var seeds: PackedInt32Array = corners.get(frame.corner, PackedInt32Array())
		seeds.append(seed_value)
		corners[frame.corner] = seeds
		assert_false(
			centre.x * near.x > 0.0 and centre.y * near.y > 0.0,
			(
				"seed %d lake centre (%.1f, %.1f) in the camera's corner"
				% [seed_value, centre.x, centre.y]
			)
		)
	assert_eq(corners.size(), 3, "all three other corners over %d seeds" % SEEDS)
	for corner in corners:
		gut.p("lakeshore corner %s: seeds %s" % [corner, corners[corner]])


func test_the_far_corner_is_drawn_most_and_a_side_lake_sits_inside_the_frame() -> void:
	# P5-7: the far corner (opposite NEAR) fills the view; a side corner's lake is pulled toward
	# the centre on the axis that points at the camera's side.
	var near := StartingLandform.NEAR
	var far := Vector2i(-roundi(signf(near.x)), -roundi(signf(near.y)))
	var half := 22.86
	var counts := {}
	for seed_value in range(1, SEEDS + 1):
		var frame := LandformLakeshore.lakeshore_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var corner: Vector2i = frame.corner
		var centre: Vector2 = frame.centre
		counts[corner] = int(counts.get(corner, 0)) + 1
		assert_false(
			centre.x * near.x > 0.0 and centre.y * near.y > 0.0,
			(
				"seed %d centre (%.1f, %.1f) in the camera's quadrant"
				% [seed_value, centre.x, centre.y]
			)
		)
		if corner == far:
			assert_almost_eq(
				centre.length(), half * LandformLakeshore.LAKE_CENTRE_SHARE * sqrt(2.0), 0.01
			)
			continue
		var on_camera_axis := absf(centre.x) if centre.x * near.x > 0.0 else absf(centre.y)
		assert_almost_eq(
			on_camera_axis,
			half * LandformLakeshore.LAKE_SIDE_CENTRE_SHARE,
			0.01,
			"seed %d side lake pulled in on the camera's axis" % seed_value
		)
	gut.p("lakeshore corner counts over %d seeds: %s" % [SEEDS, counts])
	var far_count := int(counts.get(far, 0))
	for corner in counts:
		if corner != far:
			assert_gt(far_count, int(counts[corner]), "far corner drawn more than %s" % corner)


func test_one_deep_lake_below_its_rim_with_the_stage_and_the_islet_dry() -> void:
	var islets := 0
	for seed_value in range(1, 13):
		var shaped := _lakeshore(150, seed_value)
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		var ponds := 0
		for body in doc.water_bodies:
			ponds += 0 if body.is_river() else 1
		assert_eq(ponds, 1, "%s one lake" % label)
		var lake := _pond(doc)
		if lake == null:
			continue
		assert_eq(lake.depth, WaterBody.Depth.DEEP, "%s a deep lake" % label)
		assert_lt(lake.level_m, _lowest_outside_rim(doc, lake.id), "%s level below the rim" % label)
		var stage: Vector2 = shaped.stage
		var s := doc.world_to_sample(stage).round()
		assert_eq(
			doc.pond_mask[doc.sample_index(int(s.x), int(s.y))], 0, "%s stage off the mask" % label
		)
		assert_false(WaterGeometry.is_wet_at(doc, stage), "%s stage is dry" % label)
		if not shaped.report.contains("islet at"):
			continue
		islets += 1
		var at: PackedStringArray = (
			String(shaped.report).split("islet at (")[1].split(")")[0].split(", ")
		)
		var islet := Vector2(float(at[0]), float(at[1]))
		var top := doc.world_to_sample(islet).round()
		var i := doc.sample_index(int(top.x), int(top.y))
		assert_eq(doc.pond_mask[i], 0, "%s the islet's top is off the mask" % label)
		assert_gt(
			doc.heights[i], lake.level_m + 0.3, "%s the islet's top stands over the water" % label
		)
		assert_false(WaterGeometry.is_wet_at(doc, islet), "%s the islet's top is dry" % label)
	assert_gt(islets, 0, "some seed drew an islet")


func test_forty_seeds_draw_streams_near_their_chance_and_never_break_the_map() -> void:
	var streams := 0
	var stones := 0
	var half := 15.24
	for seed_value in range(1, SEEDS + 1):
		var shaped := _lakeshore(100, seed_value)
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		var out_of_range := 0
		for h in doc.heights:
			out_of_range += 1 if is_nan(h) or absf(h) > MapDocument.MAX_ABS_HEIGHT_M else 0
		assert_eq(out_of_range, 0, "%s heights within the limit" % label)
		var packed := MapDocumentIO.serialize(doc)
		assert_eq(packed.error, "", label)
		assert_not_null(MapDocumentIO.parse(packed.entries).document, label)
		var stage: Vector2 = shaped.stage
		assert_lte(stage.length(), half * 0.5 + 0.01, "%s stage within reach" % label)
		assert_false(WaterGeometry.is_wet_at(doc, stage), "%s stage is dry" % label)
		var lake := _pond(doc)
		assert_not_null(lake, "%s the lake is always there" % label)
		var stream: Array[WaterBody] = []
		for body in doc.water_bodies:
			if body.is_river():
				stream.append(body)
		if stream.is_empty():
			assert_true(doc.crossings.is_empty(), "%s no crossing without a stream" % label)
			continue
		streams += 1
		var mouth: Vector2 = stream[-1].points[-1]
		if lake != null:
			assert_true(
				WaterGeometry.is_wet_at(doc, mouth, stream[-1].id),
				"%s the stream ends in the lake" % label
			)
		for crossing in doc.crossings:
			stones += 1
			assert_eq(crossing.kind, Crossing.Kind.STONES, "%s crossing kind" % label)
			var middle := (crossing.start + crossing.end) * 0.5
			assert_true(WaterGeometry.is_wet_at(doc, middle), "%s stones over water" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.start), "%s bank a" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.end), "%s bank b" % label)
	assert_between(
		float(streams) / SEEDS, 0.35, 0.65, "streams in %d of %d seeds" % [streams, SEEDS]
	)
	assert_gt(stones, 0, "some seed drew stones")
	gut.p("lakeshore: %d streams, %d stones over %d seeds" % [streams, stones, SEEDS])


func test_stones_are_drawn_over_water_and_never_refused() -> void:
	# P5-7: the stones pick the straightest point that the carve left wet (seed 14 once
	# refused `no_water`). Only the seeds whose feature stream draws a stream and stones run.
	var drawn := 0
	for seed_value in range(1, SEEDS + 1):
		var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
		draws.randf()
		var wants_stream := draws.randf() < LandformLakeshore.STREAM_CHANCE
		var wants_stones := draws.randf() < LandformLakeshore.STONES_CHANCE
		if not wants_stream or not wants_stones:
			continue
		for size_ft in [100, 150]:
			var report: String = _lakeshore(size_ft, seed_value).report
			gut.p("seed %d at %d ft: %s" % [seed_value, size_ft, report])
			if not report.contains("stream:"):
				continue
			drawn += 1
			assert_false(
				report.contains("refused"), "seed %d at %d ft: %s" % [seed_value, size_ft, report]
			)
	assert_gt(drawn, 0, "some seed drew stones")


func test_cost_at_150_ft() -> void:
	var started := Time.get_ticks_usec()
	for seed_value in [3, 7]:
		_lakeshore(150, seed_value)
	var ms := (Time.get_ticks_usec() - started) / 2000.0
	gut.p("lakeshore: %.0f ms per apply at 150 ft" % ms)
	assert_lt(ms, 6000.0, "a lakeshore opens in a few seconds at most")
