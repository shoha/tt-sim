extends GutTest

## A river that runs into a lower pond (card painter-fall-continuity): WaterGeometry.fed_ponds(),
## the pond owning its mask in WaterGeometry.levels() and WaterMeshBuilder.sample_owners(), and
## the sheet WaterMeshBuilder.cascades() lays where the river falls to the pond's level (before,
## the river's flat surface stood over the pond and the bed showed under its edge as a tan band).

const RIVER_LEVEL := -0.2
const POND_LEVEL := -1.0
const POND_CENTRE := Vector2(0.0, 4.0)
const POND_RADIUS := 3.0


## A flat map 2 m deep everywhere, a straight river along +Z ending at z = 2 inside a pond
## (mask radius POND_RADIUS round POND_CENTRE, so the river meets it at z = 1), the pond at
## `pond_level`.
func _doc(pond_level: float = POND_LEVEL) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "", "", 0)
	var heights := PackedFloat32Array()
	heights.resize(doc.sample_count())
	heights.fill(-2.0)
	doc.heights = heights
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).distance_to(POND_CENTRE) <= POND_RADIUS:
				mask[doc.sample_index(x, z)] = 2
	doc.pond_mask = mask
	var river := WaterBody.new()
	river.id = 1
	river.kind = WaterBody.Kind.RIVER
	river.level_m = RIVER_LEVEL
	river.speed = 1.0
	river.points = PackedVector2Array([Vector2(0, -8), Vector2(0, -3), Vector2(0, 2)])
	river.half_widths = PackedFloat32Array([1.5, 1.5, 1.5])
	var pond := WaterBody.new()
	pond.id = 2
	pond.kind = WaterBody.Kind.POND
	pond.depth = WaterBody.Depth.DEEP
	pond.level_m = pond_level
	doc.water_bodies = [river, pond] as Array[WaterBody]
	return doc


func _index(doc: MapDocument, p: Vector2) -> int:
	var s := doc.world_to_sample(p).round()
	return doc.sample_index(int(s.x), int(s.y))


func test_a_river_ending_in_a_lower_pond_feeds_it() -> void:
	assert_eq(WaterGeometry.fed_ponds(_doc()), {1: 2})
	assert_eq(WaterGeometry.fed_ponds(_doc(-0.1)), {}, "a higher pond is not fed")


func test_the_pond_owns_its_mask_and_the_river_the_rest() -> void:
	var doc := _doc()
	var levels := WaterGeometry.levels(doc)
	assert_almost_eq(levels[_index(doc, Vector2(0, 3))], POND_LEVEL, 1e-5, "in the pond")
	assert_almost_eq(levels[_index(doc, Vector2(0, -2))], RIVER_LEVEL, 1e-5, "up the river")
	assert_almost_eq(
		WaterGeometry.level_at(doc, Vector2(0, 3)), POND_LEVEL, 1e-5, "level_at agrees"
	)
	var built := WaterMeshBuilder.build(doc)
	assert_eq(built.levels, levels, "the mesh's owners follow the water model")


func test_the_surface_falls_from_the_river_to_the_pond() -> void:
	var doc := _doc()
	var sheets := WaterMeshBuilder.cascades(doc)
	var previous := RIVER_LEVEL + 0.001
	var between := 0
	for k in 12:
		var i := _index(doc, Vector2(0, 1.0 + k * 0.25))
		if not sheets.has(i):
			continue
		var h: float = sheets[i]
		assert_true(h <= previous, "falls downstream (%.2f after %.2f)" % [h, previous])
		assert_between(h, POND_LEVEL, RIVER_LEVEL + 0.001)
		if h < RIVER_LEVEL - 0.05 and h > POND_LEVEL + 0.05:
			between += 1
		previous = h
	assert_gt(between, 4, "a ramp, not a step")
	assert_false(sheets.has(_index(doc, Vector2(0, 6))), "the pond's own flat beyond it")
	var higher := _doc(-0.1)
	assert_false(
		WaterMeshBuilder.cascades(higher).has(_index(higher, Vector2(0, 1.5))),
		"no sheet into a higher pond"
	)
