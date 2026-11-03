extends GutTest

## The eye-level view: the pure maths in EyeRig (eye height, lens, walk, bounds, grab-pan) and
## EyeView on a real GameMap camera (entering stands the foot at the screen centre, turning
## pivots on the foot, leaving puts the orbit camera back as it was).

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")

var _game_map: GameMap
var _controller: CameraController


func before_each() -> void:
	var play := LevelPlayController.new()
	add_child_autofree(play)
	_game_map = GAME_MAP_SCENE.instantiate()
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	play.setup(_game_map)
	_game_map.setup(play)
	_controller = _game_map.get_camera_controller()


# --- EyeRig: pure maths ---


func test_eye_height_scales_with_the_map() -> void:
	assert_almost_eq(EyeRig.eye_height(1.0), 1.6, 0.0001)
	assert_almost_eq(EyeRig.eye_height(0.5), 0.8, 0.0001)
	assert_gt(EyeRig.eye_height(0.0), 0.0, "a zero scale does not flatten the eye")


func test_lens_is_held_to_its_range_and_steps_by_notch() -> void:
	assert_eq(EyeRig.clamp_lens(10.0), EyeRig.FOV_MIN)
	assert_eq(EyeRig.clamp_lens(120.0), EyeRig.FOV_MAX)
	assert_almost_eq(EyeRig.lens_after_notch(60.0, -1), 57.0, 0.0001, "wheel in narrows")
	assert_almost_eq(EyeRig.lens_after_notch(60.0, 1), 63.0, 0.0001, "wheel out widens")
	assert_eq(EyeRig.lens_after_notch(40.0, -1), 40.0)
	assert_eq(EyeRig.lens_after_notch(75.0, 1), 75.0)


func test_corrected_fov_keeps_the_sixteen_nine_width_on_a_narrow_window() -> void:
	assert_eq(EyeRig.corrected_fov(60.0, 16.0 / 9.0), 60.0)
	assert_eq(EyeRig.corrected_fov(60.0, 2.4), 60.0, "wider windows are left alone")
	var narrow := EyeRig.corrected_fov(60.0, 1.0)
	assert_gt(narrow, 60.0)
	# The horizontal half-extent at unit distance matches the 16:9 view's.
	var wide := tan(deg_to_rad(30.0)) * 16.0 / 9.0
	assert_almost_eq(tan(deg_to_rad(narrow) * 0.5) * 1.0, wide, 0.001)
	assert_lte(EyeRig.corrected_fov(75.0, 0.3), EyeRig.FOV_CEILING)


func test_walk_goes_the_way_the_camera_faces() -> void:
	var forward := EyeRig.walk_velocity(Vector2(0.0, 1.0), 45.0, false, 1.0)
	var up := CameraRig.screen_up(45.0)
	assert_almost_eq(forward.length(), EyeRig.WALK_SPEED, 0.0001)
	assert_almost_eq(forward.x, up.x * 5.0, 0.0001)
	assert_almost_eq(forward.y, up.z * 5.0, 0.0001)
	var right := EyeRig.walk_velocity(Vector2(1.0, 0.0), 135.0, false, 1.0)
	var screen_right := CameraRig.screen_right(135.0)
	assert_almost_eq(right.x, screen_right.x * 5.0, 0.0001)
	assert_almost_eq(right.y, screen_right.z * 5.0, 0.0001)


func test_walk_speed_runs_scales_and_does_not_speed_up_on_diagonals() -> void:
	var ahead := Vector2(0.0, 1.0)
	var walk := EyeRig.walk_velocity(ahead, 0.0, false, 1.0).length()
	var run := EyeRig.walk_velocity(ahead, 0.0, true, 1.0).length()
	var half := EyeRig.walk_velocity(ahead, 0.0, false, 0.5).length()
	var diagonal := EyeRig.walk_velocity(Vector2(1.0, 1.0), 0.0, false, 1.0).length()
	assert_almost_eq(run, walk * 2.0, 0.0001)
	assert_almost_eq(half, walk * 0.5, 0.0001)
	assert_almost_eq(diagonal, walk, 0.0001)
	assert_eq(EyeRig.walk_velocity(Vector2.ZERO, 0.0, true, 1.0), Vector2.ZERO)


func test_walk_step_covers_speed_times_time() -> void:
	var v := EyeRig.walk_velocity(Vector2(0.0, 1.0), 45.0, false, 1.0)
	var moved := EyeRig.walk_step(Vector2(10.0, 10.0), v, 2.0)
	assert_almost_eq(moved.distance_to(Vector2(10.0, 10.0)), 10.0, 0.0001, "5 m/s for 2 s")


