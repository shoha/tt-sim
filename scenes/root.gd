extends Node3D

@export var move_speed: float = 10.0
@export var zoom_speed: float = 20.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

@onready var cameraholder_node: Node3D = $WorldEnvironment/CameraHolder
@onready var camera_node: Camera3D = $WorldEnvironment/CameraHolder/Camera3D
@onready var pixelate_node: ColorRect = $WorldEnvironment/PixelateCanvas/Pixelate

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	handle_movement(delta)
	handle_zoom(delta)

func handle_movement(delta):
	var input_dir := Vector3.ZERO
	
	# Map keyboard inputs to directions
	if Input.is_action_pressed("camera_move_forward"):
		input_dir -= cameraholder_node.transform.basis.z # Move along the camera's local forward axis
	if Input.is_action_pressed("camera_move_backward"):
		input_dir += cameraholder_node.transform.basis.z
	if Input.is_action_pressed("camera_move_left"):
		input_dir -= cameraholder_node.transform.basis.x # Move along the camera's local right/left axis
	if Input.is_action_pressed("camera_move_right"):
		input_dir += cameraholder_node.transform.basis.x
	
	# Keep movement horizontal (prevent movement in the vertical y-axis of the world)
	input_dir.y = 0
	input_dir = input_dir.normalized()
	
	# Apply movement
	cameraholder_node.translate(input_dir * move_speed * delta)

func handle_zoom(delta):
	var zoom_delta: float = 0.0
	
	# Map mouse wheel input to zoom
	if Input.is_action_pressed("camera_zoom_in") or Input.is_action_just_pressed("camera_zoom_in"):
		zoom_delta = -1.0
	elif Input.is_action_pressed("camera_zoom_out") or Input.is_action_just_pressed("camera_zoom_out"):
		zoom_delta = 1.0
		
	if zoom_delta != 0.0:
		camera_node.size = clamp(camera_node.size + zoom_delta * zoom_speed * delta, min_zoom, max_zoom)
	
	pixelate_node.material.set_shader_parameter("camera_size", camera_node.size)
