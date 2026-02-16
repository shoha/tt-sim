extends Node3D
class_name MeasureTool

## Measurement tool for the game map.
## Allows players to measure distances between points on the terrain (or tokens).
##
## Usage:
##   1. Parent this node inside the SubViewport (alongside MapContainer / DragAndDrop3D).
##   2. Call configure() after a level loads to provide scale settings.
##   3. GameMap feeds input via handle_input() — returns true if the event was consumed.
##
## State machine:
##   INACTIVE ──(activate)──► PLACING_START ──(click)──► PLACING_WAYPOINT
##   PLACING_WAYPOINT ──(click)──► PLACING_WAYPOINT (adds waypoint)
##   PLACING_WAYPOINT / PLACING_START ──(deactivate / right-click / Escape)──► INACTIVE

signal toggled(active: bool)

enum State { INACTIVE, PLACING_START, PLACING_WAYPOINT }

const TERRAIN_COLLISION_LAYER: int = 1
const TOKEN_COLLISION_LAYER: int = 2
const RAYCAST_LENGTH: float = 200.0

## 2D visual constants (pixel units — rendered on a CanvasLayer above the lo-fi shader)
const LINE_WIDTH_PX: float = 2.5
const DASH_LENGTH_PX: float = 8.0
const DASH_GAP_PX: float = 6.0
const ENDPOINT_RADIUS_PX: float = 5.0
const LINE_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const ENDPOINT_COLOR := Color(1.0, 0.85, 0.2, 1.0)

## Elevation threshold — below this delta (in world meters), treat as flat.
const ELEVATION_THRESHOLD: float = 0.15

## References set by GameMap after instantiation
var camera: Camera3D
var world_viewport: SubViewport

## Scale configuration — updated via configure()
var _grid_cell_size: float = 1.524
var _display_unit: String = "ft"
var _display_unit_per_cell: float = 5.0

## State
var _state: State = State.INACTIVE
var _waypoints: PackedVector3Array = PackedVector3Array()
var _preview_point: Vector3 = Vector3.ZERO
var _has_preview: bool = false

## Screen-space overlay (CanvasLayer so it renders above the lo-fi shader)
var _canvas_layer: CanvasLayer
var _draw_control: Control
var _label_panel: PanelContainer
var _label: Label

## Cached 2D screen projections of the current 3D waypoints (for _draw_control)
var _screen_points: PackedVector2Array = PackedVector2Array()

## 2D position of the cursor dot shown during PLACING_START (before first click)
var _cursor_dot: Vector2 = Vector2.ZERO
var _show_cursor_dot: bool = false



func _process(_delta: float) -> void:
	if _state == State.INACTIVE:
		return
	_redraw()
	_update_label_position()


# ============================================================================
# Public API
# ============================================================================


## Configure scale settings. Call after level load and when scale changes.
func configure(grid_cell_size: float, display_unit: String, display_unit_per_cell: float) -> void:
	_grid_cell_size = grid_cell_size
	_display_unit = display_unit
	_display_unit_per_cell = display_unit_per_cell
	if _state != State.INACTIVE:
		_redraw()


## Returns true when the measure tool is actively capturing input.
func is_active() -> bool:
	return _state != State.INACTIVE


func activate() -> void:
	if _state != State.INACTIVE:
		return
	_state = State.PLACING_START
	_waypoints.clear()
	_has_preview = false
	_clear_visuals()
	if _label_panel:
		_label_panel.visible = false
	_push_measure_hints()
	toggled.emit(true)


func deactivate() -> void:
	_state = State.INACTIVE
	_waypoints.clear()
	_has_preview = false
	_clear_visuals()
	if _label_panel:
		_label_panel.visible = false
	_pop_measure_hints()
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

	# Mouse motion — update preview point
	if event is InputEventMouseMotion:
		_update_preview(event.position)
		# Don't consume motion: camera still needs _last_mouse_position updates
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
	# Only care about left and right clicks
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _handle_left_click(event.position, event.ctrl_pressed)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_measurement()
		return true
	# Don't consume scroll (zoom) or middle button (pan)
	return false


func _handle_key(event: InputEventKey) -> bool:
	if event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_measurement()
		return true
	# Ctrl isn't consumed — just used as a modifier for token snapping
	return false


func _handle_left_click(screen_pos: Vector2, ctrl_held: bool) -> bool:
	var hit := _raycast(screen_pos, ctrl_held)
	if hit == Vector3.INF:
		return false

	match _state:
		State.PLACING_START:
			_waypoints.clear()
			_waypoints.append(hit)
			_state = State.PLACING_WAYPOINT
			return true
		State.PLACING_WAYPOINT:
			_waypoints.append(hit)
			return true
	return false


func _cancel_measurement() -> void:
	if _state == State.PLACING_WAYPOINT and _waypoints.size() > 1:
		# Remove the last waypoint (undo)
		_waypoints.resize(_waypoints.size() - 1)
		if _waypoints.size() < 1:
			_state = State.PLACING_START
			if _label_panel:
				_label_panel.visible = false
	elif (
		_state == State.PLACING_START
		or (_state == State.PLACING_WAYPOINT and _waypoints.size() <= 1)
	):
		deactivate()


## Update the live preview point from mouse position.
func _update_preview(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos, Input.is_key_pressed(KEY_CTRL))
	if hit != Vector3.INF:
		_preview_point = hit
		_has_preview = true
	else:
		_has_preview = false


# ============================================================================
# Raycasting
# ============================================================================


