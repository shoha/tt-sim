extends GutTest

## Pure geometry tests for SunGizmoTool's compass mapping
## (scenes/states/playing/sun_gizmo_tool.gd).
##
## The gizmo draws a ring on the ground; drag angle around its centre sets
## azimuth and drag radius sets elevation, with the centre meaning overhead and
## the rim meaning horizon. Screen Y grows downward, so "up the screen" is -Y
## and is azimuth 0.
##
## Input dispatch and the overlay drawing are validated manually in the running
## game; only the math is unit tested.

const RING := 100.0


func test_drag_straight_up_is_azimuth_zero() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2(0.0, -RING), RING)

	assert_almost_eq(result.x, 0.0, 0.001)


func test_drag_sweeps_azimuth_clockwise_from_up() -> void:
	assert_almost_eq(SunGizmoTool.direction_from_drag(Vector2(RING, 0.0), RING).x, 90.0, 0.001)
	assert_almost_eq(SunGizmoTool.direction_from_drag(Vector2(0.0, RING), RING).x, 180.0, 0.001)
	assert_almost_eq(SunGizmoTool.direction_from_drag(Vector2(-RING, 0.0), RING).x, 270.0, 0.001)


func test_azimuth_is_always_normalized_to_zero_through_threesixty() -> void:
	for offset in [Vector2(1.0, -1.0), Vector2(-1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var azimuth := SunGizmoTool.direction_from_drag(offset, RING).x
		assert_between(azimuth, 0.0, 360.0, "azimuth for offset %s" % offset)


func test_centre_of_the_ring_is_overhead() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2.ZERO, RING)

	assert_almost_eq(result.y, 90.0, 0.001)


func test_rim_of_the_ring_is_the_horizon() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2(RING, 0.0), RING)

	assert_almost_eq(result.y, 0.0, 0.001)


func test_halfway_out_is_halfway_down() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2(0.0, -RING * 0.5), RING)

	assert_almost_eq(result.y, 45.0, 0.001)


func test_dragging_beyond_the_rim_clamps_to_the_horizon() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2(RING * 5.0, 0.0), RING)

	assert_almost_eq(result.y, 0.0, 0.001)


func test_a_degenerate_ring_radius_does_not_divide_by_zero() -> void:
	var result := SunGizmoTool.direction_from_drag(Vector2(10.0, 10.0), 0.0)

	assert_almost_eq(result.y, 0.0, 0.001)


func test_drag_from_direction_places_the_handle_at_the_centre_when_overhead() -> void:
	var handle := SunGizmoTool.drag_from_direction(0.0, 90.0, RING)

	assert_almost_eq(handle.length(), 0.0, 0.001)


func test_drag_from_direction_places_the_handle_on_the_rim_at_the_horizon() -> void:
	var handle := SunGizmoTool.drag_from_direction(0.0, 0.0, RING)

	assert_almost_eq(handle.length(), RING, 0.001)


func test_drag_from_direction_round_trips_through_direction_from_drag() -> void:
	for azimuth in [0.0, 45.0, 135.0, 200.0, 315.0]:
		for elevation in [0.0, 22.5, 48.0, 90.0]:
			var handle := SunGizmoTool.drag_from_direction(azimuth, elevation, RING)
			var back := SunGizmoTool.direction_from_drag(handle, RING)

			assert_almost_eq(back.y, elevation, 0.01, "elevation %f" % elevation)
			# Azimuth is indeterminate exactly at the centre, where the handle
			# has no direction to read.
			if elevation < 90.0:
				assert_almost_eq(back.x, azimuth, 0.01, "azimuth %f" % azimuth)


func test_drag_from_direction_clamps_below_horizon_elevations_to_the_rim() -> void:
	# The gizmo covers the above-horizon hemisphere. Night elevations reachable
	# via the time-of-day generator must still render a handle, on the rim.
	var handle := SunGizmoTool.drag_from_direction(90.0, -10.0, RING)

	assert_almost_eq(handle.length(), RING, 0.001)
