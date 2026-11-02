extends GutTest

## The camera rig's pitch and Alt + drag orbit: the pure maths (CameraRig, CameraPitch), the
## decision functions for the gesture and keys, and the controller wired to the real GameMap
## scene: the pivot fixed at every pitch, the clamp, the near-plane hold, W and A covering the
## same screen distance at every pitch (keyboard and edge pan), the top-down round trip, Home
## restoring pitch and yaw, and the gesture through GameMap's own input.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const W_LOCAL := Vector3(-1.0, 0.0, -1.0)
const A_LOCAL := Vector3(-1.0, 0.0, 1.0)
const PITCHES := [21.6, 35.0, 50.0, 70.0, 90.0]

var _game_map: GameMap


func before_each() -> void:
	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	_game_map = GAME_MAP_SCENE.instantiate()
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	controller.setup(_game_map)
	_game_map.setup(controller)


func _pivot(cc: CameraController) -> Vector3:
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	var holder := _game_map.cameraholder_node.global_position
	return Vector3(holder.x + off.x, 0.0, holder.z + off.y)


func _key(code: Key, alt: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.alt_pressed = alt
	return event


func _button(pressed: bool, alt: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.alt_pressed = alt
	return event


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event


func _rest(cc: CameraController) -> int:
	var frames := 0
	while not cc.is_at_rest() and frames < 300:
		await get_tree().process_frame
		frames += 1
	return frames


# --- pure maths ---


func test_pitch_is_held_to_home_and_straight_down() -> void:
	assert_almost_eq(CameraRig.clamp_pitch(5.0), 21.6, 0.0001)
	assert_almost_eq(CameraRig.clamp_pitch(55.0), 55.0, 0.0001)
	assert_almost_eq(CameraRig.clamp_pitch(120.0), 90.0, 0.0001)


func test_the_home_basis_is_the_scenes_own_camera_pose() -> void:
	var basis := CameraRig.camera_basis(Vector3(0.7071068, 0.0, -0.7071068), CameraRig.HOME_PITCH)
	assert_almost_eq(basis.y.y, 0.9297765, 0.0001)
	assert_almost_eq(basis.z.y, 0.36812454, 0.0001)
	assert_almost_eq(basis.z.x, 0.6574513, 0.0001)
	assert_almost_eq(CameraRig.pitch_of_back_y(0.36812454), 21.6, 0.001)


func test_straight_down_has_no_gimbal() -> void:
	var right := Vector3(0.7071068, 0.0, -0.7071068)
	var basis := CameraRig.camera_basis(right, 90.0)
	assert_almost_eq(basis.z.y, 1.0, 0.00001, "back is straight up")
	var up_dot := basis.y.dot(CameraRig.screen_up(45.0))
	assert_almost_eq(up_dot, 1.0, 0.0001, "screen-up keeps the home heading")
	assert_almost_eq(basis.x.dot(basis.y), 0.0, 0.0001)
	assert_almost_eq(basis.determinant(), 1.0, 0.0001)


func test_the_pitched_offset_keeps_its_length_and_side() -> void:
	var right := Vector3(0.7071068, 0.0, -0.7071068)
	var home := Vector3(11.088, 8.0, 11.088)
	for pitch in PITCHES:
		var offset := CameraRig.pitched_offset(home, right, pitch)
		assert_almost_eq(offset.length(), home.length(), 0.001, "length at %.1f" % pitch)
		assert_almost_eq(offset.dot(right), home.dot(right), 0.001, "sideways at %.1f" % pitch)
	assert_true(CameraRig.pitched_offset(home, right, CameraRig.HOME_PITCH).is_equal_approx(home))


func test_the_top_down_key_goes_down_and_back() -> void:
	assert_almost_eq(CameraRig.top_down_target(21.6, 21.6), 90.0, 0.0001)
	assert_almost_eq(CameraRig.top_down_target(90.0, 50.0), 50.0, 0.0001, "back to where it was")
	assert_almost_eq(CameraRig.top_down_target(90.0, 90.0), 21.6, 0.0001, "never back to steep")


func test_the_pitch_state_toggles_and_returns() -> void:
	var state := CameraPitch.new()
	state.set_now(50.0)
	state.toggle_top_down()
	assert_almost_eq(state.target, 90.0, 0.0001)
	var last := state.pitch
	var frames := 0
	while state.is_easing() and frames < 100:
		state.step(1.0 / 60.0)
		assert_gte(state.pitch, last - 0.0001, "the ease never turns back")
		last = state.pitch
		frames += 1
	assert_almost_eq(state.pitch, 90.0, 0.0001)
	assert_almost_eq(frames / 60.0, CameraRig.TILT_SECONDS, 0.05, "about half a second")
	state.toggle_top_down()
	assert_almost_eq(state.target, 50.0, 0.0001, "the second press returns")
	state.reset_home()
	assert_almost_eq(state.target, 21.6, 0.0001)


func test_home_forgets_the_pitch_to_return_to() -> void:
	var state := CameraPitch.new()
	state.set_now(60.0)
	state.toggle_top_down()
	state.reset_home()
	state.set_now(90.0)
	state.toggle_top_down()
	assert_almost_eq(state.target, 21.6, 0.0001)


func test_a_drag_down_tilts_higher_and_a_drag_right_turns_left() -> void:
	var change := CameraRig.orbit_delta(Vector2(100.0, 100.0))
	assert_almost_eq(change.x, -30.0, 0.0001, "yaw falls dragging right")
	assert_almost_eq(change.y, 20.0, 0.0001, "pitch rises dragging down")


func test_the_orbit_begins_only_on_a_free_alt_left_press() -> void:
	var none := CameraRig.Orbit.NONE
	assert_eq(CameraRig.orbit_action(_button(true), false, false, false), CameraRig.Orbit.BEGIN)
	assert_eq(CameraRig.orbit_action(_button(true, false), false, false, false), none, "no Alt")
	assert_eq(CameraRig.orbit_action(_button(true), false, true, false), none, "over the UI")
	assert_eq(CameraRig.orbit_action(_button(true), false, false, true), none, "a token drag runs")
	var ctrl := _button(true)
	ctrl.ctrl_pressed = true
	assert_eq(CameraRig.orbit_action(ctrl, false, false, false), none, "Ctrl+Alt is another chord")


func test_the_orbit_moves_and_ends_wherever_the_pointer_is() -> void:
	assert_eq(CameraRig.orbit_action(_motion(Vector2.ONE), true, true, true), CameraRig.Orbit.MOVE)
	assert_eq(CameraRig.orbit_action(_motion(Vector2.ONE), false, false, false), CameraRig.Orbit.NONE)
	assert_eq(CameraRig.orbit_action(_button(false, false), true, true, false), CameraRig.Orbit.END)
	assert_eq(CameraRig.orbit_action(_button(false), false, false, false), CameraRig.Orbit.NONE)


func test_o_is_the_top_down_key_only_bare() -> void:
	assert_true(CameraRig.is_top_down_key(_key(KEY_O)))
	assert_false(CameraRig.is_top_down_key(_key(KEY_O, true)), "Alt+O is not")
	assert_false(CameraRig.is_top_down_key(_key(KEY_P)))
	var echo := _key(KEY_O)
	echo.echo = true
	assert_false(CameraRig.is_top_down_key(echo), "held key repeats do not toggle")


func test_edge_pan_waits_for_alt_or_an_orbit() -> void:
	assert_true(CameraRig.edge_pan_paused(true, false))
	assert_true(CameraRig.edge_pan_paused(false, true))
	assert_false(CameraRig.edge_pan_paused(false, false))


func test_the_token_marker_fades_in_between_55_and_70_degrees() -> void:
	assert_eq(CameraRig.marker_strength(21.6), 0.0)
	assert_eq(CameraRig.marker_strength(50.0), 0.0)
	assert_between(CameraRig.marker_strength(62.0), 0.2, 0.8)
	assert_eq(CameraRig.marker_strength(70.0), 1.0)
	assert_eq(CameraRig.marker_strength(90.0), 1.0)


# --- the controller on the real scene ---


func test_the_pivot_stays_put_at_every_pitch() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	for pitch in PITCHES + [60.0, 21.6]:
		cc.set_pitch_now(pitch)
		var now := _pivot(cc)
		assert_almost_eq(now.x, pivot.x, 0.001, "pivot x at %.1f" % pitch)
		assert_almost_eq(now.z, pivot.z, 0.001, "pivot z at %.1f" % pitch)
		var back := _game_map.camera_node.global_basis.z.normalized()
		assert_almost_eq(back.y, sin(deg_to_rad(pitch)), 0.0001, "elevation at %.1f" % pitch)


func test_the_pivot_stays_put_through_pitch_and_yaw_together() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	cc.set_pitch_now(60.0)
	cc.set_yaw_now(200.0)
	cc.set_pitch_now(90.0)
	cc.set_yaw_now(315.0)
	var now := _pivot(cc)
	assert_almost_eq(now.x, pivot.x, 0.002)
	assert_almost_eq(now.z, pivot.z, 0.002)


func test_the_pitch_is_clamped_to_the_range() -> void:
	var cc := _game_map.get_camera_controller()
	cc.set_pitch_now(5.0)
	assert_almost_eq(cc.current_pitch(), 21.6, 0.0001)
	cc.set_pitch_now(200.0)
	assert_almost_eq(cc.current_pitch(), 90.0, 0.0001)


func test_home_pitch_is_the_scenes_exact_pose() -> void:
	var cc := _game_map.get_camera_controller()
	var cam := _game_map.camera_node
	var basis := cam.basis
	var base: Vector3 = cc.get("_base_camera_offset")
	cc.set_pitch_now(70.0)
	assert_false(cam.basis.is_equal_approx(basis))
	assert_false((cc.get("_base_camera_offset") as Vector3).is_equal_approx(base))
	cc.set_pitch_now(21.6)
	assert_true(cam.basis.is_equal_approx(basis), "the basis is the scene's again")
	assert_true((cc.get("_base_camera_offset") as Vector3).is_equal_approx(base), "and the offset")


func test_the_near_plane_holds_over_canopies_at_every_pitch() -> void:
	var cc := _game_map.get_camera_controller()
	var size := Vector2(_game_map.world_viewport.size)
	for pitch in PITCHES:
		cc.set_pitch_now(pitch)
		var origin: float = cc.call("_bottom_ray_origin_y", size)
		assert_gte(origin, CameraController.CANOPY_CLEARANCE - 0.01, "canopy clearance at %.1f" % pitch)


func test_the_whole_map_fit_follows_the_basis() -> void:
	var cc := _game_map.get_camera_controller()
	var home := _game_map.fit_zoom_for_extent(Vector2(60.0, 60.0), 12.0)
	cc.set_pitch_now(90.0)
	var down := _game_map.fit_zoom_for_extent(Vector2(60.0, 60.0), 12.0)
	assert_gt(down, home, "a square map seen from above needs a wider view")
	var fired := [0]
	cc.view_tilted.connect(func(_p: float) -> void: fired[0] += 1)
	cc.view().set_pitch_target(40.0)
	await _rest(cc)
	assert_gt(fired[0], 3, "the fit hears every frame of a tilt")


## Runs `step` (one 1/60 s frame of a pan) for 48 frames from rest and returns the steady speed
## over the last 12 as (ground metres a second, picture heights a second): the holder's move
## measured on the ground and in the camera's own plane against the camera size.
func _pan_speed(cc: CameraController, step: Callable) -> Vector2:
	var holder := _game_map.cameraholder_node
	var cam := _game_map.camera_node
	var start := holder.global_position
	cc.set("_camera_velocity", Vector3.ZERO)
	cc.set("_current_edge_pan", Vector2.ZERO)
	for i in 36:
		step.call()
	var mid := holder.global_position
	for i in 12:
		step.call()
	var moved := holder.global_position - mid
	cc.set("_camera_move_dir", Vector3.ZERO)
	cc.set("_camera_velocity", Vector3.ZERO)
	holder.global_position = start
	var on_screen := Vector2(moved.dot(cam.global_basis.x), moved.dot(cam.global_basis.y))
	return Vector2(moved.length(), on_screen.length() / cam.size) / 0.2


func test_w_and_a_cover_the_same_screen_distance_at_every_pitch() -> void:
	var cc := _game_map.get_camera_controller()
	for pitch in PITCHES:
		cc.set_pitch_now(pitch)
		cc.set("_camera_move_dir", W_LOCAL)
		var w := _pan_speed(cc, func() -> void: (cc.view_mode() as OrbitView).handle_movement(1.0 / 60.0))
		cc.set("_camera_move_dir", A_LOCAL)
		var a := _pan_speed(cc, func() -> void: (cc.view_mode() as OrbitView).handle_movement(1.0 / 60.0))
		assert_almost_eq(w.y / a.y, 1.0, 0.03, "W against A at %.1f" % pitch)
		assert_almost_eq(a.x, 14.14, 0.1, "A is 10 m/s a key, 14.1 on the diagonal axis")
		assert_almost_eq(w.x, a.x / sin(deg_to_rad(pitch)), 0.2, "W's ground speed is 1 / sin(pitch)")


func test_edge_pan_shares_the_pitch_rule() -> void:
	var cc := _game_map.get_camera_controller()
	var dnd := _game_map.drag_and_drop_node
	var subject := Node.new()
	(dnd.get("_state") as DragState).begin(subject)
	assert_true(dnd.is_dragging())
	for pitch in PITCHES:
		cc.set_pitch_now(pitch)
		var speeds := []
		for direction in [Vector2(0.0, -1.0), Vector2(1.0, 0.0)]:
			dnd.edge_pan_direction = direction
			speeds.append(_pan_speed(cc, func() -> void: cc.call("_handle_edge_pan", 1.0 / 60.0)))
		assert_gt(speeds[0].x, 1.0, "the edge pan moves")
		var ratio: float = speeds[0].y / speeds[1].y
		assert_almost_eq(ratio, 1.0, 0.03, "edge pan up against right at %.1f" % pitch)
	(dnd.get("_state") as DragState).finish()
	subject.free()


func test_o_toggles_top_down_and_back() -> void:
	var cc := _game_map.get_camera_controller()
	cc.set_pitch_now(50.0)
	cc.call("_unhandled_key_input", _key(KEY_O))
	assert_true(cc.is_turning())
	assert_false(cc.is_at_rest())
	await _rest(cc)
	assert_almost_eq(cc.current_pitch(), 90.0, 0.0001)
	cc.call("_unhandled_key_input", _key(KEY_O))
	await _rest(cc)
	assert_almost_eq(cc.current_pitch(), 50.0, 0.0001, "the second O returns")


func test_the_tilt_ease_never_moves_the_pivot() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	cc.view().toggle_top_down()
	var frames := 0
	while cc.is_turning() and frames < 120:
		await get_tree().process_frame
		var now := _pivot(cc)
		assert_almost_eq(now.x, pivot.x, 0.01, "pivot x mid-tilt")
		assert_almost_eq(now.z, pivot.z, 0.01, "pivot z mid-tilt")
		frames += 1
	assert_almost_eq(cc.current_pitch(), 90.0, 0.0001)


func test_home_restores_pitch_yaw_and_zoom() -> void:
	var cc := _game_map.get_camera_controller()
	var cam := _game_map.camera_node
	var basis := cam.basis
	var pivot := _pivot(cc)
	cc.set_pitch_now(75.0)
	cc.set_yaw_now(250.0)
	cc.adjust_zoom(-3.0)
	cc.call("_reset_camera_to_home")
	assert_false(cc.is_at_rest())
	var frames := await _rest(cc)
	assert_lt(frames, 300, "Home comes to rest")
	assert_almost_eq(cc.current_pitch(), 21.6, 0.0001)
	assert_almost_eq(cc.current_yaw(), CameraRig.HOME_YAW, 0.0001)
	assert_true(cam.basis.is_equal_approx(basis))
	var now := _pivot(cc)
	assert_almost_eq(now.x, pivot.x, 0.05, "Home glides back to the same ground point")
	assert_almost_eq(now.z, pivot.z, 0.05)


func test_alt_drag_through_the_game_map_tilts_and_orbits() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	_game_map._input(_button(true))
	assert_true(cc.view().orbiting, "Alt + left press begins")
	_game_map._input(_motion(Vector2(0.0, 100.0)))
	assert_almost_eq(cc.current_pitch(), 41.6, 0.0001, "100 px down is 20 degrees steeper")
	_game_map._input(_motion(Vector2(-100.0, 0.0)))
	assert_almost_eq(cc.current_yaw(), 75.0, 0.0001, "100 px left turns the yaw up 30 degrees")
	_game_map._input(_motion(Vector2(0.0, -1000.0)))
	assert_almost_eq(cc.current_pitch(), 21.6, 0.0001, "clamped at home")
	var now := _pivot(cc)
	assert_almost_eq(now.x, pivot.x, 0.002)
	assert_almost_eq(now.z, pivot.z, 0.002)
	_game_map._input(_button(false, false))
	assert_false(cc.view().orbiting, "the release ends it")
	assert_false(cc.is_turning())
	assert_almost_eq(cc.current_yaw(), 75.0, 0.0001, "the yaw stays free between snaps")


func test_q_snaps_from_a_free_yaw_to_the_next_snap() -> void:
	var cc := _game_map.get_camera_controller()
	cc.set_yaw_now(100.0)
	cc.turn_view(1)
	await _rest(cc)
	assert_almost_eq(cc.current_yaw(), 135.0, 0.0001)
	cc.set_yaw_now(100.0)
	cc.turn_view(-1)
	await _rest(cc)
	assert_almost_eq(cc.current_yaw(), 45.0, 0.0001)


func test_alt_press_with_another_drag_running_does_not_orbit() -> void:
	var cc := _game_map.get_camera_controller()
	var dnd := _game_map.drag_and_drop_node
	var subject := Node.new()
	(dnd.get("_state") as DragState).begin(subject)
	_game_map._input(_button(true))
	assert_false(cc.view().orbiting, "a token drag owns the mouse")
	(dnd.get("_state") as DragState).finish()
	subject.free()
