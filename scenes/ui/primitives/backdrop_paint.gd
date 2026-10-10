class_name BackdropPaint
extends RefCounted

## What shaders/ui_backdrop.gdshader paints, worked out on the CPU, for the full-screen backdrop
## (PaintedBackdrop) and for a map's placeholder picture (MapPlaceholder) alike, so a card and
## the screen behind it show the same world.
##
## A picture is a look and a composition. The look is the light: one of six curated moods
## (MOODS), or a mix of two while the light changes. Two looks mix in OKLCH (mix_looks): the
## lightness and the chroma run straight across and the hue takes the short way round (between
## hues all but opposite, the way through red and magenta), so golden hour to night passes
## through rose and violet rather than grey and khaki. The sun's place,
## size and moonness mix with it, so one disc moves and changes; there are never two.
##
## The composition is the land and the weather, drawn from the map's seed (compose): the phase
## and the swell of the skyline, how many poplars stand and where, and four clouds' places and
## shapes. Two forest maps get their own skies while the moods stay curated. On a screen the
## composition then makes way for the screen's paper (BackdropLayout): each cloud moves to open
## sky (a cloud's base in the band of cards read as a ghost card), the poplars to a stretch of
## crest no sheet covers, and the open square the sun or moon sits in is the largest the layout
## leaves. Two compositions mix too (mix_compositions), so a new map's land rolls into place.

