extends GutTest

## DragController and Draggable3D through their input path: the press that arms a drag, the
## threshold, the ground ray, the follow, the drop, both cancels, the wheel and the guards.
##
## The camera sits at the origin looking down -Z. A floor box 10 m ahead is what the ground ray
## hits through the screen centre, at (0, 0, -7.5); a screen point far outside the viewport misses
## it. The dragged object sits at (1000, 1000, 1000), out of the camera's way.

const FLOOR_HIT := Vector3(0, 0, -7.5)

var _camera: Camera3D
var _controller: DragController


func before_each() -> void:
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_camera.make_current()
	_controller = DragController.new()
	add_child_autofree(_controller)


func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 5)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, 0, -10)
	add_child_autofree(body)
	return body


func _draggable() -> Draggable3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var object := Draggable3D.new()
	object.add_child(body)
	object.position = Vector3(1000, 1000, 1000)
	add_child_autofree(object)
	return object


## A ground resolver that finds flat ground at height `y` under any point.
func _raise_to(point: Vector3, y: float) -> Vector3:
	return Vector3(point.x, y, point.z)


func _center() -> Vector2:
	return _controller.get_viewport().get_visible_rect().size / 2.0


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	return ev


func _button(
	index: MouseButton, pressed: bool, pos: Vector2 = Vector2.ZERO
) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = pos
	return ev


## Press on `object` at `from` and move past the threshold to `to`: an active drag.
func _drag(object: Draggable3D, from: Vector2, to: Vector2) -> void:
	_controller.press(object, from)
	_controller._input(_motion(to))
	assert_true(_controller.is_dragging(), "Setup: the drag is active")


# --- the threshold -------------------------------------------------------------------------


func test_a_press_alone_does_not_start_a_drag() -> void:
	_controller.press(_draggable(), Vector2(100, 100))
	assert_false(_controller.is_dragging(), "armed, not dragging")


func test_a_single_motion_past_the_threshold_begins_the_drag() -> void:
	var object := _draggable()
	_controller.press(object, Vector2(100, 100))
	_controller._input(_motion(Vector2(100 + _controller.drag_threshold_px + 1.0, 100)))
	assert_true(_controller.is_dragging())
	assert_eq(_controller.get_subject(), object)


func test_motion_exactly_at_the_threshold_begins_the_drag() -> void:
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_motion(Vector2(100 + _controller.drag_threshold_px, 100)))
	assert_true(_controller.is_dragging())


func test_motion_below_the_threshold_does_not() -> void:
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_motion(Vector2(100 + _controller.drag_threshold_px - 1.0, 100)))
	assert_false(_controller.is_dragging())


func test_the_threshold_export_is_honoured() -> void:
	_controller.drag_threshold_px = 30.0
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_motion(Vector2(120, 100)))
	assert_false(_controller.is_dragging(), "20 px is under a 30 px threshold")
	_controller._input(_motion(Vector2(130, 100)))
	assert_true(_controller.is_dragging())


func test_releasing_before_the_threshold_is_a_click_and_frees_the_next_press() -> void:
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_button(MOUSE_BUTTON_LEFT, false, Vector2(100, 100)))
	_controller._input(_motion(Vector2(300, 100)))
	assert_false(_controller.is_dragging(), "a click must not become a drag later")
	var next := _draggable()
	_controller.press(next, Vector2(200, 200))
	_controller._input(_motion(Vector2(220, 200)))
	assert_eq(_controller.get_subject(), next, "a new press starts its own drag")


func test_a_right_click_cancels_a_pending_press() -> void:
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)))
	_controller._input(_motion(Vector2(300, 100)))
	assert_false(_controller.is_dragging())


func test_the_second_drag_does_not_inherit_the_first_anchor() -> void:
	var first := _draggable()
	_drag(first, Vector2(0, 0), Vector2(10, 0))
	_controller._input(_button(MOUSE_BUTTON_LEFT, false, Vector2(10, 0)))
	assert_false(_controller.is_dragging(), "the first drag ended on release")
	_controller.press(_draggable(), Vector2(10, 0))
	_controller._input(_motion(Vector2(12, 0)))
	assert_false(_controller.is_dragging(), "2 px from the new press is under the threshold")


func test_dragging_disabled_blocks_a_new_drag() -> void:
	_controller.dragging_enabled = false
	_controller.press(_draggable(), Vector2(100, 100))
	_controller._input(_motion(Vector2(300, 100)))
	assert_false(_controller.is_dragging())


func test_a_press_on_a_draggable_body_reaches_the_controller() -> void:
	var object := _draggable()
	await get_tree().process_frame
	assert_true(_controller.is_in_group(DragController.GROUP), "the controller joins its group")
	var press := _button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100))
	object._on_body_input_event(null, press, Vector3.ZERO, Vector3.ZERO, 0)
	_controller._input(_motion(Vector2(200, 100)))
	assert_eq(_controller.get_subject(), object)


