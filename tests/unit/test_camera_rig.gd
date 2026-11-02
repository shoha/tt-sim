extends GutTest

## The camera rig's yaw: the pure maths (CameraRig, CameraYaw) and the controller wired to the
## real GameMap scene (as test_camera_rest.gd wires it): snap targets from any yaw, wrap-around,
## the pan axes at all four yaws, the pivot ground point staying put through a turn, Home
## restoring the yaw, and the keys that turn the view.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const W_LOCAL := Vector3(-1.0, 0.0, -1.0)

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


func _key(code: Key, alt: bool = false, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.alt_pressed = alt
	event.ctrl_pressed = ctrl
	return event


# --- pure maths ---


func test_wrap_deg_reads_any_yaw_in_0_to_360() -> void:
	assert_almost_eq(CameraRig.wrap_deg(405.0), 45.0, 0.0001)
	assert_almost_eq(CameraRig.wrap_deg(-45.0), 315.0, 0.0001)
	assert_almost_eq(CameraRig.wrap_deg(720.0), 0.0, 0.0001)


func test_shortest_turn_never_goes_the_long_way() -> void:
	assert_almost_eq(CameraRig.shortest_turn(315.0, 45.0), 90.0, 0.0001)
	assert_almost_eq(CameraRig.shortest_turn(45.0, 315.0), -90.0, 0.0001)
	assert_almost_eq(CameraRig.shortest_turn(45.0, 225.0), 180.0, 0.0001)
	assert_almost_eq(CameraRig.shortest_turn(405.0, 45.0), 0.0, 0.0001)


func test_snap_target_from_a_snap_is_the_next_one() -> void:
	assert_almost_eq(CameraRig.snap_target(45.0, 1), 135.0, 0.0001)
	assert_almost_eq(CameraRig.snap_target(45.0, -1), -45.0, 0.0001)
	assert_almost_eq(CameraRig.snap_target(315.0, 1), 405.0, 0.0001)
	assert_almost_eq(CameraRig.wrap_deg(CameraRig.snap_target(315.0, 1)), 45.0, 0.0001)


func test_snap_target_between_snaps_lands_on_the_snap_in_that_direction() -> void:
	assert_almost_eq(CameraRig.snap_target(100.0, 1), 135.0, 0.0001)
	assert_almost_eq(CameraRig.snap_target(100.0, -1), 45.0, 0.0001)
	assert_almost_eq(CameraRig.snap_target(0.0, 1), 45.0, 0.0001)
	assert_almost_eq(CameraRig.snap_target(359.0, -1), 315.0, 0.0001)
	assert_almost_eq(CameraRig.nearest_snap(100.0), 135.0, 0.0001)
	assert_almost_eq(CameraRig.nearest_snap(80.0), 45.0, 0.0001)


func test_rotate_about_pivot_keeps_the_distance_the_height_and_the_pivot() -> void:
	var pivot := Vector3(3.0, 0.0, -2.0)
	var start := Vector3(14.0, 8.0, 9.0)
	for deg in [90.0, 180.0, -90.0, 33.0]:
		var moved := CameraRig.rotate_about_pivot(start, pivot, deg)
		assert_almost_eq(moved.y, start.y, 0.0001)
		assert_almost_eq(
			Vector2(moved.x - pivot.x, moved.z - pivot.z).length(),
			Vector2(start.x - pivot.x, start.z - pivot.z).length(),
			0.0001
		)
	var quarter := CameraRig.rotate_about_pivot(start, pivot, 90.0)
	# A quarter turn about +Y takes (x, z) to (z, -x), as the holder basis does.
	assert_almost_eq(quarter.x - pivot.x, start.z - pivot.z, 0.0001)
	assert_almost_eq(quarter.z - pivot.z, -(start.x - pivot.x), 0.0001)
	assert_eq(CameraRig.rotate_about_pivot(pivot, pivot, 90.0), pivot)


func test_pan_forward_points_away_from_the_viewer_at_every_yaw() -> void:
	for yaw in [45.0, 135.0, 225.0, 315.0]:
		var w := CameraRig.pan_direction(yaw, W_LOCAL.normalized())
		assert_almost_eq(w.dot(CameraRig.screen_up(yaw)), 1.0, 0.0001, "W at yaw %d" % yaw)
		var d := CameraRig.pan_direction(yaw, Vector3(1.0, 0.0, -1.0).normalized())
		assert_almost_eq(d.dot(CameraRig.screen_right(yaw)), 1.0, 0.0001, "D at yaw %d" % yaw)
	# At home, screen-up is the legacy world (-1, 0, -1).
	assert_almost_eq(CameraRig.screen_up(45.0).x, -sqrt(0.5), 0.0001)
	assert_almost_eq(CameraRig.screen_up(45.0).z, -sqrt(0.5), 0.0001)


func test_vertical_pan_factor_matches_the_foreshortening() -> void:
	assert_almost_eq(CameraRig.vertical_pan_factor(sin(deg_to_rad(21.6))), 2.717, 0.01)
	assert_almost_eq(CameraRig.vertical_pan_factor(1.0), 1.0, 0.0001)
	assert_almost_eq(CameraRig.vertical_pan_factor(0.0), 1.0 / CameraRig.MIN_BACK_Y, 0.0001)


func test_the_north_wedge_turns_with_the_yaw() -> void:
	assert_almost_eq(CameraRig.north_angle(45.0), PI / 4.0, 0.0001)
	assert_almost_eq(CameraRig.north_angle(135.0), 3.0 * PI / 4.0, 0.0001)


func test_the_peak_turn_per_frame_of_a_snap() -> void:
	var at_30 := CameraRig.peak_degrees_per_frame(90.0, CameraRig.TURN_SECONDS, 30.0)
	var at_60 := CameraRig.peak_degrees_per_frame(90.0, CameraRig.TURN_SECONDS, 60.0)
	assert_almost_eq(at_60 * 2.0, at_30, 0.0001)
	assert_between(at_60, 6.0, 7.0, "about 6.4 degrees a frame at 60 Hz")


func test_turn_seconds_grow_with_the_angle() -> void:
	assert_almost_eq(CameraRig.turn_seconds(90.0), CameraRig.TURN_SECONDS, 0.0001)
	assert_gt(CameraRig.turn_seconds(180.0), CameraRig.turn_seconds(90.0))


# --- keys ---


func test_q_e_and_brackets_turn_the_view_while_no_brush_is_out() -> void:
	assert_eq(CameraRig.event_turn(_key(KEY_Q), false), -1)
	assert_eq(CameraRig.event_turn(_key(KEY_E), false), 1)
	assert_eq(CameraRig.event_turn(_key(KEY_BRACKETLEFT), false), -1)
	assert_eq(CameraRig.event_turn(_key(KEY_BRACKETRIGHT), false), 1)
	assert_eq(CameraRig.event_turn(_key(KEY_Q, true), false), 0, "Alt+Q is not the free mapping")


func test_with_a_brush_out_q_e_are_the_brushs_and_alt_turns_the_view() -> void:
	assert_eq(CameraRig.event_turn(_key(KEY_Q), true), 0)
	assert_eq(CameraRig.event_turn(_key(KEY_E), true), 0)
	assert_eq(CameraRig.event_turn(_key(KEY_E, true), true), 1)
	assert_eq(CameraRig.event_turn(_key(KEY_Q, true), true), -1)
	assert_eq(CameraRig.event_turn(_key(KEY_BRACKETRIGHT), true), 0, "] is the brush size")
	assert_eq(CameraRig.event_turn(_key(KEY_E, false, true), false), 0, "Ctrl+E is someone else's")


func test_a_brush_leaves_alt_q_e_alone() -> void:
	# The reason Alt+Q / Alt+E can turn the view under a brush.
	assert_eq(BrushTool.decide(_key(KEY_E, true), true, false, false), BrushTool.Action.NONE)
	assert_eq(BrushTool.decide(_key(KEY_Q, true), true, false, false), BrushTool.Action.NONE)


func test_the_hint_chip_names_the_live_mapping() -> void:
	assert_eq(CameraRig.turn_hint(false).key, "Q E")
	assert_eq(CameraRig.turn_hint(true).key, "Alt + Q E")
	assert_has(InputHints.KEPT_WITH_A_TOOL, CameraRig.turn_hint(true).key)


# --- CameraYaw ---


func test_yaw_eases_to_the_next_snap_and_lands_wrapped() -> void:
	var yaw := CameraYaw.new()
	yaw.turn(1)
	assert_true(yaw.is_turning())
	var total := 0.0
	var frames := 0
	while yaw.is_turning() and frames < 200:
		total += yaw.step(1.0 / 60.0)
		frames += 1
	assert_almost_eq(total, 90.0, 0.001, "the steps add up to the snap")
	assert_almost_eq(yaw.yaw, 135.0, 0.001)
	yaw.land()
	assert_eq(yaw.target, 135.0)
	yaw.turn(1)
	yaw.turn(1)
	assert_almost_eq(yaw.target, 315.0, 0.0001, "presses made mid-turn add up")
	yaw.turn(1)
	yaw.step(10.0)
	yaw.land()
	assert_almost_eq(yaw.yaw, 45.0, 0.0001, "405 lands as 45")


func test_no_frame_of_a_snap_turns_more_than_the_ease_allows() -> void:
	var yaw := CameraYaw.new()
	yaw.turn(1)
	var worst := 0.0
	while yaw.is_turning():
		worst = maxf(worst, absf(yaw.step(1.0 / 30.0)))
	var limit := CameraRig.peak_degrees_per_frame(90.0, CameraRig.TURN_SECONDS, 30.0)
	assert_lte(worst, limit + 0.01)
	assert_gt(worst, limit * 0.8, "the 30 fps peak is about %.1f degrees" % limit)


# --- the controller on the real scene ---


func test_a_snap_keeps_the_ground_point_under_the_screen_centre() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	for expected in [135.0, 225.0, 315.0, 45.0]:
		cc.set_yaw_now(expected)
		assert_almost_eq(cc.current_yaw(), expected, 0.0001)
		var now := _pivot(cc)
		assert_almost_eq(now.x, pivot.x, 0.001, "pivot x at yaw %d" % expected)
		assert_almost_eq(now.z, pivot.z, 0.001, "pivot z at yaw %d" % expected)
		var back := _game_map.camera_node.global_basis.z
		var bearing := Vector2(sin(deg_to_rad(expected)), cos(deg_to_rad(expected)))
		assert_almost_eq(
			Vector2(back.x, back.z).normalized().angle_to(bearing),
			0.0,
			0.001,
			"the camera stands on the %d degree bearing" % expected
		)


func test_an_eased_turn_never_moves_the_pivot_and_ends_on_the_snap() -> void:
	var cc := _game_map.get_camera_controller()
	var pivot := _pivot(cc)
	var landed := [false]
	cc.view_turned.connect(func(_yaw: float) -> void: landed[0] = true)
	cc.turn_view(1)
	assert_true(cc.is_turning())
	assert_false(cc.is_at_rest(), "a turn is not rest")
	var frames := 0
	while cc.is_turning() and frames < 120:
		await get_tree().process_frame
		var now := _pivot(cc)
		assert_almost_eq(now.x, pivot.x, 0.01, "pivot x mid-turn")
		assert_almost_eq(now.z, pivot.z, 0.01, "pivot z mid-turn")
		frames += 1
	assert_true(landed[0], "view_turned fired")
	assert_almost_eq(cc.current_yaw(), 135.0, 0.0001)
	assert_almost_eq(_game_map.cameraholder_node.global_basis.get_euler().y, deg_to_rad(90.0), 0.0001)


func test_wasd_forward_pans_away_from_the_viewer_at_every_yaw() -> void:
	var cc := _game_map.get_camera_controller()
	var holder := _game_map.cameraholder_node
	for yaw in [45.0, 135.0, 225.0, 315.0]:
		cc.set_yaw_now(yaw)
		cc.set("_camera_velocity", Vector3.ZERO)
		cc.set("_camera_move_dir", W_LOCAL)
		var before := holder.global_position
		for i in 30:
			(cc.view_mode() as OrbitView).handle_movement(1.0 / 60.0)
		cc.set("_camera_move_dir", Vector3.ZERO)
		var moved := holder.global_position - before
		assert_almost_eq(moved.normalized().dot(CameraRig.screen_up(yaw)), 1.0, 0.001, "yaw %d" % yaw)


func test_w_covers_as_much_screen_as_a() -> void:
	var cc := _game_map.get_camera_controller()
	var holder := _game_map.cameraholder_node
	var cam := _game_map.camera_node
	var anchor := _pivot(cc)
	var speeds := []
	for dir in [W_LOCAL, Vector3(-1.0, 0.0, 1.0)]:
		cc.set("_camera_velocity", Vector3.ZERO)
		cc.set("_camera_move_dir", dir)
		var start := holder.global_position
		var s0 := cam.unproject_position(anchor)
		for i in 30:
			(cc.view_mode() as OrbitView).handle_movement(1.0 / 60.0)
		speeds.append((cam.unproject_position(anchor) - s0).length())
		cc.set("_camera_move_dir", Vector3.ZERO)
		cc.set("_camera_velocity", Vector3.ZERO)
		holder.global_position = start
	assert_almost_eq(speeds[0] / speeds[1], 1.0, 0.03, "the screen speed of W against A")


func test_home_restores_the_yaw() -> void:
	var cc := _game_map.get_camera_controller()
	cc.set_yaw_now(225.0)
	cc.call("_reset_camera_to_home")
	assert_false(cc.is_at_rest())
	var frames := 0
	while not cc.is_at_rest() and frames < 300:
		await get_tree().process_frame
		frames += 1
	assert_lt(frames, 300, "Home comes to rest")
	assert_almost_eq(cc.current_yaw(), CameraRig.HOME_YAW, 0.0001)
	assert_almost_eq(_game_map.cameraholder_node.global_basis.get_euler().y, 0.0, 0.0001)


func test_the_keys_turn_the_controllers_view() -> void:
	var cc := _game_map.get_camera_controller()
	cc.call("_unhandled_key_input", _key(KEY_E))
	assert_true(cc.is_turning())
	assert_almost_eq((cc.get("_view") as CameraView).yaw.target, 135.0, 0.0001)
	cc.call("_unhandled_key_input", _key(KEY_Q))
	assert_almost_eq((cc.get("_view") as CameraView).yaw.target, 45.0, 0.0001, "Q steps back")
