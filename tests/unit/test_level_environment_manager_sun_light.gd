extends GutTest

## Unit tests for LevelEnvironmentManager's default sun light lifecycle
## (apply_level_environment's sun-light setup, apply_sun_settings, clear()) --
## see docs/superpowers/specs/2026-08-08-lighting-rendering-defaults-design.md
## for the auto/on/off mode semantics.


func _make_manager_with_loaded_level() -> LevelEnvironmentManager:
	var manager := LevelEnvironmentManager.new()
	var root: Node3D = autofree(Node3D.new())
	var level_data := LevelData.new()
	manager.apply_level_environment(level_data, root)
	return manager


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
	level_data.visual_settings.sun.mode = "on"

	manager.apply_level_environment(level_data, root)

	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_true(sun.visible)
	root.free()


func test_apply_level_environment_forces_sun_light_off_even_without_map_lights_in_off_mode(
) -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	level_data.visual_settings.sun.mode = "off"

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


func test_apply_sun_settings_updates_the_existing_light_without_recreating_it() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	manager.apply_level_environment(level_data, root)
	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D

	var settings := DefaultSun.settings_for_time(0.0)
	settings.mode = "on"
	manager.apply_sun_settings(settings)

	var same_sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D
	assert_eq(sun, same_sun)
	assert_almost_eq(same_sun.light_energy, float(DefaultSun.KEYFRAMES[0.0]["energy"]), 0.001)
	root.free()


func test_apply_sun_settings_writes_the_shadow_properties_to_the_light() -> void:
	var manager := _make_manager_with_loaded_level()
	var settings := SunSettings.default()
	settings.mode = "on"
	settings.shadows_enabled = true
	settings.softness = 3.0
	settings.shadow_darkness = 0.35

	manager.apply_sun_settings(settings)

	var light := manager.get_sun_light()
	assert_eq(light.shadow_enabled, true)
	assert_almost_eq(light.light_angular_distance, 3.0, 0.001)
	assert_almost_eq(light.shadow_opacity, 0.35, 0.001)


func test_apply_sun_settings_can_disable_shadows() -> void:
	var manager := _make_manager_with_loaded_level()
	var settings := SunSettings.default()
	settings.mode = "on"
	settings.shadows_enabled = false

	manager.apply_sun_settings(settings)

	assert_eq(manager.get_sun_light().shadow_enabled, false)


func test_apply_sun_settings_reapplies_on_a_second_call() -> void:
	# The shadow properties used to be written once at light-creation time. They
	# now live in the applier, so a live edit must take effect immediately.
	var manager := _make_manager_with_loaded_level()
	var first := SunSettings.default()
	first.mode = "on"
	first.softness = 1.0
	manager.apply_sun_settings(first)

	var second := SunSettings.default()
	second.mode = "on"
	second.softness = 4.0
	manager.apply_sun_settings(second)

	assert_almost_eq(manager.get_sun_light().light_angular_distance, 4.0, 0.001)


func test_apply_sun_settings_honours_mode_off() -> void:
	var manager := _make_manager_with_loaded_level()
	var settings := SunSettings.default()
	settings.mode = "off"

	manager.apply_sun_settings(settings)

	assert_eq(manager.get_sun_light().visible, false)


func test_apply_sun_settings_aims_the_light_from_azimuth_and_elevation() -> void:
	var manager := _make_manager_with_loaded_level()
	var settings := SunSettings.default()
	settings.mode = "on"
	settings.azimuth_degrees = 20.0
	settings.elevation_degrees = 60.0

	manager.apply_sun_settings(settings)

	var light := manager.get_sun_light()
	assert_almost_eq(light.rotation_degrees.y, 20.0, 0.001)
	assert_almost_eq(light.rotation_degrees.x, -60.0, 0.001)


func test_clear_frees_the_sun_light() -> void:
	var manager := LevelEnvironmentManager.new()
	var root := Node3D.new()
	var level_data := LevelData.new()
	manager.apply_level_environment(level_data, root)
	var sun := root.get_node_or_null("LevelSunLight") as DirectionalLight3D

	manager.clear()

	assert_true(sun.is_queued_for_deletion())
	root.free()
