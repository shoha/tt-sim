extends GutTest

## The game's one glow (EnvironmentGlow, cards fire-prod-c5b and c5c): every preset gets the
## round 6 blend, threshold, scale and levels; a preset at its own Glow value glows at INTENSITY
## (round 6 parity by day, at sunset and at night); the wash keeps bloom x intensity times the
## preset's glow_bloom_scale and grows with the square root of the Glow slider; a strength keeps
## its old relative effect; Mobile gains x2; a level's Glow, strength and bloom overrides land.

## Preset -> [intensity, bloom share, strength] at its own Glow value on Forward+.
const PARITY := {
	"": [0.5, 0.03, 1.0],
	"outdoor_sunset": [0.5, 0.1, 1.1],
	"outdoor_night": [0.5, 0.03, 1.0],
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
		var strength := EnvironmentGlow.strength(float(config["glow_strength"]))
		assert_almost_eq(env.glow_strength, strength, 0.001, preset_name + " strength")
		var wash := float(config["glow_bloom"]) * float(config["glow_intensity"])
		wash *= float(config.get("glow_bloom_scale", 1.0))
		assert_almost_eq(env.glow_bloom * env.glow_intensity, wash, 0.0001, preset_name + " wash")


func test_round_6_parity_on_the_presets_the_fire_was_judged_under() -> void:
	for preset_name: String in PARITY:
		var config := EnvironmentPresets.get_environment_config(preset_name)
		var reference := EnvironmentPresets.glow_reference(preset_name)
		var values := EnvironmentGlow.settings(config, reference, "forward_plus")
		var expected: Array = PARITY[preset_name]
		assert_almost_eq(values["glow_intensity"], expected[0], 0.0001, preset_name)
		assert_almost_eq(values["glow_bloom"], expected[1], 0.0001, preset_name)
		assert_almost_eq(values["glow_strength"], expected[2], 0.005, preset_name + " strength")
	# The default and night presets' strength of 1 passes through exactly.
	assert_eq(EnvironmentGlow.strength(1.0), 1.0)


func test_strength_keeps_its_old_relative_effect() -> void:
	assert_eq(EnvironmentGlow.strength(0.0), 0.0, "no strength")
	assert_almost_eq(EnvironmentGlow.strength(1.1), 1.054, 0.002)
	assert_almost_eq(EnvironmentGlow.strength(1.2), 1.106, 0.002)
	assert_almost_eq(EnvironmentGlow.strength(1.3), 1.157, 0.002)
	# The top of the Color pane's slider: 6.2 times the glow of a strength of 1 over Godot's own
	# levels, so not the 27 times a raw 2 makes over the wide ones.
	assert_almost_eq(EnvironmentGlow.strength(2.0), 1.48, 0.01)
	assert_true(EnvironmentGlow.strength(0.5) < 1.0, "below 1 stays below 1")
	assert_true(EnvironmentGlow.strength(0.8) < EnvironmentGlow.strength(0.9), "monotonic")


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


func test_the_glow_slider_scales_the_halo_and_the_wash_by_its_square_root() -> void:
	var world_env: WorldEnvironment = autofree(WorldEnvironment.new())
	# The default preset's own Glow is 0.3: twice that is twice the halo and 1.41 times the wash.
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 0.6})
	var env := world_env.environment
	_assert_tuning(env, "override")
	assert_almost_eq(env.glow_intensity, 1.0 * _gain(), 0.001)
	assert_almost_eq(env.glow_bloom * env.glow_intensity, 0.05 * 0.3 * sqrt(2.0), 0.0001)
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 0.0})
	assert_almost_eq(env.glow_intensity, 0.0, 0.0001, "slider at 0: no glow")
	assert_true(env.glow_bloom <= 1.0, "the bloom share stays in range at 0")
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_intensity": 2.0})
	var share := 2.0 / 0.3
	assert_almost_eq(env.glow_intensity, 0.5 * _gain() * share, 0.001, "top of the slider")
	assert_almost_eq(env.glow_bloom * env.glow_intensity, 0.05 * 0.3 * sqrt(share), 0.0001)


func test_level_overrides_of_the_other_glow_keys_still_land() -> void:
	var world_env: WorldEnvironment = autofree(WorldEnvironment.new())
	EnvironmentPresets.apply_to_world_environment(world_env, "", {"glow_enabled": false})
	assert_false(world_env.environment.glow_enabled)
	EnvironmentPresets.apply_to_world_environment(
		world_env, "outdoor_night", {"glow_strength": 1.7, "glow_bloom": 0.2}
	)
	var env := world_env.environment
	assert_almost_eq(env.glow_strength, EnvironmentGlow.strength(1.7), 0.001)
	assert_almost_eq(env.glow_bloom * env.glow_intensity, 0.2 * 0.3, 0.0001)


func test_a_preset_glow_of_zero_reads_against_the_default() -> void:
	var values := EnvironmentGlow.settings({"glow_intensity": 0.3, "glow_bloom": 0.05}, 0.0, "x")
	assert_almost_eq(values["glow_intensity"], 0.5, 0.0001)


func test_strong_wash_presets_keep_their_bloom_and_scale_the_wash() -> void:
	# Hell and ethereal keep the bloom they always had; their scale matches the old glow's wash
	# on a map without fire (card fire-prod-c5c): bloom shares 0.0684 and 0.0868 at 0.5.
	for row: Array in [["hell", 0.15, 0.38, 0.0684], ["ethereal", 0.2, 0.31, 0.0868]]:
		var preset: Dictionary = EnvironmentPresets.PRESETS[row[0]]
		assert_almost_eq(float(preset["glow_bloom"]), row[1], 0.0001, row[0])
		assert_almost_eq(float(preset["glow_bloom_scale"]), row[2], 0.0001, row[0])
		var config := EnvironmentPresets.get_environment_config(row[0])
		var values := EnvironmentGlow.settings(config, float(preset["glow_intensity"]), "x")
		assert_almost_eq(values["glow_bloom"], row[3], 0.0001, row[0] + " share")
