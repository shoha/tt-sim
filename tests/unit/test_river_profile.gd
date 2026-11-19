extends GutTest

## The river profile (card painter-river-profile): one profile per stroke (RiverProfile) with
## the falls as entries of their own, read by the carve. The sill runs through the lip, so the
## channel keeps its wetted width there (before: the first row past the lip of a short ankle
## fall was 2 of 4 samples wet, the C2 pinch); a pond dug beside a stream's head yields to the
## stream's bed and banks (before: the tall ankle fall's upper reach held 1 of 9 stations, C7);
## stations flag water whose ground was dug away.

const GRASS := "grass"
const Fixtures := preload("res://tests/unit/water_fixtures.gd")


## A 150 ft map at the default 0.25 m spacing (tier 1.524 m).
func _doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(30, 30), GRASS, "test", 5)


func _profile(doc: MapDocument, bodies: Array[WaterBody]) -> RiverProfile:
	return RiverProfile.for_doc(doc, bodies)


## Samples in the band `band` (metres along the flow from the lip) within the half-width plus
## 0.5 m whose ground lies under the fall's upper level.
func _band(doc: MapDocument, fall: Dictionary, band: Vector2) -> int:
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var reach := float(fall.half_width) + 0.5
	var count := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			var along := (p - lip).dot(dir)
			if along <= band.x or along > band.y or absf((p - lip).cross(dir)) > reach:
				continue
			if doc.heights[doc.sample_index(x, z)] < float(fall.top) - 0.005:
				count += 1
	return count


## The wetted width (metres, 5 cm steps over the bilinear ground under the upper level) across
## the channel `along` metres past the lip.
func _wetted(doc: MapDocument, fall: Dictionary, along: float) -> float:
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var side := Vector2(-dir.y, dir.x)
	var hw: float = fall.half_width
	var wet := 0.0
	var t := -hw - 0.6
	while t <= hw + 0.6:
		if WaterGeometry.ground_at(doc, lip + dir * along + side * t) < float(fall.top) - 0.005:
			wet += 0.05
		t += 0.05
	return wet


func test_a_stroke_without_falls_has_no_sill_and_no_fall_entries() -> void:
	var doc := _doc()
	var bodies := Fixtures.river(doc, Vector2(-10, 0), Vector2(10, 0), 1.0)
	var profile := _profile(doc, bodies)
	assert_true(profile.falls.is_empty(), "no fall entries on flat ground")
	var s := 0.0
	while s <= profile.total:
		assert_eq(profile.at(s).w, 0.0, "no sill at %.2f" % s)
		assert_eq(profile.at(s).z, 0.0, "no gorge at %.2f" % s)
		s += 0.5


func test_a_fall_is_an_entry_lip_foot_plunge_in_order() -> void:
	var doc := _doc()
	var bodies := Fixtures.tier_fall(doc, 0.55, WaterBody.Depth.ANKLE)
	var profile := _profile(doc, bodies)
	assert_eq(profile.falls.size(), 1, "one fall over the tier")
	if profile.falls.is_empty():
		return
	var fall: Dictionary = profile.falls[0]
	assert_almost_eq(float(fall.lip), profile.bounds[int(fall.step)], 1e-6, "the lip is the step")
	assert_lt(float(fall.lip), float(fall.foot), "the foot below the lip")
	assert_lt(float(fall.foot), float(fall.plunge), "the plunge pool past the foot")
	assert_gt(float(fall.drop), WaterFalls.FALL_MIN_DROP_M, "a fall's drop")
	assert_eq(profile.fall_at(float(fall.lip) + 0.1), fall, "the face belongs to the fall")
	assert_true(profile.fall_at(float(fall.lip) - 0.1).is_empty(), "above the lip is not the face")


