class_name GroundBroadTint
extends RefCounted

## The broad edge's one-map tint (ground layers card G4; the shader's BROAD EDGE): the second
## scale of the ground's two-scale edge, a soft recolouring a few metres wide that lets a
## biome's ground fade into its neighbour's side of the border and seats a trampled path in
## the ground around it. Pure rules plus a cached colour lookup; GroundLayerBinding binds it.
##
## The tinted components are the biome grounds (a biome drawn as the base is not one) and the
## painted surfaces of role built (the trodden fringe, P3-6). Each has a mean colour (the last
## mip of its albedo, linear) and a weight: a biome ground 1, a built surface TRAMPLE_WEIGHT.
## Per sample the tint plane holds their sum premultiplied: rgb = sum(weight x coverage x
## colour), a = sum(weight x coverage), the coverage being the biome's density or the painted
## entry's weight. broad_image() box-filters the plane by BROAD_FACTOR (3.5 m per texel at the
## default 0.25 m step) into one RGBA half-float map the shader reads with a cubic B-spline,
## one fetch whatever the number of components (the slot table's form needed two maps and
## stopped at eight slots). Stored premultiplied, the filter averages colours by their
## coverage, and rgb / a is the strength-weighted mean colour of the texel.
##
## The shader then takes away the pixel's own components (tint_at() is its CPU twin): each of
## the pixel's biome corners and painted built entries removes its weight x
## smoothstep(OWN_START, OWN_END, its fine weight) from a and that times its colour from rgb.
## What is left is what this pixel is not; the pixel recolours toward its mean colour by
## STRENGTH x smoothstep(0, FULL, what is left). So a biome tints the base beside it (its own
## pixels cancel themselves), a path tints the forest it crosses (the forest cancels itself,
## the path is left), and where two fully painted biomes meet both sides cancel: a border
## between biomes is the fine frayed edge alone, with no cream cast of one ground on another.
## Painted weight wins, as everywhere in the ground: the tint is the automatic ground's, so it
## fades out by smoothstep(OWN_START, OWN_END, the pixel's painted total) and a painted stroke
## keeps its colour (snow painted beside the taiga stays white; under the slot table the
## taiga's halo, recoloured by the snow's luminance, cast it cream). On a single biome against
## unpainted base this is the slot table's halo, unchanged.

## Samples per broad texel on each axis: 3.5 m at the default 0.25 m step. Chosen from game
## camera renders; 8 (2 m) left the gradient too narrow to read.
const BROAD_FACTOR := 14
## A painted built surface's tint weight against a biome ground's 1. The slot table tinted a
## path's fringe at 0.35 against a biome's 0.8 with its own smoothstep; in one map the two
## share the curve, and 0.55 keeps the fringe's gradient within a few percent of the old one
## where the path's broad weight is under 0.3 (its outer half), a little stronger at the path.
const TRAMPLE_WEIGHT := 0.55
## Fine weight over which a pixel's own component cancels its share of the tint (the shader's
## BROAD_OWN_START / BROAD_OWN_END: the slot table's fade, kept).
const OWN_START := 0.2
const OWN_END := 0.8
## The shader's defaults for biome_broad_strength and biome_broad_full (tint_at()).
const STRENGTH := 0.8
const FULL := 0.4
## Values per sample in the tint plane.
const CHANNELS := 4

static var _colors: Dictionary = {}


## Mean colour of palette surface `surface` at `root` (GroundPalette.surface_mean_albedo, the
## last mip the shader's textureLod reads), converted to linear, black when it has none.
## Cached per palette and surface: decompressing a map costs about 10 ms.
static func mean_color(surface: String, root: String) -> Color:
	var key := root + "|" + surface
	if not _colors.has(key):
		var mean: Variant = GroundPalette.surface_mean_albedo(surface, root)
		_colors[key] = (mean as Color).srgb_to_linear() if mean is Color else Color.BLACK
	return _colors[key]


## The tint of a component drawn as `surface` with weight `weight`: Color(linear mean rgb,
## weight), or Color(0, 0, 0, 0) for no surface or no weight. `color_of` maps a surface to its
## mean colour (mean_color()).
static func component(surface: String, weight: float, color_of: Callable) -> Color:
	if surface == "" or weight <= 0.0:
		return Color(0, 0, 0, 0)
	var c: Color = color_of.call(surface)
	return Color(c.r, c.g, c.b, weight)


