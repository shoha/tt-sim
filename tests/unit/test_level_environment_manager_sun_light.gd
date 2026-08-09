extends GutTest

## Unit tests for LevelEnvironmentManager's default sun light lifecycle
## (apply_level_environment's sun-light setup, apply_sun_overrides, clear()) --
## see docs/superpowers/specs/2026-08-08-lighting-rendering-defaults-design.md
## for the auto/on/off mode semantics.


func test_apply_level_environment_adds_a_visible_sun_light_when_map_has_no_lights() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()  # No lights stored -- store_original_light_energies() not called.
	var level_data := LevelData.new()

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_not_null(sun)
	assert_true(sun.visible)
	root.free()


func test_apply_level_environment_hides_the_sun_light_when_map_has_its_own_lights_in_auto_mode(
) -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	root.add_child(DirectionalLight3D.new())
	manager.store_original_light_energies(root)
	var level_data := LevelData.new()

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_not_null(sun)
	assert_false(sun.visible)
	root.free()


func test_apply_level_environment_forces_sun_light_on_even_with_map_lights_in_on_mode() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	root.add_child(DirectionalLight3D.new())
	manager.store_original_light_energies(root)
	var level_data := LevelData.new()
	level_data.sun_overrides = {"mode": "on"}

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_true(sun.visible)
	root.free()


func test_apply_level_environment_forces_sun_light_off_even_without_map_lights_in_off_mode(
) -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	level_data.sun_overrides = {"mode": "off"}

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_false(sun.visible)
	root.free()


func test_apply_level_environment_does_not_force_orthogonal_shadow_mode() -> void:
	# Regression test: explicitly forcing directional_shadow_mode to
	# SHADOW_ORTHOGONAL (the simplest, single-frustum mode) produced no
	# visible shadows at all in this project's camera setup -- confirmed by
	# a live visual A/B test, not just a code-level assumption. Leaving the
	# property untouched (engine default: cascaded SHADOW_PARALLEL_4_SPLITS)
	# is what made shadows appear. This test pins "don't touch this
	# property" so a future refactor can't silently reintroduce it.
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_ne(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
	root.free()


func test_apply_level_environment_uses_small_shadow_biases_so_small_tokens_keep_their_shadow(
) -> void:
	# Regression test: Godot's DirectionalLight3D engine defaults
	# (shadow_bias=0.1, shadow_normal_bias=2.0) are tuned for room/building-
	# scale geometry. A token is well under 1 unit tall, so the default
	# normal_bias risks detaching its shadow from the ground ("peter-
	# panning") -- these smaller values keep shadows attached to small
	# objects while still avoiding shadow acne on the terrain.
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_lt(sun.shadow_bias, 0.1)
	assert_lt(sun.shadow_normal_bias, 2.0)
	root.free()


func test_apply_sun_overrides_updates_the_existing_light_without_recreating_it() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	manager.apply_level_environment(level_data, root)
	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D

	manager.apply_sun_overrides({"mode": "on", "time_of_day": 0.0})

	var same_sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_eq(sun, same_sun)
	assert_almost_eq(same_sun.light_energy, float(DefaultSun.KEYFRAMES[0.0]["energy"]), 0.001)
	root.free()


func test_clear_frees_the_sun_light() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	manager.apply_level_environment(level_data, root)
	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D

	manager.clear()

	assert_true(sun.is_queued_for_deletion())
	root.free()
