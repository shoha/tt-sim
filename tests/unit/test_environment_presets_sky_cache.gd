extends GutTest

## Tests that EnvironmentPresets reuses one Sky per preset. Before this, every
## apply_to_world_environment() call (i.e. every slider tick in the Visuals drawer)
## built a new ProceduralSkyMaterial + Sky, which re-bakes the radiance cubemap.


func test_get_sky_for_preset_returns_the_same_instance() -> void:
	var first := EnvironmentPresets.get_sky_for_preset("clear_day")
	var second := EnvironmentPresets.get_sky_for_preset("clear_day")
	assert_not_null(first)
	assert_same(first, second)


func test_get_sky_for_preset_distinguishes_presets() -> void:
	var day := EnvironmentPresets.get_sky_for_preset("clear_day")
	var night := EnvironmentPresets.get_sky_for_preset("night_sky")
	assert_false(day == night)


func test_get_sky_for_unknown_preset_returns_null() -> void:
	assert_null(EnvironmentPresets.get_sky_for_preset("no_such_sky"))


func test_reapplying_the_same_preset_keeps_the_environment_sky_object() -> void:
	var world_env := WorldEnvironment.new()
	add_child_autofree(world_env)
	var overrides := {"background_mode": Environment.BG_SKY, "sky_preset": "sunset"}

	EnvironmentPresets.apply_to_world_environment(world_env, "", overrides)
	var sky_after_first := world_env.environment.sky
	EnvironmentPresets.apply_to_world_environment(world_env, "", overrides)

	assert_not_null(sky_after_first)
	assert_same(world_env.environment.sky, sky_after_first)
	assert_same(sky_after_first, EnvironmentPresets.get_sky_for_preset("sunset"))


func test_changing_preset_swaps_the_sky() -> void:
	var world_env := WorldEnvironment.new()
	add_child_autofree(world_env)
	EnvironmentPresets.apply_to_world_environment(
		world_env, "", {"background_mode": Environment.BG_SKY, "sky_preset": "sunset"}
	)
	EnvironmentPresets.apply_to_world_environment(
		world_env, "", {"background_mode": Environment.BG_SKY, "sky_preset": "overcast"}
	)
	assert_same(world_env.environment.sky, EnvironmentPresets.get_sky_for_preset("overcast"))