func test_the_level_never_rises_and_the_width_never_steps() -> void:
	var doc := _doc()
	var bodies := Fixtures.tier_fall(doc, 1.0)
	var profile := _profile(doc, bodies)
	var stations := profile.stations(doc, 0.25)
	var level: PackedFloat32Array = stations.level
	var widths: PackedFloat32Array = stations.half_width
	var arcs: PackedFloat32Array = stations.arc
	assert_gt(level.size(), 40, "stations every 0.25 m")
	# The rounded heads at the tapered ends (WaterCarve.head_width) open from nothing.
	var head := maxf(WaterCarve.pool_tail(profile.depth), 1.0 * WaterCarve.HEAD_PER_WIDTH)
	for n in range(1, level.size()):
		assert_true(level[n] <= level[n - 1] + 1e-5, "level monotone at station %d" % n)
		if arcs[n - 1] < head or arcs[n] > profile.total - head:
			continue
		var step := absf(widths[n] - widths[n - 1])
		assert_true(step <= 0.15 * maxf(widths[n], 0.3), "no width step at station %d" % n)


func test_the_sill_runs_through_the_lip_and_down_the_face() -> void:
	var doc := _doc()
	var bodies := Fixtures.tier_fall(doc, 0.55, WaterBody.Depth.ANKLE)
	var profile := _profile(doc, bodies)
	if profile.falls.is_empty():
		fail_test("no fall")
		return
	var fall: Dictionary = profile.falls[0]
	var lip := float(fall.lip)
	var tail := WaterCarve.step_shape(float(fall.upper), float(fall.lower), profile.depth, true).y
	assert_eq(profile.at(lip - tail - 0.5).w, 0.0, "the flat reach above the pool tail")
	assert_almost_eq(profile.at(lip).w, 1.0, 1e-6, "the sill at the lip")
	# The row past the lip took the lower reach's rounded section before (the C2 pinch).
	assert_almost_eq(profile.at(lip + 0.1).w, 1.0, 1e-6, "the sill just past the lip")
	assert_almost_eq(profile.at(lip + 0.25).w, 1.0, 1e-6, "the sill a sample past the lip")
	assert_eq(profile.at(float(fall.foot) + 0.2).w, 0.0, "no sill in the plunge pool")
	var line := profile.at(lip + 0.1)
	assert_almost_eq(
		line.x - line.y, WaterCarve.fall_crest_depth(profile.depth), 1e-4, "a crest's water"
	)


func _assert_width_holds(doc: MapDocument, label: String) -> void:
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1, "%s: one fall" % label)
	if falls.is_empty():
		return
	var fall: Dictionary = falls[0]
	var upstream := _band(doc, fall, Vector2(-1.25, -1.0))
	var last_row := _band(doc, fall, Vector2(-0.25, 0.0))
	var past := _band(doc, fall, Vector2(0.0, 0.25))
	var width := 2.0 * float(fall.half_width)
	var at_lip := _wetted(doc, fall, 0.05)
	gut.p(
		(
			"%s: wet samples upstream %d, last row %d, past the lip %d; wetted %.2f m of %.2f"
			% [label, upstream, last_row, past, at_lip, width]
		)
	)
	assert_true(last_row >= upstream, "%s: the last row before the lip keeps the width" % label)
	assert_true(past >= upstream, "%s: the first row past the lip keeps the width" % label)
	assert_gt(at_lip, width - 0.2, "%s: the wetted width at the lip is the channel's" % label)


func test_a_short_ankle_fall_keeps_its_width_through_the_lip() -> void:
	var doc := _doc()
	Fixtures.tier_fall(doc, 0.55, WaterBody.Depth.ANKLE)
	_assert_width_holds(doc, "short ankle")


func test_a_tall_ankle_fall_keeps_its_width_through_the_lip() -> void:
	var doc := _doc()
	Fixtures.tier(doc, Vector2(-30, -10), Vector2(30, -10), 10.0, 2.0 * doc.tier_height_m)
	Fixtures.river(doc, Vector2(0, -12), Vector2(0, 12), 0.55, WaterBody.Depth.ANKLE)
	_assert_width_holds(doc, "tall ankle")


