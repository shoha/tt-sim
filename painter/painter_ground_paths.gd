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
## turned from the sun reads as stone in a warm shade, not the violet a grey role swings to. A mood
## whose stone is far from any rock's hue (winter's blue) takes `cliff-own` of the way to the bare
## rock's own chroma and hue in OKLab (the surface's colour as the summer cliff paints it, at the
## mood's lightness), so a badlands tier under snow light is warm sandstone, not a blue band.
##
## Polish (card painter-ground-polish): the shader's cliff lip takes `cliff-warm` of a gold tint
## and, under snow, `cliff-snow` of the meadow's snow as a cap; its foot takes `cliff-foot` of the
## way to its shade colour. Under snow (`path-dust`) a path is a trodden track (card
## painter-winter-ground): the shader paints its band as packed snow, a step darker and bluer than
## the snow beside it, with the surface's own earth or stone (earth()) showing in a few glimpses
## along its middle; its seams are shallower and its edge beside the snow is dusted white.

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
## Under snow (earth()): the share of the way to the surface's own chroma and hue a path's tone goes
## at `path-dust` 1, how much darker it is there and the share of its chroma it keeps (a wet, dark
## earth, not the summer road's sandy ochre).
const EARTH_OWN := 1.5
const EARTH_DARK := 0.35
const EARTH_CHROMA := 0.75


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
	return _slot_image_of(doc, _planes(doc, ids))


## slot_image() from the slots' weight planes (_planes).
static func _slot_image_of(doc: MapDocument, planes: Array[PackedFloat32Array]) -> Image:
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
	return _only_of(_planes(doc, ids))


## only_slot() from the slots' weight planes (_planes).
static func _only_of(planes: Array[PackedFloat32Array]) -> int:
	var found := -1
	for k in planes.size():
		if not planes[k].is_empty():
			if found >= 0:
				return -1
			found = k
	return found


## Sets the slot map (or the one slot) of `doc` on `materials`, the village fields' map
## (PainterFields.bind) and the meadow swathes' seed (PainterMeadowSwathes.bind); returns the slot
## ids. With `slot_map` false the slot map is left as the materials have it (the caller knows the
## painted surfaces did not change since: a sculpt step), which skips its pass over every sample.
## `presence` (the caller's, kept across calls) answers which slots are painted from the rows that
## changed: with fewer than two the slot map is null and `path_only` alone is bound, with no pass
## over the samples (a path stroke's frame, card painter-wall-path); with two or more its slot map
## (PainterPathSlotMap) is redone over those rows alone (card painter-path-many). The same values as
## without it.
static func bind(
	materials: Array, doc: MapDocument, slot_map := true, presence: PainterPathPresence = null
) -> PackedStringArray:
	PainterFields.bind(materials, doc)
	PainterMeadowSwathes.bind(materials, doc)
	var ids := slots(doc)
	if not slot_map:
		return ids
	var texture: ImageTexture = null
	var only := -1
	var painted := PackedInt32Array()
	var spans := PackedInt32Array()
	var kept := false
	if presence != null:
		kept = presence.slot_map.keeps(doc, ids, presence)
		spans = presence.update(doc)
		painted = presence.painted_slots(doc, ids)
	if presence != null and painted.size() < 2:
		# No slot map to bind, but its planes kept in step for the second surface's first dab (card
		# painter-path-first).
		if PainterPathSlotMap.supports(doc):
			presence.slot_map.follow(doc, ids, presence, spans, kept, painted)
		else:
			presence.slot_map.invalidate()
		only = painted[0] if painted.size() == 1 else -1
	elif presence != null and PainterPathSlotMap.supports(doc):
		# Two or more: the slot map redone over the changed rows (card painter-path-many).
		texture = presence.slot_map.texture(doc, ids, presence, spans, kept)
	else:
		if presence != null:
			presence.slot_map.invalidate()
		var planes := _planes(doc, ids)
		var image := _slot_image_of(doc, planes)
		texture = null if image == null else ImageTexture.create_from_image(image)
		only = -1 if image != null else _only_of(planes)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"path_map", texture)
		material.set_shader_parameter(&"path_map_present", texture != null)
		material.set_shader_parameter(&"path_only", only)
	return ids


## The shader's path tones for slots `ids` in `mood` at `elevation`: {"lit", "shade"} (two linear
## variants a slot, MAX_SLOTS * 2 entries) and "kind" (a pattern a slot); "fields" (PainterFields)
## and "uniforms": the meadow swathes' (PainterMeadowSwathes) and the cliff and snow numbers, by
## the ground shader's names.
static func tones(
	sheet: Dictionary, mood: String, elevation: float, ids: PackedStringArray
) -> Dictionary:
	var lit := PackedVector3Array()
	var shade := PackedVector3Array()
	var kinds := PackedInt32Array()
	var surfaces := PaletteLibrary.surfaces()
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	var share: float = num.call("path-own")
	var dust: float = num.call("path-dust")
	var base := PainterSheet.tone_lch(sheet, mood, "path", elevation)
	for k in MAX_SLOTS:
		var id := ids[k] if k < ids.size() else ""
		var own := own_lch(surfaces.get(id, {}))
		var mid := earth(base if own.x < 0.0 else moved(base, own, PATH_REF, share), own, dust)
		var ramp := PainterTones.ramp(sheet, mood, "path", elevation, "ground-", mid)
		lit.append_array([PainterTones.linear(ramp[2]), PainterTones.linear(ramp[5])])
		shade.append_array([PainterTones.linear(ramp[0]), PainterTones.linear(ramp[3])])
		kinds.append(PainterGroundRoles.path_kind(id) if not id.is_empty() else 0)
	var uniforms := PainterMeadowSwathes.tones(sheet, mood, elevation)
	uniforms[&"path_dust"] = dust
	uniforms[&"cliff_snow"] = num.call("cliff-snow")
	uniforms[&"cliff_foot"] = num.call("cliff-foot")
	uniforms[&"cliff_face"] = num.call("cliff-face")
	uniforms[&"cliff_warm"] = num.call("cliff-warm")
	return {
		"lit": lit,
		"shade": shade,
		"kind": kinds,
		"fields": PainterFields.tones(sheet, mood, elevation),
		"uniforms": uniforms,
	}


