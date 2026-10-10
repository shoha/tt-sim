extends GutTest

## NewMap: the documents authoring starts from. Sizes, the base surface a starting biome
## implies, the starting cover it paints, and the dressing document over a Blender map.

const BIOME := "temperate_forest_summer_s1"


func test_each_size_is_whole_even_cells() -> void:
	var expected := {100: 20, 150: 30, 200: 40}
	for feet in NewMap.SIZES_FT:
		var doc := NewMap.create(feet, NewMap.BARE_BIOME, 3)
		assert_eq(doc.size_cells, Vector2i(expected[feet], expected[feet]), "%d ft" % feet)
		assert_eq(doc.heights.size(), doc.sample_count(), "flat heights on the whole grid")
		assert_true(doc.scatter.is_empty(), "rows are generated once the map is shown")
		assert_eq(MapDocumentIO.serialize(doc)["error"], "", "writable as created")


func test_a_custom_map_is_width_by_depth_in_whole_squares() -> void:
	var flat := StartingLandform.FLAT
	var doc := NewMap.create(200, NewMap.BARE_BIOME, 3, PaletteLibrary.DEFAULT_ROOT, flat, 100)
	assert_eq(doc.size_cells, Vector2i(40, 20))
	assert_eq(doc.extent_m(), Vector2(40, 20) * LevelData.DEFAULT_GRID_CELL_SIZE)
	var spec := {"size_ft": 300, "depth_ft": 120, "biome_id": NewMap.BARE_BIOME, "seed": 4}
	assert_eq(NewMap.from_spec(spec).size_cells, Vector2i(60, 24))
	assert_eq(NewMap.size_cells(150), Vector2i(30, 30), "no depth: square")
	assert_eq(NewMap.size_cells(102, 98), Vector2i(20, 20), "rounded to whole squares")


func test_a_map_side_is_capped_at_the_format_limit() -> void:
	assert_eq(NewMap.MAX_FT, 320)
	assert_eq(NewMap.RECOMMENDED_MAX_FT, 250)
	assert_eq(NewMap.size_error(320, 320), "")
	assert_ne(NewMap.size_error(325), "")
	assert_ne(NewMap.size_error(200, 400), "")
	assert_ne(NewMap.size_error(0, 100), "")
	assert_false(NewMap.is_big(250))
	assert_true(NewMap.is_big(255))
	assert_true(NewMap.is_big(100, 300))
	assert_null(NewMap.create(400, NewMap.BARE_BIOME, 3), "refused, not clamped")
	assert_push_error(1)


func test_a_landform_on_a_long_map_scales_by_its_shorter_side() -> void:
	var long := MapDocument.create_flat(Vector2i(60, 30), "", "", 0)
	var square := MapDocument.create_flat(Vector2i(30, 30), "", "", 0)
	assert_eq(StartingLandform.size_scale(long), StartingLandform.size_scale(square))
	assert_almost_eq(StartingLandform.size_scale(square), 1.0, 0.001, "150 ft is the reference")


func test_bare_ground_uses_the_bare_surface_and_paints_nothing() -> void:
	var doc := NewMap.create(100, NewMap.BARE_BIOME, 1)
	assert_eq(doc.base_surface, NewMap.BARE_SURFACE)
	assert_true(doc.biome_ids.is_empty())
	assert_true(doc.biome_slots.is_empty())


func test_starting_biome_sets_its_ground_and_paints_its_cover() -> void:
	var biome := PaletteLibrary.biome(BIOME)
	if biome.is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var doc := NewMap.create(150, BIOME, 42)
	assert_eq(doc.base_surface, biome["ground_surface"])
	assert_eq(doc.biome_ids, PackedStringArray([BIOME]))
	assert_eq(doc.biome_slots.size(), doc.sample_count())
	assert_eq(doc.biome_density.size(), doc.sample_count())
	var painted := 0
	for i in doc.sample_count():
		assert_eq(doc.biome_slots[i] > 0, doc.biome_density[i] > 0, "slot follows density")
		if doc.biome_density[i] > 0:
			painted += 1
	var share := float(painted) / float(doc.sample_count())
	assert_between(share, 0.5, 0.999, "most of the map is covered, with real clearings")
	assert_eq(MapDocumentIO.serialize(doc)["error"], "")


