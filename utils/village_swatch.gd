class_name VillageSwatch
extends RefCounted

## The picture on a Village tool character tile: a small painted vignette of that character's
## plaza. The kit's own plaza paving (its Paint tile thumbnail) is a disc seen a little from the
## side, lying on a ground colour of the kit's own (meadow green for the farming hamlet, warm
## ochre for the market town, harbour blue, heather slate for the hill fort village, a cool
## mid-century mint for the modern town), with one signature piece standing on it: a well, a
## striped stall, barrels, a lamp, a red phone box. The ground colours sit far apart so the five
## tiles read apart at a glance even where two kits pave alike; the
## paving still says what the ground will be. Painted pixel by pixel with soft edges from a list
## of flat shapes (layers); every function here is pure.
##
## The same paving thumbnail gives the brush its flat preview tint (paving_color): the average
## colour of the kit's plaza surface.

## Each kit's ground colour and piece. A kit not listed paints as the market town.
const LOOKS := {
	"farming_hamlet": {"ground": Color(0.46, 0.66, 0.3), "piece": &"well"},
	"market_town": {"ground": Color(0.9, 0.6, 0.24), "piece": &"stall"},
	"harbour_town": {"ground": Color(0.22, 0.52, 0.74), "piece": &"barrels"},
	"hill_fort_village": {"ground": Color(0.46, 0.42, 0.6), "piece": &"lamp"},
	"modern_town": {"ground": Color(0.5, 0.78, 0.72), "piece": &"phone_box"},
}
## The paving disc in the picture's unit square: its centre and half axes (wider than tall, a
## plaza seen from the tabletop camera's height).
const DISC_CENTRE := Vector2(0.5, 0.58)
const DISC_RADII := Vector2(0.4, 0.31)
const SHADE := Color(0.1, 0.08, 0.12, 0.32)
const INK := Color(0.16, 0.12, 0.1, 0.55)
const STONE := Color(0.7, 0.67, 0.62)
const WATER := Color(0.13, 0.3, 0.44)
const WOOD := Color(0.52, 0.33, 0.18)
const WOOD_LIGHT := Color(0.7, 0.5, 0.3)
const ROOF := Color(0.66, 0.27, 0.18)
const AWNING := Color(0.86, 0.2, 0.22)
const CREAM := Color(0.98, 0.93, 0.8)
const POST := Color(0.22, 0.2, 0.22)
const LAMP_LIGHT := Color(1.0, 0.86, 0.42)
## The phone box: pillar-box red with a deeper cap and pale glazing.
const BOX_RED := Color(0.84, 0.16, 0.14)
const BOX_RED_DARK := Color(0.6, 0.1, 0.1)
const GLAZING := Color(0.86, 0.93, 0.92)
## Field tiles: each kind's disc colour, and the colours drawn on it.
const FIELD_DISC := {
	"crops": Color(0.6, 0.38, 0.2),
	"orchard": Color(0.64, 0.78, 0.32),
	"garden": Color(0.56, 0.74, 0.34),
}
const CROP_GOLD := Color(0.96, 0.8, 0.36)
const EARTH_DARK := Color(0.45, 0.28, 0.16)
const CANOPY := Color(0.24, 0.5, 0.22)
const CANOPY_LIGHT := Color(0.44, 0.7, 0.3)
const FLOWERS: Array[Color] = [
	Color(0.92, 0.42, 0.62), Color(0.62, 0.48, 0.9), Color(1.0, 0.86, 0.4)
]

## The average colour of each (palette root, kit) plaza surface, read once.
static var _paving: Dictionary = {}


## The tile picture of kit `kit` at `size` pixels, its paving from the surfaces of palette `root`
## (a surface the palette lacks paints as the swatch fallback grey, SwatchTextures).
static func kit_texture(kit: String, root: String, size: int) -> Texture2D:
	return ImageTexture.create_from_image(vignette(kit, _plaza_image(kit, root, size)))


