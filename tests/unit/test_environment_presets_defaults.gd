extends GutTest

## Regression tests for EnvironmentPresets.PROPERTY_DEFAULTS -- the clean/simple
## baseline used by any map with no embedded WorldEnvironment (see
## docs/superpowers/specs/2026-08-08-lighting-rendering-defaults-design.md).
## Pins the specific values the design settled on so a future change to the
## defaults is a deliberate, visible diff here rather than a silent drift.


func test_glow_enabled_by_default_with_a_subtle_intensity() -> void:
	assert_true(EnvironmentPresets.PROPERTY_DEFAULTS["glow_enabled"])
	assert_almost_eq(EnvironmentPresets.PROPERTY_DEFAULTS["glow_intensity"], 0.3, 0.001)
	assert_almost_eq(EnvironmentPresets.PROPERTY_DEFAULTS["glow_bloom"], 0.05, 0.001)


func test_tonemap_stays_filmic_by_default() -> void:
	assert_eq(EnvironmentPresets.PROPERTY_DEFAULTS["tonemap_mode"], Environment.TONE_MAPPER_FILMIC)


func test_adjustment_stays_disabled_by_default() -> void:
	assert_false(EnvironmentPresets.PROPERTY_DEFAULTS["adjustment_enabled"])


func test_get_environment_config_reflects_the_new_defaults_with_no_preset_or_map_defaults() -> void:
	var config := EnvironmentPresets.get_environment_config("", {}, {})
	assert_true(config["glow_enabled"])
