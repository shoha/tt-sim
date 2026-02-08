@tool

extends DraggingObject3D
class_name DraggableToken

## Adds drag-and-drop functionality to a token's RigidBody3D
## Handles visual feedback during dragging (drop indicators, lean effects, settle animations)
## This is a pure interaction component - it has no knowledge of game entity data
##
## Expected hierarchy:
## DraggableToken (this)
## └── RigidBody3D
##     ├── CollisionShape3D (required)
##     └── Visual nodes (MeshInstance3D, etc.)

const PICKUP_HEIGHT: float = 0.25 # How much to raise the token while dragging
const INERTIA_LEAN_STRENGTH: float = 0.3 # How much the token leans from drag velocity (in radians)
const LEAN_SMOOTHING: float = 8.0 # How quickly the lean adjusts to velocity changes
const SETTLE_DURATION: float = 0.3 # Duration of the settle-to-ground animation when dropped
const PICKUP_SPRING_DURATION: float = 0.15 # Duration of the spring-up animation on pickup
const SCALE_PUNCH_AMOUNT: float = 1.05 # Scale multiplier for the pickup punch effect
const TERRAIN_COLLISION_LAYER: int = 1 # Physics layer for terrain/board surfaces

var _base_height_offset: float = 0.0
var _last_drag_position: Vector3 = Vector3.ZERO
var _drag_velocity: Vector3 = Vector3.ZERO
var _target_lean_rotation: Basis = Basis.IDENTITY
var _visual_children: Array[Node3D] = []
var _drop_indicator: DropIndicatorRenderer
var _is_currently_dragging: bool = false
var _is_settling: bool = false # True during settle/cancel animation
var _drag_start_position: Vector3 = Vector3.ZERO # Position when drag started (for cancel)
var _transform_update_timer: float = 0.0
const TRANSFORM_UPDATE_INTERVAL: float = 0.1 # Send updates 10 times per second during drag

# Tweens
var _pickup_tween: Tween = null
var _settle_tween: Tween = null

# Network interpolation state (for smooth client-side motion)
var _network_interpolating: bool = false
var _network_target_position: Vector3 = Vector3.ZERO
var _network_target_rotation: Vector3 = Vector3.ZERO
var _network_target_scale: Vector3 = Vector3.ONE
var _network_interpolation_timeout: float = 0.0
const NETWORK_INTERPOLATION_SPEED: float = 15.0
const NETWORK_INTERPOLATION_TIMEOUT: float = 0.3  # Stop interpolating if no updates for this long

@export var rigid_body: RigidBody3D
@export var collision_shape: CollisionShape3D


func _ready() -> void:
	if !rigid_body:
		rigid_body = get_parent().find_child("RigidBody3D", true, false)

		if not rigid_body:
			push_error("DraggableToken: No RigidBody3D found in parent.")
			return

	if !collision_shape:
		collision_shape = rigid_body.find_child("CollisionShape3D", true, false)

		if not collision_shape:
			push_error("DraggableToken: No CollisionShape3D found in parent.")
			return

	update_height_offset()

	# Only set up dragging signals and indicators during gameplay
	if not Engine.is_editor_hint():
		_collect_visual_children()
		_setup_drop_indicator()

		dragging_started.connect(_on_dragging_started)
		dragging_stopped.connect(_on_dragging_stopped)
		dragging_cancelled.connect(_on_dragging_cancelled)

	super ()


func _setup_drop_indicator() -> void:
	_drop_indicator = DropIndicatorRenderer.new()
	_drop_indicator.exclude_body = rigid_body
	if collision_shape:
		_drop_indicator.set_token_footprint(collision_shape)
	add_child(_drop_indicator)


func _collect_visual_children() -> void:
	for child in rigid_body.get_children():
		if child is Node3D and not child is CollisionShape3D:
			_visual_children.append(child)


## Public method to update height offset based on bounding box
## Should be called when the token's scale or collision shape changes
func update_height_offset() -> void:
	if Engine.is_editor_hint():
		return

	if not collision_shape or not collision_shape.shape:
		return

	var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()

	var scaled_aabb_position = aabb.position * rigid_body.scale
	var scaled_aabb_size = aabb.size * rigid_body.scale
	var scaled_collision_position = collision_shape.position * rigid_body.scale

	var shape_top = scaled_collision_position.y + scaled_aabb_position.y + scaled_aabb_size.y

	_base_height_offset = shape_top / 2
	heightOffset = shape_top / 2