func test_foot_stays_inside_the_map_by_the_inset() -> void:
	var bounds := AABB(Vector3(-20.0, 0.0, -10.0), Vector3(40.0, 5.0, 20.0))
	assert_eq(EyeRig.clamp_foot(Vector2(0.0, 0.0), bounds), Vector2(0.0, 0.0))
	assert_eq(EyeRig.clamp_foot(Vector2(99.0, 0.0), bounds), Vector2(18.5, 0.0))
	assert_eq(EyeRig.clamp_foot(Vector2(-99.0, -99.0), bounds), Vector2(-18.5, -8.5))
	var thin := AABB(Vector3(0.0, 0.0, 0.0), Vector3(2.0, 1.0, 50.0))
	var held := EyeRig.clamp_foot(Vector2(9.0, 5.0), thin)
	assert_almost_eq(held.x, 1.0, 0.0001, "a thin map: the middle")
	assert_eq(EyeRig.clamp_foot(Vector2(9.0, 5.0), AABB()), Vector2(9.0, 5.0), "no bounds known")


func test_ground_hit_refuses_flat_rays() -> void:
	var origin := Vector3(0.0, 1.6, 0.0)
	var steep := Vector3(0.0, -sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0)))
	var hit: Variant = EyeRig.ground_hit(origin, steep, 0.0)
	assert_typeof(hit, TYPE_VECTOR3)
	assert_almost_eq((hit as Vector3).y, 0.0, 0.0001)
	assert_almost_eq((hit as Vector3).z, -1.6 / tan(deg_to_rad(30.0)), 0.001)
	var grazing := Vector3(0.0, -sin(deg_to_rad(3.0)), -cos(deg_to_rad(3.0)))
	assert_null(EyeRig.ground_hit(origin, grazing, 0.0), "3 degrees below the horizon")
	assert_null(EyeRig.ground_hit(origin, Vector3(0.0, 0.0, -1.0), 0.0), "the horizon")
	assert_null(EyeRig.ground_hit(origin, Vector3(0.0, 0.5, -1.0), 0.0), "upward")
	var edge := Vector3(0.0, -sin(deg_to_rad(7.0)), -cos(deg_to_rad(7.0)))
	assert_typeof(EyeRig.ground_hit(origin, edge, 0.0), TYPE_VECTOR3)


func test_grab_pan_keeps_the_grabbed_point_under_the_cursor() -> void:
	# The eye at (0, 1.6, 0) grabs the ground at (0, 0, -6); the cursor then points along
	# `dir`, a ray that reaches the ground 4 m further to the right of that point.
	var grab := Vector3(0.0, 0.0, -6.0)
	var dir := Vector3(0.3, -0.35, -0.9).normalized()
	var foot: Variant = EyeRig.grab_pan_foot(grab, dir, 1.6)
	assert_typeof(foot, TYPE_VECTOR2)
	var eye := Vector3((foot as Vector2).x, 1.6, (foot as Vector2).y)
	# Casting the ray from the solved eye along `dir` lands on the grab point.
	var back: Variant = EyeRig.ground_hit(eye, dir, 0.0)
	assert_typeof(back, TYPE_VECTOR3)
	assert_almost_eq((back as Vector3).x, grab.x, 0.0001)
	assert_almost_eq((back as Vector3).z, grab.z, 0.0001)
	# Dragging the cursor right (a ray turned to the right) moves the foot left: the ground follows.
	var right_ray := Vector3(0.45, -0.35, -0.9).normalized()
	var moved: Variant = EyeRig.grab_pan_foot(grab, right_ray, 1.6)
	assert_lt((moved as Vector2).x, (foot as Vector2).x)
	assert_null(EyeRig.grab_pan_foot(grab, Vector3(0.0, -0.05, -1.0), 1.6), "too flat")


func test_stop_short_ends_before_the_target() -> void:
	var stop := EyeRig.stop_short(Vector2(0.0, 0.0), Vector2(10.0, 0.0), 1.5)
	assert_almost_eq(stop.x, 8.5, 0.0001)
	assert_eq(EyeRig.stop_short(Vector2(9.0, 0.0), Vector2(10.0, 0.0), 1.5), Vector2(9.0, 0.0))


