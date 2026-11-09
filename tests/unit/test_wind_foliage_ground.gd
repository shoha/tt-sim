extends GutTest

## The ground-cover variant (card foliagelight, docs/PERFORMANCE.md "Ground-cover lighting"):
## WindFoliage.apply_material builds a grass-category material that is not a flower on the lean
## ground shader, keeps flowers, trees and painted materials on theirs, and the antialiasing
## swap keeps a ground material on the ground pair.


func _mesh_with(material: BaseMaterial3D) -> Mesh:
	var mesh := BoxMesh.new()
	mesh.material = material
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.get_mesh_arrays())
	array_mesh.surface_set_material(0, material)
	return array_mesh


func _cutout() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return material


func _built(category: String, flower: bool, source: BaseMaterial3D = null) -> ShaderMaterial:
	var mesh := _mesh_with(source if source != null else _cutout())
	WindFoliage.apply_material(mesh, category, {}, flower)
	return mesh.surface_get_material(0) as ShaderMaterial


func test_is_ground_cover_by_category() -> void:
	assert_true(WindFoliage.is_ground_cover("grass", false), "grass cards, clumps, litter")
	assert_false(WindFoliage.is_ground_cover("grass", true), "flowers keep the full shader")
	assert_false(WindFoliage.is_ground_cover("tree", false), "trees and shrubs")
	assert_false(WindFoliage.is_ground_cover("climber", false), "wall climbers")


func test_grass_builds_on_the_ground_shader() -> void:
	var material := _built("grass", false)
	assert_eq(material.shader, WindFoliage.get_shader_ground())
	assert_true(material.has_meta(WindFoliage.META_GROUND))


func test_flower_tree_and_climber_keep_the_plain_shader() -> void:
	for case in [["grass", true], ["tree", false], ["climber", false]]:
		var material := _built(case[0], case[1])
		assert_eq(material.shader, WindFoliage.get_shader(), str(case))
		assert_false(material.has_meta(WindFoliage.META_GROUND), str(case))


func test_painted_grass_stays_painted() -> void:
	var source := _cutout()
	source.set_meta("extras", {FoliageLight.EXTRA_KEY: FoliageLight.PAINTED})
	var material := _built("grass", false, source)
	assert_eq(material.shader, FoliageLight.get_shader())
	assert_false(material.has_meta(WindFoliage.META_GROUND))


func test_antialiasing_swap_keeps_the_ground_pair() -> void:
	var material := _built("grass", false)
	assert_eq(WindFoliage.shader_for(material, false), WindFoliage.get_shader_ground_no_aa())
	assert_eq(WindFoliage.shader_for(material, true), WindFoliage.get_shader_ground())


func test_ground_shaders_count_as_wind_shaders() -> void:
	assert_true(WindFoliage.is_wind_shader(WindFoliage.get_shader_ground()))
	assert_true(WindFoliage.is_wind_shader(WindFoliage.get_shader_ground_no_aa()))
	assert_eq(WindFoliage.wind_shaders().size(), 6)
