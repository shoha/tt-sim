extends GutTest

## The environment manager turns an HDRI sky so its brightest column follows the
## sun's azimuth, in every sun mode, and keeps gradients unrotated.


func _loaded(preset: String) -> LevelEnvironmentManager:
	var manager := LevelEnvironmentManager.new()
	var root: Node3D = autofree(Node3D.new())
	var level_data := LevelData.new()
	level_data.environment_preset = preset
	manager.apply_level_environment(level_data, root)
	return manager


func _sun(azimuth: float, mode: String = "on") -> SunSettings:
	var settings := SunSettings.new()
	settings.azimuth_degrees = azimuth
	settings.mode = mode
	return settings


func _rotation(manager: LevelEnvironmentManager) -> Vector3:
	return manager.get_world_environment().environment.sky_rotation


func test_hdri_sky_rotates_with_the_sun() -> void:
	var manager := _loaded("outdoor_day")
	manager.apply_sun_settings(_sun(123.0))
	assert_eq(_rotation(manager), EnvironmentPresets.sky_rotation_for(123.0, "clear_day"))
	assert_ne(_rotation(manager), Vector3.ZERO)


func test_gradient_sky_never_rotates() -> void:
	var manager := _loaded("outdoor_night")
	manager.apply_sun_settings(_sun(123.0))
	assert_eq(_rotation(manager), Vector3.ZERO)


func test_sun_off_keeps_the_same_rotation() -> void:
	var manager := _loaded("outdoor_day")
	manager.apply_sun_settings(_sun(200.0, "off"))
	assert_eq(_rotation(manager), EnvironmentPresets.sky_rotation_for(200.0, "clear_day"))


func test_switching_the_environment_resyncs_rotation() -> void:
	var manager := _loaded("outdoor_day")
	manager.apply_sun_settings(_sun(123.0))
	manager.apply_environment_settings("outdoor_night", {})
	assert_eq(_rotation(manager), Vector3.ZERO)
	manager.apply_environment_settings("outdoor_day", {})
	assert_eq(_rotation(manager), EnvironmentPresets.sky_rotation_for(123.0, "clear_day"))
	manager.apply_environment_settings("outdoor_day", {"sky_preset": "sunset"})
	assert_eq(_rotation(manager), EnvironmentPresets.sky_rotation_for(123.0, "sunset"))


func test_level_load_applies_the_level_sun_azimuth() -> void:
	var manager := LevelEnvironmentManager.new()
	var root: Node3D = autofree(Node3D.new())
	var level_data := LevelData.new()
	level_data.environment_preset = "outdoor_day"
	level_data.visual_settings.sun.azimuth_degrees = 45.0
	manager.apply_level_environment(level_data, root)
	assert_eq(_rotation(manager), EnvironmentPresets.sky_rotation_for(45.0, "clear_day"))
