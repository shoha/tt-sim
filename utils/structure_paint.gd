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
	for mesh: Dictionary in meshes:
		if not _paints(mesh):
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
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
				if mesh.role == StructureLook.WALL and palette.has("wall"):
					# A style's own wall tone, kept under each face's slight variation.
					var tint: Color = palette.wall
					var tone := c.r / WALL_REFERENCE_TONE
					if TEXTURED_KINDS.has(String(mesh.kind)):
						tone *= TEXTURED_WALL_GAIN
					else:
						tone = 1.0 + (tone - 1.0) * STYLE_TONE_KEEP
					out[v] = Color(tint.r * tone, tint.g * tone, tint.b * tone, alpha)
				else:
					out[v] = Color(
						minf(c.r * lean.r, 1.0),
						minf(c.g * lean.g, 1.0),
						minf(c.b * lean.b, 1.0),
						alpha
					)
		arrays[Mesh.ARRAY_COLOR] = out


static func _paints(mesh: Dictionary) -> bool:
	return mesh.role != StructureLook.OPENING and mesh.kind != StructureLook.GLASS_KIND


static func _group(
	group_of_tag: PackedInt32Array, tags: PackedInt32Array, v: int, count: int
) -> int:
	var tag := tags[v] if v < tags.size() else -1
	if tag < 0 or tag >= group_of_tag.size():
		return 0
	return clampi(group_of_tag[tag], 0, count - 1)
