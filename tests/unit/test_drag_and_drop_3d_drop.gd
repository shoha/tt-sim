extends GutTest

## Tests for DragAndDrop3D.stop_drag(): the dragged body must land on the snapped
## target position, not wherever the frame-rate-dependent lerp in _process() happened
## to leave it when the mouse button came up.

var _original_current_scene: Node
var _dummy_scene_root: Node
var _camera: Camera3D


## Same harness as test_drag_and_drop_3d_threshold.gd: DragAndDrop3D._ready() awaits
## get_tree().current_scene.ready, and _begin_drag() raycasts from the current camera.
func before_each() -> void:
	_original_current_scene = get_tree().current_scene
	_dummy_scene_root = Node.new()
	get_tree().root.add_child(_dummy_scene_root)
	if not _dummy_scene_root.is_node_ready():
		await _dummy_scene_root.ready
	get_tree().current_scene = _dummy_scene_root

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
	object.position = Vector3(1000, 1000, 1000)
	return object


func _activate_drag(drag_and_drop: DragAndDrop3D, object: DraggingObject3D) -> void:
	var press_position := Vector2(100, 100)
	drag_and_drop.set_dragging_object(press_position, object)
	var move_event := InputEventMouseMotion.new()
	move_event.position = press_position + Vector2(drag_and_drop.drag_threshold_px + 1.0, 0)
	drag_and_drop._input(move_event)
	assert_true(drag_and_drop.is_dragging(), "Setup: drag should be active")


func test_stop_drag_places_body_on_target_xz() -> void:
	var drag_and_drop := DragAndDrop3D.new()
	add_child_autofree(drag_and_drop)
	var object := _make_dragging_object()
	add_child_autofree(object)
	_activate_drag(drag_and_drop, object)

	# Simulate a snapped target the lerp has not caught up to yet.
	var body := object.objectBody
	body.global_position = Vector3(1000, 1000, 1000)
	drag_and_drop._target_drag_position = Vector3(1003.0, 1000.25, 997.0)
	drag_and_drop._has_target_position = true

	drag_and_drop.stop_drag()

	assert_almost_eq(body.global_position.x, 1003.0, 0.0001, "X must land on the target")
	assert_almost_eq(body.global_position.z, 997.0, 0.0001, "Z must land on the target")
	assert_almost_eq(
		body.global_position.y, 1000.0, 0.0001, "Y is left for the settle tween, not snapped"
	)


func test_stop_drag_without_target_leaves_body_alone() -> void:
	var drag_and_drop := DragAndDrop3D.new()
	add_child_autofree(drag_and_drop)
	var object := _make_dragging_object()
	add_child_autofree(object)
	_activate_drag(drag_and_drop, object)

	var body := object.objectBody
	body.global_position = Vector3(1000, 1000, 1000)
	drag_and_drop._has_target_position = false

	drag_and_drop.stop_drag()

	assert_eq(body.global_position, Vector3(1000, 1000, 1000))


func test_whoosh_threshold_is_below_max_speed() -> void:
	# WHOOSH_SPEED_THRESHOLD was 48 while WHOOSH_SPEED_MAX was 18, so the sound could
	# never play and the pitch lerp always clamped to 0.
	assert_lt(
		DraggableToken.WHOOSH_SPEED_THRESHOLD,
		DraggableToken.WHOOSH_SPEED_MAX,
		"Whoosh threshold must be reachable and below the max-pitch speed"
	)
