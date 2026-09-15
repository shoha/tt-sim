extends GutTest

## Tests for DropIndicatorRenderer.update() -- verifies the dotted line is rebuilt only
## when the drag start position (or its raycast hit) actually moves more than
## REBUILD_EPSILON, and that the landing circle -- a prebuilt unit-radius fan -- is simply
## posed (transform + scale) every frame instead of being rebuilt.
## See scenes/board_token/board_token_drop_indicator_renderer.gd.
##
## Same headless raycast harness as test_drag_place_terrain_raycast.gd: a StaticBody3D floor
## with a box collider on the terrain layer, physics given one frame to register it.

var _renderer: DropIndicatorRenderer
var _floor_body: StaticBody3D


func before_each() -> void:
	_floor_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	shape.shape = box
	_floor_body.add_child(shape)
	_floor_body.position = Vector3(0, -0.5, 0)  # top face at y = 0
	_floor_body.collision_layer = 1
	add_child_autofree(_floor_body)

	_renderer = DropIndicatorRenderer.new()
	add_child_autofree(_renderer)

	await get_tree().physics_frame
	_renderer.show_indicator()


func test_update_skips_line_rebuild_and_poses_circle_when_start_has_not_moved() -> void:
	_renderer.update(Vector3(0, 2, 0))
	var rebuilds_after_first: int = _renderer._line_rebuilds
	var surfaces_after_first: int = _renderer._line_immediate_mesh.get_surface_count()

	_renderer.update(Vector3(0, 2, 0))

	assert_eq(
		_renderer._line_rebuilds,
		rebuilds_after_first,
		"A second update() at the same start position should not rebuild the line"
	)
	assert_eq(
		_renderer._line_immediate_mesh.get_surface_count(),
		surfaces_after_first,
		"The line mesh's surface count should be unchanged when the start didn't move"
	)

	var circle_scale: Vector3 = _renderer._circle_mesh_instance.scale
	assert_almost_eq(circle_scale.x, circle_scale.y, 0.001, "Circle pulse scale should be uniform")
	assert_almost_eq(circle_scale.y, circle_scale.z, 0.001, "Circle pulse scale should be uniform")
	assert_gt(circle_scale.x, 0.0, "Circle scale should reflect a positive pulsing radius")


func test_update_rebuilds_line_when_start_moves() -> void:
	_renderer.update(Vector3(0, 2, 0))
	_renderer.update(Vector3(0, 2, 0))
	var rebuilds_before_move: int = _renderer._line_rebuilds

	_renderer.update(Vector3(1, 2, 0))

	assert_gt(
		_renderer._line_rebuilds,
		rebuilds_before_move,
		"Moving the start position beyond REBUILD_EPSILON should rebuild the line"
	)
