extends GutTest

## Unit tests for FoliageBudget -- the triangle count of a mesh and the deterministic shuffled
## order a chunk's instances are written in (the order zoom-keyed ground thinning draws a prefix
## of; see FoliageDensityController and docs/PERFORMANCE.md). Both are pure statics with no node
## access: headless runs cannot verify real rendering, but they can verify all of this.


func _indexed_array_mesh() -> ArrayMesh:
	# An indexed triangle surface, the shape a glTF import actually produces.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	return mesh


func _non_indexed_array_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func test_counts_triangles_of_an_indexed_array_mesh() -> void:
	# A box is 6 quads = 12 triangles = 36 indices.
	assert_eq(FoliageBudget.primitives_per_instance(_indexed_array_mesh()), 12)


func test_counts_triangles_of_a_non_indexed_array_mesh() -> void:
	# No index buffer, so the count comes from the vertex count instead.
	assert_eq(FoliageBudget.primitives_per_instance(_non_indexed_array_mesh()), 1)


func test_counts_triangles_of_a_primitive_mesh() -> void:
	# PrimitiveMesh has no surface_get_array_index_len() at all -- it is an ArrayMesh
	# method. This asserts the get_faces() fallback, which is the path the scatter
	# tests' BoxMesh fixtures take.
	assert_eq(FoliageBudget.primitives_per_instance(BoxMesh.new()), 12)
	assert_eq(FoliageBudget.primitives_per_instance(QuadMesh.new()), 2)


func test_returns_zero_for_a_null_mesh() -> void:
	assert_eq(FoliageBudget.primitives_per_instance(null), 0)


func test_returns_zero_for_a_surfaceless_array_mesh() -> void:
	assert_eq(FoliageBudget.primitives_per_instance(ArrayMesh.new()), 0)


func test_ignores_non_triangle_surfaces() -> void:
	# A line surface contributes no triangles.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	assert_eq(FoliageBudget.primitives_per_instance(mesh), 0)


func test_sums_multiple_triangle_surfaces() -> void:
	# Two indexed triangle surfaces on one mesh, each a box's 12 triangles (36 indices) --
	# the trunk/leaves shape a real multi-material tree GLB takes. A count() that only
	# looked at surface 0 would pass all six single-surface tests above and still miss
	# half of this mesh's real cost.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	assert_eq(FoliageBudget.primitives_per_instance(mesh), 24)


func test_counts_a_triangle_surface_and_skips_a_line_surface_in_the_same_mesh() -> void:
	# Guards the continue-plus-accumulate interaction specifically: distinct from
	# test_ignores_non_triangle_surfaces (a line-only mesh), where an implementation that
	# abandoned the whole mesh on hitting a non-triangle surface would also pass. Here the
	# triangle surface's 12 must survive the line surface being skipped.
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	var line_arrays: Array = []
	line_arrays.resize(Mesh.ARRAY_MAX)
	line_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	assert_eq(FoliageBudget.primitives_per_instance(mesh), 12)


func test_shuffled_order_is_a_full_permutation() -> void:
	# Nothing may be lost or duplicated: this order IS the instance order in the
	# MultiMesh, so a missing index is a missing plant and a repeat is a double-drawn one.
	var order := FoliageBudget.shuffled_order(200, "GrassBlade")
	assert_eq(order.size(), 200)
	var seen := {}
	for index in order:
		assert_true(index >= 0 and index < 200, "index %d out of range" % index)
		assert_false(seen.has(index), "index %d appeared twice" % index)
		seen[index] = true


func test_shuffled_order_is_deterministic_for_the_same_seed_source() -> void:
	# A map must look the same across loads on one machine, and instances must appear and
	# disappear predictably as the thinning moves rather than reshuffling.
	var first := FoliageBudget.shuffled_order(500, "GrassBlade")
	var second := FoliageBudget.shuffled_order(500, "GrassBlade")
	assert_eq(Array(first), Array(second))


func test_shuffled_order_varies_with_the_seed_source() -> void:
	var grass := FoliageBudget.shuffled_order(500, "GrassBlade")
	var pine := FoliageBudget.shuffled_order(500, "PineTree")
	assert_ne(Array(grass), Array(pine))


func test_shuffled_order_prefixes_spread_across_the_whole_range() -> void:
	# This is the property visible_instance_count depends on: drawing the first N of the
	# order must sample the whole cell evenly, not carve a bald patch out of one side.
	var order := FoliageBudget.shuffled_order(100, "GrassBlade")
	var quartiles := [0, 0, 0, 0]
	for i in 20:
		quartiles[order[i] / 25] += 1
	for quartile in quartiles:
		assert_gt(quartile, 0, "a quarter of the range is absent from the prefix: %s" % [quartiles])


func test_shuffled_order_is_empty_for_a_nonpositive_count() -> void:
	assert_eq(FoliageBudget.shuffled_order(0, "x").size(), 0)
	assert_eq(FoliageBudget.shuffled_order(-5, "x").size(), 0)


func test_shuffled_order_pins_the_current_algorithm() -> void:
	# Golden values, intentionally brittle. This order decides which instances a user sees
	# under any thinning, so it must not drift as an accident of refactoring -- and
	# an engine RNG change on a Godot upgrade has the same effect as a deliberate edit.
	var order := FoliageBudget.shuffled_order(8, "GrassBlade")
	assert_eq(Array(order), [5, 6, 7, 3, 1, 4, 2, 0])


func test_stable_hash_is_fnv1a_and_not_the_engines_hash() -> void:
	# FNV-1a's defining property: the empty string hashes to the offset basis. Asserted so
	# the seeding cannot be quietly swapped for Godot's hash(), which is an engine detail
	# that would tie every map's appearance to an engine version.
	assert_eq(FoliageBudget._stable_hash(""), 2166136261)
	assert_eq(FoliageBudget._stable_hash("GrassBlade"), 445990121)
