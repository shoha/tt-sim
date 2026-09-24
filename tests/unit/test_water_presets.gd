extends GutTest

## WaterPresets: three preset groups (LOOKS, PALETTES, MOTIONS) that partition
## WaterSettings.KEYS, plus the legacy two-name API the loader and network path
## still use. Values are pinned so a change is a deliberate, visible diff.


func test_key_groups_partition_water_settings_keys() -> void:
	var all_keys: Array[String] = []
	all_keys.append_array(WaterPresets.LOOK_KEYS)
	all_keys.append_array(WaterPresets.PALETTE_KEYS)
	all_keys.append_array(WaterPresets.MOTION_KEYS)
	all_keys.sort()
	var expected := WaterSettings.KEYS.duplicate()
	expected.sort()
	assert_eq(all_keys, expected, "no overlap, nothing missing")


func test_every_preset_defines_exactly_its_group_keys() -> void:
	var groups := {
		"LOOKS": [WaterPresets.LOOKS, WaterPresets.LOOK_KEYS],
		"PALETTES": [WaterPresets.PALETTES, WaterPresets.PALETTE_KEYS],
		"MOTIONS": [WaterPresets.MOTIONS, WaterPresets.MOTION_KEYS],
	}
	for group_name in groups:
		var presets: Dictionary = groups[group_name][0]
		var expected: Array = groups[group_name][1].duplicate()
		expected.sort()
		for preset_name in presets:
			var keys: Array = presets[preset_name].keys()
			keys.sort()
			assert_eq(keys, expected, "%s/%s" % [group_name, preset_name])


func test_name_lists_are_in_table_order() -> void:
	assert_eq(WaterPresets.get_look_names(), ["stylized", "realistic"])
	assert_eq(
		WaterPresets.get_palette_names(), ["lagoon", "lake", "river", "swamp", "ocean", "glacial"]
	)
	assert_eq(WaterPresets.get_motion_names(), ["still", "gentle", "lively", "rough"])
	assert_eq(WaterPresets.get_preset_names(), ["stylized", "realistic"])


func test_legacy_stylized_preset_equals_water_settings_defaults() -> void:
	var from_preset := WaterSettings.from_dict(WaterPresets.get_preset("stylized"))
	assert_eq(from_preset.to_dict(), WaterSettings.default().to_dict())


func test_legacy_realistic_preset_is_realistic_lake_gentle() -> void:
	var preset := WaterPresets.get_preset("realistic")
	assert_eq(preset["water_color"], Color(0.02, 0.12, 0.22, 0.9))
	assert_eq(preset["shore_color"], Color(0.20, 0.50, 0.55, 0.7))
	assert_almost_eq(preset["depth_absorption"], 2.2, 0.001)
	assert_almost_eq(preset["ripple_scale"], 1.6, 0.001)
	assert_almost_eq(preset["ripple_strength"], 0.5, 0.001)
	assert_almost_eq(preset["wave_speed"], 0.6, 0.001)
	assert_almost_eq(preset["foam_strength"], 1.0, 0.001)
	assert_almost_eq(preset["roughness_value"], 0.06, 0.001)
	assert_almost_eq(preset["specular_value"], 0.9, 0.001)
	assert_almost_eq(preset["sky_blend_strength"], 0.35, 0.001)
	assert_almost_eq(preset["caustic_strength"], 0.5, 0.001)
	assert_almost_eq(preset["caustic_scale"], 1.8, 0.001)
	assert_almost_eq(preset["shore_depth_range"], 0.5, 0.001)
	assert_almost_eq(preset["shimmer_strength"], 0.15, 0.001)
	assert_almost_eq(preset["fresnel_power"], 3.0, 0.001)
	assert_almost_eq(preset["fresnel_strength"], 0.7, 0.001)


func test_unknown_preset_falls_back_to_stylized() -> void:
	assert_eq(WaterPresets.get_preset("not_a_real_preset"), WaterPresets.get_preset("stylized"))
	assert_eq(WaterPresets.get_preset("custom"), WaterPresets.get_preset("stylized"))


