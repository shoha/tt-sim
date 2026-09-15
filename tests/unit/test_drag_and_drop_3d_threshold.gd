extends GutTest

## Tests for DragAndDrop3D's mouse-move drag-activation threshold
## (addons/DragAndDrop3D/nodes/drag_and_drop_3d.gd).
##
## The threshold must be evaluated from the InputEventMouseMotion's own position, not from
## get_viewport().get_mouse_position(): that cached cursor position only tracks genuine OS
## mouse motion and does not update for a synthetically-injected InputEventMouseMotion
## (confirmed experimentally against the validation bridge -- readings were bit-for-bit
## identical before and after injecting one). A version that re-queries the viewport never
## activates a drag driven by injected events, which is exactly how the validation bridge
## drives token drags.

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


func test_motion_past_threshold_activates_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	drag_and_drop.set_dragging_object(object)
	assert_false(
		drag_and_drop.is_dragging(), "Should be pending, not dragging, right after mouse-down"
	)

	# The first motion event after mouse-down seeds the threshold anchor; it must not
	# activate the drag by itself.
	var seed_event := InputEventMouseMotion.new()
	seed_event.position = Vector2(100, 100)
	drag_and_drop._input(seed_event)
	assert_false(drag_and_drop.is_dragging(), "First motion event should only seed the anchor")

	# A second motion event whose own position is past the threshold from the seeded
	# anchor must activate the drag -- even though get_viewport().get_mouse_position()
	# never moves under GUT, since there is no real OS mouse here.
	var move_event := InputEventMouseMotion.new()
	move_event.position = seed_event.position + Vector2(drag_and_drop.drag_threshold_px + 1.0, 0)
	drag_and_drop._input(move_event)

	assert_true(
		drag_and_drop.is_dragging(), "Drag should activate once past-threshold motion is delivered"
	)


func test_motion_below_threshold_does_not_activate_drag() -> void:
	var drag_and_drop := _make_drag_and_drop()
	var object := _make_dragging_object()
	add_child_autofree(object)

	drag_and_drop.set_dragging_object(object)

	var seed_event := InputEventMouseMotion.new()
	seed_event.position = Vector2(100, 100)
	drag_and_drop._input(seed_event)

	var move_event := InputEventMouseMotion.new()
	move_event.position = seed_event.position + Vector2(drag_and_drop.drag_threshold_px - 1.0, 0)
	drag_and_drop._input(move_event)

	assert_false(drag_and_drop.is_dragging(), "Sub-threshold motion must not activate the drag")
