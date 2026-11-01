extends GutTest

## The token toon probe (tools/render_jobs/probes/token_toon.gd): the switch is OFF by default
## and the default path is unchanged, each approach swaps and restores exactly, and the shader
## variants build. How each approach looks is judged from render-job captures
## (tools/render_jobs/jobs/toonprobe_look.json), not here.


func after_each() -> void:
	TokenToonProbe.set_mode(TokenToonProbe.Mode.OFF, get_tree(), null)


func _source() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.4, 0.2)
	mat.vertex_color_use_as_albedo = true
	return mat


func _token(source: Material) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.material = source
	part.mesh = box
	body.add_child(part)
	add_child_autofree(token)
	return token


func _part(token: BoardToken) -> MeshInstance3D:
	return TokenGhost.meshes_of(token.rigid_body)[0]


func test_default_mode_is_off_and_adding_a_token_changes_nothing() -> void:
	assert_eq(TokenToonProbe.mode, TokenToonProbe.Mode.OFF, "OFF by default")
	var source := _source()
	var token := _token(source)
	var part := _part(token)
	assert_null(part.get_surface_override_material(0), "no override added")
	assert_same(part.mesh.surface_get_material(0), source, "the mesh keeps its material")
	assert_false(part.has_meta(TokenToonProbe.ORIGINAL_META), "nothing recorded")
	assert_eq(TokenToonProbe.swapped_meshes(get_tree()), 0)


func test_apply_in_off_mode_does_nothing() -> void:
	var token := _token(_source())
	TokenToonProbe.apply(token)
	assert_null(_part(token).get_surface_override_material(0))


func test_mode_names() -> void:
	assert_eq(TokenToonProbe.mode_named("ramp"), TokenToonProbe.Mode.RAMP)
	assert_eq(TokenToonProbe.mode_named("INK"), TokenToonProbe.Mode.INK)
	assert_eq(TokenToonProbe.mode_named("screen"), TokenToonProbe.Mode.SCREEN)
	assert_eq(TokenToonProbe.mode_named("off"), TokenToonProbe.Mode.OFF)
	assert_eq(TokenToonProbe.mode_named("nonsense"), TokenToonProbe.Mode.OFF)


func test_ramp_swaps_and_off_restores_the_same_objects() -> void:
	var source := _source()
	var token := _token(source)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.RAMP, get_tree(), null)
	var swapped := _part(token).get_surface_override_material(0)
	assert_true(swapped is ShaderMaterial, "a ShaderMaterial now")
	var ramp := swapped as ShaderMaterial
	assert_eq(ramp.get_shader_parameter("albedo_color"), source.albedo_color, "keeps the colour")
	assert_true(ramp.get_shader_parameter("use_vertex_color"), "keeps the vertex colour")
	assert_eq(TokenToonProbe.swapped_meshes(get_tree()), 1)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.OFF, get_tree(), null)
	assert_null(_part(token).get_surface_override_material(0), "override cleared")
	assert_same(_part(token).mesh.surface_get_material(0), source, "the source untouched")
	assert_eq(TokenToonProbe.swapped_meshes(get_tree()), 0)


func test_ink_keeps_the_source_and_chains_the_shared_hull() -> void:
	var source := _source()
	var token := _token(source)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.INK, get_tree(), null)
	var toon := _part(token).get_surface_override_material(0) as StandardMaterial3D
	assert_not_null(toon, "a duplicate of the source")
	assert_ne(toon, source, "not the source itself")
	assert_eq(toon.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON)
	assert_true(toon.next_pass is ShaderMaterial, "the ink pass is chained")
	assert_null(source.next_pass, "the source has no pass added")
	assert_eq(source.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY, "the source's lighting kept")
	# A second token with the same source shares the swapped material and the hull.
	var second := _token(source)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.INK, get_tree(), null)
	assert_same(
		_part(second).get_surface_override_material(0).next_pass,
		_part(token).get_surface_override_material(0).next_pass,
		"one shared ink material"
	)


func test_switching_between_modes_leaves_no_trace_of_the_last() -> void:
	var token := _token(_source())
	TokenToonProbe.set_mode(TokenToonProbe.Mode.RAMP, get_tree(), null)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.INK, get_tree(), null)
	assert_true(_part(token).get_surface_override_material(0) is StandardMaterial3D)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.RAMP, get_tree(), null)
	assert_true(_part(token).get_surface_override_material(0) is ShaderMaterial)


func test_a_transparent_source_gets_no_hull_and_a_blend_ramp() -> void:
	var source := _source()
	source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var token := _token(source)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.INK, get_tree(), null)
	assert_null(_part(token).get_surface_override_material(0).next_pass, "no hull on a blend")
	TokenToonProbe.set_mode(TokenToonProbe.Mode.RAMP, get_tree(), null)
	var shader := (_part(token).get_surface_override_material(0) as ShaderMaterial).shader
	assert_string_contains(shader.code, "#define MODE_BLEND")


func test_ramp_variants_prepend_their_defines() -> void:
	var plain := TokenToonProbe._shader_for(false, false, false)
	var scissor := TokenToonProbe._shader_for(true, false, true)
	assert_false(plain.code.begins_with("#define"), "the plain variant has no define")
	assert_true(scissor.code.begins_with("#define MODE_SCISSOR"))
	assert_string_contains(scissor.code, "#define CULL_OFF")
	assert_same(TokenToonProbe._shader_for(true, false, true), scissor, "built once")


func test_screen_pass_replaces_the_container_material_and_restores_it() -> void:
	var container := SubViewportContainer.new()
	var before := ShaderMaterial.new()
	container.material = before
	add_child_autofree(container)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.SCREEN, get_tree(), container)
	assert_ne(container.material, before, "the screen pass is on")
	assert_true(container.material is ShaderMaterial)
	TokenToonProbe.set_mode(TokenToonProbe.Mode.OFF, get_tree(), container)
	assert_same(container.material, before, "the lo-fi material is back")


func test_an_avatar_token_is_left_alone() -> void:
	var token := _token(_source())
	token.avatar_recipe = {"preset": 1}
	TokenToonProbe.set_mode(TokenToonProbe.Mode.RAMP, get_tree(), null)
	assert_null(_part(token).get_surface_override_material(0))
	assert_eq(TokenToonProbe.swapped_meshes(get_tree()), 0)
