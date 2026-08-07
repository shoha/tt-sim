extends GutTest

## Unit tests for LevelEnvironmentManager's wind-sway material cache
## (store_wind_materials / apply_foliage_overrides) -- the live-tuning half of
## foliage sway overrides. Load-time baking is covered by
## test_wind_foliage.gd's process_scatter_instances tests; this covers re-tuning
## materials that already exist in a loaded scene, without a map reload --
## mirrors store_original_light_energies / apply_light_intensity_scale's own
## cache-once-then-reapply pattern.


func _make_tagged_material(category: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WindFoliage.get_shader()
	material.set_meta("wind_category", category)
	# Seed initial values from the category's base preset, mirroring what
	# WindFoliage._build_shader_material actually does at construction time.
	# Without this, get_shader_parameter() returns null for an unset uniform
	# (Godot does not surface the shader's own declared default through that
	# API), which would make the "stale material is untouched" assertion below
	# meaningless.
	material.set_shader_parameter("sway_speed", WindFoliage.PRESETS[category]["sway_speed"])
	material.set_shader_parameter("sway_amplitude", WindFoliage.PRESETS[category]["sway_amplitude"])
	return material


func _make_multimesh_instance(category: String) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.surface_set_material(0, _make_tagged_material(category))
	var multimesh := MultiMesh.new()
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


func test_apply_foliage_overrides_updates_a_stored_materials_shader_params() -> void:
	var root := Node3D.new()
	var mm := _make_multimesh_instance("grass")
	root.add_child(mm)
	var manager := LevelEnvironmentManager.new()
	manager.store_wind_materials(root)

	manager.apply_foliage_overrides({"grass_sway_speed": 9.0})

	var material := mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(material.get_shader_parameter("sway_speed"), 9.0)

	root.free()


func test_apply_foliage_overrides_only_touches_the_matching_category() -> void:
	var root := Node3D.new()
	var tree_mm := _make_multimesh_instance("tree")
	var grass_mm := _make_multimesh_instance("grass")
	root.add_child(tree_mm)
	root.add_child(grass_mm)
	var manager := LevelEnvironmentManager.new()
	manager.store_wind_materials(root)

	manager.apply_foliage_overrides({"grass_sway_speed": 9.0})

	var tree_material := tree_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var grass_material := grass_mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(
		tree_material.get_shader_parameter("sway_speed"), WindFoliage.PRESETS["tree"]["sway_speed"]
	)
	assert_eq(grass_material.get_shader_parameter("sway_speed"), 9.0)

	root.free()


func test_apply_foliage_overrides_with_an_empty_dict_restores_preset_defaults() -> void:
	var root := Node3D.new()
	var mm := _make_multimesh_instance("grass")
	root.add_child(mm)
	var manager := LevelEnvironmentManager.new()
	manager.store_wind_materials(root)
	manager.apply_foliage_overrides({"grass_sway_speed": 9.0})

	manager.apply_foliage_overrides({})

	var material := mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(
		material.get_shader_parameter("sway_speed"), WindFoliage.PRESETS["grass"]["sway_speed"]
	)
	root.free()


func test_store_wind_materials_ignores_untagged_materials() -> void:
	var root := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var multimesh := MultiMesh.new()
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	root.add_child(instance)
	var manager := LevelEnvironmentManager.new()

	manager.store_wind_materials(root)
	manager.apply_foliage_overrides({"grass_sway_speed": 9.0})  # Must not error.

	var material := instance.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(material)  # Untagged material left completely alone.

	root.free()


func test_clear_empties_the_cache_so_a_stale_material_is_no_longer_touched() -> void:
	var root := Node3D.new()
	var mm := _make_multimesh_instance("grass")
	root.add_child(mm)
	var manager := LevelEnvironmentManager.new()
	manager.store_wind_materials(root)
	manager.clear()

	manager.apply_foliage_overrides({"grass_sway_speed": 9.0})

	var material := mm.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(
		material.get_shader_parameter("sway_speed"), WindFoliage.PRESETS["grass"]["sway_speed"]
	)

	root.free()
