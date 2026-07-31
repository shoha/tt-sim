extends GutTest

## Unit tests for GlbUtils.process_water_meshes() -- the "-water" suffix convention
## that lets terrain-paint water planes (see the Blender addon's README) get an
## animated water shader with zero per-map setup.


func test_applies_water_shader_to_suffixed_mesh() -> void:
	var root := Node3D.new()
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "Pond-water"
	water_mesh.mesh = PlaneMesh.new()
	root.add_child(water_mesh)

	GlbUtils.process_water_meshes(root)

	assert_not_null(water_mesh.material_override)
	assert_true(water_mesh.material_override is ShaderMaterial)

	root.free()


func test_suffix_match_is_case_insensitive() -> void:
	var root := Node3D.new()
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "Lake-WATER"
	water_mesh.mesh = PlaneMesh.new()
	root.add_child(water_mesh)

	GlbUtils.process_water_meshes(root)

	assert_not_null(water_mesh.material_override)

	root.free()


func test_leaves_unrelated_mesh_untouched() -> void:
	var root := Node3D.new()
	var table_mesh := MeshInstance3D.new()
	table_mesh.name = "Table"
	table_mesh.mesh = BoxMesh.new()
	root.add_child(table_mesh)

	GlbUtils.process_water_meshes(root)

	assert_null(table_mesh.material_override)

	root.free()


func test_shares_one_material_instance_across_multiple_meshes() -> void:
	var root := Node3D.new()
	var water_a := MeshInstance3D.new()
	water_a.name = "Lake-water"
	water_a.mesh = PlaneMesh.new()
	root.add_child(water_a)
	var water_b := MeshInstance3D.new()
	water_b.name = "Pond-water"
	water_b.mesh = PlaneMesh.new()
	root.add_child(water_b)

	GlbUtils.process_water_meshes(root)

	assert_eq(water_a.material_override, water_b.material_override)

	root.free()