## Get the visual children (non-collision nodes) of the rigid body
## Useful for external components that need to manipulate visuals
func get_visual_children() -> Array[Node3D]:
	return _visual_children


## Whether this token is currently being interacted with (dragging or settling)
func is_being_dragged() -> bool:
	return _is_currently_dragging or _is_settling


# -------------------------------------------------------------------------
# Drag Lifecycle
# -------------------------------------------------------------------------

func _on_dragging_started() -> void:
	# If settling from a previous drop, cancel the settle
	if _is_settling:
		_kill_settle_tween()
		_is_settling = false

	_is_currently_dragging = true

	# Store start position for cancel
	_drag_start_position = rigid_body.global_position

	# Ensure gravity is off (should already be 0 from factory, but be safe)
	rigid_body.gravity_scale = 0.0

	_last_drag_position = rigid_body.global_position
	_drag_velocity = Vector3.ZERO

	# Show drop indicator
	if _drop_indicator:
		_drop_indicator.show_indicator()

	# Spring height animation (pop up with overshoot)
	_kill_pickup_tween()
	_pickup_tween = create_tween()
	_pickup_tween.tween_property(self, "heightOffset", _base_height_offset + PICKUP_HEIGHT, PICKUP_SPRING_DURATION)\
		.from(_base_height_offset)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Scale punch on visual children (subtle pop feel)
	_play_scale_punch()

	# Cursor: closed hand while dragging
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)

	# Sound
	AudioManager.play_token_pickup()


func _on_dragging_stopped() -> void:
	_is_currently_dragging = false

	# Reset lean
	_reset_lean()

	# Kill any active pickup tween
	_kill_pickup_tween()
	heightOffset = _base_height_offset

	# Hide drop indicator
	if _drop_indicator:
		_drop_indicator.hide_indicator()

	_drag_velocity = Vector3.ZERO
	_target_lean_rotation = Basis.IDENTITY

	# Settle to the ground with animation (replaces physics gravity drop)
	_settle_to_ground()


func _on_dragging_cancelled() -> void:
	_is_currently_dragging = false

	# Reset lean
	_reset_lean()

	# Kill any active pickup tween
	_kill_pickup_tween()
	heightOffset = _base_height_offset

	# Hide drop indicator
	if _drop_indicator:
		_drop_indicator.hide_indicator()

	_drag_velocity = Vector3.ZERO
	_target_lean_rotation = Basis.IDENTITY

	# Animate back to original position
	_settle_to_position(_drag_start_position)


# -------------------------------------------------------------------------
# Settle Animations
# -------------------------------------------------------------------------

## Settle the token to the ground below it (normal drop).
func _settle_to_ground() -> void:
	var landing_pos = _find_landing_position()
	if landing_pos == null:
		# No surface below - just finalize in place
		_on_settle_complete()
		return

	_settle_to_position(landing_pos)


