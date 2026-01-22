extends Node3D
class_name BoardToken

const ROTATION_FACTOR: float = 0.0001
const SCALE_FACTOR: float = 0.0001

var _rotating: bool = false
var _scaling: bool = false
var _mouse_over: bool = false
@export var rigid_body: RigidBody3D

@onready var _dragging_object: DraggingObject3D = $DraggingObject3D
@onready var _original_rigid_body: RigidBody3D = $DraggingObject3D/RigidBody3D

func setup(rb: RigidBody3D = null) -> void:
	if rb:
		rigid_body = rb

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if rigid_body:
		_dragging_object.remove_child(_original_rigid_body)
		_dragging_object.add_child(rigid_body)
		_dragging_object._ready()

	elif not rigid_body:
		rigid_body = _original_rigid_body

		if not rigid_body:
			push_error("No RigidBody3D found in Token node.")
			return

	rigid_body.connect("mouse_entered", _mouse_entered)
	rigid_body.connect("mouse_exited", _mouse_exited)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _mouse_entered():
	_mouse_over = true

func _mouse_exited():
	_mouse_over = false

func _reset_rotation_and_scale() -> void:
	# Store the old scale to calculate position adjustment
	var old_scale = rigid_body.scale
	
	# Reset rotation to identity (no rotation)
	rigid_body.rotation = Vector3.ZERO
	
	# Calculate position adjustment to keep bottom fixed when resetting scale
	var collision_shape: CollisionShape3D = rigid_body.get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape:
		var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()
		var local_bottom_y = collision_shape.position.y + aabb.position.y
		var bottom_offset_old = local_bottom_y * old_scale.y
		var bottom_offset_new = local_bottom_y * 1.0 # New scale is 1.0
		rigid_body.position.y += (bottom_offset_old - bottom_offset_new)
	
	# Reset scale to default
	rigid_body.scale = Vector3.ONE
	
	# Recompute the height offset
	if _dragging_object is DraggableToken:
		_dragging_object._set_height_offset_from_bounding_box()

func _unhandled_input(event: InputEvent) -> void:
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
		_rotating = false
		_scaling = false
		return

	if event.is_action_pressed("select_token") and _mouse_over:
		print(event.is_action_pressed("select_token"))
		EventBus.emit_signal("token_selected", rigid_body)

	if _rotating and event is InputEventMouseMotion:
		var velocity_x = event.screen_velocity.x
		rigid_body.rotate_y(velocity_x * ROTATION_FACTOR)
	
	if _scaling and event is InputEventMouseMotion:
		var velocity_y = event.screen_velocity.y
		# Use negative velocity_y so moving mouse up scales up, down scales down
		var scale_change = - velocity_y * SCALE_FACTOR
		var old_scale = rigid_body.scale
		var new_scale = rigid_body.scale + Vector3.ONE * scale_change
		# Clamp the scale to prevent it from going too small or too large
		new_scale = new_scale.clamp(Vector3.ONE * 0.1, Vector3.ONE * 10.0)
		
		# Calculate the position adjustment to keep the bottom fixed
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
		
		rigid_body.scale = new_scale
		
		# Recompute the height offset to keep it in sync with the new AABB size
		if _dragging_object is DraggableToken:
			_dragging_object._set_height_offset_from_bounding_box()
