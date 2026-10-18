extends GutTest

## The game's one glow (EnvironmentGlow, card fire-prod-c5b): every preset gets the round 6
## blend, threshold, scale and levels; a preset at its own Glow value glows at INTENSITY (round 6
## parity by day, at sunset and at night); the wash keeps bloom x intensity; Mobile gains x2; a
## level's Glow, strength and bloom overrides still land.

const PARITY := {
	"": [0.5, 0.03],
	"outdoor_sunset": [0.5, 0.1],
	"outdoor_night": [0.5, 0.03],
}


func _gain() -> float:
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	return EnvironmentGlow.MOBILE_GAIN if mobile else 1.0


func _assert_tuning(env: Environment, label: String) -> void:
	assert_eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_ADDITIVE, label + " additive")
	assert_almost_eq(env.glow_hdr_threshold, 1.05, 0.001, label + " threshold")
	assert_almost_eq(env.glow_hdr_scale, 1.5, 0.001, label + " hdr scale")
	for k in EnvironmentGlow.LEVELS.size():
		assert_almost_eq(env.get_glow_level(k), EnvironmentGlow.LEVELS[k], 0.001, label + " level")


func test_every_preset_gets_the_one_tuning_at_its_own_glow() -> void:
	var names: Array = [""]
	names.append_array(EnvironmentPresets.PRESETS.keys())
	for preset_name: String in names:
		var config := EnvironmentPresets.get_environment_config(preset_name)
		var env := EnvironmentPresets.create_environment(preset_name)
		_assert_tuning(env, preset_name)
		assert_eq(env.glow_enabled, bool(config["glow_enabled"]), preset_name + " enabled")
		assert_almost_eq(env.glow_intensity, 0.5 * _gain(), 0.001, preset_name + " intensity")
		assert_almost_eq(
			env.glow_strength, float(config["glow_strength"]), 0.001, preset_name + " strength"
		)
		var wash := float(config["glow_bloom"]) * float(config["glow_intensity"])
		assert_almost_eq(env.glow_bloom * env.glow_intensity, wash, 0.0001, preset_name + " wash")


func test_round_6_parity_on_the_presets_the_fire_was_judged_under() -> void:
	for preset_name: String in PARITY:
		var config := EnvironmentPresets.get_environment_config(preset_name)
		var reference := EnvironmentPresets.glow_reference(preset_name)
		var values := EnvironmentGlow.settings(config, reference, "forward_plus")
		assert_almost_eq(values["glow_intensity"], PARITY[preset_name][0], 0.0001, preset_name)
		assert_almost_eq(values["glow_bloom"], PARITY[preset_name][1], 0.0001, preset_name)


func test_mobile_doubles_the_intensity_and_keeps_the_wash() -> void:
	var config := EnvironmentPresets.get_environment_config("outdoor_sunset")
	var forward := EnvironmentGlow.settings(config, 0.5, "forward_plus")
	var mobile := EnvironmentGlow.settings(config, 0.5, "mobile")
	assert_almost_eq(mobile["glow_intensity"], 2.0 * forward["glow_intensity"], 0.0001)
	assert_almost_eq(
		mobile["glow_bloom"] * mobile["glow_intensity"],
		forward["glow_bloom"] * forward["glow_intensity"],
		0.0001
	)
	var compat := EnvironmentGlow.settings(config, 0.5, "gl_compatibility")
	assert_almost_eq(compat["glow_intensity"], forward["glow_intensity"], 0.0001)


func test_the_glow_slider_scales_the_whole_glow_from_the_preset() -> void:
	var world_env: WorldEnvironment = autofree(WorldEnvironment.new())
	# The default preset's own Glow is 0.3: twice that is twice the glow, wash and all.
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 0.6})
	var env := world_env.environment
	_assert_tuning(env, "override")
	assert_almost_eq(env.glow_intensity, 1.0 * _gain(), 0.001)
	assert_almost_eq(env.glow_bloom * env.glow_intensity, 0.05 * 0.6, 0.0001)
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 0.0})
	assert_almost_eq(env.glow_intensity, 0.0, 0.0001, "slider at 0: no glow")
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 2.0})
	assert_almost_eq(env.glow_intensity, 0.5 * _gain() * 2.0 / 0.3, 0.001, "top of the slider")
	assert_true(env.glow_bloom < 1.0, "the slider never pushes the bloom share past 1")


func test_level_overrides_of_the_other_glow_keys_still_land() -> void:
	var world_env: WorldEnvironment = autofree(WorldEnvironment.new())
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_enabled": false})
	assert_false(world_env.environment.glow_enabled)
	EnvironmentPresets.apply_to_world_environment(
		world_env, "outdoor_night", {"glow_strength": 1.7, "glow_bloom": 0.2}
	)
	var env := world_env.environment
	assert_almost_eq(env.glow_strength, 1.7, 0.001)
	assert_almost_eq(env.glow_bloom * env.glow_intensity, 0.2 * 0.3, 0.0001)


func test_a_preset_glow_of_zero_reads_against_the_default() -> void:
	var values := EnvironmentGlow.settings({"glow_intensity": 0.3, "glow_bloom": 0.05}, 0.0, "x")
	assert_almost_eq(values["glow_intensity"], 0.5, 0.0001)


func test_strong_wash_presets_were_scaled_by_the_level_sums() -> void:
	# Hell and ethereal's wash went milky under the wider, additive levels (old sum 1.3, new
	# 3.1): their bloom was scaled by 1.3 / 3.1 so the wash stays as soft as before.
	assert_almost_eq(EnvironmentPresets.PRESETS["hell"]["glow_bloom"], 0.065, 0.0001)
	assert_almost_eq(EnvironmentPresets.PRESETS["ethereal"]["glow_bloom"], 0.085, 0.0001)
