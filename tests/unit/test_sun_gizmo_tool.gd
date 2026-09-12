extends GutTest

## Pure geometry tests for SunGizmoTool's compass mapping
## (scenes/states/playing/sun_gizmo_tool.gd).
##
## The gizmo draws a ring on the Y=0 ground plane; the direction of the drag
## offset around its centre sets azimuth and the distance from the centre sets
## elevation, with the centre meaning overhead and the rim meaning horizon. The
## mapping is world-space and camera-independent: the handle lies along the
## direction the light travels across the ground, so it points where the shadows
## fall.
##
## These tests deliberately anchor azimuth to WORLD directions and, in
## test_the_handle_direction_matches_the_applied_lights_ground_travel(), close
## the loop through the real DefaultSun.apply(). An earlier screen-space
## implementation passed a round-trip-only suite while aiming the sun 70 to 200
## degrees away from the handle, because nothing tied either function to the
## world.
##
## Input dispatch and the overlay drawing are validated manually in the running
## game; only the math is unit tested.

const RING := 100.0

# --- Absolute world-direction anchors -----------------------------------------
# Light travel across the ground is (-sin A, 0, -cos A). These assert the handle
# offset against that relationship directly, not against the inverse function.


func test_a_handle_to_world_north_is_azimuth_zero() -> void:
	# travel for A = 0 is (-sin 0, 0, -cos 0) = (0, 0, -1), i.e. world north.
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(0.0, 0.0, -1.0), RING)

	assert_almost_eq(result.x, 0.0, 0.001)


func test_a_handle_to_world_negative_x_is_azimuth_ninety() -> void:
	# travel for A = 90 is (-sin 90, 0, -cos 90) = (-1, 0, 0).
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(-1.0, 0.0, 0.0), RING)

	assert_almost_eq(result.x, 90.0, 0.001)


func test_a_handle_to_world_south_is_azimuth_onehundredeighty() -> void:
	# travel for A = 180 is (-sin 180, 0, -cos 180) = (0, 0, 1).
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(0.0, 0.0, 1.0), RING)

	assert_almost_eq(result.x, 180.0, 0.001)


func test_a_handle_to_world_positive_x_is_azimuth_twoseventy() -> void:
	# travel for A = 270 is (-sin 270, 0, -cos 270) = (1, 0, 0).
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(1.0, 0.0, 0.0), RING)

	assert_almost_eq(result.x, 270.0, 0.001)


func test_azimuth_is_always_normalized_to_zero_through_threesixty() -> void:
	for offset in [
		Vector3(1.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 1.0),
	]:
		var azimuth := SunGizmoTool.direction_from_ground_offset(offset, RING).x
		assert_between(azimuth, 0.0, 360.0, "azimuth for offset %s" % offset)


func test_any_y_component_in_the_offset_is_ignored() -> void:
	# The offset is measured on the ground plane; a stray height must not tilt
	# the reading, so callers need not pre-flatten it.
	var flat := SunGizmoTool.direction_from_ground_offset(Vector3(0.0, 0.0, -RING), RING)
	var raised := SunGizmoTool.direction_from_ground_offset(Vector3(0.0, 12.0, -RING), RING)

	assert_almost_eq(raised.x, flat.x, 0.001)
	assert_almost_eq(raised.y, flat.y, 0.001)


# --- Elevation from radius (rotation-invariant, unchanged by the world-space fix)


func test_centre_of_the_ring_is_overhead() -> void:
	var result := SunGizmoTool.direction_from_ground_offset(Vector3.ZERO, RING)

	assert_almost_eq(result.y, 90.0, 0.001)


func test_rim_of_the_ring_is_the_horizon() -> void:
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(RING, 0.0, 0.0), RING)

	assert_almost_eq(result.y, 0.0, 0.001)


func test_halfway_out_is_halfway_down() -> void:
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(0.0, 0.0, -RING * 0.5), RING)

	assert_almost_eq(result.y, 45.0, 0.001)


func test_dragging_beyond_the_rim_clamps_to_the_horizon() -> void:
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(RING * 5.0, 0.0, 0.0), RING)

	assert_almost_eq(result.y, 0.0, 0.001)