func test_only_a_left_press_arms_a_drag() -> void:
	var object := _draggable()
	var events: Array[InputEvent] = [
		_button(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100)),
		_button(MOUSE_BUTTON_LEFT, false, Vector2(100, 100)),
		_motion(Vector2(100, 100)),
	]
	for ev in events:
		object._on_body_input_event(null, ev, Vector3.ZERO, Vector3.ZERO, 0)
	_controller._input(_motion(Vector2(300, 100)))
	assert_false(_controller.is_dragging())


# --- signals -------------------------------------------------------------------------------


func test_begin_drop_and_cancel_signal_on_the_controller_and_the_object() -> void:
	var object := _draggable()
	watch_signals(_controller)
	watch_signals(object)
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	assert_signal_emitted_with_parameters(_controller, "dragging_started", [object])
	assert_signal_emitted(object, "dragging_started")
	_controller._input(_button(MOUSE_BUTTON_LEFT, false, Vector2(200, 100)))
	assert_signal_emitted_with_parameters(_controller, "dragging_stopped", [object])
	assert_signal_emitted(object, "dragging_stopped")
	assert_signal_not_emitted(_controller, "dragging_cancelled")

	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller._input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(200, 100)))
	assert_signal_emitted_with_parameters(_controller, "dragging_cancelled", [object])
	assert_signal_emitted(object, "dragging_cancelled")
	assert_false(_controller.is_dragging())


func test_escape_cancels_an_active_drag() -> void:
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	watch_signals(_controller)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_controller._input(esc)
	assert_signal_emitted(_controller, "dragging_cancelled")
	assert_false(_controller.is_dragging())


func test_other_keys_do_not_cancel() -> void:
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	_controller._input(key)
	assert_true(_controller.is_dragging())


func test_cancel_with_nothing_held_is_a_no_op() -> void:
	watch_signals(_controller)
	_controller.cancel_drag()
	_controller.stop_drag()
	assert_signal_not_emitted(_controller, "dragging_cancelled")
	assert_signal_not_emitted(_controller, "dragging_stopped")


func test_begin_drag_starts_without_a_press() -> void:
	var object := _draggable()
	watch_signals(_controller)
	_controller.begin_drag(object)
	assert_true(_controller.is_dragging())
	assert_signal_emitted(_controller, "dragging_started")


# --- the ground ray -----------------------------------------------------------------------


func test_the_ray_uses_the_passed_position_not_the_cursor() -> void:
	_floor()
	await get_tree().physics_frame
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	assert_true(_controller.has_target(), "a ray through the screen centre hits the floor")
	assert_almost_eq(_controller.get_target_ground_position().z, FLOOR_HIT.z, 0.001)
	var far := _controller.get_viewport().get_visible_rect().size + Vector2(5000, 5000)
	_controller.update_target_position(far)
	assert_almost_eq(
		_controller.get_target_ground_position().z, FLOOR_HIT.z, 0.001, "a miss keeps the old target"
	)


func test_the_collision_mask_filters_what_the_ray_hits() -> void:
	_floor()
	await get_tree().physics_frame
	_controller.collision_mask = 2
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	assert_false(_controller.has_target(), "the floor is on layer 1, the mask asks for layer 2")


func test_the_target_is_lifted_by_the_object_height_offset() -> void:
	_floor()
	await get_tree().physics_frame
	var object := _draggable()
	object.height_offset = 0.4
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	assert_almost_eq(_controller.get_target_position().y, 0.4, 0.001)
	assert_almost_eq(_controller.get_target_ground_position().y, 0.0, 0.001)


func test_grid_snap_puts_the_target_on_a_cell_centre() -> void:
	_floor()
	await get_tree().physics_frame
	_controller.grid_snap_enabled = true
	_controller.grid_cell_size = 2.0
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	var snapped := ScaleUtils.snap_to_grid(FLOOR_HIT, 2.0, Vector2.ZERO)
	assert_almost_eq(_controller.get_target_ground_position().x, snapped.x, 0.001)
	assert_almost_eq(_controller.get_target_ground_position().z, snapped.z, 0.001)


func test_the_ground_resolver_sets_the_target_height() -> void:
	_floor()
	await get_tree().physics_frame
	_controller.ground_resolver = _raise_to.bind(3.0)
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	assert_almost_eq(_controller.get_target_ground_position().y, 3.0, 0.001)


# --- the wheel -----------------------------------------------------------------------------


