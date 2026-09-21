extends GutTest

## OcclusionFadeManager swaps map StandardMaterial3Ds for occlusion_fade.gdshader.
## StandardMaterial3D treats `roughness`/`metallic` as multipliers over their texture
## channel, and glTF ORM maps import with those scalars left at 1.0, so copying the
## scalars while dropping the textures rendered map geometry fully metallic and fully
## rough and discarded ambient occlusion entirely. Regression coverage: assert the
## ORM textures, their channel masks and the AO settings all reach the shader.

const RED := Color(1.0, 0.0, 0.0, 0.0)
const GREEN := Color(0.0, 1.0, 0.0, 0.0)
const BLUE := Color(0.0, 0.0, 1.0, 0.0)


func _manager() -> OcclusionFadeManager:
	var mgr := OcclusionFadeManager.new()
	add_child_autofree(mgr)
	return mgr


## An ORM material as Godot's glTF importer builds one: a single packed texture wired
## into three slots with R=occlusion, G=roughness, B=metallic, scalars left at 1.0.
func _orm_material() -> StandardMaterial3D:
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 1.0
	mat.set_texture(BaseMaterial3D.TEXTURE_ROUGHNESS, tex)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.set_texture(BaseMaterial3D.TEXTURE_METALLIC, tex)
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.ao_enabled = true
	mat.set_texture(BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, tex)
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.ao_light_affect = 0.0
	return mat


func test_orm_textures_are_bound_to_the_shader() -> void:
	var mat := _manager()._create_shader_material_from(_orm_material())

	assert_true(mat.get_shader_parameter("has_roughness_texture"), "roughness texture")
	assert_true(mat.get_shader_parameter("has_metallic_texture"), "metallic texture")
	assert_true(mat.get_shader_parameter("has_ao_texture"), "ao texture")
	assert_not_null(mat.get_shader_parameter("roughness_texture"))
	assert_not_null(mat.get_shader_parameter("metallic_texture"))
	assert_not_null(mat.get_shader_parameter("ao_texture"))


func test_orm_channel_masks_match_the_source_material() -> void:
	var mat := _manager()._create_shader_material_from(_orm_material())

	assert_eq(mat.get_shader_parameter("roughness_texture_channel"), GREEN)
	assert_eq(mat.get_shader_parameter("metallic_texture_channel"), BLUE)
	assert_eq(mat.get_shader_parameter("ao_texture_channel"), RED)


func test_ao_settings_are_copied() -> void:
	var src := _orm_material()
	src.ao_light_affect = 0.25
	src.ao_on_uv2 = true
	var mat := _manager()._create_shader_material_from(src)

	assert_almost_eq(mat.get_shader_parameter("ao_light_affect"), 0.25, 0.001)
	assert_true(mat.get_shader_parameter("ao_on_uv2"))


func test_ao_texture_is_skipped_when_ao_is_disabled() -> void:
	var src := _orm_material()
	src.ao_enabled = false
	var mat := _manager()._create_shader_material_from(src)

	assert_false(mat.get_shader_parameter("has_ao_texture"))


func test_plain_material_without_orm_textures_sets_no_flags() -> void:
	var src := StandardMaterial3D.new()
	src.roughness = 0.4
	src.metallic = 0.0
	var mat := _manager()._create_shader_material_from(src)

	assert_false(mat.get_shader_parameter("has_roughness_texture"))
	assert_false(mat.get_shader_parameter("has_metallic_texture"))
	assert_false(mat.get_shader_parameter("has_ao_texture"))
	assert_almost_eq(mat.get_shader_parameter("roughness"), 0.4, 0.001)
