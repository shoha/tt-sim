extends GutTest

## The painted look of pack tokens (scenes/board_token/token_toon.gd, shaders/token_toon.gdshader):
## the default is Painted and the factory paints a pack token but not an avatar, Original puts back
## the very same material objects, the alpha modes and culling pick the right shader variant, the
## GM-hidden fade and the token ghost keep working on a ShaderMaterial, and the setting is saved
## and applied. How it looks is judged from render-job captures (tools/render_jobs/jobs/
## packtoon_look.json), not here.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TEMP_PATH := "user://test_token_toon_settings.cfg"

var _old_scene: Node = null
var _scene: Node = null
var _was_painted := true
var _was_ghost := true


## DragAndDrop3D's DraggingObject3D waits on the current scene when it enters the tree, and a GUT
## run has none: a bare node under the root stands in for it, and holds the tokens.
func before_each() -> void:
	_was_painted = TokenToon.painted
	_was_ghost = TokenGhost.enabled
	TokenToon.painted = true
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "TokenToonTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	TokenToon.painted = _was_painted
	TokenGhost.enabled = _was_ghost
	get_tree().current_scene = _old_scene
	_scene.free()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _source() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.4, 0.2)
	mat.vertex_color_use_as_albedo = true
	return mat


## A pack token (through the factory, as a loaded GLB makes it) with one box surface in `source`.
func _pack(source: Material, override: Material = null) -> BoardToken:
	var model := Node3D.new()
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.material = source
	part.mesh = box
	if override != null:
		part.set_surface_override_material(0, override)
	model.add_child(part)
	var token := BoardTokenFactory.create_from_scene(model)
	_scene.add_child(token)
	return token


func _part(token: BoardToken) -> MeshInstance3D:
	return TokenGhost.meshes_of(token.rigid_body)[0]


func _surface(token: BoardToken) -> Material:
	return _part(token).get_surface_override_material(0)


func test_default_is_painted_and_the_factory_paints_a_pack_token() -> void:
	assert_true(TokenToon.DEFAULT_PAINTED, "Painted is the default")
	var source := _source()
	var token := _pack(source)
	var painted := _surface(token)
	assert_true(painted is ShaderMaterial, "a ShaderMaterial now")
	assert_eq((painted as ShaderMaterial).shader, TokenToon.shader_for(false, false, false))
	assert_same(_part(token).mesh.surface_get_material(0), source, "the mesh keeps its material")
	assert_true(TokenToon.is_painted(_part(token)))
	assert_eq(TokenToon.painted_meshes(get_tree()), 1)


func test_an_avatar_is_left_alone() -> void:
	var avatar := AvatarTokenFactory.create(AvatarPresets.recipe(1), "Plum")
	_scene.add_child(avatar)
	TokenToon.refresh(avatar)
	assert_eq(TokenToon.painted_meshes(get_tree()), 0, "no avatar mesh is painted")
	for mi in TokenGhost.meshes_of(avatar.rigid_body):
		assert_false(TokenToon.is_painted(mi))


func test_a_token_made_while_original_is_chosen_is_not_painted() -> void:
	TokenToon.painted = false
	var token := _pack(_source())
	assert_null(_surface(token), "no override")
	assert_false(TokenToon.is_painted(_part(token)))


func test_original_restores_the_same_objects_and_painted_swaps_again() -> void:
	var source := _source()
	var kept := _source()
	var token := _pack(source, kept)
	assert_true(_surface(token) is ShaderMaterial)
	TokenToon.set_painted(false, get_tree())
	assert_same(_surface(token), kept, "the override it had is back, the same object")
	assert_eq(TokenToon.painted_meshes(get_tree()), 0)
	assert_false(_part(token).has_meta(TokenToon.ORIGINAL_META), "nothing left recorded")
	TokenToon.set_painted(true, get_tree())
	assert_true(_surface(token) is ShaderMaterial, "painted again")
	var other := _pack(_source())
	TokenToon.set_painted(false, get_tree())
	assert_null(_surface(other), "a token with no override has none again")


