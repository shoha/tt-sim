extends GutTest

## The wet term of the scatter ground rules (phase 4, P4-3, ScatterGround): nothing roots in
## the water but emergent edge species in its shallows, bank species gather on the wet
## shore, trees keep off the waterline, tall cover thins to short cover there, and the
## plan's ground_role carries the water bits without changing a rock's role.


func _river_doc(depth: WaterBody.Depth) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var bodies := WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)]),
		PackedFloat32Array([2.0, 2.0]),
		depth
	)
	var goals := WaterCarve.river_goals(doc, bodies, doc.heights)
	var rect: Rect2i = goals.rect
	var heights := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal: float = goals.goals[j * rect.size.x + i]
			if not is_inf(goal):
				var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
				heights[at] = minf(heights[at], goal)
	doc.heights = heights
	doc.water_bodies = bodies
	WaterDressing.refresh(doc)
	return doc


func _sampler(doc: MapDocument) -> Callable:
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	return ScatterGround.sampler(doc, doc.heights, grid, PackedStringArray())


func test_nothing_roots_in_the_water() -> void:
	var at := _sampler(_river_doc(WaterBody.Depth.WAIST))
	for role in [
		ScatterGround.ROLE_COVER,
		ScatterGround.ROLE_ROCK,
		ScatterGround.ROLE_TREE,
		ScatterGround.ROLE_SHRUB,
		ScatterGround.ROLE_TALL_COVER,
		ScatterGround.ROLE_COVER | ScatterGround.EDGE_BANK,
		ScatterGround.ROLE_TALL_COVER | ScatterGround.EDGE_EMERGENT,
	]:
		var g: Vector3 = at.call(Vector2(0, 0), role)
		assert_almost_eq(g.x, 0.0, 1e-6, "role %d in waist-deep water" % role)
	for role in [ScatterGround.ROLE_COVER, ScatterGround.ROLE_TREE]:
		var far: Vector3 = at.call(Vector2(0, 8), role)
		assert_almost_eq(far.x, 1.0, 1e-6, "role %d far from the water" % role)


func test_reeds_stand_in_the_shallows_and_gather_at_the_edge() -> void:
	var doc := _river_doc(WaterBody.Depth.ANKLE)
	var at := _sampler(doc)
	var reeds := ScatterGround.ROLE_TALL_COVER | ScatterGround.EDGE_EMERGENT
	var middle: Vector3 = at.call(Vector2(0, 0), reeds)
	assert_gt(middle.x, 0.2, "ankle-deep water still holds reeds")
	var edge: Vector3 = at.call(Vector2(0, 1.8), reeds)
	assert_gt(edge.x, 1.5, "and they gather at the waterline")
	var grass: Vector3 = at.call(Vector2(0, 0), ScatterGround.ROLE_COVER)
	assert_almost_eq(grass.x, 0.0, 1e-6, "grass does not grow in the water")


func test_the_bank_band_by_role() -> void:
	var doc := _river_doc(WaterBody.Depth.WAIST)
	var at := _sampler(doc)
	var bank := Vector2(0, 2.4)
	var water := WaterDressing.sample(
		doc.water_dressing, doc.samples_x(), doc.samples_z(), doc.world_to_sample(bank)
	)
	assert_gt(water.y, 0.7, "on the wet shore")
	assert_lt(water.x, 0.1)
	var tree: Vector3 = at.call(bank, ScatterGround.ROLE_TREE)
	var willow: Vector3 = at.call(bank, ScatterGround.ROLE_TREE | ScatterGround.EDGE_BANK)
	var tall: Vector3 = at.call(bank, ScatterGround.ROLE_TALL_COVER)
	var grass: Vector3 = at.call(bank, ScatterGround.ROLE_COVER)
	var flower: Vector3 = at.call(bank, ScatterGround.ROLE_COVER | ScatterGround.FLOWER_BIT)
	assert_lt(tree.x, 0.2, "trees keep off the waterline")
	assert_gt(willow.x, 1.5, "willows gather there")
	assert_lt(tall.x, 0.2, "tall cover thins to short cover")
	assert_almost_eq(grass.x, 1.0, 1e-6, "short cover stays")
	assert_lt(flower.x, grass.x, "flowers thin")
	assert_gt(flower.x, 0.3)
	assert_eq(ScatterGround.species_density(0.9, willow, ScatterGround.ROLE_TREE), 1.0)


func test_plan_role_carries_the_water_bits() -> void:
	assert_eq(
		ScatterGround.plan_role({"key": "reeds", "kind": "grass", "size_class": "ground"}),
		ScatterGround.ROLE_COVER | ScatterGround.EDGE_EMERGENT
	)
	assert_eq(
		ScatterGround.plan_role({"key": "willow", "kind": "tree", "size_class": "large"}),
		ScatterGround.ROLE_TREE | ScatterGround.EDGE_BANK
	)
	assert_eq(
		ScatterGround.plan_role({"key": "daisy", "kind": "flower", "size_class": "ground"}),
		ScatterGround.ROLE_COVER | ScatterGround.FLOWER_BIT
	)
	assert_eq(
		ScatterGround.plan_role({"key": "boulder", "kind": "rock", "size_class": "medium"}),
		ScatterGround.ROLE_ROCK,
		"a rock's role is exactly ROLE_ROCK (RockKeep reads it)"
	)


func test_dry_maps_are_unchanged() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var at := _sampler(doc)
	for role in [ScatterGround.ROLE_TREE, ScatterGround.ROLE_COVER | ScatterGround.EDGE_BANK]:
		var g: Vector3 = at.call(Vector2(1, 1), role)
		assert_almost_eq(g.x, 1.0, 1e-6)


func test_wet_biome_surfaces_default_by_biome() -> void:
	var forest := PaletteLibrary.biome("temperate_forest_summer_s1")
	if forest.is_empty():
		pending("no palette")
		return
	assert_eq(forest.get("water_bed_surface"), "riverbed")
	assert_eq(forest.get("shore_surface"), "moss", "mossy forest banks (P4-4)")
	var badlands := PaletteLibrary.biome("rocky_badlands_summer_s1")
	assert_eq(badlands.get("shore_surface"), "gravel_sandstone")
	var validated := (
		PaletteLibrary
		. validate_palette(
			{
				"format": 1,
				"surfaces":
				{
					"grass": {"albedo": "a.png", "tile_m": 2.0, "kind": "grass", "role": "ground"},
					"sand": {"albedo": "s.png", "tile_m": 2.0, "kind": "sand", "role": "ground"},
					"cobble": {"albedo": "c.png", "tile_m": 2.0, "kind": "c", "role": "built"},
				},
				"biomes":
				[
					{
						"id": "b",
						"biome": "savanna",
						"ground_surface": "grass",
						"shore_surface": "cobble",
						"species":
						[
							{
								"key": "g",
								"kind": "grass",
								"size_class": "ground",
								"density_per_m2": 1.0,
								"assets": ["b/g"],
							}
						],
					}
				],
				"assets":
				{"b/g": {"file": "assets/b/g.glb", "node": "g", "wind_category": "grass"}},
			}
		)
	)
	var biome: Dictionary = validated.palette.biomes[0]
	assert_eq(biome.water_bed_surface, "", "riverbed is not in this palette")
	assert_eq(biome.shore_surface, "sand", "a built shore warns and takes the default")
