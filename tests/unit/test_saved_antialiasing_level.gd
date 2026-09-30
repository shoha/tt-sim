extends GutTest

## VisualEffectsController.saved_antialiasing_level(): the saved Antialiasing setting, read
## without a controller (the graphics warm-up's viewport matches it).

const PATH := "user://test_saved_antialiasing_level.cfg"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_no_settings_file_means_disabled() -> void:
	assert_eq(VisualEffectsController.saved_antialiasing_level(PATH), Viewport.MSAA_DISABLED)


func test_the_saved_level_is_read() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "antialiasing", Viewport.MSAA_4X)
	assert_eq(config.save(PATH), OK)
	assert_eq(VisualEffectsController.saved_antialiasing_level(PATH), Viewport.MSAA_4X)
