class_name PainterTuftAtlas
extends RefCounted

## The painted grass tuft's dab layouts, drawn once into a texture array.
##
## A wide grass tuft's card is cut not by its texture's blades but by four round dabs laid as a
## mound (painter_selector's tuft_dab reads it; docs/systems/painter.md "Tufts"). The dabs used to
## be laid and tested per fragment, from flat per-card varyings, in vector arithmetic: the shader
## then cost 0.10 to 0.12 ms more at the village's home view even with the test skipped at run
## time (the code's presence alone; card painter-cost-stripes), and the varyings another 0.05 in
## winter. So the layouts are drawn here instead, LAYERS of them, each a SIZE x SIZE layer over
## the card's UV (u across, v down as core's tuft cards have it), and the shader reads one layer
## per card: one fetch and a comparison, the shape of the tip's texture cut.
##
## A texel holds, linear (no colour hint):
## - r: the cut as a distance field, 0.5 on the outline (a dab's brushed rim, or the body under
##   the dabs' centres), so the outline is sharp at any size;
## - g: the hash of the dab that draws it (its value and variant);
## - b, a: the point's height and offset across in that dab, in dab radii, as
##   (x + RANGE) / (2 RANGE) (the snow cap's crescent reads them; the body's texels carry the
##   bottom, so it takes no cap).
## The layouts depend on the tuft's aspect (its half width in tuft heights), so one array is made
## per aspect, kept for the process. Core's meadow tufts come in 13 aspects from 0.75 to 1.8, so
## the aspect is rounded to a power of ASPECT_RATIO over WIDE (4 arrays, about 30 ms each on the
## first painted look; a dab is at most 16 percent out of round on the card).

const LAYERS := 16
const SIZE := 32
const RANGE := 1.5
const ASPECT_RATIO := 1.35
## painter_selector's TUFT_WIDE: a tuft this many of its heights across or more is cut by dabs.
const WIDE := 0.7

## The dabs' across positions (in dab-row units), as the shader had them.
const ROW: Array[float] = [-0.75, -0.25, 0.25, 0.75]

static var _cache: Dictionary = {}


## The half width in tuft heights the shader reads for a tuft of `extent` (its mesh's half size)
## and `height` (painter_selector's tuft_half_w).
static func half_width(extent: Vector3, height: float) -> float:
	return minf(maxf(extent.x, extent.z) / maxf(height, 0.01), 2.5)


## The layouts' array a grass tuft of `extent` and `height` is cut by, or null when it is too
## narrow for dabs (painter_selector's tuft_wide: a reed keeps its texture's cut).
static func for_tuft(extent: Vector3, height: float) -> Texture2DArray:
	var half_w := half_width(extent, height)
	return atlas(half_w) if half_w >= WIDE else null


## The half width the array for `half_w` is drawn at (rounded to a power of ASPECT_RATIO over WIDE).
static func drawn_width(half_w: float) -> float:
	var step := roundf(log(maxf(half_w, WIDE) / WIDE) / log(ASPECT_RATIO))
	return WIDE * pow(ASPECT_RATIO, step)


## The layouts' array for a tuft of half width `half_w` (tuft heights), made on first use.
static func atlas(half_w: float) -> Texture2DArray:
	var drawn := drawn_width(half_w)
	var key := int(roundf(drawn * 1000.0))
	if _cache.has(key):
		return _cache[key]
	# The baked file when there is one (PainterBaked), else drawn here.
	var array := PainterBaked.load_array(PainterBaked.tuft_name(drawn))
	if array == null:
		array = Texture2DArray.new()
		array.create_from_images(images(drawn))
	_cache[key] = array
	return array


## The half widths an array is drawn at: WIDE times ASPECT_RATIO to a step, for the steps a tuft
## of half width WIDE up to the widest the shader reads (2.5 tuft heights, half_width) rounds to.
static func drawn_widths() -> Array[float]:
	var out: Array[float] = []
	var steps := int(roundf(log(2.5 / WIDE) / log(ASPECT_RATIO)))
	for step in steps + 1:
		out.append(WIDE * pow(ASPECT_RATIO, float(step)))
	return out


## The LAYERS layout images of an array drawn at half width `drawn` (pure).
static func images(drawn: float) -> Array[Image]:
	var out: Array[Image] = []
	for layer in LAYERS:
		out.append(layer_image(drawn, layer))
	return out


## One layout's dabs for `layer`: [x, y, inverse radius, hash] each, in tuft heights.
static func dabs(half_w: float, layer: int) -> Array[Vector4]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (layer + 1)
	var w := half_w * 0.8
	var out: Array[Vector4] = []
	for u: float in ROW:
		var hk := rng.randf()
		var hk2 := rng.randf()
		var x := (u + (hk - 0.5) * 0.2) * w
		var y := 0.58 - 0.32 * u * u + (hk2 - 0.5) * 0.12
		out.append(Vector4(x, y, 1.0 / (0.29 + 0.12 * hk2), rng.randf()))
	return out


## The SIZE x SIZE RGBA8 image (with mipmaps) of `layer`'s layout for a tuft of half width `half_w`.
static func layer_image(half_w: float, layer: int) -> Image:
	var layout := dabs(half_w, layer)
	var w := half_w * 0.8
	# A texel's size in tuft heights (the wider axis), so the field ramps over about two texels.
	var ramp := float(SIZE) / (2.0 * maxf(1.0, 2.0 * half_w))
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	for row in SIZE:
		var py := 1.0 - (float(row) + 0.5) / float(SIZE)
		for col in SIZE:
			var px := ((float(col) + 0.5) / float(SIZE) - 0.5) * 2.0 * half_w
			# The field (tuft heights inside the outline), and the drawing dab: the highest one over
			# the point (the middle ones lie over the outer ones), else the nearest.
			var field := -1.0e9
			var best := -1.0
			var own := Vector3(layout[1].w, -RANGE, 0.0)
			var near := Vector3.ZERO
			for dab: Vector4 in layout:
				var ax := (px - dab.x) * dab.z
				var ay := (py - dab.y) * dab.z
				# The brushed rim: the edge wavers round its circle (a triangle wave).
				var t := ax * 0.55 + ay * 0.4 + dab.w * 3.0
				var rim := 1.0 + 0.3 * (absf(t - floorf(t) - 0.5) - 0.25)
				var inside := (rim - sqrt(ax * ax + ay * ay)) / dab.z
				if inside > field:
					field = inside
					near = Vector3(dab.w, ay, ax)
				if inside > 0.0 and dab.y > best:
					best = dab.y
					own = Vector3(dab.w, ay, ax)
			# The body under the dabs' centres, so no gap opens between their feet: it takes no cap.
			var body := minf(0.42 - 0.5 * (px / w) * (px / w) - py, py + 0.05)
			if best < 0.0 and body <= field:
				own = near
			field = maxf(field, body)
			var i := (row * SIZE + col) * 4
			data[i] = int(clampf(0.5 + field * ramp, 0.0, 1.0) * 255.0 + 0.5)
			data[i + 1] = int(clampf(own.x, 0.0, 1.0) * 255.0 + 0.5)
			data[i + 2] = int(clampf((own.y + RANGE) / (2.0 * RANGE), 0.0, 1.0) * 255.0 + 0.5)
			data[i + 3] = int(clampf((own.z + RANGE) / (2.0 * RANGE), 0.0, 1.0) * 255.0 + 0.5)
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return image
