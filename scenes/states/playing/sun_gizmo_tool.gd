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
## The compass mapping is done in WORLD space on the Y=0 ground plane, not in
## screen pixels: the pointer ray is intersected with the ground and the offset
## from the ring centre is measured there. Direction around the ring sets
## azimuth, distance from the centre sets elevation, centre meaning overhead and
## rim meaning horizon. The handle is placed along the direction the light
## travels across the ground, so the handle always points the way the shadows
## fall.
##
## Doing this in screen space instead would silently bake in the camera's fixed
## 45-degree yaw and its isometric foreshortening, aiming the sun 70 to 200
## degrees away from the handle depending on the azimuth. World space is
## camera-independent, so an azimuth means the same world direction no matter
## where the camera sits or how far it is zoomed.
##
## The ring covers the above-horizon hemisphere only; below-horizon elevations
## (night, which DefaultSun.KEYFRAMES does use) remain reachable through the
## time-of-day generator and the numeric elevation field.

signal toggled(active: bool)
signal direction_changed(azimuth_degrees: float, elevation_degrees: float)

## Ring radius in WORLD units on the Y=0 ground plane. 4.5 units is roughly
## three default grid cells (1.524 each) and about a third of the ground span
## the default camera size (13.85) shows -- large enough to aim precisely,
## small enough not to blanket the map. Being in world units means the ring
## grows and shrinks on screen with zoom, unlike the fixed-pixel ring it
## replaced; that is the point, since the compass now belongs to the ground
## rather than to the screen, and the elevation each ground radius maps to stays
## the same no matter how the user zooms mid-aim.
const RING_RADIUS_WORLD: float = 4.5

## Segment count for the unprojected ground circle. 64 is smooth enough that
## the ellipse reads as a curve at any zoom this camera reaches.
const RING_SEGMENTS: int = 64
const RING_COLOR := Color(1.0, 0.85, 0.2, 0.8)
const HANDLE_RADIUS_PX: float = 7.0
const HANDLE_COLOR := Color(1.0, 0.95, 0.6, 1.0)
const RAY_COLOR := Color(1.0, 0.85, 0.2, 0.45)

var _camera: Camera3D = null
var _world_viewport: SubViewport = null
var _canvas_layer: CanvasLayer = null
var _draw_control: Control = null

var _active: bool = false
var _dragging: bool = false
var _azimuth_degrees: float = 0.0
var _elevation_degrees: float = 45.0

var _needs_redraw: bool = false
var _last_camera_size: float = -1.0
var _last_camera_pos := Vector3.INF


## Map a ground offset from the ring centre, in world units on the Y=0 plane,
## to Vector2(azimuth_degrees, elevation_degrees). Pure and camera-independent.
##
## DefaultSun.apply() writes azimuth as rotation_degrees.y and elevation as
## -rotation_degrees.x, which makes a DirectionalLight3D's travel direction
## (-basis.z) equal (-sin A * cos E, -sin E, -cos A * cos E). Its ground
## component is therefore (-sin A, 0, -cos A), and placing the handle along that
## direction -- where the shadows go -- inverts to A = atan2(-x, -z).
static func direction_from_ground_offset(offset: Vector3, ring_radius: float) -> Vector2:
	var azimuth := fposmod(rad_to_deg(atan2(-offset.x, -offset.z)), 360.0)
	var normalized := 1.0
	if ring_radius > 0.0:
		normalized = clampf(Vector2(offset.x, offset.z).length() / ring_radius, 0.0, 1.0)
	return Vector2(azimuth, 90.0 * (1.0 - normalized))


## Inverse of direction_from_ground_offset: where the handle sits, as a world
## offset from the ring centre on the Y=0 plane, for a given direction.
static func ground_offset_from_direction(
	azimuth_degrees: float, elevation_degrees: float, ring_radius: float
) -> Vector3:
	var normalized := clampf(elevation_degrees, 0.0, 90.0) / 90.0
	var radius := ring_radius * (1.0 - normalized)
	var angle := deg_to_rad(azimuth_degrees)
	return Vector3(-sin(angle), 0.0, -cos(angle)) * radius


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	_check_camera_changed()
	if _needs_redraw and _draw_control:
		_needs_redraw = false
		_draw_control.queue_redraw()


func setup(cam: Camera3D, viewport: SubViewport, overlay_parent: Node) -> void:
	_camera = cam
	_world_viewport = viewport
	_create_overlay(overlay_parent)


## Push the current sun direction in, so the handle starts where the sun already
## points and the panel's numeric fields stay authoritative.
func set_direction(azimuth_degrees: float, elevation_degrees: float) -> void:
	_azimuth_degrees = azimuth_degrees
	_elevation_degrees = elevation_degrees
	_mark_dirty()