## The vignette of kit `kit` over `paving` (a square image, the picture's size): the kit's
## ground, the disc of `paving` with a soft shadow and keyline, and the kit's piece on it.
static func vignette(kit: String, paving: Image) -> Image:
	var side := paving.get_width()
	var look: Dictionary = LOOKS.get(kit, LOOKS["market_town"])
	var ground: Color = look["ground"]
	var layers := piece_layers(StringName(look["piece"]))
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var px := 1.0 / side
	for y in side:
		for x in side:
			var uv := Vector2((x + 0.5) * px, (y + 0.5) * px)
			# The ground: lighter towards the top, a little darker in the corners.
			var color := ground.lightened(0.18 * (1.0 - uv.y)).darkened(
				0.22 * maxf(uv.distance_to(Vector2(0.5, 0.5)) - 0.45, 0.0) * 2.0
			)
			color = _over(color, SHADE, _ellipse(uv, DISC_CENTRE + Vector2(0.0, 0.035), DISC_RADII, px))
			var on_disc := _ellipse(uv, DISC_CENTRE, DISC_RADII, px)
			color = color.lerp(paving.get_pixel(x, y), on_disc)
			var rim := _ellipse(uv, DISC_CENTRE, DISC_RADII, px)
			rim -= _ellipse(uv, DISC_CENTRE, DISC_RADII - Vector2(px, px) * 1.4, px)
			color = _over(color, INK, maxf(rim, 0.0))
			for layer in layers:
				color = _over(color, _layer_color(layer, uv), _coverage(layer, uv, px))
			color.a = 1.0
			out.set_pixel(x, y, color)
	return out


## The flat shapes of piece `piece` in the unit square, back to front: each
## `{"kind": &"ellipse" or &"rect", "c": centre, "r": half size, "color"}`, a rect optionally with
## `"stripes": n` and `"alt": Color` (vertical bands alternating with `color`).
static func piece_layers(piece: StringName) -> Array[Dictionary]:
	var c := DISC_CENTRE
	var out: Array[Dictionary] = []
	match piece:
		&"well":
			out.append(_shape(&"ellipse", c + Vector2(0.03, 0.05), Vector2(0.15, 0.08), SHADE))
			out.append(_shape(&"rect", c + Vector2(-0.11, -0.12), Vector2(0.018, 0.13), WOOD))
			out.append(_shape(&"rect", c + Vector2(0.11, -0.12), Vector2(0.018, 0.13), WOOD))
			out.append(_shape(&"ellipse", c, Vector2(0.14, 0.09), STONE))
			out.append(_shape(&"ellipse", c + Vector2(0.0, -0.01), Vector2(0.09, 0.05), WATER))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.26), Vector2(0.17, 0.045), ROOF))
		&"stall":
			out.append(_shape(&"ellipse", c + Vector2(0.03, 0.09), Vector2(0.22, 0.07), SHADE))
			out.append(_shape(&"rect", c + Vector2(-0.17, -0.08), Vector2(0.016, 0.14), WOOD))
			out.append(_shape(&"rect", c + Vector2(0.17, -0.08), Vector2(0.016, 0.14), WOOD))
			out.append(_shape(&"rect", c + Vector2(0.0, 0.03), Vector2(0.19, 0.06), WOOD_LIGHT))
			var awning := _shape(&"rect", c + Vector2(0.0, -0.2), Vector2(0.23, 0.075), AWNING)
			awning["stripes"] = 5
			awning["alt"] = CREAM
			out.append(awning)
		&"barrels":
			out.append(_shape(&"ellipse", c + Vector2(0.03, 0.08), Vector2(0.24, 0.07), SHADE))
			out.append(_shape(&"rect", c + Vector2(0.12, -0.02), Vector2(0.09, 0.08), WOOD_LIGHT))
			for dx in [-0.14, 0.0]:
				out.append(_shape(&"rect", c + Vector2(dx, -0.03), Vector2(0.065, 0.09), WOOD))
				out.append(_shape(&"ellipse", c + Vector2(dx, -0.12), Vector2(0.065, 0.03), WOOD_LIGHT))
				out.append(_shape(&"rect", c + Vector2(dx, -0.02), Vector2(0.065, 0.012), POST))
		&"lamp":
			out.append(_shape(&"ellipse", c + Vector2(0.0, -0.3), Vector2(0.2, 0.17), _a(LAMP_LIGHT, 0.4)))
			out.append(_shape(&"ellipse", c + Vector2(0.04, 0.05), Vector2(0.1, 0.04), SHADE))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.12), Vector2(0.018, 0.17), POST))
			out.append(_shape(&"rect", c + Vector2(0.0, 0.04), Vector2(0.05, 0.02), POST))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.3), Vector2(0.05, 0.055), LAMP_LIGHT))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.37), Vector2(0.065, 0.016), POST))
		&"phone_box":
			out.append(_shape(&"ellipse", c + Vector2(0.05, 0.06), Vector2(0.15, 0.05), SHADE))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.14), Vector2(0.085, 0.2), BOX_RED))
			for row in 3:
				for dx in [-0.034, 0.034]:
					var pane := c + Vector2(dx, -0.22 + row * 0.075)
					out.append(_shape(&"rect", pane, Vector2(0.024, 0.03), GLAZING))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.3), Vector2(0.068, 0.016), CREAM))
			out.append(_shape(&"rect", c + Vector2(0.0, -0.355), Vector2(0.1, 0.03), BOX_RED_DARK))
			out.append(_shape(&"ellipse", c + Vector2(0.0, -0.39), Vector2(0.05, 0.026), BOX_RED_DARK))
	return out


