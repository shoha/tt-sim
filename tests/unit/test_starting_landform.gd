extends GutTest

## StartingLandform and the Valley recipe (P5-1): the same seed draws the same map, seeds
## differ, the trough has its depth with the rim at the base height, every draw is a
## writable document, rivers run downhill in reaches, crossings stand on the water, the
## stage is dry and near the centre, and NewMap centres the glade on it.

const BIOME := "temperate_forest_summer_s1"
const SEEDS := 40


func _valley(size_ft: int, seed_value: int, biome: String = BIOME) -> Dictionary:
	var doc := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(size_ft), NewMap.cells_for_feet(size_ft)),
		"grass",
		"",
		seed_value
	)
	var shaped := StartingLandform.apply(doc, StartingLandform.VALLEY, seed_value, biome)
	shaped["doc"] = doc
	return shaped


func _river_chains(doc: MapDocument) -> Array:
	var chains: Array = []
	var seen := {}
	for body in doc.water_bodies:
		if not body.is_river() or seen.has(body.id):
			continue
		var chain: Array[WaterBody] = []
		for id in WaterEdit.river_chain(doc.water_bodies, body.id):
			seen[id] = true
			chain.append(doc.water_body(id))
		chains.append(chain)
	return chains


func test_kinds_have_names_and_captions() -> void:
	for kind in StartingLandform.KINDS:
		assert_true(StartingLandform.NAMES.has(kind), kind)
		assert_true(StartingLandform.CAPTIONS.has(kind), kind)
	assert_true(StartingLandform.KINDS.has(StartingLandform.DEFAULT))


func test_flat_changes_nothing() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "", 5)
	var shaped := StartingLandform.apply(doc, StartingLandform.FLAT, 5)
	assert_eq(shaped.stage, Vector2.ZERO)
	var raised := 0
	for h in doc.heights:
		raised += 1 if h != 0.0 else 0
	assert_eq(raised, 0, "flat stays flat")
	assert_true(doc.water_bodies.is_empty())


func test_same_seed_same_map() -> void:
	var a := _valley(150, 3)
	var b := _valley(150, 3)
	assert_eq(a.stage, b.stage)
	assert_eq(a.report, b.report)
	assert_eq((a.doc as MapDocument).heights, (b.doc as MapDocument).heights, "heights")
	var entries_a: Dictionary = MapDocumentIO.serialize(a.doc).entries
	var entries_b: Dictionary = MapDocumentIO.serialize(b.doc).entries
	assert_eq(entries_a.keys(), entries_b.keys())
	for name in entries_a:
		assert_eq(entries_a[name], entries_b.get(name), name)


func test_different_seeds_turn_the_axis() -> void:
	var half := 22.86
	var headings := {}
	for seed_value in range(1, 13):
		var frame := LandformRecipes.valley_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		headings[frame.heading_deg] = true
		assert_between(absf(float(frame.bend_deg)), 8.0, 25.0, "bend %d" % seed_value)
		assert_lte(absf(float(frame.offset)), half * LandformRecipes.VALLEY_OFFSET_SHARE + 0.01)
	assert_gt(headings.size(), 2, "several of the eight headings over twelve seeds")
	var a := _valley(100, 2)
	var b := _valley(100, 3)
	assert_ne((a.doc as MapDocument).heights, (b.doc as MapDocument).heights)


func test_trough_depth_scales_with_size_and_the_rim_stays_at_the_base() -> void:
	# Seeds 9, 12 and 14 draw no water at 150 ft (the frame and the feature draws do not
	# depend on the size), so the floor is the trough alone.
	for size_ft in NewMap.SIZES_FT:
		var doc: MapDocument = _valley(size_ft, 9).doc
		var scale := StartingLandform.size_scale(doc)
		var depth := LandformRecipes.VALLEY_DEPTH_M * scale
		var fall := LandformRecipes.VALLEY_FALL_M * scale
		var lowest := INF
		var highest := -INF
		var at_base := 0
		for h in doc.heights:
			lowest = minf(lowest, h)
			highest = maxf(highest, h)
			at_base += 1 if absf(h) < 0.001 else 0
		assert_almost_eq(
			lowest, -(depth + fall), 0.05, "%d ft floor at the downstream end" % size_ft
		)
		assert_almost_eq(highest, 0.0, 0.001, "%d ft nothing above the base" % size_ft)
		assert_gt(
			float(at_base) / doc.sample_count(), 0.1, "%d ft a rim shelf at the base" % size_ft
		)
	assert_almost_eq(StartingLandform.size_scale(_valley(100, 9).doc), 0.8, 0.01)
	assert_almost_eq(StartingLandform.size_scale(_valley(200, 9).doc), 1.2, 0.01)


