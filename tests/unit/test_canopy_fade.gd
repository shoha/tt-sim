extends GutTest

## The close-zoom canopy fade's pure parts (CanopyFade) and the camera's near-plane hold
## below the home zoom (CameraController.near_plane_hold). The shader side is judged in
## renders: tools/render_jobs/jobs/pol_trees.json.

const HOME := 13.85
## The scene camera stands 8 m above the ground at its centre; its back axis rises 0.368
## per metre (21.6 degrees of pitch).
const HOME_HEIGHT := 8.0
const BACK_Y := 0.36812454


func test_strength_is_off_at_the_home_zoom_and_above() -> void:
	assert_eq(CanopyFade.strength(HOME, HOME), 0.0)
	assert_eq(CanopyFade.strength(20.0, HOME), 0.0)
	assert_eq(CanopyFade.strength(60.0, HOME), 0.0)


func test_strength_grows_as_the_camera_closes_in_and_is_full_by_the_full_fraction() -> void:
	var s12 := CanopyFade.strength(12.0, HOME)
	var s10 := CanopyFade.strength(10.0, HOME)
	assert_gt(s12, 0.0)
	assert_gt(s10, s12)
	assert_lt(s10, 1.0)
	assert_eq(CanopyFade.strength(HOME * CanopyFade.FULL_FRACTION, HOME), 1.0)
	assert_eq(CanopyFade.strength(2.0, HOME), 1.0)


func test_strength_is_off_without_a_home_size() -> void:
	assert_eq(CanopyFade.strength(6.0, 0.0), 0.0)


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


func test_near_plane_hold_is_zero_at_the_home_zoom_and_above() -> void:
	assert_eq(CameraController.near_plane_hold(HOME, HOME, HOME_HEIGHT, BACK_Y), 0.0)
	assert_eq(CameraController.near_plane_hold(20.0, HOME, HOME_HEIGHT, BACK_Y), 0.0)


func test_near_plane_hold_keeps_the_home_distance_to_the_ground_below_it() -> void:
	# The proportional offset puts the camera size / home x 8 m above the ground; the hold
	# backs it off along the view axis until it stands at the home zoom's 8 m again.
	for size: float in [12.0, 8.0, 6.0, 2.0]:
		var hold := CameraController.near_plane_hold(size, HOME, HOME_HEIGHT, BACK_Y)
		var height := HOME_HEIGHT * size / HOME + hold * BACK_Y
		assert_almost_eq(height, HOME_HEIGHT, 0.0001, "size %.1f" % size)


func test_near_plane_hold_ignores_a_level_or_missing_camera() -> void:
	assert_eq(CameraController.near_plane_hold(6.0, 0.0, HOME_HEIGHT, BACK_Y), 0.0)
	assert_eq(CameraController.near_plane_hold(6.0, HOME, HOME_HEIGHT, 0.0), 0.0)
