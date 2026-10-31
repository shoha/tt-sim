extends GutTest

## The weathervane (topic wind_c): StructureVane cuts the arrow, shaft and tail out of a build, the
## digest still covers the whole vane, VaneMotion points the arrow into the wind as a damped spring
## (StructureWind.vane_step). Summary: docs/systems/structures.md "Weathervane".

const COTTAGE := "core:cottage"


func _parts() -> Dictionary:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	return StructureGeometry.build_one(
		doc, Structure.make(1, COTTAGE, plan, 7, StructureOrnaments.with_kinds({}, ["vane"]))
	)


func _triangles(meshes: Array) -> int:
	var total := 0
	for mesh: Dictionary in meshes:
		total += (mesh.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func test_the_split_keeps_every_triangle_and_the_digest() -> void:
	var parts := _parts()
	var digest := StructureGeometry.digest_of(parts)
	var vane := StructureVane.split(parts.meshes, parts.tag_table)
	assert_false(vane.is_empty(), "the cottage got a weathervane")
	assert_gt(_triangles(vane.turning), 0)
	assert_eq(_triangles(vane.rest) + _triangles(vane.turning), _triangles(parts.meshes))
	assert_eq(StructureGeometry.digest_of(parts), digest, "the build is not changed")
	var tip: Vector3 = vane.tip
	assert_almost_eq(tip.length(), 1.0, 0.001)
	assert_eq(tip.y, 0.0)
	# Nothing of the arrow is left behind, and only shaft, arrow and tail turn.
	for mesh: Dictionary in vane.rest:
		for tag in mesh.tags:
			var path: String = parts.tag_table[tag]
			assert_false(path.ends_with("vane/arrow") or path.ends_with("vane/shaft"), path)
			assert_false(path.ends_with("vane/tail"), path)
	for mesh: Dictionary in vane.turning:
		for tag in mesh.tags:
			var path: String = parts.tag_table[tag]
			assert_true(
				path.ends_with("vane/arrow") or path.ends_with("vane/shaft") or path.ends_with("vane/tail"),
				path
			)


func test_a_building_without_a_vane_is_left_alone() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var parts := StructureGeometry.build_one(doc, Structure.make(1, COTTAGE, plan, 7, {}))
	assert_true(StructureVane.split(parts.meshes, parts.tag_table).is_empty())


func test_the_structure_node_holds_a_vane_pivot_that_points_into_the_wind() -> void:
	var parts := _parts()
	var nodes := AuthoredStructures.new()
	add_child_autofree(nodes)
	var node := nodes._structure_node(1, parts)
	add_child_autofree(node)
	var pivot := node.get_node_or_null("Vane") as VaneMotion
	assert_not_null(pivot, "a Vane node")
	assert_gt(pivot.get_child_count(), 1, "meshes and a notifier")
	var wind := Vector3(5.0, 0.0, -5.0)
	for i in 600:
		pivot.step_wind(0.05, wind, 0.4, 1.0)
	var tip: Vector3 = pivot.basis * pivot.built_tip
	assert_gt(tip.dot(-wind.normalized()), 0.99, "the arrow points where the wind comes from")
	pivot.step_wind(0.05, wind, 0.4, 0.0)
	assert_eq(pivot.yaw(), 0.0, "motion 0 holds the built pose")


func test_the_spring_settles_overshoots_and_takes_the_short_way() -> void:
	var state := Vector2.ZERO
	var peak := 0.0
	for i in 1200:
		state = StructureWind.vane_step(state, 1.0, 0.016)
		peak = maxf(peak, state.x)
	assert_almost_eq(state.x, 1.0, 0.001, "settles on the target")
	assert_gt(peak, 1.0, "under-damped: it overshoots")
	assert_lt(peak, 1.5, "but only a little")
	# From 170 degrees toward -170 degrees it goes on through 180, not back through 0.
	var s := Vector2(deg_to_rad(170.0), 0.0)
	s = StructureWind.vane_step(s, deg_to_rad(-170.0), 0.1)
	assert_gt(absf(s.x), deg_to_rad(170.0), "short way")
	# A slow frame stays stable.
	var big := StructureWind.vane_step(Vector2.ZERO, 3.0, 5.0)
	assert_true(absf(big.x) <= PI and absf(big.y) < 50.0)


func test_the_gust_wobble_is_zero_at_an_average_gust_and_grows_with_the_wind() -> void:
	assert_almost_eq(StructureWind.vane_wobble(0.4, 14.0), 0.0, 0.0001)
	assert_gt(StructureWind.vane_wobble(1.0, 14.0), 0.1)
	assert_lt(StructureWind.vane_wobble(1.0, 14.0), 0.3)
	assert_gt(StructureWind.vane_wobble(1.0, 14.0), StructureWind.vane_wobble(1.0, 4.0))
	assert_lt(StructureWind.vane_wobble(0.0, 14.0), 0.0)
	assert_almost_eq(StructureWind.vane_wobble(1.0, 140.0), StructureWind.vane_wobble(1.0, 14.0), 0.0001)
