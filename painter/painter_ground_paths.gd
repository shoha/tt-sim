class_name PainterGroundPaths
extends RefCounted

## The painted ground's path surfaces and its cliff stone (docs/systems/painter.md "Path surfaces
## and cliffs"). Pure functions over a map document and a compiled sheet; bind() sets them on the
## ground materials.
##
## The model. Every path-role surface a map paints with (PainterGroundRoles.surface_role "path")
## takes a SLOT, up to MAX_SLOTS, with its own tone and its own pattern. The tone is the sheet's
## `path` role moved toward the surface's measured colour (the library's albedo_mean_linear, as
## OKLCH): lightness, chroma and hue each by the surface's difference from PATH_REF (the colour that
## paints exactly as the sheet's path), scaled by the sheet's `path-own`. A pale caliche, a grey
## cobble and a honey sandstone flag part, and every mood and sun still moves them as it moves the
## path. The pattern is the surface's kind (PainterGroundRoles.path_kind: dirt, cobble, plates,
## tiles, gravel, planks), drawn by the ground shader (path_pattern). The slot map (R8, one texel
## per height sample, nearest) holds the slot whose blurred weight is largest there, 255 where no
## path lies; a map with one path surface binds no map, only `path_only`.
##
## The cliff stone (the rock role) is the sheet's `stone` turned by `cliff-turn` degrees, its
## chroma times `cliff-chroma`, its lightness moved by `cliff-lift`, then moved toward the map's own
## cliff surface (its main biome's) the same way from CLIFF_REF; its shade takes `cliff-pull` of
## the ground's pull and `cliff-shade-lift` more lightness (PainterSurfaces._tone_ground), so a face
## turned from the sun reads as stone in a warm shade, not the violet a grey role swings to.

## The path slots the shader has (p_lit, p_shd: two variants a slot; p_kind).
const MAX_SLOTS := 8
## The slot map's value where no path lies.
const NONE := 255
## The measured colour (OKLCH) that paints as the sheet's own path tone: about the core library's
## packed dirt road.
const PATH_REF := Vector3(0.64, 0.06, 80.0)
## The measured colour that paints as the sheet's cliff stone: the core library's grey cliff.
const CLIFF_REF := Vector3(0.52, 0.02, 74.0)
## How far a surface's own colour moves the tone, at `path-own` 1: lightness (its difference times
## this), chroma (its ratio to the reference's, clamped to OWN_C, to this power) and hue (its
## difference times this, only as far as the surface has a hue: chroma 0.01 none, 0.04 all).
const OWN_L := 0.6
const OWN_C_POW := 0.8
const OWN_C := Vector2(0.55, 2.0)
const OWN_H := 0.5


## The path-role surfaces of `doc` that take a slot, in slot order: the base surface first when it
## is a path, then the painted surfaces in the document's order; at most MAX_SLOTS (a later one
## paints with the sheet's plain path).
static func slots(doc: MapDocument) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := PackedStringArray([doc.base_surface])
	ids.append_array(doc.surface_ids)
	for id in ids:
		if out.size() < MAX_SLOTS and not out.has(id):
			if PainterGroundRoles.surface_role(id) == "path":
				out.append(id)
	return out


## The slot map of `doc` for slots `ids` (slots()) as an R8 image, or null when at most one slot is
## painted anywhere (`path_only` then names it; see used()). Each slot's weight is blurred as the
## zone map's path share is, so every texel the share reaches holds a slot. Pure.
static func slot_image(doc: MapDocument, ids: PackedStringArray) -> Image:
	var planes := _planes(doc, ids)
	var used: Array[int] = []
	for k in planes.size():
		if not planes[k].is_empty():
			used.append(k)
	if used.size() < 2:
		return null
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var n := sx * sz
	var blurred: Array[PackedFloat32Array] = []
	for k in used:
		blurred.append(PainterFieldBlur.box(planes[k], sx, sz, PainterSurfaces.ZONE_BLUR))
	var bytes := PackedByteArray()
	bytes.resize(n)
	for i in n:
		var best := 0.004
		var slot := NONE
		for u in used.size():
			var v: float = blurred[u][i]
			if v > best:
				best = v
				slot = used[u]
		bytes[i] = slot
	return Image.create_from_data(sx, sz, false, Image.FORMAT_R8, bytes)


## The one slot painted on `doc` (index in `ids`), -1 when none is or more than one is.
static func only_slot(doc: MapDocument, ids: PackedStringArray) -> int:
	var planes := _planes(doc, ids)
	var found := -1
	for k in planes.size():
		if not planes[k].is_empty():
			if found >= 0:
				return -1
			found = k
	return found


## Sets the slot map (or the one slot) of `doc` on `materials`; returns the slot ids.
static func bind(materials: Array, doc: MapDocument) -> PackedStringArray:
	var ids := slots(doc)
	var image := slot_image(doc, ids)
	var texture: ImageTexture = null if image == null else ImageTexture.create_from_image(image)
	var only := -1 if image != null else only_slot(doc, ids)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"path_map", texture)
		material.set_shader_parameter(&"path_map_present", texture != null)
		material.set_shader_parameter(&"path_only", only)
	return ids


