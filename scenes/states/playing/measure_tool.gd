extends Node
class_name MeasureTool

## Measurement tool for the game map.
## Allows players to measure distances between points on the terrain (or tokens).
##
## Usage:
##   1. Call setup() after instantiation to provide camera, viewport, and overlay parent.
##   2. Call configure() after a level loads to provide scale settings.
##   3. GameMap feeds input via handle_input() — returns true if the event was consumed.
##
## State machine:
##   INACTIVE ──(activate)──► PLACING_START ──(click)──► PLACING_WAYPOINT
##   PLACING_WAYPOINT ──(click)──► PLACING_WAYPOINT (adds waypoint)
##   PLACING_WAYPOINT / PLACING_START ──(deactivate / right-click / Escape)──► INACTIVE

signal toggled(active: bool)

enum State { INACTIVE, PLACING_START, PLACING_WAYPOINT, PLACING_VOLUME_CENTER, PLACING_VOLUME_RADIUS }

enum Mode { LINE, SPHERE, CYLINDER }

## Returns the next mode in the cycle: LINE -> SPHERE -> CYLINDER -> LINE.
static func advance_mode(current: Mode) -> Mode:
	return (current + 1) % 3 as Mode

const TERRAIN_COLLISION_LAYER: int = 1
const TOKEN_COLLISION_LAYER: int = 2
const RAYCAST_LENGTH: float = 200.0

## 2D visual constants (pixel units — rendered on a CanvasLayer above the lo-fi shader)
const LINE_WIDTH_PX: float = 2.5
const DASH_LENGTH_PX: float = 8.0
const DASH_GAP_PX: float = 6.0
const ENDPOINT_RADIUS_PX: float = 5.0
const LINE_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const PREVIEW_LINE_COLOR := Color(1.0, 0.85, 0.2, 0.5)
const ENDPOINT_COLOR := Color(1.0, 0.85, 0.2, 1.0)

## Elevation threshold — below this delta (in world meters), treat as flat.
const ELEVATION_THRESHOLD: float = 0.15

## References — set once via setup()
var _camera: Camera3D
var _world_viewport: SubViewport

## Scale configuration — updated via configure()
var _grid_cell_size: float = 1.524
var _display_unit: String = "ft"
var _display_unit_per_cell: float = 5.0

## State
var _state: State = State.INACTIVE
var _mode: Mode = Mode.LINE

## Volume mode state
var _volume_center: Vector3 = Vector3.ZERO
var _volume_radius: float = 0.0
var _has_locked_volume: bool = false
var _volume_overlay: VolumeOverlay  # created in setup()

var _waypoints: PackedVector3Array = PackedVector3Array()
var _preview_point: Vector3 = Vector3.ZERO
var _has_preview: bool = false

## Screen-space overlay (CanvasLayer so it renders above the lo-fi shader)
var _canvas_layer: CanvasLayer
var _draw_control: Control
var _total_label_panel: PanelContainer
var _total_label: Label
var _segment_label_pool: Array[PanelContainer] = []

## Cached per-frame data to avoid redundant computation
var _cached_points: PackedVector3Array = PackedVector3Array()
var _screen_points: PackedVector2Array = PackedVector2Array()
var _committed_count: int = 0

## 2D position of the cursor dot shown during PLACING_START (before first click)
var _cursor_dot: Vector2 = Vector2.ZERO
var _show_cursor_dot: bool = false

## Dirty flag — only redraw when something changed
var _needs_redraw: bool = false

## Camera state tracking — detect zoom/pan so we redraw when the camera moves
var _last_camera_size: float = 0.0
var _last_camera_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	set_process(false)
	# Process after GameMap (default priority 0) so camera zoom/pan
	# interpolation has already run when we project 3D → 2D.
	process_priority = 1


func _process(_delta: float) -> void:
	_check_camera_changed()
	if not _needs_redraw:
		return
	_needs_redraw = false
	_do_redraw()
	_update_label_positions()


# ============================================================================
# Setup & Configuration
# ============================================================================


