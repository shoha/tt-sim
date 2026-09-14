extends GutTest

## Unit tests for FoliageDensityController -- the runtime half of the foliage density
## setting. Import builds every scatter instance; this applies the user's budget by
## writing MultiMesh.visible_instance_count per chunk. See docs/PERFORMANCE.md.


func _chunk(parent: Node3D, node_name: String, instances: int, category: String) -> void:
	var mesh := BoxMesh.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = instances
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.set_meta("wind_foliage_category", category)
	parent.add_child(node)


func _scene_with(species: Dictionary) -> Node3D:
	# species maps a species name to an array of per-chunk instance counts.
	var root := Node3D.new()
	for name in species.keys():
		var counts: Array = species[name]
		for i in counts.size():
			var suffix := "" if counts.size() == 1 else "_c%d_0" % i
			_chunk(root, "%s_MultiMesh%s" % [name, suffix], counts[i], "grass")
	return root


func _visible_total(root: Node3D) -> int:
	var total := 0
	for child in root.get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.visible_instance_count
	return total


## Recurses, unlike _visible_total -- used only by the nested-chunk test below, so a future
## regression in recursion still fails loudly on every flat-fixture test rather than being
## silently masked by a helper that always recurses.
func _visible_total_recursive(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.visible_instance_count
		total += _visible_total_recursive(child)
	return total


func test_a_map_under_budget_shows_every_instance() -> void:
	# 100 instances of a 12-primitive BoxMesh is 1,200 -- far inside any real budget.
	var root := _scene_with({"GrassBlade": [50, 50]})
	var report := FoliageDensityController.apply(root, 1000000)
	assert_false(report.thinned)
	assert_eq(_visible_total(root), 100)
	root.free()


func test_a_map_over_budget_is_reduced_to_fit() -> void:
	# 100 instances x 12 primitives = 1,200 against a 600 budget -> half visible.
	var root := _scene_with({"GrassBlade": [50, 50]})
	var report := FoliageDensityController.apply(root, 600)
	assert_true(report.thinned)
	assert_eq(_visible_total(root), 50)
	root.free()


func test_chunks_nested_below_the_root_are_still_applied() -> void:
	# The production topology: ScatterGlbUtils parents chunks under the GLB scene root,
	# level_loader parents that root under map_container as "LevelMap", and
	# GameMap.apply_foliage_density passes map_container. So every chunk sits two levels
	# down. A write-back that only resolved direct children would leave them untouched at
	# -1 here while still counting them into the plan -- which is exactly the bug this
	# test exists to prevent, and which a flat fixture cannot see.
	#
	# 100 instances of a 12-primitive BoxMesh is 1,200 primitives against a 600 budget:
	# ratio 600/1200 = 0.5, so 50 of the 100 instances stay visible.
	var root := Node3D.new()
	var level_map := Node3D.new()
	level_map.name = "LevelMap"
	root.add_child(level_map)
	_chunk(level_map, "GrassBlade_MultiMesh_c0_0", 50, "grass")
	_chunk(level_map, "GrassBlade_MultiMesh_c1_0", 50, "grass")
	var report := FoliageDensityController.apply(root, 600)
	assert_true(report.thinned)
	assert_eq(_visible_total_recursive(root), 50)
	root.free()


func test_instance_count_is_never_changed_only_visible_count() -> void:
	# The full set must stay built so the slider can raise again without a reload.
	var root := _scene_with({"GrassBlade": [50, 50]})
	FoliageDensityController.apply(root, 600)
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		assert_eq(mmi.multimesh.instance_count, 50)
	root.free()


func test_raising_the_budget_raises_visible_counts_without_rebuilding() -> void:
	var root := _scene_with({"GrassBlade": [50, 50]})
	FoliageDensityController.apply(root, 600)
	assert_eq(_visible_total(root), 50)
	FoliageDensityController.apply(root, 1000000)
	assert_eq(_visible_total(root), 100)
	root.free()


func test_a_deny_listed_rock_species_is_budgeted_too() -> void:
	# classify_category returns "" for rock/stone/boulder names, which decides what sways
	# in the wind, not what costs primitives. Budgeting only tree and grass would let a map
	# escape the cap by naming a species rock_grass.
	var root := Node3D.new()
	_chunk(root, "RockCluster_MultiMesh", 100, "")
	var report := FoliageDensityController.apply(root, 600)
	assert_true(report.thinned)
	assert_eq(_visible_total(root), 50)
	root.free()


func test_a_species_is_never_reduced_to_zero_instances() -> void:
	# plan()'s floor of one applies here too: a hero species must not vanish entirely.
	var root := _scene_with({"GrassBlade": [1000], "HeroTree": [1]})
	FoliageDensityController.apply(root, 3000)
	var hero := root.get_node_or_null("HeroTree_MultiMesh") as MultiMeshInstance3D
	assert_eq(hero.multimesh.visible_instance_count, 1)
	root.free()


func test_nodes_without_the_foliage_meta_are_ignored() -> void:
	# Asserting "unchanged from whatever it was before apply() ran" states the real
	# invariant directly -- this node was never touched at all -- rather than via an
	# engine default constant that could shift across Godot versions.
	#
	# This matters beyond tidiness: MeshInstancingUtils collapses duplicate static map
	# meshes into MultiMeshInstance3D nodes under the same map_container this controller
	# scans. If the controller zeroed every MultiMesh it found and then raised only the
	# foliage ones, applying any density setting would hide collapsed walls, props and
	# terrain detail. Only nodes carrying wind_foliage_category may be written to.
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
	var report := FoliageDensityController.apply(root, 600)
	assert_false(report.thinned)
	assert_eq(mm.visible_instance_count, baseline)
	root.free()