## Sets `tones` (tones()) on the ground `material`: the path slots', the fields' and the rest.
static func set_tones(material: ShaderMaterial, tones: Dictionary) -> void:
	material.set_shader_parameter(&"p_lit", tones["lit"])
	material.set_shader_parameter(&"p_shd", tones["shade"])
	material.set_shader_parameter(&"p_kind", tones["kind"])
	for group: String in ["fields", "uniforms"]:
		var values: Dictionary = tones[group]
		for key: StringName in values:
			material.set_shader_parameter(key, values[key])


## A path's middle tone `lch` (OKLCH) under snow, as the bare earth or stone that shows through the
## trodden track's few glimpses (the shader paints the rest of the band as packed snow): moved
## `dust` * EARTH_OWN of the way to the surface's own chroma and hue `own` in OKLab (ab_mix; a
## winter path tone is the snow's blue, so a dirt road's glimpse would read blue-grey) and `dust` *
## EARTH_DARK darker, so it reads against the snow at tabletop zoom. Pure; `dust` 0 returns it as
## it is.
static func earth(lch: Vector3, own: Vector3, dust: float) -> Vector3:
	if dust <= 0.0:
		return lch
	var bare := own if own.x >= 0.0 else PATH_REF
	var out := ab_mix(lch, bare, clampf(dust * EARTH_OWN, 0.0, 1.0))
	return Vector3(
		clampf(out.x - dust * EARTH_DARK, 0.05, 0.98),
		out.y * lerpf(1.0, EARTH_CHROMA, clampf(dust, 0.0, 1.0)),
		out.z
	)


## The cliff stone's middle tone (OKLCH) in `mood` at `elevation` for a map whose cliff surface is
## `cliff_surface` ("" for none: the sheet's cliff stone alone).
static func cliff_tone(
	sheet: Dictionary, mood: String, elevation: float, cliff_surface: String
) -> Vector3:
	var stone := PainterSheet.tone_lch(sheet, mood, "stone", elevation)
	var num := func(prop: String) -> float: return PainterSheet.number(sheet, mood, prop, elevation)
	var chroma: float = num.call("cliff-chroma")
	var turn: float = num.call("cliff-turn")
	var tone := Vector3(
		clampf(stone.x + float(num.call("cliff-lift")), 0.05, 0.98),
		stone.y * chroma,
		fposmod(stone.z + turn, 360.0)
	)
	var own := CLIFF_REF
	if not cliff_surface.is_empty():
		var measured := own_lch(PaletteLibrary.surfaces().get(cliff_surface, {}))
		own = CLIFF_REF if measured.x < 0.0 else measured
	tone = moved(tone, own, CLIFF_REF, 1.0)
	var bare: float = num.call("cliff-own")
	if bare <= 0.0:
		return tone
	# The bare rock's own colour as the summer cliff paints it (the reference stone turned and
	# enriched, moved to the surface), at this mood's lightness.
	var rock := moved(
		Vector3(tone.x, CLIFF_REF.y * chroma, fposmod(CLIFF_REF.z + turn, 360.0)), own, CLIFF_REF, 1.0
	)
	return ab_mix(tone, rock, bare)


## `a` (OKLCH) moved `t` of the way to `b`'s chroma and hue in OKLab's a-b plane (a's lightness
## kept): a blue and a warm grey meet at a quiet warm grey, never through a third hue. Pure.
static func ab_mix(a: Vector3, b: Vector3, t: float) -> Vector3:
	var pa := Vector2.from_angle(deg_to_rad(a.z)) * a.y
	var pb := Vector2.from_angle(deg_to_rad(b.z)) * b.y
	var m := pa.lerp(pb, clampf(t, 0.0, 1.0))
	return Vector3(a.x, m.length(), fposmod(rad_to_deg(m.angle()), 360.0))


## The cliff surface of `doc`'s main biome (the one with the most cells, else its first), "" when
## it has none or the palette does not know it.
static func cliff_surface(doc: MapDocument) -> String:
	if doc.biome_ids.is_empty():
		return ""
	var counts := PackedInt32Array()
	counts.resize(doc.biome_ids.size() + 1)
	var slots := doc.biome_slots
	for k in counts.size():
		counts[k] = slots.count(k)  # Native: a GDScript pass over the samples cost about 4 ms.
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
