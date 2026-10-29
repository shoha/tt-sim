class_name StructurePaint
extends RefCounted

## Bakes a building's painterly colour into its mesh arrays (card S6): the tile colour of its roof
## and the lean of its walls, from a palette drawn deterministically from the record's seed and id,
## and in the alpha the height the shaders grade by (structure_roof.gdshader: 0 at the eave to 1 at
## the ridge; structure_wall.gdshader: height above the building's foot in sixteenths of a metre).
## A building is a GROUP of vertices: a structure is one group, a street row has one per lot
## (found from the provenance paths). Pure and safe on any thread; the colours are part of the
## digest that tests/fixtures/structure_digests.txt pins.

## The tone procgen's gable and hip slabs are made in (ProcgenBuilding ROOF_SHADE): a roof vertex
## colour divided by it keeps each slab's own slight variation and the darker ridge and soffit.
const ROOF_REFERENCE_TONE := 0.86
## The tone procgen's wall faces are made in (BOARD_SHADE, the stone builder's shade): a wall vertex
## colour divided by it keeps each board's and block's own slight variation under a style's tone.
const WALL_REFERENCE_TONE := 0.9
## The kinds whose colour multiplies a baked texture (planks, courses): a style's wall tone is a
## lean over the texture, so it is lifted by this gain; a style kind (plaster, ...) takes it as is.
const TEXTURED_KINDS: Array[String] = ["wood", "boards", "masonry"]
const TEXTURED_WALL_GAIN := 1.7
## How much of a face's own tone variation a style kind (plaster, adobe, brick, log) keeps: boards
## under a plaster wash must not show as stripes, the shader draws their own marks.
const STYLE_TONE_KEEP := 0.3
## Height above a foot the wall alpha spans, metres.
const WALL_ALPHA_SPAN_M := 16.0
## The green a ruin multiplies into the stone at its foot (procgen's ProcgenRuin.MOSS_TINT) and how
## the share is read back from a colour: the stone's own green over red sits at about 1.03 to 1.06,
## full moss at about 1.45.
const MOSS_TINT := Color(0.66, 0.96, 0.4)
const MOSS_G_OVER_R_FROM := 1.08
const MOSS_G_OVER_R_SPAN := 0.37
## How far full moss pulls a style wall's baked colour to green (`_mossed`).
const MOSS_BAKE := 0.8
## A style wall's moss is full up to this many metres above the building's lowest vertex and fades
## out by the second (which is about a metre above the ground: the skirt sits 0.2 m below it).
const MOSS_FULL_M := 0.4
const MOSS_CLIMB_M := 1.4


## How mossy a procgen wall colour is, 0..1: a ruin's moss is that multiplied green, and a style's
## wall tone replaces the colour, so the share is read off the green over red and put back.
static func moss_of(c: Color) -> float:
	if c.r < 0.02:
		return 0.0
	return clampf((c.g / c.r - MOSS_G_OVER_R_FROM) / MOSS_G_OVER_R_SPAN, 0.0, 1.0)


## A 32-bit mix of two integers (murmur-style finaliser), the same on every platform.
static func mix(a: int, b: int) -> int:
	var x := (
		((a & 0xFFFFFFFF) * 0x9E3779B1 + (b & 0xFFFFFFFF) * 0x85EBCA6B + 0x27D4EB2F) & 0xFFFFFFFF
	)
	x = (((x >> 15) ^ x) * 0x2C1B3C6D) & 0xFFFFFFFF
	x = (((x >> 12) ^ x) * 0x297A2D39) & 0xFFFFFFFF
	return (x >> 15) ^ x


## A float in [0, 1) from a mixed integer.
static func unit(h: int) -> float:
	return float(h & 0xFFFF) / 65536.0


