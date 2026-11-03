extends GutTest

## ViewGround (the ground a view ray lands on at the eye) and the front-of-camera line helpers
## of CameraRig (view_key, front_segment, screen_segment, screen_runs), the maths the play tools
## use at the eye: the first ground a ray marches into, refused when grazing, the view centre
## ahead of the eye, and overlays that must not draw what is behind the camera.

var _camera: Camera3D


func before_each() -> void:
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_camera.make_current()


func _flat(_xz: Vector2) -> float:
	return 0.0


## A ridge 4 m high across z in [-8, -6], flat ground elsewhere.
func _ridge(xz: Vector2) -> float:
	return 4.0 if xz.y < -6.0 and xz.y > -8.0 else 0.0


func _down(pitch_deg: float) -> Vector3:
	return Vector3(0.0, -sin(deg_to_rad(pitch_deg)), -cos(deg_to_rad(pitch_deg)))


# --- too_flat ------------------------------------------------------------------------------


func test_too_flat_follows_the_ground_ray_limit() -> void:
	assert_true(ViewGround.too_flat(_down(3.0)), "3 degrees below the horizon")
	assert_true(ViewGround.too_flat(Vector3(0, 0, -1)), "horizontal")
	assert_true(ViewGround.too_flat(Vector3(0, 0.5, -1)), "upward")
	assert_false(ViewGround.too_flat(_down(EyeRig.MIN_GROUND_RAY_DEG + 0.5)))
	assert_false(ViewGround.too_flat(Vector3(0, -1, 0)), "straight down")


# --- march ---------------------------------------------------------------------------------


func test_march_finds_the_flat_ground() -> void:
	var hit: Variant = ViewGround.march(Vector3(0, 1.6, 0), _down(20.0), _flat)
	assert_not_null(hit)
	assert_almost_eq((hit as Vector3).z, -1.6 / tan(deg_to_rad(20.0)), 0.01)
	assert_almost_eq((hit as Vector3).y, 0.0, 0.01)


func test_march_finds_the_ground_far_off() -> void:
	var hit: Variant = ViewGround.march(Vector3(0, 1.6, 0), _down(6.5), _flat)
	assert_not_null(hit, "6.5 degrees reaches 14 m")
	assert_almost_eq((hit as Vector3).z, -1.6 / tan(deg_to_rad(6.5)), 0.05)


func test_march_refuses_a_grazing_ray() -> void:
	assert_null(ViewGround.march(Vector3(0, 1.6, 0), _down(3.0), _flat))
	assert_null(ViewGround.march(Vector3(0, 1.6, 0), Vector3(0, 0.2, -1), _flat))


func test_march_stops_at_the_first_ground_so_a_ridge_in_the_way_is_the_hit() -> void:
	# From 5 m up looking 30 degrees down, flat ground would be 8.7 m ahead, but the 4 m ridge
	# whose face stands at z -6 is hit first (1.5 m up its face), as it looks from the eye.
	var hit: Variant = ViewGround.march(Vector3(0, 5.0, 0), _down(30.0), _ridge)
	assert_not_null(hit)
	assert_almost_eq((hit as Vector3).z, -6.0, 0.05, "at the ridge face, not beyond it")
	assert_almost_eq((hit as Vector3).y, 5.0 - 6.0 * tan(deg_to_rad(30.0)), 0.05)


func test_march_has_no_hit_from_below_the_ground_or_without_a_height_function() -> void:
	assert_null(ViewGround.march(Vector3(0, -1.0, 0), _down(20.0), _flat))
	assert_null(ViewGround.march(Vector3(0, 1.6, 0), _down(20.0), Callable()))


func test_march_gives_up_past_its_distance() -> void:
	var drop := func(_xz: Vector2) -> float: return -1000.0
	assert_null(ViewGround.march(Vector3(0, 1.6, 0), _down(20.0), drop))


# --- eye_point -----------------------------------------------------------------------------


func test_eye_point_is_the_hit_when_it_lands_within_reach() -> void:
	var p := ViewGround.eye_point(Vector3(0, 1.6, 0), _down(45.0), 0.0)
	assert_almost_eq(p.z, -1.6, 0.01, "45 degrees down from 1.6 m lands 1.6 m ahead")
	assert_almost_eq(p.y, 0.0, 0.001)


func test_eye_point_is_held_ahead_when_the_ray_is_far_or_flat() -> void:
	var far := ViewGround.eye_point(Vector3(0, 1.6, 0), _down(8.0), 0.0)
	assert_almost_eq(far.z, -ViewGround.AHEAD_M, 0.001, "a far hit is held at the reach")
	var level := ViewGround.eye_point(Vector3(0, 1.6, 0), Vector3(0, 0, -1), 0.0)
	assert_almost_eq(level.z, -ViewGround.AHEAD_M, 0.001, "a level view is centred ahead")
	var up := ViewGround.eye_point(Vector3(0, 1.6, 0), Vector3(0, 0.6, -0.8), 0.0)
	assert_almost_eq(up.z, -ViewGround.AHEAD_M, 0.001, "looking up too")


func test_eye_point_follows_the_heading() -> void:
	var p := ViewGround.eye_point(Vector3(10, 1.6, 10), Vector3(1, 0, 0), 0.0)
	assert_almost_eq(p.x, 10.0 + ViewGround.AHEAD_M, 0.001)
	assert_almost_eq(p.z, 10.0, 0.001)


func test_eye_point_stands_on_the_height_function() -> void:
	var slope := func(xz: Vector2) -> float: return 2.0 + xz.x * 0.1
	var p := ViewGround.eye_point(Vector3(0, 3.6, 0), Vector3(1, 0, 0), 0.0, slope)
	assert_almost_eq(p.y, 2.0 + p.x * 0.1, 0.001)
	assert_almost_eq(p.x, ViewGround.AHEAD_M, 0.001)


