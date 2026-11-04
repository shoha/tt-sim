extends GutTest

## The prop boxes a dropped token keeps out of (PropFootprints, card eyepin option A3).

const RADIUS := 0.3


func after_each() -> void:
	PropFootprints.active = []
	PropFootprints.enabled = false


func test_stepping_off_the_props_is_off_by_default() -> void:
	assert_false(PropFootprints.enabled)


func _hay(at: Vector2, yaw: float = 0.0, scale: float = 1.0) -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{"prop": "haystack", "position": at, "yaw": yaw, "scale": scale}
	]
	return PropFootprints.boxes_of(items)


func test_only_bulky_props_make_boxes() -> void:
	var items: Array[Dictionary] = [
		{"prop": "haystack", "position": Vector2(1, 2), "yaw": 0.0, "scale": 1.0},
		{"prop": "lamp_post", "position": Vector2(3, 4), "yaw": 0.0, "scale": 1.0},
		{"prop": "bench", "position": Vector2(5, 6), "yaw": 0.0, "scale": 1.0},
		{"prop": "crate_stack", "position": Vector2(7, 8), "yaw": 0.5, "scale": 1.5},
	]
	var boxes := PropFootprints.boxes_of(items)
	assert_eq(boxes.size(), 2, "the haystack and the crate stack")
	assert_eq(boxes[0]["half"], Vector2(1.1, 1.0))
	assert_almost_eq((boxes[1]["half"] as Vector2).x, 0.975, 0.0001, "scaled by 1.5")


func test_a_point_that_is_clear_stays() -> void:
	var boxes := _hay(Vector2.ZERO)
	var far := Vector2(5.0, 5.0)
	assert_eq(PropFootprints.push_out(far, RADIUS, boxes), far)
	var edge := Vector2(1.1 + RADIUS + 0.01, 0.0)
	assert_eq(PropFootprints.push_out(edge, RADIUS, boxes), edge, "just outside the margin")


func test_a_point_inside_leaves_by_the_nearest_face() -> void:
	var boxes := _hay(Vector2.ZERO)
	var out := PropFootprints.push_out(Vector2(0.9, 0.1), RADIUS, boxes)
	assert_almost_eq(out.x, 1.1 + RADIUS, 0.0001, "out through the near +x face")
	assert_almost_eq(out.y, 0.1, 0.0001, "along the face's normal only")
	var up := PropFootprints.push_out(Vector2(0.2, -0.9), RADIUS, boxes)
	assert_almost_eq(up.y, -(1.0 + RADIUS), 0.0001, "out through the -z face")


func test_a_point_beside_a_corner_is_pushed_to_the_radius_from_the_corner() -> void:
	var boxes := _hay(Vector2.ZERO)
	var out := PropFootprints.push_out(Vector2(1.2, 1.1), RADIUS, boxes)
	assert_almost_eq(out.distance_to(Vector2(1.1, 1.0)), RADIUS, 0.0001)


func test_a_turned_box_is_turned() -> void:
	# 2.2 x 2.0 turned a quarter: it is 2.0 wide along world X now.
	var boxes := _hay(Vector2.ZERO, PI * 0.5)
	var inside := Vector2(1.05, 0.0)
	assert_gt(PropFootprints.push_out(inside, RADIUS, boxes).x, 1.05, "the +x face at 1.0 pushes out")
	var out := PropFootprints.push_out(Vector2(0.3, 1.0), RADIUS, boxes)
	assert_almost_eq(out.y, 1.1 + RADIUS, 0.0001, "the box is 2.2 along world Z now")


func test_two_boxes_side_by_side_leave_the_point_clear_of_both() -> void:
	var boxes := _hay(Vector2.ZERO)
	# One metre of ground between them: room for a token 0.6 across.
	boxes.append_array(_hay(Vector2(3.2, 0.0)))
	var out := PropFootprints.push_out(Vector2(1.3, 0.0), RADIUS, boxes)
	for box in boxes:
		var local: Vector2 = (out - (box["at"] as Vector2)).abs()
		var half: Vector2 = box["half"]
		assert_true(local.x >= half.x + RADIUS - 0.0001 or local.y >= half.y + RADIUS - 0.0001)


func test_clear_of_keeps_the_height_and_does_nothing_with_no_boxes() -> void:
	var p := Vector3(0.2, 3.5, 0.0)
	assert_eq(PropFootprints.clear_of(p, RADIUS), p, "no village, no boxes")
	PropFootprints.active = _hay(Vector2.ZERO)
	var moved := PropFootprints.clear_of(p, RADIUS)
	assert_eq(moved.y, 3.5)
	assert_ne(Vector2(moved.x, moved.z), Vector2(p.x, p.z))
