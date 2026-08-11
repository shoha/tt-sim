extends GutTest

## Unit tests for LevelEnvironmentManager.apply_water_quality_ssr_override() --
## the one Water Quality knob that isn't a shader uniform (Environment.ssr_enabled
## lives on the live WorldEnvironment). See
## docs/superpowers/specs/2026-08-11-water-shader-quality-design.md.


func test_enables_ssr_when_realistic_style_and_quality_enabled() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)

	manager.apply_water_quality_ssr_override("realistic", true)

	assert_true(manager.get_world_environment().environment.ssr_enabled)
	root.free()


func test_leaves_ssr_off_when_style_is_stylized() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)

	manager.apply_water_quality_ssr_override("stylized", true)

	assert_false(manager.get_world_environment().environment.ssr_enabled)
	root.free()


func test_leaves_ssr_off_when_quality_not_high() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)

	manager.apply_water_quality_ssr_override("realistic", false)

	assert_false(manager.get_world_environment().environment.ssr_enabled)
	root.free()


func test_does_not_disable_a_preset_that_already_enabled_ssr() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)
	manager.get_world_environment().environment.ssr_enabled = true

	manager.apply_water_quality_ssr_override("stylized", false)

	assert_true(manager.get_world_environment().environment.ssr_enabled)
	root.free()
