extends GutTest

## LandformGrowth (big and long maps, 2026-10-09): a square map of 250 ft or less has no room
## and grows nothing, a big or long map has room; a long map's linear landforms turn along
## it, its hill and lake move toward an end and its terraces spread; a wide map's frames take
## each seed's own heading, so neighbouring seeds stand apart; the extras are drawn
## from the palette by the seed, and each lands on open ground clear of the stage, the water
## and the map edge, a tarn wet, a knoll raised, a meadow and a tarn's shore open in the
## cover. Built on small long maps (200 x 100 ft): a long map has full room at any size, so the
## big-size look is a render job (jobs/biglf_look.json), not a test.

const BIOME := "temperate_forest_summer_s1"
const LONG := Vector2i(40, 20)
const SEEDS := 6

## Valley builds on the long map by seed, shared by the tests that read them.
var _valleys: Dictionary = {}


func _doc(cells: Vector2i, seed_value: int = 1) -> MapDocument:
	return MapDocument.create_flat(cells, "grass", "", seed_value)


func _shaped(kind: String, seed_value: int) -> Dictionary:
	var key := "%s_%d" % [kind, seed_value]
	if not _valleys.has(key):
		var doc := _doc(LONG, seed_value)
		var shaped := StartingLandform.apply(doc, kind, seed_value, BIOME)
		shaped["doc"] = doc
		_valleys[key] = shaped
	return _valleys[key]


func test_square_maps_up_to_250_ft_have_no_room() -> void:
	for feet in [100, 150, 200, 250]:
		var cells := NewMap.cells_for_feet(feet)
		assert_eq(LandformGrowth.room(_doc(Vector2i(cells, cells))), 0.0, "%d ft" % feet)
	assert_almost_eq(LandformGrowth.room(_doc(Vector2i(64, 64))), 1.0, 0.001, "320 ft is full")
	var between := LandformGrowth.room(_doc(Vector2i(57, 57)))
	assert_between(between, 0.1, 0.9, "285 ft grows part way")
	assert_almost_eq(LandformGrowth.room(_doc(LONG)), 1.0, 0.001, "twice as long is full")
	assert_almost_eq(LandformGrowth.room(_doc(Vector2i(24, 20))), 0.2, 0.001, "1.2 to 1")


func test_growth_leaves_a_map_without_room_as_it_was() -> void:
	var doc := _doc(Vector2i(50, 50))
	var before := doc.heights.duplicate()
	var shaped := {"stage": Vector2.ZERO, "report": "valley"}
	LandformGrowth.grow(doc, StartingLandform.VALLEY, 3, shaped)
	assert_eq(shaped.report, "valley")
	assert_false(shaped.has("clearings"))
	assert_eq(doc.heights, before)
	assert_true(doc.water_bodies.is_empty())


func test_a_long_map_turns_a_heading_across_it() -> void:
	var long := _doc(LONG)
	var tall := _doc(Vector2i(16, 32))
	var square := _doc(Vector2i(20, 20))
	assert_true(LandformGrowth.is_long(long))
	assert_false(LandformGrowth.is_long(square))
	assert_eq(LandformGrowth.long_dir(tall), Vector2.DOWN)
	var across := Vector2(0.0, 1.0)
	assert_almost_eq(absf(LandformGrowth.turned(long, across).x), 1.0, 0.001)
	assert_almost_eq(absf(LandformGrowth.turned(tall, Vector2.RIGHT).y), 1.0, 0.001)
	var diagonal := Vector2(1.0, 1.0).normalized()
	assert_eq(LandformGrowth.turned(long, diagonal), diagonal, "a diagonal stays")
	assert_eq(LandformGrowth.turned(square, across), across, "a square map turns nothing")
	for seed_value in range(1, 13):
		var rng := StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		var frame := LandformRecipes.valley_frame(StartingLandform.half_extent(long), rng, long)
		var dir: Vector2 = frame.dir
		assert_gte(absf(dir.x), 0.7, "seed %d's valley runs along the long map" % seed_value)


