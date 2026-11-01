extends GutTest

## Houses and props kept on dry ground and off a village's bridges (villages phase 3, topic
## bridges round 2; docs/systems/villages.md section 12): the lot filter (pure, over wet flags and
## corridors: a dropped lot leaves a gap, the others stay as drawn), a lot's sample grid meets a
## narrow stream, the corridors reach past the banks, a dry map's street is exactly the plan, and a
## street over a river builds nothing on the water.

const RIVER_LEVEL := -0.2
const BED := -1.0


func before_all() -> void:
	StructureRecipes.ensure_served()


## A flat map with a river running north to south through x = 0, 3 m wide (as test_village_bridges).
static func _river_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var line := PackedVector2Array([Vector2(0, -15), Vector2(0, 15)])
	var widths := PackedFloat32Array([1.5, 1.5])
	doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.ANKLE, RIVER_LEVEL))
	return doc


## A street of both sides along x at z = 0, the default setback, the mixed species.
static func _street() -> Wall:
	var wall := Wall.make(
		7, Wall.Kind.ROW, PackedVector2Array([Vector2(-18, 0), Vector2(18, 0)]), false, 3.0
	)
	wall.side = ProcgenRow.SIDE_BOTH
	wall.preset = ProcgenRow.PRESET_MIXED
	wall.seed_value = 5
	return wall


static func _lot(index: int, from_x: float, width: float) -> Dictionary:
	return {
		"points":
		PackedVector3Array(
			[
				Vector3(from_x, 0, 3),
				Vector3(from_x + width, 0, 3),
				Vector3(from_x + width, 0, 9),
				Vector3(from_x, 0, 9),
			]
		),
		"plot": PackedVector3Array(),
		"side": 1.0,
		"index": index,
	}


# --- the filter (pure) ------------------------------------------------------------------------


func test_a_wet_lot_leaves_a_gap_and_the_others_stay_as_drawn() -> void:
	var lots: Array[Dictionary] = [_lot(0, -10, 4), _lot(1, -2, 4), _lot(2, 6, 4)]
	var samples := PackedVector2Array()
	var counts := PackedInt32Array()
	for lot in lots:
		var own := VillageDryGround.lot_samples(lot)
		samples.append_array(own)
		counts.append(own.size())
	var wet := PackedByteArray()
	wet.resize(samples.size())
	for i in samples.size():
		wet[i] = 1 if absf(samples[i].x) < 1.5 else 0
	var kept := VillageDryGround.kept_lots(lots, samples, counts, wet, [])
	assert_eq(kept.size(), 2, "the lot over the stream is dropped")
	assert_eq(kept[0], lots[0], "the lot before it is the plan's own")
	assert_eq(kept[1], lots[2], "and the one after it: a gap, not a reshuffle")
	var none := PackedByteArray()
	none.resize(samples.size())
	assert_eq(VillageDryGround.kept_lots(lots, samples, counts, none, []).size(), 3, "all dry")


func test_a_lot_sample_grid_meets_a_narrow_stream_under_the_house() -> void:
	var lot := _lot(0, -5, 10)
	var met := false
	for p in VillageDryGround.lot_samples(lot):
		met = met or absf(p.x - 0.3) < 0.5
	assert_true(met, "a 1 m stream under the middle of a 10 m house meets a sample")
	var reach := -INF
	for p in VillageDryGround.lot_samples(lot):
		reach = maxf(reach, p.x)
	assert_almost_eq(reach, 5.0 + VillageDryGround.LOT_MARGIN_M, 0.01, "grown by the margin")


func test_a_corridor_reaches_past_the_banks_and_holds_its_width() -> void:
	var c := VillageDryGround.corridor(Vector2(-2, 0), Vector2(2, 0), 2.0)
	var corridors: Array[Dictionary] = [c]
	assert_true(VillageDryGround.in_corridors(Vector2(3.9, 0), corridors), "a landing 1.9 m on")
	assert_false(VillageDryGround.in_corridors(Vector2(6.1, 0), corridors), "past the landing")
	assert_true(VillageDryGround.in_corridors(Vector2(0, 1.9), corridors), "on the deck's side")
	assert_false(VillageDryGround.in_corridors(Vector2(0, 2.1), corridors), "beside it")
	assert_true(VillageDryGround.in_corridors(Vector2(0, 2.1), corridors, 0.3), "a prop's reach")
	var lot := _lot(0, -1, 2)
	var samples := VillageDryGround.lot_samples(lot)
	var dry := PackedByteArray()
	dry.resize(samples.size())
	var lots: Array[Dictionary] = [lot]
	var near: Array[Dictionary] = [VillageDryGround.corridor(Vector2(0, -2), Vector2(0, 2), 1.0)]
	assert_eq(
		VillageDryGround.kept_lots(lots, samples, PackedInt32Array([samples.size()]), dry, near).size(),
		0,
		"a dry lot on a bridge's landing is dropped"
	)


func test_every_crossing_has_a_corridor_for_the_props() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	doc.crossings.append(
		Crossing.make(1, Crossing.Kind.PLANK, Vector2(-2, 5), Vector2(2, 5), Vector3.ZERO, 3.0)
	)
	var corridors := VillageDryGround.crossing_corridors(doc)
	assert_eq(corridors.size(), 1)
	assert_true(VillageDryGround.in_corridors(Vector2(3.5, 5), corridors), "the landing")
	assert_false(VillageDryGround.in_corridors(Vector2(0, 8), corridors), "the bank beside it")


