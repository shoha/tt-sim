class_name EventPuffs
extends MultiMeshInstance3D

## The soft shapes a terrain event throws up (a tree's dust as it lands, a plank's splash):
## a fixed pool of CAPACITY puffs (shaders/event_puff.gdshader) in one MultiMesh, so an event
## costs one draw and allocates nothing while it plays. Each emit takes the next slot,
## overwriting the oldest puff when every slot is busy; step() moves, sizes and fades each live
## puff (a quick swell in, a hold, a long fade out) and hides a spent one by scaling it to
## nothing. Three kinds, a few bold shapes rather than many small ones:
##
## - A blob (emit) faces the camera, its long axis along `axis` on screen (upright unless told
##   otherwise: along a trunk for a roll of dust). A drifting blob rises or spreads and slows,
##   growing from a third of its size (dust); a thrown one (gravity) is a body of water flying
##   apart instead, stretched along its flight, shrinking as it falls and fading as it goes
##   back under (a drop).
## - A plume (emit_plume) is a column of water standing on its point: it shoots up to its
##   height and falls back into a low mound as it fades, upright (the crown of a splash) or
##   leaning out (a tongue).
## - A ring (emit_ring) lies flat on the surface and spreads, thinning as it goes: the foam a
##   splash leaves on the water.
##
## The puffs draw after the water's transparent pass (RENDER_PRIORITY), which writes no depth,
## so a splash or its foam is never painted over by the river it lands in.

enum Kind { BLOB, PLUME, RING }

const CAPACITY := 96
const SHADER := preload("res://shaders/event_puff.gdshader")
## Drawn after the water (as SubmergedMarker's ring is).
const RENDER_PRIORITY := 2
## Fraction of its life a puff takes to swell in, and where its fade out starts.
const SWELL := 0.12
const FADE_FROM := 0.4
## How much of its size a thrown blob has lost when it ends.
const THROWN_SHRINK := 0.3
## Aspects (height over width): round, squat (dust, foam), tall (a tongue of spray).
const ROUND := 1.0
const SQUAT := 0.6
const TALL := 1.7
## The share of its life a plume takes to reach its height, and the share of the height it
## keeps as a mound once it has fallen back.
const PLUME_RISE := 0.35
const PLUME_MOUND := 0.15
## A ring's hole (its share of the ring's radius) as it starts and as it ends.
const RING_HOLE := Vector2(0.4, 0.78)

static var _material: ShaderMaterial = null

var _clock := 0.0
var _born := PackedFloat32Array()
var _life := PackedFloat32Array()
var _from := PackedVector3Array()
var _velocity := PackedVector3Array()
var _axis := PackedVector3Array()
var _size := PackedFloat32Array()
var _aspect := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _kind := PackedByteArray()
var _colors := PackedColorArray()
var _next := 0
var _live := 0


func _init() -> void:
	name = "EventPuffs"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = RENDER_PRIORITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	# Packed arrays are values: each is resized by name, not through a list of them.
	_born.resize(CAPACITY)
	_life.resize(CAPACITY)
	_size.resize(CAPACITY)
	_aspect.resize(CAPACITY)
	_gravity.resize(CAPACITY)
	_seed.resize(CAPACITY)
	_kind.resize(CAPACITY)
	_from.resize(CAPACITY)
	_velocity.resize(CAPACITY)
	_axis.resize(CAPACITY)
	_colors.resize(CAPACITY)
	_born.fill(-1.0)
	for slot in CAPACITY:
		multimesh.set_instance_transform(slot, _hidden())
	# The puffs move a few metres from where they start; the cull box follows them.
	extra_cull_margin = 4.0


## A blob at `at` (this node's frame) drifting at `velocity` (metres a second, slowing as it
## ages), `size` metres across when grown, living `life` seconds, in `color` (alpha its peak).
## With `gravity` (metres a second squared) it is thrown: it flies on its arc, stretched along
## it, and fades as it falls back below where it started (a drop going back into the water;
## dust leaves it 0 and hangs). `aspect` is its length over its width on screen (ROUND, SQUAT,
## TALL), its length along `axis` (world; zero: upright, or along its flight when thrown).
func emit(
	at: Vector3,
	velocity: Vector3,
	size: float,
	life: float,
	color: Color,
	gravity: float = 0.0,
	aspect: float = ROUND,
	axis: Vector3 = Vector3.ZERO
) -> void:
	_take(Kind.BLOB, at, velocity, axis, size, aspect, life, color, gravity)


## A plume standing on `at`: a column of water `size` metres wide shooting up to `height`
## metres along `axis` (upright, or leaning out for a tongue) and falling back over `life`
## seconds, in `color`.
func emit_plume(
	at: Vector3, size: float, height: float, life: float, color: Color, axis: Vector3 = Vector3.UP
) -> void:
	_take(Kind.PLUME, at, Vector3.ZERO, axis, size, height / maxf(size, 0.01), life, color, 0.0)


## A ring of foam lying on the surface at `at`, spreading to `size` metres across over `life`
## seconds, in `color`.
func emit_ring(at: Vector3, size: float, life: float, color: Color) -> void:
	_take(Kind.RING, at, Vector3.ZERO, Vector3.UP, size, RING_HOLE.x, life, color, 0.0)


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
		var keep := 1.0
		match _kind[slot]:
			Kind.PLUME:
				_place_plume(slot, k)
			Kind.RING:
				_place_ring(slot, k)
			_:
				keep = _place_blob(slot, age, k)
		var color := _colors[slot]
		color.a *= fade(k) * keep
		multimesh.set_instance_color(slot, color)