## The palette of the building with seed `seed_value` and id `id`: {"name": roof palette name,
## "roof": Color (linear, the tile colour), "lean": Color (the wall multiplier)}. With `hints`
## (StructureLook.palette_hints: a building style's lists of sRGB tones) the roof colour is drawn
## from the style's roof tones instead (name "style") and the palette gains "wall": Color (linear,
## the style's wall tone), which replaces the lean on wall meshes; everything else, and the draw
## of a building without hints, is as before.
static func palette_of(seed_value: int, id: int, hints: Dictionary = {}) -> Dictionary:
	var h := mix(seed_value, id)
	var total := 0.0
	for entry in StructureLook.ROOF_PALETTE:
		total += float(entry.weight)
	var pick := unit(h) * total
	var chosen: Dictionary = StructureLook.ROOF_PALETTE[0]
	for entry in StructureLook.ROOF_PALETTE:
		pick -= float(entry.weight)
		if pick < 0.0:
			chosen = entry
			break
	var value := 1.0 + (unit(mix(h, 7)) - 0.5) * 0.18
	var warm := unit(mix(h, 13)) - 0.5
	var srgb: Color = chosen.srgb
	var roof := (
		Color(
			srgb.r * value * (1.0 + warm * 0.06),
			srgb.g * value,
			srgb.b * value * (1.0 - warm * 0.06)
		)
		. srgb_to_linear()
	)
	var lean: Color = StructureLook.WALL_LEANS[mix(h, 21) % StructureLook.WALL_LEANS.size()]
	var palette := {"name": chosen.name, "roof": roof, "lean": lean}
	var roofs: Array = hints.get("roof", [])
	if not roofs.is_empty():
		var tone: Color = roofs[mix(h, 31) % roofs.size()]
		palette.name = "style"
		palette.roof = (
			Color(
				minf(tone.r * value * (1.0 + warm * 0.06), 1.0),
				minf(tone.g * value, 1.0),
				minf(tone.b * value * (1.0 - warm * 0.06), 1.0)
			)
			. srgb_to_linear()
		)
	var walls: Array = hints.get("wall", [])
	if not walls.is_empty():
		var tone: Color = walls[mix(h, 37) % walls.size()]
		var jitter := 1.0 + (unit(mix(h, 43)) - 0.5) * 0.10
		palette["wall"] = (
			Color(
				minf(tone.r * jitter, 1.0), minf(tone.g * jitter, 1.0), minf(tone.b * jitter, 1.0)
			)
			. srgb_to_linear()
		)
	return palette


