extends GutTest

## The canopy fades' pure parts (CanopyFade: the brush window and the cut) and the camera's
## near-plane hold over the canopies (CameraController.near_plane_hold). The shader side is judged
## in renders: tools/render_jobs/jobs/pol_trees.json.

## The scene camera's back axis rises 0.368 per metre (21.6 degrees of pitch).
const BACK_Y := 0.36812454


func test_the_view_centre_window_is_gone() -> void:
	# Removed 2026-11-16 (review board d_canopy): no setting, no globals, no per-frame ray.
	var source := FileAccess.get_file_as_string("res://scenes/states/playing/canopy_fade.gd")
	for gone: String in ["static var enabled", "func strength(", "func shape(", "view_centre_ground"]:
		assert_false(source.contains(gone), gone)
	var settings := FileAccess.get_file_as_string("res://project.godot")
	assert_false(settings.contains("canopy_fade_centre"), "no centre global")
	assert_false(settings.contains("canopy_fade_shape"), "no shape global")
	assert_true(settings.contains("canopy_fade_view"), "the camera pass mark stays")


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


func test_the_cut_opens_and_closes_apart_from_the_brush_window() -> void:
	CanopyFade.clear_brush()
	CanopyFade.clear_cut()
	CanopyFade.step_brush(1.0)
	CanopyFade.step_cut(1.0)
	CanopyFade.set_cut(Vector3(1.0, 0.5, 4.0), 2.0)
	var half := CanopyFade.step_cut(CanopyFade.BRUSH_OPEN_S * 0.5)
	assert_eq(Vector3(half.x, half.y, half.z), Vector3(1.0, 0.5, 4.0), "at the piece")
	assert_almost_eq(half.w, 1.0, 0.0001, "half open: half the radius")
	assert_almost_eq(CanopyFade.step_cut(CanopyFade.BRUSH_OPEN_S).w, 2.0, 0.0001, "open")
	assert_eq(CanopyFade.step_brush(0.1), Vector4.ZERO, "the brush window stays shut")
	CanopyFade.set_cut(Vector3(1.0, 0.5, 4.0), 0.0)
	assert_eq(CanopyFade.cut_asked().w, 0.0, "a zero radius lets go")
	var closing := CanopyFade.step_cut(CanopyFade.BRUSH_CLOSE_S * 0.25)
	assert_eq(Vector3(closing.x, closing.y, closing.z), Vector3(1.0, 0.5, 4.0), "stays put")
	assert_between(closing.w, 0.1, 2.0, "closing from its edge")
	assert_eq(CanopyFade.step_cut(CanopyFade.BRUSH_CLOSE_S), Vector4.ZERO, "shut")


func test_a_brush_mode_asks_for_no_cut_by_default() -> void:
	var mode := BrushMode.new()
	assert_eq(mode.fade_cut(null), Vector4.ZERO, "only the Village tool's picked piece cuts")


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
