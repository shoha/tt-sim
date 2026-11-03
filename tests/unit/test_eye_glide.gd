extends GutTest

## The glide between the orbit view and the eye (cards eyeentry and eyeglide): the pure maths in
## EyeGlideRig (the dolly curve, the field of view, the fog and far companions) and the glide on
## a real GameMap camera (a dolly down onto the eye and back, interrupted by any input at the
## exact target pose, the V key, the tilt past home).

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const FRAME := 1.0 / 60.0

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
	EyeGlide.enabled = true


func after_each() -> void:
	EyeGlide.enabled = true


func _camera() -> Camera3D:
	return _game_map.camera_node


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


## The field of view the plain eye gives the camera in this window.
func _eye_fov() -> float:
	var size := _game_map.world_viewport.size
	return EyeRig.corrected_fov(_controller.eye.fov_deg(), float(size.x) / float(size.y))


## Run the eye's process for `seconds` of 60 fps frames (the controller's _process calls it).
func _run(seconds: float) -> void:
	for _i in int(ceil(seconds / FRAME)):
		if _controller.view_mode() != _controller.eye:
			return
		_controller.eye.process(FRAME)


# --- EyeGlideRig: pure maths ---


func test_the_start_distance_is_the_hamlets_974_metres_at_two_degrees() -> void:
	assert_almost_eq(EyeGlideRig.start_distance(34.0), 973.9, 0.3, "the probe's 974 m")
	var d := EyeGlideRig.start_distance(34.0, 35.35)
	assert_almost_eq(d, 53.4, 0.3, "the hamlet's home camera framed at its own distance")


func test_distance_runs_from_the_start_to_the_eye_and_falls_all_the_way() -> void:
	var d0 := 974.0
	assert_almost_eq(EyeGlideRig.distance(0.0, d0), d0, 0.0001)
	assert_almost_eq(EyeGlideRig.distance(1.0, d0), 0.0, 0.0001, "exactly at the eye")
	var last := d0
	for i in range(1, 11):
		var d := EyeGlideRig.distance(float(i) / 10.0, d0)
		assert_lt(d, last, "falls at every step")
		last = d
	assert_almost_eq(EyeGlideRig.distance(2.0, d0), 0.0, 0.0001, "q is held to 1")


func test_progress_eases_in_and_out_and_is_held_to_the_glide() -> void:
	assert_eq(EyeGlideRig.progress(0.0), 0.0)
	assert_eq(EyeGlideRig.progress(1.0), 1.0)
	assert_almost_eq(EyeGlideRig.progress(0.5), 0.5, 0.0001)
	assert_eq(EyeGlideRig.progress(-1.0), 0.0)
	assert_eq(EyeGlideRig.progress(3.0), 1.0)
	assert_lt(EyeGlideRig.progress(0.1), 0.1, "slow start")
	assert_gt(EyeGlideRig.progress(0.9), 0.9, "slow end")


func test_the_field_of_view_keeps_the_pivot_plane_then_holds_the_lens() -> void:
	var v := 34.0
	assert_almost_eq(EyeGlideRig.fov(974.0, v, 60.0), 2.0, 0.01, "vanishing at the start")
	assert_almost_eq(EyeGlideRig.fov(53.3, v, 60.0), 35.35, 0.1, "the home camera's own framing")
	assert_eq(EyeGlideRig.fov(10.0, v, 60.0), 60.0, "held to the lens close in")
	assert_eq(EyeGlideRig.fov(0.0, v, 60.0), 60.0, "no division by zero at the eye")
	assert_almost_eq(EyeGlideRig.fov(29.4, v, 60.0), 60.0, 0.2, "the lens is reached at 29 m")
	assert_eq(EyeGlideRig.fov(974.0, v, 1.5), 1.5, "never wider than a narrower lens")


