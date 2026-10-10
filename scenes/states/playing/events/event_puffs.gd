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
## And three for fire (FireSweep):
##
## - A flame (emit_flame) stands on its base: the painted flame (FlameAtlas, set on the pool
##   by paint_flames), three tongues in a red rim, an amber body and a pale gold core, licking
##   on the shader's clock, swelling in fast and narrowing as it rises and dies.
## - An ember (emit_ember) is a small glowing spark drifting up and weaving as it goes.
## - A billow of smoke (emit_smoke) drifts and swells as dust does, a firm body with big soft
##   lobes, its underside lit warm by the fire below it.
##
## Fire's kinds hold their full alpha longer than the others (fire_fade), so a flame burns
## rather than flickers out.
##
## The puffs draw after the water's transparent pass (RENDER_PRIORITY), which writes no depth,
## so a splash or its foam is never painted over by the river it lands in. A pool made with a
## higher priority draws after one with a lower (a fire's flames over its smoke), and with a
## larger capacity holds one event's every puff at once.

enum Kind { BLOB, PLUME, RING, FLAME, EMBER, SMOKE }

const CAPACITY := 96
const SHADER := preload("res://shaders/event_puff.gdshader")
## Drawn after the water (as SubmergedMarker's ring is).
const RENDER_PRIORITY := 2
## How much of its width a flame has lost by the end of its life, and how far an ember weaves
## (metres) and how fast (radians a second).
const FLAME_NARROW := 0.55
const EMBER_WEAVE := 0.35
const EMBER_WEAVE_RATE := 3.2
## Where a fire puff's fade out starts (fire_fade).
const FIRE_FADE_FROM := 0.65
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

## One material per render priority, shared by every pool of that priority.
static var _materials: Dictionary = {}

## The pool's size, fixed when it is made.
var capacity: int = CAPACITY
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


## A pool of `pool_size` puffs drawn at render priority `priority` (see the header).
func _init(pool_size: int = CAPACITY, priority: int = RENDER_PRIORITY) -> void:
	name = "EventPuffs"
	capacity = maxi(pool_size, 1)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _materials.has(priority):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.render_priority = priority
		_materials[priority] = material
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _materials[priority]
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = capacity
	# Packed arrays are values: each is resized by name, not through a list of them.
	_born.resize(capacity)
	_life.resize(capacity)
	_size.resize(capacity)
	_aspect.resize(capacity)
	_gravity.resize(capacity)
	_seed.resize(capacity)
	_kind.resize(capacity)
	_from.resize(capacity)
	_velocity.resize(capacity)
	_axis.resize(capacity)
	_colors.resize(capacity)
	_born.fill(-1.0)
	for slot in capacity:
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


## A flame standing on `at`, `size` metres wide and `height` tall at its fullest, rising at
## `velocity` and narrowing as it dies over `life` seconds; `color` is its rim's colour (its
## body burns amber and its core pale gold whatever it is), alpha its peak. Linear colour, as
## every puff's is: a rim meant to show as deep red is far darker than it shows.
func emit_flame(
	at: Vector3, velocity: Vector3, size: float, height: float, life: float, color: Color
) -> void:
	_take(Kind.FLAME, at, velocity, Vector3.UP, size, height / maxf(size, 0.01), life, color, 0.0)


## A spark at `at` drifting at `velocity` (it weaves from side to side as it goes), `size`
## metres across, living `life` seconds, its halo `color`.
func emit_ember(at: Vector3, velocity: Vector3, size: float, life: float, color: Color) -> void:
	_take(Kind.EMBER, at, velocity, Vector3.ZERO, size, ROUND, life, color, 0.0)


## A billow of smoke at `at` drifting at `velocity` (slowing as it ages), `size` metres across
## when grown, living `life` seconds, in `color` (its top; the shader warms its underside).
func emit_smoke(at: Vector3, velocity: Vector3, size: float, life: float, color: Color) -> void:
	_take(Kind.SMOKE, at, velocity, Vector3.ZERO, size, ROUND, life, color, 0.0)


## Draws this pool's flames with the painted flipbook (FlameAtlas), set on its material (shared
## by every pool of its render priority). Paints the flipbook on the first call.
func paint_flames() -> void:
	var material := (multimesh.mesh as QuadMesh).material as ShaderMaterial
	material.set_shader_parameter("flame_atlas", FlameAtlas.texture())


## Advances every live puff `delta` seconds.
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
		var keep := 1.0
		var kind := _kind[slot]
		var alpha := fire_fade(k) if kind >= Kind.FLAME else fade(k)
		match kind:
			Kind.PLUME:
				_place_plume(slot, k)
			Kind.RING:
				_place_ring(slot, k)
			Kind.FLAME:
				_place_flame(slot, age, k)
			Kind.EMBER:
				_place_ember(slot, age)
			_:
				keep = _place_blob(slot, age, k)
		var color := _colors[slot]
		color.a *= alpha * keep
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


## A fire puff's alpha `k` of the way through its life: a quick swell in, a long hold, a fade
## from FIRE_FADE_FROM. Pure.
static func fire_fade(k: float) -> float:
	if k < SWELL:
		return k / SWELL
	return 1.0 - smoothstep(FIRE_FADE_FROM, 1.0, k)


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
	_next = (_next + 1) % capacity
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


## Flame `slot` `age` seconds (`k` of its life) in: risen along its velocity, swollen to its
## width at once and narrowing to FLAME_NARROW less by its end, its height kept.
func _place_flame(slot: int, age: float, k: float) -> void:
	var at := _from[slot] + _velocity[slot] * age
	var swell := smoothstep(0.0, SWELL * 2.0, k)
	var width := _size[slot] * (1.0 - FLAME_NARROW * k) * (0.55 + 0.45 * swell)
	var height := _size[slot] * _aspect[slot] * (0.7 + 0.3 * swell)
	multimesh.set_instance_transform(slot, Transform3D(basis_along(Vector3.UP, width), at))
	_shape(slot, height / maxf(width, 0.01))


## Ember `slot` `age` seconds in: drifting along its velocity and weaving across it.
func _place_ember(slot: int, age: float) -> void:
	var velocity := _velocity[slot]
	var across := Vector3(-velocity.z, 0.0, velocity.x)
	across = across.normalized() if across.length_squared() > 1e-6 else Vector3.RIGHT
	var weave := sin(age * EMBER_WEAVE_RATE + _seed[slot] * TAU) * EMBER_WEAVE
	var at := _from[slot] + velocity * age + across * weave
	multimesh.set_instance_transform(slot, Transform3D(basis_along(Vector3.UP, _size[slot]), at))


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
