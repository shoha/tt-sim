extends GutTest

## UiPreferences persists the values toggle in its own [ui] section without
## disturbing other sections, and defaults to off when nothing is saved.

const TEMP_PATH := "user://test_ui_preferences.cfg"


func before_each() -> void:
	UiPreferences.settings_path = TEMP_PATH
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	UiPreferences.settings_path = Paths.SETTINGS_PATH


func test_defaults_to_off() -> void:
	assert_false(UiPreferences.load_show_values())


func test_round_trip_keeps_other_sections() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", 0.5)
	config.save(TEMP_PATH)
	UiPreferences.save_show_values(true)
	assert_true(UiPreferences.load_show_values())
	var reread := ConfigFile.new()
	reread.load(TEMP_PATH)
	assert_eq(reread.get_value("audio", "master", -1.0), 0.5)
	UiPreferences.save_show_values(false)
	assert_false(UiPreferences.load_show_values())
