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
@onready var drag_and_drop_node: Node3D = $WorldEnvironment/DragAndDrop3D

var _camera_move_dir: Vector3
var _camera_zoom_dir: int
var _context_menu = null # TokenContextMenu - dynamically typed to avoid load order issues

func _ready() -> void:
	EventBus.pokemon_added.connect(_on_pokemon_list_pokemon_added)
	EventBus.token_selected.connect(_on_token_selected)
	_setup_context_menu()

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
	var scene = pokemon.instantiate()
	var board_token = BoardTokenFactory.create_from_scene(scene)
	if not board_token:
		push_error("GameMap: Failed to create board token")
		return
	drag_and_drop_node.add_child(board_token)

	# Connect context menu request from the token
	var token_controller = board_token.get_controller_component()
	if token_controller:
		token_controller.context_menu_requested.connect(_on_token_context_menu_requested)

func _on_token_selected(_token: Node3D) -> void:
	pass

func _setup_context_menu() -> void:
	# Load and add the context menu to the UI layer
	var context_menu_scene = load("uid://bh84knb3smm3y")
	if context_menu_scene:
		_context_menu = context_menu_scene.instantiate()
		# Find the MapMenu canvas layer to add the menu to
		var map_menu = get_node_or_null("../MapMenu/MapMenu")
		if map_menu:
			map_menu.add_child(_context_menu)
		else:
			# Fallback: add to the scene root if MapMenu not found
			add_child(_context_menu)

		# Connect context menu signals
		_context_menu.hp_adjustment_requested.connect(_on_context_menu_hp_adjustment_requested)
		_context_menu.visibility_toggled.connect(_on_context_menu_visibility_toggled)

func _on_token_context_menu_requested(token: iBoardToken, menu_position: Vector2) -> void:
	if _context_menu:
		_context_menu.open_for_token(token, menu_position)

func _on_context_menu_hp_adjustment_requested(amount: int) -> void:
	if _context_menu and _context_menu.target_token:
		if amount > 0:
			_context_menu.target_token.heal(amount)
		else:
			_context_menu.target_token.take_damage(amount)

func _on_context_menu_visibility_toggled() -> void:
	if _context_menu and _context_menu.target_token:
		_context_menu.target_token.toggle_visibility()
