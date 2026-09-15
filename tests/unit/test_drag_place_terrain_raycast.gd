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


func _make_box_body(collision_layer: int, rotation_x_degrees: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 5)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, 0, -10)
	body.rotation.x = deg_to_rad(rotation_x_degrees)
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


func test_downcast_lands_on_the_top_face() -> void:
	_make_box_body(1)
	await get_tree().physics_frame

	var hit_pos := DragPlaceController.raycast_terrain_down(
		_camera.get_world_3d().direct_space_state, Vector3(0, 0, -10)
	)

	assert_ne(hit_pos, Vector3.INF, "A downcast over the box should hit it")
	assert_almost_eq(hit_pos.y, 2.5, 0.01, "Downcast should land on the box's top face (y = 2.5)")


func test_downcast_misses_away_from_the_body() -> void:
	_make_box_body(1)
	await get_tree().physics_frame

	var hit_pos := DragPlaceController.raycast_terrain_down(
		_camera.get_world_3d().direct_space_state, Vector3(50, 0, 50)
	)

	assert_eq(hit_pos, Vector3.INF, "A downcast with no terrain below it should miss")


func test_downcast_height_varies_across_a_slope() -> void:
	# The reason _complete_drag_place re-resolves the height after grid snap:
	# on a slope, moving X/Z by part of a cell changes the surface height, so the
	# camera hit's Y is wrong for the snapped position.
	_make_box_body(1, 30.0)
	await get_tree().physics_frame

	var space_state := _camera.get_world_3d().direct_space_state
	var near_hit := DragPlaceController.raycast_terrain_down(space_state, Vector3(0, 0, -10))
	var far_hit := DragPlaceController.raycast_terrain_down(space_state, Vector3(0, 0, -8))

	assert_ne(near_hit, Vector3.INF, "Downcast at z = -10 should hit the sloped box")
	assert_ne(far_hit, Vector3.INF, "Downcast at z = -8 should hit the sloped box")
	assert_true(
		near_hit.y > far_hit.y + 0.1,
		(
			"The slope descends with +Z, so the surface must be measurably lower at z = -8 (%f vs %f)"
			% [far_hit.y, near_hit.y]
		)
	)
