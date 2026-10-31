extends GutTest

## DragMath: the pure rules of dragging a token. The ground-resolve cases that need a terrain
## live in test_relief_gameplay.gd; here the threshold, the lift, the easing, the landing and
## the edge pan.

const EPS := 1e-4

# --- threshold ---------------------------------------------------------------------------


func test_threshold_is_inclusive() -> void:
	var anchor := Vector2(100, 100)
	assert_true(DragMath.threshold_reached(anchor, Vector2(105, 100), 5.0), "exactly 5 px begins")
	assert_false(DragMath.threshold_reached(anchor, Vector2(104, 100), 5.0), "4 px does not")


func test_threshold_is_distance_not_per_axis() -> void:
	var anchor := Vector2.ZERO
	assert_true(DragMath.threshold_reached(anchor, Vector2(3, 4), 5.0), "3-4-5 is 5 px away")
	assert_false(DragMath.threshold_reached(anchor, Vector2(3, 3), 5.0), "diagonal of 4.24")


func test_threshold_works_in_every_direction() -> void:
	assert_true(DragMath.threshold_reached(Vector2(50, 50), Vector2(44, 50), 5.0))
	assert_true(DragMath.threshold_reached(Vector2(50, 50), Vector2(50, 44), 5.0))


# --- the aimed ground point ----------------------------------------------------------------


func test_resolve_without_snap_or_resolver_is_the_hit() -> void:
	var hit := Vector3(1.1, 0.4, -2.3)
	assert_eq(DragMath.resolve_target_ground(hit, false, 1.524, Vector2.ZERO, Callable()), hit)


func test_resolve_with_snap_goes_to_the_cell_centre_and_keeps_the_hit_height() -> void:
	var hit := Vector3(0.2, 0.7, 0.3)
	var target := DragMath.resolve_target_ground(hit, true, 1.524, Vector2.ZERO, Callable())
	assert_almost_eq(target.x, 0.762, EPS)
	assert_almost_eq(target.z, 0.762, EPS)
	assert_almost_eq(target.y, 0.7, EPS)


func test_resolve_snap_respects_the_grid_origin() -> void:
	var hit := Vector3(0.2, 0.0, 0.3)
	var origin := Vector2(0.5, 0.0)
	var target := DragMath.resolve_target_ground(hit, true, 1.0, origin, Callable())
	assert_eq(target, ScaleUtils.snap_to_grid(hit, 1.0, origin))


# --- lift ----------------------------------------------------------------------------------


func test_lifted_target_adds_both_offsets_to_y_only() -> void:
	var target := DragMath.lifted_target(Vector3(2, 1, 3), 0.4, 0.25)
	assert_almost_eq(target.x, 2.0, EPS)
	assert_almost_eq(target.y, 1.65, EPS)
	assert_almost_eq(target.z, 3.0, EPS)


func test_lifted_target_with_lowered_wheel_goes_below() -> void:
	assert_almost_eq(DragMath.lifted_target(Vector3.ZERO, 0.4, -0.5).y, -0.1, EPS)


# --- easing --------------------------------------------------------------------------------


func test_eased_moves_a_fraction_of_the_gap() -> void:
	var next := DragMath.eased(Vector3.ZERO, Vector3(10, 0, 0), 20.0, 0.016)
	var expected := 10.0 * (1.0 - exp(-20.0 * 0.016))
	assert_almost_eq(next.x, expected, EPS)
	assert_gt(next.x, 0.0)
	assert_lt(next.x, 10.0, "never overshoots")


func test_eased_is_frame_rate_independent() -> void:
	# One 1/30 s step lands where two 1/60 s steps do.
	var target := Vector3(8, 2, -4)
	var one := DragMath.eased(Vector3.ZERO, target, 20.0, 1.0 / 30.0)
	var half := DragMath.eased(Vector3.ZERO, target, 20.0, 1.0 / 60.0)
	var two := DragMath.eased(half, target, 20.0, 1.0 / 60.0)
	assert_almost_eq(one.x, two.x, EPS)
	assert_almost_eq(one.y, two.y, EPS)
	assert_almost_eq(one.z, two.z, EPS)


func test_eased_with_no_time_does_not_move() -> void:
	assert_eq(DragMath.eased(Vector3(1, 2, 3), Vector3(9, 9, 9), 20.0, 0.0), Vector3(1, 2, 3))


# --- landing -------------------------------------------------------------------------------


func test_landing_takes_the_target_xz_and_leaves_y() -> void:
	var landed := DragMath.landing(Vector3(1000, 1000, 1000), Vector3(1003, 1000.25, 997), false)
	assert_eq(landed, Vector3(1003, 1000, 997))


func test_landing_with_a_resolver_lifts_a_low_body_to_the_target() -> void:
	var landed := DragMath.landing(Vector3(1000, 1000, 1000), Vector3(1003, 1001.8, 997), true)
	assert_almost_eq(landed.y, 1001.8, EPS, "never settles from inside the tier")


func test_landing_with_a_resolver_leaves_a_high_body_alone() -> void:
	var landed := DragMath.landing(Vector3(1000, 1002, 1000), Vector3(1003, 1000.25, 997), true)
	assert_almost_eq(landed.y, 1002.0, EPS, "the settle owns the descent")


# --- edge pan ------------------------------------------------------------------------------


func test_edge_pan_is_zero_in_the_middle() -> void:
	assert_eq(DragMath.edge_pan(Vector2(960, 540), Vector2(1920, 1080), 50.0), Vector2.ZERO)


func test_edge_pan_ramps_from_the_margin_to_the_edge() -> void:
	var size := Vector2(1920, 1080)
	assert_almost_eq(DragMath.edge_pan(Vector2(25, 540), size, 50.0).x, -0.5, EPS, "halfway in")
	assert_almost_eq(DragMath.edge_pan(Vector2(0, 540), size, 50.0).x, -1.0, EPS, "at the edge")
	assert_almost_eq(DragMath.edge_pan(Vector2(1895, 540), size, 50.0).x, 0.5, EPS)
	assert_almost_eq(DragMath.edge_pan(Vector2(1920, 540), size, 50.0).x, 1.0, EPS)
	assert_almost_eq(DragMath.edge_pan(Vector2(960, 25), size, 50.0).y, -0.5, EPS)
	assert_almost_eq(DragMath.edge_pan(Vector2(960, 1055), size, 50.0).y, 0.5, EPS)


func test_edge_pan_in_a_corner_pulls_both_axes() -> void:
	var pan := DragMath.edge_pan(Vector2(0, 1080), Vector2(1920, 1080), 50.0)
	assert_eq(pan, Vector2(-1, 1))


func test_edge_pan_exactly_at_the_margin_is_zero() -> void:
	assert_eq(DragMath.edge_pan(Vector2(50, 50), Vector2(1920, 1080), 50.0), Vector2.ZERO)