func test_the_long_map_shapes_spread_along_it() -> void:
	var long := _doc(LONG)
	var half := StartingLandform.half_extent(long)
	var long_half := LandformGrowth.long_half(long)
	assert_almost_eq(LandformTerraces.span_of(long, Vector2.RIGHT, half), long_half, 0.001)
	assert_almost_eq(LandformTerraces.span_of(long, Vector2.DOWN, half), half, 0.001)
	var square := _doc(Vector2i(30, 30))
	assert_eq(LandformHilltop.toward_end(square, 22.86, 4), Vector2.ZERO)
	var shift := LandformHilltop.toward_end(long, half, 4)
	assert_almost_eq(shift.y, 0.0, 0.001, "along the length")
	assert_gt(absf(shift.x), half * 0.3)
	var frame := LandformLakeshore.lakeshore_frame(
		half, StartingLandform.stream(1, StartingLandform.STREAM_FRAME), long
	)
	if LandformLakeshore._is_far(frame.corner):
		var centre: Vector2 = frame.centre
		var inward := half * (1.0 - LandformLakeshore.LAKE_CENTRE_SHARE)
		assert_almost_eq(absf(centre.x), long_half - inward, 0.01, "in the map's own corner")


func test_a_big_valley_may_meander_and_keeps_its_foot() -> void:
	var big := _doc(Vector2i(64, 64))
	var half := StartingLandform.half_extent(big)
	var meanders := 0
	for seed_value in range(1, 13):
		var rng := StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		var frame := LandformRecipes.valley_frame(half, rng, big, seed_value)
		var foot: Vector2 = StartingLandform.along(frame.axis, frame.foot_arc).point
		var turn := LandformRecipes._meander(big, frame, seed_value)
		var axis: PackedVector2Array = frame.axis
		if turn != 0.0:
			meanders += 1
			assert_eq(axis.size(), 4)
			assert_between(absf(turn), 30.0, 48.0)
		var moved: Vector2 = StartingLandform.along(axis, frame.foot_arc).point
		assert_almost_eq(moved.distance_to(foot), 0.0, 0.01, "seed %d's foot stays" % seed_value)
	assert_between(meanders, 3, 11, "some meander, not all")


func test_extras_come_from_the_palette_by_the_seed() -> void:
	var palette: Dictionary = LandformGrowth.PALETTES[StartingLandform.VALLEY]
	var counts := {}
	var names := {}
	for seed_value in range(1, 41):
		var rng := StartingLandform.stream(seed_value, LandformGrowth.STREAM_EXTRAS)
		assert_true(LandformGrowth.extras(palette, 0.0, rng).is_empty(), "no room, no extras")
		var picks := LandformGrowth.extras(palette, 1.0, rng)
		counts[picks.size()] = true
		assert_between(picks.size(), 1, 2)
		for pick in picks:
			assert_true(palette.has(pick), pick)
			names[pick] = true
		if picks.size() == 2:
			assert_ne(picks[0], picks[1])
	assert_true(counts.has(1) and counts.has(2), "one extra or two")
	assert_eq(names.size(), palette.size(), "every extra drawn over forty seeds")


func test_a_spot_keeps_clear_and_inside() -> void:
	var doc := _doc(LONG)
	var rng := StartingLandform.stream(7, LandformGrowth.STREAM_EXTRAS)
	var want := {"radius": 4.0, "inset": 1.2, "water_gap": 2.0, "lean": 0.0, "tie": 0.0}
	var avoid: Array = [{"at": Vector2(10.0, 0.0), "radius": 6.0}]
	var at := LandformPlacement.find_spot(doc, rng, want, avoid, [], Vector2.ZERO)
	assert_ne(at, Vector2.INF)
	assert_gte(at.distance_to(Vector2(10.0, 0.0)), 10.0)
	assert_true(StartingLandform.inside(doc, at, 4.0 * 1.2 - 0.01))
	var everywhere: Array = [{"at": Vector2.ZERO, "radius": 100.0}]
	assert_eq(
		LandformPlacement.find_spot(doc, rng, want, everywhere, [], Vector2.ZERO), Vector2.INF
	)