func test_stylized_look_values() -> void:
	var look: Dictionary = WaterPresets.LOOKS["stylized"]
	assert_almost_eq(look["roughness_value"], 0.15, 0.001)
	assert_almost_eq(look["specular_value"], 0.6, 0.001)
	assert_almost_eq(look["sky_blend_strength"], 0.15, 0.001)
	assert_almost_eq(look["caustic_strength"], 1.0, 0.001)
	assert_almost_eq(look["caustic_scale"], 1.3, 0.001)
	assert_almost_eq(look["refraction_strength"], 0.03, 0.001)
	assert_almost_eq(look["foam_edge_sensitivity"], 1.5, 0.001)
	assert_almost_eq(look["disturbance_ripple_strength"], 0.5, 0.001)
	assert_almost_eq(look["disturbance_ripple_radius"], 1.2, 0.001)
	assert_almost_eq(look["shore_depth_range"], 0.4, 0.001)
	assert_almost_eq(look["shimmer_strength"], 0.3, 0.001)
	assert_almost_eq(look["fresnel_power"], 4.0, 0.001)
	assert_almost_eq(look["fresnel_strength"], 0.5, 0.001)
	assert_almost_eq(look["bob_height"], 0.02, 0.001)


## Pinned by value, not just by key: the palettes were tuned by eye on the River
## level, so a silent numeric drift would change every level's look.
func test_palette_values() -> void:
	var expected := {
		"lagoon":
		{
			"water_color": Color(0.05, 0.30, 0.38, 0.8),
			"shore_color": Color(0.35, 0.75, 0.70, 0.6),
			"foam_color": Color(0.88, 0.94, 0.96, 0.9),
			"depth_absorption": 1.4,
		},
		"lake":
		{
			"water_color": Color(0.02, 0.12, 0.22, 0.9),
			"shore_color": Color(0.20, 0.50, 0.55, 0.7),
			"foam_color": Color(0.85, 0.92, 0.95, 0.85),
			"depth_absorption": 2.2,
		},
		"river":
		{
			"water_color": Color(0.09, 0.17, 0.11, 0.9),
			"shore_color": Color(0.42, 0.50, 0.28, 0.7),
			"foam_color": Color(0.90, 0.91, 0.82, 0.85),
			"depth_absorption": 2.8,
		},
		"swamp":
		{
			"water_color": Color(0.07, 0.14, 0.03, 0.95),
			"shore_color": Color(0.28, 0.35, 0.10, 0.8),
			"foam_color": Color(0.80, 0.78, 0.55, 0.8),
			"depth_absorption": 5.0,
		},
		"ocean":
		{
			"water_color": Color(0.01, 0.05, 0.16, 0.95),
			"shore_color": Color(0.10, 0.36, 0.55, 0.75),
			"foam_color": Color(0.92, 0.95, 0.98, 0.9),
			"depth_absorption": 2.8,
		},
		"glacial":
		{
			"water_color": Color(0.08, 0.42, 0.52, 0.85),
			"shore_color": Color(0.50, 0.80, 0.88, 0.65),
			"foam_color": Color(0.90, 0.96, 1.00, 0.9),
			"depth_absorption": 1.4,
		},
	}
	assert_eq(WaterPresets.PALETTES.keys(), expected.keys(), "same palettes, same order")
	for palette_name in expected:
		assert_eq(WaterPresets.PALETTES.get(palette_name), expected[palette_name], palette_name)


func test_foam_alpha_stays_in_the_readable_band() -> void:
	for palette_name in WaterPresets.PALETTES:
		var foam: Color = WaterPresets.PALETTES[palette_name]["foam_color"]
		assert_between(foam.a, 0.8, 0.9, "%s foam alpha" % palette_name)


func test_motion_values() -> void:
	assert_eq(
		WaterPresets.MOTIONS["still"],
		{"ripple_strength": 0.15, "ripple_scale": 1.2, "wave_speed": 0.2, "foam_strength": 0.3}
	)
	assert_eq(
		WaterPresets.MOTIONS["gentle"],
		{"ripple_strength": 0.5, "ripple_scale": 1.6, "wave_speed": 0.6, "foam_strength": 1.0}
	)
	assert_eq(
		WaterPresets.MOTIONS["lively"],
		{"ripple_strength": 0.65, "ripple_scale": 2.0, "wave_speed": 0.9, "foam_strength": 1.0}
	)
	assert_eq(
		WaterPresets.MOTIONS["rough"],
		{"ripple_strength": 0.9, "ripple_scale": 2.6, "wave_speed": 1.4, "foam_strength": 1.5}
	)
