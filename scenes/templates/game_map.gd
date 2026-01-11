extends Node3D
class_name GameMap

@export var move_speed: float = 10.0
@export var zoom_speed: float = 20.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

@onready var cameraholder_node: Node3D = $WorldEnvironment/CameraHolder
@onready var camera_node: Camera3D = $WorldEnvironment/CameraHolder/Camera3D
@onready var pixelate_node: ColorRect = $WorldEnvironment/PixelateCanvas/Pixelate

var _camera_move_dir: Vector3
var _camera_zoom_dir: int

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	handle_movement(delta)
	handle_zoom(delta)

func handle_movement(delta):
	cameraholder_node.translate(_camera_move_dir * move_speed * delta)

func handle_zoom(delta):
	if _camera_zoom_dir != 0.0:
		camera_node.size = clamp(camera_node.size + _camera_zoom_dir * zoom_speed * delta, min_zoom, max_zoom)
	
	_camera_zoom_dir = 0
	
	pixelate_node.material.set_shader_parameter("camera_size", camera_node.size)

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	
	if event.is_action_pressed("camera_zoom_in"):
		_camera_zoom_dir -= 1
	if event.is_action_pressed("camera_zoom_out"):
		_camera_zoom_dir += 1

func _unhandled_key_input(event: InputEvent) -> void:
	var input_dir := _camera_move_dir
	
	# Map keyboard inputs to directions
	if event.is_action_pressed("camera_move_forward", true):
		input_dir.z = -cameraholder_node.transform.basis.z.z # Move along the camera's local forward axis
	if event.is_action_pressed("camera_move_backward", true):
		input_dir.z = cameraholder_node.transform.basis.z.z
	if event.is_action_pressed("camera_move_left", true):
		input_dir.x = -cameraholder_node.transform.basis.x.x # Move along the camera's local right/left axis
	if event.is_action_pressed("camera_move_right", true):
		input_dir.x = cameraholder_node.transform.basis.x.x
		
		# Map keyboard inputs to directions
	if event.is_action_released("camera_move_forward", true):
		input_dir.z = 0 # Move along the camera's local forward axis
	if event.is_action_released("camera_move_backward", true):
		input_dir.z = 0
	if event.is_action_released("camera_move_left", true):
		input_dir.x = 0 # Move along the camera's local right/left axis
	if event.is_action_released("camera_move_right", true):
		input_dir.x = 0
	
	 #Keep movement horizontal (prevent movement in the vertical y-axis of the world)
	input_dir.y = 0
	input_dir = input_dir.normalized()
	
	_camera_move_dir = input_dir

func _on_pokemon_list_pokemon_added(pokemon: PackedScene) -> void:
	$WorldEnvironment/DragAndDrop3D.add_child(pokemon.instantiate())
	
