extends GutTest

## Tests that OcclusionFadeManager keeps shared materials shared (one ShaderMaterial per
## source StandardMaterial3D, not per surface) and skips the per-tick texture update when
## no token moved.


func _make_mesh_instance(material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	mesh_inst.mesh.surface_set_material(0, material)
	return mesh_inst


func _setup_manager(map_container: Node3D) -> OcclusionFadeManager:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var tokens_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())
	manager.setup(camera, map_container, tokens_container)
	return manager


func test_two_meshes_sharing_a_material_get_one_shader_material() -> void:
	var shared := StandardMaterial3D.new()
	var map_container := Node3D.new()
	add_child_autofree(map_container)
	var a := _make_mesh_instance(shared)
	var b := _make_mesh_instance(shared)
	map_container.add_child(a)
	map_container.add_child(b)

	var manager := _setup_manager(map_container)

	assert_eq(manager._all_shader_materials.size(), 1, "One ShaderMaterial for one source")
	assert_eq(
		a.get_surface_override_material(0),
		b.get_surface_override_material(0),
		"Both surfaces reference the same converted material"
	)


func test_distinct_materials_get_distinct_shader_materials() -> void:
	var map_container := Node3D.new()
	add_child_autofree(map_container)
	map_container.add_child(_make_mesh_instance(StandardMaterial3D.new()))
	map_container.add_child(_make_mesh_instance(StandardMaterial3D.new()))

	var manager := _setup_manager(map_container)

	assert_eq(manager._all_shader_materials.size(), 2)


func test_clear_restores_both_sharing_meshes() -> void:
	var shared := StandardMaterial3D.new()
	var map_container := Node3D.new()
	add_child_autofree(map_container)
	var a := _make_mesh_instance(shared)
	var b := _make_mesh_instance(shared)
	map_container.add_child(a)
	map_container.add_child(b)
	var manager := _setup_manager(map_container)

	manager.clear()

	assert_null(
		a.get_surface_override_material(0), "Override cleared; mesh material is the original"
	)
	assert_null(b.get_surface_override_material(0))
	assert_eq(manager._shader_material_by_source.size(), 0)


func _make_token(position: Vector3) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	token.add_child(body)
	token.rigid_body = body
	body.position = position
	return token


func test_update_is_skipped_when_no_token_moved() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var tokens_container := Node3D.new()
	add_child_autofree(tokens_container)
	var token := _make_token(Vector3(1, 0, 1))
	tokens_container.add_child(token)
	var map_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())
	manager.setup(camera, map_container, tokens_container)

	assert_true(manager._update_token_uniforms(), "First tick publishes")
	assert_false(manager._update_token_uniforms(), "Identical tick is skipped")
	token.rigid_body.position = Vector3(2, 0, 1)
	assert_true(manager._update_token_uniforms(), "A moved token publishes again")
	RenderingServer.global_shader_parameter_set(OcclusionFadeManager.GLOBAL_TOKEN_COUNT, 0)


func test_aabb_cache_is_keyed_by_shape_and_cleared_on_clear() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var tokens_container := Node3D.new()
	add_child_autofree(tokens_container)
	tokens_container.add_child(_make_token(Vector3.ZERO))
	var map_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())
	manager.setup(camera, map_container, tokens_container)

	manager._update_token_uniforms()
	assert_eq(manager._aabb_cache.size(), 1)

	manager.clear()
	assert_eq(manager._aabb_cache.size(), 0)
	RenderingServer.global_shader_parameter_set(OcclusionFadeManager.GLOBAL_TOKEN_COUNT, 0)