func test_forty_seeds_draw_rivers_often_and_never_break_the_map() -> void:
	var rivers := 0
	var crossings := 0
	var half := 15.24
	for seed_value in range(1, SEEDS + 1):
		var shaped := _valley(100, seed_value)
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		# P5-7: a crossing is drawn only where the river left water (straightest_wet).
		assert_false(String(shaped.report).contains("no_water"), "%s: %s" % [label, shaped.report])
		var out_of_range := 0
		for h in doc.heights:
			out_of_range += 1 if absf(h) > MapDocument.MAX_ABS_HEIGHT_M else 0
		assert_eq(out_of_range, 0, "%s heights within the limit" % label)
		var packed := MapDocumentIO.serialize(doc)
		assert_eq(packed.error, "", label)
		var parsed := MapDocumentIO.parse(packed.entries)
		assert_not_null(parsed.document, label)
		if parsed.document != null:
			assert_eq((parsed.document as MapDocument).crossings.size(), doc.crossings.size())
		var stage: Vector2 = shaped.stage
		assert_lte(
			stage.length(), half * 0.5 + 0.01, "%s stage within a quarter of the map" % label
		)
		assert_false(WaterGeometry.is_wet_at(doc, stage), "%s stage is dry" % label)
		var chains := _river_chains(doc)
		if chains.is_empty():
			assert_true(doc.crossings.is_empty(), "%s no crossing without water" % label)
			continue
		rivers += 1
		var main: Array[WaterBody] = chains[0]
		assert_gte(main.size(), 2, "%s river in reaches" % label)
		for k in main.size() - 1:
			assert_gte(main[k].level_m, main[k + 1].level_m, "%s reaches step down" % label)
		var course: PackedVector2Array = WaterCarve.joined_course(main).points
		assert_false(
			WaterFallPlan.is_uphill(WaterGeometry.ground_along(doc, course)),
			"%s river runs downhill" % label
		)
		for crossing in doc.crossings:
			crossings += 1
			assert_true(
				crossing.kind == Crossing.Kind.FORD or crossing.kind == Crossing.Kind.STONES,
				"%s crossing kind" % label
			)
			var middle := (crossing.start + crossing.end) * 0.5
			assert_true(WaterGeometry.is_wet_at(doc, middle), "%s crossing over water" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.start), "%s bank a" % label)
			assert_false(WaterGeometry.is_wet_at(doc, crossing.end), "%s bank b" % label)
	var share := float(rivers) / SEEDS
	assert_between(share, 0.6, 0.85, "rivers in %d of %d seeds" % [rivers, SEEDS])
	assert_gt(crossings, 0, "some seed drew a crossing")


