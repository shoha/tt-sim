extends GutTest

## Tests for DragPlaceController.raycast_terrain() -- the terrain raycast used
## to land a drag-placed token on the ground under the cursor instead of the
## flat Y=0 plane. Same harness pattern as
## test_drag_and_drop_3d_threshold.gd's
## test_get_3d_mouse_position_uses_passed_position_not_viewport_cursor: a
## Camera3D made current, a StaticBody3D with a box collider in front of it,
## and a raycast through the screen center.

var _camera: Camera3D


func before_each() -> void:
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_camera.make_current()


func _make_box_body(collision_layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 5)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, 0, -10)
	body.collision_layer = collision_layer
	add_child_autofree(body)
	return body


func test_raycast_hits_terrain_body_at_near_face() -> void:
	_make_box_body(1)
	await get_tree().physics_frame

	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var screen_center := viewport_size / 2.0

	var hit_pos := DragPlaceController.raycast_terrain(
		_camera, _camera.get_world_3d().direct_space_state, screen_center
	)

	assert_ne(hit_pos, Vector3.INF, "Raycast through screen center should hit the terrain body")
	assert_almost_eq(
		hit_pos.z, -7.5, 0.01, "Hit position should land on the box's near face (z = -7.5)"
	)


func test_raycast_misses_far_off_screen() -> void:
	_make_box_body(1)
	await get_tree().physics_frame

	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var far_off_screen := Vector2(viewport_size.x + 5000.0, viewport_size.y + 5000.0)

	var hit_pos := DragPlaceController.raycast_terrain(
		_camera, _camera.get_world_3d().direct_space_state, far_off_screen
	)

	assert_eq(hit_pos, Vector3.INF, "Raycast through a far-off-screen position should miss")


func test_raycast_ignores_body_on_non_terrain_layer() -> void:
	# Layer 2 only -- not on TERRAIN_COLLISION_LAYER (1), so the mask must exclude it.
	_make_box_body(2)
	await get_tree().physics_frame

	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var screen_center := viewport_size / 2.0

	var hit_pos := DragPlaceController.raycast_terrain(
		_camera, _camera.get_world_3d().direct_space_state, screen_center
	)

	assert_eq(
		hit_pos, Vector3.INF, "A body on a non-terrain layer must not be hit by the terrain raycast"
	)