## A mood: its colours (sRGB paint values as the shader's vec3, not theme roles: the painting's
## palette is its own, and the interface's colours never change with it), then the sun's
## preferred place (x as a share of the width, y in heights
## from the foot), its radius in heights, its glow, how much of its disc shows (0: behind cloud),
## how much it is the moon, how many stars show and how large the clouds are. Every far, near
## and meadow colour holds at least 25% saturation, so no mood greys or muddies. The poplars
## stand apart from the hill in every mood: shade toward a cool teal (deep navy at night), light
## toward gold-green (a coral rim at dusk, a moonlit edge at night).
const MOODS: Array[Dictionary] = [
	{  # Morning.
		"sky_top": Vector3(0.55, 0.79, 0.94),
		"sky_low": Vector3(0.99, 0.90, 0.75),
		"sun_col": Vector3(1.00, 0.99, 0.93),
		"sun_glow": Vector3(1.00, 0.86, 0.56),
		"cloud_lit": Vector3(1.00, 0.98, 0.95),
		"cloud_shade": Vector3(0.80, 0.82, 0.94),
		"range_col": Vector3(0.64, 0.76, 0.92),
		"far_col": Vector3(0.42, 0.68, 0.78),
		"near_col": Vector3(0.49, 0.74, 0.41),
		"meadow_col": Vector3(0.34, 0.63, 0.31),
		"rim_col": Vector3(0.70, 0.86, 0.46),
		"tree_shade": Vector3(0.13, 0.42, 0.40),
		"tree_lit": Vector3(0.64, 0.82, 0.34),
		"sun_x": 0.84,
		"sun_y": 0.60,
		"sun_r": 0.046,
		"glow": 0.55,
		"disc": 1.0,
		"moon": 0.0,
		"stars": 0.0,
		"cloud_size": 1.0,
	},
	{  # Midday.
		"sky_top": Vector3(0.54, 0.79, 0.96),
		"sky_low": Vector3(0.86, 0.94, 0.97),
		"sun_col": Vector3(1.00, 1.00, 0.97),
		"sun_glow": Vector3(1.00, 0.95, 0.74),
		"cloud_lit": Vector3(1.00, 1.00, 1.00),
		"cloud_shade": Vector3(0.78, 0.85, 0.96),
		"range_col": Vector3(0.62, 0.78, 0.95),
		"far_col": Vector3(0.40, 0.66, 0.82),
		"near_col": Vector3(0.45, 0.74, 0.35),
		"meadow_col": Vector3(0.29, 0.61, 0.27),
		"rim_col": Vector3(0.62, 0.86, 0.38),
		"tree_shade": Vector3(0.11, 0.42, 0.36),
		"tree_lit": Vector3(0.58, 0.82, 0.30),
		"sun_x": 0.88,
		"sun_y": 0.70,
		"sun_r": 0.042,
		"glow": 0.40,
		"disc": 1.0,
		"moon": 0.0,
		"stars": 0.0,
		"cloud_size": 0.9,
	},
	{  # Golden hour.
		"sky_top": Vector3(0.64, 0.74, 0.93),
		"sky_low": Vector3(1.00, 0.82, 0.57),
		"sun_col": Vector3(1.00, 0.97, 0.84),
		"sun_glow": Vector3(1.00, 0.70, 0.36),
		"cloud_lit": Vector3(1.00, 0.89, 0.73),
		"cloud_shade": Vector3(0.80, 0.67, 0.80),
		"range_col": Vector3(0.88, 0.66, 0.84),
		"far_col": Vector3(0.66, 0.52, 0.76),
		"near_col": Vector3(0.80, 0.70, 0.34),
		"meadow_col": Vector3(0.47, 0.65, 0.25),
		"rim_col": Vector3(0.95, 0.82, 0.42),
		"tree_shade": Vector3(0.12, 0.38, 0.44),
		"tree_lit": Vector3(0.76, 0.80, 0.28),
		"sun_x": 0.82,
		"sun_y": 0.50,
		"sun_r": 0.056,
		"glow": 0.80,
		"disc": 1.0,
		"moon": 0.0,
		"stars": 0.0,
		"cloud_size": 1.05,
	},
	{  # Dusk.
		"sky_top": Vector3(0.45, 0.44, 0.76),
		"sky_low": Vector3(0.99, 0.67, 0.53),
		"sun_col": Vector3(1.00, 0.93, 0.78),
		"sun_glow": Vector3(1.00, 0.58, 0.44),
		"cloud_lit": Vector3(0.99, 0.73, 0.67),
		"cloud_shade": Vector3(0.58, 0.47, 0.72),
		"range_col": Vector3(0.80, 0.54, 0.70),
		"far_col": Vector3(0.55, 0.36, 0.60),
		"near_col": Vector3(0.43, 0.32, 0.60),
		"meadow_col": Vector3(0.29, 0.24, 0.47),
		"rim_col": Vector3(0.78, 0.50, 0.60),
		"tree_shade": Vector3(0.08, 0.27, 0.36),
		"tree_lit": Vector3(0.90, 0.56, 0.48),
		"sun_x": 0.80,
		"sun_y": 0.47,
		"sun_r": 0.060,
		"glow": 0.85,
		"disc": 1.0,
		"moon": 0.0,
		"stars": 0.3,
		"cloud_size": 1.0,
	},
	{  # Overcast: the sun behind cloud, its glow alone showing.
		"sky_top": Vector3(0.68, 0.75, 0.92),
		"sky_low": Vector3(0.94, 0.91, 0.95),
		"sun_col": Vector3(0.99, 0.98, 0.97),
		"sun_glow": Vector3(0.98, 0.96, 0.92),
		"cloud_lit": Vector3(0.97, 0.97, 0.99),
		"cloud_shade": Vector3(0.72, 0.74, 0.88),
		"range_col": Vector3(0.66, 0.74, 0.90),
		"far_col": Vector3(0.46, 0.64, 0.78),
		"near_col": Vector3(0.42, 0.66, 0.52),
		"meadow_col": Vector3(0.29, 0.56, 0.40),
		"rim_col": Vector3(0.56, 0.76, 0.56),
		"tree_shade": Vector3(0.12, 0.38, 0.40),
		"tree_lit": Vector3(0.52, 0.74, 0.46),
		"sun_x": 0.62,
		"sun_y": 0.62,
		"sun_r": 0.050,
		"glow": 0.30,
		"disc": 0.0,
		"moon": 0.0,
		"stars": 0.0,
		"cloud_size": 1.35,
	},
	{  # Night: a smaller, cooler crescent moon high up, and the stars.
		"sky_top": Vector3(0.19, 0.25, 0.51),
		"sky_low": Vector3(0.44, 0.52, 0.80),
		"sun_col": Vector3(0.92, 0.95, 1.00),
		"sun_glow": Vector3(0.56, 0.66, 1.00),
		"cloud_lit": Vector3(0.62, 0.68, 0.90),
		"cloud_shade": Vector3(0.31, 0.35, 0.62),
		"range_col": Vector3(0.32, 0.38, 0.70),
		"far_col": Vector3(0.24, 0.30, 0.58),
		"near_col": Vector3(0.20, 0.28, 0.53),
		"meadow_col": Vector3(0.13, 0.20, 0.41),
		"rim_col": Vector3(0.34, 0.46, 0.72),
		"tree_shade": Vector3(0.07, 0.11, 0.30),
		"tree_lit": Vector3(0.44, 0.58, 0.86),
		"sun_x": 0.78,
		"sun_y": 0.72,
		"sun_r": 0.030,
		"glow": 0.45,
		"disc": 1.0,
		"moon": 1.0,
		"stars": 1.0,
		"cloud_size": 0.95,
	},
]

