extends GutTest

## The canopy fade's pure parts (CanopyFade) and the camera's near-plane hold over
## the canopies (CameraController.near_plane_hold). The shader side is judged in renders:
## tools/render_jobs/jobs/pol_trees.json.

const HOME := 13.85
## The scene camera's back axis rises 0.368 per metre (21.6 degrees of pitch).
const BACK_Y := 0.36812454


func test_strength_is_the_play_strength_from_home_to_the_play_zoom_out() -> void:
	var play := CanopyFade.play_strength
	assert_almost_eq(CanopyFade.strength(HOME, HOME), play, 0.0001)
	assert_almost_eq(CanopyFade.strength(17.0, HOME), play, 0.0001)
	assert_almost_eq(CanopyFade.strength(CanopyFade.PLAY_MAX_SIZE, HOME), play, 0.0001)


func test_strength_fades_out_past_the_play_zoom_out() -> void:
	var s25 := CanopyFade.strength(25.0, HOME)
	assert_gt(s25, 0.0)
	assert_lt(s25, CanopyFade.play_strength)
	assert_eq(CanopyFade.strength(CanopyFade.FADE_OUT_SIZE, HOME), 0.0)
	assert_eq(CanopyFade.strength(60.0, HOME), 0.0)


func test_strength_ramps_to_full_as_the_camera_closes_in() -> void:
	var s12 := CanopyFade.strength(12.0, HOME)
	var s10 := CanopyFade.strength(10.0, HOME)
	assert_gt(s12, CanopyFade.play_strength)
	assert_gt(s10, s12)
	assert_eq(CanopyFade.strength(HOME * CanopyFade.FULL_FRACTION, HOME), 1.0)
	assert_eq(CanopyFade.strength(2.0, HOME), 1.0)


func test_the_window_grows_from_the_play_window_to_the_close_one() -> void:
	var home := CanopyFade.shape(HOME, HOME)
	assert_almost_eq(home.x, CanopyFade.play_inner * HOME, 0.0001)
	assert_almost_eq(home.y, CanopyFade.play_outer * HOME, 0.0001)
	var close_size := HOME * CanopyFade.FULL_FRACTION
	var close := CanopyFade.shape(close_size, HOME)
	assert_almost_eq(close.x, CanopyFade.CLOSE_INNER * close_size, 0.0001)
	assert_almost_eq(close.y, CanopyFade.CLOSE_OUTER * close_size, 0.0001)
	assert_almost_eq(close.z, CanopyFade.BAND * close_size, 0.0001)
	assert_lt(home.x, home.y)


func test_strength_is_off_without_a_home_size() -> void:
	assert_eq(CanopyFade.strength(6.0, 0.0), 0.0)


func test_the_brush_window_opens_from_its_centre_and_closes_back_in() -> void:
	CanopyFade.clear_brush()
	CanopyFade.step_brush(1.0)
	CanopyFade.set_brush(Vector3(2.0, 1.0, -3.0), 6.0)
	var half := CanopyFade.step_brush(CanopyFade.BRUSH_OPEN_S * 0.5)
	assert_eq(Vector3(half.x, half.y, half.z), Vector3(2.0, 1.0, -3.0), "at the ring")
	assert_almost_eq(half.w, 3.0, 0.0001, "half open: half the radius (smoothstep at 0.5)")
	var open := CanopyFade.step_brush(CanopyFade.BRUSH_OPEN_S)
	assert_almost_eq(open.w, 6.0, 0.0001, "open")
	CanopyFade.clear_brush()
	var closing := CanopyFade.step_brush(CanopyFade.BRUSH_CLOSE_S * 0.25)
	assert_eq(Vector3(closing.x, closing.y, closing.z), Vector3(2.0, 1.0, -3.0), "stays put")
	assert_between(closing.w, 0.1, 6.0, "closing from its edge")
	assert_eq(CanopyFade.step_brush(CanopyFade.BRUSH_CLOSE_S), Vector4.ZERO, "shut")


func test_plane_hit_finds_the_ground_along_the_ray() -> void:
	var dir := Vector3(-0.6574513, -BACK_Y, -0.6574513)
	var hit := CanopyFade.plane_hit(Vector3(10.0, 8.0, 10.0), dir, 0.0)
	assert_almost_eq(hit.y, 0.0, 0.0001)
	assert_almost_eq(hit.x, 10.0 - 0.6574513 * 8.0 / BACK_Y, 0.001)
	var raised := CanopyFade.plane_hit(Vector3(10.0, 8.0, 10.0), dir, 3.0)
	assert_almost_eq(raised.y, 3.0, 0.0001)


func test_plane_hit_returns_the_origin_for_a_level_ray() -> void:
	var origin := Vector3(1.0, 2.0, 3.0)
	assert_eq(CanopyFade.plane_hit(origin, Vector3(1.0, 0.0, 0.0), 0.0), origin)


func test_near_plane_hold_is_zero_when_the_origins_already_clear_the_floor() -> void:
	assert_eq(CameraController.near_plane_hold(30.0, 24.0, BACK_Y), 0.0)
	assert_eq(CameraController.near_plane_hold(24.0, 24.0, BACK_Y), 0.0)


func test_near_plane_hold_lifts_the_bottom_origins_onto_the_canopy_floor() -> void:
	# The home zoom's bottom corners stand 1.56 m up (8 m at the centre less 6.92 x 0.93);
	# pulled back by the hold along the view axis they rise to the clearance.
	var floor_y := CameraController.CANOPY_CLEARANCE
	for bottom: float in [1.56, 0.68, 0.5, -3.0]:
		var hold := CameraController.near_plane_hold(bottom, floor_y, BACK_Y)
		assert_gt(hold, 0.0)
		assert_almost_eq(bottom + hold * BACK_Y, floor_y, 0.0001, "bottom %.2f" % bottom)


func test_near_plane_hold_ignores_a_level_camera() -> void:
	assert_eq(CameraController.near_plane_hold(1.0, 24.0, 0.0), 0.0)
