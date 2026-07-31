class_name BoardTokenController
extends Node

## Handles user interaction and visual manipulation for tokens
## Manages rotation, scaling, and selection input
## Keeps interaction logic separate from entity data and drag mechanics
##
## This component bridges user input with the token's visual representation
## It operates on the RigidBody3D and coordinates with DraggableToken
##
## Responsibilities:
## - Mouse hover detection (+ cursor feedback)
## - Rotation input (middle mouse drag, 45-degree snapping)
## - Scaling input (middle mouse + shift drag)
## - Reset transformations (middle mouse double-click)
## - Token selection (left click)
## - Context menu (right click)
##
## Network Considerations:
## - All mutating input is gated by _has_input_authority()
## - In single-player, authority is always granted
## - When networking is added, this will check for host/authority status

signal context_menu_requested(token: BoardToken, position: Vector2)
signal focus_requested(position: Vector3)  # Double-click to center camera on token

const ROTATION_SNAP_DEGREES: float = 45.0  # Rotation snaps to this increment
const ROTATION_INPUT_THRESHOLD: float = 60.0  # Accumulated pixel distance before each rotation snap
const ROTATION_TWEEN_DURATION: float = 0.1  # Duration of rotation snap animation
const SCALE_SNAP_INCREMENT: float = 0.25  # Scale snaps by this amount per step
const SCALE_INPUT_THRESHOLD: float = 60.0  # Accumulated pixel distance before each scale snap
const SCALE_TWEEN_DURATION: float = 0.1  # Duration of scale snap animation
const SCALE_MIN: float = 0.1
const SCALE_MAX: float = 10.0

@export var rigid_body: RigidBody3D
@export var draggable_token: DraggableToken
@export var animation_tree: AnimationTree

var _rotating: bool = false
var _scaling: bool = false
var _mouse_over: bool = false
var _transform_update_timer: float = 0.0

# Rotation snapping state
var _rotation_accumulator: float = 0.0
var _rotation_tween: Tween = null

# Scale snapping state
var _scale_accumulator: float = 0.0
var _scale_tween: Tween = null

# R+LMB alternative rotate/scale state
var _r_key_rotating: bool = false
var _r_key_scaling: bool = false


## Check if this client has authority to manipulate this token.
## In single-player mode, always returns true.
## In networked games, the host always has authority.
## Players have authority if they've been granted CONTROL permission for this token.
## @return: true if input should be processed, false to ignore
func _has_input_authority() -> bool:
	if GameState.has_authority():
		return true
	# Guard against missing multiplayer peer (can happen during reconnection / disconnect)
	if not multiplayer.multiplayer_peer:
		return false
	var board_token = get_parent() as BoardToken
	if board_token:
		return GameState.has_token_permission(
			board_token.network_id, multiplayer.get_unique_id(), TokenPermissions.Permission.CONTROL
		)
	return false


func _ready() -> void:
	if not rigid_body:
		push_warning("BoardTokenController: No RigidBody3D assigned.")
		return

	# Connect to mouse events
	rigid_body.connect("mouse_entered", _on_mouse_entered)
	rigid_body.connect("mouse_exited", _on_mouse_exited)

	# Only process when actively scaling or rotating
	set_process(false)


func _notification(what: int) -> void:
	# When the mouse leaves the game window, Godot's physics picking may not
	# fire mouse_exited on the RigidBody3D. This can cause rapid re-entry
	# cycles at the window boundary, repeatedly triggering the hover sound.
	# Force-clear hover state here to prevent that.
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		if _mouse_over:
			_on_mouse_exited()


func _on_mouse_entered() -> void:
	_mouse_over = true
	# Show hover highlight
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.add_highlight()
	# Cursor: show pointing hand when hovering (not during drag)
	if not draggable_token or not draggable_token.is_being_dragged():
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	# Sound
	AudioManager.play_token_hover()


