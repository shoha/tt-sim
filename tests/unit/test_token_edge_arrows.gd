extends GutTest

## The eye view's off-screen token indicator (TokenEdgeArrows) and the far pin's distance fade
## (TokenMarkers.eye_pin_fade): the pure rules (card eyepin), the stacking of arrows along the
## edge, and that pins and arrows are on in the eye view and not in the orbit view.

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


func test_both_eye_options_are_on_by_default() -> void:
	var markers := TokenMarkers.new()
	assert_true(markers.eye_pins)
	assert_true(markers.eye_arrows)
	markers.free()


func test_the_eye_has_pins_and_arrows_and_the_orbit_view_does_not() -> void:
	assert_eq(TokenMarkers.strength_for(0.0, true, true), 1.0, "eye: whole at any pitch")
	assert_eq(TokenMarkers.strength_for(0.0, false, true), 0.0, "orbit, low pitch: none")
	assert_eq(TokenMarkers.strength_for(0.7, false, true), 0.7, "orbit keeps the pitch rule")
	assert_eq(TokenMarkers.strength_for(0.0, true, false), 0.0, "switch off")
	assert_true(TokenMarkers.arrows_wanted(true, true))
	assert_false(TokenMarkers.arrows_wanted(false, true), "no arrows in the orbit view")
	assert_false(TokenMarkers.arrows_wanted(true, false))


