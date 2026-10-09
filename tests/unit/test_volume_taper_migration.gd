extends GutTest

## Volumes saved before the squared taper keep their loudness. The first load converts
## each saved percentage p to 100 sqrt(p / 100) and stamps audio/taper, so the same gain
## comes out of the new curve; a stamped file is never converted again, nothing but the
## volumes changes, and the Settings menu stamps the marker whenever it saves, so a fresh
## install's first save is never converted. Every test works on its own config file, never
## user://settings.cfg.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TEMP_PATH := "user://_test_volume_taper_settings.cfg"


func before_each() -> void:
	_remove_temp()


func after_each() -> void:
	_remove_temp()


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


## A settings file as a build before the squared taper wrote it: no audio/taper.
func _write_linear_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", 50.0)
	config.set_value("audio", "sfx", 100.0)
	config.set_value("audio", "ui", 0.0)
	config.set_value("graphics", "vsync", false)
	config.set_value("graphics", "rendering_method", "mobile")
	config.set_value("grid_visuals", "line_thickness", 3.0)
	config.set_value("controls", "profile", 2)
	config.save(TEMP_PATH)


func _reread() -> ConfigFile:
	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	return config


func _master(config: ConfigFile) -> float:
	return float(config.get_value("audio", "master"))


func test_a_linear_save_keeps_its_loudness() -> void:
	_write_linear_settings()
	assert_not_null(AudioManager.load_migrated_settings(TEMP_PATH))

	var config := _reread()
	assert_almost_eq(_master(config), 70.71, 0.01, "50% becomes 70.7%")
	assert_almost_eq(
		AudioManager.slider_to_db(_master(config) / 100.0),
		linear_to_db(0.5),
		0.001,
		"which plays at the -6 dB the linear taper gave 50%"
	)
	assert_almost_eq(float(config.get_value("audio", "sfx")), 100.0, 0.0001)
	assert_eq(float(config.get_value("audio", "ui")), 0.0, "silent stays silent")
	assert_eq(config.get_value("audio", AudioManager.VOLUME_TAPER_KEY), AudioManager.VOLUME_TAPER)


func test_a_second_load_does_not_convert_again() -> void:
	_write_linear_settings()
	AudioManager.load_migrated_settings(TEMP_PATH)
	var loaded := AudioManager.load_migrated_settings(TEMP_PATH)

	assert_almost_eq(_master(loaded), 70.71, 0.01, "not 84.1%, the square root taken twice")
	assert_almost_eq(_master(_reread()), 70.71, 0.01)


func test_a_stamped_file_is_untouched() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", 50.0)
	config.set_value("audio", AudioManager.VOLUME_TAPER_KEY, AudioManager.VOLUME_TAPER)
	config.save(TEMP_PATH)
	var before := FileAccess.get_file_as_string(TEMP_PATH)

	var loaded := AudioManager.load_migrated_settings(TEMP_PATH)

	assert_eq(_master(loaded), 50.0)
	assert_eq(FileAccess.get_file_as_string(TEMP_PATH), before)


func test_only_the_saved_volumes_change() -> void:
	_write_linear_settings()
	AudioManager.load_migrated_settings(TEMP_PATH)

	var config := _reread()
	var sections := PackedStringArray(["audio", "graphics", "grid_visuals", "controls"])
	assert_eq(config.get_sections(), sections)
	assert_eq(
		config.get_section_keys("audio"),
		PackedStringArray(["master", "sfx", "ui", AudioManager.VOLUME_TAPER_KEY]),
		"no music volume is invented"
	)
	assert_eq(config.get_value("graphics", "vsync"), false)
	assert_eq(config.get_value("graphics", "rendering_method"), "mobile")
	assert_eq(config.get_value("grid_visuals", "line_thickness"), 3.0)
	assert_eq(config.get_value("controls", "profile"), 2)


func test_no_file_stays_no_file() -> void:
	assert_null(AudioManager.load_migrated_settings(TEMP_PATH))
	assert_false(FileAccess.file_exists(TEMP_PATH), "a fresh install gets no file at startup")


func test_the_menu_stamps_the_taper_when_it_saves() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	menu.master_slider.set_value_no_signal(50.0)

	menu._save_settings(TEMP_PATH)
	var loaded := AudioManager.load_migrated_settings(TEMP_PATH)

	assert_eq(loaded.get_value("audio", AudioManager.VOLUME_TAPER_KEY), AudioManager.VOLUME_TAPER)
	assert_eq(_master(loaded), 50.0, "a value saved on the squared taper is not converted")
