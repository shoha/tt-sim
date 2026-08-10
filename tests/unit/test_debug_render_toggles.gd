extends GutTest

## Unit tests for DebugRenderToggles' node-collection helpers and toggle-state
## defaults (scenes/states/playing/debug_render_toggles.gd). Mirrors the
## collection-helper test style in test_occlusion_fade_manager.gd. UI wiring, the
## shader swap, and real shadow/MSAA behavior are not covered here -- GUT's
## --headless mode cannot verify real rendering output (see AGENTS.md); see the
## manual smoke test in Task 4 of this plan.


func test_collects_a_tree_tagged_multimesh() -> void:
	var root := Node3D.new()
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	root.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "tree", result)

	assert_eq(result.size(), 1)
	assert_eq(result[0], tree_mm)

	root.free()


func test_ignores_a_grass_tagged_multimesh_when_collecting_trees() -> void:
	var root := Node3D.new()
	var grass_mm := MultiMeshInstance3D.new()
	grass_mm.set_meta("wind_foliage_category", "grass")
	root.add_child(grass_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "tree", result)

	assert_true(result.is_empty())

	root.free()


func test_collects_a_grass_tagged_multimesh() -> void:
	var root := Node3D.new()
	var grass_mm := MultiMeshInstance3D.new()
	grass_mm.set_meta("wind_foliage_category", "grass")
	root.add_child(grass_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "grass", result)

	assert_eq(result.size(), 1)
	assert_eq(result[0], grass_mm)

	root.free()


func test_ignores_an_untagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var untagged_mm := MultiMeshInstance3D.new()
	root.add_child(untagged_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "tree", result)

	assert_true(result.is_empty())

	root.free()


func test_ignores_an_invisible_tree_tagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	tree_mm.visible = false
	root.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "tree", result)

	assert_true(result.is_empty())

	root.free()


func test_recurses_into_nested_children_for_multimeshes() -> void:
	var root := Node3D.new()
	var wrapper := Node3D.new()
	root.add_child(wrapper)
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	wrapper.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	DebugRenderToggles._collect_multimeshes_by_category(root, "tree", result)

	assert_eq(result.size(), 1)

	root.free()


func test_collect_mesh_instances_finds_a_visible_mesh_with_geometry() -> void:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	root.add_child(mesh_inst)

	var result: Array[MeshInstance3D] = []
	DebugRenderToggles._collect_mesh_instances(root, result)

	assert_eq(result.size(), 1)
	assert_eq(result[0], mesh_inst)

	root.free()


func test_collect_mesh_instances_skips_a_mesh_instance_with_no_mesh_resource() -> void:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	root.add_child(mesh_inst)

	var result: Array[MeshInstance3D] = []
	DebugRenderToggles._collect_mesh_instances(root, result)

	assert_true(result.is_empty())

	root.free()


func test_collect_mesh_instances_ignores_invisible_mesh_instance() -> void:
	var root := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	mesh_inst.visible = false
	root.add_child(mesh_inst)

	var result: Array[MeshInstance3D] = []
	DebugRenderToggles._collect_mesh_instances(root, result)

	assert_true(result.is_empty())

	root.free()


func test_get_toggle_states_defaults_to_everything_on() -> void:
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)

	var states := toggles.get_toggle_states()

	assert_true(states["toggle_foliage_visible"])
	assert_true(states["toggle_tree_shadows"])
	assert_true(states["toggle_grass_shadows"])
	assert_true(states["toggle_map_shadows"])


func test_apply_shadow_setting_true_sets_cast_shadow_on() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	DebugRenderToggles._apply_shadow_setting([mesh_inst], true)

	assert_eq(mesh_inst.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	mesh_inst.free()


func test_apply_shadow_setting_false_sets_cast_shadow_off() -> void:
	var mesh_inst := MeshInstance3D.new()

	DebugRenderToggles._apply_shadow_setting([mesh_inst], false)

	assert_eq(mesh_inst.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	mesh_inst.free()
