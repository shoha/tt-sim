extends GutTest

## Unit tests for ScatterChunker -- the cell arithmetic behind splitting a scatter species
## into a grid of per-cell MultiMeshes so frustum culling can discard off-screen foliage
## (see docs/PERFORMANCE.md). Every function under test is a pure static, which is the whole
## reason the arithmetic lives in its own class: headless runs cannot verify rendering, but
## they can verify all of this.


func _at(x: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, 0.0, z))


func test_cell_for_a_positive_position() -> void:
	assert_eq(ScatterChunker.cell_for(Vector3(5.0, 0.0, 25.0), 10.0), Vector2i(0, 2))


func test_cell_for_a_negative_position_uses_floor_not_truncation() -> void:
	# int() truncates toward zero -- int(-0.5) is 0 -- which would collapse everything
	# between -chunk_size and +chunk_size into cell 0 on each axis, making the origin cell
	# four times the size of every other and leaving a quarter of the map uncullable. Half
	# this map has negative coordinates, so this is the common case, not an edge case.
	assert_eq(ScatterChunker.cell_for(Vector3(-0.5, 0.0, -0.5), 10.0), Vector2i(-1, -1))
	assert_eq(ScatterChunker.cell_for(Vector3(-15.0, 0.0, -25.0), 10.0), Vector2i(-2, -3))


func test_a_position_on_a_cell_boundary_goes_to_the_higher_cell() -> void:
	# Pinned so a future switch to rounding or truncation fails loudly instead of silently
	# reshuffling which chunk every boundary instance belongs to.
	assert_eq(ScatterChunker.cell_for(Vector3(10.0, 0.0, 0.0), 10.0), Vector2i(1, 0))
	assert_eq(ScatterChunker.cell_for(Vector3(0.0, 0.0, 0.0), 10.0), Vector2i(0, 0))
	assert_eq(ScatterChunker.cell_for(Vector3(-10.0, 0.0, 0.0), 10.0), Vector2i(-1, 0))


func test_cell_for_ignores_y() -> void:
	# Asserting low == high alone would pass a broken guard that returns Vector2i.ZERO for
	# both, so pin the actual expected cell too.
	var low := ScatterChunker.cell_for(Vector3(5.0, -100.0, 5.0), 10.0)
	var high := ScatterChunker.cell_for(Vector3(5.0, 100.0, 5.0), 10.0)
	assert_eq(low, Vector2i(0, 0))
	assert_eq(high, Vector2i(0, 0))


func test_cell_suffix_formats_positive_and_negative_cells() -> void:
	assert_eq(ScatterChunker.cell_suffix(Vector2i(0, 0)), "_c0_0")
	assert_eq(ScatterChunker.cell_suffix(Vector2i(-1, 2)), "_c-1_2")


func test_bucket_by_cell_returns_only_occupied_cells() -> void:
	# Two transforms 30 units apart at chunk_size 10 occupy two cells, not the four the
	# bounding box spans.
	var buckets := ScatterChunker.bucket_by_cell([_at(0.0, 0.0), _at(30.0, 0.0)], 10.0)
	assert_eq(buckets.size(), 2)
	assert_true(buckets.has(Vector2i(0, 0)))
	assert_true(buckets.has(Vector2i(3, 0)))


func test_bucket_by_cell_loses_and_duplicates_nothing() -> void:
	var transforms: Array[Transform3D] = []
	for i in 50:
		transforms.append(_at(float(i), float(i)))
	var buckets := ScatterChunker.bucket_by_cell(transforms, 10.0)
	var total := 0
	for cell in buckets.keys():
		total += (buckets[cell] as Array).size()
	assert_eq(total, 50)


func test_bucket_by_cell_groups_a_single_cell_species_into_one_bucket() -> void:
	var buckets := ScatterChunker.bucket_by_cell([_at(1.0, 1.0), _at(2.0, 2.0)], 100.0)
	assert_eq(buckets.size(), 1)
	assert_eq((buckets[Vector2i(0, 0)] as Array).size(), 2)


func test_bucket_by_cell_handles_empty_input() -> void:
	var empty: Array[Transform3D] = []
	assert_eq(ScatterChunker.bucket_by_cell(empty, 10.0).size(), 0)


func test_bucket_by_cell_is_deterministic() -> void:
	# A map must chunk identically on every load and every machine, or a host and its
	# clients would disagree about what exists. Pins the exact cell set and per-cell
	# counts for a fixed input, rather than only comparing two calls against each other --
	# there is no state, RNG or iteration-order dependence in bucket_by_cell, so no
	# implementation could pass the first call and fail the second, which made the
	# two-calls version of this test unable to fail against a broken implementation.
	var transforms: Array[Transform3D] = [
		_at(1.0, 1.0),
		_at(2.0, 2.0),
		_at(3.0, 3.0),  # cell (0, 0)
		_at(15.0, 1.0),
		_at(16.0, 2.0),  # cell (1, 0)
		_at(1.0, 25.0),  # cell (0, 2)
		_at(-5.0, -5.0),
		_at(-1.0, -1.0),  # cell (-1, -1)
	]
	var buckets := ScatterChunker.bucket_by_cell(transforms, 10.0)
	assert_eq(buckets.keys().size(), 4)
	assert_eq((buckets[Vector2i(0, 0)] as Array).size(), 3)
	assert_eq((buckets[Vector2i(1, 0)] as Array).size(), 2)
	assert_eq((buckets[Vector2i(0, 2)] as Array).size(), 1)
	assert_eq((buckets[Vector2i(-1, -1)] as Array).size(), 2)


func test_bucket_by_cell_degrades_safely_on_a_nonpositive_chunk_size() -> void:
	# A zero or negative chunk size would divide by zero. Falling back to one bucket
	# reproduces the pre-chunking behaviour, which is safe rather than corrupt.
	var buckets := ScatterChunker.bucket_by_cell([_at(0.0, 0.0), _at(30.0, 0.0)], 0.0)
	assert_eq(buckets.size(), 1)
	assert_eq((buckets[Vector2i(0, 0)] as Array).size(), 2)
