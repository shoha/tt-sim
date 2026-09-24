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


func test_apply_water_settings_sets_floats_colors_and_hex_strings() -> void:
	(
		WaterGlbUtils
		. apply_water_settings(
			{
				"wave_speed": 2.25,
				"water_color": Color(0.1, 0.2, 0.3, 0.4),
				"foam_color": Color(0.5, 0.6, 0.7, 0.8).to_html(true),
				"not_a_uniform": 9.0,
			}
		)
	)

	var material := WaterGlbUtils._get_water_material()
	assert_almost_eq(material.get_shader_parameter("wave_speed"), 2.25, 0.001)
	assert_true(
		WaterSettings.colors_match(
			material.get_shader_parameter("water_color"), Color(0.1, 0.2, 0.3, 0.4)
		)
	)
	assert_true(
		WaterSettings.colors_match(
			material.get_shader_parameter("foam_color"), Color(0.5, 0.6, 0.7, 0.8)
		)
	)
	assert_null(material.get_shader_parameter("not_a_uniform"))


func test_apply_water_settings_from_resource_round_trips_through_the_material() -> void:
	var settings := WaterSettings.from_style("realistic")
	WaterGlbUtils.apply_water_settings(settings.to_dict())

	var material := WaterGlbUtils._get_water_material()
	assert_true(
		WaterSettings.colors_match(
			material.get_shader_parameter("shore_color"), settings.shore_color
		)
	)
	assert_almost_eq(material.get_shader_parameter("roughness_value"), 0.06, 0.001)


## A "-water" plane as Godot's GLTF importer produces it: a PlaneMesh whose surface
## material is a StandardMaterial3D, with or without an emission texture (terrain-paint
## carries the flow map there). terrain-paint's Add Water Plane is a 1x1 quad with the
## size on the object scale, and glTF carries that as node scale -- so the mesh's own
## PlaneMesh stays 1x1 here and `size` lands on the node's scale instead, mirroring what
## the importer actually hands the loader.
func _water_plane(name: String, size: float, with_flow: bool) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = name
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	if with_flow:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(0.5, 0.5, 0.0))
		material.emission_texture = ImageTexture.create_from_image(image)
	plane.material = material
	mesh_node.mesh = plane
	mesh_node.scale = Vector3(size, 1.0, size)
	return mesh_node


func test_extract_flow_map_returns_the_imported_emission_texture() -> void:
	var plane := _water_plane("Lake-water", 4.0, true)
	var expected: Texture2D = (
		(plane.mesh.surface_get_material(0) as BaseMaterial3D).emission_texture
	)
	assert_eq(WaterGlbUtils._extract_flow_map(plane), expected)
	plane.free()


func test_extract_flow_map_is_null_without_texture_material_or_mesh() -> void:
	var bare := _water_plane("Pond-water", 4.0, false)
	assert_null(WaterGlbUtils._extract_flow_map(bare))
	bare.free()
	var no_material := MeshInstance3D.new()
	no_material.mesh = PlaneMesh.new()
	assert_null(WaterGlbUtils._extract_flow_map(no_material))
	no_material.free()
	var no_mesh := MeshInstance3D.new()
	assert_null(WaterGlbUtils._extract_flow_map(no_mesh))
	no_mesh.free()
	assert_null(WaterGlbUtils._extract_flow_map(null))


func test_flow_map_goes_to_the_largest_carrying_plane_only() -> void:
	var root := Node3D.new()
	var small := _water_plane("Pond-water", 2.0, true)
	var big := _water_plane("Lake-water", 8.0, true)
	var plain := _water_plane("Puddle-water", 20.0, false)
	root.add_child(small)
	root.add_child(big)
	root.add_child(plain)

	WaterGlbUtils.process_water_meshes(root)

	var material := WaterGlbUtils._get_water_material()
	assert_eq(
		material.get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM),
		WaterGlbUtils._extract_flow_map(big)
	)
	assert_true(big.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM))
	assert_false(bool(small.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM)))
	assert_false(bool(plain.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM)))
	root.free()


## Regression for the mesh-local-AABB bug: the mesh's own PlaneMesh is always the same
## unscaled 1x1 quad, so the footprint has to come from the node-scale chain up to the
## root passed to process_water_meshes, not mesh.get_aabb(). A carrying plane nested
## under a scaled intermediate Node3D (scale 4) with a smaller node scale (3, so
## effective footprint 12x12) must beat a top-level plane with a larger node scale (10)
## but no parent scale, proving the chain is accumulated rather than read off either
## node alone.
func test_flow_map_footprint_accumulates_through_parent_node_scale() -> void:
	var root := Node3D.new()
	# top_level is added -- and therefore traversed -- first: with the mesh-local-AABB
	# bug both planes report the same unscaled 1x1 footprint, a tie that falls through to
	# traversal order and would pick top_level here, the wrong answer. Only measuring the
	# footprint through the node-scale chain breaks the tie correctly, in either order.
	var top_level := _water_plane("Pond-water", 10.0, true)
	root.add_child(top_level)
	var wrapper := Node3D.new()
	wrapper.scale = Vector3(4.0, 1.0, 4.0)
	root.add_child(wrapper)
	var nested := _water_plane("River-water", 3.0, true)
	wrapper.add_child(nested)

	WaterGlbUtils.process_water_meshes(root)

	var material := WaterGlbUtils._get_water_material()
	assert_eq(
		material.get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM),
		WaterGlbUtils._extract_flow_map(nested)
	)
	assert_true(nested.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM))
	assert_false(bool(top_level.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM)))
	root.free()


func test_a_level_without_a_flow_map_clears_the_shared_parameter() -> void:
	var with_map := Node3D.new()
	with_map.add_child(_water_plane("Lake-water", 8.0, true))
	WaterGlbUtils.process_water_meshes(with_map)
	assert_not_null(
		WaterGlbUtils._get_water_material().get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM)
	)
	with_map.free()

	var without := Node3D.new()
	without.add_child(_water_plane("Pond-water", 8.0, false))
	WaterGlbUtils.process_water_meshes(without)
	assert_null(
		WaterGlbUtils._get_water_material().get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM)
	)
	without.free()


## Every GLB goes through process_water_meshes, including token models loaded AFTER the
## level (AssetModelCache -> GlbUtils.load_glb_with_processing). A scene with no "-water"
## mesh at all must therefore leave the shared sampler alone: clearing it here wiped the
## River level's flow map the moment the first token model loaded, and the still-flagged
## plane then decoded the unbound sampler as a full-speed diagonal current. Only a scene
## that carries water planes (a level swap) may clear it, which the test above covers.
func test_a_scene_with_no_water_mesh_leaves_the_shared_parameter_alone() -> void:
	var with_map := Node3D.new()
	with_map.add_child(_water_plane("Lake-water", 8.0, true))
	WaterGlbUtils.process_water_meshes(with_map)
	var flow_map: Texture2D = WaterGlbUtils._get_water_material().get_shader_parameter(
		WaterGlbUtils.FLOW_MAP_PARAM
	)
	assert_not_null(flow_map)

	var token_model := Node3D.new()
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "Bulbasaur"
	body_mesh.mesh = BoxMesh.new()
	token_model.add_child(body_mesh)
	WaterGlbUtils.process_water_meshes(token_model)
	assert_eq(
		WaterGlbUtils._get_water_material().get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM),
		flow_map,
		"a later GLB without water must not clear the level's flow map"
	)
	token_model.free()
	with_map.free()
