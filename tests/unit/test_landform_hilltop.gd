extends GutTest

## The Hilltop recipe (P5-2): the same seed draws the same map, seeds turn the heading, the
## summit stands at its height and a crown is a flat tier top with a rock face, forty seeds
## draw the stream and the stones near their chances and never break the map, a stream off
## the crown falls, the stones stand on the water, the stage is dry and near the centre.

const BIOME := "temperate_forest_summer_s1"
const SEEDS := 40
const CLIFF_SLOPE := tan(deg_to_rad(TerrainRules.CLIFF_START_DEG))


func _hilltop(size_ft: int, seed_value: int, biome: String = BIOME) -> Dictionary:
	var doc := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(size_ft), NewMap.cells_for_feet(size_ft)),
		"grass",
		"",
		seed_value
	)
	var shaped := StartingLandform.apply(doc, StartingLandform.HILLTOP, seed_value, biome)
	shaped["doc"] = doc
	return shaped


## The steepest rise between neighbouring samples of `doc` (metres per metre).
static func steepest(doc: MapDocument) -> float:
	var step := doc.sample_step().x
	var best := 0.0
	for z in doc.samples_z():
		for x in doc.samples_x() - 1:
			var i := doc.sample_index(x, z)
			best = maxf(best, absf(doc.heights[i + 1] - doc.heights[i]) / step)
	return best


func test_same_seed_same_map() -> void:
	var a := _hilltop(150, 3)
	var b := _hilltop(150, 3)
	assert_eq(a.stage, b.stage)
	assert_eq(a.report, b.report)
	assert_eq((a.doc as MapDocument).heights, (b.doc as MapDocument).heights, "heights")


func test_seeds_turn_the_heading() -> void:
	var half := 22.86
	var headings := {}
	for seed_value in range(1, 13):
		var frame := LandformHilltop.hilltop_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		headings[frame.heading_deg] = true
		assert_lte(float(frame.offset), half * LandformHilltop.HILL_OFFSET_SHARE + 0.01)
	assert_gt(headings.size(), 2, "several of the eight headings over twelve seeds")
	assert_ne(
		(_hilltop(100, 2).doc as MapDocument).heights, (_hilltop(100, 3).doc as MapDocument).heights
	)


