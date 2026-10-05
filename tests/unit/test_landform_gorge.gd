extends GutTest

## The Gorge recipe (P5-2): the same seed draws the same map, seeds turn the heading, the
## floor lies one or two tiers below the rim (tilted by its fall) behind walls past the cliff
## slope, forty seeds draw the stream and the arch near their chances and never break the
## map, the arch stands on the rims over the stream, a dry gorge has a wash, the stage is dry
## and near the centre.

const BIOME := "temperate_forest_summer_s1"
const SEEDS := 40
const CLIFF_SLOPE := tan(deg_to_rad(TerrainRules.CLIFF_START_DEG))


func _gorge(size_ft: int, seed_value: int, biome: String = BIOME) -> Dictionary:
	var doc := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(size_ft), NewMap.cells_for_feet(size_ft)),
		"grass",
		"",
		seed_value
	)
	var shaped := StartingLandform.apply(doc, StartingLandform.GORGE, seed_value, biome)
	shaped["doc"] = doc
	return shaped


## The steepest rise between neighbouring samples of `doc` (metres per metre).
func _steepest(doc: MapDocument) -> float:
	var step := doc.sample_step().x
	var best := 0.0
	for z in doc.samples_z():
		for x in doc.samples_x() - 1:
			var i := doc.sample_index(x, z)
			best = maxf(best, absf(doc.heights[i + 1] - doc.heights[i]) / step)
	return best


func test_same_seed_same_map() -> void:
	var a := _gorge(150, 3)
	var b := _gorge(150, 3)
	assert_eq(a.stage, b.stage)
	assert_eq(a.report, b.report)
	assert_eq((a.doc as MapDocument).heights, (b.doc as MapDocument).heights, "heights")


