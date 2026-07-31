class_name DustBurst
extends GPUParticles3D

## One-shot dust particle burst for token drop impact.
##
## Usage:
##   var dust = DustBurst.create_at(world_position)
##   some_3d_parent.add_child(dust)
##
## The node auto-frees after the particles finish.

const PARTICLE_COUNT := 8
const LIFETIME := 0.4
const SPREAD_RADIUS := 0.3  # XZ spread
const RISE_SPEED := 0.2  # Slight upward drift

var _spawn_position := Vector3.ZERO


static func create_at(pos: Vector3) -> DustBurst:
	var dust := DustBurst.new()
	dust._spawn_position = pos
	return dust


func _ready() -> void:
	global_position = _spawn_position
	emitting = false
	one_shot = true
	explosiveness = 1.0
	amount = PARTICLE_COUNT
	lifetime = LIFETIME
	# No fixed velocity — controlled by process material
	fixed_fps = 0
	interpolate = true

	# Build process material
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0  # Full ring
	mat.flatness = 1.0  # Flat ring on XZ plane
	mat.initial_velocity_min = SPREAD_RADIUS / LIFETIME
	mat.initial_velocity_max = SPREAD_RADIUS / LIFETIME * 1.5
	mat.gravity = Vector3(0, RISE_SPEED, 0)
	mat.damping_min = 2.0
	mat.damping_max = 3.0
	# Scale: start small, grow slightly
	mat.scale_min = 0.03
	mat.scale_max = 0.06
	# Fade out over lifetime
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(0.3, 0.5))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve
	# Warm grey-brown color
	mat.color = Color(0.55, 0.50, 0.42, 0.6)

	process_material = mat

	# Use a simple sphere mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2
	draw_pass_1 = mesh

	# Auto-free when done
	finished.connect(queue_free)

	# Start emitting on next frame to ensure transforms are applied
	_start_emitting.call_deferred()


func _start_emitting() -> void:
	emitting = true
