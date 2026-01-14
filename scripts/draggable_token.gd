@tool

extends DraggingObject3D
class_name DraggableToken

const ROTATION_FACTOR: float = 0.0001

var _rotating: bool = false
var _rigid_body: RigidBody3D
var _mouse_over: bool = false

func _ready() -> void:
	_rigid_body = get_child(0)
	_rigid_body.connect("mouse_entered", _mouse_entered)
	_rigid_body.connect("mouse_exited", _mouse_exited)
	
	super()

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
		
		
	

	
	
