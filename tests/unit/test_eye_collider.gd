extends GutTest

## EyeCollider: the sphere sweep that keeps the eye view out of walls, against real collision
## bodies on the terrain layer (concave faces with backface collision, like AuthoredWalls and
## AuthoredStructures build). The eye is at height 1.6, the sphere 0.35.

const HEIGHT := 1.6
const RADIUS := 0.35

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


## A vertical quad from (x0, z0) to (x1, z1), from y = bottom to y = top, as two triangles.
func _quad(x0: float, z0: float, x1: float, z1: float, bottom: float, top: float) -> Array[Vector3]:
	var a := Vector3(x0, bottom, z0)
	var b := Vector3(x1, bottom, z1)
	var c := Vector3(x1, top, z1)
	var d := Vector3(x0, top, z0)
	return [a, b, c, a, c, d]


func _body(quads: Array, layer: int = WaterSurface.TERRAIN_LAYER) -> StaticBody3D:
	var faces := PackedVector3Array()
	for quad: Array[Vector3] in quads:
		faces.append_array(PackedVector3Array(quad))
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_root.add_child(body)
	return body


func _collider(exclude: Array[RID] = []) -> EyeCollider:
	return EyeCollider.new(_root.get_world_3d().direct_space_state, exclude, RADIUS)


func _wall_at_x5() -> StaticBody3D:
	return _body([_quad(5.0, -10.0, 5.0, 10.0, 0.0, 4.0)])


func test_walking_at_a_wall_stops_short_of_it() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var end := _collider().move(Vector2.ZERO, Vector2(10.0, 0.0), HEIGHT)
	assert_almost_eq(end.x, 5.0 - RADIUS, 0.03, "stopped one radius from the wall")
	assert_almost_eq(end.y, 0.0, 0.001)
	assert_lt(end.x, 5.0 - RADIUS + 0.0001, "never inside the sphere's reach")


func test_walking_from_the_back_of_a_wall_stops_too() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var end := _collider().move(Vector2(10.0, 1.0), Vector2(-10.0, 0.0), HEIGHT)
	assert_almost_eq(end.x, 5.0 + RADIUS, 0.03)


func test_a_slanting_walk_slides_along_the_wall() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var end := _collider().move(Vector2.ZERO, Vector2(10.0, 4.0), HEIGHT)
	assert_almost_eq(end.x, 5.0 - RADIUS, 0.03)
	assert_almost_eq(end.y, 4.0, 0.08, "the part of the walk along the wall is kept")


func test_a_thin_wall_does_not_let_a_long_move_through() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	for length in [0.17, 1.0, 12.0, 40.0]:
		var end := _collider().move(Vector2(4.0, 0.0), Vector2(float(length), 0.0), HEIGHT)
		assert_lt(end.x, 5.0, "a move of %s m is held by a wall with no thickness" % length)


func test_a_run_into_a_wall_frame_by_frame_never_tunnels_and_holds_still() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var foot := Vector2.ZERO
	var settled := Vector2.ZERO
	for i in 120:
		foot = _collider().move(foot, Vector2(10.0, 0.0) / 60.0, HEIGHT)
		assert_lt(foot.x, 5.0 - RADIUS + 0.0001, "frame %d" % i)
		if i == 80:
			settled = foot
	assert_almost_eq(foot.x, settled.x, 0.0001, "no creep or jitter at the wall")


func test_pushing_diagonally_on_a_wall_glides_along_it_steadily() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var foot := Vector2(4.0, 0.0)
	var last_z := 0.0
	for i in 60:
		foot = _collider().move(foot, Vector2(0.17, 0.1), HEIGHT)
		if i > 20:
			assert_almost_eq(foot.y - last_z, 0.1, 0.003, "even speed along the wall, frame %d" % i)
		last_z = foot.y
		assert_lt(foot.x, 5.0 - RADIUS + 0.0001)


func test_sliding_along_a_wall_carries_on_past_its_end() -> void:
	# A wall from z = -10 to z = 0 at x = 5: pushed into it diagonally, the eye slides along it
	# and goes around its end instead of catching there.
	_body([_quad(5.0, -10.0, 5.0, 0.0, 0.0, 4.0)])
	await get_tree().physics_frame
	var foot := Vector2(3.0, -8.0)
	var stuck := 0
	for i in 150:
		var before := foot
		foot = _collider().move(foot, Vector2(0.06, 0.15), HEIGHT)
		if foot.distance_to(before) < 0.05:
			stuck += 1
	assert_gt(foot.y, 6.0, "past the end of the wall")
	assert_lte(stuck, 2, "no frame lost on the way")


func test_a_corner_holds_and_does_not_shake() -> void:
	_body([_quad(5.0, -10.0, 5.0, 10.0, 0.0, 4.0), _quad(-10.0, 5.0, 10.0, 5.0, 0.0, 4.0)])
	await get_tree().physics_frame
	var foot := Vector2.ZERO
	var history: Array[Vector2] = []
	for i in 150:
		foot = _collider().move(foot, Vector2(0.17, 0.17), HEIGHT)
		assert_lt(foot.x, 5.0 - RADIUS + 0.0001)
		assert_lt(foot.y, 5.0 - RADIUS + 0.0001)
		history.append(foot)
	assert_almost_eq(foot.x, 5.0 - RADIUS, 0.05, "in the corner")
	assert_almost_eq(foot.y, 5.0 - RADIUS, 0.05)
	assert_almost_eq(history[149].distance_to(history[120]), 0.0, 0.001, "and still there")