func _on_mouse_exited() -> void:
	_mouse_over = false
	# Hide hover highlight
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.remove_highlight()
	# Cursor: restore to arrow (only if not currently dragging)
	if not draggable_token or not draggable_token.is_being_dragged():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if not rigid_body:
		return

	# Double-click left mouse to focus camera on this token (any player, no authority needed)
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.double_click
		and _mouse_over
	):
		focus_requested.emit(rigid_body.global_position)
		return

	# Gate all mutating input behind authority check
	# Context menu is allowed for all (read-only viewing), but actions within may be gated
	if not _has_input_authority():
		# Still allow context menu for viewing token info (actions inside will be gated)
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed
			and _mouse_over
		):
			var board_token = get_parent() as BoardToken
			if board_token:
				context_menu_requested.emit(board_token, event.position)
		return

	# Handle right-click for context menu
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and _mouse_over
	):
		var board_token = get_parent() as BoardToken
		if board_token:
			context_menu_requested.emit(board_token, event.position)
		return

	# Check for double-click on middle mouse button to reset rotation and scale
	if (
		event is InputEventMouseButton
		and event.double_click
		and event.is_action_pressed("rotate_model")
		and _mouse_over
	):
		InputProfile.notify_middle_click()
		_reset_rotation_and_scale()
		return

	# --- MMB rotate/scale (original binding) ---
	if event.is_action_pressed("rotate_model") and _mouse_over:
		InputProfile.notify_middle_click()
		# Check if shift is held to determine scaling vs rotation
		if Input.is_key_pressed(KEY_SHIFT):
			_scaling = true
			_scale_accumulator = 0.0
		else:
			_rotating = true
			_rotation_accumulator = 0.0
		set_process(true)
		return

	if event.is_action_released("rotate_model"):
		if _rotating or _scaling:
			_finalize_rotate_scale()
			return

	# --- R+double-click LMB to reset rotation and scale (alternative binding) ---
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.double_click
		and _mouse_over
		and Input.is_key_pressed(KEY_R)
	):
		_reset_rotation_and_scale()
		get_viewport().set_input_as_handled()
		return

	# --- R+LMB rotate/scale (alternative binding) ---
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and _mouse_over
		and Input.is_key_pressed(KEY_R)
	):
		if Input.is_key_pressed(KEY_SHIFT):
			_r_key_scaling = true
			_scaling = true
			_scale_accumulator = 0.0
		else:
			_r_key_rotating = true
			_rotating = true
			_rotation_accumulator = 0.0
		set_process(true)
		get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and (_r_key_rotating or _r_key_scaling)
	):
		_r_key_rotating = false
		_r_key_scaling = false
		_finalize_rotate_scale()
		get_viewport().set_input_as_handled()
		return

	if _rotating and event is InputEventMouseMotion:
		_handle_rotation(event)

	if _scaling and event is InputEventMouseMotion:
		_handle_scaling(event)


## Shared finalize logic for ending a rotate/scale gesture (MMB or R+LMB).
func _finalize_rotate_scale() -> void:
	var was_rotating := _rotating
	var was_scaling := _scaling
	_rotating = false
	_scaling = false
	_rotation_accumulator = 0.0
	_scale_accumulator = 0.0
	set_process(false)

	# Emit signal for network sync when rotation/scale changes complete
	var board_token := get_parent() as BoardToken
	if board_token and (was_rotating or was_scaling):
		board_token.transform_changed.emit()


## Handle rotation input with 45-degree snapping.
## Accumulates mouse velocity until a threshold is reached, then snaps to the next increment
## with a smooth tween animation.
func _handle_rotation(event: InputEventMouseMotion) -> void:
	_rotation_accumulator += event.relative.x

	if abs(_rotation_accumulator) >= ROTATION_INPUT_THRESHOLD:
		var direction = sign(_rotation_accumulator)
		_rotation_accumulator = 0.0

		var snap_radians = deg_to_rad(ROTATION_SNAP_DEGREES)
		var current_y = rigid_body.rotation.y
		var target_y = current_y + snap_radians * direction

		# Snap to nearest multiple of the snap angle
		target_y = round(target_y / snap_radians) * snap_radians

		# Smoothly animate to the snapped rotation
		if _rotation_tween and _rotation_tween.is_valid():
			_rotation_tween.kill()
		_rotation_tween = create_tween()
		(
			_rotation_tween
			. tween_property(rigid_body, "rotation:y", target_y, ROTATION_TWEEN_DURATION)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)


