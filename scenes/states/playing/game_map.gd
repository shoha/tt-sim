extends Node3D
class_name GameMap

## Main game map controller for the playing state.
## Manages camera movement/zoom, the lo-fi visual effect, and token context menus.
##
## ARCHITECTURE (SubViewport-based rendering):
## The 3D scene renders to a SubViewport, then the lo-fi shader is applied as a
## 2D post-process via SubViewportContainer's material. This approach properly
## handles transparent objects (glass, water, particles, selection glow) - they
## all receive the lo-fi effect correctly.
##
## Scene structure:
##   GameMap (Node3D) - this script
##   ├── WorldViewportLayer (CanvasLayer, layer=-1)
##   │   └── SubViewportContainer (lo-fi shader applied here)
##   │       └── SubViewport
##   │           ├── CameraHolder/Camera3D
##   │           ├── MapContainer (map geometry, environment)
##   │           ├── DragAndDrop3D (tokens)
##   │           └── OcclusionFadeManager (fades geometry hiding tokens)
##   └── GameplayMenu (CanvasLayer - UI on top)
##
## INPUT HANDLING NOTE:
## Camera zoom uses _input() instead of _unhandled_input() because input events
## routed through SubViewportContainer may not reach _unhandled_input on this node.
## Keyboard camera movement still uses _unhandled_key_input() which works correctly.
##
## LO-FI EFFECT:
## Toggle via set_lofi_enabled(bool) or Settings menu. The effect is applied
## by setting a ShaderMaterial on viewport_container. See lofi_canvas.gdshader.

@export var move_speed: float = 10.0
@export var move_accel_speed: float = 15.0  # Smoothing rate for camera movement acceleration/deceleration
@export var zoom_step: float = 1.5  # How much each scroll tick changes the target zoom
@export var zoom_smooth_speed: float = 12.0  # Smoothing rate for zoom interpolation
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0
@onready var viewport_container: SubViewportContainer = $WorldViewportLayer/SubViewportContainer
@onready var world_viewport: SubViewport = $WorldViewportLayer/SubViewportContainer/SubViewport
@onready
var cameraholder_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder
@onready
var camera_node: Camera3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D
@onready
var tiltshift_node: MeshInstance3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D/MeshInstance3D
@onready
var map_container: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/MapContainer
@onready
var drag_and_drop_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/DragAndDrop3D
@onready  # OcclusionFadeManager - type resolved at runtime after editor imports the new script
var occlusion_fade: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/OcclusionFadeManager
@onready var gameplay_menu: CanvasLayer = $GameplayMenu

var _camera_move_dir: Vector3
var _camera_velocity: Vector3 = Vector3.ZERO  # Smoothed camera movement velocity
var _target_zoom: float = 0.0  # Target zoom level (smoothly interpolated toward)
var _current_edge_pan: Vector2 = Vector2.ZERO  # Smoothed edge pan direction
var _context_menu = null  # TokenContextMenu - dynamically typed to avoid load order issues
var _level_play_controller: LevelPlayController = null
var _lofi_material: ShaderMaterial = null  # Cached lo-fi material (from scene or created)
var _occlusion_fade_enabled: bool = true  # Whether the occlusion fade effect is active

const EDGE_PAN_SMOOTH_SPEED: float = 8.0  # Smoothing rate for edge panning ramp-up/coast-out
const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	_setup_context_menu()
	_setup_viewport()
	_load_lofi_setting()
	_load_occlusion_fade_setting()
	_setup_occlusion_fade()
	# Initialize target zoom from the camera's current size
	_target_zoom = camera_node.size


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller

	# Pass the controller to the gameplay menu
	if gameplay_menu:
		var menu_controller = gameplay_menu.get_node_or_null("GameplayMenu")
		if menu_controller and menu_controller.has_method("setup"):
			menu_controller.setup(level_play_controller)


func _process(delta: float) -> void:
	# Don't process camera movement while a level is loading
	if _is_level_loading():
		return
	handle_movement(delta)
	handle_zoom(delta)
	_handle_edge_pan(delta)


func handle_movement(delta: float) -> void:
	# Smoothly accelerate toward target velocity and decelerate when keys released
	var target_velocity = _camera_move_dir * move_speed
	var smooth_factor = 1.0 - exp(-move_accel_speed * delta)
	_camera_velocity = _camera_velocity.lerp(target_velocity, smooth_factor)

	# Only translate if velocity is meaningful (avoid micro-drift)
	if _camera_velocity.length_squared() > 0.001:
		cameraholder_node.translate(_camera_velocity * delta)


func handle_zoom(delta: float) -> void:
	# Smoothly interpolate camera size toward target zoom
	var smooth_factor = 1.0 - exp(-zoom_smooth_speed * delta)
	camera_node.size = lerpf(camera_node.size, _target_zoom, smooth_factor)

	# Update tilt-shift DoF from actual interpolated zoom
	var zoom_percentage: float = (camera_node.size - min_zoom) / (max_zoom - min_zoom)
	tiltshift_node.mesh.material.set_shader_parameter(&"DoF", 5 * zoom_percentage)


func _input(event: InputEvent) -> void:
	# Handle zoom input - use _input instead of _unhandled_input because
	# events going through SubViewportContainer may not reach _unhandled_input
	if event is not InputEventMouseButton:
		return

	# Don't zoom while a level is loading
	if _is_level_loading():
		return

	# Don't zoom when scrolling over any UI element (e.g. asset browser list)
	if _is_mouse_over_gui():
		return

	# Don't zoom while dragging - scroll wheel is used for token height adjustment
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		return

	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
	if event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)


func _unhandled_key_input(event: InputEvent) -> void:
	# Don't process camera input while a level is loading
	if _is_level_loading():
		return

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


