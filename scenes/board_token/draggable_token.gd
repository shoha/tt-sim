@tool

extends DraggingObject3D
class_name DraggableToken

## Adds drag-and-drop functionality to a token's RigidBody3D
## Handles visual feedback during dragging (drop indicators, lean effects)
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

var _base_height_offset: float = 0.0
var _last_drag_position: Vector3 = Vector3.ZERO
var _drag_velocity: Vector3 = Vector3.ZERO
var _target_lean_rotation: Basis = Basis.IDENTITY
var _visual_children: Array[Node3D] = []
var _drop_indicator: DropIndicatorRenderer
var _is_currently_dragging: bool = false # Track dragging state properly

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

	super ()


func _setup_drop_indicator() -> void:
	_drop_indicator = DropIndicatorRenderer.new()
	_drop_indicator.exclude_body = rigid_body
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


func _on_dragging_started() -> void:
	_is_currently_dragging = true
	rigid_body.gravity_scale = 0.0
	heightOffset = _base_height_offset + PICKUP_HEIGHT

	_last_drag_position = rigid_body.global_position
	_drag_velocity = Vector3.ZERO

	if _drop_indicator:
		_drop_indicator.show_indicator()


func _on_dragging_stopped() -> void:
	_is_currently_dragging = false

	for child in _visual_children:
		if is_instance_valid(child):
			child.transform.basis = Basis.IDENTITY

	rigid_body.gravity_scale = 1.0
	heightOffset = _base_height_offset

	if _drop_indicator:
		_drop_indicator.hide_indicator()

	_drag_velocity = Vector3.ZERO
	_target_lean_rotation = Basis.IDENTITY

	# Sync the parent BoardToken position with the rigid body
	_sync_parent_position()


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


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _is_currently_dragging:
		_update_drop_indicator()
		_update_inertia_lean(delta)


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
