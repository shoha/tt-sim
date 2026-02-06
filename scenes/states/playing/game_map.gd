extends Node3D
class_name GameMap

@export var move_speed: float = 10.0
@export var zoom_speed: float = 20.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

# SubViewport-based structure for proper transparency support
# The 3D scene renders to a SubViewport, then the lo-fi shader is applied
# as a 2D post-process via the SubViewportContainer's material
@onready var viewport_container: SubViewportContainer = $WorldViewportLayer/SubViewportContainer
@onready var world_viewport: SubViewport = $WorldViewportLayer/SubViewportContainer/SubViewport
@onready var cameraholder_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder
@onready var camera_node: Camera3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D
@onready var tiltshift_node: MeshInstance3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D/MeshInstance3D
@onready var drag_and_drop_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/DragAndDrop3D
@onready var gameplay_menu: CanvasLayer = $GameplayMenu

var _camera_move_dir: Vector3
var _camera_zoom_dir: int
var _context_menu = null # TokenContextMenu - dynamically typed to avoid load order issues
var _level_play_controller: LevelPlayController = null

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	_setup_context_menu()
	_setup_viewport()
	_load_lofi_setting()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Pass the controller to the gameplay menu
	if gameplay_menu:
		var menu_controller = gameplay_menu.get_node_or_null("GameplayMenu")
		if menu_controller and menu_controller.has_method("setup"):
			menu_controller.setup(level_play_controller)

func _process(delta: float) -> void:
	handle_movement(delta)
	handle_zoom(delta)


func handle_movement(delta: float) -> void:
	cameraholder_node.translate(_camera_move_dir * move_speed * delta)


func handle_zoom(delta: float) -> void:
	var zoom_level = clamp(camera_node.size + _camera_zoom_dir * zoom_speed * delta, min_zoom, max_zoom)

	if _camera_zoom_dir != 0.0:
		camera_node.size = zoom_level

	_camera_zoom_dir = 0

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
	# Don't process camera input if a text input has focus
	if _is_text_input_focused():
		return
	
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


## Check if a text input control currently has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _setup_context_menu() -> void:
	# Load and add the context menu to the UI layer
	var context_menu_scene = load("uid://bh84knb3smm3y")
	if context_menu_scene:
		_context_menu = context_menu_scene.instantiate()
		# Find the GameplayMenu canvas layer to add the menu to
		var menu_control = gameplay_menu.get_node_or_null("GameplayMenu") if gameplay_menu else null
		if menu_control:
			menu_control.add_child(_context_menu)
		else:
			# Fallback: add to the scene root if GameplayMenu not found
			add_child(_context_menu)

		# Connect context menu signals
		_context_menu.hp_adjustment_requested.connect(_on_context_menu_hp_adjustment_requested)
		_context_menu.visibility_toggled.connect(_on_context_menu_visibility_toggled)

func _on_token_context_menu_requested(token: BoardToken, menu_position: Vector2) -> void:
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


## Setup the SubViewport for proper rendering
## With SubViewportContainer.stretch = true, viewport size is managed automatically
func _setup_viewport() -> void:
	# The SubViewportContainer with stretch=true automatically handles sizing
	# No manual setup needed
	pass


## Load lo-fi filter setting from config
func _load_lofi_setting() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	# Default to enabled if no setting exists
	var lofi_enabled = true
	if err == OK:
		lofi_enabled = config.get_value("graphics", "lofi_enabled", true)
	
	set_lofi_enabled(lofi_enabled)


## Enable or disable the lo-fi visual filter
func set_lofi_enabled(enabled: bool) -> void:
	if viewport_container:
		if enabled:
			# Apply the lo-fi shader material
			var shader = load("res://shaders/lofi_canvas.gdshader")
			var material = ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("pixelation", 0.003)
			material.set_shader_parameter("saturation", 0.85)
			material.set_shader_parameter("color_tint", Color(1.02, 1.0, 0.96))
			material.set_shader_parameter("vignette_strength", 0.3)
			material.set_shader_parameter("vignette_radius", 0.8)
			material.set_shader_parameter("grain_intensity", 0.025)
			material.set_shader_parameter("grain_speed", 0.2)
			material.set_shader_parameter("grain_scale", 0.12)
			viewport_container.material = material
		else:
			# Remove the shader to show unprocessed viewport
			viewport_container.material = null