## Raycast against terrain (and optionally tokens).
## Returns the hit position or Vector3.INF if nothing was hit.
## Uses the SubViewport's mouse position (not the main viewport's event.position)
## because Camera3D.project_ray_origin works in the camera's own viewport space.
func _raycast(_screen_pos: Vector2, include_tokens: bool = false) -> Vector3:
	if not camera or not world_viewport:
		return Vector3.INF

	var world: World3D = world_viewport.find_world_3d()
	if not world:
		return Vector3.INF

	var space_state := world.direct_space_state
	if not space_state:
		return Vector3.INF

	# Get mouse position from the SubViewport (same approach as DragAndDrop3D).
	# The camera lives inside the SubViewport, so project_ray_origin expects
	# coordinates in that viewport's space, not the main window's space.
	var vp_mouse := world_viewport.get_mouse_position()
	var from := camera.project_ray_origin(vp_mouse)
	var to := from + camera.project_ray_normal(vp_mouse) * RAYCAST_LENGTH

	# When Ctrl is held, try token layer first for snap-to-token-base
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

	# Terrain raycast
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


## Calculate distance metrics from waypoints + optional preview.
## Returns {horizontal: float, elevation: float, direct: float}.
func _calculate_distances() -> Dictionary:
	var points := _get_all_points()
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


## Return all committed waypoints plus the live preview point.
func _get_all_points() -> PackedVector3Array:
	var pts := _waypoints.duplicate()
	if _has_preview and _state == State.PLACING_WAYPOINT:
		pts.append(_preview_point)
	return pts


# ============================================================================
# Rendering — 2D overlay (drawn on _draw_control in the CanvasLayer)
# ============================================================================


func _clear_visuals() -> void:
	_screen_points.clear()
	_show_cursor_dot = false
	if _draw_control:
		_draw_control.queue_redraw()


func _redraw() -> void:
	# During PLACING_START, show a cursor dot at the mouse position
	if _state == State.PLACING_START and _has_preview and camera:
		_cursor_dot = camera.unproject_position(_preview_point)
		_show_cursor_dot = true
		if _draw_control:
			_draw_control.queue_redraw()
	else:
		_show_cursor_dot = false

	var points := _get_all_points()
	if points.size() < 2:
		_screen_points.clear()
		if _draw_control:
			_draw_control.queue_redraw()
		if _label_panel:
			_label_panel.visible = false
		return

	# Project 3D waypoints to 2D screen coordinates
	_screen_points.clear()
	for pt in points:
		_screen_points.append(camera.unproject_position(pt))

	if _draw_control:
		_draw_control.queue_redraw()

	# Update label text
	if _label and _label_panel:
		var dists := _calculate_distances()
		_label.text = (
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
		_label_panel.visible = true


## Called by _draw_control's draw signal — renders dotted lines and endpoint dots.
func _on_draw_control_draw() -> void:
	# Cursor dot shown during PLACING_START before the first click
	if _show_cursor_dot:
		_draw_control.draw_circle(_cursor_dot, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)

	if _screen_points.size() < 2:
		return

	# Draw dashed segments between consecutive screen points
	for i in range(1, _screen_points.size()):
		_draw_dashed_line_2d(_screen_points[i - 1], _screen_points[i])

	# Draw endpoint circles at each waypoint
	for pt in _screen_points:
		_draw_control.draw_circle(pt, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)


func _draw_dashed_line_2d(from_pt: Vector2, to_pt: Vector2) -> void:
	var total_dist := from_pt.distance_to(to_pt)
	if total_dist < 0.5:
		return

	var direction := (to_pt - from_pt) / total_dist
	var current := 0.0

	while current < total_dist:
		var dash_end := minf(current + DASH_LENGTH_PX, total_dist)
		var dash_start_pt := from_pt + direction * current
		var dash_end_pt := from_pt + direction * dash_end
		_draw_control.draw_line(dash_start_pt, dash_end_pt, LINE_COLOR, LINE_WIDTH_PX, true)
		current += DASH_LENGTH_PX + DASH_GAP_PX


# ============================================================================
# Screen-Space Label
# ============================================================================


## Create the screen-space overlay (line drawing + label). Must be parented
## outside the SubViewport so visuals aren't pixelated by the lo-fi shader.
## [param label_parent] should be a node in the main scene tree (e.g. GameMap root).
func create_label(label_parent: Node) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	label_parent.add_child(_canvas_layer)

	# Full-rect Control for drawing measurement lines via _draw()
	_draw_control = Control.new()
	_draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_control.draw.connect(_on_draw_control_draw)
	_canvas_layer.add_child(_draw_control)

	# Semi-transparent dark panel behind the label for maximum contrast
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.content_margin_left = 8.0
	stylebox.content_margin_right = 8.0
	stylebox.content_margin_top = 4.0
	stylebox.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", stylebox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	panel.add_child(_label)

	_label_panel = panel
	_canvas_layer.add_child(_label_panel)


func _update_label_position() -> void:
	if not _label_panel or not _label_panel.visible or not camera:
		return

	var points := _get_all_points()
	if points.size() < 2:
		return

	# Position the panel at the midpoint of the last segment
	var last := points[points.size() - 1]
	var prev := points[points.size() - 2]
	var midpoint := (last + prev) * 0.5

	var screen_pos := camera.unproject_position(midpoint)
	# Offset above the line
	screen_pos.y -= 36.0
	_label_panel.position = screen_pos - _label_panel.size * 0.5


# ============================================================================
# Input Hints
# ============================================================================


func _push_measure_hints() -> void:
	UIManager.remove_hint("M")
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
