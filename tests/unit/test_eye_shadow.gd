extends GutTest

## EyeShadow: the sun's shadow max distance at the eye view (pure maths), and the manager's
## eye fit that applies it.

const MAP := AABB(Vector3(-75, 0, -75), Vector3(150, 12, 150))


func after_each() -> void:
	EyeShadow.max_distance = EyeShadow.MAX_DISTANCE


func test_far_reach_is_the_farthest_corner_in_the_horizontal() -> void:
	assert_almost_eq(EyeShadow.far_reach(Vector3(0, 1.6, 0), MAP), 75.0 * sqrt(2.0), 0.001)
	assert_almost_eq(EyeShadow.far_reach(Vector3(60, 9.0, 60), MAP), 135.0 * sqrt(2.0), 0.001)


func test_far_reach_of_an_empty_box_is_zero() -> void:
	assert_eq(EyeShadow.far_reach(Vector3.ZERO, AABB()), 0.0)


func test_far_reach_ignores_height_and_the_way_the_eye_faces() -> void:
	var low := EyeShadow.far_reach(Vector3(10, 0, 10), MAP)
	var high := EyeShadow.far_reach(Vector3(10, 50, 10), MAP)
	assert_eq(low, high)


func test_the_distance_keeps_the_fade_band_past_the_far_ground() -> void:
	var eye := Vector3(0, 1.6, 0)
	var reach := EyeShadow.far_reach(eye, MAP)
	var wanted := EyeShadow.distance(eye, MAP, 1.0)
	assert_gte(wanted * LevelEnvironmentManager.SUN_SHADOW_FADE_START, reach, "fade starts beyond")
	assert_eq(fmod(wanted, EyeShadow.STEP), 0.0, "a multiple of the step")


func test_a_small_map_keeps_the_floor() -> void:
	var tiny := AABB(Vector3(-10, 0, -10), Vector3(20, 5, 20))
	assert_eq(
		EyeShadow.distance(Vector3.ZERO, tiny, 1.0), LevelEnvironmentManager.SUN_SHADOW_MAX_DISTANCE
	)


func test_a_big_map_is_capped() -> void:
	var huge := AABB(Vector3(-400, 0, -400), Vector3(800, 12, 800))
	assert_eq(EyeShadow.distance(Vector3.ZERO, huge, 1.0), EyeShadow.MAX_DISTANCE)
	assert_eq(EyeShadow.distance(Vector3.ZERO, huge, 2.0), EyeShadow.MAX_DISTANCE * 2.0)


func test_the_cap_can_be_set_for_a_probe_and_never_goes_below_the_floor() -> void:
	var huge := AABB(Vector3(-400, 0, -400), Vector3(800, 12, 800))
	EyeShadow.max_distance = 120.0
	assert_eq(EyeShadow.distance(Vector3.ZERO, huge, 1.0), 120.0)
	EyeShadow.max_distance = 50.0
	assert_eq(
		EyeShadow.distance(Vector3.ZERO, huge, 1.0), LevelEnvironmentManager.SUN_SHADOW_MAX_DISTANCE
	)


func test_the_distance_follows_where_the_eye_stands() -> void:
	# The input is a point, not a view: no yaw can move it. Walking across the map does.
	var middle := EyeShadow.distance(Vector3(0, 1.6, 0), MAP, 1.0)
	var corner := EyeShadow.distance(Vector3(-70, 1.6, 70), MAP, 1.0)
	assert_gt(corner, middle, "the far corner of the map is farther from a corner")


func test_the_manager_applies_the_eye_fit_with_a_one_metre_dead_band() -> void:
	var manager := LevelEnvironmentManager.new()
	var light := DirectionalLight3D.new()
	add_child_autofree(light)
	manager._sun_light = light
	var eye := Vector3(0, 1.6, 0)
	var wanted := EyeShadow.distance(eye, MAP, 1.0)
	assert_eq(manager.fit_shadow_distance_for_eye(eye, MAP, 1.0), wanted)
	assert_eq(light.directional_shadow_max_distance, wanted)
	light.directional_shadow_max_distance = wanted + 0.4
	manager.fit_shadow_distance_for_eye(eye, MAP, 1.0)
	assert_almost_eq(
		light.directional_shadow_max_distance, wanted + 0.4, 0.001, "inside the dead band"
	)
