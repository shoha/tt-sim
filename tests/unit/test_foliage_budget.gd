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


func test_keeps_every_index_when_keep_meets_or_exceeds_count() -> void:
	assert_eq(Array(FoliageBudget.select_indices(5, 9, "x")), [0, 1, 2, 3, 4])
	assert_eq(Array(FoliageBudget.select_indices(5, 5, "x")), [0, 1, 2, 3, 4])


func test_keeps_nothing_when_keep_is_zero_or_negative() -> void:
	assert_eq(FoliageBudget.select_indices(5, 0, "x").size(), 0)
	assert_eq(FoliageBudget.select_indices(5, -3, "x").size(), 0)


func test_keeps_nothing_when_count_is_zero() -> void:
	assert_eq(FoliageBudget.select_indices(0, 4, "x").size(), 0)


func test_returns_exactly_keep_indices() -> void:
	assert_eq(FoliageBudget.select_indices(1000, 250, "GrassBlade").size(), 250)


func test_indices_are_distinct_and_in_range() -> void:
	var picked := FoliageBudget.select_indices(200, 50, "GrassBlade")
	var seen := {}
	for index in picked:
		assert_true(index >= 0 and index < 200, "index %d out of range" % index)
		assert_false(seen.has(index), "index %d appeared twice" % index)
		seen[index] = true


func test_is_deterministic_for_the_same_seed_source() -> void:
	# Load-bearing: a map must thin identically on every load and on every machine, or
	# its appearance would change between sessions and between a host and its clients.
	var first := FoliageBudget.select_indices(500, 120, "GrassBlade")
	var second := FoliageBudget.select_indices(500, 120, "GrassBlade")
	assert_eq(Array(first), Array(second))


func test_varies_with_the_seed_source() -> void:
	# Different species must not thin to the same index pattern in lockstep.
	var grass := FoliageBudget.select_indices(500, 120, "GrassBlade")
	var pine := FoliageBudget.select_indices(500, 120, "PineTree")
	assert_ne(Array(grass), Array(pine))


func test_spreads_across_the_whole_range() -> void:
	# Scatter transforms arrive in brush-stroke or row order, so dropping a suffix would
	# leave a bald patch. Every quarter of the range must still be represented.
	var picked := FoliageBudget.select_indices(100, 20, "GrassBlade")
	var quartiles := [0, 0, 0, 0]
	for index in picked:
		quartiles[index / 25] += 1
	for quartile in quartiles:
		assert_gt(quartile, 0, "a quarter of the range was dropped entirely: %s" % [quartiles])


func test_pins_the_current_selection_algorithm() -> void:
	# Golden values, intentionally brittle. Changing the seeding or the shuffle silently
	# changes which instances survive in every existing map, so that must never happen as
	# an accident of refactoring -- if this test fails, the change was deliberate or it
	# is a bug, and either way someone has to look.
	assert_eq(Array(FoliageBudget.select_indices(10, 4, "GrassBlade")), [0, 1, 3, 5])
	assert_eq(Array(FoliageBudget.select_indices(10, 4, "PineTree")), [0, 4, 5, 6])


func test_stable_hash_is_fnv1a_and_not_the_engines_hash() -> void:
	# FNV-1a's defining property: the empty string hashes to the offset basis. Asserted
	# so the seeding cannot be quietly swapped for Godot's own hash(), which is an engine
	# implementation detail and would tie every map's appearance to an engine version.
	assert_eq(FoliageBudget._stable_hash(""), 2166136261)
	assert_eq(FoliageBudget._stable_hash("GrassBlade"), 445990121)


func _species(count: int, per_instance: int) -> Dictionary:
	return {"count": count, "primitives_per_instance": per_instance}


func test_a_map_under_budget_is_left_alone() -> void:
	var report := FoliageBudget.plan({"Grass": _species(1000, 10)}, 100000)
	assert_false(report.thinned)
	assert_eq(report.kept["Grass"], 1000)
	assert_eq(report.total_before, 10000)
	assert_eq(report.total_after, 10000)


func test_a_map_exactly_on_budget_is_left_alone() -> void:
	var report := FoliageBudget.plan({"Grass": _species(100, 10)}, 1000)
	assert_false(report.thinned)
	assert_eq(report.kept["Grass"], 100)


func test_a_map_over_budget_is_thinned_to_within_budget() -> void:
	var report := FoliageBudget.plan({"Grass": _species(1000, 10)}, 4000)
	assert_true(report.thinned)
	assert_lte(report.total_after, 4000)
	assert_eq(report.kept["Grass"], 400)


func test_allocation_is_proportional_across_equal_species() -> void:
	# Same primitive load each, so each keeps the same fraction -- the map's composition
	# is preserved rather than one species being sacrificed to save another.
	var report := FoliageBudget.plan(
		{"Grass": _species(1000, 10), "Fern": _species(1000, 10)}, 10000
	)
	assert_true(report.thinned)
	assert_eq(report.kept["Grass"], 500)
	assert_eq(report.kept["Fern"], 500)


func test_allocation_scales_a_heavier_species_by_the_same_fraction() -> void:
	# Trees cost 10x per instance here. Both keep half their instances; the tree species
	# still surrenders 10x as many primitives, which is the point.
	var report := FoliageBudget.plan(
		{"Grass": _species(1000, 10), "Tree": _species(1000, 100)}, 55000
	)
	assert_true(report.thinned)
	assert_eq(report.kept["Grass"], 500)
	assert_eq(report.kept["Tree"], 500)


func test_a_species_with_no_countable_primitives_is_never_thinned() -> void:
	# primitives_per_instance of 0 means the mesh's cost could not be determined. Thinning
	# it would be silent content loss for no measurable saving.
	var report := FoliageBudget.plan(
		{"Grass": _species(1000, 10), "Unknown": _species(50, 0)}, 4000
	)
	assert_true(report.thinned)
	assert_eq(report.kept["Unknown"], 50)
	assert_eq(report.kept["Grass"], 400)


func test_an_empty_species_set_is_not_thinned() -> void:
	var report := FoliageBudget.plan({}, 4000)
	assert_false(report.thinned)
	assert_eq(report.total_before, 0)
	assert_eq(report.instances_before, 0)


func test_reports_instance_counts_before_and_after() -> void:
	var report := FoliageBudget.plan({"Grass": _species(1000, 10), "Fern": _species(500, 10)}, 7500)
	assert_eq(report.instances_before, 1500)
	assert_eq(report.instances_after, 750)


func test_defaults_to_the_shipped_budget() -> void:
	# Called without an explicit budget, a map far under PRIMITIVE_BUDGET is untouched.
	var report := FoliageBudget.plan({"Grass": _species(10, 10)})
	assert_false(report.thinned)


func test_describe_names_the_before_and_after_counts_and_the_reason() -> void:
	var report := FoliageBudget.plan({"Grass": _species(1000, 10)}, 4000)
	var message := FoliageBudget.describe(report)
	assert_string_contains(message, "400")
	assert_string_contains(message, "1,000")
	assert_string_contains(message, "performance")
