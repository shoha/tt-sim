extends Node3D
class_name BoardToken

const ROTATION_FACTOR: float = 0.0001

var _rotating: bool = false
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_model") and _mouse_over:
		_rotating = true
		return

	if event.is_action_released("rotate_model"):
		_rotating = false
		return

	if event.is_action_pressed("select_token") and _mouse_over:
		print(event.is_action_pressed("select_token"))
		EventBus.emit_signal("token_selected", rigid_body)

	if _rotating and event is InputEventMouseMotion:
		var velocity_x = event.screen_velocity.x
		rigid_body.rotate_y(velocity_x * ROTATION_FACTOR)
