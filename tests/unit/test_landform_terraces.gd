extends GutTest

## The Terraces recipe (P5-2): the same seed draws the same map, seeds turn the heading,
## the ground stands on two or three flat tiers with rock-steep faces between, forty seeds
## draw the river and the bridge near their chances and never break the map, a river across
## the steps falls at them, the bridge stands on the water, the stage is dry and near the
## centre.

const BIOME := "temperate_forest_summer_s1"
const SEEDS := 40
const CLIFF_SLOPE := tan(deg_to_rad(TerrainRules.CLIFF_START_DEG))


func _terraces(size_ft: int, seed_value: int, biome: String = BIOME) -> Dictionary:
	var doc := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(size_ft), NewMap.cells_for_feet(size_ft)),
		"grass",
		"",
		seed_value
	)
	var shaped := StartingLandform.apply(doc, StartingLandform.TERRACES, seed_value, biome)
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
	var a := _terraces(150, 3)
	var b := _terraces(150, 3)
	assert_eq(a.stage, b.stage)
	assert_eq(a.report, b.report)
	assert_eq((a.doc as MapDocument).heights, (b.doc as MapDocument).heights, "heights")


func test_seeds_turn_the_heading() -> void:
	var half := 22.86
	var headings := {}
	for seed_value in range(1, 13):
		var frame := LandformTerraces.terraces_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		headings[frame.heading_deg] = true
		assert_lte(absf(float(frame.offset)), half * LandformTerraces.SET_OFFSET_SHARE + 0.01)
	assert_gt(headings.size(), 2, "several of the eight headings over twelve seeds")
	assert_ne(
		(_terraces(100, 2).doc as MapDocument).heights,
		(_terraces(100, 3).doc as MapDocument).heights
	)


func test_dry_draws_stand_on_flat_tiers_with_rock_faces_between() -> void:
	var twos := 0
	var threes := 0
	for seed_value in range(1, SEEDS + 1):
		var shaped := _terraces(150, seed_value)
		if not shaped.report.contains("dry"):
			continue
		var doc: MapDocument = shaped.doc
		var tier := doc.tier_height_m
		var tiers := int(shaped.report.split(" tiers")[0].split(", ")[-1])
		if tiers == 2:
			twos += 1
		else:
			threes += 1
		var levels := {}
		var on := 0
		var highest := -INF
		for h in doc.heights:
			highest = maxf(highest, h)
			if HeightBrush.on_tier(h, tier):
				on += 1
				levels[HeightBrush.tier_level(h, tier)] = true
		assert_gt(
			float(on) / doc.sample_count(),
			0.7,
			"seed %d most of the ground is on a tier" % seed_value
		)
		assert_eq(levels.size(), tiers, "seed %d %d flat levels" % [seed_value, tiers])
		assert_almost_eq(
			highest, (tiers - 1) * tier, 0.01, "seed %d the top is a tier" % seed_value
		)
		for level in range(tiers):
			assert_true(levels.has(level), "seed %d level %d is present" % [seed_value, level])
		assert_gte(
			_steepest(doc), CLIFF_SLOPE, "seed %d the steps pass the cliff rule" % seed_value
		)
	assert_gt(twos, 0, "some dry seed drew two tiers")
	assert_gt(threes, 0, "some dry seed drew three tiers")


func test_forty_seeds_draw_rivers_near_their_chance_and_never_break_the_map() -> void:
	var rivers := 0
	var bridges := 0
	var half := 15.24
	for seed_value in range(1, SEEDS + 1):
		var shaped := _terraces(100, seed_value)
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
		if doc.water_bodies.is_empty():
			assert_true(doc.crossings.is_empty(), "%s no crossing without water" % label)
			continue
		rivers += 1
		assert_gt(WaterFalls.falls(doc).size(), 0, "%s a river across the steps falls" % label)
		for crossing in doc.crossings:
			bridges += 1
			assert_eq(crossing.kind, Crossing.Kind.PLANK, "%s crossing kind" % label)
			var middle := (crossing.start + crossing.end) * 0.5
			assert_true(WaterGeometry.is_wet_at(doc, middle), "%s bridge over water" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.start), "%s bank a" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.end), "%s bank b" % label)
	assert_between(float(rivers) / SEEDS, 0.45, 0.75, "rivers in %d of %d seeds" % [rivers, SEEDS])
	assert_gt(bridges, 0, "some seed drew a bridge")
	gut.p("terraces: %d rivers, %d bridges over %d seeds" % [rivers, bridges, SEEDS])


func test_cost_at_150_ft() -> void:
	var started := Time.get_ticks_usec()
	for seed_value in [3, 7]:
		_terraces(150, seed_value)
	var ms := (Time.get_ticks_usec() - started) / 2000.0
	gut.p("terraces: %.0f ms per apply at 150 ft" % ms)
	assert_lt(ms, 4000.0, "terraces open in a few seconds at most")