## Paints `meshes` ({"kind", "role", "arrays", "tags"} as StructureGeometry makes them) in place.
## `group_of_tag` maps a tag id to the index of its palette in `palettes` (a tag it does not list,
## and the tag -1, take group 0). Roof meshes get their group's tile colour and the eave-to-ridge
## alpha, wall, trim and chimney meshes the group's lean and the foot-height alpha; openings and
## glass stay as procgen made them.
static func paint(meshes: Array, group_of_tag: PackedInt32Array, palettes: Array) -> void:
	if meshes.is_empty() or palettes.is_empty():
		return
	var roof_low := PackedFloat32Array()
	var roof_high := PackedFloat32Array()
	var foot := PackedFloat32Array()
	roof_low.resize(palettes.size())
	roof_low.fill(INF)
	roof_high.resize(palettes.size())
	roof_high.fill(-INF)
	foot.resize(palettes.size())
	foot.fill(INF)
	var moss_peak := PackedFloat32Array()
	moss_peak.resize(palettes.size())
	for mesh: Dictionary in meshes:
		if not _paints(mesh):
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var source: PackedColorArray = mesh.arrays[Mesh.ARRAY_COLOR]
		var tags: PackedInt32Array = mesh.tags
		var roof: bool = mesh.role == StructureLook.ROOF
		for v in vertices.size():
			var g := _group(group_of_tag, tags, v, palettes.size())
			var y := vertices[v].y
			if roof:
				roof_low[g] = minf(roof_low[g], y)
				roof_high[g] = maxf(roof_high[g], y)
			else:
				foot[g] = minf(foot[g], y)
				if mesh.role == StructureLook.WALL and v < source.size():
					moss_peak[g] = maxf(moss_peak[g], moss_of(source[v]))
	for mesh: Dictionary in meshes:
		if not _paints(mesh):
			continue
		var arrays: Array = mesh.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var tags: PackedInt32Array = mesh.tags
		var roof: bool = mesh.role == StructureLook.ROOF
		var out := PackedColorArray()
		out.resize(vertices.size())
		for v in vertices.size():
			var g := _group(group_of_tag, tags, v, palettes.size())
			var palette: Dictionary = palettes[g]
			var c: Color = colors[v] if v < colors.size() else Color.WHITE
			if roof:
				var span := maxf(roof_high[g] - roof_low[g], 0.1)
				var tone := c.r / ROOF_REFERENCE_TONE
				var tile: Color = palette.roof
				out[v] = Color(
					minf(tile.r * tone, 1.0),
					minf(tile.g * tone, 1.0),
					minf(tile.b * tone, 1.0),
					clampf((vertices[v].y - roof_low[g]) / span, 0.0, 1.0)
				)
			else:
				var lean: Color = palette.lean
				if mesh.role == StructureLook.TRIM:
					lean = Color.WHITE
				var metres := vertices[v].y - (foot[g] if foot[g] < INF else 0.0)
				var alpha := clampf(metres / WALL_ALPHA_SPAN_M, 0.0, 1.0)
				if mesh.role == StructureLook.FRAME:
					# Beams, vigas and ladders keep the tone procgen gave them (dark timber), not
					# the wall's, so half-timber reads as framing over the plaster.
					out[v] = Color(c.r, c.g, c.b, alpha)
				elif mesh.role == StructureLook.WALL and palette.has("wall"):
					# A style's own wall tone, kept under each face's slight variation, and a
					# ruin's moss (a green multiplied into the stone, which `tone` would drop).
					var tint: Color = palette.wall
					var tone := c.r / WALL_REFERENCE_TONE
					if TEXTURED_KINDS.has(String(mesh.kind)):
						tone *= TEXTURED_WALL_GAIN
					else:
						tone = 1.0 + (tone - 1.0) * STYLE_TONE_KEEP
					var moss := moss_of(c)
					if not TEXTURED_KINDS.has(String(mesh.kind)):
						# procgen's moss sits on the lowest strip of a style wall (a quarter metre
						# of its brick or plaster courses), which is too thin a band to read once it
						# is interpolated: the building's strongest moss climbs the first metre.
						moss = maxf(
							moss,
							moss_peak[g] * (1.0 - smoothstep(MOSS_FULL_M, MOSS_CLIMB_M, metres))
						)
					var toned := Color(
						tint.r * tone * lerpf(1.0, MOSS_TINT.r, moss),
						tint.g * tone * lerpf(1.0, MOSS_TINT.g, moss),
						tint.b * tone * lerpf(1.0, MOSS_TINT.b, moss),
						alpha
					)
					if moss > 0.0 and not TEXTURED_KINDS.has(String(mesh.kind)):
						toned = _mossed(toned, moss)
					out[v] = toned
				else:
					out[v] = Color(
						minf(c.r * lean.r, 1.0),
						minf(c.g * lean.g, 1.0),
						minf(c.b * lean.b, 1.0),
						alpha
					)
		arrays[Mesh.ARRAY_COLOR] = out


## `c` pulled toward a moss green by `moss`, keeping its light and dark. The wall shaders read moss
## back from the colour as green over red and blue (s_moss_of), which a red brick or an orange
## adobe with a multiplied green never shows (its red stays the largest), so the style kinds get
## the green baked in here and the shader's pull then finds it.
static func _mossed(c: Color, moss: float) -> Color:
	var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var green := Color(0.5 * luma * 1.2, 1.15 * luma * 1.2, 0.34 * luma * 1.2, c.a)
	return c.lerp(green, clampf(moss * MOSS_BAKE, 0.0, 1.0))


static func _paints(mesh: Dictionary) -> bool:
	return mesh.role != StructureLook.OPENING and mesh.kind != StructureLook.GLASS_KIND


static func _group(
	group_of_tag: PackedInt32Array, tags: PackedInt32Array, v: int, count: int
) -> int:
	var tag := tags[v] if v < tags.size() else -1
	if tag < 0 or tag >= group_of_tag.size():
		return 0
	return clampi(group_of_tag[tag], 0, count - 1)
