class_name DragRuler
extends Node

## Shows a distance ruler line from a token's start position to its current
## position while dragging. Renders as a 2D overlay on its own CanvasLayer
## (above the lo-fi shader, below the measure tool).
##
## The label adds "In fire" while the drop point stands in the map's persistent fire at the
## flames band or above (in_fire, on this peer's own document: the FireField of the map, found by
## its group at drag start). It only tells: nothing is synced and the token is not changed (fire
## is a rules matter for the GM).
##
## Usage:
##   1. Call setup() after instantiation to provide camera, viewport, and overlay parent.
##   2. Call configure() after a level loads to provide scale settings.
##   3. GameMap connects DragAndDrop3D signals to activate() / deactivate().

const LINE_WIDTH_PX: float = 2.5
const ENDPOINT_RADIUS_PX: float = 5.0
const LINE_COLOR := Color(0.6, 0.8, 1.0, 0.9)
const ENDPOINT_COLOR := Color(0.6, 0.8, 1.0, 1.0)
## The ground under the token at drag start is found by a downcast from this far above the
## token's origin (a token's origin may sit on its base, right at the ground).
const START_CAST_CLEARANCE_M: float = 0.5
## The label's part for a drop point in fire, after the distance's parts.
const IN_FIRE_TEXT := "In fire"

## References — set once via setup()
var _camera: Camera3D
var _world_viewport: SubViewport
var _drag_and_drop: DragAndDrop3D

## Scale configuration — updated via configure()
var _grid_cell_size: float = LevelData.DEFAULT_GRID_CELL_SIZE
var _display_unit: String = LevelData.DEFAULT_DISPLAY_UNIT
var _display_unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL
var _grid_snap_enabled: bool = false

## State
var _active: bool = false
var _start_pos: Vector3 = Vector3.ZERO
## Ground height (world Y) under the token where the drag began, or NAN when no ground was
## found there (the label then shows no elevation).
var _start_ground_y: float = NAN
## The map's persistent fire during a drag (null on a map without one).
var _fire: FireField = null

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
	_start_ground_y = _ground_below(_start_pos)
	_fire = get_tree().get_first_node_in_group(FireField.GROUP) as FireField
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

	# Distance on the XZ plane; elevation from the ground under the start to the ground at
	# the target (not the token's own lift or scroll height, which the settle undoes).
	var dist_2d := Vector2(_start_pos.x, _start_pos.z).distance_to(Vector2(end_pos.x, end_pos.z))
	var target := _drag_and_drop.get_target_ground_position()
	var elevation := 0.0
	if not is_nan(_start_ground_y):
		var end_ground := _ground_below(target)
		if not is_nan(end_ground):
			elevation = end_ground - _start_ground_y
	var burning := false
	if is_instance_valid(_fire):
		var local := _fire.to_local(target)
		burning = in_fire(_fire.document, Vector2(local.x, local.z))

	if _distance_label:
		_distance_label.text = ruler_text(
			dist_2d,
			elevation,
			_grid_cell_size,
			_display_unit_per_cell,
			_display_unit,
			_grid_snap_enabled,
			burning
		)
		# A PanelContainer grows with its text but never shrinks by itself: without this the chip
		# kept the width of a longer label ("In fire", an elevation) after the text shortened.
		if _distance_panel:
			_distance_panel.reset_size()

	# Project to screen
	var screen_start := _camera.unproject_position(_start_pos)
	var screen_end := _camera.unproject_position(end_pos)

	# Only show label if the line is long enough (or the drop point is in fire: a short step
	# into a fire still says so)
	if _distance_panel:
		var screen_len := screen_start.distance_to(screen_end)
		_distance_panel.visible = screen_len > 40.0 or burning
		if _distance_panel.visible:
			var midpoint := (_start_pos + end_pos) * 0.5
			var screen_mid := _camera.unproject_position(midpoint)
			screen_mid.y -= 24.0
			_distance_panel.position = screen_mid - _distance_panel.size * 0.5

	if _draw_control:
		_draw_control.queue_redraw()


## The ruler label: the horizontal distance ("30 ft", or "6 cells / 30 ft" with grid snap),
## followed like the measure tool's by the signed elevation change and the direct distance
## when the elevation passes MeasureTool.ELEVATION_THRESHOLD
## (ScaleUtils.format_distance_with_elevation), and by IN_FIRE_TEXT when `burning`. Pure.
static func ruler_text(
	horizontal: float,
	elevation: float,
	grid_cell_size: float,
	display_unit_per_cell: float,
	display_unit: String,
	snap: bool,
	burning := false,
) -> String:
	var text := (
		ScaleUtils
		. format_distance_with_elevation(
			horizontal,
			elevation,
			Vector2(horizontal, elevation).length(),
			grid_cell_size,
			display_unit_per_cell,
			display_unit,
			MeasureTool.ELEVATION_THRESHOLD,
		)
	)
	if snap and grid_cell_size > 0.0:
		text = "%d cells / %s" % [roundi(horizontal / grid_cell_size), text]
	if burning:
		text += "  |  " + IN_FIRE_TEXT
	return text


## Whether a token dropped at `at` (document metres, the map's frame: XZ in the FireField's
## frame) of `doc` stands in fire: the fire mask there (FireField.mask_at) at the flames band
## (FireField.FLAME_MIN) or above; embers do not count. False off the map, on a map without fire
## and without a document. Pure.
static func in_fire(doc: MapDocument, at: Vector2) -> bool:
	return FireField.mask_at(doc, at) >= FireField.FLAME_MIN


## The walkable surface (world Y) straight below `point`: the ground, or a water surface
## above it (WaterSurface.surface_below), so a ruler across a river measures along the
## surface the grid lies on, not down to the bed a wading token stands on. NAN with neither.
func _ground_below(point: Vector3) -> float:
	if not _world_viewport:
		return NAN
	var hit := WaterSurface.surface_below(
		_world_viewport.find_world_3d().direct_space_state, point, point.y + START_CAST_CLEARANCE_M
	)
	return hit.y if hit != Vector3.INF else NAN


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

	var result: Dictionary = MapOverlayUtils.create_label_panel(16)
	_distance_panel = result.panel
	_distance_label = result.label
	_canvas_layer.add_child(_distance_panel)