func test_tokens_sharing_a_source_share_the_painted_material() -> void:
	var source := _source()
	var a := _pack(source)
	var b := _pack(source)
	assert_same(_surface(a), _surface(b), "one swap per source")
	assert_ne(_surface(a), _surface(_pack(_source())), "a different source gets its own")


func test_the_painted_material_keeps_the_sources_look() -> void:
	var source := _source()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	source.albedo_texture = ImageTexture.create_from_image(image)
	source.emission_enabled = true
	source.emission = Color(1, 0.5, 0)
	source.emission_energy_multiplier = 2.0
	source.alpha_scissor_threshold = 0.3
	var mat := _surface(_pack(source)) as ShaderMaterial
	assert_eq(mat.get_shader_parameter("albedo_color"), source.albedo_color)
	assert_true(mat.get_shader_parameter("use_tex"))
	assert_eq(mat.get_shader_parameter("albedo_tex"), source.albedo_texture)
	assert_true(mat.get_shader_parameter("use_vertex_color"), "vertex colour kept")
	assert_eq(mat.get_shader_parameter("emission_color"), source.emission)
	assert_eq(mat.get_shader_parameter("emission_energy"), 2.0)
	assert_almost_eq(float(mat.get_shader_parameter("alpha_cutoff")), 0.3, 0.0001)


func test_alpha_modes_and_culling_pick_the_shader_variant() -> void:
	var cutout := _source()
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cutout.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blend := _source()
	blend.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cut_mat := _surface(_pack(cutout)) as ShaderMaterial
	assert_eq(cut_mat.shader, TokenToon.shader_for(true, false, true))
	assert_string_contains(cut_mat.shader.code, "#define MODE_SCISSOR")
	assert_string_contains(cut_mat.shader.code, "#define CULL_OFF")
	assert_false("#define MODE_BLEND" in cut_mat.shader.code)
	var blend_mat := _surface(_pack(blend)) as ShaderMaterial
	assert_eq(blend_mat.shader, TokenToon.shader_for(false, true, false))
	assert_string_contains(blend_mat.shader.code, "#define MODE_BLEND")
	var plain := TokenToon.shader_for(false, false, false)
	assert_false(plain.code.begins_with("#define"), "the opaque variant has no define")
	assert_eq(TokenToon._shaders.size(), 6, "six variants")


func test_surfaces_that_cannot_be_painted_keep_their_material() -> void:
	var unshaded := _source()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var additive := _source()
	additive.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	assert_false(TokenToon.paintable(unshaded))
	assert_false(TokenToon.paintable(additive))
	assert_false(TokenToon.paintable(ShaderMaterial.new()))
	var token := _pack(unshaded)
	assert_false(TokenToon.is_painted(_part(token)), "a mesh with nothing paintable is not marked")
	assert_null(_surface(token))


func test_the_hidden_fade_uses_the_blend_variant_and_comes_back() -> void:
	var token := _pack(_source())
	var opaque := _surface(token) as ShaderMaterial
	token.set_visible_to_players(false)
	var faded := _surface(token) as ShaderMaterial
	assert_not_null(faded)
	assert_ne(faded, opaque, "the blend twin while hidden")
	assert_eq(faded.shader, TokenToon.shader_for(false, true, false))
	assert_almost_eq(
		float(_part(token).get_instance_shader_parameter("fade")), TokenToon.HIDDEN_ALPHA, 0.0001
	)
	token.set_visible_to_players(true)
	assert_same(_surface(token), opaque, "the opaque material is back")
	assert_almost_eq(float(_part(token).get_instance_shader_parameter("fade")), 1.0, 0.0001)


