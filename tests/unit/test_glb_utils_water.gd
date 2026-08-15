extends GutTest

## Unit tests for WaterGlbUtils.process_water_meshes() -- the "-water" suffix convention
## that lets terrain-paint water planes (see the Blender addon's README) get an
## animated water shader with zero per-map setup.


func test_applies_water_shader_to_suffixed_mesh() -> void:
	var root := Node3D.new()
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "Pond-water"
	water_mesh.mesh = PlaneMesh.new()
	root.add_child(water_mesh)

	WaterGlbUtils.process_water_meshes(root)

	assert_not_null(water_mesh.material_override)
	assert_true(water_mesh.material_override is ShaderMaterial)

	root.free()


func test_suffix_match_is_case_insensitive() -> void:
	var root := Node3D.new()
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "Lake-WATER"
	water_mesh.mesh = PlaneMesh.new()
	root.add_child(water_mesh)

	WaterGlbUtils.process_water_meshes(root)

	assert_not_null(water_mesh.material_override)

	root.free()


func test_leaves_unrelated_mesh_untouched() -> void:
	var root := Node3D.new()
	var table_mesh := MeshInstance3D.new()
	table_mesh.name = "Table"
	table_mesh.mesh = BoxMesh.new()
	root.add_child(table_mesh)

	WaterGlbUtils.process_water_meshes(root)

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

	WaterGlbUtils.process_water_meshes(root)

	assert_eq(water_a.material_override, water_b.material_override)

	root.free()


func test_attaches_a_water_zone_sibling_to_the_water_mesh() -> void:
	var root := Node3D.new()
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "Pond-water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	water_mesh.mesh = plane
	root.add_child(water_mesh)

	WaterGlbUtils.process_water_meshes(root)

	var zone := root.get_node_or_null("Pond-water_zone")
	assert_not_null(zone)
	assert_true(zone is WaterZone)

	root.free()


func test_push_disturbance_points_sets_the_shared_material_parameter() -> void:
	var points: Array = [Vector4(1.0, 2.0, 0.0, 1.0)]
	WaterGlbUtils.push_disturbance_points(points)

	var material := WaterGlbUtils._get_water_material()
	assert_eq(material.get_shader_parameter("water_disturbance_points"), points)


func test_apply_water_style_sets_preset_values_on_the_shared_material() -> void:
	WaterGlbUtils.apply_water_style("realistic")

	var material := WaterGlbUtils._get_water_material()
	var expected := WaterPresets.get_preset("realistic")
	assert_eq(material.get_shader_parameter("water_color"), expected["water_color"])
	assert_almost_eq(material.get_shader_parameter("ripple_scale"), expected["ripple_scale"], 0.001)
	assert_almost_eq(
		material.get_shader_parameter("sky_blend_strength"), expected["sky_blend_strength"], 0.001
	)


func test_apply_water_style_falls_back_to_stylized_for_unknown_name() -> void:
	WaterGlbUtils.apply_water_style("not_a_real_style")

	var material := WaterGlbUtils._get_water_material()
	var expected := WaterPresets.get_preset("stylized")
	assert_eq(material.get_shader_parameter("water_color"), expected["water_color"])
