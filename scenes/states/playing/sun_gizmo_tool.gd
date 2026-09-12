class_name SunGizmoTool
extends Node

## Modal tool for aiming the level's sun by dragging a compass ring on the
## ground, so shadows can be art-directed directly instead of through a
## time-of-day slider.
##
## Follows the MeasureTool contract exactly (is_active/activate/deactivate/
## toggle/handle_input, plus a `toggled` signal), because GameMap dispatches both
## from the same place in _input() and CameraController suppresses RMB pan for
## both. Being modal is what keeps it from conflicting with DragAndDrop3D token
## dragging: tokens are not draggable while the gizmo is active.
##
## The compass mapping: drag angle around the ring centre sets azimuth, drag
## radius sets elevation, centre meaning overhead and rim meaning horizon.
## Screen Y grows downward, so "up the screen" is -Y and reads as azimuth 0.
## The ring covers the above-horizon hemisphere only; below-horizon elevations
## (night, which DefaultSun.KEYFRAMES does use) remain reachable through the
## time-of-day generator and the numeric elevation field.

signal toggled(active: bool)
signal direction_changed(azimuth_degrees: float, elevation_degrees: float)


## Map a drag offset from the ring centre, in pixels, to
## Vector2(azimuth_degrees, elevation_degrees).
static func direction_from_drag(offset: Vector2, ring_radius: float) -> Vector2:
	var azimuth := fposmod(rad_to_deg(atan2(offset.x, -offset.y)), 360.0)
	var normalized := 0.0
	if ring_radius > 0.0:
		normalized = clampf(offset.length() / ring_radius, 0.0, 1.0)
	else:
		normalized = 1.0
	return Vector2(azimuth, 90.0 * (1.0 - normalized))


## Inverse of direction_from_drag: where the handle sits, as an offset from the
## ring centre in pixels, for a given direction.
static func drag_from_direction(
	azimuth_degrees: float, elevation_degrees: float, ring_radius: float
) -> Vector2:
	var normalized := clampf(elevation_degrees, 0.0, 90.0) / 90.0
	var radius := ring_radius * (1.0 - normalized)
	var angle := deg_to_rad(azimuth_degrees)
	return Vector2(sin(angle), -cos(angle)) * radius