## Between hues this close to opposite (radians), the mix goes through red and magenta. Narrow:
## a wider band sent a hill the warm way while the meadow under it went the cool way, an
## orange hill on a teal meadow half way from dusk to morning.
const WARM_ROUTE := 0.2
## Below this chroma a colour has no hue worth keeping; it takes the other colour's.
const GREY_CHROMA := 0.03
## How far each cloud sways about its place, in heights (the shader's SWAY).
const SWAY := 0.045
## How much of the screen the sun's open square is sought in: above this many heights from the
## foot, so the sun or moon stands in the sky, not over the meadow.
const SKY_FLOOR := 0.30
## The open square is sought nearest this point (x as a share of the width, y in heights).
const SUN_TOWARD := Vector2(0.84, 0.60)
## The poplar group's preferred places on the crest, as shares of the width; the seed picks.
const GROVE_AT: Array[float] = [0.30, 0.56, 0.64, 0.44]
## The draw (0 to 1) past which the group has one, two, three and four poplars: none in one map
## in ten, most often two or three.
const GROVE_ODDS: Array[float] = [0.1, 0.25, 0.5, 0.82]


## The look of `mood` (a PaintedBackdrop.Mood).
static func look_of(mood: int) -> Dictionary:
	return MOODS[clampi(mood, 0, MOODS.size() - 1)]


## The look part way, `k`, from `from` to `to`: colours in OKLCH, everything else straight.
static func mix_looks(from: Dictionary, to: Dictionary, k: float) -> Dictionary:
	if k <= 0.0:
		return from
	if k >= 1.0:
		return to
	var mixed := {}
	for key: String in to:
		var a: Variant = from.get(key, to[key])
		if a is Vector3:
			mixed[key] = mix_oklch(a, to[key], k)
		else:
			mixed[key] = lerpf(float(a), float(to[key]), k)
	return mixed


## The sRGB colour `a` mixed `k` of the way to `b` in OKLCH, so the mix keeps its saturation.
static func mix_oklch(a: Vector3, b: Vector3, k: float) -> Vector3:
	var one := to_oklch(a)
	var two := to_oklch(b)
	if one.y < GREY_CHROMA:
		one.z = two.z
	if two.y < GREY_CHROMA:
		two.z = one.z
	var lch := Vector3(lerpf(one.x, two.x, k), lerpf(one.y, two.y, k), _mix_hue(one.z, two.z, k))
	return from_oklch(lch)


## The hue `k` of the way from `from` to `to` (radians): the short way round, except between
## near-opposite hues, where the way through red and magenta (hue 0) is taken, since the other
## way runs through olive.
static func _mix_hue(from: float, to: float, k: float) -> float:
	var start := fposmod(from, TAU)
	var up := fposmod(to - start, TAU)
	var down := TAU - up
	var go_up := up <= down
	if absf(up - down) < WARM_ROUTE:
		go_up = start + up >= TAU
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


## The composition of the map with seed `seed` in a rect of `size` pixels, made way for the
## screen's paper when `layout` is given (null: a placeholder, nothing over it).
static func compose(seed: float, size: Vector2, layout: BackdropLayout) -> Dictionary:
	var aspect := size.x / maxf(size.y, 1.0)
	var ridges := Vector4(
		4.2 + _rand(seed, 1) * TAU,
		1.3 + _rand(seed, 2) * TAU,
		2.4 + _rand(seed, 3) * TAU,
		lerpf(0.06, 0.11, _rand(seed, 4))
	)
	var composition := {"seed": seed, "aspect": aspect, "ridges": ridges}
	# The sun's open square: the largest the paper leaves in the sky, nearest the sun's usual
	# place; none over a placeholder, where the sun stands where its mood puts it.
	var box := Rect2()
	if layout:
		var toward := Vector2(SUN_TOWARD.x * size.x, (1.0 - SUN_TOWARD.y) * size.y)
		box = _to_heights(layout.largest_square(size.y * (1.0 - SKY_FLOOR), toward), size)
	composition["sun_box"] = box
	composition["sun_side"] = 1.0 if _rand(seed, 5) < 0.7 else -1.0
	var sun := sun_of(look_of(0), composition)
	composition["poplars"] = _grove(seed, size, layout)
	composition["clouds"] = _clouds(seed, size, layout, sun)
	return composition