func test_glide_is_quick_but_bounded_and_arrives() -> void:
	var goal := Vector2(100.0, 0.0)
	var one := EyeRig.glide_step(Vector2.ZERO, goal, 1.0 / 60.0)
	assert_almost_eq(one.x, EyeRig.GLIDE_MAX_SPEED / 60.0, 0.0001, "a far goal is a capped walk")
	var near_step := EyeRig.glide_step(Vector2.ZERO, Vector2(0.5, 0.0), 1.0 / 60.0)
	assert_gte(near_step.x, EyeRig.GLIDE_MIN_SPEED / 60.0 - 0.0001, "a tail still moves")
	assert_lt(near_step.x, 0.5)
	var foot := Vector2.ZERO
	var frames := 0
	while foot != goal and frames < 1000:
		foot = EyeRig.glide_step(foot, goal, 1.0 / 60.0)
		frames += 1
	assert_eq(foot, goal, "it ends on the goal")
	assert_lt(frames, 600, "100 m takes well under ten seconds")
	var half := EyeRig.glide_step(Vector2.ZERO, goal, 1.0 / 60.0, 0.5)
	assert_almost_eq(half.x, EyeRig.GLIDE_MAX_SPEED * 0.5 / 60.0, 0.0001, "scaled with the map")


func test_smooth_toward_does_not_overshoot_and_ignores_frame_length() -> void:
	assert_lt(EyeRig.smooth_toward(0.0, 1.0, 6.0, 0.016), 1.0)
	var one := EyeRig.smooth_toward(0.0, 1.0, 6.0, 0.1)
	var two := EyeRig.smooth_toward(EyeRig.smooth_toward(0.0, 1.0, 6.0, 0.05), 1.0, 6.0, 0.05)
	assert_almost_eq(one, two, 0.0001)


# --- CameraPitch range ---


func test_pitch_range_can_be_widened_for_the_eye() -> void:
	var pitch := CameraPitch.new()
	pitch.set_now(-10.0)
	assert_eq(pitch.pitch, CameraRig.MIN_PITCH, "orbit: no flatter than home")
	pitch.set_range(EyeRig.PITCH_MIN, EyeRig.PITCH_MAX)
	pitch.set_now(-80.0)
	assert_eq(pitch.pitch, EyeRig.PITCH_MIN)
	pitch.set_now(80.0)
	assert_eq(pitch.pitch, EyeRig.PITCH_MAX)


# --- EyeView on the real camera ---


func _holder() -> Node3D:
	return _game_map.cameraholder_node


func _camera() -> Camera3D:
	return _game_map.camera_node


func test_entering_the_eye_makes_the_camera_a_perspective_eye() -> void:
	_controller.set_view_mode(_controller.eye)
	var camera := _camera()
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	assert_eq(camera.projection, Camera3D.PROJECTION_PERSPECTIVE)
	assert_almost_eq(camera.near, EyeView.NEAR_PLANE, 0.0001)
	assert_almost_eq(camera.far, EyeView.FAR_PLANE, 0.0001)
	assert_almost_eq(_controller.view_mode().fov_deg(), 60.0, 0.0001)
	assert_almost_eq(camera.global_position.y - _holder().global_position.y, 1.6, 0.0001)
	assert_almost_eq(_controller.current_pitch(), EyeRig.PITCH_ENTRY, 0.0001)
	var look := -camera.global_basis.z
	assert_lt(look.y, 0.0, "the entry pitch looks slightly down")
	assert_lt(look.y, 0.0)


func test_the_eye_is_the_map_scale_high() -> void:
	var map := Node3D.new()
	map.name = "LevelMap"
	map.scale = Vector3.ONE * 0.5
	_game_map.map_container.add_child(map)
	_controller.set_view_mode(_controller.eye)
	_controller.eye.process(0.016)
	assert_almost_eq(_camera().global_position.y - _holder().global_position.y, 0.8, 0.0001)


func test_the_foot_starts_under_the_screen_centre_and_the_yaw_is_kept() -> void:
	var yaw := _controller.current_yaw()
	var camera := _camera()
	var vp := Vector2(_game_map.world_viewport.size) * 0.5
	var origin := camera.project_ray_origin(vp)
	var dir := camera.project_ray_normal(vp)
	var hit := origin + dir * (-origin.y / dir.y)
	_controller.set_view_mode(_controller.eye)
	var foot := _controller.eye.foot()
	assert_almost_eq(foot.x, hit.x, 0.001)
	assert_almost_eq(foot.y, hit.z, 0.001)
	assert_almost_eq(_controller.current_yaw(), yaw, 0.0001)


