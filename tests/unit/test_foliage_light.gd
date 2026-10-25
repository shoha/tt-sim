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


func _painted_with_shade(shade: Variant) -> ShaderMaterial:
	var mesh := _leaf_mesh(
		{FoliageLight.EXTRA_KEY: FoliageLight.PAINTED, FoliageLight.SHADE_KEY: shade}
	)
	WindFoliage.apply_material(mesh, "tree")
	return mesh.surface_get_material(0) as ShaderMaterial


func test_the_shade_floor_extra_sets_the_uniform_on_a_painted_material() -> void:
	var material := _painted_with_shade([0.2, 0.15, 0.06])
	assert_eq(material.shader, FoliageLight.get_shader())
	var shade: Variant = material.get_shader_parameter(FoliageLight.SHADE_UNIFORM)
	assert_true(shade is Vector3, "the uniform is a vec3")
	assert_almost_eq(shade as Vector3, Vector3(0.2, 0.15, 0.06), Vector3.ONE * 0.0001)
	var ints := _painted_with_shade([0, 1, 0])
	assert_eq(ints.get_shader_parameter(FoliageLight.SHADE_UNIFORM), Vector3(0.0, 1.0, 0.0))


func test_no_shade_floor_extra_leaves_the_shader_default() -> void:
	var mesh := _leaf_mesh({FoliageLight.EXTRA_KEY: FoliageLight.PAINTED})
	WindFoliage.apply_material(mesh, "tree")
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_null(material.get_shader_parameter(FoliageLight.SHADE_UNIFORM), "the default stands")


func test_a_malformed_shade_floor_is_ignored() -> void:
	var bad: Array = [
		[0.1, 0.2],
		[0.1, 0.2, 0.3, 0.4],
		[],
		[NAN, 0.2, 0.3],
		[0.1, INF, 0.3],
		["0.1", 0.2, 0.3],
		[true, 0.2, 0.3],
		[null, 0.2, 0.3],
		"0.1, 0.2, 0.3",
		0.5,
		{"r": 0.1, "g": 0.2, "b": 0.3},
		null,
	]
	for value: Variant in bad:
		var material := _painted_with_shade(value)
		assert_eq(material.shader, FoliageLight.get_shader(), "still painted: %s" % str(value))
		assert_null(
			material.get_shader_parameter(FoliageLight.SHADE_UNIFORM), "ignored: %s" % str(value)
		)
	assert_engine_error(bad.size(), "one warning per malformed floor")


func test_an_out_of_range_shade_floor_is_clamped() -> void:
	var material := _painted_with_shade([-0.5, 1.5, 0.3])
	assert_almost_eq(
		material.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3,
		Vector3(0.0, 1.0, 0.3),
		Vector3.ONE * 0.0001
	)
	assert_engine_error("clamped to 0..1")


func test_the_shade_floor_on_a_plain_material_does_nothing() -> void:
	for extras: Variant in [
		{FoliageLight.SHADE_KEY: [0.2, 0.15, 0.06]},
		{FoliageLight.EXTRA_KEY: "flat", FoliageLight.SHADE_KEY: [0.2, 0.15, 0.06]},
	]:
		var mesh := _leaf_mesh(extras)
		WindFoliage.apply_material(mesh, "tree")
		var material := mesh.surface_get_material(0) as ShaderMaterial
		assert_eq(material.shader, WindFoliage.get_shader())
		assert_null(material.get_shader_parameter(FoliageLight.SHADE_UNIFORM))
		assert_null(FoliageLight.shade_floor(mesh.surface_get_material(0)))


func test_two_materials_with_different_shade_floors_keep_their_own() -> void:
	var box := BoxMesh.new()
	var mesh := ArrayMesh.new()
	var shades := [[0.2, 0.15, 0.06], [0.12, 0.28, 0.1]]
	for shade: Array in shades:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
		var source := StandardMaterial3D.new()
		source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		source.set_meta(
			"extras", {FoliageLight.EXTRA_KEY: FoliageLight.PAINTED, FoliageLight.SHADE_KEY: shade}
		)
		mesh.surface_set_material(mesh.get_surface_count() - 1, source)
	WindFoliage.apply_material(mesh, "tree")
	var first := mesh.surface_get_material(0) as ShaderMaterial
	var second := mesh.surface_get_material(1) as ShaderMaterial
	assert_ne(first, second, "one wind material per source material")
	var tolerance := Vector3.ONE * 0.0001
	var first_shade := first.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3
	var second_shade := second.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3
	assert_almost_eq(first_shade, Vector3(0.2, 0.15, 0.06), tolerance)
	assert_almost_eq(second_shade, Vector3(0.12, 0.28, 0.1), tolerance)
	# The antialiasing swap changes the shader, never the per-material floor.
	first.shader = WindFoliage.shader_for(first, false)
	assert_almost_eq(
		first.get_shader_parameter(FoliageLight.SHADE_UNIFORM) as Vector3,
		Vector3(0.2, 0.15, 0.06),
		tolerance
	)


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


