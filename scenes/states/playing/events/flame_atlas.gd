class_name FlameAtlas
extends RefCounted

## The painted flame a fire's tongues are drawn with (EventPuffs' flame kind,
## shaders/event_puff.gdshader): a small flipbook of FRAMES frames side by side, painted once at
## the first fire and kept for the session. Each frame is one flame of three tongues (a tall
## middle one and two shorter ones beside it) laid in three flat bands with soft edges, the way
## a painter lays a flame in: a red rim, an amber body and a pale gold core, each band its own
## silhouette nested in the last, so a flame reads as a few bold shapes at tabletop zoom rather
## than a gradient. Frame to frame the tongues lean and stretch on offset phases; the shader
## cross-fades the frames on its clock, so a flame licks with no per-frame work.
##
## Red holds the heat (the shader's colour ramp: about 0.12 the rim, 0.57 amber, 1 the core),
## green the coverage (the rim band's silhouette). Row 0 holds the tips.
##
## Cost: FRAMES * SIZE pixels painted once, each tongue's width worked out per row, not per
## pixel.

const FRAMES := 4
const SIZE := Vector2i(48, 96)
## Per band (rim, amber, core): its tongues' height and width as shares of the rim's, and how
## far up its foot starts (a share of the frame's height).
const BAND_TALL: Array[float] = [1.0, 0.72, 0.45]
const BAND_WIDE: Array[float] = [1.0, 0.72, 0.5]
const BAND_FOOT: Array[float] = [0.0, 0.04, 0.08]
## Per tongue (middle, left, right): where it stands across (-1..1), its foot (a share of the
## height), its height and its width.
const TONGUE_X: Array[float] = [0.0, -0.4, 0.36]
const TONGUE_FOOT: Array[float] = [0.0, 0.1, 0.06]
const TONGUE_TALL: Array[float] = [0.95, 0.6, 0.7]
const TONGUE_WIDE: Array[float] = [0.6, 0.34, 0.36]
## How far a tongue's tip leans and how much its height breathes, frame to frame.
const LEAN := 0.22
const BREATHE := 0.1
## A band's soft edge inside and outside its silhouette (in the -1..1 units across).
const EDGE := Vector2(0.06, 0.02)
## The heat of the rim band and what the amber and core bands add to it.
const HEAT := Vector3(0.12, 0.45, 0.43)

static var _texture: ImageTexture = null


## The flipbook, painted on the first call.
static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(paint())
	return _texture


## The flipbook's image: FORMAT_RG8, FRAMES * SIZE.x by SIZE.y (see the header). Pure.
static func paint() -> Image:
	var width := SIZE.x * FRAMES
	# Two bytes a pixel (heat, coverage), written straight into the image's data.
	var data := PackedByteArray()
	data.resize(width * SIZE.y * 2)
	# One row's tongues, per band then tongue: the centre across and the half width (0: none).
	var centres := PackedFloat32Array()
	var halves := PackedFloat32Array()
	centres.resize(9)
	halves.resize(9)
	for frame in FRAMES:
		var phase := TAU * float(frame) / float(FRAMES)
		for y in SIZE.y:
			var rise := 1.0 - (float(y) + 0.5) / float(SIZE.y)
			for band in 3:
				for i in 3:
					var k := band * 3 + i
					var tall := TONGUE_TALL[i] * BAND_TALL[band] * (1.0 + BREATHE * sin(phase + i * 2.1))
					var r := (rise - TONGUE_FOOT[i] - BAND_FOOT[band]) / tall
					halves[k] = 0.0
					if r <= 0.0 or r >= 1.0:
						continue
					var lean := LEAN * sin(phase + i * 1.7) * r * r
					centres[k] = TONGUE_X[i] * BAND_WIDE[band] + lean
					# Round at the foot, drawn to a point at the tip.
					halves[k] = TONGUE_WIDE[i] * BAND_WIDE[band] * 1.7 * sqrt(r) * pow(1.0 - r, 0.85)
			for x in SIZE.x:
				var u := (float(x) + 0.5) / float(SIZE.x) * 2.0 - 1.0
				var rim := _band(u, centres, halves, 0)
				var heat := HEAT.x + HEAT.y * _band(u, centres, halves, 3)
				heat += HEAT.z * _band(u, centres, halves, 6)
				var at := (y * width + frame * SIZE.x + x) * 2
				data[at] = roundi(clampf(heat, 0.0, 1.0) * 255.0)
				data[at + 1] = roundi(rim * 255.0)
	return Image.create_from_data(width, SIZE.y, false, Image.FORMAT_RG8, data)


## How much of the band whose tongues start at `first` covers `u` (0..1).
static func _band(
	u: float, centres: PackedFloat32Array, halves: PackedFloat32Array, first: int
) -> float:
	var cover := 0.0
	for k in range(first, first + 3):
		var half := halves[k]
		if half > 0.0:
			var away := absf(u - centres[k])
			cover = maxf(cover, 1.0 - smoothstep(half - EDGE.x, half + EDGE.y, away))
	return cover
