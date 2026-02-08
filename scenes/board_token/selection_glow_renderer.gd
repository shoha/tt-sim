extends Node3D
class_name SelectionGlowRenderer

## Renders a glow effect behind selected/hovered tokens.
##
## This is a pure visual component attached to a token's RigidBody3D.
## The glow is rendered as a flat disc (QuadMesh) positioned at the token's base,
## using a custom shader (selection_glow.gdshader) for a soft radial falloff effect.
##
## LIFECYCLE:
## Created by BoardTokenFactory and attached to each token's RigidBody3D.
## The glow is hidden by default and shown/hidden via show_glow()/hide_glow().
##
## INTEGRATION:
## BoardToken has is_highlighted property and set_highlighted() method that
## controls this renderer. BoardTokenController triggers highlight on mouse hover.
##
## CUSTOMIZATION:
## - Size automatically calculated from token's collision bounds
## - Color can be changed via set_glow_color()
## - Pulse animation controlled by shader parameters
##
## EXAMPLE USAGE:
##   # Via BoardToken (preferred):
##   token.set_highlighted(true)
##   token.set_highlight_color(Color.CYAN)
##
##   # Direct access:
##   token.get_selection_glow().show_glow()
##   token.get_selection_glow().set_glow_color(Color.RED)

const GLOW_SHADER = preload("res://shaders/selection_glow.gdshader")

## Default glow color (golden yellow, reduced intensity for a subtler hover)
const DEFAULT_GLOW_COLOR = Color(1.0, 0.8, 0.2, 0.6)

## Size multiplier for the glow relative to the token
@export var size_multiplier: float = 1.2

## Maximum glow size in world units (caps the indicator for large tokens)
@export var max_size: float = 1.6

## Vertical offset from token base (slightly above ground to prevent z-fighting)
@export var ground_offset: float = 0.02

## Duration of the fade in/out animation
const FADE_DURATION: float = 0.12

var _glow_mesh_instance: MeshInstance3D
var _glow_material: ShaderMaterial
var _base_size: float = 1.0
var _fade_tween: Tween


func _ready() -> void:
	_create_glow_mesh()
	hide_glow(true)


func _create_glow_mesh() -> void:
	# Create shader material
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	_glow_material.set_shader_parameter("glow_color", DEFAULT_GLOW_COLOR)
	_glow_material.set_shader_parameter("falloff", 2.5)
	_glow_material.set_shader_parameter("pulse_speed", 1.5)
	_glow_material.set_shader_parameter("pulse_amount", 0.15)
	
	# Create a flat quad mesh oriented horizontally (XZ plane)
	var quad = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)  # Will be scaled based on token size
	quad.orientation = PlaneMesh.FACE_Y  # Face upward
	
	# Create mesh instance
	_glow_mesh_instance = MeshInstance3D.new()
	_glow_mesh_instance.mesh = quad
	_glow_mesh_instance.material_override = _glow_material
	_glow_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(_glow_mesh_instance)


## Update the glow size based on the token's collision bounds
## Call this after the token is fully set up or when scale changes
func update_size_from_collision(collision_shape: CollisionShape3D) -> void:
	if not collision_shape or not collision_shape.shape:
		return
	
	# Get the AABB of the collision shape to determine token footprint
	var aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()
	
	# Use the larger of X or Z extent for the glow radius
	var max_horizontal_extent = max(aabb.size.x, aabb.size.z)
	_base_size = clampf(max_horizontal_extent * size_multiplier, 0.0, max_size)

	# Position at the bottom of the collision shape
	var bottom_y = aabb.position.y + ground_offset
	_glow_mesh_instance.position = Vector3(0, bottom_y, 0)
	
	# Scale the quad to match
	_glow_mesh_instance.scale = Vector3(_base_size, 1.0, _base_size)


## Update glow size when token scale changes
func update_scale(token_scale: Vector3) -> void:
	if _glow_mesh_instance:
		# Account for non-uniform scaling by using the average horizontal scale
		var horizontal_scale = (token_scale.x + token_scale.z) / 2.0
		var effective_size = clampf(_base_size * horizontal_scale, 0.0, max_size)
		_glow_mesh_instance.scale = Vector3(effective_size, 1.0, effective_size)


## Show the selection glow with a smooth fade-in
func show_glow() -> void:
	if not _glow_mesh_instance or not _glow_material:
		return

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_glow_mesh_instance.show()
	var target_color: Color = DEFAULT_GLOW_COLOR
	var current_color: Color = _glow_material.get_shader_parameter("glow_color")
	current_color.a = 0.0
	_glow_material.set_shader_parameter("glow_color", current_color)

	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_glow_alpha, 0.0, target_color.a, FADE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Hide the selection glow with a smooth fade-out
## Set immediate to true to skip the animation (e.g. during initialization)
func hide_glow(immediate: bool = false) -> void:
	if not _glow_mesh_instance or not _glow_material:
		return

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	if immediate:
		_set_glow_alpha(0.0)
		_glow_mesh_instance.hide()
		return

	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_glow_alpha, _get_glow_alpha(), 0.0, FADE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_glow_mesh_instance.hide)


## Check if the glow is currently shown
func is_glow_visible() -> bool:
	return _glow_mesh_instance and _glow_mesh_instance.visible


## Set the glow alpha (used by fade tweens)
func _set_glow_alpha(alpha: float) -> void:
	if _glow_material:
		var color: Color = _glow_material.get_shader_parameter("glow_color")
		color.a = alpha
		_glow_material.set_shader_parameter("glow_color", color)


## Get the current glow alpha
func _get_glow_alpha() -> float:
	if _glow_material:
		var color: Color = _glow_material.get_shader_parameter("glow_color")
		return color.a
	return 0.0


## Set the glow color
func set_glow_color(color: Color) -> void:
	if _glow_material:
		_glow_material.set_shader_parameter("glow_color", color)


## Set the pulse animation speed (0 to disable pulsing)
func set_pulse_speed(speed: float) -> void:
	if _glow_material:
		_glow_material.set_shader_parameter("pulse_speed", speed)


## Set the falloff sharpness (higher = tighter glow)
func set_falloff(falloff: float) -> void:
	if _glow_material:
		_glow_material.set_shader_parameter("falloff", falloff)
