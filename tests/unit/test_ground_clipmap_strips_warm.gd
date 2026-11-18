extends GutTest

## The ground clipmap strip bake's warm-up viewports (GroundClipmapStrips.warm_viewports, card
## painter-level-entry): the first-launch graphics warm-up draws each bake shader and pass once in a
## strip-format viewport, one a frame, so a level's first strip draw compiles nothing.

var _warm: Array[SubViewport] = []


func before_each() -> void:
	_warm = GroundClipmapStrips.warm_viewports()


func after_each() -> void:
	for vp in _warm:
		vp.free()
	_warm.clear()


func test_one_viewport_per_bake_shader_and_pass() -> void:
	assert_eq(_warm.size(), 4)
	var seen := {}
	for vp in _warm:
		var mi := vp.get_child(vp.get_child_count() - 1) as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		var pass_index := int(mat.get_shader_parameter("bake_pass"))
		seen["%s_%d" % [mat.shader.resource_path.get_file(), pass_index]] = true
	assert_eq(seen.size(), 4, "every shader and pass once")
	assert_true(seen.has("authored_ground_bake.gdshader_0"))
	assert_true(seen.has("authored_ground_bake.gdshader_1"))
	assert_true(seen.has("authored_ground_bake_looked.gdshader_0"))
	assert_true(seen.has("authored_ground_bake_looked.gdshader_1"))


func test_viewports_wait_until_asked_and_draw_once() -> void:
	for vp in _warm:
		assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	GroundClipmapStrips.render_warm(_warm, 1)
	assert_eq(_warm[1].render_target_update_mode, SubViewport.UPDATE_ONCE)
	assert_eq(_warm[0].render_target_update_mode, SubViewport.UPDATE_DISABLED)
	GroundClipmapStrips.render_warm(_warm, -1)
	GroundClipmapStrips.render_warm(_warm, _warm.size())


func test_the_session_keeps_every_warm_material() -> void:
	var samples := GroundClipmapStrips.warm_samples(_warm)
	assert_eq(samples.size(), 4)
	for sample: Dictionary in samples:
		assert_true(sample["material"] is ShaderMaterial)
	var before := GraphicsWarmup.kept_material_count()
	GraphicsWarmup.keep_materials(samples)
	assert_eq(GraphicsWarmup.kept_material_count(), before + 4)
	GraphicsWarmup.release_materials()


func test_the_framebuffer_is_the_strips_own() -> void:
	for vp in _warm:
		assert_true(vp.own_world_3d)
		assert_true(vp.transparent_bg)
		assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED)
		assert_eq(vp.size, Vector2i(GroundClipmapStrips.WARM_PX, GroundClipmapStrips.WARM_PX))
		assert_true((vp.get_child(0) as Camera3D).current)


func test_the_triangle_fills_a_chunks_layout_and_nothing_else() -> void:
	var arrays := GroundClipmapStrips._warm_arrays()
	for slot in Mesh.ARRAY_MAX:
		assert_eq(
			arrays[slot] != null,
			GroundClipmapStrips.WARM_LAYOUT.has(slot),
			"slot %d" % slot
		)


func test_the_layout_is_the_painters_ground_layout() -> void:
	assert_eq(GroundClipmapStrips.WARM_LAYOUT, PainterWarmup.LAYOUT_GROUND)