func test_cover_is_open_in_the_middle_and_denser_at_the_edges() -> void:
	var half := Vector2(30.0, 30.0)
	var centre := NewMap.starting_density(Vector2.ZERO, half, 0.0)
	var edge := NewMap.starting_density(Vector2(29.0, 0.0), half, 0.0)
	assert_almost_eq(centre, NewMap.COVER_CENTRE_DENSITY, 0.001)
	assert_gt(edge, centre * 3.0, "groves toward the edge")
	assert_eq(NewMap.starting_density(Vector2.ZERO, half, -1.0), 0.0, "noise opens clearings")


func test_the_cover_feathers_out_at_the_map_edge() -> void:
	var half := Vector2(30.0, 20.0)
	var width := NewMap.edge_feather_m(half)
	assert_almost_eq(width, 5.0, 0.001, "a quarter of the shorter half")
	var big := NewMap.edge_feather_m(Vector2(48.8, 48.8))
	assert_almost_eq(big, NewMap.EDGE_FEATHER_MAX_M, 0.001, "320 ft: the most")
	var small := NewMap.edge_feather_m(Vector2(10.0, 10.0))
	assert_almost_eq(small, NewMap.EDGE_FEATHER_MIN_M, 0.001, "a small map: the least")
	assert_eq(NewMap.edge_feather(Vector2(30.0, 0.0), half, width, 0.0), 0.0, "none at the edge")
	assert_eq(NewMap.edge_feather(Vector2(0.0, 0.0), half, width, 1.0), 1.0, "all inside")
	var deep := NewMap.edge_feather(Vector2(0.0, 19.0), half, width, 1.0)
	assert_lt(deep, NewMap.edge_feather(Vector2(0.0, 19.0), half, width, -1.0), "ragged depth")
	if PaletteLibrary.biome(BIOME).is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var doc := NewMap.create(100, BIOME, 7)
	var last := doc.samples_x() - 1
	for k in doc.samples_z():
		for x in [0, last]:
			assert_eq(doc.biome_density[doc.sample_index(x, k)], 0, "the edge sample is bare")


func test_same_seed_same_cover_different_seed_different_cover() -> void:
	if PaletteLibrary.biome(BIOME).is_empty():
		pass_test("palette without %s" % BIOME)
		return
	var a := NewMap.create(100, BIOME, 7)
	var b := NewMap.create(100, BIOME, 7)
	var c := NewMap.create(100, BIOME, 8)
	assert_eq(a.biome_density, b.biome_density)
	assert_ne(a.biome_density, c.biome_density)


func test_dressing_document_reaches_the_farthest_geometry() -> void:
	var bounds := AABB(Vector3(-4.0, 0.0, -12.0), Vector3(20.0, 3.0, 14.0))
	var doc := NewMap.create_dressing(bounds, 5)
	assert_true(doc.has_base_map)
	assert_eq(doc.base_surface, "", "the GLB brings its own ground")
	assert_eq(doc.size_cells.x % 2, 0)
	assert_eq(doc.size_cells.y % 2, 0)
	var half := doc.extent_m() * 0.5
	assert_true(half.x >= 16.0, "reaches x = 16 (%s)" % half)
	assert_true(half.y >= 12.0, "reaches z = -12 (%s)" % half)
	assert_eq(MapDocumentIO.serialize(doc)["error"], "")


func test_dressing_document_is_capped_to_the_document_limits() -> void:
	var doc := NewMap.create_dressing(AABB(Vector3(-500, 0, -500), Vector3(1000, 1, 1000)), 5)
	assert_eq(doc.size_cells, Vector2i(MapDocument.MAX_SIZE_CELLS, MapDocument.MAX_SIZE_CELLS))
