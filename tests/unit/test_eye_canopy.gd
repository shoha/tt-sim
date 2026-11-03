extends GutTest

## The eye view's foliage maths (EyeCanopy), what CanopyFade.publish writes for a perspective
## camera and what it still writes, unchanged, for the orthographic one, and the shaders' copies
## of the constants. The fade itself is judged in renders (jobs/eyecanopy_*.json).

const HOME := 13.85


func _camera(position: Vector3, perspective: bool) -> Camera3D:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	if perspective:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 60.0
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = HOME
	camera.global_position = position
	return camera


func _shader_const(path: String, name: String) -> float:
	var text := FileAccess.get_file_as_string(path)
	var regex := RegEx.create_from_string("const float " + name + " = ([0-9.]+);")
	var found := regex.search(text)
	assert_not_null(found, "%s declares %s" % [path, name])
	return float(found.get_string(1)) if found else NAN


func after_each() -> void:
	CanopyFade.enabled = CanopyFade.DEFAULT_ENABLED


# --- the near fade ---------------------------------------------------------------------------


func test_cards_inside_the_full_radius_are_gone_and_far_ones_stay() -> void:
	assert_eq(EyeCanopy.near_fade(0.0), 1.0)
	assert_eq(EyeCanopy.near_fade(EyeCanopy.NEAR_FULL_M), 1.0)
	assert_eq(EyeCanopy.near_fade(EyeCanopy.NEAR_NONE_M), 0.0)
	assert_eq(EyeCanopy.near_fade(20.0), 0.0, "a crown further away stays painted")


func test_the_near_fade_falls_steadily_between_the_radii() -> void:
	var last := 1.0
	for i in range(1, 20):
		var d := lerpf(EyeCanopy.NEAR_FULL_M, EyeCanopy.NEAR_NONE_M, i / 20.0)
		var f := EyeCanopy.near_fade(d)
		assert_lt(f, last, "monotone at %f m" % d)
		last = f
	assert_between(EyeCanopy.near_fade(1.5), 0.3, 0.8, "a crown 1.5 m away is thinned, not gone")


func test_the_near_fade_scales_with_the_map() -> void:
	assert_almost_eq(EyeCanopy.near_fade(3.0, 2.0), EyeCanopy.near_fade(1.5, 1.0), 0.00001)
	assert_eq(EyeCanopy.near_fade(1.5, 0.0), EyeCanopy.near_fade(1.5, 1.0), "no scale reads as 1")


# --- the ghost range -------------------------------------------------------------------------


func test_the_ghost_keeps_its_strength_near_and_fades_by_range() -> void:
	assert_eq(EyeCanopy.ghost_weight(10.0, 1.0), 1.0)
	assert_eq(EyeCanopy.ghost_weight(EyeCanopy.GHOST_START_M, 1.0), 1.0)
	assert_eq(EyeCanopy.ghost_weight(EyeCanopy.GHOST_END_M, 1.0), 0.0)
	assert_eq(EyeCanopy.ghost_weight(100.0, 1.0), 0.0, "a ghost at 100 m is gone")
	assert_between(EyeCanopy.ghost_weight(40.0, 1.0), 0.01, 0.99)
	assert_almost_eq(
		EyeCanopy.ghost_weight(80.0, 2.0), EyeCanopy.ghost_weight(40.0, 1.0), 0.00001
	)


func test_scale_zero_is_the_home_view_with_no_range_fade() -> void:
	assert_eq(EyeCanopy.ghost_weight(500.0, 0.0), 1.0)


# --- the focus ---------------------------------------------------------------------------------


