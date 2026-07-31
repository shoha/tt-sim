class_name DragRuler
extends Node

## Shows a distance ruler line from a token's start position to its current
## position while dragging. Renders as a 2D overlay on its own CanvasLayer
## (above the lo-fi shader, below the measure tool).
##
## Usage:
##   1. Call setup() after instantiation to provide camera, viewport, and overlay parent.
##   2. Call configure() after a level loads to provide scale settings.
##   3. GameMap connects DragAndDrop3D signals to activate() / deactivate().

const LINE_WIDTH_PX: float = 2.5
const ENDPOINT_RADIUS_PX: float = 5.0
const LINE_COLOR := Color(0.6, 0.8, 1.0, 0.9)
const ENDPOINT_COLOR := Color(0.6, 0.8, 1.0, 1.0)

## References — set once via setup()
var _camera: Camera3D
var _world_viewport: SubViewport
var _drag_and_drop: DragAndDrop3D

## Scale configuration — updated via configure()
var _grid_cell_size: float = 1.524
var _display_unit: String = "ft"
var _display_unit_per_cell: float = 5.0
var _grid_snap_enabled: bool = false

## State
var _active: bool = false
var _start_pos: Vector3 = Vector3.ZERO

## Overlay nodes
var _canvas_layer: CanvasLayer
var _draw_control: Control
var _distance_panel: PanelContainer
var _distance_label: Label

## Dirty flag + camera tracking (same pattern as MeasureTool)
var _needs_redraw: bool = false
var _last_camera_size: float = 0.0
var _last_camera_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	set_process(false)
	process_priority = 1


func _process(_delta: float) -> void:
	_check_camera_changed()
	if _active and _drag_and_drop:
		_needs_redraw = true
	if not _needs_redraw:
		return
	_needs_redraw = false
	_do_redraw()


# ============================================================================
# Setup & Configuration
# ============================================================================


## One-time initialization.
func setup(
	cam: Camera3D,
	viewport: SubViewport,
	overlay_parent: Node,
	drag_and_drop: DragAndDrop3D,
) -> void:
	_camera = cam
	_world_viewport = viewport
	_drag_and_drop = drag_and_drop
	_create_overlay(overlay_parent)

	drag_and_drop.dragging_started.connect(_on_dragging_started)
	drag_and_drop.dragging_stopped.connect(_on_dragging_stopped)
	drag_and_drop.dragging_cancelled.connect(_on_dragging_stopped)


## Configure scale settings. Call after level load and when scale changes.
func configure(
	grid_cell_size: float,
	display_unit: String,
	display_unit_per_cell: float,
	grid_snap_enabled: bool,
) -> void:
	_grid_cell_size = grid_cell_size
	_display_unit = display_unit
	_display_unit_per_cell = display_unit_per_cell
	_grid_snap_enabled = grid_snap_enabled


# ============================================================================
# Activation
# ============================================================================


func _on_dragging_started(dragging_object: DraggingObject3D) -> void:
	if not dragging_object or not dragging_object.objectBody:
		return
	_start_pos = dragging_object.objectBody.global_position
	_active = true
	set_process(true)
	_needs_redraw = true


func _on_dragging_stopped(_dragging_object: DraggingObject3D) -> void:
	_active = false
	_clear_visuals()
	set_process(false)


## Force-deactivate (e.g. on level clear).
func deactivate() -> void:
	_active = false
	_clear_visuals()
	set_process(false)


# ============================================================================
# Rendering
# ============================================================================


func _clear_visuals() -> void:
	if _draw_control:
		_draw_control.queue_redraw()
	if _distance_panel:
		_distance_panel.visible = false


func _do_redraw() -> void:
	if not _active or not _camera or not _drag_and_drop:
		_clear_visuals()
		return

	# Read the snap target (not the lerping body position) for a crisp endpoint
	var end_pos := _drag_and_drop._target_drag_position
	if not _drag_and_drop._has_target_position:
		_clear_visuals()
		return

	# Calculate 2D distance on the XZ plane
	var dist_2d := Vector2(_start_pos.x, _start_pos.z).distance_to(Vector2(end_pos.x, end_pos.z))

	# Format the label
	var text := ScaleUtils.format_distance(
		dist_2d, _grid_cell_size, _display_unit_per_cell, _display_unit
	)
	if _grid_snap_enabled and _grid_cell_size > 0.0:
		var cells := roundi(dist_2d / _grid_cell_size)
		text = "%d cells / %s" % [cells, text]

	if _distance_label:
		_distance_label.text = text

	# Project to screen
	var screen_start := _camera.unproject_position(_start_pos)
	var screen_end := _camera.unproject_position(end_pos)

	# Only show label if the line is long enough
	if _distance_panel:
		var screen_len := screen_start.distance_to(screen_end)
		_distance_panel.visible = screen_len > 40.0
		if _distance_panel.visible:
			var midpoint := (_start_pos + end_pos) * 0.5
			var screen_mid := _camera.unproject_position(midpoint)
			screen_mid.y -= 24.0
			_distance_panel.position = screen_mid - _distance_panel.size * 0.5

	if _draw_control:
		_draw_control.queue_redraw()


func _on_draw_control_draw() -> void:
	if not _active or not _camera or not _drag_and_drop:
		return
	if not _drag_and_drop._has_target_position:
		return

	var screen_start := _camera.unproject_position(_start_pos)
	var screen_end := _camera.unproject_position(_drag_and_drop._target_drag_position)

	# Draw the ruler line
	var total_dist := screen_start.distance_to(screen_end)
	if total_dist < 1.0:
		return
	_draw_control.draw_line(screen_start, screen_end, LINE_COLOR, LINE_WIDTH_PX, true)

	# Endpoint circles
	_draw_control.draw_circle(screen_start, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)
	_draw_control.draw_circle(screen_end, ENDPOINT_RADIUS_PX, ENDPOINT_COLOR)


# ============================================================================
# Camera tracking
# ============================================================================


func _check_camera_changed() -> void:
	if not _camera:
		return
	var cam_size := _camera.size
	var cam_pos := _camera.global_position
	if cam_size != _last_camera_size or cam_pos != _last_camera_pos:
		_last_camera_size = cam_size
		_last_camera_pos = cam_pos
		_needs_redraw = true


# ============================================================================
# Overlay creation
# ============================================================================


func _create_overlay(overlay_parent: Node) -> void:
	var overlay: Dictionary = MapOverlayUtils.create_overlay(
		overlay_parent, Constants.LAYER_DRAG_RULER, _on_draw_control_draw
	)
	_canvas_layer = overlay.canvas_layer
	_draw_control = overlay.draw_control

	var result: Dictionary = MapOverlayUtils.create_label_panel(16, Color(0.85, 0.92, 1.0))
	_distance_panel = result.panel
	_distance_label = result.label
	_canvas_layer.add_child(_distance_panel)