func test_long_valleys_grow_extras_that_stand_on_their_own() -> void:
	var drawn := {}
	for seed_value in range(1, SEEDS + 1):
		var shaped := _shaped(StartingLandform.VALLEY, seed_value)
		var doc: MapDocument = shaped.doc
		var stage: Vector2 = shaped.stage
		assert_false(WaterGeometry.is_wet_at(doc, stage), "seed %d: the stage is dry" % seed_value)
		var report := String(shaped.report)
		for extra in LandformGrowth.PALETTES[StartingLandform.VALLEY]:
			if report.contains("%s at" % extra) or report.contains("%s " % extra):
				drawn[extra] = true
		for clearing: Dictionary in shaped.get("clearings", []):
			var at: Vector2 = clearing.at
			assert_true(StartingLandform.inside(doc, at, 0.0), "seed %d" % seed_value)
			assert_gte(at.distance_to(stage), LandformGrowth.STAGE_CLEAR_M, "seed %d" % seed_value)
		assert_eq(MapDocumentIO.serialize(doc).error, "", "seed %d writes" % seed_value)
	assert_gt(drawn.size(), 1, "the seeds draw different extras")


func test_a_tarn_is_wet_and_a_knoll_stands_up() -> void:
	var doc := _doc(LONG)
	var rng := StartingLandform.stream(3, LandformGrowth.STREAM_EXTRAS)
	var before := WaterGeometry.ground_at(doc, Vector2(-12.0, 0.0))
	LandformGrowth.knoll(doc, Vector2(-12.0, 0.0), 6.0, 3.0, rng)
	assert_almost_eq(WaterGeometry.ground_at(doc, Vector2(-12.0, 0.0)) - before, 3.0, 0.05)
	assert_almost_eq(WaterGeometry.ground_at(doc, Vector2(-12.0, 9.0)), before, 0.001)
	var body := LandformGrowth.tarn(doc, Vector2(12.0, 0.0), 5.0, rng)
	assert_not_null(body)
	assert_true(WaterGeometry.is_wet_at(doc, Vector2(12.0, 0.0)))
	assert_false(WaterGeometry.is_wet_at(doc, Vector2(12.0, 9.0)))


func test_open_ground_is_painted_with_the_biomes_meadow_surface() -> void:
	assert_eq(LandformPlacement.meadow_surface(""), "")
	var surface := LandformPlacement.meadow_surface(BIOME)
	if surface == "":
		pass_test("palette without a grass accent in %s" % BIOME)
		return
	assert_true(surface.begins_with("grass") or surface.begins_with("moss"), surface)
	var doc := _doc(LONG)
	var rng := StartingLandform.stream(5, LandformGrowth.STREAM_EXTRAS)
	LandformPlacement.paint_open(doc, surface, {"at": Vector2(8.0, 0.0), "radius": 6.0}, rng)
	var slot := doc.surface_ids.find(surface)
	assert_gte(slot, 0)
	assert_eq(_weight(doc, slot, Vector2(8.0, 0.0)), 255, "full at the centre")
	assert_eq(_weight(doc, slot, Vector2(8.0, 9.0)), 0, "nothing past the warped outline")


