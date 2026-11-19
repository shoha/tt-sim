class_name PainterFlowerHue
extends RefCounted

## The painted flowers' blooms (docs/systems/painter.md "Flowers", card painter-flowers): which
## surfaces of a flower asset are its blooms, which of the sheet's six flower roles each takes, and
## the shape of the one dab the plant shader draws for each bloom. Read once per surface when the
## stand-in is made, from the asset's own material and mesh, never from a fixed colour, so a poppy
## paints red, a bluebell blue and a buttercup gold in every mood, and two species never share one
## flat accent.
##
## The model. Core's flowers (plantgen) are three surfaces: `_Bark` (the stems), `_Leaf` (the
## leaves) and `_LeafB` (the blooms: small cards, UV 0..1 each, three crossed per head or many
## tilted over a mound), whose texture holds the bloom's own colour on a teardrop or spike cut.
## A bloom surface is drawn whole as dabs: each card a soft-edged blot the shape of its texture's
## opaque box, in the role its texture's mean colour sorts into (class_of), grown by the shader to
## a floor in pixels so it reads at the orbit view. A stem or leaf surface is the grass ramp. A
## surface whose name says neither (a user library's flower in one atlas) keeps the old per-pixel
## petal test, coloured by the mean of its non-green pixels. Pure functions; no state.

## The six flower roles, in the selector's `accent` order (painter_selector.gdshaderinc).
const ROLES: Array[String] = [
	"flower-gold", "flower-rose", "flower-violet", "flower-white", "flower-red", "flower-blue"
]
const GOLD := 0
const ROSE := 1
const VIOLET := 2
const WHITE := 3
const RED := 4
const BLUE := 5
## Not a bloom: a stem or leaves, drawn in the grass ramp.
const NONE := -1
## The last word of a material name (`Flower_Poppy_v0_LeafB`) that marks a bloom surface, and the
## words that mark a stem or leaves.
const BLOOM_WORDS: Array[String] = ["leafb", "petal", "petals", "bloom", "blossom", "flowers"]
const GREEN_WORDS: Array[String] = ["bark", "leaf", "leaves", "stem", "stalk"]
## OKLCH chroma under which a bloom is white.
const WHITE_CHROMA := 0.05
## OKLCH hue bounds (degrees) between the coloured roles: rose below RED_FROM and from ROSE_FROM
## up, red to GOLD_FROM, gold to BLUE_FROM (a green-yellow bloom is gold), blue to VIOLET_FROM,
## violet to ROSE_FROM. The core blooms sit well inside: poppy 33, bloom mound 355 and 85,
## buttercup 98, bluebell 270 to 276, bellflower and lavender 296 to 301 (test_painter_flowers).
const RED_FROM := 22.0
const GOLD_FROM := 60.0
const BLUE_FROM := 170.0
const VIOLET_FROM := 286.0
const ROSE_FROM := 330.0
## The samples a texture is read at, per side (a 128 px bloom texture read every 8th texel).
const SAMPLES := 16
## The least share of a surface's opaque texels that must be non-green for a surface of an
## unknown name to carry petals.
const PETAL_SHARE := 0.05
## The width of the centres texture (texels; the shader's VERTEX_ID % CENTRE_WIDTH), and the most
## vertices a bloom surface may have for its cards to be grown (core's have 160 to 260).
const CENTRE_WIDTH := 256
const MAX_VERTICES := 16384
## A bloom surface is drawn as one carpet at the orbit view (carpet_of) when it has at least
## CARPET_CARDS cards and its highest card's middle is under CARPET_TOP (mesh units, metres): core's
## bloom and lavender mounds top out at 0.10 to 0.13, its poppies, daisies and bells on their stems
## at 0.29 to 0.41, every one 40 to 65 cards (measured 2026-11-19).
const CARPET_CARDS := 12
const CARPET_TOP := 0.2


## The sheet role index (ROLES) a bloom of sRGB colour `c` takes.
static func class_of(c: Color) -> int:
	var lch := PainterSheet.lch_of_color(c)
	if lch.y < WHITE_CHROMA:
		return WHITE
	var h := lch.z
	if h < RED_FROM or h >= ROSE_FROM:
		return ROSE
	if h < GOLD_FROM:
		return RED
	if h < BLUE_FROM:
		return GOLD
	if h < VIOLET_FROM:
		return BLUE
	return VIOLET


