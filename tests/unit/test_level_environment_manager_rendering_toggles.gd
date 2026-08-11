extends GutTest

## Unit tests for LevelEnvironmentManager.apply_rendering_toggles() -- the
## global SSAO/SSR/SDFGI settings' write path onto the live WorldEnvironment.
## See docs/superpowers/specs/2026-08-11-global-rendering-toggles-design.md.


func test_writes_all_three_properties_when_enabled() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)

	manager.apply_rendering_toggles(true, true, true)

	var env := manager.get_world_environment().environment
	assert_true(env.ssao_enabled)
	assert_true(env.ssr_enabled)
	assert_true(env.sdfgi_enabled)
	root.free()


func test_writes_all_three_properties_when_disabled() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)
	manager.apply_rendering_toggles(true, true, true)

	manager.apply_rendering_toggles(false, false, false)

	var env := manager.get_world_environment().environment
	assert_false(env.ssao_enabled)
	assert_false(env.ssr_enabled)
	assert_false(env.sdfgi_enabled)
	root.free()


func test_toggles_are_independent() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	manager.apply_level_environment(LevelData.new(), root)

	manager.apply_rendering_toggles(true, false, false)

	var env := manager.get_world_environment().environment
	assert_true(env.ssao_enabled)
	assert_false(env.ssr_enabled)
	assert_false(env.sdfgi_enabled)
	root.free()


func test_is_a_safe_no_op_before_any_world_environment_exists() -> void:
	var manager := LevelEnvironmentManager.new()

	manager.apply_rendering_toggles(true, true, true)  # must not error

	assert_null(manager.get_world_environment())
