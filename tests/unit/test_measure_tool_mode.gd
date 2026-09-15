extends GutTest

## Tests for MeasureTool mode cycling logic.


func test_mode_enum_order() -> void:
	assert_eq(MeasureTool.Mode.LINE, 0)
	assert_eq(MeasureTool.Mode.SPHERE, 1)
	assert_eq(MeasureTool.Mode.CYLINDER, 2)


func test_advance_mode_line_to_sphere() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.LINE), MeasureTool.Mode.SPHERE)


func test_advance_mode_sphere_to_cylinder() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.SPHERE), MeasureTool.Mode.CYLINDER)


func test_advance_mode_cylinder_wraps_to_line() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.CYLINDER), MeasureTool.Mode.LINE)


func test_initial_mode_is_line() -> void:
	var tool := MeasureTool.new()
	add_child_autofree(tool)
	assert_eq(tool._mode, MeasureTool.Mode.LINE)


func test_two_motion_events_same_frame_defer_preview_raycast_to_process() -> void:
	var tool := MeasureTool.new()
	add_child_autofree(tool)
	# Skip activate()/setup(): this test only needs an active state, not the camera/overlay
	# machinery activate() wires up -- poking _state directly (as other tests in this file
	# already do with _mode) is the established pattern here.
	tool._state = MeasureTool.State.PLACING_START

	# Two motion events injected in the same frame must not each raycast synchronously --
	# only the flag should end up set; handle_input() itself no longer calls _update_preview().
	var first_move := InputEventMouseMotion.new()
	first_move.position = Vector2(100, 100)
	tool.handle_input(first_move)

	var second_move := InputEventMouseMotion.new()
	second_move.position = Vector2(140, 160)
	tool.handle_input(second_move)

	assert_true(
		tool._preview_dirty,
		"Motion while the tool is active should defer to a pending preview raycast"
	)

	# No camera/viewport is set up via setup() in this harness, so the consumed raycast
	# itself cannot be observed here; assert on the dirty flag only, per the brief's
	# fallback for an unobservable _update_preview() call.
	tool._process(0.016)

	assert_false(tool._preview_dirty, "_process() should consume the pending preview raycast once")