## One-time initialization. Call after instantiation.
## [param cam] The Camera3D inside the SubViewport.
## [param viewport] The SubViewport containing the 3D scene.
## [param overlay_parent] A node in the main scene tree (e.g. GameMap) for the
## crisp 2D overlay (lines + label) that sits above the lo-fi shader.
func setup(cam: Camera3D, viewport: SubViewport, overlay_parent: Node) -> void:
	_camera = cam
	_world_viewport = viewport
	_create_overlay(overlay_parent)


## Configure scale settings. Call after level load and when scale changes.
func configure(grid_cell_size: float, display_unit: String, display_unit_per_cell: float) -> void:
	_grid_cell_size = grid_cell_size
	_display_unit = display_unit
	_display_unit_per_cell = display_unit_per_cell
	_mark_dirty()


# ============================================================================
# Public API
# ============================================================================


## Returns true when the measure tool is actively capturing input.
func is_active() -> bool:
	return _state != State.INACTIVE


func activate() -> void:
	if _state != State.INACTIVE:
		return
	_state = State.PLACING_START if _mode == Mode.LINE else State.PLACING_VOLUME_CENTER
	_waypoints.clear()
	_has_preview = false
	_has_locked_volume = false
	_clear_visuals()
	_push_measure_hints()
	set_process(true)
	toggled.emit(true)


func deactivate() -> void:
	_state = State.INACTIVE
	_waypoints.clear()
	_has_preview = false
	_has_locked_volume = false
	if _volume_overlay:
		_volume_overlay.clear()
	_clear_visuals()
	_pop_measure_hints()
	set_process(false)
	toggled.emit(false)


func toggle() -> void:
	if is_active():
		deactivate()
	else:
		activate()


## Process an input event. Returns true if the event was consumed and should
## not propagate further (e.g. to camera pan/drag systems).
func handle_input(event: InputEvent) -> bool:
	if _state == State.INACTIVE:
		return false

	if event is InputEventMouseMotion:
		_update_preview()
		return false

	if event is InputEventMouseButton:
		return _handle_mouse_button(event)

	if event is InputEventKey:
		return _handle_key(event)

	return false


# ============================================================================
# Input Handling (private)
# ============================================================================


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _handle_left_click(event.ctrl_pressed)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_measurement()
		return true
	return false


func _handle_key(event: InputEventKey) -> bool:
	if event.pressed and event.keycode == KEY_TAB:
		_cycle_mode()
		return true
	if event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_measurement()
		return true
	return false


func _handle_left_click(ctrl_held: bool) -> bool:
	var hit := _raycast(ctrl_held)
	if hit == Vector3.INF:
		return false

	match _state:
		State.PLACING_START:
			_waypoints.clear()
			_waypoints.append(hit)
			_state = State.PLACING_WAYPOINT
			_mark_dirty()
			AudioManager.play_tick()
			return true
		State.PLACING_WAYPOINT:
			_waypoints.append(hit)
			_mark_dirty()
			AudioManager.play_tick()
			return true
		State.PLACING_VOLUME_CENTER:
			_volume_center = hit
			_volume_radius = 0.0
			_state = State.PLACING_VOLUME_RADIUS
			_mark_dirty()
			AudioManager.play_tick()
			return true
		State.PLACING_VOLUME_RADIUS:
			if _has_preview:
				_volume_radius = Vector2(_preview_point.x, _preview_point.z).distance_to(
					Vector2(_volume_center.x, _volume_center.z)
				)
				_has_locked_volume = true
				_state = State.PLACING_VOLUME_CENTER
				_redraw_locked_volume()
				_mark_dirty()
				AudioManager.play_tick()
			return true
	return false


func _cancel_measurement() -> void:
	if _state == State.PLACING_WAYPOINT and _waypoints.size() > 1:
		_waypoints.resize(_waypoints.size() - 1)
		_mark_dirty()
		if _waypoints.size() < 1:
			_state = State.PLACING_START
			if _total_label_panel:
				_total_label_panel.visible = false
			for panel in _segment_label_pool:
				panel.visible = false
	elif _state == State.PLACING_VOLUME_RADIUS:
		_state = State.PLACING_VOLUME_CENTER
		_has_preview = false
		if _volume_overlay:
			if _has_locked_volume:
				_redraw_locked_volume()
			else:
				_volume_overlay.clear()
		_mark_dirty()
	elif _state == State.PLACING_VOLUME_CENTER:
		if _has_locked_volume:
			_has_locked_volume = false
			_volume_radius = 0.0
			if _volume_overlay:
				_volume_overlay.clear()
			_mark_dirty()
		else:
			deactivate()
	elif (
		_state == State.PLACING_START
		or (_state == State.PLACING_WAYPOINT and _waypoints.size() <= 1)
	):
		deactivate()


