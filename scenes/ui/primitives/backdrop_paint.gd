class_name BackdropPaint
extends RefCounted

## The colours shaders/ui_backdrop.gdshader paints, for the full-screen backdrop
## (PaintedBackdrop) and for a map's placeholder picture (MapPlaceholder) alike, so a card and
## the screen behind it share one light.
##
## A look is a soft sky gradient in three stops, top to horizon: one of six curated moods
## (MOODS), or a mix of two while the light changes. Two looks mix in OKLCH (mix_looks): the
## lightness and the chroma run straight across, so no mix greys, and every stop's hue turns
## round the circle the same way (hue_route), so the top and the horizon never pass through
## opposite hues. The painted scenery (a sun, clouds, hills, poplars) was retired by the
## UI_TASTE verdict of 2026-10-10: until the UI's painterly side is revisited, the screens
## outside play stand on solid colour and subtle gradients.

## A mood: its sky's three stops (sRGB paint values as the shader's vec3, not theme roles: the
## backdrop's palette is its own, and the interface's colours never change with it). The
## middle stop is curated: its hue is the way the gradient turns from the top to the horizon
## (morning's lavender sends it through a blush rather than through mint). The shader blends
## the three on one smooth curve in OKLCH (uniforms, colour_at), so the middle stop shapes the
## gradient without a seam at it.
const MOODS: Array[Dictionary] = [
	{  # Morning: clear blue through a lavender blush to a warm cream horizon.
		"sky_top": Vector3(0.55, 0.79, 0.94),
		"sky_mid": Vector3(0.84, 0.85, 0.98),
		"sky_low": Vector3(0.99, 0.90, 0.75),
	},
	{  # Midday: a deep, bright blue paling to the horizon.
		"sky_top": Vector3(0.50, 0.77, 0.96),
		"sky_mid": Vector3(0.66, 0.85, 0.97),
		"sky_low": Vector3(0.84, 0.94, 0.97),
	},
	{  # Golden hour: blue over a rose band over gold.
		"sky_top": Vector3(0.64, 0.74, 0.93),
		"sky_mid": Vector3(1.00, 0.76, 0.78),
		"sky_low": Vector3(1.00, 0.82, 0.57),
	},
	{  # Dusk: violet over rose over coral.
		"sky_top": Vector3(0.45, 0.44, 0.76),
		"sky_mid": Vector3(0.88, 0.54, 0.68),
		"sky_low": Vector3(0.99, 0.67, 0.53),
	},
	{  # Overcast: soft periwinkle over a pale blush.
		"sky_top": Vector3(0.66, 0.73, 0.92),
		"sky_mid": Vector3(0.80, 0.82, 0.96),
		"sky_low": Vector3(0.96, 0.89, 0.95),
	},
	{  # Night: deep navy over a moonlit blue.
		"sky_top": Vector3(0.19, 0.25, 0.51),
		"sky_mid": Vector3(0.29, 0.37, 0.68),
		"sky_low": Vector3(0.44, 0.52, 0.80),
	},
]

## The furthest a colour turns round the hue circle (radians) to keep to the route; a colour
## that would turn further takes its own short way, which is then a small turn.
const MAX_TURN := TAU * 5.0 / 6.0
## Below this chroma a colour has no hue worth keeping; it takes the other colour's.
const GREY_CHROMA := 0.03


## The look of `mood` (a PaintedBackdrop.Mood).
static func look_of(mood: int) -> Dictionary:
	return MOODS[clampi(mood, 0, MOODS.size() - 1)]


## The shader's uniforms for `look`: its stops as OKLCH (lightness, chroma, hue in radians),
## each hue unwrapped from the one above it the short way, so the gradient turns through the
## middle stop's hue. The shader blends in OKLCH because a blend in sRGB of a blue top and a
## warm horizon cancels to grey part way (morning's did); in OKLCH the chroma runs between
## the stops' own and never dips toward grey.
static func uniforms(look: Dictionary) -> Dictionary:
	var top := to_oklch(look.sky_top)
	var mid := to_oklch(look.sky_mid)
	var low := to_oklch(look.sky_low)
	# Every stop keeps its own hue, however pale: no stop is grey (the luminous gradient test).
	mid.z = top.z + _short_turn(top.z, mid.z)
	low.z = mid.z + _short_turn(mid.z, low.z)
	return {"top_lch": top, "mid_lch": mid, "low_lch": low}


## The colour `t` of the way up `look`'s gradient (0 the horizon, 1 the top), as the shader
## paints it: one quadratic curve in OKLCH through the three stops, clipped to the screen.
static func colour_at(look: Dictionary, t: float) -> Vector3:
	var stops := uniforms(look)
	var low: Vector3 = stops.low_lch
	var mid: Vector3 = stops.mid_lch
	var top: Vector3 = stops.top_lch
	var lin := _linear_of(low.lerp(mid, t).lerp(mid.lerp(top, t), t)).clamp(Vector3.ZERO, Vector3.ONE)
	return Vector3(_to_srgb(lin.x), _to_srgb(lin.y), _to_srgb(lin.z))


## The signed turn from hue `from` to hue `to` the short way (radians).
static func _short_turn(from: float, to: float) -> float:
	var up := fposmod(to - from, TAU)
	return up if up <= PI else up - TAU