func test_seeds_turn_the_heading() -> void:
	var half := 22.86
	var headings := {}
	for seed_value in range(1, 13):
		var frame := LandformGorge.gorge_frame(
			half,
			seed_value % 2 == 0,
			StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		headings[frame.heading_deg] = true
		assert_lte(absf(float(frame.offset)), half * LandformGorge.OFFSET_SHARE + 0.01)
		assert_eq((frame.axis as PackedVector2Array).size(), 4 if seed_value % 2 == 0 else 3)
		# P5-4: the ravine crosses the view, never runs along the camera's diagonal.
		assert_true(
			LandformGorge.HEADINGS.has(int(frame.heading_deg) / 45),
			"seed %d heading %d off the camera's diagonal" % [seed_value, frame.heading_deg]
		)
		var dir := Vector2(cos(deg_to_rad(frame.heading_deg)), sin(deg_to_rad(frame.heading_deg)))
		assert_lt(
			absf(dir.dot(StartingLandform.VIEW)),
			0.9,
			"seed %d heading across the view" % seed_value
		)
	assert_gt(headings.size(), 2, "several of the six headings over twelve seeds")
	assert_ne(
		(_gorge(100, 2).doc as MapDocument).heights, (_gorge(100, 3).doc as MapDocument).heights
	)


func test_dry_floor_lies_tiers_below_the_rim_behind_rock_walls() -> void:
	var ones := 0
	var twos := 0
	for seed_value in range(1, SEEDS + 1):
		var shaped := _gorge(150, seed_value)
		if not shaped.report.contains("dry wash"):
			continue
		var doc: MapDocument = shaped.doc
		var tier := doc.tier_height_m
		var fall := LandformGorge.FALL_M * StartingLandform.size_scale(doc)
		var depth := float(shaped.report.split(" m deep")[0].split(", ")[-1])
		var tiers := roundi(depth / tier)
		assert_true(tiers == 1 or tiers == 2, "seed %d one or two tiers" % seed_value)
		assert_almost_eq(depth, tiers * tier, 0.01, "seed %d the depth is whole tiers" % seed_value)
		if tiers == 1:
			ones += 1
		else:
			twos += 1
		var lowest := INF
		var highest := -INF
		var on_floor := 0
		for h in doc.heights:
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
			if h <= -depth + 0.01 and h >= -depth - fall - 0.01:
				on_floor += 1
		assert_almost_eq(lowest, -depth - fall, 0.05, "seed %d the floor's low end" % seed_value)
		assert_almost_eq(highest, 0.0, 0.001, "seed %d the rim is the base" % seed_value)
		assert_gt(
			on_floor, 200, "seed %d a floor between the tiers' depth and its fall" % seed_value
		)
		assert_gte(
			_steepest(doc), CLIFF_SLOPE, "seed %d the walls pass the cliff rule" % seed_value
		)
		var biome := PaletteLibrary.biome(BIOME)
		if not biome.is_empty():
			assert_true(doc.surface_ids.has(biome["scree_surface"]), "seed %d a wash" % seed_value)
	assert_gt(ones, 0, "some dry seed drew one tier")
	assert_gt(twos, 0, "some dry seed drew two tiers")


func test_forty_seeds_draw_streams_near_their_chance_and_never_break_the_map() -> void:
	var streams := 0
	var arches := 0
	var half := 15.24
	for seed_value in range(1, SEEDS + 1):
		var shaped := _gorge(100, seed_value)
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		var out_of_range := 0
		for h in doc.heights:
			out_of_range += 1 if is_nan(h) or absf(h) > MapDocument.MAX_ABS_HEIGHT_M else 0
		assert_eq(out_of_range, 0, "%s heights within the limit" % label)
		var packed := MapDocumentIO.serialize(doc)
		assert_eq(packed.error, "", label)
		var parsed := MapDocumentIO.parse(packed.entries)
		assert_not_null(parsed.document, label)
		if parsed.document != null:
			assert_eq(
				(parsed.document as MapDocument).crossings.size(), doc.crossings.size(), label
			)
		var stage: Vector2 = shaped.stage
		assert_lte(stage.length(), half * 0.5 + 0.01, "%s stage within reach" % label)
		assert_false(WaterGeometry.is_wet_at(doc, stage), "%s stage is dry" % label)
		assert_gte(WaterGeometry.ground_at(doc, stage), -0.05, "%s stage on the rim" % label)
		# P5-4: a 100 ft map is always one tier deep.
		var depth := float(shaped.report.split(" m deep")[0].split(", ")[-1])
		assert_almost_eq(depth, doc.tier_height_m, 0.01, "%s one tier on a 100 ft map" % label)
		if doc.water_bodies.is_empty():
			assert_true(doc.crossings.is_empty(), "%s no crossing without water" % label)
			continue
		streams += 1
		var chain: Array[WaterBody] = []
		for body in doc.water_bodies:
			chain.append(body)
		for k in chain.size() - 1:
			assert_gte(chain[k].level_m, chain[k + 1].level_m, "%s reaches step down" % label)
		for crossing in doc.crossings:
			arches += 1
			assert_eq(crossing.kind, Crossing.Kind.ARCH, "%s crossing kind" % label)
			# The stream runs toward the far wall, so the water is somewhere along the span.
			var wet := false
			for n in 41:
				wet = (
					wet or WaterGeometry.is_wet_at(doc, crossing.start.lerp(crossing.end, n / 40.0))
				)
			assert_true(wet, "%s arch over water" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.start), "%s rim a" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.end), "%s rim b" % label)
			assert_gte(
				WaterGeometry.ground_at(doc, crossing.start), -0.05, "%s foot a on the rim" % label
			)
			assert_gte(
				WaterGeometry.ground_at(doc, crossing.end), -0.05, "%s foot b on the rim" % label
			)
			assert_lte(crossing.span_m(), Crossing.MAX_SPAN_M, "%s span" % label)
	assert_between(
		float(streams) / SEEDS, 0.55, 0.85, "streams in %d of %d seeds" % [streams, SEEDS]
	)
	assert_gt(arches, 0, "some seed drew an arch")
	gut.p("gorge: %d streams, %d arches over %d seeds" % [streams, arches, SEEDS])


func test_cost_at_150_ft() -> void:
	var started := Time.get_ticks_usec()
	for seed_value in [3, 7]:
		_gorge(150, seed_value)
	var ms := (Time.get_ticks_usec() - started) / 2000.0
	gut.p("gorge: %.0f ms per apply at 150 ft" % ms)
	assert_lt(ms, 4000.0, "a gorge opens in a few seconds at most")