## Settle the token to a specific position (used for both drop and cancel).
func _settle_to_position(target_pos: Vector3) -> void:
	_is_settling = true

	# Disable hover detection while settling so the token can't be
	# highlighted / re-picked before it finishes its landing animation.
	rigid_body.input_ray_pickable = false

	_kill_settle_tween()
	_settle_tween = create_tween()
	_settle_tween.tween_property(rigid_body, "global_position", target_pos, SETTLE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_settle_tween.tween_callback(_on_settle_complete)


func _on_settle_complete() -> void:
	_is_settling = false

	# Re-enable hover detection now that the settle animation is done
	rigid_body.input_ray_pickable = true

	# Sync hierarchy positions
	_sync_parent_position()

	# Cursor: restore to arrow
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	# Sound
	AudioManager.play_token_drop()


## Find where the token should land by raycasting down from its bottom.
## Returns Vector3 or null if no surface is found.
func _find_landing_position() -> Variant:
	if not rigid_body or not collision_shape or not collision_shape.shape:
		return null

	var aabb = collision_shape.shape.get_debug_mesh().get_aabb()
	var scaled_bottom_y = (collision_shape.position.y + aabb.position.y) * rigid_body.scale.y
	var bottom_world = rigid_body.global_position + Vector3(0, scaled_bottom_y, 0)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(bottom_world, bottom_world + Vector3.DOWN * 100.0)
	query.collision_mask = TERRAIN_COLLISION_LAYER # Only hit terrain, not other tokens
	query.exclude = [rigid_body.get_rid()]
	var hit = space_state.intersect_ray(query)

	if not hit:
		return null

	# Place token so its bottom sits on the hit surface
	var landing_y = hit.position.y - scaled_bottom_y
	return Vector3(rigid_body.global_position.x, landing_y, rigid_body.global_position.z)


# -------------------------------------------------------------------------
# Visual Effects
# -------------------------------------------------------------------------

## Play a subtle scale punch on visual children (pop feel on pickup).
func _play_scale_punch() -> void:
	for child in _visual_children:
		if is_instance_valid(child):
			var base_scale = child.scale
			var punch_scale = base_scale * SCALE_PUNCH_AMOUNT
			var tween = create_tween()
			tween.tween_property(child, "scale", punch_scale, PICKUP_SPRING_DURATION * 0.5)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(child, "scale", base_scale, PICKUP_SPRING_DURATION * 0.5)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _reset_lean() -> void:
	for child in _visual_children:
		if is_instance_valid(child):
			child.transform.basis = Basis.IDENTITY


func _update_inertia_lean(delta: float) -> void:
	var current_position = rigid_body.global_position
	var position_delta = current_position - _last_drag_position

	_drag_velocity = _drag_velocity.lerp(position_delta / delta, 0.3)
	_last_drag_position = current_position

	var horizontal_velocity = Vector3(_drag_velocity.x, 0, _drag_velocity.z)

	if horizontal_velocity.length() > 0.001:
		var lean_axis = horizontal_velocity.cross(Vector3.UP).normalized()
		var lean_angle = clamp(horizontal_velocity.length() * INERTIA_LEAN_STRENGTH, 0.0, 0.5)
		_target_lean_rotation = Basis(lean_axis, lean_angle)
	else:
		_target_lean_rotation = Basis.IDENTITY

	for child in _visual_children:
		if is_instance_valid(child):
			var current_basis = child.transform.basis.orthonormalized()
			child.transform.basis = current_basis.slerp(_target_lean_rotation, LEAN_SMOOTHING * delta).orthonormalized()


# -------------------------------------------------------------------------
# Process
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _is_currently_dragging:
		_update_drop_indicator()
		_update_inertia_lean(delta)

		# Emit throttled transform updates for network sync
		_transform_update_timer += delta
		if _transform_update_timer >= TRANSFORM_UPDATE_INTERVAL:
			_transform_update_timer = 0.0
			var board_token = get_parent() as BoardToken
			if board_token:
				board_token.transform_updated.emit()
	elif _network_interpolating:
		# Handle network interpolation with lean effects (same as dragging)
		_update_network_interpolation(delta)


func _update_drop_indicator() -> void:
	if not _drop_indicator or not collision_shape or not collision_shape.shape:
		return

	# Calculate the bottom center of the token
	var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()
	var scaled_aabb_position = aabb.position * rigid_body.scale
	var scaled_collision_position = collision_shape.position * rigid_body.scale
	var bottom_y = scaled_collision_position.y + scaled_aabb_position.y

	var start_pos = rigid_body.global_position + Vector3(0, bottom_y, 0)
	_drop_indicator.update(start_pos)


# -------------------------------------------------------------------------
# Position Sync
# -------------------------------------------------------------------------

## Sync the parent BoardToken's position with the rigid body after dragging
## This keeps the entire hierarchy in sync so reading from any node gives the correct position
func _sync_parent_position() -> void:
	if not rigid_body:
		return

	# Find the BoardToken (grandparent: BoardToken -> DraggableToken -> RigidBody3D)
	var board_token = get_parent()
	if not board_token or not board_token is BoardToken:
		return

	# Get the rigid body's world position
	var world_pos = rigid_body.global_position
	var world_rot = rigid_body.global_rotation

	# Move the BoardToken to match the rigid body's world position
	board_token.global_position = world_pos
	board_token.global_rotation = world_rot

	# Reset the intermediate nodes to local origin so hierarchy stays clean
	# DraggableToken (self) relative to BoardToken
	position = Vector3.ZERO
	rotation = Vector3.ZERO

	# RigidBody3D relative to DraggableToken
	rigid_body.position = Vector3.ZERO
	rigid_body.rotation = Vector3.ZERO

	# Notify that the token position has changed (for network sync)
	board_token.position_changed.emit()


# -------------------------------------------------------------------------
# Tween Helpers
# -------------------------------------------------------------------------

func _kill_pickup_tween() -> void:
	if _pickup_tween and _pickup_tween.is_valid():
		_pickup_tween.kill()
	_pickup_tween = null


func _kill_settle_tween() -> void:
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
	_settle_tween = null


# -------------------------------------------------------------------------
# Network Interpolation
# -------------------------------------------------------------------------

## Handle network interpolation - smoothly moves towards target with lean effects
func _update_network_interpolation(delta: float) -> void:
	if not rigid_body:
		return

	# Store previous position for velocity calculation
	var prev_position = rigid_body.global_position

	# Interpolate position, rotation, and scale
	rigid_body.global_position = rigid_body.global_position.lerp(_network_target_position, NETWORK_INTERPOLATION_SPEED * delta)
	rigid_body.global_rotation = rigid_body.global_rotation.lerp(_network_target_rotation, NETWORK_INTERPOLATION_SPEED * delta)
	rigid_body.scale = rigid_body.scale.lerp(_network_target_scale, NETWORK_INTERPOLATION_SPEED * delta)

	# Update drop indicator (same as local dragging)
	_update_drop_indicator()

	# Compute velocity from movement for lean effect
	var position_delta = rigid_body.global_position - prev_position
	_drag_velocity = _drag_velocity.lerp(position_delta / delta, 0.3)

	# Apply lean based on velocity (same formula as local dragging)
	var horizontal_velocity = Vector3(_drag_velocity.x, 0, _drag_velocity.z)
	if horizontal_velocity.length() > 0.001:
		var lean_axis = horizontal_velocity.cross(Vector3.UP).normalized()
		var lean_angle = clamp(horizontal_velocity.length() * INERTIA_LEAN_STRENGTH, 0.0, 0.5)
		_target_lean_rotation = Basis(lean_axis, lean_angle)
	else:
		_target_lean_rotation = Basis.IDENTITY

	# Apply lean to visual children
	for child in _visual_children:
		if is_instance_valid(child):
			var current_basis = child.transform.basis.orthonormalized()
			child.transform.basis = current_basis.slerp(_target_lean_rotation, LEAN_SMOOTHING * delta).orthonormalized()

	# Check timeout - stop interpolating if no updates received recently
	_network_interpolation_timeout -= delta
	if _network_interpolation_timeout <= 0:
		_stop_network_interpolation()


## Set network interpolation target (called by network sync on clients)
func set_network_target(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	_network_target_position = p_position
	_network_target_rotation = p_rotation
	_network_target_scale = p_scale

	# Reset timeout - we're still receiving updates
	_network_interpolation_timeout = NETWORK_INTERPOLATION_TIMEOUT

	# Start network interpolation if not already active
	if not _network_interpolating:
		_network_interpolating = true
		# Disable gravity while being remotely manipulated (same as local dragging)
		if rigid_body:
			rigid_body.gravity_scale = 0.0
		# Show drop indicator (same as local dragging)
		if _drop_indicator:
			_drop_indicator.show_indicator()

	# Initialize last drag position if not already set
	if _last_drag_position == Vector3.ZERO and rigid_body:
		_last_drag_position = rigid_body.global_position


## Stop network interpolation and settle to ground
func _stop_network_interpolation() -> void:
	if not _network_interpolating:
		return

	_network_interpolating = false
	_drag_velocity = Vector3.ZERO

	# Hide drop indicator
	if _drop_indicator:
		_drop_indicator.hide_indicator()

	# Settle to ground after remote manipulation ends
	_settle_to_ground()


## Directly set transform without interpolation (for initial placement)
func set_transform_immediate(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	_stop_network_interpolation()
	_target_lean_rotation = Basis.IDENTITY

	if rigid_body:
		rigid_body.global_position = p_position
		rigid_body.global_rotation = p_rotation
		rigid_body.scale = p_scale

	# Reset lean on visual children
	for child in _visual_children:
		if is_instance_valid(child):
			child.transform.basis = Basis.IDENTITY

	# Update targets to match
	_network_target_position = p_position
	_network_target_rotation = p_rotation
	_network_target_scale = p_scale