## Round 3 (2026-10-09): the greening runs on every map, not only one with room, and the edge
## band is greened too. Changed assertions: the 250 ft square is now painted like the long map
## (was: no surface at all), and the map edge is all meadow (was: nothing on the feather).
func test_thin_cover_and_the_edge_are_greened_on_every_map() -> void:
	var surface := LandformPlacement.meadow_surface(BIOME)
	if surface == "":
		pass_test("palette without a grass accent in %s" % BIOME)
		return
	# Thin cover west of x = 0, groves east of it; a long map and a 250 ft square alike.
	for cells in [LONG, Vector2i(50, 50)]:
		var doc := _covered(_doc(cells))
		LandformPlacement.paint_sparse(doc, BIOME)
		var slot := doc.surface_ids.find(surface)
		assert_gte(slot, 0, "%s: the meadow surface is painted" % cells)
		var greened := 0
		var thin := 0
		for z in range(-5, 6):
			for x in range(-20, -10):
				thin += 1
				greened += 1 if _weight(doc, slot, Vector2(x, z)) > 128 else 0
		assert_between(float(greened) / thin, 0.25, 1.0, "%s: thin cover greened" % cells)
		for z in range(-5, 6):
			for x in range(10, 20):
				assert_eq(_weight(doc, slot, Vector2(x, z)), 0, "%s: groves keep their floor" % cells)
		var half := doc.extent_m() * 0.5
		for z in range(-5, 6):
			for x in [-half.x, half.x]:
				assert_eq(_weight(doc, slot, Vector2(x, z)), 255, "%s: the edge is meadow" % cells)
		assert_eq(TerrainSkirt.edge_surface(doc), slot, "%s: the skirt continues it" % cells)


func test_the_edge_band_greens_over_the_feather_depth() -> void:
	var surface := LandformPlacement.meadow_surface(BIOME)
	if surface == "":
		pass_test("palette without a grass accent in %s" % BIOME)
		return
	# Groves everywhere: only the edge band is greened.
	var doc := _doc(Vector2i(50, 50))
	_covered(doc)
	doc.biome_density.fill(204)
	LandformPlacement.paint_sparse(doc, BIOME)
	var slot := doc.surface_ids.find(surface)
	var half := doc.extent_m() * 0.5
	var width := NewMap.edge_feather_m(half)
	var reach := width * (1.0 + NewMap.EDGE_FEATHER_WOBBLE)
	for z in range(-10, 11, 5):
		assert_eq(_weight(doc, slot, Vector2(half.x - 0.1, z)), 255, "full at the edge")
		assert_eq(_weight(doc, slot, Vector2(half.x - reach - 1.0, z)), 0, "none past the band")


func test_a_wood_thins_the_groves_toward_the_open_side() -> void:
	var half := Vector2(30.0, 30.0)
	var grove := 0.6
	var drawn := NewMap.wood_density(grove, Vector2.ZERO, half, {"density": 1.0})
	assert_almost_eq(drawn, grove, 0.001, "as drawn")
	var thin := NewMap.wood_density(grove, Vector2.ZERO, half, {"density": 0.5})
	assert_almost_eq(thin, lerpf(NewMap.COVER_CENTRE_DENSITY, grove, 0.5), 0.001, "thinned")
	var glade := NewMap.wood_density(0.1, Vector2.ZERO, half, {"density": 0.0})
	assert_eq(glade, 0.1, "the glade's own cover stays")
	var wood := {"density": 1.0, "side": Vector2.RIGHT, "lean": 0.8}
	var gathered := NewMap.wood_density(grove, Vector2(25.0, 0.0), half, wood)
	var opened := NewMap.wood_density(grove, Vector2(-25.0, 0.0), half, wood)
	assert_almost_eq(gathered, grove, 0.001, "the groves gather on their side")
	assert_lt(opened, grove * 0.5, "the far side opens")