## Update the live preview point from the SubViewport mouse position.
func _update_preview() -> void:
	var hit := _raycast(Input.is_key_pressed(KEY_CTRL))
	if hit != Vector3.INF:
		_preview_point = hit
		_has_preview = true
	else:
		_has_preview = false
	_mark_dirty()


func _mark_dirty() -> void:
	_needs_redraw = true


## Compare current camera state to last frame; mark dirty if it moved or zoomed.
func _check_camera_changed() -> void:
	if not _camera:
		return
	var cam_size := _camera.size
	var cam_pos := _camera.global_position
	if cam_size != _last_camera_size or cam_pos != _last_camera_pos:
		_last_camera_size = cam_size
		_last_camera_pos = cam_pos
		_mark_dirty()


# ============================================================================
# Raycasting
# ============================================================================


## Raycast against terrain (and optionally tokens).
## Returns the hit position or Vector3.INF if nothing was hit.
## Uses the SubViewport's mouse position because Camera3D.project_ray_origin
## works in the camera's own viewport space, not the main window's space.
func _raycast(include_tokens: bool = false) -> Vector3:
	if not _camera or not _world_viewport:
		return Vector3.INF

	var world: World3D = _world_viewport.find_world_3d()
	if not world:
		return Vector3.INF

	var space_state := world.direct_space_state
	if not space_state:
		return Vector3.INF

	var vp_mouse := _world_viewport.get_mouse_position()
	var from := _camera.project_ray_origin(vp_mouse)
	var to := from + _camera.project_ray_normal(vp_mouse) * RAYCAST_LENGTH

	if include_tokens:
		var token_hit := _raycast_layer(space_state, from, to, TOKEN_COLLISION_LAYER)
		if not token_hit.is_empty():
			var collider = token_hit.collider
			if collider:
				return Vector3(
					collider.global_position.x,
					token_hit.position.y,
					collider.global_position.z,
				)

	var terrain_hit := _raycast_layer(space_state, from, to, TERRAIN_COLLISION_LAYER)
	if not terrain_hit.is_empty():
		return terrain_hit.position

	return Vector3.INF


