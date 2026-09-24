extends GutTest

## Unit tests for WaterPresets.PRESETS -- mirrors test_environment_presets_defaults.gd's
## style of pinning specific values so a future change is a deliberate, visible diff.

const EXPECTED_KEYS := [
	"water_color",
	"shore_color",
	"shore_depth_range",
	"depth_absorption",
	"shimmer_strength",
	"ripple_scale",
	"ripple_strength",
	"fresnel_power",
	"fresnel_strength",
	"roughness_value",
	"specular_value",
	"sky_blend_strength",
	"caustic_scale",
	"caustic_strength",
	"disturbance_ripple_radius",
	"disturbance_ripple_strength",
	"foam_color",
	"foam_edge_sensitivity",
	"foam_strength",
]


func test_get_preset_names_returns_both_presets() -> void:
	assert_eq(WaterPresets.get_preset_names(), ["stylized", "realistic"])


## Every preset must set every tunable, so switching styles never leaves a value from
## the previous style behind on the shared material.
func test_both_presets_define_the_same_keys() -> void:
	for preset_name in WaterPresets.get_preset_names():
		var preset := WaterPresets.get_preset(preset_name)
		var keys := preset.keys()
		keys.sort()
		var expected := EXPECTED_KEYS.duplicate()
		expected.sort()
		assert_eq(keys, expected, "%s preset keys" % preset_name)


func test_stylized_preset_values() -> void:
	var preset := WaterPresets.get_preset("stylized")
	assert_eq(preset["water_color"], Color(0.05, 0.30, 0.38, 0.8))
	assert_eq(preset["shore_color"], Color(0.35, 0.75, 0.70, 0.6))
	assert_almost_eq(preset["shore_depth_range"], 0.4, 0.001)
	assert_almost_eq(preset["depth_absorption"], 1.4, 0.001)
	assert_almost_eq(preset["shimmer_strength"], 0.3, 0.001)
	assert_almost_eq(preset["ripple_scale"], 1.6, 0.001)
	assert_almost_eq(preset["ripple_strength"], 0.5, 0.001)
	assert_almost_eq(preset["fresnel_power"], 4.0, 0.001)
	assert_almost_eq(preset["fresnel_strength"], 0.5, 0.001)
	assert_almost_eq(preset["roughness_value"], 0.15, 0.001)
	assert_almost_eq(preset["specular_value"], 0.6, 0.001)
	assert_almost_eq(preset["sky_blend_strength"], 0.15, 0.001)
	assert_almost_eq(preset["caustic_scale"], 1.3, 0.001)
	assert_almost_eq(preset["caustic_strength"], 1.0, 0.001)
	assert_almost_eq(preset["disturbance_ripple_radius"], 1.2, 0.001)
	assert_almost_eq(preset["disturbance_ripple_strength"], 0.5, 0.001)
	assert_eq(preset["foam_color"], Color(0.88, 0.94, 0.96, 0.9))
	assert_almost_eq(preset["foam_edge_sensitivity"], 1.5, 0.001)
	assert_almost_eq(preset["foam_strength"], 1.0, 0.001)


func test_realistic_preset_values() -> void:
	var preset := WaterPresets.get_preset("realistic")
	assert_eq(preset["water_color"], Color(0.02, 0.12, 0.22, 0.9))
	assert_eq(preset["shore_color"], Color(0.20, 0.50, 0.55, 0.7))
	assert_almost_eq(preset["shore_depth_range"], 0.5, 0.001)
	assert_almost_eq(preset["depth_absorption"], 2.2, 0.001)
	assert_almost_eq(preset["shimmer_strength"], 0.15, 0.001)
	assert_almost_eq(preset["ripple_scale"], 2.0, 0.001)
	assert_almost_eq(preset["ripple_strength"], 0.6, 0.001)
	assert_almost_eq(preset["fresnel_power"], 3.0, 0.001)
	assert_almost_eq(preset["fresnel_strength"], 0.7, 0.001)
	assert_almost_eq(preset["roughness_value"], 0.06, 0.001)
	assert_almost_eq(preset["specular_value"], 0.9, 0.001)
	assert_almost_eq(preset["sky_blend_strength"], 0.35, 0.001)
	assert_almost_eq(preset["caustic_scale"], 1.8, 0.001)
	assert_almost_eq(preset["caustic_strength"], 0.5, 0.001)
	assert_almost_eq(preset["disturbance_ripple_radius"], 1.2, 0.001)
	assert_almost_eq(preset["disturbance_ripple_strength"], 0.5, 0.001)
	assert_eq(preset["foam_color"], Color(0.85, 0.92, 0.95, 0.85))
	assert_almost_eq(preset["foam_edge_sensitivity"], 1.5, 0.001)
	assert_almost_eq(preset["foam_strength"], 0.7, 0.001)


func test_unknown_preset_falls_back_to_stylized() -> void:
	assert_eq(WaterPresets.get_preset("not_a_real_preset"), WaterPresets.get_preset("stylized"))
