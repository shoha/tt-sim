extends GutTest

## The eye view's off-screen token indicator (TokenEdgeArrows) and the far pin's distance fade
## (TokenMarkers.eye_pin_fade): the pure rules (card eyepin). Both options are off by default.

const SIZE := Vector2(1000.0, 600.0)


func test_a_token_in_frame_has_no_arrow() -> void:
	var placed := TokenEdgeArrows.place(Vector3(0.0, 0.0, -5.0), Vector2(500.0, 300.0), SIZE)
	assert_true(placed.is_empty())


func test_a_token_past_the_right_edge_points_right_on_the_edge() -> void:
	var placed := TokenEdgeArrows.place(Vector3(9.0, 0.0, -5.0), Vector2(1400.0, 300.0), SIZE)
	assert_false(placed.is_empty())
	assert_almost_eq((placed.dir as Vector2).x, 1.0, 0.001, "points right")
	var edge := SIZE.x - TokenEdgeArrows.MARGIN_PX
	assert_almost_eq((placed.pos as Vector2).x, edge, 0.01, "on the edge")
	assert_almost_eq((placed.pos as Vector2).y, 300.0, 0.01, "at the height it would have")


func test_a_diagonal_token_lands_on_the_inset_rectangle() -> void:
	var placed := TokenEdgeArrows.place(Vector3(-9.0, 9.0, -5.0), Vector2(-600.0, -700.0), SIZE)
	var pos: Vector2 = placed.pos
	var m := TokenEdgeArrows.MARGIN_PX
	assert_between(pos.x, m - 0.01, SIZE.x - m + 0.01)
	assert_between(pos.y, m - 0.01, SIZE.y - m + 0.01)
	assert_true(pos.x < SIZE.x * 0.5 and pos.y < SIZE.y * 0.5, "up and to the left")


func test_a_token_behind_the_eye_points_to_the_side_it_is_on() -> void:
	var right := TokenEdgeArrows.place(Vector3(2.0, 0.0, 6.0), Vector2.ZERO, SIZE)
	var left := TokenEdgeArrows.place(Vector3(-2.0, 0.0, 6.0), Vector2.ZERO, SIZE)
	assert_gt((right.dir as Vector2).x, 0.9, "right of the line behind")
	assert_lt((left.dir as Vector2).x, -0.9, "left of the line behind")
	assert_almost_eq((right.pos as Vector2).x, SIZE.x - TokenEdgeArrows.MARGIN_PX, 0.01)


func test_the_chevron_tip_is_the_position_and_it_points_along_the_direction() -> void:
	var corners := TokenEdgeArrows.chevron(Vector2(100.0, 100.0), Vector2.RIGHT)
	assert_eq(corners[0], Vector2(100.0, 100.0))
	assert_lt(corners[1].x, 100.0, "the base lies behind the tip")
	assert_almost_eq(corners[1].x, corners[2].x, 0.001)
	assert_almost_eq(corners[1].y, -corners[2].y + 200.0, 0.001, "symmetric about the axis")


func test_the_label_is_whole_metres() -> void:
	assert_eq(TokenEdgeArrows.label_of(34.4), "34 m")
	assert_eq(TokenEdgeArrows.label_of(34.6), "35 m")


func test_the_far_pin_fades_in_between_near_and_full_distance() -> void:
	assert_eq(TokenMarkers.eye_pin_fade(2.0), 0.0, "a token beside the eye shows its model")
	assert_eq(TokenMarkers.eye_pin_fade(TokenMarkers.EYE_PIN_FULL_M), 1.0)
	assert_eq(TokenMarkers.eye_pin_fade(60.0), 1.0)
	var half_way := 0.5 * (TokenMarkers.EYE_PIN_NEAR_M + TokenMarkers.EYE_PIN_FULL_M)
	assert_between(TokenMarkers.eye_pin_fade(half_way), 0.4, 0.6)
	var small := TokenMarkers.eye_pin_fade(15.0, 1.0)
	var big := TokenMarkers.eye_pin_fade(15.0, 2.0)
	assert_gt(small, big, "the fade distances scale with the map")


func test_both_eye_options_are_off_by_default() -> void:
	var markers := TokenMarkers.new()
	assert_false(markers.eye_pins)
	assert_false(markers.eye_arrows)
	markers.free()