## The flat preview colour of kit `kit`'s plaza paving in palette `root`: its surface's average.
static func paving_color(kit: String, root: String) -> Color:
	var key := "%s|%s" % [root, kit]
	if not _paving.has(key):
		var image := _plaza_image(kit, root, 16)
		image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		var color := image.get_pixel(0, 0)
		color.a = 1.0
		_paving[key] = color
	return _paving[key]


static func _plaza_image(kit: String, root: String, size: int) -> Image:
	var surface := str(VillagePlazas.ground_of(kit).get("plaza", ""))
	var albedo := str(PaletteLibrary.surfaces(root).get(surface, {}).get("albedo", ""))
	var image := SwatchTextures.palette_thumbnail(albedo, size, root).get_image()
	image = image.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return image


static func _shape(kind: StringName, c: Vector2, r: Vector2, color: Color) -> Dictionary:
	return {"kind": kind, "c": c, "r": r, "color": color}


## The colour of `layer` at `uv`: its own, or on a striped rect the band's.
static func _layer_color(layer: Dictionary, uv: Vector2) -> Color:
	if not layer.has("stripes"):
		return layer["color"]
	var c: Vector2 = layer["c"]
	var r: Vector2 = layer["r"]
	var band := floori((uv.x - c.x + r.x) / (2.0 * r.x) * int(layer["stripes"]))
	return layer["color"] if band % 2 == 0 else layer["alt"]


## The picture on a field-kind tile (topic fields) at `size` pixels: the same meadow and disc as a
## character's vignette, the disc painted as the kind lays it: tilled earth with gold rows (crops),
## warm grass with round fruit trees (orchard), grass with two flowering beds (garden).
static func field_texture(kind: String, size: int) -> Texture2D:
	return ImageTexture.create_from_image(field_image(kind, size))