func test_a_door_gap_wider_than_the_sphere_lets_the_eye_through() -> void:
	# A wall at x = 5 with a door 2 m wide at z -1..1 and a lintel from 2 m up.
	_body(
		[
			_quad(5.0, -10.0, 5.0, -1.0, 0.0, 4.0),
			_quad(5.0, 1.0, 5.0, 10.0, 0.0, 4.0),
			_quad(5.0, -1.0, 5.0, 1.0, 2.0, 4.0),
		]
	)
	await get_tree().physics_frame
	var through := _collider().move(Vector2(3.0, 0.0), Vector2(6.0, 0.0), HEIGHT)
	assert_almost_eq(through.x, 9.0, 0.001, "the doorway is open at eye height")
	var beside := _collider().move(Vector2(3.0, 2.0), Vector2(6.0, 0.0), HEIGHT)
	assert_lt(beside.x, 5.0 - RADIUS + 0.0001, "the wall beside it is not")
	# Walking at the door frame (0.2 m from its edge, inside the sphere's reach) slides the eye
	# off the corner and into the opening; it never ends inside the frame.
	var narrow := _collider().move(Vector2(3.0, 0.8), Vector2(6.0, 0.0), HEIGHT)
	assert_lt(narrow.y, 0.8, "the frame pushes the eye toward the middle of the door")
	var half := _collider().move(Vector2(3.0, 0.8), Vector2(1.9, 0.0), HEIGHT)
	assert_lt(half.x, 5.0 - 0.2, "and holds it back from the frame while it is beside it")


func test_the_shipped_radius_does_not_fit_a_standard_door() -> void:
	# The recipes' doors are 1.0 to 1.1 m holes in the collision (no interiors, verdict SL6).
	_body(
		[
			_quad(5.0, -10.0, 5.0, -0.5, 0.0, 4.0),
			_quad(5.0, 0.5, 5.0, 10.0, 0.0, 4.0),
			_quad(5.0, -0.5, 5.0, 0.5, 2.1, 4.0),
		]
	)
	await get_tree().physics_frame
	var space := _root.get_world_3d().direct_space_state
	var shipped := EyeCollider.new(space, [], EyeCollider.RADIUS_M)
	var end := shipped.move(Vector2(3.0, 0.0), Vector2(6.0, 0.0), HEIGHT)
	assert_lt(end.x, 5.0, "a 1.0 m door stops the eye")
	var wide_gap := EyeCollider.new(space, [], 0.4).move(Vector2(3.0, 0.0), Vector2(6.0, 0.0), HEIGHT)
	assert_almost_eq(wide_gap.x, 9.0, 0.001, "a thin sphere would walk in")


func test_an_excluded_body_and_other_layers_do_not_block() -> void:
	var wall := _wall_at_x5()
	await get_tree().physics_frame
	var rids: Array[RID] = [wall.get_rid()]
	var end := _collider(rids).move(Vector2.ZERO, Vector2(10.0, 0.0), HEIGHT)
	assert_almost_eq(end.x, 10.0, 0.001, "an excluded body (the ground's) is ignored")
	wall.queue_free()
	var token_layer := _body([_quad(5.0, -10.0, 5.0, 10.0, 0.0, 4.0)], 2)
	await get_tree().physics_frame
	assert_not_null(token_layer)
	var past := _collider().move(Vector2.ZERO, Vector2(10.0, 0.0), HEIGHT)
	assert_almost_eq(past.x, 10.0, 0.001, "a token (layer 2) is not a wall")


func test_a_roof_above_the_eye_does_not_stop_it_but_a_low_one_does() -> void:
	# A roof edge as a vertical face from y 2.5 up: clear of an eye at 1.6 (sphere top 1.95), met
	# by one at 2.2 (sphere 1.85 to 2.55).
	_body([_quad(5.0, -10.0, 5.0, 10.0, 2.5, 6.0)])
	await get_tree().physics_frame
	var clear := _collider().move(Vector2.ZERO, Vector2(10.0, 0.0), HEIGHT)
	assert_almost_eq(clear.x, 10.0, 0.001)
	var low_end := _collider().move(Vector2.ZERO, Vector2(10.0, 0.0), 2.2)
	assert_lt(low_end.x, 5.0, "a taller eye meets it")


func test_a_scaled_sphere_keeps_its_reach() -> void:
	_wall_at_x5()
	await get_tree().physics_frame
	var half := EyeCollider.new(_root.get_world_3d().direct_space_state, [], RADIUS * 0.5)
	var end := half.move(Vector2.ZERO, Vector2(10.0, 0.0), 0.8)
	assert_almost_eq(end.x, 5.0 - RADIUS * 0.5, 0.03)


func test_no_space_is_no_collision() -> void:
	var none := EyeCollider.new(null, [], RADIUS)
	assert_eq(none.move(Vector2.ZERO, Vector2(3.0, 0.0), HEIGHT), Vector2(3.0, 0.0))
