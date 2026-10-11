class_name SmokePuffs
extends MultiMeshInstance3D

## A fire's smoke (FireSweep): a fixed pool of billows in one MultiMesh, so a fire's smoke is
## one draw and allocates nothing while it plays. Each emit takes the next slot (overwriting
## the oldest when every slot is busy); step() moves, turns and sizes each live billow and hands
## its age to the shader. A spent billow is hidden by scaling it to nothing.
##
## A billow is a smoke crown, made the way a tree's crown is: one mesh of CARDS small puff cards
## (crown_mesh, built once and shared by every billow), each turned to face the camera in the
## shader (shaders/fire_smoke.gdshader), its painted puff cut out with a crisp edge, lit by the
## crown's volume normal through a two-tone step. Opaque all its life, it thins by erosion: the
## fire's one noise eats whole cards and the edges of the rest, so an old billow breaks into a
## few puffs and is gone by about 0.8 of its life. A pool of n billows draws n * CARDS cards
## (FireSweep's 50: 2200 cards at most), one instance and one transform a billow on the CPU.

const SHADER := preload("res://shaders/fire_smoke.gdshader")
## A billow's size as it rises (a share of its full size), and how much more it has spread by
## its end (the shader opens its cards a little more as it ages).
const START := 0.8
const SPREAD := 0.7
## Puff cards in one crown, the crown's half-extents in its own unit (a billow `size` metres
## across fills about one unit), and a card's half-size at the middle and at the rim.
const CARDS := 44
const CROWN := Vector3(0.38, 0.28, 0.38)
const CARD_HALF := Vector2(0.16, 0.09)
## The crown's draws are fixed, so every pool shares one mesh.
const CROWN_SEED := 1979

## One material and one mesh for every pool.
static var _material: ShaderMaterial = null
static var _crown: ArrayMesh = null

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
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = crown_mesh()
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


## The shared smoke crown: CARDS quads, each vertex at its card's centre (the shader spreads the
## corners out to face the camera), UV the corner, UV2 the card's half-size and its rank (the
## order erosion takes the cards in), COLOR.r a draw for its painted puff. The cards fill a low
## dome, large in the middle and small at the rim, so its outline breaks as a crown's does.
static func crown_mesh() -> ArrayMesh:
	if _crown != null:
		return _crown
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWN_SEED
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for card in CARDS:
		var at := _crown_point(rng)
		var out := clampf(Vector3(at.x / CROWN.x, at.y / CROWN.y, at.z / CROWN.z).length(), 0, 1)
		var half := lerpf(CARD_HALF.x, CARD_HALF.y, out) * rng.randf_range(0.85, 1.15)
		var rank := clampf(0.6 * rng.randf() + 0.4 * out, 0.0, 1.0)
		var draw := rng.randf()
		var first := vertices.size()
		for corner in corners:
			vertices.append(at)
			uvs.append(corner)
			uv2s.append(Vector2(half, rank))
			colors.append(Color(draw, 0.0, 0.0, 1.0))
		indices.append_array(
			PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3])
		)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_crown = ArrayMesh.new()
	_crown.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_crown.surface_set_material(0, _material)
	# The corners reach past the centres: the box takes them in.
	_crown.custom_aabb = AABB(-CROWN * 2.0, CROWN * 4.0)
	return _crown


## A card's centre in the crown's dome: inside the half-ellipsoid CROWN, its foot flattened.
static func _crown_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 32:
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if p.length_squared() > 1.0:
			continue
		if p.y < -0.35:
			p.y = -0.35 + (p.y + 0.35) * 0.3
		return p * CROWN
	return Vector3.ZERO


## A billow at `at` (this node's frame) drifting at `velocity` (metres a second, slowing as it
## ages), `size` metres across when grown, living `life` seconds. The palette is the shader's;
## `color` scales the cards' draws (COLOR.r), so pass white.
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


## Billow `slot` `age` seconds (`k` of its life) in: drifting, slowing, turned by its seed,
## grown and spreading, its age handed to the shader.
func _place(slot: int, age: float, k: float) -> void:
	var at := _from[slot] + _velocity[slot] * age * (1.0 - 0.5 * k)
	var size := _size[slot] * billow_size(k)
	var turn := Basis(Vector3.UP, _seed[slot] * TAU).scaled(Vector3.ONE * size)
	multimesh.set_instance_transform(slot, Transform3D(turn, at))
	multimesh.set_instance_custom_data(slot, Color(_seed[slot], 0.0, k, 0.0))


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