## The shader's path tones for slots `ids` in `mood` at `elevation`: {"lit", "shade"} (two linear
## variants a slot, MAX_SLOTS * 2 entries) and "kind" (a pattern a slot).
static func tones(
	sheet: Dictionary, mood: String, elevation: float, ids: PackedStringArray
) -> Dictionary:
	var lit := PackedVector3Array()
	var shade := PackedVector3Array()
	var kinds := PackedInt32Array()
	var surfaces := PaletteLibrary.surfaces()
	var share := PainterSheet.number(sheet, mood, "path-own", elevation)
	var base := PainterSheet.tone_lch(sheet, mood, "path", elevation)
	for k in MAX_SLOTS:
		var id := ids[k] if k < ids.size() else ""
		var own := own_lch(surfaces.get(id, {}))
		var mid := base if own.x < 0.0 else moved(base, own, PATH_REF, share)
		var ramp := PainterTones.ramp(sheet, mood, "path", elevation, "ground-", mid)
		lit.append_array([PainterTones.linear(ramp[2]), PainterTones.linear(ramp[5])])
		shade.append_array([PainterTones.linear(ramp[0]), PainterTones.linear(ramp[3])])
		kinds.append(PainterGroundRoles.path_kind(id) if not id.is_empty() else 0)
	return {"lit": lit, "shade": shade, "kind": kinds}


## The cliff stone's middle tone (OKLCH) in `mood` at `elevation` for a map whose cliff surface is
## `cliff_surface` ("" for none: the sheet's cliff stone alone).
static func cliff_tone(
	sheet: Dictionary, mood: String, elevation: float, cliff_surface: String
) -> Vector3:
	var stone := PainterSheet.tone_lch(sheet, mood, "stone", elevation)
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	var tone := Vector3(
		clampf(stone.x + float(num.call("cliff-lift")), 0.05, 0.98),
		stone.y * float(num.call("cliff-chroma")),
		fposmod(stone.z + float(num.call("cliff-turn")), 360.0)
	)
	if cliff_surface.is_empty():
		return tone
	var own := own_lch(PaletteLibrary.surfaces().get(cliff_surface, {}))
	return tone if own.x < 0.0 else moved(tone, own, CLIFF_REF, 1.0)


## The cliff surface of `doc`'s main biome (the one with the most cells, else its first), "" when
## it has none or the palette does not know it.
static func cliff_surface(doc: MapDocument) -> String:
	if doc.biome_ids.is_empty():
		return ""
	var counts := PackedInt32Array()
	counts.resize(doc.biome_ids.size() + 1)
	for slot in doc.biome_slots:
		if slot <= doc.biome_ids.size():
			counts[slot] += 1
	var best := 0
	for k in doc.biome_ids.size():
		if counts[k + 1] > counts[best + 1]:
			best = k
	return str(PaletteLibrary.biome(doc.biome_ids[best]).get("cliff_surface", ""))


## A palette surface entry's measured colour as OKLCH, or x -1 when it has none.
static func own_lch(entry: Dictionary) -> Vector3:
	var mean: Variant = entry.get("albedo_mean_linear")
	if not mean is Array or (mean as Array).size() != 3:
		return Vector3(-1.0, 0.0, 0.0)
	var c := Color(float(mean[0]), float(mean[1]), float(mean[2])).linear_to_srgb()
	return PainterSheet.lch_of_color(c)


## `base` (OKLCH) moved by `share` of the way a surface of measured colour `own` differs from
## `ref` (the header's OWN_ numbers). Pure.
static func moved(base: Vector3, own: Vector3, ref: Vector3, share: float) -> Vector3:
	var hue_k := clampf((own.y - 0.01) / 0.03, 0.0, 1.0)
	var dh := fposmod(own.z - ref.z + 180.0, 360.0) - 180.0
	var ratio := clampf(own.y / maxf(ref.y, 0.001), OWN_C.x, OWN_C.y)
	return Vector3(
		clampf(base.x + (own.x - ref.x) * OWN_L * share, 0.05, 0.98),
		base.y * pow(ratio, OWN_C_POW * share),
		fposmod(base.z + dh * OWN_H * hue_k * share, 360.0)
	)


## One weight plane per slot of `ids` over `doc`'s samples (an empty array for a slot painted
## nowhere): a painted surface's weight, and the base surface's share left under the paint.
static func _planes(doc: MapDocument, ids: PackedStringArray) -> Array[PackedFloat32Array]:
	var planes: Array[PackedFloat32Array] = []
	for k in ids.size():
		planes.append(PackedFloat32Array())
	if ids.is_empty():
		return planes
	var n := doc.samples_x() * doc.samples_z()
	var slot_of := PackedInt32Array()
	for id in doc.surface_ids:
		slot_of.append(ids.find(id))
	var base_slot := ids.find(doc.base_surface)
	var weights := doc.surface_weights
	var has_surfaces := weights.size() == n * MapDocument.SURFACE_BYTES
	if base_slot >= 0:
		planes[base_slot].resize(n)
		planes[base_slot].fill(1.0)
	if not has_surfaces:
		return planes
	for i in n:
		var painted := 0.0
		for e in 4:
			var w := weights[n * 4 + i * 4 + e] / 255.0
			if w <= 0.0:
				continue
			painted += w
			var at := weights[i * 4 + e]
			var k := slot_of[at] if at < slot_of.size() else -1
			if k < 0:
				continue
			if planes[k].is_empty():
				planes[k].resize(n)
			planes[k][i] = maxf(planes[k][i], w)
		if base_slot >= 0:
			planes[base_slot][i] = maxf(0.0, 1.0 - painted)
	return planes