func test_the_wheel_raises_and_lowers_the_target_by_the_height_step() -> void:
	_floor()
	await get_tree().physics_frame
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	var base := _controller.get_target_position().y
	_controller._input(_button(MOUSE_BUTTON_WHEEL_UP, true, _center()))
	_controller._input(_button(MOUSE_BUTTON_WHEEL_UP, true, _center()))
	_controller._process(0.016)
	assert_almost_eq(_controller.get_target_position().y, base + 2.0 * _controller.height_step, 0.001)
	_controller._input(_button(MOUSE_BUTTON_WHEEL_DOWN, true, _center()))
	_controller._process(0.016)
	assert_almost_eq(_controller.get_target_position().y, base + _controller.height_step, 0.001)


func test_the_wheel_height_resets_for_the_next_drag() -> void:
	_floor()
	await get_tree().physics_frame
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller._input(_button(MOUSE_BUTTON_WHEEL_UP, true, _center()))
	_controller._process(0.016)
	_controller.cancel_drag()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	assert_almost_eq(_controller.get_target_position().y, 0.0, 0.001)


# --- the deferred ray ----------------------------------------------------------------------


func test_motion_events_defer_the_ray_to_process_and_keep_the_last() -> void:
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller._input(_motion(Vector2(300, 300)))
	_controller._input(_motion(Vector2(320, 340)))
	assert_true(_controller._pointer_dirty, "motion defers the ray")
	assert_eq(_controller._pending_pointer_position, Vector2(320, 340), "the last event wins")
	_controller._process(0.016)
	assert_false(_controller._pointer_dirty, "process consumes it once")


func test_a_stale_pointer_flag_never_leaks_into_the_next_drag() -> void:
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller._pointer_dirty = true
	_controller.stop_drag()
	assert_false(_controller._pointer_dirty, "a drop clears it")
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller._pointer_dirty = true
	_controller.cancel_drag()
	assert_false(_controller._pointer_dirty, "a cancel clears it")
	_controller._pointer_dirty = true
	_controller.begin_drag(object)
	assert_false(_controller._pointer_dirty, "a new drag clears it")


# --- the follow and the drop ---------------------------------------------------------------


func test_process_eases_the_body_toward_the_target() -> void:
	_floor()
	await get_tree().physics_frame
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	var before := object.body.global_position
	_controller._process(0.016)
	var after := object.body.global_position
	var target := _controller.get_target_position()
	assert_lt(after.distance_to(target), before.distance_to(target), "closer to the target")
	assert_gt(after.distance_to(target), 0.0, "but not there in one frame")


func test_a_drop_lands_the_body_on_the_target_xz_and_leaves_y() -> void:
	_floor()
	await get_tree().physics_frame
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	_controller.update_target_position(_center())
	_controller.stop_drag()
	var landed := object.body.global_position
	assert_almost_eq(landed.x, FLOOR_HIT.x, 0.001, "X on the target")
	assert_almost_eq(landed.z, FLOOR_HIT.z, 0.001, "Z on the target")
	assert_almost_eq(landed.y, 1000.0, 0.001, "Y is left for the settle tween")


func test_a_drop_with_a_resolver_lifts_a_low_body_to_the_target_height() -> void:
	_floor()
	await get_tree().physics_frame
	_controller.ground_resolver = _raise_to.bind(2.0)
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	object.body.global_position = Vector3(0, -5, 0)
	_controller.update_target_position(_center())
	_controller.stop_drag()
	assert_almost_eq(object.body.global_position.y, 2.0, 0.001, "lifted out of the cliff")


func test_a_drop_with_no_target_leaves_the_body_alone() -> void:
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	var before := object.body.global_position
	_controller.stop_drag()
	assert_eq(object.body.global_position, before)


func test_a_dragged_object_freed_mid_drag_ends_the_drag() -> void:
	var object := _draggable()
	_drag(object, Vector2(100, 100), Vector2(200, 100))
	object.free()
	_controller._process(0.016)
	assert_false(_controller.is_dragging())


func test_edge_pan_is_zero_when_disabled_or_idle() -> void:
	_drag(_draggable(), Vector2(100, 100), Vector2(200, 100))
	_controller.edge_pan_enabled = false
	_controller._process(0.016)
	assert_eq(_controller.edge_pan_direction, Vector2.ZERO)
	_controller.cancel_drag()
	assert_eq(_controller.edge_pan_direction, Vector2.ZERO)


func test_draggable_defaults() -> void:
	var object := _draggable()
	var resolver := func(p: Vector3) -> Vector3: return p
	assert_eq(object.drag_resolver(resolver), resolver, "the shared resolver by default")
	assert_eq(object.get_height_offset(), 0.0)
	assert_not_null(object.body, "the first CollisionObject3D below is the body")