func test_the_companions_follow_the_distance() -> void:
	assert_eq(EyeGlideRig.fog_offset(0.0), 0.0, "the eye's own fog at the eye")
	assert_eq(EyeGlideRig.fog_offset(974.0), 974.0)
	assert_eq(EyeGlideRig.far_plane(0.0), EyeView.FAR_PLANE, "the eye's far plane at the eye")
	assert_eq(EyeGlideRig.far_plane(974.0), 1274.0, "d + 300 when far")
	assert_eq(EyeGlideRig.far_plane(200.0), 600.0)
	assert_eq(EyeGlideRig.NEAR, EyeView.NEAR_PLANE)


func test_the_pose_starts_on_the_home_axis_and_ends_exactly_at_the_eye() -> void:
	var home := CameraRig.camera_basis(CameraRig.screen_right(CameraRig.HOME_YAW), 21.6)
	var eye := CameraRig.camera_basis(CameraRig.screen_right(CameraRig.HOME_YAW), 6.0)
	var pivot := Vector3(-18.0, 0.0, -10.0)
	var eye_at := Vector3(-18.0, 1.6, -10.0)
	var start := EyeGlideRig.pose(0.0, home, pivot, eye, eye_at, 974.0)
	assert_true(start.basis.is_equal_approx(home))
	assert_true(start.origin.is_equal_approx(pivot + home.z * 974.0), "974 m back along the axis")
	var end := EyeGlideRig.pose(1.0, home, pivot, eye, eye_at, 974.0)
	assert_true(end.basis.is_equal_approx(eye), "the eye's basis")
	assert_true(end.origin.is_equal_approx(eye_at), "the eye's position, exactly")
	var mid := EyeGlideRig.pose(0.3, home, pivot, eye, eye_at, 974.0)
	assert_true(mid.basis.is_equal_approx(home), "the pitch has not started to turn before 0.45")


func test_the_fog_follows_the_camera_all_the_way_in_and_out() -> void:
	var d0 := EyeGlideRig.start_distance(34.0)
	for i in range(0, 11):
		var q := float(i) / 10.0
		var d := EyeGlideRig.distance(q, d0)
		assert_eq(EyeGlideRig.fog_offset(d), d, "the fog is measured from the pivot at q %.1f" % q)
		assert_gte(EyeGlideRig.far_plane(d), d + EyeGlideRig.FAR_MARGIN - 0.001, "the pivot is in range")
	assert_almost_eq(
		EyeGlideRig.fog_offset(EyeGlideRig.distance(1.0, d0)), 0.0, 0.0001, "the eye's own fog"
	)


func test_a_stalled_frame_slows_the_glide_instead_of_skipping_it() -> void:
	_controller.view().enter_street(false)
	var eye := _controller.eye
	eye.begin_glide_in()
	eye.process(1.0)  # a one second frame
	assert_true(eye.is_view_gliding(), "one long frame does not finish it")
	assert_almost_eq(
		eye.glide.fraction(), EyeGlideRig.MAX_STEP_SECONDS / EyeGlideRig.SECONDS, 0.0001
	)


# --- The glide on a real camera ---


func test_entering_starts_on_the_home_picture_and_lands_on_the_plain_eye() -> void:
	var camera := _camera()
	var home_basis := camera.global_basis
	_controller.view().enter_street()
	var eye := _controller.eye
	var pivot := Vector3(eye.foot().x, 0.0, eye.foot().y)
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	assert_true(eye.is_view_gliding())
	assert_eq(camera.projection, Camera3D.PROJECTION_PERSPECTIVE)
	assert_almost_eq(camera.fov, 2.0, 0.05, "a vanishing field of view")
	assert_true(camera.global_basis.is_equal_approx(home_basis), "the home view's direction")
	assert_gt(camera.global_position.distance_to(pivot), 100.0, "far back along the home axis")
	assert_almost_eq(eye.sky.fog_offset, eye.glide.distance(), 0.01, "the fog moved out with it")
	_run(EyeGlideRig.SECONDS * 0.5)
	assert_true(eye.is_view_gliding(), "still on its way at half time")
	assert_lt(eye.glide.distance(), 974.0)
	_run(EyeGlideRig.SECONDS * 0.6)
	assert_false(eye.is_view_gliding(), "landed")
	assert_true(camera.global_position.is_equal_approx(eye.eye_position()), "at the eye, exactly")
	assert_almost_eq(camera.fov, _eye_fov(), 0.0001)
	assert_almost_eq(camera.near, EyeView.NEAR_PLANE, 0.0001)
	assert_eq(camera.far, EyeView.FAR_PLANE)
	assert_eq(eye.sky.fog_offset, 0.0)


