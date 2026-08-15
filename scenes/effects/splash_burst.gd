class_name SplashBurst
extends OneShotParticleBurst3D

## One-shot splash particle burst for a token crossing into/out of a `-water` mesh's
## WaterZone. is_entry scales intensity: bigger upward-then-falling droplets on entry,
## a smaller/quieter burst on exit.
##
## Usage:
##   var splash = SplashBurst.create_at(world_position, true)  # true = entry
##   some_3d_parent.add_child(splash)
##
## The node auto-frees after the particles finish.

const ENTRY_PARTICLE_COUNT := 10
const EXIT_PARTICLE_COUNT := 5
const ENTRY_LIFETIME := 0.5
const EXIT_LIFETIME := 0.35
const ENTRY_VELOCITY_MIN := 1.2
const ENTRY_VELOCITY_MAX := 2.2
const EXIT_VELOCITY_MIN := 0.4
const EXIT_VELOCITY_MAX := 0.9

var _is_entry := true


static func create_at(pos: Vector3, is_entry: bool) -> SplashBurst:
	var splash := SplashBurst.new()
	splash._spawn_position = pos
	splash._is_entry = is_entry
	return splash


func _get_particle_count() -> int:
	return ENTRY_PARTICLE_COUNT if _is_entry else EXIT_PARTICLE_COUNT


func _get_lifetime() -> float:
	return ENTRY_LIFETIME if _is_entry else EXIT_LIFETIME


func _build_process_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.flatness = 0.4 if _is_entry else 0.8
	if _is_entry:
		mat.initial_velocity_min = ENTRY_VELOCITY_MIN
		mat.initial_velocity_max = ENTRY_VELOCITY_MAX
		mat.gravity = Vector3(0, -2.5, 0)  # droplets fling up then fall back
	else:
		mat.initial_velocity_min = EXIT_VELOCITY_MIN
		mat.initial_velocity_max = EXIT_VELOCITY_MAX
		mat.gravity = Vector3(0, -1.0, 0)  # gentle drip
	mat.damping_min = 1.5
	mat.damping_max = 2.5
	mat.scale_min = 0.03
	mat.scale_max = 0.07
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.9))
	curve.add_point(Vector2(0.4, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve
	mat.color = Color(0.75, 0.88, 0.95, 0.75)
	return mat


func _build_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2
	return mesh
