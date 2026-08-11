extends GutTest

## Unit tests for WaterPresets.PRESETS -- mirrors test_environment_presets_defaults.gd's
## style of pinning specific values so a future change is a deliberate, visible diff.


func test_get_preset_names_returns_both_presets() -> void:
	assert_eq(WaterPresets.get_preset_names(), ["stylized", "realistic"])


func test_stylized_preset_values() -> void:
	var preset := WaterPresets.get_preset("stylized")
	assert_eq(preset["water_color"], Color(0.04, 0.22, 0.28, 0.75))
	assert_eq(preset["shore_color"], Color(0.35, 0.75, 0.7, 0.65))
	assert_almost_eq(preset["ripple_scale"], 4.0, 0.001)
	assert_almost_eq(preset["fresnel_power"], 4.0, 0.001)
	assert_almost_eq(preset["fresnel_strength"], 0.5, 0.001)
	assert_almost_eq(preset["roughness_value"], 0.08, 0.001)
	assert_almost_eq(preset["specular_value"], 0.6, 0.001)
	assert_almost_eq(preset["sky_blend_strength"], 0.15, 0.001)


func test_realistic_preset_values() -> void:
	var preset := WaterPresets.get_preset("realistic")
	assert_eq(preset["water_color"], Color(0.02, 0.12, 0.22, 0.85))
	assert_eq(preset["shore_color"], Color(0.25, 0.55, 0.6, 0.7))
	assert_almost_eq(preset["ripple_scale"], 7.0, 0.001)
	assert_almost_eq(preset["fresnel_power"], 3.0, 0.001)
	assert_almost_eq(preset["fresnel_strength"], 0.7, 0.001)
	assert_almost_eq(preset["roughness_value"], 0.04, 0.001)
	assert_almost_eq(preset["specular_value"], 0.9, 0.001)
	assert_almost_eq(preset["sky_blend_strength"], 0.4, 0.001)


func test_unknown_preset_falls_back_to_stylized() -> void:
	assert_eq(WaterPresets.get_preset("not_a_real_preset"), WaterPresets.get_preset("stylized"))