func test_a_turn_at_the_eye_pivots_on_the_foot() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	var before := _camera().global_position
	var foot := eye.foot()
	_controller.set_yaw_now(135.0)
	assert_almost_eq(_camera().global_position.x, before.x, 0.001)
	assert_almost_eq(_camera().global_position.z, before.z, 0.001)
	assert_eq(eye.foot(), foot)
	var flat := -_camera().global_basis.z
	flat.y = 0.0
	var up := CameraRig.screen_up(135.0)
	assert_almost_eq(flat.normalized().dot(up), 1.0, 0.001, "faces the new yaw")


func test_pitch_at_the_eye_looks_up_to_35_and_down_to_60() -> void:
	_controller.set_view_mode(_controller.eye)
	_controller.set_pitch_now(-80.0)
	assert_almost_eq(_controller.current_pitch(), -35.0, 0.0001)
	assert_gt(-_camera().global_basis.z.y, -1.0)
	assert_gt((-_camera().global_basis.z).y, 0.0, "looking up")
	_controller.set_pitch_now(80.0)
	assert_almost_eq(_controller.current_pitch(), 60.0, 0.0001)
	assert_lt((-_camera().global_basis.z).y, 0.0, "looking down")


func test_walking_moves_the_foot_along_the_facing_and_stops() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	eye.set_map_bounds(AABB(Vector3(-500.0, 0.0, -500.0), Vector3(1000.0, 10.0, 1000.0)))
	var start := eye.foot()
	eye.set_walk(Vector2(0.0, 1.0))
	for _i in 120:
		eye.process(1.0 / 60.0)
	var gone := eye.foot() - start
	var up := CameraRig.screen_up(_controller.current_yaw())
	assert_gt(gone.length(), 7.5, "about 2 s at 5 m/s, less the ramp-up")
	assert_lt(gone.length(), 10.0)
	assert_almost_eq(gone.normalized().dot(Vector2(up.x, up.z)), 1.0, 0.001)
	eye.set_walk(Vector2.ZERO)
	for _i in 60:
		eye.process(1.0 / 60.0)
	assert_true(eye.is_at_rest())


func test_walking_cannot_leave_the_map() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	eye.set_map_bounds(AABB(Vector3(-10.0, 0.0, -10.0), Vector3(20.0, 5.0, 20.0)))
	eye.set_walk(Vector2(0.0, 1.0), true)
	for _i in 300:
		eye.process(1.0 / 60.0)
	var foot := eye.foot()
	assert_lte(absf(foot.x), 8.5 + 0.0001)
	assert_lte(absf(foot.y), 8.5 + 0.0001)


func test_the_wheel_moves_the_lens_inside_its_range() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	for _i in 20:
		_controller.zoom_in_step()
	eye.finish_zoom()
	assert_almost_eq(eye.fov_deg(), 40.0, 0.0001)
	for _i in 30:
		_controller.zoom_out_step()
	eye.finish_zoom()
	assert_almost_eq(eye.fov_deg(), 75.0, 0.0001)
	assert_gte(_camera().fov, 75.0 - 0.001)


func test_leaving_the_eye_puts_the_orbit_camera_back() -> void:
	var camera := _camera()
	var holder_before := _holder().global_position
	var position_before := camera.position
	var basis_before := camera.basis
	var size_before := camera.size
	var near_before := camera.near
	var far_before := camera.far
	var pitch_before := _controller.current_pitch()
	_controller.set_view_mode(_controller.eye)
	_controller.eye.set_walk(Vector2(1.0, 1.0))
	for _i in 30:
		_controller.eye.process(1.0 / 60.0)
	_controller.set_view_mode(_controller.orbit_view())
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(camera.size, size_before, 0.0001)
	assert_almost_eq(camera.far, far_before, 0.0001)
	assert_almost_eq(camera.near, near_before, 0.001)
	assert_true(camera.position.is_equal_approx(position_before))
	assert_true(camera.basis.is_equal_approx(basis_before))
	assert_true(_holder().global_position.is_equal_approx(holder_before), "the walk left no trace")
	assert_almost_eq(_controller.current_pitch(), pitch_before, 0.0001)
	_controller.set_pitch_now(5.0)
	assert_almost_eq(_controller.current_pitch(), CameraRig.MIN_PITCH, 0.0001, "orbit range back")


