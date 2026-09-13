extends GutTest

## Unit tests for FoliageBudget -- the fixed global cap on scattered-foliage primitives
## in user-imported maps (see docs/PERFORMANCE.md). Every function under test is a pure
## static with no node access, which is the whole reason the allocator lives in its own
## class: headless runs cannot verify real rendering, but they can verify all of this.


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
	# A line surface contributes no triangles. Counting its indices as triangles would
	# inflate the species' cost and thin the map more than it needs to be.
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	assert_eq(FoliageBudget.primitives_per_instance(mesh), 0)