## The look part way, `k`, from `from` to `to`, its colours mixed in OKLCH, every stop's hue
## turning round the circle the same way (hue_route).
static func mix_looks(from: Dictionary, to: Dictionary, k: float) -> Dictionary:
	if k <= 0.0:
		return from
	if k >= 1.0:
		return to
	var route := hue_route(from, to)
	var mixed := {}
	for key: String in to:
		mixed[key] = mix_oklch(from.get(key, to[key]), to[key], k, route)
	return mixed


## The way round the hue circle the stops take from `from` to `to`: 1.0 up, -1.0 down. Each
## stop votes for its short way by how far it turns and how colourful it is, so the stops that
## change the most decide, and the rest follow them.
static func hue_route(from: Dictionary, to: Dictionary) -> float:
	var vote := 0.0
	for key: String in to:
		var hues := _hues(from.get(key, to[key]), to[key])
		var up := fposmod(hues[1].z - hues[0].z, TAU)
		var turn := up if up <= PI else up - TAU
		vote += turn * minf(hues[0].y, hues[1].y)
	return 1.0 if vote >= 0.0 else -1.0


## The sRGB colour `a` mixed `k` of the way to `b` in OKLCH, so the mix keeps its saturation;
## its hue turns the way `route` says (1.0 up, -1.0 down) unless that is past MAX_TURN, and
## the short way with no route (0.0).
static func mix_oklch(a: Vector3, b: Vector3, k: float, route := 0.0) -> Vector3:
	var hues := _hues(a, b)
	var one: Vector3 = hues[0]
	var two: Vector3 = hues[1]
	var hue := _mix_hue(one.z, two.z, k, route)
	return from_oklch(Vector3(lerpf(one.x, two.x, k), lerpf(one.y, two.y, k), hue))


## `a` and `b` as OKLCH, a grey taking the other colour's hue (it has none worth keeping).
static func _hues(a: Vector3, b: Vector3) -> Array[Vector3]:
	var one := to_oklch(a)
	var two := to_oklch(b)
	if one.y < GREY_CHROMA:
		one.z = two.z
	if two.y < GREY_CHROMA:
		two.z = one.z
	return [one, two]


## The hue `k` of the way from `from` to `to` (radians), turning the way `route` says unless
## that is past MAX_TURN; the short way with no route.
static func _mix_hue(from: float, to: float, k: float, route: float) -> float:
	var start := fposmod(from, TAU)
	var up := fposmod(to - start, TAU)
	var down := TAU - up
	var go_up := up <= down
	if route > 0.0 and up <= MAX_TURN:
		go_up = true
	elif route < 0.0 and down <= MAX_TURN:
		go_up = false
	return start + (up if go_up else -down) * k


## An sRGB colour (0 to 1 per channel) as OKLCH: lightness, chroma and hue in radians.
static func to_oklch(rgb: Vector3) -> Vector3:
	var lin := Vector3(_to_linear(rgb.x), _to_linear(rgb.y), _to_linear(rgb.z))
	var l := _cbrt(0.4122214708 * lin.x + 0.5363325363 * lin.y + 0.0514459929 * lin.z)
	var m := _cbrt(0.2119034982 * lin.x + 0.6806995451 * lin.y + 0.1073969566 * lin.z)
	var s := _cbrt(0.0883024619 * lin.x + 0.2817188376 * lin.y + 0.6299787005 * lin.z)
	var lightness := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var a := 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	var b := 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return Vector3(lightness, sqrt(a * a + b * b), atan2(b, a))


## OKLCH back to an sRGB colour. A colour past what a screen shows keeps its lightness and hue
## and gives up chroma until it fits, so no mix shifts toward another hue at the gamut's edge.
static func from_oklch(lch: Vector3) -> Vector3:
	var lin := _linear_of(lch)
	if not _in_gamut(lin):
		var low := 0.0
		var high := lch.y
		for i in 12:
			var mid := (low + high) * 0.5
			if _in_gamut(_linear_of(Vector3(lch.x, mid, lch.z))):
				low = mid
			else:
				high = mid
		lin = _linear_of(Vector3(lch.x, low, lch.z))
	lin = lin.clamp(Vector3.ZERO, Vector3.ONE)
	return Vector3(_to_srgb(lin.x), _to_srgb(lin.y), _to_srgb(lin.z))


static func _linear_of(lch: Vector3) -> Vector3:
	var a := lch.y * cos(lch.z)
	var b := lch.y * sin(lch.z)
	var l := lch.x + 0.3963377774 * a + 0.2158037573 * b
	var m := lch.x - 0.1055613458 * a - 0.0638541728 * b
	var s := lch.x - 0.0894841775 * a - 1.2914855480 * b
	l = l * l * l
	m = m * m * m
	s = s * s * s
	return Vector3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	)


static func _in_gamut(lin: Vector3) -> bool:
	var low := minf(lin.x, minf(lin.y, lin.z))
	return low >= -0.001 and maxf(lin.x, maxf(lin.y, lin.z)) <= 1.001


static func _to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _to_srgb(c: float) -> float:
	return 12.92 * c if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


static func _cbrt(value: float) -> float:
	return pow(maxf(value, 0.0), 1.0 / 3.0)
