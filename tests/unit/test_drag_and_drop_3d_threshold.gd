extends GutTest

## Tests for DragAndDrop3D's mouse-move drag-activation threshold
## (addons/DragAndDrop3D/nodes/drag_and_drop_3d.gd) and the drop-target raycast
## (addons/DragAndDrop3D/nodes/dragging_object_3d.gd).
##
## The threshold anchor must be seeded from the true mouse-down point (the press position
## carried through DraggingObject3D's object_body_mouse_down signal), not from
## get_viewport().get_mouse_position(): that cached cursor position only tracks genuine OS
## mouse motion and does not update for a synthetically-injected InputEventMouseMotion or
## InputEventMouseButton (confirmed experimentally against the validation bridge -- readings
## were bit-for-bit identical before and after injecting one). Seeding the anchor at
## mouse-down (rather than deferring to the first motion event) also means a single
## past-threshold motion event activates a drag, matching how absolute-position devices
## (styluses, touch-emulated mice, RDP/VM cursor jumps) deliver input: a press, one large
## jump, then release.

var _original_current_scene: Node
var _dummy_scene_root: Node
var _camera: Camera3D


## DragAndDrop3D._ready() and DraggingObject3D._ready() both await
## get_tree().current_scene.ready. gut_cmdln's headless runner never assigns a
## current_scene, so give them a throwaway root-level scene for the duration of the test
## (same pattern as test_draggable_token_submerge.gd).
func before_each() -> void:
	_original_current_scene = get_tree().current_scene
	_dummy_scene_root = Node.new()
	get_tree().root.add_child(_dummy_scene_root)
	if not _dummy_scene_root.is_node_ready():
		await _dummy_scene_root.ready
	get_tree().current_scene = _dummy_scene_root

	# _begin_drag() immediately calls _update_target_position(), which raycasts from the
	# viewport's current camera. Without one, get_viewport().get_camera_3d() returns null
	# and the raycast setup crashes before the threshold assertion is ever reached.
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_camera.make_current()


func after_each() -> void:
	get_tree().current_scene = _original_current_scene
	if is_instance_valid(_dummy_scene_root):
		_dummy_scene_root.queue_free()
	_dummy_scene_root = null


func _make_dragging_object() -> DraggingObject3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)

	var object := DraggingObject3D.new()
	object.add_child(body)
	# Keep it out of the camera's default frustum so _get_3d_mouse_position()'s raycast
	# finds nothing and returns early -- the threshold logic under test does not depend
	# on a successful raycast, and this keeps the test from depending on collision
	# behaviour that is not what is being tested here.
	object.position = Vector3(1000, 1000, 1000)
	return object


func _make_drag_and_drop() -> DragAndDrop3D:
	var drag_and_drop := DragAndDrop3D.new()
	add_child_autofree(drag_and_drop)
	return drag_and_drop


func _press_event() -> Vector2:
	return Vector2(100, 100)


func test_single_motion_past_threshold_activates_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, object)
	assert_false(
		drag_and_drop.is_dragging(), "Should be pending, not dragging, right after mouse-down"
	)

	# A single motion event past the threshold from the true press point must activate the
	# drag immediately -- no second, seeding-only motion event required. This is the
	# regression case for absolute-position devices (stylus, touch-emulated mouse, RDP/VM
	# cursor jump) that can deliver one large jump before button-up.
	var move_event := InputEventMouseMotion.new()
	move_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px + 1.0, 0)
	drag_and_drop._input(move_event)

	assert_true(
		drag_and_drop.is_dragging(), "A single past-threshold motion event should activate the drag"
	)


func test_motion_exactly_at_threshold_activates_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, object)

	# The threshold comparison is >=, so a motion event exactly drag_threshold_px away must
	# activate the drag (boundary case).
	var move_event := InputEventMouseMotion.new()
	move_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px, 0)
	drag_and_drop._input(move_event)

	assert_true(drag_and_drop.is_dragging(), "Motion exactly at the threshold should activate")


func test_motion_below_threshold_does_not_activate_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, object)

	var move_event := InputEventMouseMotion.new()
	move_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px - 1.0, 0)
	drag_and_drop._input(move_event)

	assert_false(drag_and_drop.is_dragging(), "Sub-threshold motion must not activate the drag")