func test_wide_hills_and_lakes_stand_toward_any_side_and_draw_their_wood() -> void:
	var places := {}
	var hill_sides := {}
	var woods := {}
	var large := 0
	for seed_value in range(1, 25):
		var rng := StartingLandform.stream(seed_value, StartingLandform.STREAM_SETTING)
		var wood := LandformPlacement.wood(rng, Vector2(0.4, 1.0), 0.5)
		woods["%.2f %s" % [float(wood.density), wood.has("side")]] = true
		rng.randf()
		rng.randf()
		rng.randf()
		var wide := _doc(Vector2i(50, 50), seed_value)
		var frame := LandformLakeshore.wide_frame(
			wide, StartingLandform.half_extent(wide), rng, seed_value
		)
		places[frame.corner] = true
		large += 1 if float(frame.radius) > 0.5 * StartingLandform.half_extent(wide) else 0
		var reach := (frame.centre as Vector2).abs() + Vector2.ONE * float(frame.radius)
		var half := wide.extent_m() * 0.5
		assert_lte(reach.x, half.x + 0.01, "seed %d on the map" % seed_value)
		assert_lte(reach.y, half.y + 0.01, "seed %d on the map" % seed_value)
	assert_gte(places.size(), 6, "the lake takes most of the eight places over 24 seeds")
	assert_between(large, 3, 16, "a larger lake sometimes")
	assert_gte(woods.size(), 20, "the wood differs seed to seed")
	for seed_value in range(1, 7):
		var doc := _doc(Vector2i(50, 50), seed_value)
		var shaped := StartingLandform.apply(doc, StartingLandform.HILLTOP, seed_value, BIOME)
		assert_true(shaped.has("wood"), "the hilltop draws a wood")
		var off := float(shaped.report.split(", ")[1].split(" m")[0])
		var half := StartingLandform.half_extent(doc)
		assert_gte(off, half * LandformHilltop.HILL_WIDE_OFFSET_SHARE.x - 0.1, "well off centre")
		hill_sides[shaped.report.split(" deg")[0]] = true
	assert_gt(hill_sides.size(), 2, "the hill stands toward several sides")


func test_a_wide_map_takes_each_seeds_own_heading() -> void:
	# 2026-10-10: the frame's eight headings gave seeds 1, 4 and 7 the same 315 in every
	# landform at 200 and 250 ft. Seeds 1-6 now stand apart as the camera sees them: a line
	# (the terraces' fall, a valley) at least 15 degrees on screen, a gorge 5 within its 32.5
	# either side of level (60 on the ground, clear of the camera's diagonal), a lake 8 m.
	var wide := _doc(Vector2i(50, 50))
	var half := StartingLandform.half_extent(wide)
	var small := _doc(Vector2i(30, 30))
	var long := _doc(LONG)
	var terraces: Array[float] = []
	var valleys: Array[float] = []
	var gorges: Array[float] = []
	var lakes: Array[Vector2] = []
	for seed_value in range(1, 7):
		var draw := func() -> RandomNumberGenerator:
			return StartingLandform.stream(seed_value, StartingLandform.STREAM_FRAME)
		var terrace := LandformTerraces.terraces_frame(half, draw.call(), wide, seed_value)
		terraces.append(_screen_deg(terrace.dir))
		var valley := LandformRecipes.valley_frame(half, draw.call(), wide, seed_value)
		valleys.append(_screen_deg(valley.dir))
		var gorge := LandformGorge.gorge_frame(half, false, draw.call(), wide, seed_value)
		var gorge_dir := Vector2.RIGHT.rotated(deg_to_rad(gorge.heading_deg))
		gorges.append(_screen_deg(gorge_dir))
		assert_lt(absf(gorge_dir.dot(StartingLandform.VIEW)), 0.87, "seed %d across" % seed_value)
		var setting := StartingLandform.stream(seed_value, StartingLandform.STREAM_SETTING)
		lakes.append(LandformLakeshore.wide_frame(wide, half, setting, seed_value).centre)
		# A map under 200 ft and a long map keep the frame's drawn (or turned) heading.
		for doc: MapDocument in [small, long]:
			var own := LandformTerraces.terraces_frame(half, draw.call(), doc, seed_value)
			var drawn := LandformTerraces.terraces_frame(half, draw.call())
			var turned := LandformGrowth.turned(doc, drawn.dir)
			assert_almost_eq((own.dir as Vector2).distance_to(turned), 0.0, 0.001)
	for a in 6:
		for b in range(a + 1, 6):
			var pair := "seeds %d and %d" % [a + 1, b + 1]
			assert_gte(_apart(terraces[a], terraces[b]), 15.0, "terraces " + pair)
			assert_gte(_apart(valleys[a], valleys[b]), 15.0, "valley " + pair)
			assert_gte(_apart(gorges[a], gorges[b]), 5.0, "gorge " + pair)
			assert_gte(lakes[a].distance_to(lakes[b]), 8.0, "lake " + pair)
	for g in gorges:
		assert_lte(absf(g), 32.6, "the gorge within its spread on screen")


