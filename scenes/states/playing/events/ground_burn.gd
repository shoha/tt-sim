class_name GroundBurn
extends MeshInstance3D

## The fire on the ground (FireSweep): a box over the burning stand whose shader
## (shaders/ground_burn.gdshader) paints the ground seen through it from the depth buffer. The
## front is not a circle but a level line of the fire's noise: a point burns once the front's
## radius (front_radius: the nearest tree's distance at once, the rim SPREAD_S later) passes
## its reach, its distance from the centre pulled in or pushed out by the lobe field (reach), so
## lobes run ahead and bays lag as it grows. Ahead of it the grass dries in a mottled band, on it
## a hot band of varying width burns, broken into crawling segments, and behind it the ground is
## charred with glowing specks that cool as the front leaves them. Its glow dies once the front
## has reached the rim (glow_at), and the char stays until the ash has landed (FireSweep holds
## it past the event's end until its change is on the board, drifting meanwhile toward the
## ash's warm grey, ashen_at), then goes (char_at), so the charred ground hands over to the ash
## rather than popping or showing the grass between.
##
## The lobe field is one small wrapping texture of the fire's noise (fire_noise.gdshaderinc's
## two octaves, made periodic), painted once for the session; the shader samples it and reach
## reads the same bytes, so the ground tongues and the trees (FireSweep) are timed by the very
## line the ground shows. A frame only sets a few uniforms, so it allocates nothing while it
## plays.
##
## Along a path (setup_path, Start a fire's Path shape) the same front runs along the line
## instead of out from a centre: a point's reach is its arc length to the nearest point of the
## line (FirePath.project, run in the shader over the path's points), lobed by the same field
## (path_reach), and it burns only within the half-width of the line, the same dry band and
## ragged edge along both sides and round both ends. The box covers the path's bounds, and the
## ground's height is taken from the line under each point, so a path over a slope keeps to
## the ground and what stands low on it.

## The lobe field: its size in pixels, its period in noise units (one blob a unit across), and
## how far it moves the front (metres, a share of the rim) at what scale (a blob's width,
## metres, a share of the rim, at least LOBE_MIN_M).
const LOBE_PX := 64
const LOBE_PERIOD := 8
const LOBE_SHARE := 0.55
const LOBE_SCALE := 0.4
const LOBE_MIN_M := 1.5
## The box: its half height (metres about the stand's ground) and how far past the furthest
## lobe it reaches (the dry band and the ragged edge).
const HALF_HEIGHT_M := 1.5
const PAD_M := 2.6
## Glow: how fast it comes in, how long it holds past the front reaching the rim, how long it
## takes to die; and the char's going about the end of the event.
const GLOW_IN_S := 0.15
const GLOW_HOLD_S := 0.35
const GLOW_OUT_S := 0.8
const CHAR_OUT_S := Vector2(-0.2, 0.6)
## Held past the event's end until the change lands (FireSweep.end_at), the char drifts toward
## the landed ash's warm grey: this share of the way at most, over ASHEN_S from the end, so a
## long path's board is not a still dark strip for seconds and the char hands over to a near
## colour (card F6c; at 0.5 a 50 m path's char went from 63,56,50 to 84,75,65 by the end of its
## hold against the landed ash's 143,119,101, too little to read as change).
const ASHEN := 0.7
const ASHEN_S := 3.0
const SHADER := preload("res://shaders/ground_burn.gdshader")

static var _lobe_bytes := PackedByteArray()
static var _lobe_texture: ImageTexture = null

var _material: ShaderMaterial = null
var _nearest := 0.0
var _radius := 1.0
var _spread := 1.0
var _duration := 1.0


## The burn set up over map point `centre` (ground height), the nearest tree `nearest` metres
## out and the rim `radius`, the front taking `spread` seconds between them, the event lasting
## `duration`, its lobes drawn by `event_seed`.
func setup(
	centre: Vector3, nearest: float, radius: float, spread: float, duration: float, event_seed: int
) -> void:
	_begin(nearest, radius, spread, duration)
	position = centre
	var across := 2.0 * (_radius * (1.05 + 0.5 * LOBE_SHARE) + PAD_M)
	_shade(Vector3(across, 2.0 * HALF_HEIGHT_M, across), _radius, event_seed)
	step(0.0)


