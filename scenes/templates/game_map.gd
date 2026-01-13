extends Node3D
class_name GameMap

@export var move_speed: float = 10.0
@export var zoom_speed: float = 20.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

@onready var cameraholder_node: Node3D = $WorldEnvironment/CameraHolder
@onready var camera_node: Camera3D = $WorldEnvironment/CameraHolder/Camera3D
@onready var pixelate_node: ColorRect = $WorldEnvironment/PixelateCanvas/Pixelate
@onready var tiltshift_node: MeshInstance3D = $WorldEnvironment/CameraHolder/Camera3D/MeshInstance3D

var _camera_move_dir: Vector3
var _camera_zoom_dir: int

func _ready() -> void:
	EventBus.pokemon_added.connect(_on_pokemon_list_pokemon_added)
	pass # Replace with function body.

func _process(delta):
	handle_movement(delta)
	handle_zoom(delta)

func handle_movement(delta):
	cameraholder_node.translate(_camera_move_dir * move_speed * delta)

func handle_zoom(delta):
	var zoom_level = clamp(camera_node.size + _camera_zoom_dir * zoom_speed * delta, min_zoom, max_zoom)
	
	if _camera_zoom_dir != 0.0:
		camera_node.size = zoom_level
	
	_camera_zoom_dir = 0
	pixelate_node.material.set_shader_parameter(&"camera_size", camera_node.size)
	
	var zoom_percentage: float = (zoom_level - min_zoom) / (max_zoom - min_zoom)
	tiltshift_node.mesh.material.set_shader_parameter(&"DoF", 5 * zoom_percentage)
	

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	
	if event.is_action_pressed("camera_zoom_in"):
		_camera_zoom_dir -= 1
	if event.is_action_pressed("camera_zoom_out"):
		_camera_zoom_dir += 1

func _unhandled_key_input(event: InputEvent) -> void:
	var input_dir := _camera_move_dir
	
	if event.is_action_released("camera_move_forward"):
		input_dir.x += 1
		input_dir.z += 1
	if event.is_action_released("camera_move_backward"):
		input_dir.x -= 1
		input_dir.z -= 1
	if event.is_action_released("camera_move_left"):
		input_dir.x += 1
		input_dir.z -= 1
	if event.is_action_released("camera_move_right"):
		input_dir.x -= 1
		input_dir.z += 1
	
	if event.is_action_pressed("camera_move_forward"):
		input_dir.x -= 1
		input_dir.z -= 1
	if event.is_action_pressed("camera_move_backward"):
		input_dir.x += 1
		input_dir.z += 1
	if event.is_action_pressed("camera_move_left"):
		input_dir.x -= 1
		input_dir.z += 1
	if event.is_action_pressed("camera_move_right"):
		input_dir.x += 1
		input_dir.z -= 1
		
	input_dir.y = 0	
	_camera_move_dir = input_dir

func _on_pokemon_list_pokemon_added(pokemon: PackedScene) -> void:
	$WorldEnvironment/DragAndDrop3D.add_child(pokemon.instantiate())
