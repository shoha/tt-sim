extends GutTest

## The player's Wind motion setting (card wind_de): the slider's words and clamps, the saved
## [graphics] wind_motion value round trip through the Settings menu, and the live change of the
## Wind autoload (the OS reduce-motion override is tested in test_wind_autoload.gd).

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TEMP_PATH := "user://test_settings_wind_motion.cfg"

var _was: float = 1.0


func before_each() -> void:
	_was = Wind.wind_motion()


func after_each() -> void:
	Wind.set_wind_motion(_was)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_percent_and_scale_clamp_and_invert() -> void:
	assert_eq(SettingsWindMotion.percent_of(1.0), 100.0)
	assert_eq(SettingsWindMotion.percent_of(0.25), 25.0)
	assert_eq(SettingsWindMotion.percent_of(7.0), 100.0, "clamped high")
	assert_eq(SettingsWindMotion.percent_of(-2.0), 0.0, "clamped low")
	assert_eq(SettingsWindMotion.scale_of(50.0), 0.5)
	assert_eq(SettingsWindMotion.scale_of(250.0), 1.0)
	assert_eq(SettingsWindMotion.scale_of(-10.0), 0.0)
	assert_eq(SettingsWindMotion.label_for(35.0), "35%")


func test_a_stored_value_outside_the_range_or_of_the_wrong_type_is_safe() -> void:
	var config := ConfigFile.new()
	assert_eq(SettingsWindMotion.stored(config), 1.0, "absent: the default")
	config.set_value("graphics", "wind_motion", 3.0)
	assert_eq(SettingsWindMotion.stored(config), 1.0, "clamped")
	config.set_value("graphics", "wind_motion", -1.0)
	assert_eq(SettingsWindMotion.stored(config), 0.0)
	config.set_value("graphics", "wind_motion", "loud")
	assert_eq(SettingsWindMotion.stored(config), 1.0, "not a number: the default")


func test_the_autoload_clamps_the_scale() -> void:
	Wind.set_wind_motion(5.0)
	assert_eq(Wind.wind_motion(), 1.0)
	Wind.set_wind_motion(-1.0)
	assert_eq(Wind.wind_motion(), 0.0)
	Wind.set_wind_motion(0.4)
	assert_almost_eq(Wind.wind_motion(), 0.4, 0.0001)


func test_the_menu_slider_saves_and_shows_the_setting() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	assert_eq(menu.wind_motion_slider.value, 100.0, "the default is full motion")
	menu.wind_motion_slider.set_value_no_signal(40.0)
	menu._save_settings(TEMP_PATH)
	var config := ConfigFile.new()
	assert_eq(config.load(TEMP_PATH), OK)
	assert_almost_eq(float(config.get_value("graphics", "wind_motion")), 0.4, 0.0001)
	menu.wind_motion_slider.set_value_no_signal(100.0)
	SettingsWindMotion.show_saved(menu, config)
	assert_eq(menu.wind_motion_slider.value, 40.0)
	assert_eq(menu.wind_motion_label.text, "40%")


func test_the_autoload_loads_the_saved_setting() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "wind_motion", 0.3)
	config.save(TEMP_PATH)
	Wind.set_wind_motion(1.0)
	Wind.load_settings(TEMP_PATH)
	assert_almost_eq(Wind.wind_motion(), 0.3, 0.0001)


func test_moving_the_slider_applies_to_the_autoload_at_once() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	Wind.set_wind_motion(1.0)
	menu.wind_motion_slider.value = 25.0
	assert_almost_eq(Wind.wind_motion(), 0.25, 0.0001)
	assert_eq(menu.wind_motion_label.text, "25%")
	menu.wind_motion_slider.value = 0.0
	assert_eq(Wind.wind_motion(), 0.0, "zero holds everything still")
	assert_eq(Wind.motion_scale(), 0.0)


func test_the_slider_row_is_named_and_explained() -> void:
	var menu: SettingsMenu = SETTINGS_SCENE.instantiate()
	add_child_autofree(menu)
	assert_eq((menu.wind_motion_slider.get_parent().get_node("Label") as Label).text, "Wind motion")
	assert_true(menu.wind_motion_slider.tooltip_text.contains("reduce-motion"))
	assert_true(menu.wind_motion_slider.tooltip_text.contains("0 holds everything still"))