func test_the_focus_is_the_ground_hit_or_a_fixed_distance_ahead() -> void:
	var eye := Vector3(1.0, 1.6, 2.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	var hit := Vector3(4.0, 0.0, -9.0)
	assert_eq(EyeCanopy.focus_point(eye, forward, true, hit), hit)
	var miss := EyeCanopy.focus_point(eye, forward, false, Vector3.ZERO)
	assert_almost_eq(miss.distance_to(eye), EyeCanopy.FOCUS_AHEAD_M, 0.0001)
	assert_almost_eq(miss.z, 2.0 - EyeCanopy.FOCUS_AHEAD_M, 0.0001)
	var scaled := EyeCanopy.focus_point(eye, forward, false, Vector3.ZERO, 2.0)
	assert_almost_eq(scaled.distance_to(eye), EyeCanopy.FOCUS_AHEAD_M * 2.0, 0.0001)


func test_the_window_size_is_the_span_of_the_view_at_the_focus() -> void:
	assert_almost_eq(EyeCanopy.window_size(12.0, 60.0), 13.8564, 0.001, "about the home size")
	var home := EyeCanopy.window_size(EyeCanopy.FOCUS_HOME_M, 60.0)
	assert_almost_eq(EyeCanopy.home_size(60.0), home, 0.0001)
	var wide := EyeCanopy.window_size(12.0, 90.0)
	assert_gt(wide, EyeCanopy.window_size(12.0, 40.0), "a wider lens spans more")
	assert_almost_eq(EyeCanopy.window_size(24.0, 60.0, 2.0), EyeCanopy.window_size(12.0, 60.0), 0.0001)


func test_the_window_closes_in_as_the_focus_comes_near() -> void:
	var home := EyeCanopy.home_size(60.0)
	var far := CanopyFade.strength(EyeCanopy.window_size(12.0, 60.0), home)
	var near := CanopyFade.strength(EyeCanopy.window_size(4.0, 60.0), home)
	assert_gt(near, far, "stronger when the focus is close")
	assert_eq(
		CanopyFade.strength(EyeCanopy.window_size(40.0, 60.0), home), 0.0,
		"a focus 40 m away asks for no window"
	)


# --- the camera's own pass --------------------------------------------------------------------


func test_only_the_camera_at_the_eye_is_the_camera_pass() -> void:
	var eye := Vector3(5.0, 1.6, 5.0)
	assert_true(EyeCanopy.is_camera_pass(eye, eye))
	assert_true(EyeCanopy.is_camera_pass(eye + Vector3(0.1, 0.0, 0.0), eye))
	assert_false(EyeCanopy.is_camera_pass(eye + Vector3(30.0, 60.0, -20.0), eye), "the sun's view")


# --- the occlusion fade's projection fix -----------------------------------------------------


func test_a_fragment_on_the_ray_to_the_token_has_no_offset_under_perspective() -> void:
	var token := Vector3(3.0, 1.0, -12.0)
	var fragment := token * 0.4
	var offset := EyeCanopy.token_plane_xy(fragment, token, true) - Vector2(token.x, token.y)
	assert_almost_eq(offset.length(), 0.0, 0.0001)
	var unfixed := Vector2(fragment.x, fragment.y) - Vector2(token.x, token.y)
	assert_gt(unfixed.length(), 1.0, "the old subtraction missed by metres at this angle")


func test_the_orthographic_offset_is_the_view_space_xy_as_before() -> void:
	var token := Vector3(3.0, 1.0, -12.0)
	var fragment := Vector3(2.0, 0.5, -4.0)
	assert_eq(EyeCanopy.token_plane_xy(fragment, token, false), Vector2(2.0, 0.5))


func test_a_fragment_at_the_eye_plane_is_left_alone() -> void:
	var xy := EyeCanopy.token_plane_xy(Vector3(1.0, 2.0, 0.0), Vector3(0.0, 0.0, -5.0), true)
	assert_eq(xy, Vector2(1.0, 2.0))


# --- the shaders' copies ---------------------------------------------------------------------


func test_the_foliage_shader_carries_the_near_fade_radii() -> void:
	var path := "res://shaders/wind_foliage_include.gdshaderinc"
	assert_eq(_shader_const(path, "CANOPY_EYE_FULL"), EyeCanopy.NEAR_FULL_M)
	assert_eq(_shader_const(path, "CANOPY_EYE_NONE"), EyeCanopy.NEAR_NONE_M)
	assert_eq(_shader_const(path, "CANOPY_EYE_PASS"), EyeCanopy.PASS_TOLERANCE_M)


func test_the_ghost_shader_carries_the_range() -> void:
	var path := "res://shaders/token_ghost.gdshader"
	assert_eq(_shader_const(path, "GHOST_START"), EyeCanopy.GHOST_START_M)
	assert_eq(_shader_const(path, "GHOST_END"), EyeCanopy.GHOST_END_M)


func test_the_eye_fade_is_tested_against_the_camera_origin_not_the_shadow_pass() -> void:
	var text := FileAccess.get_file_as_string("res://shaders/wind_foliage_include.gdshaderinc")
	var origin_test := "distance(inv_view_matrix[3].xyz, canopy_eye.xyz) < CANOPY_EYE_PASS"
	assert_string_contains(text, origin_test)
	assert_string_contains(text, "if (eye_pass) {", "the eye term runs only in the camera's pass")
	var ghost := FileAccess.get_file_as_string("res://shaders/token_ghost.gdshader")
	assert_string_contains(ghost, "PROJECTION_MATRIX[3][3] < 0.5", "perspective only")


func test_the_occlusion_fade_scales_by_projection_only_when_perspective() -> void:
	var text := FileAccess.get_file_as_string("res://shaders/occlusion_fade_include.gdshaderinc")
	assert_string_contains(text, "projection_matrix[3][3] < 0.5")
	assert_string_contains(text, "fragment_xy *= token_view.z / vertex_view.z;")


# --- what publish writes ---------------------------------------------------------------------


func test_the_orthographic_publish_writes_the_same_values_as_before() -> void:
	var camera := _camera(Vector3(10.0, 20.0, 10.0), false)
	camera.look_at(Vector3.ZERO)
	CanopyFade.enabled = false
	CanopyFade.publish(camera, HOME, Vector2(1920.0, 1080.0), 0.0)
	var back := camera.global_basis.z.normalized()
	assert_eq(CanopyFade._last_view, Vector4(back.x, back.y, back.z, 0.0))
	var size := camera.size
	assert_eq(CanopyFade._last_shape, CanopyFade.shape(size, HOME), "from Camera3D.size, as ever")
	assert_eq(CanopyFade._last_centre, Vector4.ZERO, "off while the setting is off")
	assert_eq(CanopyFade._last_eye, Vector4.ZERO, "no eye in the orbit view")


func test_the_orthographic_window_still_follows_the_size() -> void:
	var camera := _camera(Vector3(10.0, 20.0, 10.0), false)
	camera.look_at(Vector3.ZERO)
	camera.size = 9.0
	CanopyFade.enabled = true
	CanopyFade.publish(camera, HOME, Vector2(1920.0, 1080.0), 0.0)
	assert_eq(CanopyFade._last_shape, CanopyFade.shape(9.0, HOME))
	assert_almost_eq(CanopyFade._last_centre.w, CanopyFade.strength(9.0, HOME), 0.00001)
	assert_eq(CanopyFade._last_eye, Vector4.ZERO)


func test_the_perspective_publish_carries_the_eye_and_ignores_the_stale_size() -> void:
	var camera := _camera(Vector3(2.0, 1.6, 3.0), true)
	camera.size = 99.0
	CanopyFade.enabled = false
	CanopyFade.publish(camera, camera.size, Vector2(1920.0, 1080.0), 0.0)
	assert_eq(CanopyFade._last_eye, Vector4(2.0, 1.6, 3.0, 1.0))
	assert_eq(CanopyFade._last_centre, Vector4.ZERO)
	var back := camera.global_basis.z.normalized()
	assert_eq(CanopyFade._last_view, Vector4(back.x, back.y, back.z, 0.0), "the axis the shaders test")
	assert_ne(CanopyFade._last_shape, CanopyFade.shape(99.0, 99.0))


func test_the_probe_switch_holds_the_eye_fade_off() -> void:
	var camera := _camera(Vector3(2.0, 1.6, 3.0), true)
	CanopyFade.eye_fade_enabled = false
	CanopyFade.publish(camera, camera.size, Vector2(1920.0, 1080.0), 0.0)
	CanopyFade.eye_fade_enabled = true
	assert_eq(CanopyFade._last_eye, Vector4(2.0, 1.6, 3.0, 0.0), "scale 0: no near fade, no range")


func test_the_perspective_window_focuses_a_fixed_distance_ahead_when_the_ray_misses() -> void:
	var camera := _camera(Vector3(0.0, 1.6, 0.0), true)
	CanopyFade.enabled = true
	CanopyFade.publish(camera, camera.size, Vector2(1920.0, 1080.0), 0.0)
	var focus := CanopyFade._last_centre
	assert_gt(focus.w, 0.0, "the window is on")
	var at := Vector3(focus.x, focus.y, focus.z)
	assert_almost_eq(at.distance_to(camera.global_position), EyeCanopy.FOCUS_AHEAD_M, 0.0001)
	var size := EyeCanopy.window_size(EyeCanopy.FOCUS_AHEAD_M, 60.0)
	assert_eq(CanopyFade._last_shape, CanopyFade.shape(size, EyeCanopy.home_size(60.0)))


func test_the_map_scale_is_read_from_the_level_map_beside_the_camera() -> void:
	var viewport := Node3D.new()
	add_child_autofree(viewport)
	var holder := Node3D.new()
	viewport.add_child(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	assert_eq(CanopyFade.map_scale(camera), 1.0, "no map")
	var container := Node3D.new()
	container.name = "MapContainer"
	viewport.add_child(container)
	var map := Node3D.new()
	map.name = "LevelMap"
	map.scale = Vector3.ONE * 2.5
	container.add_child(map)
	assert_almost_eq(CanopyFade.map_scale(camera), 2.5, 0.0001)
	assert_eq(CanopyFade.map_scale(autofree(Camera3D.new())), 1.0, "a camera with no parent")