func test_f9_toggles_the_eye() -> void:
	# The instant switch (the glide has its own tests, test_eye_glide.gd).
	EyeGlide.enabled = false
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	var key := InputEventKey.new()
	key.keycode = KEY_F9
	key.pressed = true
	_controller._unhandled_key_input(key)
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_controller._unhandled_key_input(key)
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	EyeGlide.enabled = true


func test_grab_pan_moves_the_foot_so_the_point_stays_under_the_cursor() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	eye.set_map_bounds(AABB(Vector3(-500.0, 0.0, -500.0), Vector3(1000.0, 10.0, 1000.0)))
	_controller.set_pitch_now(30.0)
	var camera := _camera()
	var vp := Vector2(_game_map.world_viewport.size)
	var press := vp * Vector2(0.5, 0.8)
	var origin := camera.project_ray_origin(press)
	var dir := camera.project_ray_normal(press)
	var grabbed := origin + dir * (-origin.y / dir.y)
	eye.pan_begin(press, false)
	assert_true(eye.is_panning())
	var motion := InputEventMouseMotion.new()
	motion.position = press + Vector2(120.0, 40.0)
	eye.pan_motion(motion)
	var under := camera.project_ray_origin(motion.position)
	var under_dir := camera.project_ray_normal(motion.position)
	var now := under + under_dir * (-under.y / under_dir.y)
	assert_almost_eq(now.x, grabbed.x, 0.01, "the grabbed ground point is still under the cursor")
	assert_almost_eq(now.z, grabbed.z, 0.01)
	eye.pan_end(false)
	assert_false(eye.is_panning())


func test_slide_motion_removes_only_the_part_into_the_wall() -> void:
	var wall := Vector2(0.0, -1.0)  # a wall facing -z
	assert_eq(EyeRig.slide_motion(Vector2(3.0, 4.0), wall), Vector2(3.0, 0.0), "slides along x")
	assert_eq(EyeRig.slide_motion(Vector2(0.0, 2.0), wall), Vector2.ZERO, "head on stops")
	assert_eq(EyeRig.slide_motion(Vector2(1.0, -2.0), wall), Vector2(1.0, -2.0), "leaving is free")
	assert_eq(EyeRig.slide_motion(Vector2(2.0, 0.0), wall), Vector2(2.0, 0.0), "along is free")
	assert_eq(EyeRig.slide_motion(Vector2(1.0, 1.0), Vector2.ZERO), Vector2.ZERO, "no normal: stop")
	var diagonal := Vector2(1.0, -1.0).normalized()
	var slid := EyeRig.slide_motion(Vector2(-1.0, 1.0) * 2.0, diagonal * 7.0)
	assert_almost_eq(slid.dot(diagonal), 0.0, 0.0001, "nothing left into a skew wall")
	assert_almost_eq(EyeRig.slide_motion(Vector2(-2.0, 0.0), diagonal).length(), 1.4142, 0.001)


func test_cast_steps_are_never_longer_than_the_radius() -> void:
	assert_eq(EyeRig.cast_step_count(0.0, 0.35), 0)
	assert_eq(EyeRig.cast_step_count(0.1, 0.35), 1)
	assert_eq(EyeRig.cast_step_count(0.35, 0.35), 1)
	assert_eq(EyeRig.cast_step_count(0.36, 0.35), 2)
	# 10 m/s at 20 fps is the worst frame anyone plays at: 0.5 m, two segments.
	assert_eq(EyeRig.cast_step_count(0.5, 0.35), 2)
	assert_eq(EyeRig.cast_step_count(20.0, 0.35), 58)
	for distance in [0.2, 0.7, 3.3, 20.0]:
		var n := EyeRig.cast_step_count(distance, 0.35)
		assert_lte(float(distance) / float(n), 0.35 + 0.00001)


func test_the_document_extent_is_the_walking_area_when_there_is_one() -> void:
	var doc := AABB(Vector3(-125.0, 0.0, -125.0), Vector3(250.0, 0.0, 250.0))
	var meshes := AABB(Vector3(-38.0, 0.0, -30.0), Vector3(76.0, 5.0, 60.0))
	assert_eq(EyeRig.walk_bounds(doc, meshes), doc)
	assert_eq(EyeRig.walk_bounds(AABB(), meshes), meshes, "no document: the orbit bounds")
	assert_eq(EyeRig.walk_bounds(AABB(), AABB()), AABB())
	var inside := EyeRig.clamp_foot(Vector2(500.0, -500.0), doc)
	assert_eq(inside, Vector2(123.5, -123.5), "1.5 m inside the document's edge")
	assert_eq(EyeRig.clamp_foot(Vector2(100.0, 100.0), doc), Vector2(100.0, 100.0), "the whole map")


