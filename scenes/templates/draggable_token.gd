@tool

extends DraggingObject3D
class_name DraggableToken

const ROTATION_FACTOR: float = 0.0001

@onready var _rigid_body: RigidBody3D = $RigidBody3D
@onready var _collision_shape: CollisionShape3D = $RigidBody3D/CollisionShape3D

func _ready() -> void:
	if not _rigid_body:
		push_error("DraggableToken requires a RigidBody3D node")
		return

	_set_height_offset_from_bounding_box()

	super ()


func _set_height_offset_from_bounding_box() -> void:
	if Engine.is_editor_hint():
		return

	if not _collision_shape or not _collision_shape.shape:
		return

	# Get the bounding box of the shape
	var aabb: AABB = _collision_shape.shape.get_debug_mesh().get_aabb()

	# Account for the collision shape's local position
	var shape_top = _collision_shape.position.y + aabb.position.y + aabb.size.y

	# Set height offset to align the bottom of the bounding box at y=0
	heightOffset = shape_top

func _process(_delta: float) -> void:
	pass
