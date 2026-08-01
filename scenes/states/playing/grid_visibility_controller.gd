class_name GridVisibilityController
extends Node

## Manages grid overlay visibility policy for GameMap: whether the grid should
## be shown based on the explicit G-key toggle, auto-show during measurement
## or token dragging, or the level's default, plus the drag cell-highlight
## tracking used while a token is being dragged.
##
## This is visibility policy only -- distinct from GridOverlay's actual
## rendering and from VisualEffectsController's grid appearance settings
## (color/thickness/fade-radius).
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (_grid_overlay,
## drag_and_drop_node, _drag_ruler) directly from the injected GameMap
## reference at call time, since several of these are only set up after this
## sub-component is constructed.

var _game_map: GameMap = null

var _grid_explicit_toggle: bool = false  # Set by G key, persists until toggled or level change
var _grid_auto_show_measure: bool = false
var _grid_auto_show_drag: bool = false
var _grid_level_default: bool = false  # From LevelData.grid_visible
var _grid_show_on_measure: bool = true  # From LevelData
var _grid_show_on_drag: bool = true  # From LevelData
var _drag_highlight_active: bool = false
var _drag_highlight_start_pos: Vector3 = Vector3.ZERO


## Wire this controller to its owning GameMap.
func setup(game_map: GameMap) -> void:
	_game_map = game_map


func _process(_delta: float) -> void:
	_update_drag_cell_highlight()


## Toggle the explicit grid visibility override (G key).
func toggle_explicit() -> void:
	_grid_explicit_toggle = not _grid_explicit_toggle
	_update_grid_visibility()


## Update whether the grid should auto-show due to active measurement.
func set_auto_show_measure(active: bool) -> void:
	_grid_auto_show_measure = active
	_update_grid_visibility()


func _on_drag_started_grid(obj: DraggingObject3D) -> void:
	_grid_auto_show_drag = true
	_update_grid_visibility()
	# Show "Shift: Free move" hint when grid snap is active
	if _game_map.drag_and_drop_node and _game_map.drag_and_drop_node.grid_snap_enabled:
		UIManager.add_hint(InputProfile.label(&"free_move"), "Free Move")
	# Start cell highlighting
	if obj and obj.objectBody:
		_drag_highlight_active = true
		_drag_highlight_start_pos = obj.objectBody.global_position


func _on_drag_stopped_grid(_obj: DraggingObject3D) -> void:
	_grid_auto_show_drag = false
	_drag_highlight_active = false
	_update_grid_visibility()
	UIManager.remove_hint(InputProfile.label(&"free_move"))
	if _game_map._grid_overlay:
		_game_map._grid_overlay.clear_drag_highlight()


## Update the grid shader's highlighted cell each frame during a drag.
func _update_drag_cell_highlight() -> void:
	if (
		not _drag_highlight_active
		or not _game_map._grid_overlay
		or not _game_map.drag_and_drop_node
	):
		return
	var drag_node := _game_map.drag_and_drop_node
	if not drag_node.is_dragging() or not drag_node._has_target_position:
		return
	_game_map._grid_overlay.set_drag_highlight(
		drag_node._target_drag_position, _drag_highlight_start_pos
	)


## Configure grid overlay and drag systems from LevelData.
func configure_grid(level_data: LevelData) -> void:
	_grid_level_default = level_data.grid_visible
	_grid_explicit_toggle = level_data.grid_visible
	_grid_show_on_measure = level_data.grid_show_on_measure
	_grid_show_on_drag = level_data.grid_show_on_drag
	_grid_auto_show_measure = false
	_grid_auto_show_drag = false

	if _game_map._grid_overlay:
		_game_map._grid_overlay.configure(
			level_data.grid_cell_size, level_data.grid_origin, level_data.grid_color
		)
		# Set floor level so the grid doesn't project onto token bodies.
		# GLB maps are authored with floors at Y≈0; the AABB bottom includes
		# mesh undersides/foundations so we default to Y=0 instead.
		# Tolerance covers slight elevation (rugs, ramps) but excludes tokens.
		var floor_y := 0.0
		var tolerance: float = maxf(level_data.grid_cell_size * 0.4, 0.5)
		_game_map._grid_overlay.set_floor_level(floor_y, tolerance)
	_update_grid_visibility()

	# Configure drag snap on the DragAndDrop3D node
	if _game_map.drag_and_drop_node:
		_game_map.drag_and_drop_node.grid_snap_enabled = level_data.grid_snap_enabled
		_game_map.drag_and_drop_node.grid_cell_size = level_data.grid_cell_size
		_game_map.drag_and_drop_node.grid_origin = level_data.grid_origin

	# Configure drag ruler
	if _game_map._drag_ruler:
		(
			_game_map
			. _drag_ruler
			. configure(
				level_data.grid_cell_size,
				level_data.display_unit,
				level_data.display_unit_per_cell,
				level_data.grid_snap_enabled,
			)
		)


## Evaluate all grid visibility sources and show/hide accordingly.
func _update_grid_visibility() -> void:
	if not _game_map._grid_overlay:
		return
	var should_show: bool = (
		_grid_explicit_toggle
		or (_grid_show_on_measure and _grid_auto_show_measure)
		or (_grid_show_on_drag and _grid_auto_show_drag)
	)
	if should_show and not _game_map._grid_overlay.is_grid_visible():
		_game_map._grid_overlay.show_grid()
	elif not should_show and _game_map._grid_overlay.is_grid_visible():
		_game_map._grid_overlay.hide_grid()


## Reset grid state when a level is cleared.
func reset_grid_state() -> void:
	_grid_explicit_toggle = false
	_grid_auto_show_measure = false
	_grid_auto_show_drag = false
	_grid_level_default = false
	_drag_highlight_active = false
	if _game_map._grid_overlay:
		_game_map._grid_overlay.clear_drag_highlight()
		_game_map._grid_overlay.hide_grid_immediate()
	if _game_map._drag_ruler:
		_game_map._drag_ruler.deactivate()