func test_a_glide_in_takes_the_whole_glide_seconds() -> void:
	_controller.view().enter_street()
	var frames := 0
	while _controller.eye.is_view_gliding() and frames < 1000:
		_controller.eye.process(FRAME)
		frames += 1
	assert_almost_eq(float(frames) * FRAME, EyeGlideRig.SECONDS, 0.04)


func test_input_ends_a_glide_in_at_the_eye_and_leaves_nothing_stuck() -> void:
	var camera := _camera()
	_controller.view().enter_street()
	var eye := _controller.eye
	_run(0.4)
	assert_true(eye.is_view_gliding())
	_controller._unhandled_key_input(_key(KEY_W))
	assert_false(eye.is_view_gliding(), "a key ends it")
	assert_true(camera.global_position.is_equal_approx(eye.eye_position()), "at the target pose")
	assert_almost_eq(camera.fov, _eye_fov(), 0.0001)
	assert_eq(camera.far, EyeView.FAR_PLANE)
	assert_eq(eye.sky.fog_offset, 0.0)
	assert_eq(_controller.view_mode().mode_name(), &"eye", "and the eye is the view")
	# A pan does the same, the wheel too.
	_controller.view().leave_street(false)
	_controller.view().enter_street()
	eye.pan_begin(Vector2(100.0, 100.0), false)
	assert_false(eye.is_view_gliding(), "a pan ends it")
	eye.pan_cancel()
	_controller.view().leave_street(false)
	_controller.view().enter_street()
	_controller.zoom_in_step()
	assert_false(eye.is_view_gliding(), "the wheel ends it")


func test_leaving_glides_back_and_lands_on_the_orbit_pose() -> void:
	var camera := _camera()
	var holder_before := _game_map.cameraholder_node.global_position
	var position_before := camera.position
	var basis_before := camera.basis
	var size_before := camera.size
	var far_before := camera.far
	_controller.view().enter_street(false)
	var eye := _controller.eye
	assert_false(eye.is_view_gliding(), "unsmooth: at once")
	assert_true(camera.global_position.is_equal_approx(eye.eye_position()))
	_controller.view().leave_street()
	assert_eq(_controller.view_mode().mode_name(), &"eye", "the eye stays the view while it climbs")
	assert_true(eye.is_view_gliding())
	assert_true(camera.global_position.is_equal_approx(eye.eye_position()), "frame one: the eye")
	_run(EyeGlideRig.SECONDS * 0.5)
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_run(EyeGlideRig.SECONDS * 0.6)
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "the orbit takes over last")
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(camera.size, size_before, 0.0001)
	assert_almost_eq(camera.far, far_before, 0.0001)
	assert_true(camera.position.is_equal_approx(position_before))
	assert_true(camera.basis.is_equal_approx(basis_before))
	assert_true(_game_map.cameraholder_node.global_position.is_equal_approx(holder_before))


func test_input_ends_a_glide_out_at_the_orbit_view() -> void:
	var camera := _camera()
	var position_before := camera.position
	_controller.view().enter_street(false)
	_controller.view().leave_street()
	_run(0.3)
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_controller._unhandled_key_input(_key(KEY_W))
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "a key lands it")
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_true(camera.position.is_equal_approx(position_before))
	assert_false(_controller.eye.is_view_gliding())