func test_a_diagonal_fall_keeps_its_width_through_the_lip() -> void:
	var doc := _doc()
	Fixtures.tier(doc, Vector2(-45, -20), Vector2(25, 50), 20.0, doc.tier_height_m)
	Fixtures.river(doc, Vector2(-12, 0), Vector2(12, 0), 1.0)
	_assert_width_holds(doc, "diagonal waist")


func test_a_pond_dug_beside_a_stream_head_leaves_the_stream_its_water() -> void:
	# A tier whose south brink is at z -12, an ankle stream from (0, -9) over its north brink,
	# then a deep pond painted at the tier's south foot, its edge 1.5 m from the stream's head
	# (the fall spike's map, F4). Its banks reached 6 m into the plateau and took the stream's
	# bed and banks away.
	var doc := _doc()
	Fixtures.tier(doc, Vector2(-30, -6), Vector2(30, -6), 6.0, doc.tier_height_m)
	var bodies := Fixtures.river(doc, Vector2(0, -9), Vector2(0, 12), 0.55, WaterBody.Depth.ANKLE)
	var upper := bodies[0]
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	var id := doc.next_water_id()
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(Vector2(0, -14)) < 3.5:
				mask[doc.sample_index(x, z)] = id
	doc.pond_mask = mask
	var pond := WaterBody.pond(id, WaterBody.Depth.DEEP, WaterGeometry.pond_rim_level(doc, id))
	var waters := doc.water_bodies.duplicate()
	waters.append(pond)
	doc.water_bodies = waters
	var before := doc.heights.duplicate()
	Fixtures.carve(doc, WaterCarve.pond_goals(doc, pond, before))
	assert_lt(
		WaterGeometry.ground_at(doc, Vector2(0, -14)), pond.level_m - 1.0, "the pond is dug"
	)
	assert_lt(
		WaterGeometry.ground_at(doc, Vector2(4, -10.5)),
		WaterGeometry.ground_at(doc, Vector2(4, -6)) - 0.3,
		"its bank still cuts the plateau away from the stream"
	)
	var profile := _profile(doc, bodies)
	var stations := profile.stations(doc, 0.25)
	var undermined: PackedByteArray = stations.undermined
	var arcs: PackedFloat32Array = stations.arc
	var lost := 0
	for n in arcs.size():
		if arcs[n] < profile.bounds[0] and undermined[n] != 0:
			lost += 1
	assert_eq(lost, 0, "no station of the upper reach undermined")
	var held := 0
	var probes := 0
	var z := -8.5
	while z < upper.points[-1].y - 0.3:
		probes += 1
		if WaterGeometry.ground_at(doc, Vector2(0, z)) < upper.level_m:
			held += 1
		z += 0.5
	assert_eq(held, probes, "the upper reach keeps water at its centre all along")
	assert_gt(
		WaterGeometry.ground_at(doc, Vector2(0.7, -7.5)),
		upper.level_m,
		"the bank beside the head still holds"
	)


func test_stations_flag_water_whose_ground_was_dug_away() -> void:
	var doc := _doc()
	Fixtures.shape(doc, func(_p: Vector2) -> float: return 2.0)
	var bodies := Fixtures.river(doc, Vector2(-10, 0), Vector2(10, 0), 1.0)
	var profile := _profile(doc, bodies)
	var clean: PackedByteArray = profile.stations(doc, 0.5).undermined
	assert_eq(clean.count(1), 0, "a fresh channel holds everywhere")
	# Dig the south bank away from x 0 to 4 (a sculpt brush or a later dig).
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x > 0.0 and p.x < 4.0 and p.y > 1.0:
				heights[doc.sample_index(x, z)] = 0.0
	doc.heights = heights
	var dug := profile.stations(doc, 0.5)
	var flags: PackedByteArray = dug.undermined
	var centres: PackedVector2Array = dug.centre
	for n in flags.size():
		var inside := centres[n].x > 0.5 and centres[n].x < 3.5
		var outside := centres[n].x < -1.0 or centres[n].x > 5.0
		if inside:
			assert_eq(flags[n], 1, "undermined at x %.1f" % centres[n].x)
		elif outside:
			assert_eq(flags[n], 0, "held at x %.1f" % centres[n].x)
