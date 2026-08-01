class_name DragPlaceController
extends Node

## Handles drag-to-place: dragging an asset from the asset browser and
## dropping it onto the map to spawn a new token, including the ghost icon
## that follows the cursor and the ground-position/grid-snap math used to
## resolve the drop point. Distinct from DragAndDrop3D-based dragging of
## already-placed tokens on the board, which this controller does not touch.
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (camera_node,
## world_viewport, cameraholder_node, drag_and_drop_node) directly from the
## injected GameMap reference at call time. The actual token-spawning call
## (LevelPlayController.spawn_asset) is injected as a Callable via setup()
## rather than passing a reference to the whole LevelPlayController.
##
## GameMap._input() calls handle_input() explicitly instead of relying on
## this Node's own automatic _input() dispatch, so the drag-place branch
## keeps running at the exact same point in GameMap's input handling order
## as it did before the extraction.

var _game_map: GameMap = null
var _spawn_asset_fn: Callable

var _drag_placing: bool = false
var _drag_place_info: Dictionary = {}
var _drag_ghost: TextureRect = null
var _drag_ghost_layer: CanvasLayer = null


## Wire this controller to its owning GameMap and the token-spawning callable.
## spawn_asset_fn(pack_id, asset_id, variant_id, spawn_position) -> BoardToken
func setup(game_map: GameMap, spawn_asset_fn: Callable) -> void:
	_game_map = game_map
	_spawn_asset_fn = spawn_asset_fn


## Handle input while a drag-place may be active. Returns true if the event
## was consumed and GameMap._input() should stop processing it further --
## mirrors the original inline "if _drag_placing: ... return" branch.
func handle_input(event: InputEvent) -> bool:
	if not _drag_placing:
		return false

	if event is InputEventMouseMotion and _drag_ghost:
		_drag_ghost.position = event.position - Vector2(32, 32)
		get_viewport().set_input_as_handled()
		return true
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		if _game_map._is_mouse_over_gui():
			_cancel_drag_place()
		else:
			_complete_drag_place(event.position)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag_place()
		get_viewport().set_input_as_handled()
		return true
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		_cancel_drag_place()
		get_viewport().set_input_as_handled()
		return true

	return false


## Entry point for starting a drag-place. Connected (by GameMap.setup()) to
## GameplayMenuController's drag_place_started signal, which the asset
## browser triggers when a drag begins.
func _on_drag_place_started(
	pack_id: String, asset_id: String, variant_id: String, icon: Texture2D
) -> void:
	_drag_placing = true
	_drag_place_info = {
		"pack_id": pack_id,
		"asset_id": asset_id,
		"variant_id": variant_id,
	}
	# Create ghost icon on a high canvas layer
	_drag_ghost_layer = CanvasLayer.new()
	_drag_ghost_layer.layer = Constants.LAYER_DIALOG
	add_child(_drag_ghost_layer)

	_drag_ghost = TextureRect.new()
	if icon:
		_drag_ghost.texture = icon
	else:
		# Fallback: small colored square
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.6, 0.2, 0.6))
		_drag_ghost.texture = ImageTexture.create_from_image(img)
	_drag_ghost.custom_minimum_size = Vector2(64, 64)
	_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_ghost.modulate = Color(1, 1, 1, 0.6)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.position = get_viewport().get_mouse_position() - Vector2(32, 32)
	_drag_ghost_layer.add_child(_drag_ghost)

	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func _cancel_drag_place() -> void:
	_drag_placing = false
	_drag_place_info.clear()
	if _drag_ghost_layer:
		_drag_ghost_layer.queue_free()
		_drag_ghost_layer = null
		_drag_ghost = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _complete_drag_place(screen_pos: Vector2) -> void:
	var ground_pos := _get_ground_position(screen_pos)
	if ground_pos == Vector3.INF:
		ground_pos = _get_camera_ground_position()
	ground_pos = _snap_to_grid_if_enabled(ground_pos)

	if _spawn_asset_fn.is_valid():
		var token = (
			_spawn_asset_fn
			. call(
				_drag_place_info.get("pack_id", ""),
				_drag_place_info.get("asset_id", ""),
				_drag_place_info.get("variant_id", "default"),
				ground_pos,
			)
		)
		if not token:
			UIManager.show_error("Failed to place token")

	_cancel_drag_place()


## Get the world position where a screen point intersects the Y=0 ground plane.
## Returns Vector3.INF if the ray doesn't intersect (camera pointing up).
func _get_ground_position(screen_pos: Vector2) -> Vector3:
	if not _game_map.camera_node:
		return Vector3.INF
	var origin := _game_map.camera_node.project_ray_origin(screen_pos)
	var direction := _game_map.camera_node.project_ray_normal(screen_pos)
	if abs(direction.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / direction.y
	if t < 0:
		return Vector3.INF
	return origin + direction * t


## Get the ground position at viewport center (where the camera looks).
func _get_camera_ground_position() -> Vector3:
	var center := Vector2(_game_map.world_viewport.size) / 2.0
	var pos := _get_ground_position(center)
	if pos == Vector3.INF:
		pos = Vector3(
			_game_map.cameraholder_node.global_position.x,
			0,
			_game_map.cameraholder_node.global_position.z,
		)
	return pos


## Snap a world position to the grid if grid snap is enabled.
func _snap_to_grid_if_enabled(world_pos: Vector3) -> Vector3:
	var drag_and_drop_node := _game_map.drag_and_drop_node
	if not drag_and_drop_node or not drag_and_drop_node.grid_snap_enabled:
		return world_pos
	return ScaleUtils.snap_to_grid(
		world_pos, drag_and_drop_node.grid_cell_size, drag_and_drop_node.grid_origin
	)