## The burn set up along `line` (map XZ, at least two points; `heights` the ground under each),
## `half_width` metres either side of it, the front running from its first point to its last
## over `spread` seconds, the event lasting `duration`, its lobes drawn by `event_seed`. Its
## frame is the line's first point's, as a circle's is its centre, so path_reach and the shader
## read the lobe field alike.
func setup_path(
	line: PackedVector2Array,
	heights: PackedFloat32Array,
	half_width: float,
	spread: float,
	duration: float,
	event_seed: int
) -> void:
	var along := FirePath.arcs(line)
	_begin(0.0, along[-1], spread, duration)
	var area := Rect2(line[0], Vector2.ZERO)
	for p in line:
		area = area.expand(p)
	area = area.grow(half_width * (1.05 + 0.5 * LOBE_SHARE) + PAD_M)
	var low := INF
	var high := -INF
	for h in heights:
		low = minf(low, h)
		high = maxf(high, h)
	var middle := area.get_center()
	position = Vector3(middle.x, (low + high) * 0.5, middle.y)
	var size := Vector3(area.size.x, high - low + 2.0 * HALF_HEIGHT_M, area.size.y)
	_shade(size, half_width, event_seed)
	var points := PackedVector4Array()
	for i in line.size():
		var at := line[i] - line[0]
		points.append(Vector4(at.x, at.y, along[i], heights[i] - position.y))
	_material.set_shader_parameter(&"path_points", points)
	_material.set_shader_parameter(&"path_count", line.size())
	_material.set_shader_parameter(&"path_width", half_width)
	_material.set_shader_parameter(&"frame_offset", middle - line[0])
	step(0.0)


