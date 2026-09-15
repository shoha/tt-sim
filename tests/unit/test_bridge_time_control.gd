extends GutTest


func test_half_second_at_sixty_hz_is_thirty_frames() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(0.5, 60), 30)


func test_zero_duration_requests_no_frames() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(0.0, 60), 0)


func test_negative_duration_requests_no_frames() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(-1.0, 60), 0)


func test_sub_frame_duration_still_advances_one_frame() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(0.001, 60), 1)


func test_duration_rounds_to_nearest_frame() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(0.017, 60), 1)
	assert_eq(BridgeTimeControl.frames_for_duration(0.025, 60), 2)


func test_invalid_tick_rate_requests_no_frames() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(1.0, 0), 0)
	assert_eq(BridgeTimeControl.frames_for_duration(1.0, -60), 0)


func test_frame_count_is_clamped_to_maximum() -> void:
	assert_eq(BridgeTimeControl.frames_for_duration(10000.0, 60), BridgeTimeControl.MAX_STEP_FRAMES)


func test_duration_for_frames_is_the_inverse() -> void:
	assert_almost_eq(BridgeTimeControl.duration_for_frames(30, 60), 0.5, 0.0001)


func test_duration_for_frames_handles_invalid_tick_rate() -> void:
	assert_almost_eq(BridgeTimeControl.duration_for_frames(30, 0), 0.0, 0.0001)
