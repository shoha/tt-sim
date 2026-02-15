extends GPUParticles3D
class_name SparkleBurst

## One-shot sparkle particle burst for "model ready" feedback.
##
## Usage:
##   var sparkle = SparkleBurst.create_at(world_position)
##   some_3d_parent.add_child(sparkle)
##
## The node auto-frees after the particles finish.

const PARTICLE_COUNT := 6
const LIFETIME := 0.5

var _spawn_position := Vector3.ZERO


static func create_at(pos: Vector3) -> SparkleBurst:
	var sparkle := SparkleBurst.new()
	sparkle._spawn_position = pos
	return sparkle


func _ready() -> void:
	global_position = _spawn_position
	emitting = false
	one_shot = true
	explosiveness = 1.0
	amount = PARTICLE_COUNT
	lifetime = LIFETIME
	fixed_fps = 0
	interpolate = true

	# Build process material
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0  # Full sphere
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -1.0, 0)  # Slight downward pull
	mat.damping_min = 3.0
	mat.damping_max = 5.0
	# Scale: small sparkle points
	mat.scale_min = 0.02
	mat.scale_max = 0.05
	# Fade out over lifetime
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.5, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve
	# Bright warm sparkle color
	mat.color = Color(1.0, 0.9, 0.5, 0.9)
	# Emissive glow for sparkle effect
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2

	process_material = mat

	# Use a simple sphere mesh for sparkle particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2

	# Make particles glow with emissive material
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.9, 0.5)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.85, 0.4)
	spark_mat.emission_energy_multiplier = 2.0
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = spark_mat

	draw_pass_1 = mesh

	# Auto-free when done
	finished.connect(queue_free)

	# Start emitting on next frame to ensure transforms are applied
	_start_emitting.call_deferred()


func _start_emitting() -> void:
	emitting = true