func test_switching_to_original_while_hidden_fades_the_original_material() -> void:
	var source := _source()
	var token := _pack(source)
	token.set_visible_to_players(false)
	TokenToon.set_painted(false, get_tree())
	var faded := _surface(token) as StandardMaterial3D
	assert_not_null(faded, "BoardToken's own fade is back on a StandardMaterial3D")
	assert_eq(faded.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(faded.albedo_color.a, TokenToon.HIDDEN_ALPHA, 0.0001)
	assert_eq(source.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "the source untouched")
	TokenToon.set_painted(true, get_tree())
	token.set_visible_to_players(true)
	var back := _surface(token) as ShaderMaterial
	assert_not_null(back)
	assert_eq(back.shader, TokenToon.shader_for(false, false, false), "opaque again, not blended")


func test_the_ghost_reads_the_original_material_of_a_painted_mesh() -> void:
	TokenGhost.enabled = true
	var source := _source()
	source.albedo_color = Color(0.2, 0.6, 0.9)
	var token := _pack(source)
	assert_true(_surface(token) is ShaderMaterial)
	TokenGhost.dress(token)
	var ghost := TokenGhost.overlay_of(_part(token))
	assert_not_null(ghost, "dressed")
	assert_true(ghost.get_shader_parameter("use_albedo"), "a source colour, not the grey default")
	assert_eq(ghost.get_shader_parameter("albedo_col"), source.albedo_color)
	assert_same(ghost.get_meta(TokenGhost.SOURCE_META), source)


func test_warmup_samples_cover_all_six_variants_on_both_layouts() -> void:
	var samples := TokenToon.warmup_samples()
	assert_eq(samples.size(), 12)
	var shaders := {}
	var names := {}
	for sample in samples:
		assert_true(GraphicsWarmup.valid_sample(sample), "well formed: %s" % sample.name)
		assert_false(names.has(sample.name), "unique name %s" % sample.name)
		names[sample.name] = true
		shaders[(sample.material as ShaderMaterial).shader] = true
	assert_eq(shaders.size(), 6)
	for shader: Shader in TokenToon._shaders.values():
		assert_true(shaders.has(shader), "the game's own Shader object is the one warmed")
	assert_true(GraphicsWarmup.COVERED_SHADERS.has("res://shaders/token_toon.gdshader"))
	assert_true(GraphicsWarmup.sample_sources().has(TokenToon.warmup_samples))


func test_every_variant_compiles() -> void:
	for shader: Shader in TokenToon._shaders.values():
		assert_ne(shader.get_rid(), RID(), "has a RID")
		assert_eq(shader.get_mode(), Shader.MODE_SPATIAL)


func test_the_setting_is_saved_and_shown_and_applied() -> void:
	var menu := SETTINGS_SCENE.instantiate() as SettingsMenu
	add_child_autofree(menu)
	await wait_process_frames(1)
	assert_eq(menu.token_shading_option.get_selected_id(), TokenToon.SHADING_PAINTED, "default")
	var original_index := menu.token_shading_option.get_item_index(TokenToon.SHADING_ORIGINAL)
	menu.token_shading_option.select(original_index)
	menu._save_settings(TEMP_PATH)
	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	assert_eq(SettingsTokenShading.saved_id(config), TokenToon.SHADING_ORIGINAL)
	var token := _pack(_source())
	assert_true(_surface(token) is ShaderMaterial)
	SettingsTokenShading.apply(menu)
	assert_false(TokenToon.painted)
	assert_null(_surface(token), "Original applied at once, no restart")
	SettingsTokenShading.show_defaults(menu)
	assert_eq(menu.token_shading_option.get_selected_id(), TokenToon.SHADING_PAINTED)
	SettingsTokenShading.apply(menu)
	assert_true(_surface(token) is ShaderMaterial)
	var empty := ConfigFile.new()
	assert_eq(SettingsTokenShading.saved_id(empty), TokenToon.SHADING_PAINTED, "no key: Painted")