## True when no puff is alive.
func is_idle() -> bool:
	return _live == 0


## A puff's alpha `k` of the way through its life, 0 to 1: a quick swell in, a hold, a long
## fade out. Pure.
static func fade(k: float) -> float:
	if k < SWELL:
		return k / SWELL
	return 1.0 - smoothstep(FADE_FROM, 1.0, k)


## A plume's height, as a share of its full height, `k` of the way through its life: it
## shoots up over PLUME_RISE (easing out), then falls back under its own weight (easing in) to
## a mound of PLUME_MOUND. Pure.
static func plume_rise(k: float) -> float:
	if k < PLUME_RISE:
		var up := k / PLUME_RISE
		return 1.0 - (1.0 - up) * (1.0 - up)
	var down := (k - PLUME_RISE) / (1.0 - PLUME_RISE)
	return 1.0 - (1.0 - PLUME_MOUND) * minf(down * down, 1.0)


func _take(
	kind: Kind,
	at: Vector3,
	velocity: Vector3,
	axis: Vector3,
	size: float,
	aspect: float,
	life: float,
	color: Color,
	gravity: float
) -> void:
	var slot := _next
	_next = (_next + 1) % CAPACITY
	if _born[slot] < 0.0:
		_live += 1
	_born[slot] = _clock
	_life[slot] = maxf(life, 0.05)
	_kind[slot] = kind
	_from[slot] = at
	_velocity[slot] = velocity
	_axis[slot] = axis
	_size[slot] = size
	_aspect[slot] = maxf(aspect, 0.2)
	_gravity[slot] = gravity
	_colors[slot] = color
	_seed[slot] = fmod(_clock * 7.31 + slot * 0.618, 1.0)
	_shape(slot, _aspect[slot])


## Hands puff `slot`'s seed, `shape` (a blob's or plume's length over its width, a ring's
## hole), kind and boldness to the shader (INSTANCE_CUSTOM). Water (a plume, a ring, a thrown
## drop) draws bolder than drifting dust.
func _shape(slot: int, shape: float) -> void:
	var kind := _kind[slot]
	var bold := 0.0 if kind == Kind.BLOB and _gravity[slot] <= 0.0 else 1.0
	multimesh.set_instance_custom_data(slot, Color(_seed[slot], shape, kind, bold))


## Moves blob `slot` `age` seconds (`k` of its life) in; returns its alpha's share (a thrown
## drop fades out as it goes back under).
func _place_blob(slot: int, age: float, k: float) -> float:
	var from := _from[slot]
	var gravity := _gravity[slot]
	var axis := _axis[slot]
	var keep := 1.0
	var at: Vector3
	var size: float
	if gravity > 0.0:
		var velocity := _velocity[slot]
		at = from + velocity * age
		at.y -= 0.5 * gravity * age * age
		if axis == Vector3.ZERO:
			axis = velocity + Vector3(0.0, -gravity * age, 0.0)
		size = _size[slot] * (1.0 - THROWN_SHRINK * k)
		# Under by its own size and it is gone.
		var under := from.y - at.y
		if under > 0.0:
			keep = clampf(1.0 - under / maxf(size, 0.05), 0.0, 1.0)
			at.y = maxf(at.y, from.y - size)
	else:
		# Drifts as far as its velocity takes it in half its life, slowing all the way.
		at = from + _velocity[slot] * age * (1.0 - 0.5 * k)
		var grown := 1.0 - pow(1.0 - k, 3.0)
		size = _size[slot] * (0.35 + 0.65 * grown)
	multimesh.set_instance_transform(slot, Transform3D(basis_along(axis, size), at))
	return keep


## A plume `k` of its life in: standing on its point, its height rising and falling back while
## it spreads a little.
func _place_plume(slot: int, k: float) -> void:
	var width := _size[slot] * (0.85 + 0.35 * k)
	var height := _size[slot] * _aspect[slot] * plume_rise(k)
	multimesh.set_instance_transform(
		slot, Transform3D(basis_along(_axis[slot], width), _from[slot])
	)
	_shape(slot, height / width)


## A ring `k` of its life in: spreading fast then slowing, its band thinning as it goes.
func _place_ring(slot: int, k: float) -> void:
	var spread := 1.0 - (1.0 - k) * (1.0 - k)
	var size := _size[slot] * (0.3 + 0.7 * spread)
	multimesh.set_instance_transform(
		slot, Transform3D(Basis.from_scale(Vector3.ONE * size), _from[slot])
	)
	_shape(slot, lerpf(RING_HOLE.x, RING_HOLE.y, k))


## A basis `size` metres across whose Y axis lies along `axis` (upright when it is zero): the
## shader stretches a puff along that axis's direction on screen. Pure.
static func basis_along(axis: Vector3, size: float) -> Basis:
	var y := axis.normalized() if axis.length_squared() > 1e-8 else Vector3.UP
	var helper := Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	return Basis(x * size, y * size, x.cross(y) * size)


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
