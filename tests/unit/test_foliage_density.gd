extends GutTest

## Unit tests for FoliageDensityController -- zoom-keyed thinning of ground cover: the ramp from
## camera size to the share drawn, the visible count of a chunk, and the pass that writes
## MultiMesh.visible_instance_count. See docs/PERFORMANCE.md "Zoom-keyed ground thinning".


func after_each() -> void:
	FoliageDensityController.fraction = 1.0


func _chunk(
	parent: Node3D, node_name: String, instances: int, category: String, ground: bool
) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	if ground:
		var material := ShaderMaterial.new()
		material.set_meta(WindFoliage.META_GROUND, true)
		mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = instances
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.set_meta("wind_foliage_category", category)
	parent.add_child(node)
	return node


func _visible_total_recursive(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.visible_instance_count
		total += _visible_total_recursive(child)
	return total


func test_every_instance_is_drawn_up_to_the_full_size() -> void:
	assert_eq(FoliageDensityController.keep_fraction(2.0), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(4.0), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(10.0), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(13.85), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(14.0), 1.0)


func test_two_thirds_are_drawn_from_zoom_20_out() -> void:
	# 2/3 quantised to 1/32 is 21/32.
	assert_eq(FoliageDensityController.keep_fraction(20.0), 21.0 / 32.0)
	assert_eq(FoliageDensityController.keep_fraction(30.0), 21.0 / 32.0)
	assert_eq(FoliageDensityController.keep_fraction(400.0), 21.0 / 32.0)
	assert_almost_eq(FoliageDensityController.keep_fraction(20.0), 2.0 / 3.0, 1.0 / 32.0)


func test_the_ramp_between_is_monotone_and_stepped() -> void:
	var last := 1.0
	var distinct := {}
	var size := 14.0
	while size <= 20.0:
		var keep := FoliageDensityController.keep_fraction(size)
		assert_lte(keep, last, "size %.2f" % size)
		assert_almost_eq(
			keep * FoliageDensityController.STEPS, roundf(keep * FoliageDensityController.STEPS), 1e-4
		)
		distinct[keep] = true
		last = keep
		size += 0.05
	assert_gt(distinct.size(), 8, "the ramp is a run of small steps, not one jump")


func test_a_map_whose_home_is_further_out_keeps_all_of_it_at_home() -> void:
	# Home 25: the ramp starts there, and spans 25 * (20 / 14 - 1) = 10.7 m of camera size.
	assert_eq(FoliageDensityController.keep_fraction(25.0, 25.0), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(25.0 * 20.0 / 14.0, 25.0), 21.0 / 32.0)
	assert_lt(FoliageDensityController.keep_fraction(30.0, 25.0), 1.0)


func test_a_home_closer_in_than_the_full_size_does_not_pull_the_ramp_in() -> void:
	# A tiny map's home at 8 still draws everything up to 14: zoomed in, a card is large on screen.
	assert_eq(FoliageDensityController.keep_fraction(12.0, 8.0), 1.0)
	assert_eq(FoliageDensityController.keep_fraction(20.0, 8.0), 21.0 / 32.0)


func test_a_chunk_is_never_emptied() -> void:
	assert_eq(FoliageDensityController.thinned_count(1, 0.5), 1)
	assert_eq(FoliageDensityController.thinned_count(3, 0.5), 2)
	assert_eq(FoliageDensityController.thinned_count(100, 0.5), 50)
	assert_eq(FoliageDensityController.thinned_count(100, 1.0), 100)
	assert_eq(FoliageDensityController.thinned_count(0, 0.5), 0)


func test_thinning_keeps_a_prefix_so_a_thinner_draw_is_inside_a_fuller_one() -> void:
	# Drawing the first k of the shuffled order: every k' < k is a subset of it, so the same
	# instances stay while the zoom moves.
	var low := FoliageDensityController.thinned_count(200, 0.5)
	var high := FoliageDensityController.thinned_count(200, 0.75)
	assert_lt(low, high)
	assert_eq(low, 100)
	assert_eq(high, 150)


func test_only_ground_cover_chunks_are_thinned() -> void:
	var root := Node3D.new()
	var grass := _chunk(root, "Grass_MultiMesh_c0_0", 100, "grass", true)
	var tree := _chunk(root, "Oak_MultiMesh_c0_0", 100, "tree", false)
	var rock := _chunk(root, "Rock_MultiMesh", 100, "", false)
	var flower := _chunk(root, "Poppy_MultiMesh_c0_0", 100, "grass", false)
	FoliageDensityController.fraction = 0.5
	assert_eq(FoliageDensityController.visible_count(grass), 50)
	assert_eq(FoliageDensityController.visible_count(tree), 100)
	assert_eq(FoliageDensityController.visible_count(rock), 100)
	assert_eq(FoliageDensityController.visible_count(flower), 50, "a flower is ground cover")
	root.free()


func test_a_structure_decor_node_is_not_a_scatter_chunk() -> void:
	# Decor multimeshes carry the category meta but are not shuffled, and are named decor_*.
	var root := Node3D.new()
	var decor := _chunk(root, "decor_ivy", 40, "grass", true)
	FoliageDensityController.fraction = 0.5
	assert_eq(FoliageDensityController.visible_count(decor), 40)
	root.free()


func test_apply_sizes_nested_chunks_at_the_current_fraction() -> void:
	# The production topology: chunks sit under the GLB scene root under "LevelMap", two levels
	# below what the loader hands apply().
	var root := Node3D.new()
	var level_map := Node3D.new()
	level_map.name = "LevelMap"
	root.add_child(level_map)
	_chunk(level_map, "Grass_MultiMesh_c0_0", 50, "grass", true)
	_chunk(level_map, "Grass_MultiMesh_c1_0", 50, "grass", true)
	_chunk(level_map, "Oak_MultiMesh_c0_0", 10, "tree", false)
	FoliageDensityController.fraction = 0.5
	assert_eq(FoliageDensityController.apply(root), 2, "two ground chunks")
	assert_eq(_visible_total_recursive(root), 25 + 25 + 10)
	root.free()


func test_the_fraction_moves_the_visible_counts_both_ways_without_rebuilding() -> void:
	var root := Node3D.new()
	var grass := _chunk(root, "Grass_MultiMesh_c0_0", 64, "grass", true)
	add_child(root)
	FoliageDensityController.apply(root)
	assert_eq(grass.multimesh.visible_instance_count, 64)
	assert_eq(FoliageDensityController.set_fraction(get_tree(), 0.5), 1)
	assert_eq(grass.multimesh.visible_instance_count, 32)
	assert_eq(grass.multimesh.instance_count, 64, "the full set stays built")
	assert_eq(FoliageDensityController.set_fraction(get_tree(), 1.0), 1)
	assert_eq(grass.multimesh.visible_instance_count, 64)
	root.queue_free()


func test_setting_the_same_fraction_writes_nothing() -> void:
	var root := Node3D.new()
	_chunk(root, "Grass_MultiMesh_c0_0", 64, "grass", true)
	add_child(root)
	FoliageDensityController.apply(root)
	assert_eq(FoliageDensityController.set_fraction(get_tree(), 1.0), 0)
	root.queue_free()


func test_nodes_without_the_foliage_meta_are_ignored() -> void:
	# MeshInstancingUtils collapses duplicate static map meshes into MultiMeshInstance3D nodes
	# under the same map_container apply() scans; only nodes carrying wind_foliage_category may
	# be written to.
	var root := Node3D.new()
	var other := MultiMeshInstance3D.new()
	other.name = "SomethingElse_MultiMesh"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 100
	other.multimesh = mm
	root.add_child(other)
	var baseline := mm.visible_instance_count
	FoliageDensityController.fraction = 0.5
	FoliageDensityController.apply(root)
	assert_eq(mm.visible_instance_count, baseline)
	root.free()


func test_the_eye_view_draws_everything() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.size = 30.0
	var thinner := GroundThinner.new()
	var map := GameMap.new()
	map.camera_node = camera
	thinner.setup(map)
	assert_eq(thinner.target_fraction(), 1.0)
	thinner.free()
	map.free()
	camera.free()