func test_eye_point_looking_straight_down_is_under_the_eye() -> void:
	var p := ViewGround.eye_point(Vector3(4, 1.6, 7), Vector3(0, -1, 0), 0.0)
	assert_almost_eq(p.x, 4.0, 0.001)
	assert_almost_eq(p.z, 7.0, 0.001)


# --- CameraRig: the front of the camera ---------------------------------------------------


func test_view_key_changes_with_pose_lens_and_size() -> void:
	var before := CameraRig.view_key(_camera)
	assert_eq(CameraRig.view_key(_camera), before, "the same view, the same key")
	_camera.rotation_degrees = Vector3(0, 10, 0)
	assert_ne(CameraRig.view_key(_camera), before, "a turn about the eye")
	before = CameraRig.view_key(_camera)
	_camera.fov = 50.0
	assert_ne(CameraRig.view_key(_camera), before, "a lens change")
	before = CameraRig.view_key(_camera)
	_camera.size = 3.0
	assert_ne(CameraRig.view_key(_camera), before, "an orthographic size")


func test_front_segment_keeps_a_segment_in_front() -> void:
	var seg: Variant = CameraRig.front_segment(_camera, Vector3(0, 0, -2), Vector3(1, 0, -5))
	assert_not_null(seg)
	assert_eq((seg as Array)[0], Vector3(0, 0, -2))
	assert_eq((seg as Array)[1], Vector3(1, 0, -5))


func test_front_segment_drops_a_segment_behind() -> void:
	assert_null(CameraRig.front_segment(_camera, Vector3(0, 0, 2), Vector3(1, 0, 5)))


func test_front_segment_cuts_a_segment_that_crosses_the_eye_plane() -> void:
	var seg: Variant = CameraRig.front_segment(_camera, Vector3(0, 0, 4), Vector3(0, 0, -6))
	assert_not_null(seg)
	var start: Vector3 = (seg as Array)[0]
	assert_eq((seg as Array)[1], Vector3(0, 0, -6), "the end in front is kept")
	assert_almost_eq(start.z, -(_camera.near + CameraRig.FRONT_CLIP_M), 0.0001)
	assert_false(_camera.is_position_behind(start), "the cut end is drawable")


func test_screen_segment_is_empty_behind_and_two_points_in_front() -> void:
	assert_eq(CameraRig.screen_segment(_camera, Vector3(0, 0, 2), Vector3(1, 0, 5)).size(), 0)
	var seen := CameraRig.screen_segment(_camera, Vector3(-1, 0, -4), Vector3(1, 0, -4))
	assert_eq(seen.size(), 2)
	assert_lt(seen[0].x, seen[1].x)


func test_an_orthographic_camera_returns_the_segment_whole() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 10.0
	_camera.near = -50.0
	var seg: Variant = CameraRig.front_segment(_camera, Vector3(0, 0, 20), Vector3(0, 0, 30))
	assert_not_null(seg, "behind the camera's plane but in front of its negative near plane")
	assert_eq((seg as Array)[0], Vector3(0, 0, 20))


func test_clip_line_to_rect() -> void:
	var rect := Rect2(0, 0, 100, 50)
	var inside := CameraRig.clip_line_to_rect(Vector2(10, 10), Vector2(90, 40), rect)
	assert_eq(inside, PackedVector2Array([Vector2(10, 10), Vector2(90, 40)]), "unchanged inside")
	var cut := CameraRig.clip_line_to_rect(Vector2(50, 20), Vector2(50, 20000), rect)
	assert_eq(cut.size(), 2)
	assert_almost_eq(cut[1].y, 50.0, 0.001, "cut at the bottom edge")
	assert_almost_eq(cut[1].x, 50.0, 0.001)
	assert_eq(CameraRig.clip_line_to_rect(Vector2(-50, -50), Vector2(-10, 200), rect).size(), 0)
	assert_eq(CameraRig.clip_line_to_rect(Vector2(-10, 25), Vector2(110, 25), rect).size(), 2)
	assert_eq(CameraRig.clip_line_to_rect(Vector2(-10, 80), Vector2(110, 80), rect).size(), 0)


func test_screen_runs_is_one_run_when_all_in_front() -> void:
	var points := PackedVector3Array()
	for i in 9:
		var a := TAU * float(i) / 8.0
		points.append(Vector3(cos(a), 0.0, -5.0 + sin(a)))
	var runs := CameraRig.screen_runs(_camera, points)
	assert_eq(runs.size(), 1)
	assert_eq(runs[0].size(), 9)


func test_screen_runs_splits_a_ring_that_passes_behind_the_eye() -> void:
	# A ring of radius 4 about a point 1 m ahead of the eye: its near side is behind the camera.
	var points := PackedVector3Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		points.append(Vector3(4.0 * cos(a), 0.0, -1.0 + 4.0 * sin(a)))
	var runs := CameraRig.screen_runs(_camera, points)
	assert_gt(runs.size(), 0)
	for run in runs:
		assert_gt(run.size(), 1)
	var total := 0
	for run in runs:
		total += run.size()
	assert_lt(total, 33 + 2, "the part behind the eye is not drawn")


func test_screen_runs_of_a_line_wholly_behind_is_empty() -> void:
	var points := PackedVector3Array([Vector3(0, 0, 3), Vector3(1, 0, 5), Vector3(2, 0, 8)])
	assert_eq(CameraRig.screen_runs(_camera, points).size(), 0)