## The tint plane's floats for the samples of `rect` (sample coordinates, clipped to the grid
## by the caller), row-major, CHANNELS per sample (see the header). `biome_tints` is indexed by
## biome slot (0, no biome, and any slot past its end untinted), `paint_tints` by document
## surface index; each entry is component()'s Color. Masks shorter than the grid read as
## unpainted.
static func tint_plane(
	doc: MapDocument, biome_tints: PackedColorArray, paint_tints: PackedColorArray, rect: Rect2i
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(rect.size.x * rect.size.y * CHANNELS)
	var samples_x := doc.samples_x()
	var slots := doc.biome_slots
	var density := doc.biome_density
	var biome_count := mini(slots.size(), density.size())
	var weights := doc.surface_weights
	var paints := doc.has_surface_entries() and not paint_tints.is_empty()
	var plane := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var o := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * samples_x
		for x in range(rect.position.x, rect.end.x):
			var i := row + x
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			if i < biome_count:
				var slot := slots[i]
				if slot > 0 and slot < biome_tints.size() and density[i] > 0:
					var t := biome_tints[slot]
					var w := t.a * density[i] / 255.0
					r += t.r * w
					g += t.g * w
					b += t.b * w
					a += w
			if paints:
				for e in MapDocument.SURFACE_ENTRIES:
					var value := weights[plane + i * MapDocument.SURFACE_CHANNELS + e]
					if value == 0:
						break
					var s := weights[i * MapDocument.SURFACE_CHANNELS + e]
					if s >= paint_tints.size():
						continue
					var t := paint_tints[s]
					var w := t.a * value / 255.0
					r += t.r * w
					g += t.g * w
					b += t.b * w
					a += w
			out[o] = r
			out[o + 1] = g
			out[o + 2] = b
			out[o + 3] = a
			o += CHANNELS
	return out


## The plane's floats for `size` samples as an RGBAF image (the CPU mirror).
static func plane_image(size: Vector2i, plane: PackedFloat32Array) -> Image:
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, plane.to_byte_array())


## The broad tint map of the mirror `plane_img` (one texel per sample): box-filtered down by
## BROAD_FACTOR in native code (Image.resize with trilinear filtering averages the mip chain,
## so a stroke can refresh it every frame), as RGBA half floats (linear filtering of half
## floats is universal; of 32-bit floats it is not). Never empty: at least 1 x 1.
static func broad_image(plane_img: Image) -> Image:
	var broad := plane_img.duplicate() as Image
	var size := broad_size(plane_img.get_size())
	broad.resize(size.x, size.y, Image.INTERPOLATE_TRILINEAR)
	broad.convert(Image.FORMAT_RGBAH)
	return broad


## Size of broad_image() for a mirror of `samples` texels.
static func broad_size(samples: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(1, ceili(float(samples.x) / BROAD_FACTOR)),
		maxi(1, ceili(float(samples.y) / BROAD_FACTOR))
	)


## The shader's broad edge at one pixel (apply_broad_edge's CPU twin, at the default strength):
## `broad` the filtered texel (premultiplied rgb, weight a), `own` the pixel's own components
## (component() Colors) and `fines` their fine weights, `painted` the pixel's painted total.
## Returns Color(target rgb, tint): the mean colour the pixel recolours toward and by how much
## (0: none).
static func tint_at(
	broad: Color, own: PackedColorArray, fines: PackedFloat32Array, painted: float = 0.0
) -> Color:
	var r := broad.r
	var g := broad.g
	var b := broad.b
	var left := broad.a
	for k in mini(own.size(), fines.size()):
		var shown := own[k].a * smoothstep(OWN_START, OWN_END, fines[k])
		r -= own[k].r * shown
		g -= own[k].g * shown
		b -= own[k].b * shown
		left -= shown
	if left <= 0.002:
		return Color(0, 0, 0, 0)
	var target := Color(
		clampf(r / left, 0.0, 1.0), clampf(g / left, 0.0, 1.0), clampf(b / left, 0.0, 1.0)
	)
	var hold := 1.0 - smoothstep(OWN_START, OWN_END, painted)
	return Color(target.r, target.g, target.b, STRENGTH * smoothstep(0.0, FULL, left) * hold)
