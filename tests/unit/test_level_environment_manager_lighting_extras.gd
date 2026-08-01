extends GutTest

## Unit tests for LevelEnvironmentManager.extract_and_strip_map_environment()'s
## handling of Blender-authored ambient light glTF extras (see GlbUtils
## .extract_lighting_config()) as a map-defaults source alongside embedded
## WorldEnvironment nodes.


func test_uses_lighting_extras_as_map_defaults_with_no_world_environment() -> void:
	var root := Node3D.new()
	root.set_meta(
		"tt_lighting_extras",
		{"tt_ambient_light_color": [0.1, 0.2, 0.3], "tt_ambient_light_energy": 1.5}
	)
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_eq(config.get("ambient_light_color"), Color(0.1, 0.2, 0.3))
	assert_eq(config.get("ambient_light_energy"), 1.5)

	root.free()


func test_world_environment_overrides_lighting_extras_on_conflicting_keys() -> void:
	var root := Node3D.new()
	root.set_meta("tt_lighting_extras", {"tt_ambient_light_energy": 1.5})
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_energy = 9.0
	world_env.environment = env
	root.add_child(world_env)
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_eq(config.get("ambient_light_energy"), 9.0)

	root.free()


func test_returns_empty_dict_with_no_extras_and_no_world_environment() -> void:
	var root := Node3D.new()
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_true(config.is_empty())

	root.free()