func test_bluff_is_one_tier_on_one_bank_only() -> void:
	# P5-4: about half the seeds raise one bank (bluff_side_of: the far bank of a valley
	# crossing the view, else the outer) behind a one-tier rock face; the other bank keeps
	# the cosine slope and the floor its depth, so it is a valley, not a gorge.
	var bluffs := 0
	var checked := 0
	for seed_value in range(1, SEEDS + 1):
		var shaped := _valley(150, seed_value)
		var report: String = shaped.report
		if not report.contains("bluff"):
			continue
		bluffs += 1
		if not report.contains("dry") or checked >= 4:
			continue
		checked += 1
		var doc: MapDocument = shaped.doc
		var label := "seed %d" % seed_value
		var half := StartingLandform.half_extent(doc)
		var scale := StartingLandform.size_scale(doc)
		var tier := doc.tier_height_m
		var frame := LandformRecipes.valley_frame(
			half, StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		)
		var foot := StartingLandform.along(frame.axis, float(frame.foot_arc))
		var inner: Vector2 = (foot.dir as Vector2).rotated(float(frame.turn) * PI / 2.0)
		var bluff := inner * LandformRecipes.bluff_side_of(frame)
		var along := absf((frame.dir as Vector2).dot(StartingLandform.VIEW))
		if along <= cos(deg_to_rad(LandformRecipes.BLUFF_ALONG_DEG)):
			assert_gt(
				bluff.dot(StartingLandform.VIEW),
				0.0,
				"%s a valley across the view: the bluff on the far bank" % label
			)
		else:
			assert_eq(
				bluff, -inner, "%s a valley along the view: the bluff on the outer bank" % label
			)
		var rim := half * LandformRecipes.VALLEY_RIM_SHARE
		var probe := rim - 1.0
		var plain_h := WaterGeometry.ground_at(doc, foot.point - bluff * probe)
		var bluff_h := WaterGeometry.ground_at(doc, foot.point + bluff * probe)
		var cosine := (
			-(LandformRecipes.VALLEY_DEPTH_M * scale + LandformRecipes.VALLEY_FALL_M * scale * 0.5)
			* StartingLandform.trough_shape(probe, half * LandformRecipes.VALLEY_FLOOR_SHARE, rim)
		)
		assert_almost_eq(plain_h, cosine, 0.35, "%s the other bank keeps the cosine slope" % label)
		assert_lt(bluff_h, plain_h - 0.1, "%s the bluff bank is cut below the other" % label)
		assert_gt(
			bluff_h, cosine - tier - 0.35, "%s the bluff bank is cut one tier at most" % label
		)
		var beyond := rim + HeightBrush.tier_span(tier) + LandformRecipes.BLUFF_WOBBLE_M + 1.0
		assert_almost_eq(
			WaterGeometry.ground_at(doc, foot.point + bluff * beyond),
			0.0,
			0.01,
			"%s the base beyond the bluff" % label
		)
		var lowest := INF
		for h in doc.heights:
			lowest = minf(lowest, h)
		assert_almost_eq(
			lowest,
			-(LandformRecipes.VALLEY_DEPTH_M + LandformRecipes.VALLEY_FALL_M) * scale,
			0.05,
			"%s the floor keeps its depth" % label
		)
	assert_between(float(bluffs) / SEEDS, 0.3, 0.7, "bluffs in %d of %d seeds" % [bluffs, SEEDS])
	assert_gt(checked, 0, "some dry seed drew a bluff")


func test_tributary_joins_the_river() -> void:
	# Seed 4 draws a river and a tributary at every size.
	var doc: MapDocument = _valley(150, 4).doc
	var chains := _river_chains(doc)
	assert_eq(chains.size(), 2, "the river and its tributary")
	if chains.size() < 2:
		return
	var tributary: Array[WaterBody] = chains[1]
	var mouth: Vector2 = tributary[-1].points[-1]
	assert_eq(tributary[0].depth, WaterBody.Depth.ANKLE)
	assert_true(WaterGeometry.is_wet_at(doc, mouth, tributary[-1].id), "its mouth is in the river")


func test_dry_draw_paints_a_wash_of_the_scree_surface() -> void:
	var biome := PaletteLibrary.biome(BIOME)
	if biome.is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var shaped := _valley(150, 1234)
	var doc: MapDocument = shaped.doc
	assert_true(doc.water_bodies.is_empty(), "seed 1234 is dry")
	assert_true(doc.surface_ids.has(biome["scree_surface"]), shaped.report)
	assert_eq(MapDocumentIO.serialize(doc).error, "")


