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


func test_no_crown_has_a_flank_ledge_toward_the_camera() -> void:
	# P5-4b: a crownless hill has a one-tier bench on its camera-facing flank, its face a cliff.
	var near := StartingLandform.NEAR
	var found := 0
	for seed_value in range(1, 4 * SEEDS + 1):
		var shaped := _hilltop(150, seed_value)
		var report: String = shaped.report
		if not report.contains("no crown"):
			continue
		found += 1
		var label := "seed %d" % seed_value
		gut.p("%s: %s" % [label, report])
		assert_true(report.contains("flank ledge"), "%s: %s" % [label, report])
		var doc: MapDocument = shaped.doc
		var half := StartingLandform.half_extent(doc)
		var radius := half * LandformHilltop.HILL_RADIUS_SHARE
		var frame := LandformHilltop.hilltop_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var centre: Vector2 = frame.centre
		var ledge := LandformHilltop.ledge_of(
			LandformHilltop.HILL_HEIGHT_M * StartingLandform.size_scale(doc),
			doc.tier_height_m,
			radius
		)
		var line_r: float = ledge.line_r
		var target: float = ledge.target
		var step := doc.sample_step().x
		var on_bench := 0
		var steepest_face := 0.0
		for z in doc.samples_z() - 1:
			for x in doc.samples_x() - 1:
				var offset := doc.sample_to_world(Vector2(x, z)) - centre
				if absf(near.angle_to(offset)) > deg_to_rad(20.0):
					continue
				var r := offset.length()
				if r < line_r * 0.4 or r > line_r + 1.0:
					continue
				var i := doc.sample_index(x, z)
				var h := doc.heights[i]
				if r <= line_r and absf(h - target) <= 0.01:
					on_bench += 1
				var rise := maxf(
					absf(doc.heights[i + 1] - h), absf(doc.heights[doc.sample_index(x, z + 1)] - h)
				)
				steepest_face = maxf(steepest_face, rise / step)
		assert_gt(on_bench, 3, "%s a run of samples on the bench's tier" % label)
		assert_true(HeightBrush.on_tier(target, doc.tier_height_m), "%s on a tier" % label)
		assert_gte(steepest_face, CLIFF_SLOPE, "%s the ledge's face passes the cliff rule" % label)
		if found == 3:
			break
	assert_gt(found, 0, "some seed drew no crown")


func test_a_stream_never_crosses_the_flank_ledge() -> void:
	# P5-7: the ledge's arc is 90-130 degrees; a stream on a ledged hill draws its azimuth from
	# stream_azimuth_window, clear of the bench. Over 40 crownless seeds with a stream (found by
	# peeking at the feature stream, sizes in turn), no point of the stream's channel lies
	# where the bench raises the ground.
	var near := StartingLandform.NEAR
	var found := 0
	var seed_value := 0
	var arcs := PackedInt32Array()
	while found < SEEDS and seed_value < 2000:
		seed_value += 1
		var draws := StartingLandform.stream(seed_value, StartingLandform.STREAM_FEATURES)
		var wants_crown := draws.randf() < LandformHilltop.CROWN_CHANCE
		draws.randf()
		var wants_stream := draws.randf() < LandformHilltop.STREAM_CHANCE
		if wants_crown or not wants_stream:
			continue
		var size_ft: int = NewMap.SIZES_FT[found % NewMap.SIZES_FT.size()]
		found += 1
		var shaped := _hilltop(size_ft, seed_value)
		var report: String = shaped.report
		var label := "seed %d at %d ft" % [seed_value, size_ft]
		if not report.contains("flank ledge") or not report.contains("stream:"):
			continue
		var doc: MapDocument = shaped.doc
		var half := StartingLandform.half_extent(doc)
		var radius := half * LandformHilltop.HILL_RADIUS_SHARE
		var height := LandformHilltop.HILL_HEIGHT_M * StartingLandform.size_scale(doc)
		var centre: Vector2 = (
			LandformHilltop
			. hilltop_frame(
				half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
			)
			. centre
		)
		var ledge := LandformHilltop.ledge_of(height, doc.tier_height_m, radius)
		var line_r: float = ledge.line_r
		var target: float = ledge.target
		var arc_deg := int(report.split("over a ")[1].split(" deg arc")[0])
		arcs.append(arc_deg)
		assert_between(
			arc_deg,
			int(LandformHilltop.LEDGE_ARC_DEG.x),
			int(LandformHilltop.LEDGE_ARC_DEG.y),
			"%s arc" % label
		)
		var half_arc := deg_to_rad(arc_deg * 0.5 + 0.5)
		var crossings := 0
		for body in doc.water_bodies:
			for p in body.points:
				var offset: Vector2 = p - centre
				var r := offset.length()
				if r > line_r + HeightBrush.TIER_SOFTEN_M or r < 1e-3:
					continue
				if height * StartingLandform.bump(r / radius) >= target:
					continue
				# The bench's footprint test of the recipe, with the channel's half-width.
				var inside := (
					(half_arc - absf(near.angle_to(offset))) * line_r
					+ HeightBrush.TIER_SOFTEN_M
					+ LandformHilltop.STREAM_HALF_WIDTH_M * line_r / r
				)
				if inside > 0.0:
					crossings += 1
		assert_eq(crossings, 0, "%s the stream keeps off the bench: %s" % [label, report])
	assert_eq(found, SEEDS, "found %d crownless seeds with a stream" % SEEDS)
	gut.p("ledge arcs drawn: %s" % arcs)


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
