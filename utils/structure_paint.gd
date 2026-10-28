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
## "roof": Color (linear, the tile colour), "lean": Color (the wall multiplier)}.
static func palette_of(seed_value: int, id: int) -> Dictionary:
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
	return {"name": chosen.name, "roof": roof, "lean": lean}


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
				out[v] = Color(
					minf(c.r * lean.r, 1.0),
					minf(c.g * lean.g, 1.0),
					minf(c.b * lean.b, 1.0),
					clampf(metres / WALL_ALPHA_SPAN_M, 0.0, 1.0)
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
