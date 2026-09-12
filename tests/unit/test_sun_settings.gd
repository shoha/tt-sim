extends GutTest

## Unit tests for SunSettings (resources/sun_settings.gd) -- the typed sun and
## shadow configuration that replaced the untyped LevelData.sun_overrides
## dictionary in schema version 1.


func test_new_instance_has_neutral_defaults() -> void:
	var s := SunSettings.new()

	assert_eq(s.mode, "auto")
	assert_eq(s.shadows_enabled, true)
	assert_almost_eq(s.softness, 0.0, 0.0001)
	assert_almost_eq(s.shadow_darkness, 1.0, 0.0001)
	assert_almost_eq(s.time_of_day, DefaultSun.DEFAULT_TIME_OF_DAY, 0.0001)


func test_to_dict_serializes_color_as_hex_string() -> void:
	var s := SunSettings.new()
	s.color = Color(1.0, 0.5, 0.0)

	var data := s.to_dict()

	assert_true(data["color"] is String, "color must serialize as a JSON-safe string")
	assert_true((data["color"] as String).begins_with("#"))


func test_from_dict_round_trips_every_field() -> void:
	var original := SunSettings.new()
	original.mode = "on"
	original.azimuth_degrees = 210.0
	original.elevation_degrees = 12.5
	original.color = Color(0.2, 0.4, 0.8)
	original.energy = 2.25
	original.shadows_enabled = false
	original.softness = 3.5
	original.shadow_darkness = 0.6
	original.time_of_day = 19.0

	var restored := SunSettings.from_dict(original.to_dict())

	assert_eq(restored.mode, "on")
	assert_almost_eq(restored.azimuth_degrees, 210.0, 0.0001)
	assert_almost_eq(restored.elevation_degrees, 12.5, 0.0001)
	# Hex serialization quantizes to 8 bits per channel, which is the existing
	# on-disk convention (see EnvironmentPresets.overrides_to_json).
	assert_almost_eq(restored.color.r, 0.2, 0.005)
	assert_almost_eq(restored.color.g, 0.4, 0.005)
	assert_almost_eq(restored.color.b, 0.8, 0.005)
	assert_almost_eq(restored.energy, 2.25, 0.0001)
	assert_eq(restored.shadows_enabled, false)
	assert_almost_eq(restored.softness, 3.5, 0.0001)
	assert_almost_eq(restored.shadow_darkness, 0.6, 0.0001)
	assert_almost_eq(restored.time_of_day, 19.0, 0.0001)


func test_from_dict_falls_back_to_defaults_for_missing_keys() -> void:
	var restored := SunSettings.from_dict({"mode": "off"})

	assert_eq(restored.mode, "off")
	assert_eq(restored.shadows_enabled, true)
	assert_almost_eq(restored.shadow_darkness, 1.0, 0.0001)


func test_from_dict_accepts_a_raw_color_object() -> void:
	# Network payloads pass through without a JSON encode/decode round-trip, so
	# a live Color can arrive where a hex string would be on disk.
	var restored := SunSettings.from_dict({"color": Color(0.0, 1.0, 0.0)})

	assert_almost_eq(restored.color.g, 1.0, 0.0001)


func test_duplicate_deep_returns_an_independent_object() -> void:
	# SunSettings is a Resource, so plain assignment aliases. GameplayMenuController
	# snapshots settings on drawer open and restores them on cancel, so an alias
	# would silently break cancel.
	var original := SunSettings.new()
	original.azimuth_degrees = 90.0
	original.color = Color(1.0, 0.0, 0.0)

	var copy := original.duplicate_deep()
	copy.azimuth_degrees = 270.0
	copy.color = Color(0.0, 0.0, 1.0)

	assert_almost_eq(original.azimuth_degrees, 90.0, 0.0001)
	assert_almost_eq(original.color.r, 1.0, 0.0001)


func test_duplicate_deep_preserves_full_color_precision() -> void:
	# Unlike to_dict/from_dict, the in-memory copy must not quantize.
	var original := SunSettings.new()
	original.color = Color(0.123456, 0.654321, 0.314159)

	var copy := original.duplicate_deep()

	assert_eq(copy.color, original.color)