func test_a_perspective_camera_makes_the_arrows_and_an_orthographic_one_does_not() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var markers := TokenMarkers.attach(viewport, camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(markers.arrows_node(), "orbit: not even made")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(markers.arrows_node())
	assert_true(markers.arrows_node().visible, "eye: shown")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(markers.arrows_node().visible, "back in the orbit view: hidden")


# --- stacking ---


func _arrow(pos: Vector2, metres: float) -> Dictionary:
	return {"pos": pos, "dir": Vector2.RIGHT, "metres": metres, "id": int(metres)}


func _gap(a: Dictionary, b: Dictionary) -> float:
	var sa := TokenEdgeArrows.edge_param(a.pos, SIZE)
	var sb := TokenEdgeArrows.edge_param(b.pos, SIZE)
	return absf(sa - sb)


func test_the_edge_loop_parameter_and_point_are_inverses() -> void:
	var m := TokenEdgeArrows.MARGIN_PX
	for pos in [
		Vector2(SIZE.x - m, 200.0),
		Vector2(m, 100.0),
		Vector2(300.0, m),
		Vector2(700.0, SIZE.y - m),
		Vector2(200.0, SIZE.y - m),
		Vector2(m, m),
		Vector2(SIZE.x - m, SIZE.y - m),
	]:
		var s := TokenEdgeArrows.edge_param(pos, SIZE)
		assert_between(s, 0.0, TokenEdgeArrows.loop_length(SIZE))
		var back := TokenEdgeArrows.edge_point(s, SIZE)
		assert_almost_eq(back.x, pos.x, 0.01, "x of %s" % str(pos))
		assert_almost_eq(back.y, pos.y, 0.01, "y of %s" % str(pos))


func test_the_edge_loop_runs_clockwise_from_the_bottom_centre() -> void:
	var m := TokenEdgeArrows.MARGIN_PX
	var left := TokenEdgeArrows.edge_param(Vector2(m, 300.0), SIZE)
	var top := TokenEdgeArrows.edge_param(Vector2(500.0, m), SIZE)
	var right := TokenEdgeArrows.edge_param(Vector2(SIZE.x - m, 300.0), SIZE)
	assert_lt(left, top)
	assert_lt(top, right)


func test_a_lone_arrow_stays_where_it_was_placed() -> void:
	var one := _arrow(Vector2(SIZE.x - TokenEdgeArrows.MARGIN_PX, 250.0), 30.0)
	var out := TokenEdgeArrows.stack([one], SIZE)
	assert_eq(out.size(), 1)
	assert_almost_eq((out[0].pos as Vector2).x, one.pos.x, 0.01)
	assert_almost_eq((out[0].pos as Vector2).y, one.pos.y, 0.01)
	assert_eq(out[0].extra, 0)


func test_arrows_far_apart_are_left_alone() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var out := TokenEdgeArrows.stack(
		[_arrow(Vector2(x, 100.0), 30.0), _arrow(Vector2(x, 400.0), 40.0)], SIZE
	)
	assert_eq(out.size(), 2)
	var ys := [(out[0].pos as Vector2).y, (out[1].pos as Vector2).y]
	ys.sort()
	assert_almost_eq(ys[0], 100.0, 0.01)
	assert_almost_eq(ys[1], 400.0, 0.01)


func test_arrows_in_the_same_direction_fan_out_along_the_edge() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var out := TokenEdgeArrows.stack(
		[
			_arrow(Vector2(x, 300.0), 25.0),
			_arrow(Vector2(x, 304.0), 40.0),
			_arrow(Vector2(x, 296.0), 60.0)
		],
		SIZE
	)
	assert_eq(out.size(), 3)
	var ys: Array = []
	for a in out:
		assert_almost_eq((a.pos as Vector2).x, x, 0.01, "still on the right edge")
		ys.append((a.pos as Vector2).y)
	ys.sort()
	assert_almost_eq(ys[1] - ys[0], TokenEdgeArrows.SPACING_PX, 0.5)
	assert_almost_eq(ys[2] - ys[1], TokenEdgeArrows.SPACING_PX, 0.5)
	assert_almost_eq(ys[1], 300.0, 5.0, "centred on where they wanted to be")


func test_the_fan_keeps_each_arrow_pointing_at_its_own_token() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var a := _arrow(Vector2(x, 300.0), 25.0)
	a["dir"] = Vector2(1.0, 0.2).normalized()
	var b := _arrow(Vector2(x, 302.0), 40.0)
	b["dir"] = Vector2(1.0, -0.1).normalized()
	for result in TokenEdgeArrows.stack([a, b], SIZE):
		var want: Vector2 = a.dir if result.metres == 25.0 else b.dir
		assert_eq(result.dir, want)


func test_the_nearest_arrow_is_drawn_last_so_it_lies_in_front() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var out := TokenEdgeArrows.stack(
		[
			_arrow(Vector2(x, 300.0), 25.0),
			_arrow(Vector2(x, 300.0), 60.0),
			_arrow(Vector2(x, 300.0), 40.0)
		],
		SIZE
	)
	assert_eq(out[0].metres, 60.0)
	assert_eq(out[2].metres, 25.0)


func test_a_run_of_more_than_three_keeps_the_nearest_three_and_counts_the_rest() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var arrows: Array[Dictionary] = []
	for i in 6:
		arrows.append(_arrow(Vector2(x, 300.0 + float(i)), 20.0 + 10.0 * float(i)))
	var out := TokenEdgeArrows.stack(arrows, SIZE)
	assert_eq(out.size(), TokenEdgeArrows.FAN_MAX)
	var extras := 0
	for a in out:
		extras += int(a.extra)
		assert_lte(float(a.metres), 40.0, "the nearest three")
	assert_eq(extras, 3, "three left out")
	assert_eq(out[out.size() - 1].extra, 3, "carried by the nearest, drawn last")


func test_two_directions_make_two_separate_fans() -> void:
	var right := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var left := TokenEdgeArrows.MARGIN_PX
	var out := (
		TokenEdgeArrows
		. stack(
			[
				_arrow(Vector2(right, 300.0), 25.0),
				_arrow(Vector2(right, 303.0), 35.0),
				_arrow(Vector2(left, 300.0), 45.0),
				_arrow(Vector2(left, 302.0), 55.0),
				_arrow(Vector2(left, 298.0), 65.0),
			],
			SIZE
		)
	)
	assert_eq(out.size(), 5)
	var on_right := 0
	for a in out:
		on_right += 1 if (a.pos as Vector2).x > SIZE.x * 0.5 else 0
	assert_eq(on_right, 2)
	for i in out.size():
		for j in range(i + 1, out.size()):
			assert_gte(_gap(out[i], out[j]), TokenEdgeArrows.SPACING_PX - 1.0, "no two overlap")


func test_a_press_picks_the_arrow_under_it_and_the_nearer_centre_wins() -> void:
	var x := SIZE.x - TokenEdgeArrows.MARGIN_PX
	var arrows: Array[Dictionary] = [
		_arrow(Vector2(x, 100.0), 30.0), _arrow(Vector2(x, 400.0), 30.0)
	]
	var circle := TokenEdgeArrows.hit_circle(arrows[1].pos, arrows[1].dir)
	assert_eq(TokenEdgeArrows.pick(arrows, circle.centre), 1)
	assert_eq(TokenEdgeArrows.pick(arrows, Vector2(500.0, 250.0)), -1, "empty screen")


func test_an_arrow_is_bigger_than_the_old_half_size_chevron() -> void:
	assert_gte(TokenEdgeArrows.LENGTH_PX, 40.0)
	assert_gte(TokenEdgeArrows.LABEL_SIZE, 22)
	var corners := TokenEdgeArrows.chevron(Vector2.ZERO, Vector2.RIGHT, 2.0)
	assert_almost_eq(corners[1].x, -2.0 * TokenEdgeArrows.LENGTH_PX, 0.01, "grow scales the length")


func test_arrow_sizes_are_in_screen_pixels_whatever_the_window() -> void:
	var design := Vector2(1920.0, 1080.0)
	assert_almost_eq(TokenEdgeArrows.ui_unit(design, design), 1.0, 0.001)
	assert_almost_eq(
		TokenEdgeArrows.ui_unit(Vector2(960.0, 540.0), design), 2.0, 0.001, "half-size window"
	)
	assert_almost_eq(TokenEdgeArrows.ui_unit(Vector2(1280.0, 720.0), design), 1.5, 0.001)
	assert_almost_eq(TokenEdgeArrows.ui_unit(Vector2(3840.0, 2160.0), design), 0.5, 0.001)
	assert_almost_eq(
		TokenEdgeArrows.ui_unit(Vector2(1280.0, 1080.0), design), 1.5, 0.001, "the smaller ratio"
	)
	assert_lte(TokenEdgeArrows.ui_unit(Vector2(10.0, 10.0), design), 4.0, "clamped")


func test_the_eye_turns_toward_a_token_the_short_way() -> void:
	# Forward at yaw y is (-sin y, -cos y): yaw 0 looks -z, 90 looks -x (west), 270 looks +x.
	assert_almost_eq(CameraRig.yaw_toward(Vector2.ZERO, Vector2(0.0, -10.0), 0.0), 0.0, 0.01)
	assert_almost_eq(CameraRig.yaw_toward(Vector2.ZERO, Vector2(-10.0, 0.0), 0.0), 90.0, 0.01)
	assert_almost_eq(
		CameraRig.yaw_toward(Vector2.ZERO, Vector2(10.0, 0.0), 0.0),
		-90.0,
		0.01,
		"east is 90 the other way"
	)
	# From 350 degrees, a token at yaw 10 is 20 degrees round, not 340 back.
	var target := CameraRig.yaw_toward(
		Vector2.ZERO, Vector2(-sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0))) * 8.0, 350.0
	)
	assert_almost_eq(target, 370.0, 0.01)
