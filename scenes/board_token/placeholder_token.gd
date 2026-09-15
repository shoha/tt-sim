class_name PlaceholderToken
extends Node3D

## A simple placeholder shown while a token's model is being downloaded.
## Displays a pulsing/spinning cube that indicates loading state.

const PULSE_QUANTIZE_STEPS: float = 64.0  # write granularity; avoids material churn every frame

@export var spin_speed: float = 2.0
@export var pulse_speed: float = 1.5
@export var base_color: Color = Color(0.4, 0.6, 0.9, 0.8)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _time: float = 0.0
var _last_written_pulse: float = -1.0  # quantized value last written; -1.0 never matches


func _ready() -> void:
	_create_placeholder_mesh()


func _create_placeholder_mesh() -> void:
	# Create a simple box mesh
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PlaceholderMesh"

	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.8, 0.5)
	_mesh_instance.mesh = box_mesh

	# Create a semi-transparent pulsing material with emissive glow
	_material = StandardMaterial3D.new()
	_material.albedo_color = base_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Emissive pulse: same color as base, pulsed via energy multiplier in _process
	_material.emission_enabled = true
	_material.emission = Color(base_color.r, base_color.g, base_color.b)
	_material.emission_energy_multiplier = 0.0
	_mesh_instance.material_override = _material

	# Position the mesh so it sits on the ground
	_mesh_instance.position.y = 0.4

	add_child(_mesh_instance)


func _process(delta: float) -> void:
	_time += delta

	# Spin the mesh
	if _mesh_instance:
		_mesh_instance.rotation.y += spin_speed * delta

	# Pulse the alpha and emissive energy, but only write the material when the
	# quantized pulse value actually changed -- skips two StandardMaterial3D property
	# writes per frame while the value would round to the same step anyway.
	if _material:
		var pulse: float = (sin(_time * pulse_speed * TAU) + 1.0) * 0.5
		var quantized_pulse: float = roundf(pulse * PULSE_QUANTIZE_STEPS) / PULSE_QUANTIZE_STEPS
		if not is_equal_approx(quantized_pulse, _last_written_pulse):
			_last_written_pulse = quantized_pulse
			var alpha: float = lerp(0.4, 0.9, quantized_pulse)
			_material.albedo_color.a = alpha
			# Emissive shimmer: oscillates 0.0 → 0.3 alongside the alpha pulse
			_material.emission_energy_multiplier = quantized_pulse * 0.3


## Set the color of the placeholder
func set_placeholder_color(color: Color) -> void:
	base_color = color
	if _material:
		_material.albedo_color = color


## Create a collision shape for the placeholder (for click detection)
func create_collision() -> CollisionShape3D:
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"

	var shape = BoxShape3D.new()
	shape.size = Vector3(0.5, 0.8, 0.5)
	collision.shape = shape
	collision.position.y = 0.4

	return collision