func test_a_prop_at_the_waters_edge_is_wet_by_its_ring() -> void:
	var doc := _river_doc()
	# A log pile 2.2 m from the river's middle (its bank at 1.5 m): its centre is dry, its drawn
	# radius (0.6 / 0.8 m) and the bank strip reach the water.
	var ring := VillageDryGround.prop_ring(Vector2(2.2, 5.0), 0.6)
	assert_eq(ring.size(), VillageDryGround.PROP_RING_POINTS)
	var wet := VillageDryGround.wet_flags(doc, ring, Rect2(-5, 0, 10, 10))
	assert_eq(wet[0], 0, "the centre is on the bank")
	assert_gt(Array(wet).count(1), 0, "the ring reaches the water")
	var far := VillageDryGround.wet_flags(
		doc, VillageDryGround.prop_ring(Vector2(6.0, 5.0), 0.6), Rect2(-5, 0, 15, 10)
	)
	assert_eq(Array(far).count(1), 0, "a prop well up the bank stands")
	for p in ring:
		assert_eq(
			WaterGeometry.is_wet_at(doc, p),
			wet[ring.find(p)] != 0,
			"wet_flags agrees with is_wet_at at %s" % p
		)


# --- the document ------------------------------------------------------------------------------


func test_a_dry_map_street_is_exactly_its_plan() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var wall := _street()
	var plan := WallGeometry.row_plan(doc, wall)
	assert_gt(plan.size(), 4)
	assert_eq(WallGeometry.row_lots(doc, wall), plan, "every lot stands")
	assert_true(
		is_same(VillageDryGround.dry_lots(doc, wall, plan), plan), "the plan itself comes back"
	)
	var geometry := PlantGeometry.new()
	assert_true(is_same(VillageDryGround.without_lots(geometry, {}), geometry), "nothing rebuilt")
	assert_eq(VillageDryGround.street_corridors(doc, wall).size(), 0, "no water, no corridor")
	# The key is the one it was before water mattered: the same fields, nothing appended.
	var samples := PackedFloat32Array()
	var a := wall.points[0]
	var b := wall.points[1]
	var steps := maxi(1, ceili(a.distance_to(b) / WallGeometry.KEY_STEP_M))
	for s in steps + 1:
		samples.append(WaterGeometry.ground_at(doc, a.lerp(b, float(s) / steps)))
	var old_key := hash(
		[
			doc.map_seed,
			wall.id,
			wall.kind,
			wall.points,
			wall.closed,
			wall.height_m,
			wall.style,
			wall.seed_value,
			wall.side,
			wall.preset,
			WallGeometry.textured,
			samples,
		]
	)
	assert_eq(WallGeometry.key_of(doc, wall), old_key, "a dry street's key is unchanged")


func test_a_street_over_a_river_stands_no_lot_on_the_water() -> void:
	var doc := _river_doc()
	var wall := _street()
	var plan := WallGeometry.row_plan(doc, wall)
	var lots := WallGeometry.row_lots(doc, wall)
	assert_lt(lots.size(), plan.size(), "the lots over the river are dropped")
	assert_gt(lots.size(), 2, "houses still stand on both banks")
	var west := 0
	var east := 0
	var at := 0
	for lot in lots:
		while at < plan.size() and plan[at] != lot:
			at += 1
		assert_lt(at, plan.size(), "each kept lot is the plan's own, in order")
		for p in VillageDryGround.lot_samples(lot):
			assert_false(WaterGeometry.is_wet_at(doc, p), "no lot sample on the water")
		var middle: Vector3 = (lot.points[0] + lot.points[2]) * 0.5
		if middle.x < 0.0:
			west += 1
		else:
			east += 1
	assert_gt(west, 0, "a house on the west bank")
	assert_gt(east, 0, "and on the east")
	assert_eq(VillageDryGround.street_corridors(doc, wall).size(), 1, "one crossing corridor")
	assert_ne(
		WallGeometry.key_of(doc, wall),
		WallGeometry.key_of(MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9), wall),
		"water under the lots is in the key"
	)


func test_a_street_over_a_river_builds_nothing_on_the_water() -> void:
	var doc := _river_doc()
	var wall := _street()
	var parts := WallGeometry.build_one(doc, wall)
	var drawn := 0
	for key: String in ["stone", "masonry", "wood", "glass", WallGeometry.ROOF_PART]:
		var arrays: Array = parts[key]
		if arrays.is_empty():
			continue
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			drawn += 1
			assert_false(absf(v.x) < 1.0, "no building over the river at %s" % v)
			if absf(v.x) < 1.0:
				return
	assert_gt(drawn, 0, "the dry lots are built")
	var dry := WallGeometry.build_one(MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9), wall)
	var dry_drawn := 0
	for key: String in ["stone", "masonry", "wood", "glass", WallGeometry.ROOF_PART]:
		var arrays: Array = dry[key]
		if not arrays.is_empty():
			dry_drawn += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_lt(drawn, dry_drawn, "fewer houses than on a dry map")
