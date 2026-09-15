extends GutTest

## Unit tests for OcclusionFadeManager's tree-foliage support -- the piece that lets
## tree-category scattered foliage (built by ScatterGlbUtils.process_scatter_instances(),
## tagged via wind_foliage_category meta) participate in the occlusion fade without
## pulling in grass or untagged nodes.


func test_collects_a_tree_tagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	root.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	OcclusionFadeManager._collect_tree_multimeshes(root, result)

	assert_eq(result.size(), 1)
	assert_eq(result[0], tree_mm)

	root.free()


func test_ignores_a_grass_tagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var grass_mm := MultiMeshInstance3D.new()
	grass_mm.set_meta("wind_foliage_category", "grass")
	root.add_child(grass_mm)

	var result: Array[MultiMeshInstance3D] = []
	OcclusionFadeManager._collect_tree_multimeshes(root, result)

	assert_true(result.is_empty())

	root.free()


func test_ignores_an_untagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var untagged_mm := MultiMeshInstance3D.new()
	root.add_child(untagged_mm)

	var result: Array[MultiMeshInstance3D] = []
	OcclusionFadeManager._collect_tree_multimeshes(root, result)

	assert_true(result.is_empty())

	root.free()


func test_ignores_an_invisible_tree_tagged_multimesh_instance() -> void:
	var root := Node3D.new()
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	tree_mm.visible = false
	root.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	OcclusionFadeManager._collect_tree_multimeshes(root, result)

	assert_true(result.is_empty())

	root.free()


func test_recurses_into_nested_children() -> void:
	var root := Node3D.new()
	var wrapper := Node3D.new()
	root.add_child(wrapper)
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	wrapper.add_child(tree_mm)

	var result: Array[MultiMeshInstance3D] = []
	OcclusionFadeManager._collect_tree_multimeshes(root, result)

	assert_eq(result.size(), 1)

	root.free()


func _make_tree_multimesh() -> MultiMeshInstance3D:
	var tree_mm := MultiMeshInstance3D.new()
	tree_mm.set_meta("wind_foliage_category", "tree")
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	var wind_mat := ShaderMaterial.new()
	wind_mat.shader = WindFoliage.get_shader()
	multimesh.mesh.surface_set_material(0, wind_mat)
	tree_mm.multimesh = multimesh
	return tree_mm


func test_setup_registers_tree_material_and_enables_occlusion() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)

	var map_container := Node3D.new()
	var tree_mm := _make_tree_multimesh()
	map_container.add_child(tree_mm)
	add_child_autofree(map_container)

	var tokens_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())

	manager.setup(camera, map_container, tokens_container)

	var wind_mat: ShaderMaterial = tree_mm.multimesh.mesh.surface_get_material(0)
	assert_true(wind_mat.get_shader_parameter("enable_occlusion"))
	assert_true(wind_mat in manager._all_shader_materials)


func test_clear_disables_tree_material_occlusion() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)

	var map_container := Node3D.new()
	var tree_mm := _make_tree_multimesh()
	map_container.add_child(tree_mm)
	add_child_autofree(map_container)

	var tokens_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())

	manager.setup(camera, map_container, tokens_container)
	manager.clear()

	var wind_mat: ShaderMaterial = tree_mm.multimesh.mesh.surface_get_material(0)
	assert_false(wind_mat.get_shader_parameter("enable_occlusion"))


func _make_grass_multimesh() -> MultiMeshInstance3D:
	var grass_mm := MultiMeshInstance3D.new()
	grass_mm.set_meta("wind_foliage_category", "grass")
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BoxMesh.new()
	var wind_mat := ShaderMaterial.new()
	wind_mat.shader = WindFoliage.get_shader()
	multimesh.mesh.surface_set_material(0, wind_mat)
	grass_mm.multimesh = multimesh
	return grass_mm


func test_setup_leaves_grass_material_occlusion_disabled() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var map_container := Node3D.new()
	var grass_mm := _make_grass_multimesh()
	map_container.add_child(grass_mm)
	add_child_autofree(map_container)
	var tokens_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())

	manager.setup(camera, map_container, tokens_container)

	var wind_mat: ShaderMaterial = grass_mm.multimesh.mesh.surface_get_material(0)
	# The shader default must be false and the manager must not have touched it:
	# the token count is a process-global, so this flag is the only thing keeping
	# grass out of the fade loop.
	var enabled: Variant = wind_mat.get_shader_parameter("enable_occlusion")
	assert_true(enabled == null or enabled == false, "Grass must not opt in to the fade")
	assert_false(wind_mat in manager._all_shader_materials)


func test_converted_map_material_opts_in_to_occlusion() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var shader_mat := manager._create_shader_material_from(StandardMaterial3D.new())
	assert_true(shader_mat.get_shader_parameter("enable_occlusion"))