func _raycast_layer(
	space_state: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	layer: int,
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = layer
	return space_state.intersect_ray(query)


# ============================================================================
# Distance Calculation
# ============================================================================


## Calculate distance metrics from the cached points.
## Returns {horizontal: float, elevation: float, direct: float}.
func _calculate_distances(points: PackedVector3Array) -> Dictionary:
	if points.size() < 2:
		return {horizontal = 0.0, elevation = 0.0, direct = 0.0}

	var total_h := 0.0
	var total_d := 0.0
	var total_elev := 0.0

	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		total_h += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		total_d += a.distance_to(b)
		total_elev += b.y - a.y

	return {horizontal = total_h, elevation = total_elev, direct = total_d}


## Build the combined waypoints + optional preview point array.
## Also records how many are committed (for rendering the preview differently).
func _build_points() -> PackedVector3Array:
	var pts := _waypoints.duplicate()
	_committed_count = pts.size()
	if _has_preview and _state == State.PLACING_WAYPOINT:
		pts.append(_preview_point)
	return pts


# ============================================================================
# Rendering — 2D overlay (drawn on _draw_control in the CanvasLayer)
# ============================================================================


func _clear_visuals() -> void:
	_screen_points.clear()
	_cached_points.clear()
	_show_cursor_dot = false
	_committed_count = 0
	if _draw_control:
		_draw_control.queue_redraw()
	if _total_label_panel:
		_total_label_panel.visible = false
	for panel in _segment_label_pool:
		panel.visible = false


func _current_volume_shape() -> VolumeOverlay.Shape:
	return VolumeOverlay.Shape.SPHERE if _mode == Mode.SPHERE else VolumeOverlay.Shape.CYLINDER


func _redraw_locked_volume() -> void:
	if not _volume_overlay or not _has_locked_volume:
		return
	var label := ScaleUtils.format_distance(
		_volume_radius, _grid_cell_size, _display_unit_per_cell, _display_unit
	)
	_volume_overlay.show(_current_volume_shape(), _volume_center, _volume_radius, label, false)


func _redraw_volume_preview() -> void:
	if not _volume_overlay or not _has_preview:
		return
	var radius := Vector2(_preview_point.x, _preview_point.z).distance_to(
		Vector2(_volume_center.x, _volume_center.z)
	)
	if radius < 0.01:
		return
	var label := ScaleUtils.format_distance(
		radius, _grid_cell_size, _display_unit_per_cell, _display_unit
	)
	_volume_overlay.show(_current_volume_shape(), _volume_center, radius, label, true)


func _do_redraw() -> void:
	# Volume mode — skip line rendering entirely
	if _mode != Mode.LINE:
		if _state != State.INACTIVE and _has_preview and _camera:
			_cursor_dot = _camera.unproject_position(_preview_point)
			_show_cursor_dot = true
		else:
			_show_cursor_dot = false
		if _draw_control:
			_draw_control.queue_redraw()
		if _state == State.PLACING_VOLUME_RADIUS:
			_redraw_volume_preview()
		return

	# Show a cursor dot at the mouse position whenever there's a preview hit.
	# In PLACING_START this is the only visual; in PLACING_WAYPOINT it reinforces
	# the endpoint of the tentative segment (especially useful when very short).
	if _state != State.INACTIVE and _has_preview and _camera:
		_cursor_dot = _camera.unproject_position(_preview_point)
		_show_cursor_dot = true
	else:
		_show_cursor_dot = false

	# Build and cache points once per frame
	_cached_points = _build_points()

	if _cached_points.size() < 2:
		_screen_points.clear()
		if _draw_control:
			_draw_control.queue_redraw()
		if _total_label_panel:
			_total_label_panel.visible = false
		for panel in _segment_label_pool:
			panel.visible = false
		return

	# Project 3D waypoints to 2D screen coordinates
	_screen_points.clear()
	for pt in _cached_points:
		_screen_points.append(_camera.unproject_position(pt))

	if _draw_control:
		_draw_control.queue_redraw()

	var segment_count := _cached_points.size() - 1

	# Update per-segment labels
	var has_preview_seg := _cached_points.size() > _committed_count
	_ensure_segment_label_count(segment_count)
	for i in range(segment_count):
		var a: Vector3 = _cached_points[i]
		var b: Vector3 = _cached_points[i + 1]
		var h_dist := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var seg_text := ScaleUtils.format_distance(
			h_dist, _grid_cell_size, _display_unit_per_cell, _display_unit
		)
		var panel: PanelContainer = _segment_label_pool[i]
		var lbl: Label = panel.get_child(0) as Label
		lbl.text = seg_text

		# Hide the preview (tentative) segment label when it's too short on
		# screen — prevents overlap with the total label and the previous endpoint.
		var is_preview_seg := has_preview_seg and i == segment_count - 1
		if is_preview_seg:
			var screen_len := _screen_points[i].distance_to(_screen_points[i + 1])
			panel.visible = screen_len > 80.0
		else:
			panel.visible = true

	# Hide any excess pooled labels
	for i in range(segment_count, _segment_label_pool.size()):
		_segment_label_pool[i].visible = false

	# Update total label (only show when there are 2+ segments for clarity)
	if _total_label and _total_label_panel:
		var dists := _calculate_distances(_cached_points)
		_total_label.text = (
			ScaleUtils
			. format_distance_with_elevation(
				dists.horizontal,
				dists.elevation,
				dists.direct,
				_grid_cell_size,
				_display_unit_per_cell,
				_display_unit,
				ELEVATION_THRESHOLD,
			)
		)
		_total_label_panel.visible = segment_count >= 2


## Called by _draw_control's draw signal — renders dotted lines and endpoint dots.
func _on_draw_control_draw() -> void:
	# Cursor dot shown during PLACING_START before the first click
	if _show_cursor_dot:
		_draw_control.draw_circle(_cursor_dot, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)

	if _screen_points.size() < 2:
		return

	# Draw committed segments (full opacity)
	for i in range(1, mini(_committed_count, _screen_points.size())):
		_draw_dashed_line_2d(_screen_points[i - 1], _screen_points[i], LINE_COLOR)

	# Draw preview segment (half opacity) — last segment when there's a preview
	if _screen_points.size() > _committed_count:
		var preview_idx := _screen_points.size() - 1
		_draw_dashed_line_2d(
			_screen_points[preview_idx - 1], _screen_points[preview_idx], PREVIEW_LINE_COLOR
		)

	# Draw endpoint circles at each waypoint
	for pt in _screen_points:
		_draw_control.draw_circle(pt, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)


func _draw_dashed_line_2d(from_pt: Vector2, to_pt: Vector2, color: Color) -> void:
	var total_dist := from_pt.distance_to(to_pt)
	if total_dist < 0.5:
		return

	var direction := (to_pt - from_pt) / total_dist
	var current := 0.0

	while current < total_dist:
		var dash_end := minf(current + DASH_LENGTH_PX, total_dist)
		var dash_start_pt := from_pt + direction * current
		var dash_end_pt := from_pt + direction * dash_end
		_draw_control.draw_line(dash_start_pt, dash_end_pt, color, LINE_WIDTH_PX, true)
		current += DASH_LENGTH_PX + DASH_GAP_PX


# ============================================================================
# Screen-Space Overlay
# ============================================================================


## Create the screen-space overlay (line drawing + distance label). Parented
## outside the SubViewport so visuals aren't pixelated by the lo-fi shader.
func _create_overlay(overlay_parent: Node) -> void:
	var overlay: Dictionary = MapOverlayUtils.create_overlay(
		overlay_parent, Constants.LAYER_MEASURE_OVERLAY, _on_draw_control_draw
	)
	_canvas_layer = overlay.canvas_layer
	_draw_control = overlay.draw_control

	# Total distance label (larger, shown when 2+ segments)
	var total: Dictionary = MapOverlayUtils.create_label_panel(20)
	_total_label_panel = total.panel
	_total_label = total.label
	_canvas_layer.add_child(_total_label_panel)


## Ensure the segment label pool has at least [param count] entries.
func _ensure_segment_label_count(count: int) -> void:
	while _segment_label_pool.size() < count:
		var result: Dictionary = MapOverlayUtils.create_label_panel(14)
		var panel: PanelContainer = result.panel
		_canvas_layer.add_child(panel)
		_segment_label_pool.append(panel)


func _update_label_positions() -> void:
	if not _camera or _cached_points.size() < 2:
		return

	var segment_count := _cached_points.size() - 1

	# Position per-segment labels at each segment's midpoint
	for i in range(mini(segment_count, _segment_label_pool.size())):
		var panel: PanelContainer = _segment_label_pool[i]
		if not panel.visible:
			continue
		var a: Vector3 = _cached_points[i]
		var b: Vector3 = _cached_points[i + 1]
		var midpoint := (a + b) * 0.5
		var screen_pos := _camera.unproject_position(midpoint)
		screen_pos.y -= 24.0
		panel.position = screen_pos - panel.size * 0.5

	# Position total label at the endpoint of the path
	if _total_label_panel and _total_label_panel.visible:
		var endpoint := _cached_points[_cached_points.size() - 1]
		var screen_pos := _camera.unproject_position(endpoint)
		screen_pos.y -= 40.0
		_total_label_panel.position = screen_pos - _total_label_panel.size * 0.5


# ============================================================================
# Input Hints
# ============================================================================


func _push_measure_hints() -> void:
	UIManager.remove_hint("M")
	UIManager.remove_hint("G")
	UIManager.add_hint("LMB", "Place Point")
	UIManager.add_hint("Ctrl+LMB", "Snap Token")
	UIManager.add_hint("RMB", "Undo / Cancel")
	UIManager.add_hint("M", "Done")


func _pop_measure_hints() -> void:
	UIManager.remove_hint("LMB")
	UIManager.remove_hint("Ctrl+LMB")
	UIManager.remove_hint("RMB")
	UIManager.remove_hint("M")
	UIManager.add_hint("M", "Measure")
	UIManager.add_hint("G", "Grid")


func _cycle_mode() -> void:
	_mode = advance_mode(_mode)
