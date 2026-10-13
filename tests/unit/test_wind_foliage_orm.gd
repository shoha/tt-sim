extends GutTest

## Unit tests for the wind shaders' ORM fallback (WindFoliage.orm_texture_of and the
## has_orm_texture flag): an asset without a packed ORM texture used to render black under
## the wind shaders, because the ORM sampler's white default read as metallic 1.0 (found by
## treecube's kit probe, 2026-10-12). Now WindFoliage flags a harvested ORM and the shaders
## take metallic 0 without one; an asset with an ORM (every treecube asset) reads it as before.

const INCLUDE_PATH := "res://shaders/wind_foliage_include.gdshaderinc"


func _make_test_texture(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _wind_material_for(source: BaseMaterial3D) -> ShaderMaterial:
	var mesh := BoxMesh.new()
	mesh.material = source
	WindFoliage.apply_material(mesh, "tree")
	return mesh.surface_get_material(0) as ShaderMaterial


func test_an_orm_material3d_texture_is_flagged() -> void:
	var material := ORMMaterial3D.new()
	material.albedo_texture = _make_test_texture(Color.GREEN)
	var orm := _make_test_texture(Color.WHITE)
	material.orm_texture = orm

	var wind_material := _wind_material_for(material)

	assert_eq(wind_material.get_shader_parameter("orm_texture"), orm)
	assert_true(wind_material.get_shader_parameter("has_orm_texture"))


func test_a_glb_packed_orm_on_a_standard_material_is_flagged() -> void:
	# The shape Godot's glTF importer gives a packed ORM: one image on all three slots.
	var material := StandardMaterial3D.new()
	material.albedo_texture = _make_test_texture(Color.GREEN)
	var orm := _make_test_texture(Color(1.0, 0.85, 0.0))
	material.ao_texture = orm
	material.metallic_texture = orm
	material.roughness_texture = orm

	var wind_material := _wind_material_for(material)

	assert_eq(WindFoliage.orm_texture_of(material), orm)
	assert_eq(wind_material.get_shader_parameter("orm_texture"), orm)
	assert_true(wind_material.get_shader_parameter("has_orm_texture"))


func test_a_material_without_an_orm_texture_leaves_the_flag_off() -> void:
	# The kit probe's black asset: no ORM texture at all. The flag stays at its default
	# (off), so the shader takes metallic 0 (ASSET_PIPELINE.md section 6 "Packed ORM").
	for material: BaseMaterial3D in [StandardMaterial3D.new(), ORMMaterial3D.new()]:
		material.albedo_texture = _make_test_texture(Color.GREEN)

		var wind_material := _wind_material_for(material)

		assert_null(WindFoliage.orm_texture_of(material))
		assert_null(wind_material.get_shader_parameter("orm_texture"))
		assert_ne(wind_material.get_shader_parameter("has_orm_texture"), true)


func test_every_wind_shader_gates_its_metallic_on_the_flag() -> void:
	# Every wind variant shares the include, so each must see the flag; a variant reading
	# orm.b unguarded would render an ORM-less asset black again.
	for shader: Shader in [WindFoliage.get_shader(), FoliageLight.get_shader()]:
		var names: Array = shader.get_shader_uniform_list().map(
			func(uniform: Dictionary) -> String: return uniform["name"]
		)
		assert_has(names, "has_orm_texture", shader.resource_path)
	var include := FileAccess.get_file_as_string(INCLUDE_PATH)
	assert_true(include.contains("uniform bool has_orm_texture = false;"))
	assert_true(include.contains("out_metallic = orm.b * float(has_orm_texture);"))


func test_the_flag_is_never_read_through_a_ternary() -> void:
	# `has_orm_texture ? orm.b : 0.0` (0fe3d41) segfaulted the game from a background thread,
	# with no backtrace, every time a saved authored map was opened in authoring on
	# Godot 4.7.2 / Vulkan; the product form does not (bisected and A/B-tested 2026-10-13).
	var include := FileAccess.get_file_as_string(INCLUDE_PATH)
	var ternary := RegEx.create_from_string("has_orm_texture\\s*\\?")
	assert_null(ternary.search(include), "has_orm_texture must not drive a ternary")
