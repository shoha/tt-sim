extends GutTest

## Unit tests for WeatherRenderer.rebase_fog() -- re-reads the environment's fog
## as the new base and re-adds the weather renderer's fog contribution after
## EnvironmentPresets has overwritten fog_density/fog_enabled from config. See
## LevelPlayController.apply_environment_settings() for the call site.


func _make_manager_with_environment() -> LevelEnvironmentManager:
	var manager := LevelEnvironmentManager.new()
	var root: Node3D = autofree(Node3D.new())
	manager.apply_level_environment(LevelData.new(), root)
	return manager


func test_rebase_fog_reapplies_contribution_after_environment_rewrite() -> void:
	var manager := _make_manager_with_environment()
	var env := manager.get_world_environment().environment
	env.fog_density = 0.01
	env.fog_enabled = false

	var renderer := WeatherRenderer.new()
	add_child_autofree(renderer)
	renderer._environment_manager = manager
	renderer._fog_intensity = 0.5

	renderer.rebase_fog()

	assert_true(env.fog_enabled)
	assert_almost_eq(
		env.fog_density, 0.01 + 0.5 * WeatherRenderer.FOG_DENSITY_PER_INTENSITY, 0.0001
	)
	assert_almost_eq(renderer._base_fog_density, 0.01, 0.0001)


func test_rebase_fog_with_zero_intensity_only_captures_base() -> void:
	var manager := _make_manager_with_environment()
	var env := manager.get_world_environment().environment
	env.fog_density = 0.02
	env.fog_enabled = false

	var renderer := WeatherRenderer.new()
	add_child_autofree(renderer)
	renderer._environment_manager = manager
	renderer._fog_intensity = 0.0

	renderer.rebase_fog()

	assert_almost_eq(env.fog_density, 0.02, 0.0001)
	assert_false(env.fog_enabled)
	assert_almost_eq(renderer._base_fog_density, 0.02, 0.0001)


func test_rebase_fog_without_environment_manager_is_noop() -> void:
	var renderer := WeatherRenderer.new()
	add_child_autofree(renderer)

	renderer.rebase_fog()  # must not error

	assert_false(renderer._has_base_fog)
