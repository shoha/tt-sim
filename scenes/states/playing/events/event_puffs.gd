class_name EventPuffs
extends MultiMeshInstance3D

## The soft shapes a terrain event throws up (a tree's dust as it lands, a plank's splash):
## a fixed pool of CAPACITY camera-facing puffs (shaders/event_puff.gdshader) in one
## MultiMesh, so an event costs one draw and allocates nothing while it plays. emit() takes the
## next slot, overwriting the oldest puff when every slot is busy; step() moves each live puff
## (it rises or spreads and slows), grows it (an ease-out from a third of its size) and fades
## it (a quick swell in, a long fade out), and hides a spent one by scaling it to nothing.

const CAPACITY := 96
const SHADER := preload("res://shaders/event_puff.gdshader")
## Fraction of its life a puff takes to swell in.
const SWELL := 0.12

static var _material: ShaderMaterial = null

var _clock := 0.0
var _born := PackedFloat32Array()
var _life := PackedFloat32Array()
var _from := PackedVector3Array()
var _velocity := PackedVector3Array()
var _size := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _colors := PackedColorArray()
var _next := 0
var _live := 0


func _init() -> void:
	name = "EventPuffs"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	_born.resize(CAPACITY)
	_life.resize(CAPACITY)
	_size.resize(CAPACITY)
	_gravity.resize(CAPACITY)
	_from.resize(CAPACITY)
	_velocity.resize(CAPACITY)
	_colors.resize(CAPACITY)
	_born.fill(-1.0)
	for slot in CAPACITY:
		multimesh.set_instance_transform(slot, _hidden())
	# The puffs move a few metres from where they start; the cull box follows them.
	extra_cull_margin = 4.0


## A puff at `at` (this node's frame) drifting at `velocity` (metres a second, slowing as it
## ages), `size` metres across when grown, living `life` seconds, in `color` (alpha its peak).
## With `gravity` (metres a second squared) it is thrown: it rises, falls back and never goes
## below where it started (spray falling back to the water; dust leaves it 0 and hangs).
func emit(
	at: Vector3, velocity: Vector3, size: float, life: float, color: Color, gravity: float = 0.0
) -> void:
	var slot := _next
	_gravity[slot] = gravity
	_next = (_next + 1) % CAPACITY
	if _born[slot] < 0.0:
		_live += 1
	_born[slot] = _clock
	_life[slot] = maxf(life, 0.05)
	_from[slot] = at
	_velocity[slot] = velocity
	_size[slot] = size
	_colors[slot] = color
	multimesh.set_instance_custom_data(slot, Color(fmod(_clock * 7.31 + slot * 0.618, 1.0), 0, 0, 0))


## Advances every live puff `delta` seconds.
func step(delta: float) -> void:
	_clock += delta
	if _live == 0:
		return
	for slot in CAPACITY:
		if _born[slot] < 0.0:
			continue
		var age := _clock - _born[slot]
		var k := age / _life[slot]
		if k >= 1.0:
			_born[slot] = -1.0
			_live -= 1
			multimesh.set_instance_transform(slot, _hidden())
			continue
		# Drifts as far as its velocity takes it in half its life, slowing all the way.
		var travel := age * (1.0 - 0.5 * k)
		var at := _from[slot] + _velocity[slot] * travel
		if _gravity[slot] > 0.0:
			at = _from[slot] + _velocity[slot] * age
			at.y = maxf(at.y - 0.5 * _gravity[slot] * age * age, _from[slot].y)
		var grown := 1.0 - pow(1.0 - k, 3.0)
		var size := _size[slot] * (0.35 + 0.65 * grown)
		var alpha := k / SWELL if k < SWELL else 1.0 - smoothstep(0.35, 1.0, k)
		var color := _colors[slot]
		color.a *= alpha
		multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		multimesh.set_instance_color(slot, color)


## True when no puff is alive.
func is_idle() -> bool:
	return _live == 0


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