## `entry` (a KIND_FLOWER entry of PainterPlantRoles.of) for one surface of the asset, whose
## material is `material` (null allowed) and, when given, whose mesh surface is `surface` of `mesh`:
## a copy with `petal` (a ROLES index, or NONE), `dab` (true when the whole surface is blooms drawn
## as dabs), and for a dab surface `dab_box` (the texture's opaque box in UV: centre x, y and half
## extents) and `centres` (centres(): each vertex's card, null without a mesh, which turns the
## growth off).
static func for_surface(
	entry: Dictionary, material: Material, mesh: Mesh = null, surface: int = -1
) -> Dictionary:
	var out := entry.duplicate()
	out["petal"] = NONE
	out["dab"] = false
	var word := _last_word(material)
	if word in GREEN_WORDS:
		return out
	var texture := _texture_of(material)
	var image := texture.get_image() if texture != null else null
	if image != null and image.is_compressed():
		image = image.duplicate() as Image
		image.decompress()
	var tint := _tint_of(material)
	if word in BLOOM_WORDS:
		var mean := _mean(image, false)
		out["petal"] = class_of(_mul(mean if mean.a > 0.0 else Color.WHITE, tint))
		out["dab"] = true
		var box := opaque_box(image)
		out["dab_box"] = box
		out["centres"] = centres(mesh, surface, box)
		return out
	var petals := _mean(image, true)
	if petals.a >= PETAL_SHARE:
		out["petal"] = class_of(_mul(petals, tint))
	return out


## The UV box of `image`'s opaque texels (alpha over a half) as centre x, y and half extents, the
## whole card when there is no image or nothing opaque.
static func opaque_box(image: Image) -> Vector4:
	if image == null:
		return Vector4(0.5, 0.5, 0.5, 0.5)
	var lo := Vector2(1.0, 1.0)
	var hi := Vector2(0.0, 0.0)
	var size := Vector2(image.get_width(), image.get_height())
	for y in SAMPLES * 2:
		for x in SAMPLES * 2:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(SAMPLES * 2)
			var px := Vector2i((uv * size).floor())
			if image.get_pixelv(px).a > 0.5:
				lo = lo.min(uv)
				hi = hi.max(uv)
	if hi.x < lo.x:
		return Vector4(0.5, 0.5, 0.5, 0.5)
	var half := (hi - lo) * 0.5 + Vector2.ONE / float(SAMPLES * 4)
	var mid := (hi + lo) * 0.5
	return Vector4(mid.x, mid.y, half.x, half.y)


## Each vertex's card of surface `surface` of `mesh` (null when there is none, or more than
## MAX_VERTICES): a float texture CENTRE_WIDTH texels wide, one texel per vertex in vertex order
## (the shader's VERTEX_ID), holding its card's centre (xyz, mesh units) and the size of the dab
## drawn on it (w: the smaller of the card's UV-mapped width and height times the opaque box's,
## `box` opaque_box's), and one row more whose first texel is carpet_of() the cards. A card is a
## set of triangles joined by shared vertices; the plant shader grows each about its centre, so no
## card frame is assumed (core's bloom cards run every way).
static func centres(mesh: Mesh, surface: int, box: Vector4) -> ImageTexture:
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return null
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	if uvs == null or verts.is_empty() or verts.size() > MAX_VERTICES:
		return null
	var index = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array(range(verts.size())) if index == null else index as PackedInt32Array
	var parent: Array[int] = []
	parent.assign(range(verts.size()))
	for t in range(0, order.size() - 2, 3):
		_join(parent, order[t], order[t + 1])
		_join(parent, order[t], order[t + 2])
	# Per card: the sum of its vertices, their count, and its UV-mapped size (mesh units per UV
	# unit across and down, from its first triangle).
	var sums := {}
	var sizes := {}
	for t in range(0, order.size() - 2, 3):
		var root := _root(parent, order[t])
		if sizes.has(root):
			continue
		var size := _uv_scale(verts, uvs, order[t], order[t + 1], order[t + 2])
		if size != Vector2.ZERO:
			sizes[root] = size
	for i in verts.size():
		var root := _root(parent, i)
		var s: Vector4 = sums.get(root, Vector4.ZERO)
		sums[root] = s + Vector4(verts[i].x, verts[i].y, verts[i].z, 1.0)
	var rows := ceili(float(verts.size()) / CENTRE_WIDTH)
	var image := Image.create_empty(CENTRE_WIDTH, rows + 1, false, Image.FORMAT_RGBAF)
	for i in verts.size():
		var root := _root(parent, i)
		var s: Vector4 = sums[root]
		var size: Vector2 = sizes.get(root, Vector2.ZERO) * Vector2(box.z, box.w) * 2.0
		image.set_pixel(
			i % CENTRE_WIDTH,
			i / CENTRE_WIDTH,
			Color(s.x / s.w, s.y / s.w, s.z / s.w, minf(size.x, size.y))
		)
	image.set_pixel(0, rows, carpet_of(sums.values()))
	return ImageTexture.create_from_image(image)