## The composition part way, `k`, from `from` to `to`: the skyline rolls, clouds and poplars
## slide and grow or shrink into their new places.
static func mix_compositions(from: Dictionary, to: Dictionary, k: float) -> Dictionary:
	if k >= 1.0 or from.is_empty():
		return to
	if k <= 0.0:
		return from
	var mixed := to.duplicate()
	mixed["ridges"] = (from.ridges as Vector4).lerp(to.ridges, k)
	for key: String in ["poplars", "clouds"]:
		var shapes: Array[Vector4] = []
		for i in (to[key] as Array).size():
			var a: Vector4 = from[key][i]
			var b: Vector4 = to[key][i]
			# A shape that comes or goes grows or shrinks where it stands.
			if a.y == 0.0 or a.z == 0.0:
				a = Vector4(b.x, b.y if key == "clouds" else 0.0, 0.0 if key == "clouds" else b.z, b.w)
			if b.y == 0.0 or b.z == 0.0:
				b = Vector4(a.x, a.y if key == "clouds" else 0.0, 0.0 if key == "clouds" else a.z, a.w)
			shapes.append(a.lerp(b, k))
		mixed[key] = shapes
	mixed["sun_side"] = lerpf(from.sun_side, to.sun_side, k)
	return mixed


## Where the sun or moon of `look` stands in `composition`, and its radius: Vector3(x, y, r) in
## heights. Its mood's place (on the seed's side), pulled into the open square when there is
## one, and smaller when the square is small.
static func sun_of(look: Dictionary, composition: Dictionary) -> Vector3:
	var aspect: float = composition.aspect
	var share: float = look.sun_x
	if composition.sun_side < 0.0:
		share = 1.0 - share
	var at := Vector2(share * aspect, look.sun_y)
	var radius: float = look.sun_r
	var box: Rect2 = composition.sun_box
	if box.size.x <= 0.0:
		return Vector3(at.x, at.y, radius)
	# The disc and its bloom need about 2.4 radii each way.
	var reach := minf(radius * 2.4, box.size.x * 0.5)
	radius = minf(radius, maxf(reach / 2.4, 0.014))
	at.x = clampf(at.x, box.position.x + reach, box.end.x - reach)
	at.y = clampf(at.y, box.position.y + reach, box.end.y - reach)
	return Vector3(at.x, at.y, radius)


## The shader's uniforms for `look` in `composition` (`seed` for the stars).
static func uniforms(look: Dictionary, composition: Dictionary) -> Dictionary:
	var values := {}
	for key: String in look:
		if look[key] is Vector3:
			values[key] = look[key]
	var sun := sun_of(look, composition)
	values["sun_at"] = Vector4(sun.x, sun.y, sun.z, look.glow)
	values["sun_look"] = Vector2(look.disc, look.moon)
	values["stars"] = look.stars
	values["cloud_size"] = look.cloud_size
	values["seed"] = composition.seed
	values["ridges"] = composition.ridges
	for i in 4:
		values["cloud%d" % i] = composition.clouds[i]
		values["poplar%d" % i] = composition.poplars[i]
	return values


## The near hill's crest at `x` heights from the left (the shader's near_line).
static func near_line(x: float, aspect: float, phase: float) -> float:
	var h := 0.11 + 0.17 * exp(-pow((x - 0.74 * aspect) / 0.5, 2.0)) + 0.012 * _wave(x * 3.0, phase)
	return h + 0.05 * exp(-pow((x - 0.12 * aspect) / 0.3, 2.0))


static func _wave(x: float, phase: float) -> float:
	return 0.55 * sin(x + phase) + 0.3 * sin(x * 2.3 + phase * 1.7) + 0.15 * sin(x * 4.1 + phase * 2.9)


## The poplars: none to four (most often two or three) in a group at a place on the crest the
## seed picks, each its own height and girth; on a screen, the group moves along the crest to
## the nearest stretch the paper leaves open, losing a tree at a time when the stretch is short.
static func _grove(seed: float, size: Vector2, layout: BackdropLayout) -> Array[Vector4]:
	var aspect := size.x / maxf(size.y, 1.0)
	var phase := 2.4 + _rand(seed, 3) * TAU
	var draw := _rand(seed, 10)
	var count := 0
	for odds: float in GROVE_ODDS:
		count += 1 if draw >= odds else 0
	var trees: Array[Vector4] = []
	var offset := 0.0
	for i in count:
		var tall := lerpf(0.085, 0.14, _rand(seed, 20 + i))
		var girth := lerpf(0.017, 0.024, _rand(seed, 30 + i))
		trees.append(Vector4(offset, tall, girth, 0.0))
		offset += lerpf(0.026, 0.040, _rand(seed, 40 + i))
	var start := GROVE_AT[int(_rand(seed, 11) * GROVE_AT.size()) % GROVE_AT.size()] * aspect
	while not trees.is_empty() and layout:
		var found := _open_crest(trees, start, size, phase, layout)
		if not is_nan(found):
			start = found
			break
		trees.pop_back()
	var grove: Array[Vector4] = []
	for i in 4:
		if i < trees.size():
			grove.append(Vector4(start + trees[i].x, trees[i].y, trees[i].z, 0.0))
		else:
			grove.append(Vector4.ZERO)
	return grove


