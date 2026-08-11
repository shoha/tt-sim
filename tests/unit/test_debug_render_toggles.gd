extends GutTest

## Unit tests for DebugRenderToggles' node-collection helpers and toggle-state
## defaults (scenes/states/playing/debug_render_toggles.gd). Mirrors the
## collection-helper test style in test_occlusion_fade_manager.gd. UI wiring and real
## shadow-casting rendering behavior are not covered here -- GUT's --headless mode
## cannot verify real rendering output (see AGENTS.md); see the manual smoke test in
## Task 4 of this plan.


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


func test_get_toggle_states_defaults_trivial_foliage_shader_to_off() -> void:
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)

	var states := toggles.get_toggle_states()

	assert_false(states["toggle_trivial_foliage_shader"])


func test_get_toggle_states_defaults_unshaded_foliage_textured_to_off() -> void:
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)

	var states := toggles.get_toggle_states()

	assert_false(states["toggle_unshaded_foliage_textured"])


func test_get_toggle_states_defaults_cheap_lighting_foliage_to_off() -> void:
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)

	var states := toggles.get_toggle_states()

	assert_false(states["toggle_cheap_lighting_foliage"])


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


func _make_wind_foliage_multimesh(category: String) -> MultiMeshInstance3D:
	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.set_meta("wind_foliage_category", category)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = WindFoliage.get_shader()
	multimesh.mesh.surface_set_material(0, mat)
	mm_inst.multimesh = multimesh
	return mm_inst


func test_trivial_foliage_shader_toggled_on_swaps_material_to_the_debug_shader() -> void:
	var root := Node3D.new()
	var grass_mm := _make_wind_foliage_multimesh("grass")
	root.add_child(grass_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root

	toggles._on_trivial_foliage_shader_toggled(true)

	var mat := grass_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.shader, WindFoliage.get_shader_debug_trivial())

	root.free()


func test_trivial_foliage_shader_toggled_off_restores_the_original_shader() -> void:
	var root := Node3D.new()
	var tree_mm := _make_wind_foliage_multimesh("tree")
	root.add_child(tree_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root
	var mat := tree_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var original_shader := mat.shader

	toggles._on_trivial_foliage_shader_toggled(true)
	toggles._on_trivial_foliage_shader_toggled(false)

	assert_eq(mat.shader, original_shader)

	root.free()


func test_unshaded_foliage_textured_toggled_on_swaps_material_to_the_debug_shader() -> void:
	var root := Node3D.new()
	var grass_mm := _make_wind_foliage_multimesh("grass")
	root.add_child(grass_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root

	toggles._on_unshaded_foliage_textured_toggled(true)

	var mat := grass_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.shader, WindFoliage.get_shader_debug_unshaded())

	root.free()


func test_unshaded_foliage_textured_toggled_off_restores_the_original_shader() -> void:
	var root := Node3D.new()
	var tree_mm := _make_wind_foliage_multimesh("tree")
	root.add_child(tree_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root
	var mat := tree_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var original_shader := mat.shader

	toggles._on_unshaded_foliage_textured_toggled(true)
	toggles._on_unshaded_foliage_textured_toggled(false)

	assert_eq(mat.shader, original_shader)

	root.free()


func test_cheap_lighting_foliage_toggled_on_swaps_material_to_the_debug_shader() -> void:
	var root := Node3D.new()
	var grass_mm := _make_wind_foliage_multimesh("grass")
	root.add_child(grass_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root

	toggles._on_cheap_lighting_foliage_toggled(true)

	var mat := grass_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.shader, WindFoliage.get_shader_debug_cheap_lighting())

	root.free()


func test_cheap_lighting_foliage_toggled_off_restores_the_original_shader() -> void:
	var root := Node3D.new()
	var tree_mm := _make_wind_foliage_multimesh("tree")
	root.add_child(tree_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root
	var mat := tree_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var original_shader := mat.shader

	toggles._on_cheap_lighting_foliage_toggled(true)
	toggles._on_cheap_lighting_foliage_toggled(false)

	assert_eq(mat.shader, original_shader)

	root.free()


func test_switching_from_trivial_to_unshaded_swaps_shader_and_unchecks_the_other_box() -> void:
	var root := Node3D.new()
	var grass_mm := _make_wind_foliage_multimesh("grass")
	root.add_child(grass_mm)
	var toggles := DebugRenderToggles.new()
	add_child_autofree(toggles)
	toggles._map_container = root
	var trivial_checkbox := CheckBox.new()
	var unshaded_checkbox := CheckBox.new()
	var cheap_lighting_checkbox := CheckBox.new()
	toggles._checkboxes = {
		"trivial_foliage_shader": trivial_checkbox,
		"unshaded_foliage_textured": unshaded_checkbox,
		"cheap_lighting_foliage": cheap_lighting_checkbox,
	}
	var mat := grass_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var original_shader := mat.shader

	toggles._on_trivial_foliage_shader_toggled(true)
	assert_eq(mat.shader, WindFoliage.get_shader_debug_trivial())

	toggles._on_unshaded_foliage_textured_toggled(true)
	assert_eq(mat.shader, WindFoliage.get_shader_debug_unshaded())
	assert_false(trivial_checkbox.button_pressed)

	toggles._on_cheap_lighting_foliage_toggled(true)
	assert_eq(mat.shader, WindFoliage.get_shader_debug_cheap_lighting())
	assert_false(trivial_checkbox.button_pressed)
	assert_false(unshaded_checkbox.button_pressed)

	# Restoration after a chain of direct debug-to-debug switches must still recover
	# the real original shader, not one of the debug shaders it passed through.
	toggles._on_cheap_lighting_foliage_toggled(false)
	assert_eq(mat.shader, original_shader)

	trivial_checkbox.free()
	unshaded_checkbox.free()
	cheap_lighting_checkbox.free()
	root.free()
