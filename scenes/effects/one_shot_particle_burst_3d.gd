class_name OneShotParticleBurst3D
extends GPUParticles3D

## Shared one-shot particle burst lifecycle (emitter setup, auto-free after finishing).
## Subclasses supply their own particle count/lifetime/material/mesh by overriding the
## four methods below -- see DustBurst, SparkleBurst, SplashBurst.
##
## Usage (from a subclass):
##   static func create_at(pos: Vector3) -> MyBurst:
##       var burst := MyBurst.new()
##       burst._spawn_position = pos
##       return burst

var _spawn_position := Vector3.ZERO


func _ready() -> void:
	global_position = _spawn_position
	emitting = false
	one_shot = true
	explosiveness = 1.0
	amount = _get_particle_count()
	lifetime = _get_lifetime()
	fixed_fps = 0
	interpolate = true

	process_material = _build_process_material()
	draw_pass_1 = _build_mesh()

	finished.connect(queue_free)

	# Start emitting on next frame to ensure transforms are applied
	_start_emitting.call_deferred()


func _get_particle_count() -> int:
	return 8


func _get_lifetime() -> float:
	return 0.4


func _build_process_material() -> ParticleProcessMaterial:
	return ParticleProcessMaterial.new()


func _build_mesh() -> Mesh:
	return SphereMesh.new()


func _start_emitting() -> void:
	emitting = true
