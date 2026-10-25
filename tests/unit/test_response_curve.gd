extends GutTest

## ResponseCurve: the response-curve editor's model (presets, add/remove/move with snapping and
## the contract's rules, the engine's piecewise-linear sampling).


func test_every_preset_is_a_valid_curve_on_every_evaluated_axis() -> void:
	for axis in ResponseCurve.axes():
		for shape in ResponseCurve.PRESETS:
			var points := ResponseCurve.preset(axis, shape)
			assert_eq(ResponseCurve.problem(axis, points), "", "%s %s" % [axis, shape])
			assert_eq(ResponseCurve.preset_of(axis, points), shape)


func test_the_evaluated_axes_include_water_dist_since_s12c() -> void:
	assert_eq(ResponseCurve.axes(), ["slope", "height", "wet", "water_dist"])


func test_sample_matches_the_engine_curve_value() -> void:
	var points: Array = [[10.0, 0.0], [30.0, 1.0], [50.0, 0.25], [80.0, 1.0]]
	var flat := ScatterPlan.flatten_curve(points)
	for x in [-5.0, 0.0, 10.0, 12.5, 30.0, 41.0, 50.0, 65.0, 80.0, 90.0]:
		assert_almost_eq(ResponseCurve.sample(points, x), ScatterPlan.curve_value(flat, x), 0.0001)
	assert_eq(ResponseCurve.sample([], 3.0), 1.0, "no curve changes nothing")


func test_flat_and_is_flat() -> void:
	assert_true(ResponseCurve.is_flat(ResponseCurve.flat("slope")))
	assert_false(ResponseCurve.is_flat(ResponseCurve.preset("slope", "bell")))
	assert_eq(ResponseCurve.describe(ResponseCurve.flat("wet")), "flat")
	assert_eq(ResponseCurve.describe([]), "off")


func test_add_point_inserts_in_order_with_the_curve_value() -> void:
	var points := ResponseCurve.preset("slope", "ramp_up")
	var added := ResponseCurve.add_point("slope", points, 45.0)
	assert_eq(added.size(), 3)
	assert_eq(added[1], [45.0, 0.5])
	assert_eq(ResponseCurve.problem("slope", added), "")
	var again := ResponseCurve.add_point("slope", added, 45.2)
	assert_eq(again.size(), 3, "a point is not added on top of another")


func test_add_point_stops_at_the_limit_and_snaps() -> void:
	var points := ResponseCurve.flat("wet")
	for i in 10:
		points = ResponseCurve.add_point("wet", points, 0.07 + 0.09 * i)
	assert_eq(points.size(), LibraryContracts.RESPONSE_MAX_POINTS)
	assert_eq(ResponseCurve.problem("wet", points), "")
	for point: Array in points:
		assert_almost_eq(fmod(float(point[0]) / 0.05 + 0.0001, 1.0), 0.0, 0.01, "x snaps to 0.05")


func test_remove_point_keeps_two() -> void:
	var points := ResponseCurve.preset("slope", "bell")
	assert_eq(ResponseCurve.remove_point(points, 2).size(), 4)
	var two := ResponseCurve.flat("slope")
	assert_eq(ResponseCurve.remove_point(two, 0).size(), 2)
	assert_eq(ResponseCurve.remove_point(points, 9).size(), 5)


func test_move_point_snaps_clamps_and_never_passes_a_neighbour() -> void:
	var points: Array = [[0.0, 0.0], [30.0, 1.0], [60.0, 1.0], [90.0, 0.0]]
	var moved := ResponseCurve.move_point("slope", points, 1, 33.4, 0.62)
	assert_eq(moved[1], [33.0, 0.6])
	var blocked := ResponseCurve.move_point("slope", points, 1, 80.0, 2.0)
	assert_true(float(blocked[1][0]) < 60.0, "held before the next point")
	assert_eq(blocked[1][1], 1.0, "y held to 1")
	assert_eq(ResponseCurve.problem("slope", blocked), "")
	var low := ResponseCurve.move_point("slope", points, 3, -50.0, -1.0)
	assert_true(float(low[3][0]) > 60.0)
	assert_eq(low[3][1], 0.0)
	var free := ResponseCurve.move_point("slope", points, 1, 33.4, 0.62, false)
	assert_eq(free[1], [33.4, 0.62], "no snapping when asked")


func test_the_height_axis_widens_the_view_for_points_outside_it() -> void:
	assert_eq(ResponseCurve.display_range("height"), Vector2(-2.0, 12.0))
	assert_eq(
		ResponseCurve.display_range("height", [[-5.0, 1.0], [40.0, 0.0]]), Vector2(-5.0, 40.0)
	)
	assert_eq(ResponseCurve.axis_range("height"), Vector2(-500.0, 5000.0))


func test_the_input_is_never_changed() -> void:
	var points: Array = [[0.0, 0.0], [90.0, 1.0]]
	var copy := points.duplicate(true)
	ResponseCurve.add_point("slope", points, 40.0)
	ResponseCurve.move_point("slope", points, 0, 10.0, 0.5)
	ResponseCurve.remove_point(points, 0)
	assert_eq(points, copy)
