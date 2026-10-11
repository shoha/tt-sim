class_name GroundBurn
extends Decal

## The fire on the ground (FireSweep): a decal over the burning stand whose painted ring is the
## burn front, glowing in the flames' own stepped bands (deep red outside, orange, gold, a few
## ember spots behind), with charred ground inside it. It is sized every frame so the ring runs
## out with the front (front_radius: the nearest tree's distance at once, the rim SPREAD_S
## later), its glow dies once the front has reached the rim (glow_at), and the char under it
## stays until the ash lands at the end of the event, then goes (char_at), so the charred
## ground hands over to the ash rather than popping.
##
## Painted once (texture pair, kept for the session); a frame only sets its size, energy and
## alpha, so it allocates nothing while it plays. Its normal fade keeps it off the trunks.

## The ring's mean radius in the texture (a share of its half size), how far the painted front
## wanders from it, and the texture's size in pixels.
const RING_AT := 0.86
const RING_WANDER := 0.08
const PAINT_PX := 256
## The decal's height (metres) about the stand's ground.
const DEPTH_M := 3.0
## Glow: how fast it comes in, how long it holds past the front reaching the rim, how long it
## takes to die; and the char's going about the end of the event.
const GLOW_IN_S := 0.15
const GLOW_HOLD_S := 0.35
const GLOW_OUT_S := 0.8
const CHAR_OUT_S := Vector2(-0.2, 0.6)
const ENERGY := 2.4
## The stepped bands (sRGB, as the decal's textures are): the front's deep red outer edge,
## orange, gold behind it, the ember spots; the charred ground and the band once it has
## cooled, dark warm brown.
const BAND_RED := Color(0.75, 0.12, 0.04)
const BAND_ORANGE := Color(1.0, 0.45, 0.08)
const BAND_GOLD := Color(1.0, 0.78, 0.3)
const EMBER := Color(0.8, 0.2, 0.04)
const CHAR := Color(0.11, 0.08, 0.07, 0.88)
const CHAR_ASH := Color(0.3, 0.27, 0.25, 0.8)
const BAND_COOL := Color(0.13, 0.08, 0.06, 0.92)

static var _albedo: ImageTexture = null
static var _emission: ImageTexture = null

var _nearest := 0.0
var _radius := 1.0
var _spread := 1.0
var _duration := 1.0


## The ring set up over map point `centre` (ground height), the nearest tree `nearest` metres
## out and the rim `radius`, the front taking `spread` seconds between them, the event lasting
## `duration`.
func setup(centre: Vector3, nearest: float, radius: float, spread: float, duration: float) -> void:
	name = "GroundBurn"
	_nearest = nearest
	_radius = maxf(radius, 0.5)
	_spread = maxf(spread, 0.05)
	_duration = duration
	position = centre
	paint()
	texture_albedo = _albedo
	texture_emission = _emission
	normal_fade = 0.45
	upper_fade = 0.2
	lower_fade = 0.2
	emission_energy = 0.0
	cull_mask = 0xFFFFF
	_size_to(front_radius(0.0, _nearest, _radius, _spread))


## Plays the ring `elapsed` seconds into the fire.
func step(elapsed: float) -> void:
	var gone := char_at(elapsed, _duration)
	visible = gone > 0.0
	if not visible:
		return
	_size_to(front_radius(elapsed, _nearest, _radius, _spread))
	var flicker := 0.88 + 0.12 * sin(elapsed * 13.0)
	emission_energy = ENERGY * glow_at(elapsed, _spread) * flicker
	modulate = Color(1.0, 1.0, 1.0, gone)


## The front's radius `t` seconds in: the nearest tree's distance at once, the rim `spread`
## seconds later, holding a little past it. Pure.
static func front_radius(t: float, nearest: float, radius: float, spread: float) -> float:
	var x := clampf(t / maxf(spread, 0.01), 0.0, 1.05)
	return lerpf(nearest, radius, x)


## The ring's glow `t` seconds in, 0..1: in over GLOW_IN_S, held until GLOW_HOLD_S after the
## front reaches the rim, dying over GLOW_OUT_S. Pure.
static func glow_at(t: float, spread: float) -> float:
	var rise := clampf(t / GLOW_IN_S, 0.0, 1.0)
	var fall := 1.0 - smoothstep(spread + GLOW_HOLD_S, spread + GLOW_HOLD_S + GLOW_OUT_S, t)
	return rise * fall


## The char's alpha `t` seconds into an event of `duration`: whole until just before the ash
## lands, gone soon after. Pure.
static func char_at(t: float, duration: float) -> float:
	return 1.0 - smoothstep(duration + CHAR_OUT_S.x, duration + CHAR_OUT_S.y, t)


## Paints the ring's albedo and emission once for the session.
static func paint() -> void:
	if _albedo != null:
		return
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.frequency = 0.05
	noise.seed = 11
	var albedo := Image.create(PAINT_PX, PAINT_PX, false, Image.FORMAT_RGBA8)
	var emission := Image.create(PAINT_PX, PAINT_PX, false, Image.FORMAT_RGBA8)
	var half := PAINT_PX * 0.5
	for y in PAINT_PX:
		for x in PAINT_PX:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half) / half
			var paint_at := ring_paint(p, noise.get_noise_2d(x, y) * 0.5 + 0.5)
			albedo.set_pixel(x, y, paint_at[0])
			emission.set_pixel(x, y, paint_at[1])
	_albedo = ImageTexture.create_from_image(albedo)
	_emission = ImageTexture.create_from_image(emission)


## The ring's paint at `p` (the texture's -1..1) with the noise there `blot` (0..1): [albedo,
## emission]. Stepped bands about a front that wanders round the ring. Pure.
static func ring_paint(p: Vector2, blot: float) -> Array[Color]:
	var a := p.angle()
	var wander := 0.5 * sin(5.0 * a + 1.0) + 0.3 * sin(9.0 * a + 2.0) + 0.2 * sin(17.0 * a + 0.5)
	var front := RING_AT + RING_WANDER * wander
	var d := p.length() - front
	var none := Color(0.0, 0.0, 0.0, 0.0)
	if d > 0.04:
		return [none, none]
	# The front burns in arcs of varying depth with a few cool breaks between them, not as one
	# even line (an even ring read as a drawn outline).
	var arc := 0.5 + 0.5 * sin(7.0 * a + 2.0 * sin(3.0 * a + 0.7))
	if arc < 0.16:
		return [BAND_COOL, none]
	var deep := 0.55 + 0.75 * arc
	if d > 0.018:
		return [BAND_COOL, BAND_RED]
	if d > -0.012 * deep:
		return [BAND_COOL, BAND_ORANGE]
	if d > -0.04 * deep:
		return [BAND_COOL, BAND_GOLD]
	var ground := CHAR_ASH if blot > 0.68 else CHAR
	if d > -0.22 and blot < 0.3:
		return [BAND_COOL, EMBER]
	return [ground, none]


func _size_to(front: float) -> void:
	var across := 2.0 * front / RING_AT
	size = Vector3(across, DEPTH_M, across)
