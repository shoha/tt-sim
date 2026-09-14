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
	# disappear predictably as the density slider moves rather than reshuffling.
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
	# at any density below 100%, so it must not drift as an accident of refactoring -- and
	# an engine RNG change on a Godot upgrade has the same effect as a deliberate edit.
	var order := FoliageBudget.shuffled_order(8, "GrassBlade")
	assert_eq(Array(order), [5, 6, 7, 3, 1, 4, 2, 0])


func test_stable_hash_is_fnv1a_and_not_the_engines_hash() -> void:
	# FNV-1a's defining property: the empty string hashes to the offset basis. Asserted so
	# the seeding cannot be quietly swapped for Godot's hash(), which is an engine detail
	# that would tie every map's appearance to an engine version.
	assert_eq(FoliageBudget._stable_hash(""), 2166136261)
	assert_eq(FoliageBudget._stable_hash("GrassBlade"), 445990121)


func test_visible_counts_distribute_proportionally() -> void:
	var counts := FoliageBudget.visible_counts_for_chunks(
		{Vector2i(0, 0): 100, Vector2i(1, 0): 100}, 100, 200
	)
	assert_eq(counts[Vector2i(0, 0)], 50)
	assert_eq(counts[Vector2i(1, 0)], 50)


func test_visible_counts_respect_uneven_chunks() -> void:
	var counts := FoliageBudget.visible_counts_for_chunks(
		{Vector2i(0, 0): 80, Vector2i(1, 0): 20}, 50, 100
	)
	assert_eq(counts[Vector2i(0, 0)], 40)
	assert_eq(counts[Vector2i(1, 0)], 10)


func test_visible_counts_show_everything_when_kept_equals_total() -> void:
	var counts := FoliageBudget.visible_counts_for_chunks(
		{Vector2i(0, 0): 30, Vector2i(1, 0): 70}, 100, 100
	)
	assert_eq(counts[Vector2i(0, 0)], 30)
	assert_eq(counts[Vector2i(1, 0)], 70)


func test_visible_counts_never_exceed_a_chunks_instance_count() -> void:
	# Writing a visible_instance_count above instance_count is invalid in Godot.
	var counts := FoliageBudget.visible_counts_for_chunks(
		{Vector2i(0, 0): 10, Vector2i(1, 0): 10}, 500, 20
	)
	assert_eq(counts[Vector2i(0, 0)], 10)
	assert_eq(counts[Vector2i(1, 0)], 10)


func test_visible_counts_are_zero_for_a_zero_allocation() -> void:
	var counts := FoliageBudget.visible_counts_for_chunks({Vector2i(0, 0): 40}, 0, 40)
	assert_eq(counts[Vector2i(0, 0)], 0)


func test_visible_counts_handle_empty_and_degenerate_input() -> void:
	assert_eq(FoliageBudget.visible_counts_for_chunks({}, 10, 10).size(), 0)
	var counts := FoliageBudget.visible_counts_for_chunks({Vector2i(0, 0): 10}, 5, 0)
	assert_eq(counts[Vector2i(0, 0)], 0)


func test_visible_counts_never_lose_a_species_to_rounding() -> void:
	# Independent per-chunk rounding returns 0 for all three here (round(1/3) = 0), losing
	# the species entirely. Largest-remainder apportionment must hand the whole allocation
	# to one chunk instead.
	var counts := FoliageBudget.visible_counts_for_chunks(
		{Vector2i(0, 0): 1, Vector2i(1, 0): 1, Vector2i(2, 0): 1}, 1, 3
	)
	var total := 0
	for key in counts.keys():
		total += counts[key]
	assert_eq(total, 1)


func test_visible_counts_never_exceed_the_allocation_through_rounding() -> void:
	# Independent rounding gives round(0.5) = 1 on every chunk here, doubling the
	# allocation and blowing the budget the user set.
	var chunk_counts := {}
	for i in 100:
		chunk_counts[Vector2i(i, 0)] = 1
	var counts := FoliageBudget.visible_counts_for_chunks(chunk_counts, 50, 100)
	var total := 0
	for key in counts.keys():
		total += counts[key]
	assert_eq(total, 50)


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


func test_describe_names_the_density_percentage_and_the_reason() -> void:
	# 400 kept of 1,000 before is 40%. Present tense and names the setting (not the map) as
	# the cause, since this is a live dial the player can raise back up, not a one-time loss.
	var report := FoliageBudget.plan({"Grass": _species(1000, 10)}, 4000)
	var message := FoliageBudget.describe(report)
	assert_string_contains(message, "40%")
	assert_string_contains(message, "Foliage Density")


func test_describe_formats_the_percentage_as_a_whole_number() -> void:
	# 250 of 749 is 33.377...%, which must read as a clean "33%" -- not "33.4%" and not
	# "33.0%" -- since the wording is meant to be skimmed in a toast, not read precisely.
	var report := {"instances_before": 749, "instances_after": 250}
	var message := FoliageBudget.describe(report)
	assert_string_contains(message, "33%")
	# Isolate the number itself rather than the whole sentence, which legitimately ends in
	# its own, unrelated period.
	var percent_text := message.split("%")[0]
	assert_false(percent_text.contains("."), "percentage must not include a decimal point")


func test_a_species_is_never_allocated_zero_instances() -> void:
	# A zero allocation would leave ScatterGlbUtils' template node unfreed and rendering at
	# a stray transform, so a species with instances always keeps at least one even when its
	# proportional share rounds to nothing.
	var report := FoliageBudget.plan(
		{"Grass": _species(1000, 10), "HeroTree": _species(1, 100)}, 3000
	)
	assert_true(report.thinned)
	assert_eq(report.kept["HeroTree"], 1)
	assert_gt(report.kept["Grass"], 0)


func test_an_empty_species_is_never_allocated_a_phantom_instance() -> void:
	# The floor-to-1 must not invent an instance for a species that has none, or the report
	# would count a phantom and a caller could index an empty transform array.
	var report := FoliageBudget.plan({"Grass": _species(1000, 10), "Empty": _species(0, 50)}, 3000)
	assert_true(report.thinned)
	assert_eq(report.kept["Empty"], 0)