func is_active() -> bool:
	return _active


func activate() -> void:
	if _active:
		return
	_active = true
	_dragging = false
	if _canvas_layer:
		_canvas_layer.visible = true
	set_process(true)
	_mark_dirty()
	toggled.emit(true)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_dragging = false
	if _canvas_layer:
		_canvas_layer.visible = false
	set_process(false)
	toggled.emit(false)


func toggle() -> void:
	if is_active():
		deactivate()
	else:
		activate()


## Process an input event. Returns true if the event was consumed and should not
## propagate further (e.g. to camera pan/drag systems).
func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			deactivate()
			return true
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if _dragging:
				_apply_drag()
			return true

	if event is InputEventMouseMotion and _dragging:
		_apply_drag()
		return true

	return false


## Read the pointer from the SubViewport rather than from the event, matching
## MeasureTool: the ray projection below is in SubViewport space, so the cursor
## must be read in that same space. InputEvent.position is in window space and
## only happens to agree today because SubViewportContainer has stretch = true.
##
## Both the ring centre and the pointer are resolved onto the Y=0 ground plane,
## so the drag is measured in world units and the resulting azimuth is a world
## direction rather than a screen angle.
func _apply_drag() -> void:
	if not _camera or not _world_viewport:
		return
	var centre := _viewport_centre_ground_point()
	if centre == Vector3.INF:
		return
	var pointer := _ground_point_at(_world_viewport.get_mouse_position())
	if pointer == Vector3.INF:
		return
	var direction := direction_from_ground_offset(pointer - centre, RING_RADIUS_WORLD)
	_azimuth_degrees = direction.x
	_elevation_degrees = direction.y
	_mark_dirty()
	direction_changed.emit(_azimuth_degrees, _elevation_degrees)


## World point where the ray through [param screen_pos] (in SubViewport space)
## meets the Y=0 ground plane, or Vector3.INF if it never does.
func _ground_point_at(screen_pos: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.INF
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t


## Ring centre: the point on the Y=0 ground plane at the centre of the viewport,
## so the compass sits in the world rather than floating in screen space.
func _viewport_centre_ground_point() -> Vector3:
	if not _camera or not _world_viewport:
		return Vector3.INF
	return _ground_point_at(Vector2(_world_viewport.size) * 0.5)


func _mark_dirty() -> void:
	_needs_redraw = true


## Compare current camera state to last frame; mark dirty if it moved or zoomed,
## so the ground-anchored ring stays put under a pan or zoom.
func _check_camera_changed() -> void:
	if not _camera:
		return
	var cam_size := _camera.size
	var cam_pos := _camera.global_position
	if cam_size != _last_camera_size or cam_pos != _last_camera_pos:
		_last_camera_size = cam_size
		_last_camera_pos = cam_pos
		_mark_dirty()


func _create_overlay(overlay_parent: Node) -> void:
	# Reuses the measure overlay layer: the two tools are mutually exclusive
	# (GameMap deactivates one when the other activates), and both need to draw
	# above the lo-fi post-processing shader so they are not pixelated by it.
	var overlay: Dictionary = MapOverlayUtils.create_overlay(
		overlay_parent, Constants.LAYER_MEASURE_OVERLAY, _on_draw_control_draw
	)
	_canvas_layer = overlay.canvas_layer
	_draw_control = overlay.draw_control
	_canvas_layer.visible = false


func _on_draw_control_draw() -> void:
	if not _active or not _draw_control or not _camera:
		return
	var centre := _viewport_centre_ground_point()
	if centre == Vector3.INF:
		return

	_draw_ground_ring(centre, RING_RADIUS_WORLD, 2.0)
	_draw_ground_ring(centre, RING_RADIUS_WORLD * 0.5, 1.0)

	var offset := ground_offset_from_direction(
		_azimuth_degrees, _elevation_degrees, RING_RADIUS_WORLD
	)
	var centre_screen := _camera.unproject_position(centre)
	var handle_screen := _camera.unproject_position(centre + offset)
	_draw_control.draw_line(centre_screen, handle_screen, RAY_COLOR, 2.0, true)
	_draw_control.draw_circle(handle_screen, HANDLE_RADIUS_PX, HANDLE_COLOR)


## Draw a circle that lives on the Y=0 ground plane, by unprojecting points
## around it. Under the fixed isometric camera this reads as a ground ellipse,
## which is both truer to where the compass actually is and a clearer cue that
## the handle's direction is a world direction, not a screen one.
func _draw_ground_ring(centre: Vector3, radius: float, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(RING_SEGMENTS + 1):
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		points.append(
			_camera.unproject_position(centre + Vector3(cos(angle), 0.0, sin(angle)) * radius)
		)
	_draw_control.draw_polyline(points, RING_COLOR, width, true)