## The screen angle (degrees, -90..90, from level) of the line along ground direction `d` as
## the camera sees it (LandformGrowth.VIEW_RISE).
func _screen_deg(d: Vector2) -> float:
	var across := Vector2(-StartingLandform.VIEW.y, StartingLandform.VIEW.x)
	var rise := LandformGrowth.VIEW_RISE * d.dot(StartingLandform.VIEW)
	return wrapf(rad_to_deg(atan2(rise, d.dot(across))), -90.0, 90.0)


## How far apart two lines' screen angles are (degrees, 0..90).
func _apart(a: float, b: float) -> float:
	var deg := absf(a - b)
	return minf(deg, 180.0 - deg)


func test_a_river_over_three_steps_jogs_aside() -> void:
	var frame := {"dir": Vector2.RIGHT, "normal": Vector2.DOWN}
	var plateaus: Array[Dictionary] = [{"edge": -10.0}, {"edge": 0.0}, {"edge": 10.0}]
	var line := LandformTerraces.river_line(plateaus, frame, 4.0, 30.0, 30.0)
	var jog := maxf(30.0 * LandformTerraces.JOG_SHARE, LandformTerraces.JOG_MIN_M)
	assert_almost_eq(line[1].y, 4.0, 0.001, "the first step crossed at the river's line")
	assert_almost_eq(line[3].y, 4.0 + jog, 0.001, "the next jogged away from the axis")
	assert_almost_eq(line[5].y, 4.0, 0.001, "and back")
	assert_almost_eq(line[3].x, -LandformTerraces.JOG_SQUARE_M, 0.001, "square over the edge")
	var two: Array[Dictionary] = [{"edge": -10.0}, {"edge": 10.0}]
	assert_eq(LandformTerraces.river_line(two, frame, 4.0, 30.0, 30.0).size(), 2, "straight")
	# On a wide or long map two steps already jog: the second step stands aside.
	var jogged := LandformTerraces.river_line(two, frame, 4.0, 30.0, 30.0, 2)
	assert_almost_eq(jogged[1].y, 4.0, 0.001, "the top step crossed at the river's line")
	assert_almost_eq(jogged[3].y, 4.0 + jog, 0.001, "the second jogged aside")
	assert_almost_eq(jogged[jogged.size() - 1].y, 4.0 + jog, 0.001, "and runs on from there")


## `doc` with BIOME painted: thin (0.1) west of x = 0, groves (0.8) east of it.
func _covered(doc: MapDocument) -> MapDocument:
	var slots := PackedByteArray()
	var density := PackedByteArray()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var thin := doc.sample_to_world(Vector2(x, z)).x < 0.0
			slots.append(1)
			density.append(26 if thin else 204)
	doc.biome_ids = PackedStringArray([BIOME])
	doc.biome_slots = slots
	doc.biome_density = density
	return doc


## The weight of surface `slot` at the sample nearest `p`.
func _weight(doc: MapDocument, slot: int, p: Vector2) -> int:
	var s := doc.world_to_sample(p).round()
	var i := doc.sample_index(int(s.x), int(s.y))
	return doc.surface_weights[MapDocument.surface_offset(i, slot, doc.sample_count())]


func test_a_clearing_opens_the_cover_and_leaves_the_rest() -> void:
	var clearings: Array = [{"at": Vector2(5.0, 0.0), "radius": 8.0}]
	var inside := NewMap.clearing_density(Vector2(5.0, 1.0), clearings, 0.6, 0.0)
	assert_lte(inside, NewMap.COVER_CENTRE_DENSITY * NewMap.CLEARING_OPEN_SHARE + 0.001)
	assert_eq(NewMap.clearing_density(Vector2(5.0, 12.0), clearings, 0.6, 0.0), 0.6)