func test_the_core_palette_flags_every_crown_and_no_ground_litter() -> void:
	# docs/ASSET_PIPELINE.md section 6 (tt_foliage_light "painted"): plantgen writes the extra on
	# the leaf material of every tree, bush, fern and flower crown; grass tufts, litter, logs and
	# stumps carry none. (Until 2026-10-25 this pinned treecube's installed palette.)
	var painted := PackedStringArray()
	var pines := 0
	var acacias := 0
	var willows := 0
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
				var file := String(asset_id).get_file()
				for i in mesh.get_surface_count():
					var source := mesh.surface_get_material(i) as BaseMaterial3D
					if source == null or not WindFoliage.is_leaf_cutout(source):
						continue
					var crown := file.begins_with("Tree_") or file.begins_with("Bush_")
					crown = crown or file.begins_with("Fern_") or file.begins_with("Flower_")
					crown = crown or file.begins_with("Grass_SprigClump")
					assert_eq(FoliageLight.is_painted(source), crown, "%s: painted" % file)
					if not FoliageLight.is_painted(source):
						continue
					painted.append(file)
					if file.begins_with("Tree_Pine"):
						pines += 1
					if file.begins_with("Tree_Acacia"):
						acacias += 1
					if file.begins_with("Tree_Willow"):
						willows += 1
	assert_gt(painted.size(), 100, "the broadleaf crowns are flagged: %s" % str(painted))
	assert_gte(pines, 6, "every pine's frond crown is flagged: %s" % str(painted))
	assert_gte(acacias, 3, "the savanna acacias: %s" % str(painted))
	assert_gte(willows, 3, "the wetland's three willows: %s" % str(painted))


func test_the_core_palette_carries_the_tone_shade_floors() -> void:
	# plantgen writes each leaf material's tt_foliage_shade (PlantMaterials.foliage_shade_floor,
	# translated in linear light from the shade colour); the game profile tones one stem
	# differently per biome, so the floors differ between biomes. Recorded 2026-10-25 from the
	# shipped core (three decimals).
	var expected := {
		"temperate_forest_summer_s1/Tree_Oak_v0": Vector3(0.022, 0.049, 0.677),
		"temperate_forest_summer_s1/Tree_Birch_v0": Vector3(0.08, 0.141, 0.264),
		"savanna_summer_s1/Tree_Acacia_v0": Vector3(0.122, 0.11, 0.287),
		"wetland_riparian_summer_s1/Tree_Willow_v0": Vector3(0.243, 0.385, 0.689),
		"temperate_forest_summer_s1/Tree_Spruce_v0_temperate_forest":
		Vector3(0.166, 0.257, 0.343),
		"temperate_forest_summer_s1/Tree_Pine_v0_temperate_forest": Vector3(0.098, 0.273, 0.358),
		"temperate_forest_summer_s1/Tree_Sapling_v0_temperate_forest":
		Vector3(0.022, 0.049, 0.677),
		"savanna_summer_s1/Tree_Sapling_v0_savanna": Vector3(0.062, 0.057, 0.135),
		"temperate_forest_summer_s1/Bush_Bush_v0_temperate_forest": null,
	}
	for asset_id: String in expected:
		var mesh := PaletteLibrary.resolve(asset_id).get("mesh") as Mesh
		assert_not_null(mesh, asset_id)
		if mesh == null:
			continue
		WindFoliage.apply_material(mesh, "tree")
		var found: Variant = null
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as ShaderMaterial
			if material != null and material.has_meta(FoliageLight.META_PAINTED):
				found = material.get_shader_parameter(FoliageLight.SHADE_UNIFORM)
		if expected[asset_id] == null:
			assert_not_null(found, "%s carries a floor" % asset_id)
		else:
			assert_almost_eq(found as Vector3, expected[asset_id] as Vector3, Vector3.ONE * 2e-3)


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