func test_the_eye_walks_the_document_extent_not_the_mesh_bounds() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	eye.set_map_bounds(AABB(Vector3(-10.0, 0.0, -10.0), Vector3(20.0, 5.0, 20.0)))
	eye.frame_ground(Vector2(100.0, 0.0), 0.0)
	assert_almost_eq(eye.foot().x, 8.5, 0.0001, "held to the mesh bounds")
	eye.set_document_bounds(AABB(Vector3(-125.0, 0.0, -125.0), Vector3(250.0, 0.0, 250.0)))
	eye.frame_ground(Vector2(100.0, 0.0), 0.0)
	assert_almost_eq(eye.foot().x, 100.0, 0.0001, "the document's extent replaces them")
	eye.frame_ground(Vector2(400.0, 0.0), 0.0)
	assert_almost_eq(eye.foot().x, 123.5, 0.0001)
	eye.set_document_bounds(AABB())
	assert_almost_eq(eye.foot().x, 8.5, 0.0001, "no document: back to the orbit bounds")


func test_o_at_the_eye_leaves_it_and_toggles_top_down() -> void:
	var pitch_before := _controller.current_pitch()
	_controller.set_view_mode(_controller.eye)
	var key := InputEventKey.new()
	key.keycode = KEY_O
	key.pressed = true
	_controller._unhandled_key_input(key)
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "O leaves the eye")
	assert_eq(_camera().projection, Camera3D.PROJECTION_ORTHOGONAL)
	var pitch := _controller.view().pitch
	assert_almost_eq(pitch.pitch, pitch_before, 0.0001, "the orbit pitch was restored first")
	assert_almost_eq(pitch.target, CameraRig.TOP_DOWN_PITCH, 0.0001, "then it tilts top-down")
	_controller._unhandled_key_input(key)
	assert_almost_eq(pitch.target, pitch_before, 0.0001, "the next O goes back")


func test_a_shake_shows_in_the_eye_and_goes_when_it_ends() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	eye.process(0.016)
	var rest := _camera().global_position
	_controller._apply_shake_offset(Vector3(0.04, 0.0, -0.03))
	eye.process(0.016)
	assert_true(_camera().global_position.is_equal_approx(rest + Vector3(0.04, 0.0, -0.03)))
	assert_eq(eye.foot(), Vector2(rest.x, rest.z), "the foot itself is not moved by it")
	_controller._apply_shake_offset(Vector3.ZERO)
	eye.process(0.016)
	assert_true(_camera().global_position.is_equal_approx(rest))


func test_leaving_mid_shake_leaves_no_drift() -> void:
	var holder_before := _holder().global_position
	_controller.set_view_mode(_controller.eye)
	_controller._apply_shake_offset(Vector3(0.04, 0.0, 0.02))
	_controller.eye.process(0.016)
	_controller.set_view_mode(_controller.orbit_view())
	_controller._apply_shake_offset(Vector3.ZERO)
	assert_true(_holder().global_position.is_equal_approx(holder_before))


func test_the_eye_raises_antialiasing_to_4x_and_restores_the_setting() -> void:
	var viewport := _game_map.world_viewport
	_game_map.set_foliage_antialiasing_level(Viewport.MSAA_DISABLED)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	_controller.set_view_mode(_controller.eye)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X, "the eye is smoothed")
	_controller.set_view_mode(_controller.orbit_view())
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED, "the setting is back")
	_game_map.set_foliage_antialiasing_level(Viewport.MSAA_8X)
	_controller.set_view_mode(_controller.eye)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_8X, "a higher setting is kept")
	_game_map.set_foliage_antialiasing_level(Viewport.MSAA_2X)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X, "a settings change at the eye is raised too")
	_controller.set_view_mode(_controller.orbit_view())
	assert_eq(viewport.msaa_3d, Viewport.MSAA_2X)


func test_a_grab_on_the_sky_grabs_nothing() -> void:
	_controller.set_view_mode(_controller.eye)
	var eye := _controller.eye
	_controller.set_pitch_now(0.0)
	var vp := Vector2(_game_map.world_viewport.size)
	eye.pan_begin(vp * Vector2(0.5, 0.2), false)
	assert_false(eye.is_panning())
