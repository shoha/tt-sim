extends GutTest

## MapDocument (resources/map_document.gd): grid geometry, coordinate conversion and the
## row helpers. File I/O and validation are in test_map_document_io.gd.

const CELL := LevelData.DEFAULT_GRID_CELL_SIZE


func test_create_flat_100_ft() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "abc1234", 7)
	assert_almost_eq(doc.extent_m(), Vector2(30.48, 30.48), Vector2(1e-4, 1e-4))
	# round(30.48 / 0.25) + 1 = round(121.92) + 1
	assert_eq(doc.samples_x(), 123)
	assert_eq(doc.samples_z(), 123)
	assert_eq(doc.heights.size(), 123 * 123)
	assert_eq(doc.base_surface, "grass_alpine")
	assert_eq(doc.palette_version, "abc1234")
	assert_eq(doc.map_seed, 7)
	assert_false(doc.has_base_map)
	assert_almost_eq(doc.tier_height_m, CELL, 1e-6, "one tier defaults to one cell (5 ft)")


func test_create_flat_150_ft() -> void:
	var doc := MapDocument.create_flat(Vector2i(30, 30), "", "", 0)
	assert_almost_eq(doc.extent_m().x, 45.72, 1e-4)
	assert_eq(doc.samples_x(), 184)
	assert_eq(doc.heights.size(), 184 * 184)


func test_create_flat_200_ft_matches_the_spec_probe() -> void:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "", "", 0)
	assert_almost_eq(doc.extent_m().x, 60.96, 1e-4)
	assert_eq(doc.samples_x(), 245, "the design's 245 x 245 at 0.25 m")
	assert_eq(doc.heights.size(), 245 * 245)


func test_create_flat_is_all_zero() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	for h in doc.heights:
		if h != 0.0:
			fail_test("non-zero height %f" % h)
			return
	pass_test("flat")
	assert_true(doc.scatter.is_empty())
	assert_true(doc.props.is_empty())
	assert_true(doc.erase_mask.is_empty())
	assert_true(doc.biome_slots.is_empty())


func test_create_flat_clamps_size() -> void:
	var doc := MapDocument.create_flat(Vector2i(0, 500), "", "", 0)
	assert_eq(doc.size_cells, Vector2i(MapDocument.MIN_SIZE_CELLS, MapDocument.MAX_SIZE_CELLS))


func test_rectangular_map_has_separate_axes() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 30), "", "", 0)
	assert_eq(doc.samples_x(), 123)
	assert_eq(doc.samples_z(), 184)
	assert_eq(doc.heights.size(), 123 * 184)
	assert_eq(doc.sample_index(2, 1), 123 + 2, "row-major: Z rows of X columns")


func test_samples_for_never_below_two() -> void:
	assert_eq(MapDocument.samples_for(0.1, 1.0), 2)
	assert_eq(MapDocument.samples_for(10.0, 0.0), 2)
	assert_eq(MapDocument.samples_for(10.0, 1.0), 11)


func test_world_to_sample_corners_and_centre() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 30), "", "", 0)
	var half := doc.extent_m() * 0.5
	var eps := Vector2(1e-3, 1e-3)
	assert_almost_eq(doc.world_to_sample(-half), Vector2.ZERO, eps)
	assert_almost_eq(doc.world_to_sample(half), Vector2(122, 183), eps)
	assert_almost_eq(doc.world_to_sample(Vector2(half.x, -half.y)), Vector2(122, 0), eps)
	assert_almost_eq(doc.world_to_sample(Vector2.ZERO), Vector2(61, 91.5), eps)


func test_sample_to_world_inverts() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 30), "", "", 0)
	var half := doc.extent_m() * 0.5
	var eps := Vector2(1e-4, 1e-4)
	assert_almost_eq(doc.sample_to_world(Vector2.ZERO), -half, eps)
	assert_almost_eq(doc.sample_to_world(Vector2(122, 183)), half, eps)
	assert_almost_eq(doc.sample_to_world(Vector2(61, 91.5)), Vector2.ZERO, eps)
	var point := Vector2(3.21, -7.5)
	assert_almost_eq(doc.sample_to_world(doc.world_to_sample(point)), point, eps)


func test_sample_step_spans_the_extent_exactly() -> void:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "", "", 0)
	var step := doc.sample_step()
	assert_almost_eq(step.x * (doc.samples_x() - 1), doc.extent_m().x, 1e-4)
	assert_almost_eq(step.x, 0.25, 0.001, "close to the nominal spacing")


func test_scatter_groups_builds_array_rows() -> void:
	var flat := PackedFloat32Array([1, 2, 3, 0, 0, 0, 1, 1, 1, 1, 4, 5, 6, 0, 0, 0, 1, 2, 2, 2])
	var rows: Dictionary[String, PackedFloat32Array] = {"pkg/Tree": flat}
	var groups := MapDocument.scatter_groups(rows)
	assert_eq(groups["pkg/Tree"].size(), 2)
	assert_eq(groups["pkg/Tree"][1], [4.0, 5.0, 6.0, 0.0, 0.0, 0.0, 1.0, 2.0, 2.0, 2.0])
	var xform: Variant = ScatterGlbUtils._row_to_transform(groups["pkg/Tree"][1])
	assert_true(xform is Transform3D, "the converted rows are what build_scatter reads")
	assert_eq(MapDocument.row_count(rows), 2)