func test_a_degenerate_ring_radius_does_not_divide_by_zero() -> void:
	var result := SunGizmoTool.direction_from_ground_offset(Vector3(10.0, 0.0, 10.0), 0.0)

	assert_almost_eq(result.y, 0.0, 0.001)


# --- The inverse ---------------------------------------------------------------


func test_ground_offset_is_flat_on_the_ground_plane() -> void:
	for azimuth in [0.0, 37.0, 180.0, 290.0]:
		var offset := SunGizmoTool.ground_offset_from_direction(azimuth, 30.0, RING)
		assert_almost_eq(offset.y, 0.0, 0.0001, "y for azimuth %f" % azimuth)


func test_ground_offset_places_the_handle_at_the_centre_when_overhead() -> void:
	var offset := SunGizmoTool.ground_offset_from_direction(0.0, 90.0, RING)

	assert_almost_eq(offset.length(), 0.0, 0.001)


func test_ground_offset_places_the_handle_on_the_rim_at_the_horizon() -> void:
	var offset := SunGizmoTool.ground_offset_from_direction(0.0, 0.0, RING)

	assert_almost_eq(offset.length(), RING, 0.001)


func test_ground_offset_at_azimuth_zero_points_world_north() -> void:
	var offset := SunGizmoTool.ground_offset_from_direction(0.0, 0.0, RING)

	assert_almost_eq(offset.x, 0.0, 0.001)
	assert_almost_eq(offset.z, -RING, 0.001)


func test_ground_offset_round_trips_through_direction_from_ground_offset() -> void:
	for azimuth in [0.0, 45.0, 135.0, 200.0, 315.0]:
		for elevation in [0.0, 22.5, 48.0, 90.0]:
			var offset := SunGizmoTool.ground_offset_from_direction(azimuth, elevation, RING)
			var back := SunGizmoTool.direction_from_ground_offset(offset, RING)

			assert_almost_eq(back.y, elevation, 0.01, "elevation %f" % elevation)
			# Azimuth is indeterminate exactly at the centre, where the handle
			# has no direction to read.
			if elevation < 90.0:
				assert_almost_eq(back.x, azimuth, 0.01, "azimuth %f" % azimuth)


func test_ground_offset_clamps_below_horizon_elevations_to_the_rim() -> void:
	# The gizmo covers the above-horizon hemisphere. Night elevations reachable
	# via the time-of-day generator must still render a handle, on the rim.
	var offset := SunGizmoTool.ground_offset_from_direction(90.0, -10.0, RING)

	assert_almost_eq(offset.length(), RING, 0.001)


# --- The loop closed through the real applier ----------------------------------


func test_the_handle_direction_matches_the_applied_lights_ground_travel() -> void:
	# The regression guard. Runs the full chain the gizmo drives -- handle offset
	# -> azimuth -> SunSettings -> DefaultSun.apply() -> DirectionalLight3D --
	# and asserts the light's shadows travel along the ground toward the handle.
	# The previous screen-space mapping -- Vector2(sin A, -cos A) read back as an
	# offset -- fails this everywhere except the two azimuths where sin A is 0.
	for azimuth in [0.0, 30.0, 45.0, 90.0, 135.0, 180.0, 250.0, 315.0]:
		var offset := SunGizmoTool.ground_offset_from_direction(azimuth, 40.0, RING)
		var read_back := SunGizmoTool.direction_from_ground_offset(offset, RING)

		var settings := SunSettings.new()
		settings.azimuth_degrees = read_back.x
		settings.elevation_degrees = read_back.y

		var light := DirectionalLight3D.new()
		DefaultSun.apply(light, settings)
		# A DirectionalLight3D shines along its local -Z. The light is an orphan,
		# so its local basis is its world basis.
		var travel := -light.transform.basis.z
		light.free()

		var travel_ground := Vector2(travel.x, travel.z).normalized()
		var handle_ground := Vector2(offset.x, offset.z).normalized()

		assert_almost_eq(
			travel_ground.x, handle_ground.x, 0.002, "travel.x for azimuth %f" % azimuth
		)
		assert_almost_eq(
			travel_ground.y, handle_ground.y, 0.002, "travel.z for azimuth %f" % azimuth
		)
