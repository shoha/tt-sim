extends GutTest

## Serialization and migration tests for LevelData.visual_settings -- the typed
## sun schema that replaced the flat sun_overrides dictionary in format version
## 1. See docs/superpowers/specs/2026-09-11-sun-shadow-visual-settings-design.md.


func test_to_dict_stamps_the_current_format_version() -> void:
	var level := LevelData.new()

	var data := level.to_dict()

	assert_eq(data["format_version"], LevelData.FORMAT_VERSION)


func test_to_dict_includes_visual_settings() -> void:
	var level := LevelData.new()
	level.visual_settings.sun.mode = "on"
	level.visual_settings.sun.azimuth_degrees = 200.0

	var data := level.to_dict()

	assert_eq(data["visual_settings"]["sun"]["mode"], "on")
	assert_almost_eq(float(data["visual_settings"]["sun"]["azimuth_degrees"]), 200.0, 0.001)


func test_to_dict_no_longer_writes_the_legacy_key() -> void:
	var data := LevelData.new().to_dict()

	assert_false(data.has("sun_overrides"), "legacy key must not be written by v1")


func test_from_dict_restores_visual_settings_for_a_versioned_level() -> void:
	var data := {
		"format_version": 1,
		"visual_settings": {"sun": {"mode": "off", "softness": 2.0, "shadow_darkness": 0.5}},
	}

	var level := LevelData.from_dict(data)

	assert_eq(level.visual_settings.sun.mode, "off")
	assert_almost_eq(level.visual_settings.sun.softness, 2.0, 0.001)
	assert_almost_eq(level.visual_settings.sun.shadow_darkness, 0.5, 0.001)


func test_from_dict_migrates_a_level_with_no_format_version() -> void:
	var data := {"sun_overrides": {"mode": "on", "time_of_day": 8.0}}

	var level := LevelData.from_dict(data)

	assert_eq(level.format_version, LevelData.FORMAT_VERSION)
	assert_eq(level.visual_settings.sun.mode, "on")
	assert_almost_eq(level.visual_settings.sun.time_of_day, 8.0, 0.001)
	# Direction must come from the keyframes at hour 8, not from the field default.
	var expected := DefaultSun.settings_for_time(8.0)
	assert_almost_eq(level.visual_settings.sun.azimuth_degrees, expected.azimuth_degrees, 0.001)
	assert_almost_eq(level.visual_settings.sun.elevation_degrees, expected.elevation_degrees, 0.001)


func test_from_dict_migrates_a_level_with_neither_key() -> void:
	var level := LevelData.from_dict({})

	assert_eq(level.format_version, LevelData.FORMAT_VERSION)
	assert_eq(level.visual_settings.sun.mode, "auto")
	assert_almost_eq(level.visual_settings.sun.time_of_day, DefaultSun.DEFAULT_TIME_OF_DAY, 0.001)


func test_from_dict_ignores_a_stray_legacy_key_on_a_versioned_level() -> void:
	# A v1 writer never emits sun_overrides, so if both appear the versioned
	# field wins and the stale one is discarded.
	var data := {
		"format_version": 1,
		"visual_settings": {"sun": {"mode": "off"}},
		"sun_overrides": {"mode": "on"},
	}

	var level := LevelData.from_dict(data)

	assert_eq(level.visual_settings.sun.mode, "off")


func test_round_trip_through_to_dict_and_from_dict_is_stable() -> void:
	var level := LevelData.new()
	level.visual_settings.sun.mode = "on"
	level.visual_settings.sun.azimuth_degrees = 275.0
	level.visual_settings.sun.elevation_degrees = 8.0
	level.visual_settings.sun.energy = 1.4
	level.visual_settings.sun.shadows_enabled = false
	level.visual_settings.sun.softness = 4.0

	var restored := LevelData.from_dict(level.to_dict())

	assert_eq(restored.visual_settings.sun.mode, "on")
	assert_almost_eq(restored.visual_settings.sun.azimuth_degrees, 275.0, 0.001)
	assert_almost_eq(restored.visual_settings.sun.elevation_degrees, 8.0, 0.001)
	assert_almost_eq(restored.visual_settings.sun.energy, 1.4, 0.001)
	assert_eq(restored.visual_settings.sun.shadows_enabled, false)
	assert_almost_eq(restored.visual_settings.sun.softness, 4.0, 0.001)


func test_duplicate_level_copies_visual_settings_independently() -> void:
	# VisualSettings is a Resource, so a plain assignment in duplicate_level()
	# would alias and let edits to the copy leak into the original.
	var level := LevelData.new()
	level.visual_settings.sun.mode = "on"

	var copy := level.duplicate_level()
	copy.visual_settings.sun.mode = "off"

	assert_eq(level.visual_settings.sun.mode, "on")


func test_a_snapshot_taken_with_copy_settings_survives_later_edits() -> void:
	# This is the aliasing hazard the drawer's cancel path depends on:
	# GameplayMenuController snapshots visual_settings on open, the user edits
	# the live settings, and cancel restores the snapshot. If the snapshot
	# aliased, the edits would have overwritten it and cancel would do nothing.
	var level := LevelData.new()
	level.visual_settings.sun.azimuth_degrees = 100.0

	var snapshot := level.visual_settings.copy_settings()
	level.visual_settings.sun.azimuth_degrees = 300.0
	level.visual_settings = snapshot.copy_settings()

	assert_almost_eq(level.visual_settings.sun.azimuth_degrees, 100.0, 0.001)


func test_two_fresh_levels_do_not_share_one_visual_settings() -> void:
	# The bottom rung of the aliasing ladder: `@export var visual_settings:
	# VisualSettings = VisualSettings.default()` must produce a new resource per
	# instance, not one shared default that every level then edits in common.
	var first := LevelData.new()
	var second := LevelData.new()

	first.visual_settings.sun.azimuth_degrees = 42.0

	assert_false(
		first.visual_settings == second.visual_settings, "fresh levels must not share an instance"
	)
	assert_false(first.visual_settings.sun == second.visual_settings.sun, "nor a shared sun")
	var fresh := SunSettings.default()
	assert_almost_eq(second.visual_settings.sun.azimuth_degrees, fresh.azimuth_degrees, 0.001)
	assert_almost_eq(first.visual_settings.sun.azimuth_degrees, 42.0, 0.001)


func test_setting_the_legacy_property_directly_migrates_the_sun() -> void:
	# Exercises LevelData._set() the same way ResourceLoader does when it reads a
	# legacy .tres that still carries a sun_overrides property. That path never
	# reaches from_dict(), so without the hook the sun would be silently lost.
	var level := LevelData.new()

	level.set("sun_overrides", {"mode": "off", "time_of_day": 20.0})

	assert_eq(level.visual_settings.sun.mode, "off")
	assert_almost_eq(level.visual_settings.sun.time_of_day, 20.0, 0.001)
	var expected := DefaultSun.settings_for_time(20.0)
	assert_almost_eq(level.visual_settings.sun.azimuth_degrees, expected.azimuth_degrees, 0.001)
	assert_almost_eq(level.visual_settings.sun.elevation_degrees, expected.elevation_degrees, 0.001)
	assert_almost_eq(level.visual_settings.sun.energy, expected.energy, 0.001)


func test_setting_a_genuinely_unknown_property_is_still_rejected() -> void:
	# _set() must return false for anything but the one legacy key, so typos and
	# unrelated stray properties keep failing loudly instead of being swallowed.
	var level := LevelData.new()

	level.set("no_such_property_at_all", 7)

	assert_false(
		level.get("no_such_property_at_all") != null, "unknown properties must not be stored"
	)