## field_texture's image. Pure.
static func field_image(kind: String, size: int) -> Image:
	var disc: Color = FIELD_DISC.get(kind, FIELD_DISC["orchard"])
	var layers := field_layers(kind)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var px := 1.0 / size
	var meadow: Color = LOOKS["farming_hamlet"]["ground"]
	for y in size:
		for x in size:
			var uv := Vector2((x + 0.5) * px, (y + 0.5) * px)
			var color := meadow.lightened(0.18 * (1.0 - uv.y))
			color = _over(color, SHADE, _ellipse(uv, DISC_CENTRE + Vector2(0.0, 0.035), DISC_RADII, px))
			var on_disc := _ellipse(uv, DISC_CENTRE, DISC_RADII, px)
			color = color.lerp(disc, on_disc)
			for layer in layers:
				var amount := _coverage(layer, uv, px)
				if layer.get("clip", false):
					amount *= on_disc
				color = _over(color, layer["color"], amount)
			color.a = 1.0
			out.set_pixel(x, y, color)
	return out


## The shapes over a field kind's disc, back to front (`"clip"` keeps a shape on the disc).
static func field_layers(kind: String) -> Array[Dictionary]:
	var c := DISC_CENTRE
	var out: Array[Dictionary] = []
	match kind:
		"crops":
			for k in 4:
				var row := _shape(&"rect", c + Vector2(0.0, -0.21 + k * 0.14), Vector2(0.4, 0.035), CROP_GOLD)
				row["clip"] = true
				out.append(row)
			out.append(_shape(&"rect", c + Vector2(0.06, -0.1), Vector2(0.012, 0.13), WOOD))
			out.append(_shape(&"rect", c + Vector2(0.06, -0.15), Vector2(0.07, 0.012), WOOD))
			out.append(_shape(&"ellipse", c + Vector2(0.06, -0.21), Vector2(0.035, 0.035), CROP_GOLD))
		"garden":
			for k in 2:
				var at := c + Vector2(0.0, -0.08 + k * 0.17)
				out.append(_shape(&"ellipse", at, Vector2(0.27, 0.06), EARTH_DARK))
				for n in 5:
					var bloom := FLOWERS[(k + n) % FLOWERS.size()]
					var spot := at + Vector2(-0.2 + n * 0.1, -0.02)
					out.append(_shape(&"ellipse", spot, Vector2(0.04, 0.035), bloom))
			out.append(_shape(&"ellipse", c + Vector2(0.33, -0.12), Vector2(0.08, 0.08), CANOPY))
		_:
			for k in 5:
				var x := -0.2 + float(k % 3) * 0.2 + (0.1 if k >= 3 else 0.0)
				var at := c + Vector2(x, -0.13 + floorf(k / 3.0) * 0.17)
				out.append(_shape(&"ellipse", at + Vector2(0.0, 0.05), Vector2(0.075, 0.03), SHADE))
				out.append(_shape(&"ellipse", at, Vector2(0.085, 0.08), CANOPY))
				out.append(_shape(&"ellipse", at + Vector2(-0.025, -0.03), Vector2(0.035, 0.03), CANOPY_LIGHT))
				out.append(_shape(&"ellipse", at + Vector2(0.03, 0.01), Vector2(0.016, 0.016), AWNING))
	return out


## How much of the pixel at `uv` (pixels `px` wide) `layer` covers, 0 to 1.
static func _coverage(layer: Dictionary, uv: Vector2, px: float) -> float:
	var c: Vector2 = layer["c"]
	var r: Vector2 = layer["r"]
	if layer["kind"] == &"ellipse":
		return _ellipse(uv, c, r, px)
	var d := (uv - c).abs()
	return clampf((r.x - d.x) / px + 0.5, 0.0, 1.0) * clampf((r.y - d.y) / px + 0.5, 0.0, 1.0)


## The coverage of an ellipse (centre `c`, half axes `r`) at `uv`, soft over about a pixel.
static func _ellipse(uv: Vector2, c: Vector2, r: Vector2, px: float) -> float:
	var reach := ((uv - c) / r).length()
	return clampf((1.0 - reach) * minf(r.x, r.y) / px + 0.5, 0.0, 1.0)


## `paint` over `base` with `amount` of its alpha.
static func _over(base: Color, paint: Color, amount: float) -> Color:
	return base.lerp(Color(paint.r, paint.g, paint.b), paint.a * amount) if amount > 0.0 else base


static func _a(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
