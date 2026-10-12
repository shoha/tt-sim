extends GutTest

## Tests for the painted foliage light (FoliageLight, utils/foliage_light.gd): a leaf material
## carrying the glTF extra tt_foliage_light "painted" gets the painted wind shader variant and
## one without keeps today's shader; the antialiasing swap keeps each in its form; both
## painted variants are warmed; and the foliage_sun global follows the level's sun.


class FakeGameMap:
	extends Node

	func apply_lofi_overrides(_overrides: Dictionary) -> void:
		pass


func _leaf_mesh(extras: Variant) -> ArrayMesh:
	var box := BoxMesh.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var source := StandardMaterial3D.new()
	source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if extras != null:
		source.set_meta("extras", extras)
	mesh.surface_set_material(0, source)
	return mesh


func test_a_material_with_the_extra_gets_the_painted_variant() -> void:
	var mesh := _leaf_mesh({FoliageLight.EXTRA_KEY: FoliageLight.PAINTED})
	WindFoliage.apply_material(mesh, "tree")
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(material.shader, FoliageLight.get_shader())
	assert_eq(material.shader.resource_path, "res://shaders/wind_foliage_painted.gdshader")
	assert_true(material.has_meta(FoliageLight.META_PAINTED))
	assert_eq(material.get_shader_parameter("canopy_part"), WindFoliage.CANOPY_CARD)


func test_a_material_without_the_extra_keeps_todays_shader() -> void:
	for extras: Variant in [null, {}, {"other": 1}, {FoliageLight.EXTRA_KEY: "flat"}, "painted"]:
		var mesh := _leaf_mesh(extras)
		WindFoliage.apply_material(mesh, "tree")
		var material := mesh.surface_get_material(0) as ShaderMaterial
		assert_eq(material.shader, WindFoliage.get_shader(), "extras %s" % str(extras))
		assert_false(material.has_meta(FoliageLight.META_PAINTED))


func test_tree_leaf_cutouts_take_the_leaf_shadow_push_and_blended_cards_do_not() -> void:
	var leaf := _leaf_mesh(null)
	WindFoliage.apply_material(leaf, "tree")
	var push: Variant = (leaf.surface_get_material(0) as ShaderMaterial).get_shader_parameter(
		"shadow_caster_push"
	)
	assert_eq(push, FoliageLight.LEAF_SHADOW_PUSH)
	var baked := _leaf_mesh(null)
	(baked.surface_get_material(0) as BaseMaterial3D).transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	WindFoliage.apply_material(baked, "tree")
	assert_null(
		(baked.surface_get_material(0) as ShaderMaterial).get_shader_parameter(
			"shadow_caster_push"
		),
		"a Blender map's blended surfaces keep the shader default"
	)


func test_the_installed_palette_flags_broadleaf_leaves_and_nothing_else() -> void:
	# docs/ASSET_PIPELINE.md section 6: oak, birch, bush, poplar and their saplings carry the
	# extra on their leaf material; pines and every non-leaf material do not.
	var painted := PackedStringArray()
	var seen := {}
	for biome in PaletteLibrary.biomes():
		for rule in PaletteLibrary.species(String(biome.id)):
			for asset_id in rule.get("assets", []):
				if seen.has(asset_id):
					continue
				seen[asset_id] = true
				var mesh := PaletteLibrary.resolve(String(asset_id)).get("mesh") as Mesh
				if mesh == null:
					continue
				for i in mesh.get_surface_count():
					var source := mesh.surface_get_material(i) as BaseMaterial3D
					if source == null or not FoliageLight.is_painted(source):
						continue
					var file := String(asset_id).get_file()
					painted.append(file)
					assert_false(file.begins_with("Tree_Pine"), "%s is a pine" % file)
					assert_true(WindFoliage.is_leaf_cutout(source), "%s: a leaf cutout" % file)
	assert_gt(painted.size(), 10, "the round 5 broadleaf crowns are flagged: %s" % str(painted))


func test_the_antialiasing_swap_keeps_painted_and_plain_apart() -> void:
	var painted := ShaderMaterial.new()
	painted.set_meta(FoliageLight.META_PAINTED, true)
	var plain := ShaderMaterial.new()
	assert_eq(WindFoliage.shader_for(painted, true), FoliageLight.get_shader())
	assert_eq(WindFoliage.shader_for(painted, false), FoliageLight.get_shader_no_aa())
	assert_eq(WindFoliage.shader_for(plain, true), WindFoliage.get_shader())
	assert_eq(WindFoliage.shader_for(plain, false), WindFoliage.get_shader_no_aa())
	for shader in WindFoliage.wind_shaders():
		assert_true(WindFoliage.is_wind_shader(shader))
	assert_false(WindFoliage.is_wind_shader(load("res://shaders/wind_foliage_burn.gdshader")))


func test_both_painted_variants_are_warmed() -> void:
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/wind_foliage_painted.gdshader")
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/wind_foliage_painted_no_aa.gdshader")


func test_sun_value_points_toward_the_sun_and_weighs_its_energy() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	light.light_energy = 2.0
	var value := FoliageLight.sun_value(light)
	assert_almost_eq(Vector3(value.x, value.y, value.z), Vector3.UP, Vector3.ONE * 0.001)
	assert_eq(value.w, 1.0, "energy clamps to a full weight")
	light.light_energy = 0.4
	assert_almost_eq(FoliageLight.sun_value(light).w, 0.4, 0.0001)
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	assert_lt(FoliageLight.sun_value(light).w, 0.1, "a sun 4 degrees up weighs little")
	light.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	assert_eq(FoliageLight.sun_value(light).w, 1.0, "35 degrees up weighs fully")
	light.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	assert_eq(FoliageLight.sun_value(light).w, 0.0, "below the horizon weighs nothing")
	light.visible = false
	assert_eq(FoliageLight.sun_value(light).w, 0.0, "a hidden sun weighs nothing")
	assert_eq(FoliageLight.sun_value(null), FoliageLight.NO_SUN)
	light.free()


func test_the_sun_global_follows_the_level_sun_when_it_changes() -> void:
	var manager := LevelEnvironmentManager.new()
	var game_map := FakeGameMap.new()
	manager.setup(game_map)
	var root := Node3D.new()
	var level := LevelData.new()
	level.visual_settings.sun.mode = "on"
	level.visual_settings.sun.azimuth_degrees = 0.0
	level.visual_settings.sun.elevation_degrees = 45.0
	manager.apply_level_environment(level, root)
	var at_load := FoliageLight.last_sun
	assert_eq(at_load, FoliageLight.sun_value(manager.get_sun_light()), "published at map load")
	assert_gt(at_load.y, 0.6, "45 degrees up")

	var dusk := level.visual_settings.sun.duplicate() as SunSettings
	dusk.azimuth_degrees = 90.0
	dusk.elevation_degrees = 10.0
	manager.apply_sun_settings(dusk)
	var later := FoliageLight.last_sun
	assert_ne(later, at_load, "the Sun pane's change reaches the global")
	assert_almost_eq(later.y, sin(deg_to_rad(10.0)), 0.001)

	dusk.mode = "off"
	manager.apply_sun_settings(dusk)
	assert_eq(FoliageLight.last_sun, FoliageLight.NO_SUN, "sun off, no map light: no sun")
	root.free()
	game_map.free()