## Handle scaling input with increment snapping.
## Accumulates mouse Y movement until a threshold is reached, then snaps to the next scale
## increment with a smooth tween animation. Mouse up = scale up, mouse down = scale down.
func _handle_scaling(event: InputEventMouseMotion) -> void:
	# Negative so mouse-up = scale-up
	_scale_accumulator -= event.relative.y

	if abs(_scale_accumulator) >= SCALE_INPUT_THRESHOLD:
		var direction = sign(_scale_accumulator)
		_scale_accumulator = 0.0

		var current_scale_val = rigid_body.scale.x
		var target_scale_val = current_scale_val + SCALE_SNAP_INCREMENT * direction

		# Snap to nearest multiple of the snap increment
		target_scale_val = snapped(target_scale_val, SCALE_SNAP_INCREMENT)
		target_scale_val = clampf(target_scale_val, SCALE_MIN, SCALE_MAX)

		var target_scale = Vector3.ONE * target_scale_val

		# Adjust position so the bottom stays grounded
		_adjust_position_for_scale(rigid_body.scale, target_scale)

		# Smoothly animate to the snapped scale
		if _scale_tween and _scale_tween.is_valid():
			_scale_tween.kill()
		_scale_tween = create_tween()
		(
			_scale_tween
			. tween_property(rigid_body, "scale", target_scale, SCALE_TWEEN_DURATION)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		_scale_tween.tween_callback(
			func() -> void:
				if draggable_token:
					draggable_token.update_height_offset()
		)


func _adjust_position_for_scale(old_scale: Vector3, new_scale: Vector3) -> void:
	# Get the collision shape to determine the object's height
	var collision_shape_node: CollisionShape3D = rigid_body.get_node_or_null("CollisionShape3D")
	if collision_shape_node and collision_shape_node.shape:
		var aabb: AABB = collision_shape_node.shape.get_debug_mesh().get_aabb()
		# Calculate the bottom position in local space
		var local_bottom_y = collision_shape_node.position.y + aabb.position.y
		# Calculate how much the bottom moves when scaling from center
		var bottom_offset_old = local_bottom_y * old_scale.y
		var bottom_offset_new = local_bottom_y * new_scale.y
		# Adjust position to compensate
		rigid_body.position.y += (bottom_offset_old - bottom_offset_new)


func _reset_rotation_and_scale() -> void:
	# Store the old scale to calculate position adjustment
	var old_scale = rigid_body.scale

	# Animate rotation reset
	if _rotation_tween and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = create_tween()
	(
		_rotation_tween
		. tween_property(rigid_body, "rotation", Vector3.ZERO, ROTATION_TWEEN_DURATION * 2.0)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	# Calculate position adjustment to keep bottom fixed when resetting scale
	_adjust_position_for_scale(old_scale, Vector3.ONE)

	# Reset scale to default
	rigid_body.scale = Vector3.ONE

	# Recompute the height offset
	if draggable_token:
		draggable_token.update_height_offset()

	# Emit signal for network sync
	var board_token = get_parent() as BoardToken
	if board_token:
		board_token.transform_changed.emit()


func _process(delta: float) -> void:
	# Emit throttled transform updates during rotation/scaling for network sync
	if _rotating or _scaling:
		_transform_update_timer += delta
		if _transform_update_timer >= Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL:
			_transform_update_timer = 0.0
			var board_token = get_parent() as BoardToken
			if board_token:
				board_token.transform_updated.emit()
