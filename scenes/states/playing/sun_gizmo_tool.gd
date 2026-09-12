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

## Ring radius in pixels. Fixed rather than derived from zoom so the drag
## sensitivity does not change under the user mid-aim.
const RING_RADIUS_PX: float = 120.0
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
## MeasureTool: the ring centre comes from Camera3D.unproject_position(), which
## is in SubViewport space, so the cursor must be read in that same space.
## InputEvent.position is in window space and only happens to agree today
## because SubViewportContainer has stretch = true.
func _apply_drag() -> void:
	if not _world_viewport:
		return
	var centre := _ring_centre_screen()
	if centre == Vector2.INF:
		return
	var pointer := _world_viewport.get_mouse_position()
	var direction := direction_from_drag(pointer - centre, RING_RADIUS_PX)
	_azimuth_degrees = direction.x
	_elevation_degrees = direction.y
	_mark_dirty()
	direction_changed.emit(_azimuth_degrees, _elevation_degrees)


## Screen position of the ring centre: the point on the Y=0 ground plane at the
## centre of the viewport, so the compass sits in the world rather than floating
## in screen space.
func _ring_centre_screen() -> Vector2:
	if not _camera or not _world_viewport:
		return Vector2.INF
	var ground := _viewport_centre_ground_point()
	if ground == Vector3.INF:
		return Vector2.INF
	return _camera.unproject_position(ground)


func _viewport_centre_ground_point() -> Vector3:
	var centre := Vector2(_world_viewport.size) * 0.5
	var from := _camera.project_ray_origin(centre)
	var dir := _camera.project_ray_normal(centre)
	if absf(dir.y) < 0.001:
		return Vector3.INF
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t


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
	if not _active or not _draw_control:
		return
	var centre := _ring_centre_screen()
	if centre == Vector2.INF:
		return

	_draw_control.draw_arc(centre, RING_RADIUS_PX, 0.0, TAU, 64, RING_COLOR, 2.0, true)
	_draw_control.draw_arc(centre, RING_RADIUS_PX * 0.5, 0.0, TAU, 48, RING_COLOR, 1.0, true)

	var handle := centre + drag_from_direction(_azimuth_degrees, _elevation_degrees, RING_RADIUS_PX)
	_draw_control.draw_line(centre, handle, RAY_COLOR, 2.0, true)
	_draw_control.draw_circle(handle, HANDLE_RADIUS_PX, HANDLE_COLOR)