func test_v_and_f9_toggle_with_a_glide_and_a_second_press_only_lands_it() -> void:
	_controller._unhandled_key_input(_key(KEY_V))
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	assert_true(_controller.eye.is_view_gliding())
	_controller._unhandled_key_input(_key(KEY_V))
	assert_false(_controller.eye.is_view_gliding(), "V in flight lands it, it does not reverse")
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_controller._unhandled_key_input(_key(KEY_V))
	assert_true(_controller.eye.is_view_gliding(), "V at the eye climbs")
	_controller._unhandled_key_input(_key(KEY_F9))
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "F9 mid-climb lands it at the orbit")
	_controller._unhandled_key_input(_key(KEY_F9))
	assert_eq(_controller.view_mode().mode_name(), &"eye", "and F9 works as before")


func test_the_settings_and_reduced_motion_make_the_change_instant() -> void:
	EyeGlide.enabled = false
	assert_false(EyeGlide.allowed())
	_controller._unhandled_key_input(_key(KEY_V))
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	assert_false(_controller.eye.is_view_gliding(), "off: the plain switch")
	_controller._unhandled_key_input(_key(KEY_V))
	assert_eq(_controller.view_mode().mode_name(), &"orbit")


func test_tilting_flatter_past_home_steps_down_to_the_street() -> void:
	var view := _controller.view()
	assert_almost_eq(view.pitch.target, CameraRig.MIN_PITCH, 0.0001, "the scene starts at home")
	view.tilt_by(CameraCompass.TILT_STEP)
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "steeper stays in the orbit")
	view.tilt_by(-CameraCompass.TILT_STEP)
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "back to home, not past it")
	view.pitch.set_now(CameraRig.MIN_PITCH)
	view.tilt_by(-CameraCompass.TILT_STEP)
	assert_eq(_controller.view_mode().mode_name(), &"eye", "flatter than home: the street")
	assert_true(_controller.eye.is_view_gliding())


func test_an_alt_drag_pulled_past_home_steps_down_only_after_the_pull() -> void:
	var view := _controller.view()
	view.begin_orbit()
	view.orbit_by(Vector2(0.0, -CameraRig.STREET_PULL_DEG * 0.5))
	assert_eq(_controller.view_mode().mode_name(), &"orbit", "a nudge does not")
	view.orbit_by(Vector2(0.0, -CameraRig.STREET_PULL_DEG * 0.6))
	assert_eq(_controller.view_mode().mode_name(), &"eye", "a pull of 8 degrees does")
	assert_false(view.orbiting, "and the drag ended")


func test_authoring_never_steps_down() -> void:
	_game_map.authoring_mode = true
	var view := _controller.view()
	view.tilt_by(-CameraCompass.TILT_STEP)
	_controller._unhandled_key_input(_key(KEY_V))
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	_game_map.authoring_mode = false


func test_the_steepest_look_down_climbs_back_up() -> void:
	_controller.view().enter_street(false)
	var view := _controller.view()
	view.pitch.set_now(EyeRig.PITCH_MAX)
	view.tilt_by(CameraCompass.TILT_STEP)
	assert_true(_controller.eye.is_view_gliding(), "climbing")
	_run(EyeGlideRig.SECONDS + 0.1)
	assert_eq(_controller.view_mode().mode_name(), &"orbit")


func test_home_at_the_eye_climbs_and_then_goes_home() -> void:
	_controller.view().enter_street(false)
	_controller.eye.reset_home()
	assert_true(_controller.eye.is_view_gliding())
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_run(EyeGlideRig.SECONDS + 0.1)
	assert_eq(_controller.view_mode().mode_name(), &"orbit")


func test_leaving_by_setup_authoring_ends_the_glide() -> void:
	_controller.view().enter_street()
	_run(0.3)
	_controller.leave_eye()
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	assert_false(_controller.eye.is_view_gliding())
	assert_eq(_camera().projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_eq(_controller.eye.sky.fog_offset, 0.0)
