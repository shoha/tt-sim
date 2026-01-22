@tool

extends DraggingObject3D
class_name DraggableToken

const ROTATION_FACTOR: float = 0.0001
const PICKUP_HEIGHT: float = 0.5 # How much to raise the token while dragging

var _base_height_offset: float = 0.0

@onready var _rigid_body: RigidBody3D = $RigidBody3D
@onready var _collision_shape: CollisionShape3D = $RigidBody3D/CollisionShape3D

func _ready() -> void:
	if not _rigid_body:
		push_error("DraggableToken requires a RigidBody3D node")
		return

	_set_height_offset_from_bounding_box()

	# Connect to dragging signals to disable gravity while dragging
	dragging_started.connect(_on_dragging_started)
	dragging_stopped.connect(_on_dragging_stopped)

	super ()


func _set_height_offset_from_bounding_box() -> void:
	if Engine.is_editor_hint():
		return

	if not _collision_shape or not _collision_shape.shape:
		return

	# Get the bounding box of the shape
	var aabb: AABB = _collision_shape.shape.get_debug_mesh().get_aabb()

	# Account for the rigid_body's scale transformation
	var scaled_aabb_position = aabb.position * _rigid_body.scale
	var scaled_aabb_size = aabb.size * _rigid_body.scale

	# Account for the collision shape's local position (also affected by scale)
	var scaled_collision_position = _collision_shape.position * _rigid_body.scale

	# Calculate the top of the shape with scaling applied
	var shape_top = scaled_collision_position.y + scaled_aabb_position.y + scaled_aabb_size.y

	# Set height offset to align the bottom of the bounding box at y=0
	_base_height_offset = shape_top
	heightOffset = shape_top

func _on_dragging_started() -> void:
	# Disable gravity while dragging
	_rigid_body.gravity_scale = 0.0
	# Raise the token to create a "picked up" effect
	heightOffset = _base_height_offset + PICKUP_HEIGHT

func _on_dragging_stopped() -> void:
	# Re-enable gravity when dragging stops
	_rigid_body.gravity_scale = 1.0
	# Lower the token back to its base height
	heightOffset = _base_height_offset

func _process(_delta: float) -> void:
	pass
