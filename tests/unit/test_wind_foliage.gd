extends GutTest

## Unit tests for WindFoliage (utils/wind_foliage.gd) -- the wind-sway shader GlbUtils
## applies to scattered foliage built by process_scatter_instances() (see
## test_glb_utils_scatter_instances.gd for that feature's own tests). Covers
## classify_category (pure, tested directly against real documented Geoscatter asset
## names -- see terrain-paint's docs/scatter-integration.md) and apply_material's
## per-surface mutation of the Mesh resource itself (confirmed via a real headless
## probe that MultiMeshInstance3D has no set_surface_override_material method at all,
## unlike MeshInstance3D -- see apply_material's own docstring).


func _make_test_texture(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _make_orm_material(albedo_color: Color) -> ORMMaterial3D:
	var material := ORMMaterial3D.new()
	material.albedo_texture = _make_test_texture(albedo_color)
	material.orm_texture = _make_test_texture(Color.WHITE)
	return material


func _make_two_surface_mesh(material_a: Material, material_b: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material_a)
	mesh.surface_set_material(1, material_b)
	return mesh


func test_classify_category_denies_rocks_regardless_of_case() -> void:
	assert_eq(WindFoliage.classify_category("Rock_0_000"), "")
	assert_eq(WindFoliage.classify_category("BOULDER_Big"), "")
	assert_eq(WindFoliage.classify_category("mossy_stone_slab"), "")


func test_classify_category_matches_tree_keywords() -> void:
	assert_eq(WindFoliage.classify_category("OakTree_01"), "tree")
	assert_eq(WindFoliage.classify_category("Pine_Branch_002"), "tree")


func test_classify_category_defaults_to_grass_for_ambiguous_real_names() -> void:
	# Real Geoscatter Plant Library asset names (see docs/scatter-integration.md) --
	# none contain "grass," "fern," or any other plant-taxonomy keyword, so the
	# default must be a generic sway preset, not "no sway."
	assert_eq(WindFoliage.classify_category("FP_Small_Plants_001"), "grass")
	assert_eq(WindFoliage.classify_category("GS Forest seedlings 01"), "grass")
	assert_eq(WindFoliage.classify_category("GS Nettle 01"), "grass")


func test_apply_material_is_a_noop_for_the_deny_category() -> void:
	var original := _make_orm_material(Color.GREEN)
	var mesh := BoxMesh.new()
	mesh.material = original

	WindFoliage.apply_material(mesh, "")

	assert_eq(mesh.surface_get_material(0), original)


func test_apply_material_replaces_the_surface_material_with_the_wind_shader() -> void:
	var albedo := _make_test_texture(Color.GREEN)
	var material := ORMMaterial3D.new()
	material.albedo_texture = albedo
	var orm := _make_test_texture(Color.WHITE)
	material.orm_texture = orm
	var mesh := BoxMesh.new()
	mesh.material = material

	WindFoliage.apply_material(mesh, "grass")

	var wind_material := mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(wind_material)
	assert_eq(wind_material.shader, WindFoliage.get_shader())
	assert_eq(wind_material.get_shader_parameter("albedo_texture"), albedo)
	assert_eq(wind_material.get_shader_parameter("orm_texture"), orm)
	var grass_preset: Dictionary = WindFoliage.PRESETS["grass"]
	assert_eq(wind_material.get_shader_parameter("sway_speed"), grass_preset["sway_speed"])
	assert_eq(wind_material.get_shader_parameter("sway_amplitude"), grass_preset["sway_amplitude"])


func test_apply_material_skips_a_surface_with_no_basematerial3d() -> void:
	# A source using a raw ShaderMaterial already can't be harvested -- confirm this
	# is a defensive skip, not a crash.
	var original := ShaderMaterial.new()
	var mesh := BoxMesh.new()
	mesh.material = original

	WindFoliage.apply_material(mesh, "grass")

	assert_eq(mesh.surface_get_material(0), original)


func test_apply_material_gives_each_surface_its_own_independently_textured_material() -> void:
	# Regression test for the original design's material_override mistake: a real
	# Geoscatter asset can have separate leaf/stem materials on disjoint faces of one
	# mesh (see docs/scatter-integration.md's "GS Forest seedlings 01"). Each surface
	# must be harvested independently, never all painted with surface 0's textures.
	var leaf_albedo := _make_test_texture(Color.GREEN)
	var leaf_material := ORMMaterial3D.new()
	leaf_material.albedo_texture = leaf_albedo
	var stem_albedo := _make_test_texture(Color.html("#5a3a1a"))
	var stem_material := ORMMaterial3D.new()
	stem_material.albedo_texture = stem_albedo
	var mesh := _make_two_surface_mesh(leaf_material, stem_material)

	WindFoliage.apply_material(mesh, "tree")

	var leaf_wind_material := mesh.surface_get_material(0) as ShaderMaterial
	var stem_wind_material := mesh.surface_get_material(1) as ShaderMaterial
	assert_not_null(leaf_wind_material)
	assert_not_null(stem_wind_material)
	assert_eq(leaf_wind_material.get_shader_parameter("albedo_texture"), leaf_albedo)
	assert_eq(stem_wind_material.get_shader_parameter("albedo_texture"), stem_albedo)
	assert_ne(leaf_wind_material, stem_wind_material)


func test_process_scatter_instances_leaves_a_rock_multimesh_with_no_wind_override() -> void:
	var scene := Node3D.new()
	var rock := MeshInstance3D.new()
	rock.name = "Rock_0_000"
	var original := _make_orm_material(Color.GRAY)
	var mesh := BoxMesh.new()
	mesh.material = original
	rock.mesh = mesh
	scene.add_child(rock)
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"Rock_0_000": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	GlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("Rock_0_000_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_eq(multimesh_instance.multimesh.mesh.surface_get_material(0), original)

	scene.free()


func test_process_scatter_instances_applies_wind_to_a_grass_multimesh() -> void:
	var scene := Node3D.new()
	var grass := MeshInstance3D.new()
	grass.name = "GrassBlade"
	var mesh := BoxMesh.new()
	mesh.material = _make_orm_material(Color.GREEN)
	grass.mesh = mesh
	scene.add_child(grass)
	scene.set_meta(
		"tt_gltf_scene_extras",
		{"tt_scatter_instances": {"GrassBlade": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]]}}
	)

	GlbUtils.process_scatter_instances(scene)

	var multimesh_instance := scene.get_node_or_null("GrassBlade_MultiMesh") as MultiMeshInstance3D
	assert_not_null(multimesh_instance)
	assert_true(multimesh_instance.multimesh.mesh.surface_get_material(0) is ShaderMaterial)

	scene.free()