## The nearest place to `start` (heights) where every tree of the group stands clear of the
## paper, or NAN when there is none.
static func _open_crest(
	trees: Array[Vector4], start: float, size: Vector2, phase: float, layout: BackdropLayout
) -> float:
	var aspect := size.x / maxf(size.y, 1.0)
	var step := layout.cell() / size.y
	var span := trees[-1].x
	for n in int(aspect / step) * 2:
		var at := start + (step * ceili(n / 2.0)) * (1.0 if n % 2 == 0 else -1.0)
		if at < 0.02 or at + span > aspect - 0.02:
			continue
		var clear := true
		for tree in trees:
			var x := at + tree.x
			var foot := near_line(x, aspect, phase)
			var rect := Rect2(x - tree.z, foot - 0.02, tree.z * 2.0, tree.y + 0.02)
			if not layout.is_open(_to_pixels(rect, size)):
				clear = false
				break
		if clear:
			return at
	return NAN


## Four clouds spread across the sky at heights and sizes the seed draws; on a screen each
## moves to the nearest open sky clear of the sun, or stays away when there is none.
static func _clouds(seed: float, size: Vector2, layout: BackdropLayout, sun: Vector3) -> Array:
	var aspect := size.x / maxf(size.y, 1.0)
	var clouds: Array[Vector4] = []
	var sun_rect := Rect2(sun.x - sun.z * 2.2, sun.y - sun.z * 2.2, sun.z * 4.4, sun.z * 4.4)
	var order := [0, 2, 1, 3]
	for i in 4:
		var x := (float(order[i]) + 0.2 + 0.6 * _rand(seed, 50 + i)) / 4.0 * aspect
		# High and low clouds in turn.
		var high := i % 2 == 0
		var y := lerpf(0.58 if high else 0.5, 0.9 if high else 0.74, _rand(seed, 60 + i))
		var scale := lerpf(0.17, 0.30, _rand(seed, 70 + i))
		var cloud := Vector4(x, y, scale, _rand(seed, 80 + i))
		if layout:
			cloud = _open_sky(cloud, size, layout, sun_rect)
		clouds.append(cloud)
	return clouds


## `cloud` moved to the nearest place where its base and lower puffs, through its sway and at
## its overcast size, stand clear of the paper, and all of it clear of the sun (up or down
## first, then sideways); or with no width when there is none. Its crown may tuck behind a
## card: a cloud passing behind the screen's paper reads as sky, its base in the band of cards
## as a ghost card.
static func _open_sky(cloud: Vector4, size: Vector2, layout: BackdropLayout, sun: Rect2) -> Vector4:
	var aspect := size.x / maxf(size.y, 1.0)
	var s := cloud.z * 1.15
	for dx: float in [0.0, -0.12, 0.12, -0.24, 0.24, -0.36, 0.36]:
		for n in 13:
			var dy := 0.03 * ceili(n / 2.0) * (1.0 if n % 2 == 0 else -1.0)
			var x := cloud.x + dx * aspect
			var y := cloud.y + dy
			if y < 0.44 or y + 0.62 * s > 1.0:
				continue
			var whole := Rect2(x - 0.85 * s - SWAY, y - 0.14 * s, 1.8 * s + 2.0 * SWAY, 0.76 * s)
			if whole.intersects(sun):
				continue
			var base := Rect2(whole.position, Vector2(whole.size.x, 0.36 * s))
			if layout.is_open(_to_pixels(base, size)):
				return Vector4(x, y, cloud.z, cloud.w)
	return Vector4(cloud.x, cloud.y, 0.0, cloud.w)


## A rect in heights (y up from the foot) as pixels (y down from the top).
static func _to_pixels(rect: Rect2, size: Vector2) -> Rect2:
	var h := size.y
	return Rect2(rect.position.x * h, (1.0 - rect.end.y) * h, rect.size.x * h, rect.size.y * h)


## A rect in pixels as heights.
static func _to_heights(rect: Rect2, size: Vector2) -> Rect2:
	var h := maxf(size.y, 1.0)
	if rect.size.x <= 0.0:
		return Rect2()
	return Rect2(rect.position.x / h, 1.0 - rect.end.y / h, rect.size.x / h, rect.size.y / h)


## A stable draw in [0, 1) for the seed's `index`th choice.
static func _rand(seed: float, index: int) -> float:
	return fposmod(sin(seed * 12.9898 * 57.0 + float(index) * 78.233) * 43758.5453, 1.0)
