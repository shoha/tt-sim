class_name PainterStateReset
extends RefCounted

## Puts the painter's process-wide state back to Classic for a test that assumes it (card
## painter-default-flip). Painted is the default look, so any earlier script in a shard that
## applies a level environment without clearing it leaves the two shared water materials on the
## painter's shaders and a painted ground in FireLook.glow_mirrors; which scripts ran before
## depends on the shard count (CI runs 2 shards, the local gate 8). A test that reads that state
## calls classic() in before_each instead of relying on the order.

const CLASSIC_WATER := "res://shaders/water.gdshader"
const CLASSIC_FALL := "res://shaders/waterfall.gdshader"


## The shared water and fall materials on Classic's shaders with none of the painter's marks, and
## no painted ground mirroring the fire bake.
static func classic() -> void:
	_restore(WaterGlbUtils.water_material(), load(CLASSIC_WATER) as Shader)
	_restore(AuthoredWater.fall_material(), load(CLASSIC_FALL) as Shader)
	FireLook.glow_mirrors.clear()


static func _restore(material: ShaderMaterial, classic_shader: Shader) -> void:
	material.shader = classic_shader
	material.remove_meta(PainterWater.META)
	for uniform in PainterWater.tone_uniforms():
		material.set_shader_parameter(uniform, null)