func _begin(nearest: float, radius: float, spread: float, duration: float) -> void:
	name = "GroundBurn"
	_nearest = nearest
	_radius = maxf(radius, 0.5)
	_spread = maxf(spread, 0.05)
	_duration = duration
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The box of `size` and its material, the lobe field scaled for a rim (or a path's half-width)
## of `scale_m`.
func _shade(size: Vector3, scale_m: float, event_seed: int) -> void:
	var box := BoxMesh.new()
	box.size = size
	mesh = box
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# Below the water's transparent pass: the ground is reworked before anything is drawn over it.
	_material.render_priority = -1
	_material.set_shader_parameter(&"lobe_texture", lobe_texture())
	_material.set_shader_parameter(&"lobe_m", lobe_m(scale_m))
	_material.set_shader_parameter(&"lobe_scale", lobe_scale(scale_m))
	_material.set_shader_parameter(&"lobe_offset", lobe_offset(event_seed))
	_material.set_shader_parameter(&"lobe_period", float(LOBE_PERIOD))
	_material.set_shader_parameter(&"half_height", HALF_HEIGHT_M)
	material_override = _material


## Plays the burn `elapsed` seconds into the fire, its char going about `end` (char_at; the
## event's end when below 0, else FireSweep.end_at: once its change has landed).
func step(elapsed: float, end: float = -1.0) -> void:
	var gone := char_at(elapsed, _duration if end < 0.0 else end)
	visible = gone > 0.0
	if not visible:
		return
	_material.set_shader_parameter(&"front", front_radius(elapsed, _nearest, _radius, _spread))
	_material.set_shader_parameter(&"glow", glow_at(elapsed, _spread))
	_material.set_shader_parameter(&"fade", gone)
	_material.set_shader_parameter(&"ashen", ashen_at(elapsed, _duration))
	_material.set_shader_parameter(&"elapsed", elapsed)


## The front's radius `t` seconds in: the nearest tree's distance at once, the rim `spread`
## seconds later, holding a little past it. Pure.
static func front_radius(t: float, nearest: float, radius: float, spread: float) -> float:
	var x := clampf(t / maxf(spread, 0.01), 0.0, 1.05)
	return lerpf(nearest, radius, x)


## The burn's glow `t` seconds in, 0..1: in over GLOW_IN_S, held until GLOW_HOLD_S after the
## front reaches the rim, dying over GLOW_OUT_S. Pure.
static func glow_at(t: float, spread: float) -> float:
	var rise := clampf(t / GLOW_IN_S, 0.0, 1.0)
	var fall := 1.0 - smoothstep(spread + GLOW_HOLD_S, spread + GLOW_HOLD_S + GLOW_OUT_S, t)
	return rise * fall


## The char's alpha `t` seconds into an event whose ash has landed by `duration` (the event's
## end, or later once its change landed): whole until just before then, gone soon after. Pure.
static func char_at(t: float, duration: float) -> float:
	return 1.0 - smoothstep(duration + CHAR_OUT_S.x, duration + CHAR_OUT_S.y, t)


## How far toward the ash's colour the char has drifted `t` seconds into an event that ended
## at `duration`: none while it burns, easing up to ASHEN over ASHEN_S after its end. Pure.
static func ashen_at(t: float, duration: float) -> float:
	return ASHEN * smoothstep(duration, duration + ASHEN_S, t)


## How far the lobe field moves the front for a rim of `radius` metres, and its blobs' width.
static func lobe_m(radius: float) -> float:
	return LOBE_SHARE * radius


static func lobe_scale(radius: float) -> float:
	return maxf(LOBE_SCALE * radius, LOBE_MIN_M)


## Where in the lobe field a fire of `event_seed` reads (noise units).
static func lobe_offset(event_seed: int) -> Vector2:
	var a := fposmod(float(event_seed) * 0.7548777, 1.0)
	var b := fposmod(float(event_seed) * 0.5698403, 1.0)
	return Vector2(a, b) * float(LOBE_PERIOD)


## The reach of map point `p` (metres from the centre, the burn's frame) in a fire of rim
## `radius` and seed `event_seed`: its distance pulled in where the lobe field is high and
## pushed out where it is low, so the front (front_radius) reaches it once it passes this.
## The shader's line, less its fine ragging. Pure but for the field, painted once.
static func reach(p: Vector2, radius: float, event_seed: int) -> float:
	var at := p / lobe_scale(radius) + lobe_offset(event_seed)
	return p.length() - lobe_m(radius) * (lobe_at(at / float(LOBE_PERIOD)) - 0.5)


## The reach along a path of map point `p` (metres from the path's first point), `arc` metres
## along the line where it lies nearest, in a fire `half_width` wide of seed `event_seed`: its
## arc pulled in or pushed out by the lobe field, as reach() moves a circle's distance. Pure
## but for the field.
static func path_reach(p: Vector2, arc: float, half_width: float, event_seed: int) -> float:
	var at := p / lobe_scale(half_width) + lobe_offset(event_seed)
	return arc - lobe_m(half_width) * (lobe_at(at / float(LOBE_PERIOD)) - 0.5)


## The lobe field at `uv` (wrapping, a period across), 0..1, bilinear as the GPU samples it.
static func lobe_at(uv: Vector2) -> float:
	lobe_texture()
	var f := uv * float(LOBE_PX) - Vector2(0.5, 0.5)
	var x0 := floori(f.x)
	var y0 := floori(f.y)
	var tx := f.x - x0
	var ty := f.y - y0
	var a := _lobe_byte(x0, y0) * (1.0 - tx) + _lobe_byte(x0 + 1, y0) * tx
	var b := _lobe_byte(x0, y0 + 1) * (1.0 - tx) + _lobe_byte(x0 + 1, y0 + 1) * tx
	return (a * (1.0 - ty) + b * ty) / 255.0


## The lobe field's texture, painted once for the session: fire_noise.gdshaderinc's two
## octaves on a lattice wrapped every LOBE_PERIOD units.
static func lobe_texture() -> ImageTexture:
	if _lobe_texture != null:
		return _lobe_texture
	_lobe_bytes.resize(LOBE_PX * LOBE_PX)
	for y in LOBE_PX:
		for x in LOBE_PX:
			var q := Vector2(x + 0.5, y + 0.5) * float(LOBE_PERIOD) / float(LOBE_PX)
			var v := 0.68 * fire_noise(q, LOBE_PERIOD)
			v += 0.32 * fire_noise(q * 2.0 + Vector2(7.0, 3.0), LOBE_PERIOD * 2)
			_lobe_bytes[y * LOBE_PX + x] = clampi(roundi(v * 255.0), 0, 255)
	var image := Image.create_from_data(LOBE_PX, LOBE_PX, false, Image.FORMAT_L8, _lobe_bytes)
	_lobe_texture = ImageTexture.create_from_image(image)
	return _lobe_texture


## fire_noise.gdshaderinc's value noise at `p`, its lattice wrapped every `period` units, so
## the field tiles. Pure.
static func fire_noise(p: Vector2, period: int) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := fire_hash(_wrap(i, period))
	var b := fire_hash(_wrap(i + Vector2(1.0, 0.0), period))
	var c := fire_hash(_wrap(i + Vector2(0.0, 1.0), period))
	var d := fire_hash(_wrap(i + Vector2(1.0, 1.0), period))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


## fire_noise.gdshaderinc's hash, 0..1. Pure.
static func fire_hash(p: Vector2) -> float:
	var q := Vector2(_fract(p.x * 123.34), _fract(p.y * 456.21))
	var d := q.dot(q + Vector2(45.32, 45.32))
	q += Vector2(d, d)
	return _fract(q.x * q.y)


static func _fract(v: float) -> float:
	return v - floorf(v)


static func _wrap(i: Vector2, period: int) -> Vector2:
	return Vector2(fposmod(i.x, period), fposmod(i.y, period))


static func _lobe_byte(x: int, y: int) -> float:
	return float(_lobe_bytes[posmod(y, LOBE_PX) * LOBE_PX + posmod(x, LOBE_PX)])
