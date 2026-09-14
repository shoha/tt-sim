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
	# plan()'s floor of one applies here too: a hero species must not vanish entirely, even
	# once its allocation has to be split across several chunks. Three chunks of 1 instance
	# each, not one chunk of 1: with a single chunk, visible_counts_for_chunks' fraction is
	# 1.0 and returns 1 unconditionally regardless of rounding, so that fixture could never
	# have caught independent-per-chunk rounding losing the species. Here, kept=1 against
	# total=3 gives each chunk an exact share of 1/3 -- round(1 * 0.333) = 0 on every chunk
	# under the old arithmetic, losing HeroTree entirely; largest-remainder apportionment
	# must instead hand the one allocated instance to one of the three chunks.
	var root := _scene_with({"GrassBlade": [1000], "HeroTree": [1, 1, 1]})
	FoliageDensityController.apply(root, 3000)
	var hero_visible := 0
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi and String(mmi.name).begins_with("HeroTree"):
			hero_visible += mmi.multimesh.visible_instance_count
	assert_eq(hero_visible, 1)
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


func test_applying_a_budget_never_exceeds_it_in_primitives() -> void:
	# Closes the loop Fix 1 fixed: nothing else multiplies visible counts by
	# primitives_per_instance and checks the result against the budget, which is the actual
	# quantity the budget promises to bound -- the per-species report alone doesn't prove it,
	# since visible_counts_for_chunks could still over-allocate a chunk.
	#
	# Five chunks of 7 BoxMesh (12-primitive) instances each: 35 instances, 420 primitives
	# before thinning. Against a 200-primitive budget, plan()'s ratio is 200/420 = 0.47619,
	# so it allocates floor(35 * 0.47619) = floor(16.667) = 16 instances to the species.
	# Splitting 16 across 5 equal chunks of 7 gives each an exact share of 7 * 16 / 35 = 3.2 --
	# not an integer, so this genuinely exercises rounding rather than dividing evenly.
	# 16 instances * 12 primitives = 192, which must land at or under the 200 budget.
	var root := _scene_with({"GrassBlade": [7, 7, 7, 7, 7]})
	var report := FoliageDensityController.apply(root, 200)
	assert_true(report.thinned)
	var total_primitives := 0
	for child in root.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi and mmi.multimesh:
			total_primitives += (
				mmi.multimesh.visible_instance_count
				* FoliageBudget.primitives_per_instance(mmi.multimesh.mesh)
			)
	assert_eq(total_primitives, 192)
	assert_lte(total_primitives, 200)
	root.free()


func test_budget_from_settings_round_trips_a_saved_value() -> void:
	var path := "user://test_foliage_budget_from_settings_round_trip.cfg"
	var config := ConfigFile.new()
	config.set_value(
		FoliageDensityController.SETTINGS_SECTION, FoliageDensityController.SETTINGS_KEY, 5_000_000
	)
	config.save(path)
	assert_eq(FoliageDensityController.budget_from_settings(path), 5_000_000)
	DirAccess.remove_absolute(path)


func test_budget_from_settings_defaults_when_the_key_is_absent() -> void:
	var path := "user://test_foliage_budget_from_settings_missing_key.cfg"
	var config := ConfigFile.new()
	config.set_value(FoliageDensityController.SETTINGS_SECTION, "some_other_key", 1)
	config.save(path)
	assert_eq(FoliageDensityController.budget_from_settings(path), FoliageBudget.PRIMITIVE_BUDGET)
	DirAccess.remove_absolute(path)
