@tool

extends DraggingObject3D
class_name Token

const ROTATION_FACTOR: float = 0.0001

var _rotating: bool = false
var _rigid_body: RigidBody3D
var _mouse_over: bool = false

func _init(rigid_body: RigidBody3D = null) -> void:
	if rigid_body:
		# Remove any existing RigidBody3D children
		for child in get_children():
			if child is RigidBody3D:
				child.queue_free()

		_rigid_body = rigid_body
		add_child(rigid_body)

func _ready() -> void:
	# Use the provided rigid_body or get it from children
	if not _rigid_body:
		_rigid_body = get_child(0) as RigidBody3D

	if not _rigid_body:
		push_error("DraggableToken requires a RigidBody3D node")
		return

	_rigid_body.connect("mouse_entered", _mouse_entered)
	_rigid_body.connect("mouse_exited", _mouse_exited)

	_set_height_offset_from_bounding_box()

	super ()


func _set_height_offset_from_bounding_box() -> void:
	if Engine.is_editor_hint():
		return

	# Find the CollisionShape3D child
	var collision_shape: CollisionShape3D = $RigidBody3D/CollisionShape3D

	if not collision_shape or not collision_shape.shape:
		return

	# Get the bounding box of the shape
	var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()

	# Account for the collision shape's local position
	var shape_top = collision_shape.position.y + aabb.position.y + aabb.size.y

	# Set height offset to align the bottom of the bounding box at y=0
	heightOffset = shape_top

func _mouse_entered():
	_mouse_over = true

func _mouse_exited():
	_mouse_over = false

func _process(_delta: float) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_model") and _mouse_over:
		_rotating = true
		return

	if event.is_action_released("rotate_model"):
		_rotating = false
		return

	if event.is_action_pressed("select_token") and _mouse_over:
		print(event.is_action_pressed("select_token"))
		EventBus.emit_signal("token_selected", _rigid_body)

	if _rotating and event is InputEventMouseMotion:
		var velocity_x = event.screen_velocity.x
		_rigid_body.rotate_y(velocity_x * ROTATION_FACTOR)
