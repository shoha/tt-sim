extends GutTest

## The picker groups must cover every lighting preset exactly once, and the
## display names must be readable.


func test_every_preset_is_in_exactly_one_group() -> void:
	var seen: Dictionary = {}
	for group in EnvironmentPresets.PRESET_GROUPS:
		for preset_name in EnvironmentPresets.PRESET_GROUPS[group]:
			assert_true(EnvironmentPresets.PRESETS.has(preset_name), preset_name + " exists")
			assert_false(seen.has(preset_name), preset_name + " listed once")
			seen[preset_name] = true
	for preset_name in EnvironmentPresets.PRESETS:
		assert_true(seen.has(preset_name), preset_name + " is grouped")


func test_group_lookup_and_display_names() -> void:
	assert_eq(EnvironmentPresets.get_preset_group("outdoor_day"), "Outdoor")
	assert_eq(EnvironmentPresets.get_preset_group("tavern"), "Indoor")
	assert_eq(EnvironmentPresets.get_preset_group("nope"), "Other")
	assert_eq(EnvironmentPresets.display_name("outdoor_day"), "Outdoor Day")
	assert_eq(EnvironmentPresets.display_name(""), "Map defaults")