func test_summit_height_and_a_flat_crown_on_a_tier() -> void:
	var crowned := 0
	var bare := 0
	for seed_value in range(1, SEEDS + 1):
		var shaped := _hilltop(150, seed_value)
		if not shaped.report.contains("dry"):
			continue
		var doc: MapDocument = shaped.doc
		var scale := StartingLandform.size_scale(doc)
		var tier := doc.tier_height_m
		var highest := -INF
		for h in doc.heights:
			highest = maxf(highest, h)
		if shaped.report.contains("no crown"):
			bare += 1
			assert_almost_eq(
				highest, LandformHilltop.HILL_HEIGHT_M * scale, 0.05, "seed %d summit" % seed_value
			)
			continue
		crowned += 1
		var frame := LandformHilltop.hilltop_frame(
			StartingLandform.half_extent(doc),
			StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var radius := StartingLandform.half_extent(doc) * LandformHilltop.HILL_RADIUS_SHARE
		var crown_radius := LandformHilltop.crown_radius_of(radius, tier)
		var crown := LandformHilltop.crown_of(
			LandformHilltop.HILL_HEIGHT_M * scale, tier, crown_radius / radius
		)
		var target: float = crown.target
		assert_almost_eq(highest, target, 0.01, "seed %d the crown is the summit" % seed_value)
		assert_true(HeightBrush.on_tier(target, tier), "the crown stands on a tier")
		var flat := crown_radius * (1.0 - LandformHilltop.CROWN_WARP) - HeightBrush.tier_span(tier)
		var off := 0
		var on := 0
		for z in doc.samples_z():
			for x in doc.samples_x():
				var p := doc.sample_to_world(Vector2(x, z))
				if p.distance_to(frame.centre) > flat:
					continue
				on += 1
				if absf(doc.heights[doc.sample_index(x, z)] - target) > 0.01:
					off += 1
		assert_gt(on, 20, "seed %d samples on the top" % seed_value)
		assert_eq(off, 0, "seed %d the top is flat on the tier" % seed_value)
		assert_gte(
			steepest(doc),
			CLIFF_SLOPE,
			"seed %d the crown's face passes the cliff rule" % seed_value
		)
	assert_gt(crowned, 0, "some dry seed drew a crown")
	assert_gt(bare, 0, "some dry seed drew no crown")


func test_forty_seeds_draw_streams_near_their_chances_and_never_break_the_map() -> void:
	var streams := 0
	var stones := 0
	var falls := 0
	var half := 15.24
	for seed_value in range(1, SEEDS + 1):
		var shaped := _hilltop(100, seed_value)
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
		var stage: Vector2 = shaped.stage
		assert_lte(stage.length(), half * 0.5 + 0.01, "%s stage within reach" % label)
		assert_false(WaterGeometry.is_wet_at(doc, stage), "%s stage is dry" % label)
		if doc.water_bodies.is_empty():
			assert_true(doc.crossings.is_empty(), "%s no crossing without water" % label)
			continue
		streams += 1
		falls += WaterFalls.falls(doc).size()
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
	# The flank is steeper than the falls rule's drop slope over its middle run only, and a
	# spring's first two metres are its pool, so not every stream falls; some must.
	assert_gt(falls, 0, "some stream down the flank falls")
	gut.p(
		"hilltop: %d streams, %d stones, %d falls over %d seeds" % [streams, stones, falls, SEEDS]
	)


func test_no_crown_is_never_a_bare_mound() -> void:
	# P5-4: a hill without a crown carries the second hill or the stream.
	var bare := 0
	for seed_value in range(1, SEEDS + 1):
		var report: String = _hilltop(100, seed_value).report
		if not report.contains("no crown"):
			continue
		bare += 1
		assert_true(
			report.contains("second hill") or report.contains("stream:"),
			"seed %d: %s" % [seed_value, report]
		)
	assert_gt(bare, 0, "some seed drew no crown")


func test_crown_pool_spills_over_the_face_in_a_fall() -> void:
	# P5-4: with a crown the spring is a pool on the crown's top that falls off its face.
	var found := 0
	for seed_value in range(1, SEEDS + 1):
		var shaped := _hilltop(150, seed_value)
		var report: String = shaped.report
		if not report.contains("crown pool"):
			continue
		found += 1
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		var target := float(report.split("crown at ")[1].split(" m")[0])
		var frame := LandformHilltop.hilltop_frame(
			StartingLandform.half_extent(doc),
			StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var radius := StartingLandform.half_extent(doc) * LandformHilltop.HILL_RADIUS_SHARE
		var crown_radius := LandformHilltop.crown_radius_of(radius, doc.tier_height_m)
		var head: Vector2 = doc.water_bodies[0].points[0]
		assert_lt(
			head.distance_to(frame.centre),
			crown_radius * (1.0 + LandformHilltop.CROWN_WARP),
			"%s the pool's head is on the crown" % label
		)
		assert_gt(
			WaterGeometry.level_at(doc, head),
			target - doc.tier_height_m,
			"%s the pool stands on the crown's tier" % label
		)
		assert_gt(WaterFalls.falls(doc).size(), 0, "%s the pool spills in a fall" % label)
		assert_false(WaterGeometry.is_wet_at(doc, shaped.stage), "%s stage is dry" % label)
		if found == 3:
			break
	assert_gt(found, 0, "some seed drew a crown and a stream")


func test_cost_at_150_ft() -> void:
	var started := Time.get_ticks_usec()
	for seed_value in [3, 7]:
		_hilltop(150, seed_value)
	var ms := (Time.get_ticks_usec() - started) / 2000.0
	gut.p("hilltop: %.0f ms per apply at 150 ft" % ms)
	assert_lt(ms, 4000.0, "a hilltop opens in a few seconds at most")
