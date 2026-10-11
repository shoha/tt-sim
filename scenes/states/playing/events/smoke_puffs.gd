class_name SmokePuffs
extends MultiMeshInstance3D

## A fire's smoke (FireSweep): a fixed pool of billows (shaders/fire_smoke.gdshader) in one
## MultiMesh, so a fire's smoke is one draw and allocates nothing while it plays. Each emit takes
## the next slot (overwriting the oldest when every slot is busy); step() moves and sizes each
## live billow and hands its age to the shader, which draws it as a heap of lit balls (the
## crowns' soft two-tone read, solid, with their own depth) and erodes it as it ages: opaque all
## its life, so it thins by breaking up, never by going see-through. A spent billow is hidden
## by scaling it to nothing.

const SHADER := preload("res://shaders/fire_smoke.gdshader")
## A billow's size as it rises (a share of its full size), and how much more it has spread by
## its end.
const START := 0.5
const SPREAD := 0.25

## One material for every pool.
static var _material: ShaderMaterial = null

## The pool's size, fixed when it is made.
var capacity: int = 1
var _clock := 0.0
var _born := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _from := PackedVector3Array()
var _velocity := PackedVector3Array()
var _next := 0
var _live := 0


## A pool of `pool_size` billows.
func _init(pool_size: int = 32) -> void:
	name = "SmokePuffs"
	capacity = maxi(pool_size, 1)
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
	multimesh.instance_count = capacity
	_born.resize(capacity)
	_life.resize(capacity)
	_size.resize(capacity)
	_seed.resize(capacity)
	_from.resize(capacity)
	_velocity.resize(capacity)
	_born.fill(-1.0)
	for slot in capacity:
		multimesh.set_instance_transform(slot, _hidden())
	# Billows rise a few metres from where they start; the cull box follows them.
	extra_cull_margin = 6.0


## A billow at `at` (this node's frame) drifting at `velocity` (metres a second, slowing as it
## ages), `size` metres across when grown, living `life` seconds, tinted `color` (white: the
## shader's own palette).
func emit(at: Vector3, velocity: Vector3, size: float, life: float, color: Color) -> void:
	var slot := _next
	_next = (_next + 1) % capacity
	if _born[slot] < 0.0:
		_live += 1
	_born[slot] = _clock
	_life[slot] = maxf(life, 0.05)
	_size[slot] = size
	_from[slot] = at
	_velocity[slot] = velocity
	_seed[slot] = fmod(_clock * 7.31 + slot * 0.618, 1.0)
	multimesh.set_instance_color(slot, color)
	_place(slot, 0.0, 0.0)


## Advances every live billow `delta` seconds.
func step(delta: float) -> void:
	_clock += delta
	if _live == 0:
		return
	for slot in capacity:
		if _born[slot] < 0.0:
			continue
		var age := _clock - _born[slot]
		var k := age / _life[slot]
		if k >= 1.0:
			_born[slot] = -1.0
			_live -= 1
			multimesh.set_instance_transform(slot, _hidden())
			continue
		_place(slot, age, k)


## True when no billow is alive.
func is_idle() -> bool:
	return _live == 0


## How many billows are alive.
func live_count() -> int:
	return _live


## A billow's size, as a share of its full size, `k` of the way through its life: grown from
## START (easing out) and still spreading by SPREAD to its end. Pure.
static func billow_size(k: float) -> float:
	var grown := 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)
	return (START + (1.0 - START) * grown) * (1.0 + SPREAD * k)


## Billow `slot` `age` seconds (`k` of its life) in: drifting, slowing, grown and spreading, its
## age handed to the shader.
func _place(slot: int, age: float, k: float) -> void:
	var at := _from[slot] + _velocity[slot] * age * (1.0 - 0.5 * k)
	var size := _size[slot] * billow_size(k)
	multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
	multimesh.set_instance_custom_data(slot, Color(_seed[slot], 0.0, k, 0.0))


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
