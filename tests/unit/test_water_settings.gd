extends GutTest

## WaterSettings: the typed per-level water tuning. to_dict() is complete and
## JSON-safe (colors as hex strings), from_dict() round-trips, tolerates sparse
## and malformed input, and accepts Color values from in-process callers.


func test_keys_cover_every_export() -> void:
	var settings := WaterSettings.default()
	for key in WaterSettings.KEYS:
		assert_true(key in settings, "%s is a property" % key)
	assert_eq(WaterSettings.KEYS.size(), 22)


func test_to_dict_is_complete_with_hex_colors() -> void:
	var data := WaterSettings.default().to_dict()
	assert_eq(data.keys().size(), WaterSettings.KEYS.size())
	for key in WaterSettings.KEYS:
		assert_true(data.has(key), key)
	assert_typeof(data["water_color"], TYPE_STRING)
	assert_eq(data["water_color"], Color(0.05, 0.30, 0.38, 0.8).to_html(true))
	assert_typeof(data["ripple_scale"], TYPE_FLOAT)
	assert_almost_eq(float(data["ripple_scale"]), 1.6, 0.0001)


func test_from_dict_round_trips() -> void:
	var settings := WaterSettings.default()
	settings.water_color = Color(0.1, 0.2, 0.3, 0.9)
	settings.caustic_strength = 1.75
	var restored := WaterSettings.from_dict(settings.to_dict())
	assert_true(WaterSettings.colors_match(restored.water_color, Color(0.1, 0.2, 0.3, 0.9)))
	assert_almost_eq(restored.caustic_strength, 1.75, 0.0001)
	assert_eq(restored.to_dict(), settings.to_dict())


func test_from_dict_accepts_color_values() -> void:
	var restored := WaterSettings.from_dict({"shore_color": Color.RED})
	assert_eq(restored.shore_color, Color.RED)


func test_from_dict_keeps_defaults_for_missing_and_ignores_unknown_keys() -> void:
	var restored := WaterSettings.from_dict({"wave_speed": 2.0, "not_a_key": 1.0})
	assert_almost_eq(restored.wave_speed, 2.0, 0.0001)
	assert_almost_eq(restored.ripple_scale, WaterSettings.default().ripple_scale, 0.0001)
	assert_false("not_a_key" in restored)


func test_from_dict_non_dictionary_yields_defaults() -> void:
	assert_eq(WaterSettings.from_dict(null).to_dict(), WaterSettings.default().to_dict())
	assert_eq(WaterSettings.from_dict("junk").to_dict(), WaterSettings.default().to_dict())


func test_from_dict_bad_color_string_keeps_default() -> void:
	var restored := WaterSettings.from_dict({"foam_color": "not a color"})
	assert_eq(restored.foam_color, WaterSettings.default().foam_color)


func test_copy_settings_is_independent() -> void:
	var settings := WaterSettings.default()
	var copy := settings.copy_settings()
	copy.wave_speed = 3.0
	copy.water_color = Color.BLUE
	assert_almost_eq(settings.wave_speed, WaterSettings.default().wave_speed, 0.0001)
	assert_ne(settings.water_color, Color.BLUE)


func test_colors_match_tolerates_hex_quantization_but_not_real_differences() -> void:
	var original := Color(0.1, 0.2, 0.3, 0.9)
	var quantized := Color.html(original.to_html(true))
	assert_false(original.is_equal_approx(quantized), "sanity: hex round trip is lossy")
	assert_true(WaterSettings.colors_match(original, quantized))
	assert_false(WaterSettings.colors_match(original, Color(0.1, 0.2, 0.31, 0.9)))


func test_from_style_realistic_is_realistic_lake_gentle() -> void:
	var settings := WaterSettings.from_style("realistic")
	assert_eq(settings.matching_look(), "realistic")
	assert_eq(settings.matching_palette(), "lake")
	assert_eq(settings.matching_motion(), "gentle")


func test_from_style_unknown_is_default() -> void:
	assert_eq(WaterSettings.from_style("nope").to_dict(), WaterSettings.default().to_dict())
	assert_eq(WaterSettings.from_style("custom").to_dict(), WaterSettings.default().to_dict())


func test_defaults_match_stylized_lagoon_gentle() -> void:
	var settings := WaterSettings.default()
	assert_eq(settings.matching_look(), "stylized")
	assert_eq(settings.matching_palette(), "lagoon")
	assert_eq(settings.matching_motion(), "gentle")


func test_one_edit_flips_only_its_group_to_custom() -> void:
	var settings := WaterSettings.default()
	settings.wave_speed = 2.5
	assert_eq(settings.matching_motion(), WaterPresets.CUSTOM_KEY)
	assert_eq(settings.matching_look(), "stylized")
	assert_eq(settings.matching_palette(), "lagoon")
	settings.water_color = Color.RED
	assert_eq(settings.matching_palette(), WaterPresets.CUSTOM_KEY)
	assert_eq(settings.matching_look(), "stylized")


func test_apply_group_sets_only_those_keys() -> void:
	var settings := WaterSettings.default()
	settings.apply_group(WaterPresets.PALETTES["swamp"])
	assert_eq(settings.matching_palette(), "swamp")
	assert_eq(settings.matching_look(), "stylized")
	assert_eq(settings.matching_motion(), "gentle")