## The texel the shader reads last in the centres texture, from each card's vertex sum (xyz) and
## count (w): the cards' middle across (x, z), the top card's height (y), and 1 in alpha when the
## surface is a low carpet of blooms (CARPET_CARDS, CARPET_TOP: a bloom mound), else 0. At the
## orbit view the plant shader turns a carpet's cards to the view, draws them in toward that middle
## and up to that top over the leaves, and grows them, so the mound reads as one solid blot of bloom
## in a few hues instead of a ring of small dabs with the green between (owner, board l44_mound:
## "One solid blot"; painter_selector's bloom_grown). Pure.
static func carpet_of(cards: Array) -> Color:
	var mid := Vector3.ZERO
	var top := -INF
	for s: Vector4 in cards:
		var c := Vector3(s.x, s.y, s.z) / maxf(s.w, 1.0)
		mid += c
		top = maxf(top, c.y)
	mid /= maxf(float(cards.size()), 1.0)
	var carpet := cards.size() >= CARPET_CARDS and top < CARPET_TOP
	return Color(mid.x, top if cards.size() > 0 else 0.0, mid.z, 1.0 if carpet else 0.0)


## Mesh units per UV unit across and down the triangle a, b, c (zero when its UVs are degenerate).
static func _uv_scale(
	verts: PackedVector3Array, uvs: PackedVector2Array, a: int, b: int, c: int
) -> Vector2:
	var e1 := verts[b] - verts[a]
	var e2 := verts[c] - verts[a]
	var d1 := uvs[b] - uvs[a]
	var d2 := uvs[c] - uvs[a]
	var det := d1.x * d2.y - d2.x * d1.y
	if absf(det) < 1.0e-8:
		return Vector2.ZERO
	var du := (e1 * d2.y - e2 * d1.y) / det
	var dv := (e2 * d1.x - e1 * d2.x) / det
	return Vector2(du.length(), dv.length())


## The card (union-find root) of vertex `i`; `parent` is shared by reference and compressed.
static func _root(parent: Array[int], i: int) -> int:
	var at := i
	while parent[at] != at:
		parent[at] = parent[parent[at]]
		at = parent[at]
	return at


static func _join(parent: Array[int], a: int, b: int) -> void:
	var ra := _root(parent, a)
	var rb := _root(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


## The last `_`-separated word of the material's name, lower case ("" for none).
static func _last_word(material: Material) -> String:
	if material == null:
		return ""
	var name := material.resource_name.to_lower()
	return name.get_slice("_", name.get_slice_count("_") - 1)


## The albedo texture of a standard material or a wind stand-in (its `albedo_texture`), or null.
static func _texture_of(material: Material) -> Texture2D:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_texture
	if material is ShaderMaterial:
		return (material as ShaderMaterial).get_shader_parameter(&"albedo_texture") as Texture2D
	return null


## A standard material's albedo colour (white for any other material).
static func _tint_of(material: Material) -> Color:
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_color
	return Color.WHITE


static func _mul(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b)


## The mean sRGB colour of `image`'s opaque texels (alpha over a half), only the non-green ones
## (the selector's petal test: green under 0.02 over red and blue) when `petals`; its alpha is the
## share of the opaque texels counted (0 when none, or no image).
static func _mean(image: Image, petals: bool) -> Color:
	if image == null:
		return Color(0, 0, 0, 0)
	var sum := Color(0, 0, 0, 0)
	var opaque := 0
	var counted := 0
	for y in SAMPLES:
		for x in SAMPLES:
			var px := Vector2i(
				(x * image.get_width()) / SAMPLES + image.get_width() / (SAMPLES * 2),
				(y * image.get_height()) / SAMPLES + image.get_height() / (SAMPLES * 2)
			)
			var c := image.get_pixelv(px)
			if c.a <= 0.5:
				continue
			opaque += 1
			if petals and c.g - maxf(c.r, c.b) >= 0.02:
				continue
			counted += 1
			sum += Color(c.r, c.g, c.b, 0.0)
	if counted == 0:
		return Color(0, 0, 0, 0)
	return Color(
		sum.r / counted, sum.g / counted, sum.b / counted, float(counted) / float(maxi(opaque, 1))
	)