## Check if a level is currently being loaded
func _is_level_loading() -> bool:
	return _level_play_controller and _level_play_controller.is_loading()


## Check if a text input control currently has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## Check if the mouse is currently hovering over any UI control (not the 3D viewport).
## Uses gui_get_hovered_control() for a general check that works with any UI overlay.
func _is_mouse_over_gui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	# The SubViewportContainer is our 3D rendering surface, not a UI element
	if hovered == viewport_container:
		return false
	return true


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
	# Cache the lo-fi material from the scene (if present)
	# This allows editor-tweaked values to be preserved
	if viewport_container and viewport_container.material is ShaderMaterial:
		_lofi_material = viewport_container.material as ShaderMaterial


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
			# Use the cached material (from scene) or create a default one
			if not _lofi_material:
				_lofi_material = _create_default_lofi_material()
			viewport_container.material = _lofi_material
		else:
			# Remove the shader to show unprocessed viewport
			viewport_container.material = null
	# Keep occlusion dither grid aligned with lo-fi pixelation
	_sync_lofi_pixelation()


## Create a default lo-fi material with sensible defaults
## Used as fallback if no material is defined in the scene
func _create_default_lofi_material() -> ShaderMaterial:
	var shader = load("res://shaders/lofi_canvas.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	# Apply shared defaults — prefer setting values in the scene's material
	for param_name in Constants.LOFI_DEFAULTS:
		material.set_shader_parameter(param_name, Constants.LOFI_DEFAULTS[param_name])
	return material


## Load occlusion fade setting from config
func _load_occlusion_fade_setting() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	var enabled = true
	if err == OK:
		enabled = config.get_value("graphics", "occlusion_fade_enabled", true)
	set_occlusion_fade_enabled(enabled)


## Enable or disable the occlusion fade effect
func set_occlusion_fade_enabled(enabled: bool) -> void:
	_occlusion_fade_enabled = enabled
	if not occlusion_fade:
		return
	if enabled:
		# Re-setup if a map is already loaded
		if map_container and map_container.get_child_count() > 0:
			occlusion_fade.setup(camera_node, map_container, drag_and_drop_node)
			_sync_lofi_pixelation()
	else:
		occlusion_fade.clear()


## Initialize the occlusion fade manager with node references.
## The mesh cache is rebuilt separately when a map loads (see notify_map_loaded).
func _setup_occlusion_fade() -> void:
	if occlusion_fade and _occlusion_fade_enabled:
		occlusion_fade.setup(camera_node, map_container, drag_and_drop_node)
		_sync_lofi_pixelation()


## Notify the occlusion fade manager that a new map has been loaded.
## Re-initializes and rebuilds the internal mesh cache so occlusion detection
## works with the new geometry.
func notify_map_loaded() -> void:
	if occlusion_fade and _occlusion_fade_enabled:
		occlusion_fade.setup(camera_node, map_container, drag_and_drop_node)
		_sync_lofi_pixelation()


## Clear occlusion fade state. Call before loading a new map.
## The manager will be re-activated when notify_map_loaded() is called.
func notify_map_clearing() -> void:
	if occlusion_fade:
		occlusion_fade.clear()


## Handle camera edge-panning when dragging a token near screen edges.
## Reads the edge_pan_direction from DragAndDrop3D and smoothly interpolates
## to provide a gentle ramp-up entering the zone and coast-out when leaving.
func _handle_edge_pan(delta: float) -> void:
	# Determine raw target pan direction (zero if not dragging)
	var target_pan = Vector2.ZERO
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		target_pan = drag_and_drop_node.edge_pan_direction

	# Smoothly interpolate toward the target pan direction
	var smooth_factor = 1.0 - exp(-EDGE_PAN_SMOOTH_SPEED * delta)
	_current_edge_pan = _current_edge_pan.lerp(target_pan, smooth_factor)

	# Only translate if pan is meaningful
	if _current_edge_pan.length_squared() < 0.0001:
		_current_edge_pan = Vector2.ZERO
		return

	# Convert screen-space pan direction to isometric camera movement
	# Same coordinate mapping as keyboard: up=(-1,-1), down=(+1,+1), left=(-1,+1), right=(+1,-1)
	var cam_move = Vector3.ZERO
	cam_move.x = _current_edge_pan.x + _current_edge_pan.y
	cam_move.z = -_current_edge_pan.x + _current_edge_pan.y

	var pan_speed = drag_and_drop_node.edge_pan_speed if drag_and_drop_node else 4.0
	cameraholder_node.translate(cam_move * pan_speed * delta)


## Override lo-fi shader parameters from map data
## Call this after loading a map to apply map-specific visual settings
## Parameters dict can contain any subset of shader parameter names
func apply_lofi_overrides(overrides: Dictionary) -> void:
	if not _lofi_material:
		_lofi_material = _create_default_lofi_material()

	for param_name in overrides:
		_lofi_material.set_shader_parameter(param_name, overrides[param_name])

	# If pixelation was among the overrides, sync it to the occlusion shader
	if "pixelation" in overrides:
		_sync_lofi_pixelation()


## Sync the lo-fi pixelation value to the occlusion fade manager so its dither
## grid aligns with the post-process pixelation. Pass 0 when lo-fi is off.
func _sync_lofi_pixelation() -> void:
	if not occlusion_fade:
		return
	var px := 0.0
	if viewport_container and viewport_container.material is ShaderMaterial:
		var mat := viewport_container.material as ShaderMaterial
		var val = mat.get_shader_parameter("pixelation")
		if val != null:
			px = float(val)
	occlusion_fade.set_lofi_pixelation(px)