func test_click_with_no_motion_clears_pending_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, object)

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = press_position
	drag_and_drop._input(release_event)

	assert_false(drag_and_drop.is_dragging(), "A plain click must not activate a drag")
	assert_null(
		drag_and_drop._pending_drag_object,
		"Release before any motion should clear the pending drag entirely"
	)

	# Confirm the pending state is really gone, not just leaving is_dragging() false: a new
	# press must be free to start its own pending drag.
	var next_object := _make_dragging_object()
	add_child_autofree(next_object)
	drag_and_drop.set_dragging_object(Vector2(200, 200), next_object)
	assert_eq(
		drag_and_drop._pending_drag_object,
		next_object,
		"A new press after a cleared click should start its own pending drag"
	)


func test_right_click_cancels_pending_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, object)

	var right_click_event := InputEventMouseButton.new()
	right_click_event.button_index = MOUSE_BUTTON_RIGHT
	right_click_event.pressed = true
	right_click_event.position = press_position
	drag_and_drop._input(right_click_event)

	assert_null(drag_and_drop._pending_drag_object, "Right-click should cancel the pending drag")

	# A subsequent motion past the threshold must not resurrect the cancelled drag.
	var move_event := InputEventMouseMotion.new()
	move_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px + 1.0, 0)
	drag_and_drop._input(move_event)

	assert_false(
		drag_and_drop.is_dragging(), "Motion after a right-click cancel must not start a drag"
	)


func test_second_drag_does_not_leak_anchor_from_first() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var first_object := _make_dragging_object()
	add_child_autofree(first_object)

	# First drag: press at (0, 0), activate with a motion well past the threshold, then
	# release to end it normally.
	drag_and_drop.set_dragging_object(Vector2(0, 0), first_object)
	var first_move := InputEventMouseMotion.new()
	first_move.position = Vector2(10, 0)
	drag_and_drop._input(first_move)
	assert_true(drag_and_drop.is_dragging(), "First drag should have activated")

	var release_event := InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = Vector2(10, 0)
	drag_and_drop._input(release_event)
	assert_false(drag_and_drop.is_dragging(), "First drag should have stopped on release")

	# Second drag: press at (10, 0) -- the same point where the mouse now sits -- then move
	# only 2px, well below the 5px threshold from THIS press position. If the anchor had
	# leaked from the first drag (stale at (0, 0)), this motion's distance from (0, 0) would
	# be 12px and would wrongly activate a drag.
	var second_object := _make_dragging_object()
	add_child_autofree(second_object)
	drag_and_drop.set_dragging_object(Vector2(10, 0), second_object)

	var second_move := InputEventMouseMotion.new()
	second_move.position = Vector2(12, 0)
	drag_and_drop._input(second_move)

	assert_false(
		drag_and_drop.is_dragging(),
		(
			"Sub-threshold motion relative to the second press must not activate a drag"
			+ " -- a leaked first-drag anchor would wrongly activate here"
		)
	)


func test_get_3d_mouse_position_uses_passed_position_not_viewport_cursor() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var dragging_object := _make_dragging_object()
	add_child_autofree(dragging_object)

	# Activate a drag so _currentDraggingObject is set -- _get_3d_mouse_position() excludes
	# it from the raycast via _get_excluded_objects(), which dereferences it unconditionally.
	var press_position := _press_event()
	drag_and_drop.set_dragging_object(press_position, dragging_object)
	var activate_event := InputEventMouseMotion.new()
	activate_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px + 1.0, 0)
	drag_and_drop._input(activate_event)
	assert_true(drag_and_drop.is_dragging(), "Setup: drag should be active before raycasting")

	# A separate target body sitting directly in front of the camera (which the default
	# Camera3D faces along -Z from the origin).
	var target_body := StaticBody3D.new()
	var target_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 5)
	target_shape.shape = box
	target_body.add_child(target_shape)
	target_body.position = Vector3(0, 0, -10)
	add_child_autofree(target_body)

	# Let the physics server register the new body before querying its space.
	await get_tree().physics_frame

	var viewport_size := drag_and_drop.get_viewport().get_visible_rect().size
	var screen_center := viewport_size / 2.0
	# Far outside the viewport in either direction: a ray through this screen point cannot
	# hit a box only 5 units wide centered on the forward axis.
	var far_off_screen := Vector2(viewport_size.x + 5000.0, viewport_size.y + 5000.0)

	var hit_result = drag_and_drop._get_3d_mouse_position(screen_center)
	assert_not_null(
		hit_result,
		(
			"Raycast through the passed screen-center position should hit the target body"
			+ " -- get_viewport().get_mouse_position() never moves in this headless test, so a"
			+ " hit here proves the passed position (not the cursor) drives the raycast"
		)
	)

	var miss_result = drag_and_drop._get_3d_mouse_position(far_off_screen)
	assert_null(
		miss_result, "Raycast through a far-off-screen passed position should miss the target"
	)
