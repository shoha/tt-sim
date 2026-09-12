extends GutTest

## Unit tests for VisualSettings (resources/visual_settings.gd) -- the schema
## version 1 container for a level's visual configuration. It holds only `sun`
## today; the intent-level look schema is added to it later, which is why the
## wrapper exists at all rather than LevelData owning SunSettings directly.


func test_default_builds_a_default_sun() -> void:
	var v := VisualSettings.default()

	assert_not_null(v.sun)
	assert_almost_eq(v.sun.time_of_day, DefaultSun.DEFAULT_TIME_OF_DAY, 0.001)


func test_to_dict_nests_the_sun_under_a_sun_key() -> void:
	var v := VisualSettings.default()
	v.sun.mode = "on"

	var data := v.to_dict()

	assert_true(data.has("sun"))
	assert_eq(data["sun"]["mode"], "on")


func test_from_dict_round_trips_the_sun() -> void:
	var original := VisualSettings.default()
	original.sun.mode = "off"
	original.sun.azimuth_degrees = 42.0
	original.sun.softness = 1.25

	var restored := VisualSettings.from_dict(original.to_dict())

	assert_eq(restored.sun.mode, "off")
	assert_almost_eq(restored.sun.azimuth_degrees, 42.0, 0.001)
	assert_almost_eq(restored.sun.softness, 1.25, 0.001)


func test_from_dict_falls_back_to_a_default_sun_when_the_key_is_missing() -> void:
	var restored := VisualSettings.from_dict({})

	assert_not_null(restored.sun)
	assert_almost_eq(restored.sun.time_of_day, DefaultSun.DEFAULT_TIME_OF_DAY, 0.001)


func test_from_dict_falls_back_to_a_default_sun_when_the_key_is_not_a_dictionary() -> void:
	var restored := VisualSettings.from_dict({"sun": "corrupt"})

	assert_not_null(restored.sun)
	assert_eq(restored.sun.mode, "auto")


func test_new_instances_do_not_share_a_sun() -> void:
	var a := VisualSettings.new()
	var b := VisualSettings.new()

	a.sun.azimuth_degrees = 10.0
	b.sun.azimuth_degrees = 20.0

	assert_almost_eq(a.sun.azimuth_degrees, 10.0, 0.001)


func test_copy_settings_copies_the_nested_sun() -> void:
	var original := VisualSettings.default()
	original.sun.azimuth_degrees = 90.0

	var copy := original.copy_settings()
	copy.sun.azimuth_degrees = 270.0

	assert_almost_eq(original.sun.azimuth_degrees, 90.0, 0.001)
