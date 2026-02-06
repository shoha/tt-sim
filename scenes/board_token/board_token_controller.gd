extends Node
class_name BoardTokenController

## Handles user interaction and visual manipulation for tokens
## Manages rotation, scaling, and selection input
## Keeps interaction logic separate from entity data and drag mechanics
##
## This component bridges user input with the token's visual representation
## It operates on the RigidBody3D and coordinates with DraggableToken
##
## Responsibilities:
## - Mouse hover detection
## - Rotation input (middle mouse drag)
## - Scaling input (middle mouse + shift drag)
## - Reset transformations (middle mouse double-click)
## - Token selection (left click)
## - Context menu (right click)
##
## Network Considerations:
## - All mutating input is gated by _has_input_authority()
## - In single-player, authority is always granted
## - When networking is added, this will check for host/authority status

const ROTATION_FACTOR: float = 0.0001
const SCALE_FACTOR: float = 0.0001

@export var rigid_body: RigidBody3D
@export var draggable_token: DraggableToken
@export var animation_tree: AnimationTree

var _rotating: bool = false
var _scaling: bool = false
var _mouse_over: bool = false
var _transform_update_timer: float = 0.0
const TRANSFORM_UPDATE_INTERVAL: float = 0.1 # Send updates 10 times per second during manipulation

signal context_menu_requested(token: BoardToken, position: Vector2)


## Check if this client has authority to manipulate this token.
## In single-player mode, always returns true.
## In networked games, only the host has authority (for now).
## Future: Could allow client-owned tokens.
## @return: true if input should be processed, false to ignore
func _has_input_authority() -> bool:
	return NetworkManager.is_host() or not NetworkManager.is_networked()


func _ready() -> void:
	if not rigid_body:
		push_warning("BoardTokenController: No RigidBody3D assigned.")
		return

	# Connect to mouse events
	rigid_body.connect("mouse_entered", _on_mouse_entered)
	rigid_body.connect("mouse_exited", _on_mouse_exited)

func _on_mouse_entered() -> void:
	_mouse_over = true
	# Show hover highlight
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.set_highlighted(true)

func _on_mouse_exited() -> void:
	_mouse_over = false
	# Hide hover highlight
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.set_highlighted(false)

func _unhandled_input(event: InputEvent) -> void:
	if not rigid_body:
		return

	# Gate all mutating input behind authority check
	# Context menu is allowed for all (read-only viewing), but actions within may be gated
	if not _has_input_authority():
		# Still allow context menu for viewing token info (actions inside will be gated)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _mouse_over:
			var board_token = get_parent() as BoardToken
			if board_token:
				context_menu_requested.emit(board_token, event.position)
		return

	# Handle right-click for context menu
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _mouse_over:
		var board_token = get_parent() as BoardToken
		if board_token:
			context_menu_requested.emit(board_token, event.position)
		return

	# Check for double-click on middle mouse button to reset rotation and scale
	if event is InputEventMouseButton and event.double_click and event.is_action_pressed("rotate_model") and _mouse_over:
		_reset_rotation_and_scale()
		return

	if event.is_action_pressed("rotate_model") and _mouse_over:
		# Check if shift is held to determine scaling vs rotation
		if Input.is_key_pressed(KEY_SHIFT):
			_scaling = true
		else:
			_rotating = true
		return

	if event.is_action_released("rotate_model"):
		var was_rotating = _rotating
		var was_scaling = _scaling
		_rotating = false
		_scaling = false
		
		# Emit signals for network sync when rotation/scale changes complete
		var board_token = get_parent() as BoardToken
		if board_token:
			if was_rotating:
				board_token.rotation_changed.emit()
			if was_scaling:
				board_token.scale_changed.emit()
		return

	if _rotating and event is InputEventMouseMotion:
		_handle_rotation(event)

	if _scaling and event is InputEventMouseMotion:
		_handle_scaling(event)

func _handle_rotation(event: InputEventMouseMotion) -> void:
	var velocity_x = event.screen_velocity.x
	rigid_body.rotate_y(velocity_x * ROTATION_FACTOR)

func _handle_scaling(event: InputEventMouseMotion) -> void:
	var velocity_y = event.screen_velocity.y
	# Use negative velocity_y so moving mouse up scales up, down scales down
	var scale_change = - velocity_y * SCALE_FACTOR
	var old_scale = rigid_body.scale
	var new_scale = rigid_body.scale + Vector3.ONE * scale_change
	# Clamp the scale to prevent it from going too small or too large
	new_scale = new_scale.clamp(Vector3.ONE * 0.1, Vector3.ONE * 10.0)

	# Calculate the position adjustment to keep the bottom fixed
	_adjust_position_for_scale(old_scale, new_scale)

	rigid_body.scale = new_scale

	# Update the draggable token's height offset to match new scale
	if draggable_token:
		draggable_token.update_height_offset()

func _adjust_position_for_scale(old_scale: Vector3, new_scale: Vector3) -> void:
	# Get the collision shape to determine the object's height
	var collision_shape: CollisionShape3D = rigid_body.get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape:
		var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()
		# Calculate the bottom position in local space
		var local_bottom_y = collision_shape.position.y + aabb.position.y
		# Calculate how much the bottom moves when scaling from center
		var bottom_offset_old = local_bottom_y * old_scale.y
		var bottom_offset_new = local_bottom_y * new_scale.y
		# Adjust position to compensate
		rigid_body.position.y += (bottom_offset_old - bottom_offset_new)

func _reset_rotation_and_scale() -> void:
	# Store the old scale to calculate position adjustment
	var old_scale = rigid_body.scale

	# Reset rotation to identity (no rotation)
	rigid_body.rotation = Vector3.ZERO

	# Calculate position adjustment to keep bottom fixed when resetting scale
	_adjust_position_for_scale(old_scale, Vector3.ONE)

	# Reset scale to default
	rigid_body.scale = Vector3.ONE

	# Recompute the height offset
	if draggable_token:
		draggable_token.update_height_offset()
	
	# Emit signals for network sync
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.rotation_changed.emit()
		board_token.scale_changed.emit()


func _process(delta: float) -> void:
	# Emit throttled transform updates during rotation/scaling for network sync
	if _rotating or _scaling:
		_transform_update_timer += delta
		if _transform_update_timer >= TRANSFORM_UPDATE_INTERVAL:
			_transform_update_timer = 0.0
			var board_token = get_parent() as BoardToken
			if board_token:
				board_token.transform_updated.emit()
