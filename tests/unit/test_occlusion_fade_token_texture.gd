extends GutTest

## Tests for OcclusionFadeManager's token data path: instead of pushing three uniform
## arrays to every converted material at 30 Hz, the manager packs tokens into one shared
## 32x1 RGBAF texture (xyz = world centre, w = fade radius) and one global int count.
## Under --headless GPU state does not round-trip, so these tests assert on the Image the
## manager builds, never on texture contents read back. They also cannot assert on
## RenderingServer.global_shader_parameter_get(): confirmed via a direct probe that it is
## an editor-only accessor -- it warns "This function should never be used outside the
## editor" and returns null from any running project (a GUT test included), on both the
## headless dummy renderer and a real Vulkan/Forward+ run. OcclusionFadeManager mirrors
## the last published count in _last_token_count for tests to read instead; the real
## RenderingServer.global_shader_parameter_set() call (which does work at runtime) is
## unaffected.


func after_each() -> void:
	RenderingServer.global_shader_parameter_set(OcclusionFadeManager.GLOBAL_TOKEN_COUNT, 0)


func test_build_token_image_packs_entries_and_pads_to_max() -> void:
	var entries: Array[Vector4] = [Vector4(1.0, 2.0, 3.0, 0.5), Vector4(-4.0, 0.25, 6.0, 1.5)]

	var image := OcclusionFadeManager.build_token_image(entries)

	assert_eq(image.get_width(), OcclusionFadeManager.MAX_TOKENS)
	assert_eq(image.get_height(), 1)
	assert_eq(image.get_format(), Image.FORMAT_RGBAF)
	assert_eq(image.get_pixel(0, 0), Color(1.0, 2.0, 3.0, 0.5))
	assert_eq(image.get_pixel(1, 0), Color(-4.0, 0.25, 6.0, 1.5))
	assert_eq(image.get_pixel(2, 0), Color(0, 0, 0, 0), "Unused slots are zero (radius 0)")
	assert_eq(image.get_pixel(OcclusionFadeManager.MAX_TOKENS - 1, 0), Color(0, 0, 0, 0))


func test_build_token_image_truncates_beyond_max() -> void:
	var entries: Array[Vector4] = []
	for i in range(OcclusionFadeManager.MAX_TOKENS + 5):
		entries.append(Vector4(float(i), 0.0, 0.0, 1.0))

	var image := OcclusionFadeManager.build_token_image(entries)

	assert_eq(image.get_width(), OcclusionFadeManager.MAX_TOKENS)
	assert_eq(image.get_pixel(OcclusionFadeManager.MAX_TOKENS - 1, 0).r, 31.0)


func _make_token(position: Vector3, scale: float = 1.0) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 1)
	shape.shape = box
	body.add_child(shape)
	token.add_child(body)
	token.rigid_body = body
	body.position = position
	body.scale = Vector3.ONE * scale
	return token


func test_update_pushes_count_to_global_and_centre_to_image() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var tokens_container := Node3D.new()
	add_child_autofree(tokens_container)
	tokens_container.add_child(_make_token(Vector3(10, 0, 5)))
	tokens_container.add_child(_make_token(Vector3(-2, 0, 0), 2.0))
	var map_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())
	manager.setup(camera, map_container, tokens_container)

	manager._update_token_uniforms()

	assert_eq(manager._last_token_count, 2)
	var px0 := manager._token_image.get_pixel(0, 0)
	assert_almost_eq(px0.r, 10.0, 0.0001)
	# _collect_token_entries' local-centre-y math (unchanged) reads
	# aabb.position.y + aabb.size.y * 0.5 from the shape's OWN debug-mesh AABB, which
	# is centred on the shape's origin for a BoxShape3D (position.y == -size.y/2) --
	# confirmed via a direct probe: aabb.position=(-0.5,-1,-0.5), size=(1,2,1) for this
	# box. That makes the offset exactly 0 for any centred box, at any scale, so the
	# token's centre-y stays at the rigid body's own global y (0 here).
	assert_almost_eq(px0.g, 0.0, 0.0001)
	assert_almost_eq(px0.b, 5.0, 0.0001)
	# Radius: half of max(x,z) footprint (0.5) * fade_radius_multiplier (1.5) = 0.75
	assert_almost_eq(px0.a, 0.75, 0.0001)
	var px1 := manager._token_image.get_pixel(1, 0)
	assert_almost_eq(px1.g, 0.0, 0.0001, "Centred box: local centre y offset is 0 at any scale")
	assert_almost_eq(px1.a, 1.5, 0.0001, "Scale 2 doubles the footprint radius")


func test_clear_resets_global_count() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var tokens_container := Node3D.new()
	add_child_autofree(tokens_container)
	tokens_container.add_child(_make_token(Vector3.ZERO))
	var map_container: Node3D = autofree(Node3D.new())
	var camera: Camera3D = autofree(Camera3D.new())
	manager.setup(camera, map_container, tokens_container)
	manager._update_token_uniforms()
	assert_eq(manager._last_token_count, 1)

	manager.clear()

	assert_eq(manager._last_token_count, 0)


func test_created_material_is_bound_to_the_shared_token_texture() -> void:
	var manager := OcclusionFadeManager.new()
	add_child_autofree(manager)
	var std_mat := StandardMaterial3D.new()

	var shader_mat := manager._create_shader_material_from(std_mat)

	assert_eq(
		shader_mat.get_shader_parameter(OcclusionFadeManager.TOKEN_TEXTURE_UNIFORM),
		manager._token_texture
	)