func test_new_map_centres_the_glade_on_the_stage() -> void:
	# The round glade, which every recipe but the Valley keeps (P5-7: the Valley's glade is its
	# floor; the next test). Was run on the Valley before P5-7.
	if PaletteLibrary.biome(BIOME).is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var seed_value := 3
	var doc := NewMap.create(
		150, BIOME, seed_value, PaletteLibrary.DEFAULT_ROOT, StartingLandform.HILLTOP
	)
	var flat := MapDocument.create_flat(
		Vector2i(NewMap.cells_for_feet(150), NewMap.cells_for_feet(150)), "grass", "", seed_value
	)
	var stage: Vector2 = (
		StartingLandform.apply(flat, StartingLandform.HILLTOP, seed_value, BIOME).stage
	)
	assert_gt(stage.length(), 5.0, "a stage off the centre makes the test mean something")
	assert_eq(doc.biome_slots.size(), doc.sample_count())
	var half := doc.extent_m() * 0.5
	var glade := 0.0
	var glade_n := 0
	var edge := 0.0
	var edge_n := 0
	var opposite := 0.0
	var opposite_n := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			var density := float(doc.biome_density[doc.sample_index(x, z)])
			var reach := (world - stage).length() / half.x
			if reach < 0.3:
				glade += density
				glade_n += 1
			elif reach > 0.8:
				edge += density
				edge_n += 1
			if (world + stage).length() / half.x < 0.3:
				opposite += density
				opposite_n += 1
	assert_lt(glade / glade_n, 0.5 * edge / edge_n, "open at the stage, dense toward the edges")
	assert_lt(glade / glade_n, opposite / opposite_n, "the glade moved with the stage")
	assert_eq(MapDocumentIO.serialize(doc).error, "")


func test_a_valley_glade_opens_the_floor_and_keeps_the_rim_dense() -> void:
	# P5-7: the Valley returns a line glade along its floor; the floor's centreline stays below
	# the glade threshold (halfway between the glade's density and the groves') for most of its
	# length, the far rim stays dense and the slope toward the camera stays thin.
	if PaletteLibrary.biome(BIOME).is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var threshold := (NewMap.COVER_CENTRE_DENSITY + NewMap.COVER_EDGE_DENSITY) * 0.5 * 255.0
	for seed_value in [3, 9, 21]:
		var label := "seed %d" % seed_value
		var shaped := _valley(150, seed_value)
		var glade: Dictionary = shaped.get("glade", {})
		assert_true(glade.has("line"), "%s the valley returns a line glade" % label)
		var doc := NewMap.create(
			150, BIOME, seed_value, PaletteLibrary.DEFAULT_ROOT, StartingLandform.VALLEY
		)
		var line: PackedVector2Array = glade.line
		var floor_half: float = glade.half_width
		var rim := floor_half + float(glade.rise)
		var open := 0
		var on_line := 0
		var rim_sum := 0.0
		var rim_n := 0
		var near_sum := 0.0
		var near_n := 0
		for z in doc.samples_z():
			for x in doc.samples_x():
				var world := doc.sample_to_world(Vector2(x, z))
				var at := StartingLandform.nearest_on(line, world)
				var distance := at.x
				var density := float(doc.biome_density[doc.sample_index(x, z)])
				if distance < doc.sample_step().x * 0.5:
					on_line += 1
					open += 1 if density < threshold else 0
					continue
				var k := int(at.z)
				var q := Geometry2D.get_closest_point_to_segment(world, line[k], line[k + 1])
				var facing := (world - q).normalized().dot(StartingLandform.NEAR)
				# The far rim keeps its groves; the near slope (P5-7) stays thin.
				if facing < -0.5 and absf(distance - rim) < 1.0:
					rim_sum += density
					rim_n += 1
				elif facing > 0.5 and distance > floor_half and distance < rim:
					near_sum += density
					near_n += 1
		gut.p(
			(
				"%s: %d of %d centreline samples open, far rim mean %.0f, near slope mean %.0f"
				% [label, open, on_line, rim_sum / maxf(rim_n, 1.0), near_sum / maxf(near_n, 1.0)]
			)
		)
		assert_gt(on_line, 20, "%s samples on the centreline" % label)
		assert_gt(float(open) / on_line, 0.8, "%s the floor's centreline is open" % label)
		assert_gt(rim_n, 10, "%s samples on the far rim" % label)
		assert_gt(rim_sum / rim_n, threshold, "%s the far rim stays dense" % label)
		assert_gt(near_n, 10, "%s samples on the near slope" % label)
		assert_lt(near_sum / near_n, threshold, "%s the near slope stays thin" % label)
