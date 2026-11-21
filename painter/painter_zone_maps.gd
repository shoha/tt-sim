class_name PainterZoneMaps
extends RefCounted

## The painted ground's zone maps for one map document, kept current per edit (card
## painter-zone-dirty-rect; docs/systems/painter.md "Zone maps"): the zone map (RGBA8: r meadow
## share, g path, b rock, a shore), the char map (R8, the scorched ground's share; only when the
## document names an ash surface) and the biome zone map (RGBA8: r dry, g ash, b earth; only when a
## biome paints in one of those roles). One texel per height sample, each blurred ZONE_BLUR samples.
##
## The model. A texel is a pure function of two things: the PLAN, the whole-map inputs every texel
## reads alike (the grid's size, the roles' channel tables, the base surface's role, which arrays
## the document has, the dominant dry biome: plan()), and the samples within ZONE_BLUR of it (the
## blur's three taps). So an edit of the samples in a rectangle changes only the texels in that
## rectangle grown by ZONE_BLUR, and those read only the samples within ZONE_BLUR of them: update()
## recomputes that region from the samples around it and writes it into the kept images, while a
## changed plan (a new surface or biome, a dominant biome won or lost, a new size) rebuilds whole.
## The region functions are the whole build too (build() is the region of the whole grid), so a
## partial update equals the whole rebuild bit for bit (test_painter_zone_maps.gd).
##
## Textures. One ImageTexture per map, shared by every material that reads it (the ground and the
## skirt), updated in place (ImageTexture.update uploads the whole image: Godot 4.7 has no partial
## upload); a new one only when the size or format changes (another map) or a map appears.

## The images now (null for a map the plan has none of; zone is null before the first build).
var zone: Image = null
var char_map: Image = null
var biome: Image = null
## The region the last update() wrote (grid coordinates), the whole grid after a build (probes).
var last_rect := Rect2i()
## Whether the last call rebuilt whole (tests, probes).
var last_whole := false

var _plan: Dictionary = {}
var _zone_texture: ImageTexture = null
var _char_texture: ImageTexture = null
var _biome_texture: ImageTexture = null


## Rebuilds every map of `doc` whole and uploads them.
func build(doc: MapDocument, plan_now: Dictionary = {}) -> void:
	var p := plan_now if not plan_now.is_empty() else plan(doc)
	var grid := Rect2i(0, 0, p["sx"], p["sz"])
	zone = _image_of(grid, Image.FORMAT_RGBA8, zone_region(doc, p, grid))
	char_map = (
		_image_of(grid, Image.FORMAT_R8, char_region(doc, p, grid)) if p["char_any"] else null
	)
	biome = (
		_image_of(grid, Image.FORMAT_RGBA8, biome_region(doc, p, grid))
		if p["biome_present"]
		else null
	)
	_plan = p
	last_rect = grid
	last_whole = true
	_upload()


## Brings the maps up to `doc` after an edit of the samples in `rect` (grid coordinates, the
## ground_edited rectangle: it covers every sample changed since the last call); rebuilds whole
## when the plan changed or nothing was built yet.
func update(doc: MapDocument, rect: Rect2i) -> void:
	var p := plan(doc)
	if zone == null or p != _plan or PainterSurfaces.ZONE_BLUR != 1 or mini(p["sx"], p["sz"]) < 2:
		# The region form relies on the three-tap blur (PainterFieldBlur.box at radius 1 on a field
		# at least two samples wide), whose every output reads only its neighbours; a wider radius
		# or a narrower field takes the running sum.
		build(doc, p)
		return
	var grid := Rect2i(0, 0, p["sx"], p["sz"])
	var out := rect.grow(PainterSurfaces.ZONE_BLUR).intersection(grid)
	last_whole = false
	last_rect = out
	if not out.has_area():
		return
	_blit(zone, Image.FORMAT_RGBA8, zone_region(doc, p, out), out)
	if char_map != null:
		_blit(char_map, Image.FORMAT_R8, char_region(doc, p, out), out)
	if biome != null:
		_blit(biome, Image.FORMAT_RGBA8, biome_region(doc, p, out), out)
	_upload()


## The zone map's texture (null before the first build).
func zone_texture() -> ImageTexture:
	return _zone_texture


## The char map's texture, null when the document names no ash surface.
func char_texture() -> ImageTexture:
	return _char_texture


## The biome zone map's texture, null when no biome paints in its roles.
func biome_texture() -> ImageTexture:
	return _biome_texture


func _upload() -> void:
	_zone_texture = _uploaded(_zone_texture, zone)
	_char_texture = _uploaded(_char_texture, char_map)
	_biome_texture = _uploaded(_biome_texture, biome)


## `texture` updated in place with `image`, or a new one when the size or format differs; null
## for no image.
static func _uploaded(texture: ImageTexture, image: Image) -> ImageTexture:
	if image == null:
		return null
	if (
		texture != null
		and texture.get_size() == Vector2(image.get_size())
		and texture.get_format() == image.get_format()
	):
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


static func _image_of(rect: Rect2i, format: Image.Format, bytes: PackedByteArray) -> Image:
	return Image.create_from_data(rect.size.x, rect.size.y, false, format, bytes)


## Writes `bytes` (a `format` image of `rect`'s size) into `target` at `rect`.
static func _blit(
	target: Image, format: Image.Format, bytes: PackedByteArray, rect: Rect2i
) -> void:
	target.blit_rect(_image_of(rect, format, bytes), Rect2i(Vector2i.ZERO, rect.size), rect.position)


# ---------------------------------------------------------------- the whole-map inputs


## The whole-map inputs of `doc`'s maps (pure): {"sx", "sz", "n", "base" (the zone map's value of
## an untouched sample), the biome and surface roles' channels and targets, "has_biomes",
## "has_surfaces", "has_wet", "surface_char" (1 per ash surface), "char_any", "biome_targets"
## (each biome's channel in the biome zone map), "dominant" (_dominant_channel), "biome_present"}.
## Two plans compare equal exactly when every texel reads the same constants.
static func plan(doc: MapDocument) -> Dictionary:
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var n := sx * sz
	var slots := doc.biome_slots
	var density := doc.biome_density
	var biome_targets := PackedInt32Array()
	var biome_any := false
	var biome_channel := PackedInt32Array()
	var biome_target := PackedFloat32Array()
	for id in doc.biome_ids:
		var role := PainterGroundRoles.biome_role(id)
		var channel := PainterGroundRoles.index(role) - PainterGroundRoles.BIOME_ROLES_FROM
		biome_targets.append(channel if channel >= 0 and channel < 3 else -1)
		biome_any = biome_any or channel >= 0
		_role_channel(role, biome_channel, biome_target)
	var dominant := _dominant_channel(biome_targets, slots)
	var base_role := PainterGroundRoles.surface_role(doc.base_surface)
	if base_role == "shore" and slots.size() > 0 and dominant >= 0:
		base_role = "meadow"
	var surface_channel := PackedInt32Array()
	var surface_target := PackedFloat32Array()
	var surface_char := PackedByteArray()
	var char_any := false
	for id in doc.surface_ids:
		var role := PainterGroundRoles.surface_role(id)
		_role_channel(role, surface_channel, surface_target)
		surface_char.append(1 if role == "char" else 0)
		char_any = char_any or role == "char"
	var has_biomes := slots.size() == n and density.size() == n
	return {
		"sx": sx,
		"sz": sz,
		"n": n,
		"base": _mix_role(Vector4.ZERO, base_role, 1.0),
		"biome_channel": biome_channel,
		"biome_target": biome_target,
		"surface_channel": surface_channel,
		"surface_target": surface_target,
		"has_biomes": has_biomes,
		"has_surfaces": doc.surface_weights.size() == n * MapDocument.SURFACE_BYTES,
		"has_wet": doc.water_dressing.size() == n * 4,
		"surface_char": surface_char,
		"char_any": char_any,
		"biome_targets": biome_targets,
		"dominant": dominant,
		"biome_present": biome_any and has_biomes,
	}


## The biome zone map's channel (0 dry, 1 ash, 2 earth) of the map's dominant dry biome, -1 when
## none: the dry biome whose cells are at least a quarter of the map and more than any other
## biome's. `targets` is the channel of each biome slot (-1 for a biome that is none of them),
## `slots` the document's biome_slots. Such a map's whole ground paints in that role (a savanna is
## straw everywhere, not in patches). The cells are counted natively (PackedByteArray.count).
static func _dominant_channel(targets: PackedInt32Array, slots: PackedByteArray) -> int:
	var counts := PackedInt32Array()
	counts.resize(targets.size() + 1)
	for k in counts.size():
		counts[k] = slots.count(k)
	var best := -1
	var best_count := 0
	var other := 0
	for k in targets.size():
		if targets[k] >= 0 and counts[k + 1] > best_count:
			best = targets[k]
			best_count = counts[k + 1]
	for k in targets.size():
		if targets[k] != best:
			other = maxi(other, counts[k + 1])
	if best >= 0 and best_count * 4 >= slots.size() and best_count > other:
		return best
	return -1


## Whether `doc`'s ground is painted by one dry biome throughout (_dominant_channel): the zone map
## then drops the base surface's shore (a savanna or badlands map's base is sand).
static func has_dominant_dry(doc: MapDocument) -> bool:
	return doc.biome_slots.size() > 0 and int(plan(doc)["dominant"]) >= 0


## Appends the channel (0 r .. 3 a, -1 for a role the zone map has no channel for) and the value a
## ground role pulls its channel to (_mix_role's table), for the sample loop.
static func _role_channel(
	role: String, channels: PackedInt32Array, targets: PackedFloat32Array
) -> void:
	match role:
		"meadow":
			channels.append(0)
			targets.append(1.0)
		"floor":
			channels.append(0)
			targets.append(0.0)
		"path":
			channels.append(1)
			targets.append(1.0)
		"rock":
			channels.append(2)
			targets.append(1.0)
		"shore":
			channels.append(3)
			targets.append(1.0)
		_:
			channels.append(-1)
			targets.append(0.0)


## `v` (r meadow share, g path, b rock, a shore) moved `w` of the way to ground role `role`.
static func _mix_role(v: Vector4, role: String, w: float) -> Vector4:
	match role:
		"meadow":
			v.x = lerpf(v.x, 1.0, w)
		"floor":
			v.x = lerpf(v.x, 0.0, w)
		"path":
			v.y = lerpf(v.y, 1.0, w)
		"rock":
			v.z = lerpf(v.z, 1.0, w)
		"shore":
			v.w = lerpf(v.w, 1.0, w)
	return v


# ---------------------------------------------------------------- the whole maps (pure)


## The zone map of `doc` as an RGBA8 image (pure).
static func zone_image(doc: MapDocument) -> Image:
	var p := plan(doc)
	var grid := Rect2i(0, 0, p["sx"], p["sz"])
	return _image_of(grid, Image.FORMAT_RGBA8, zone_region(doc, p, grid))


## The scorched ground's share per height sample as an R8 image (the `char` role has no channel in
## the zone maps: it is rare, so its map exists only when the document names an ash surface, the
## scar a fire event stamps, and costs nothing else), null when it names none (pure; painter-fire).
## A burnt BIOME is not char: it is the `ash` role of the biome zone map (painter-coverage), and
## the scar lies over it. A surface weight is the share.
static func char_image(doc: MapDocument) -> Image:
	var p := plan(doc)
	if not p["char_any"]:
		return null
	var grid := Rect2i(0, 0, p["sx"], p["sz"])
	return _image_of(grid, Image.FORMAT_R8, char_region(doc, p, grid))


## The biome zone map of `doc` (card painter-coverage): an RGBA8 image, r the share of the dry
## biome's role (savanna straw), g ash (a burnt forest), b earth (the badlands); null when no biome
## of the map paints in one of those roles (the shader then never reads it). Pure.
static func biome_zone_image(doc: MapDocument) -> Image:
	var p := plan(doc)
	if not p["biome_present"]:
		return null
	var grid := Rect2i(0, 0, p["sx"], p["sz"])
	return _image_of(grid, Image.FORMAT_RGBA8, biome_region(doc, p, grid))


# ---------------------------------------------------------------- regions (pure)


## The zone map's bytes over `out` (RGBA8, row by row), from the samples of `out` grown by
## ZONE_BLUR. The document's arrays and the roles' channels are read once, outside the sample loop
## (a property read on the document costs more than the arithmetic it feeds). A channel no sample
## of the region moved off the base is one flat value, and a flat plane blurs to itself (the base
## is 0 or 1, which the three taps keep exactly).
static func zone_region(doc: MapDocument, p: Dictionary, out: Rect2i) -> PackedByteArray:
	var sx: int = p["sx"]
	var n: int = p["n"]
	var src := _source(p, out)
	var w := src.size.x
	var base: Vector4 = p["base"]
	var biome_channel: PackedInt32Array = p["biome_channel"]
	var biome_target: PackedFloat32Array = p["biome_target"]
	var surface_channel: PackedInt32Array = p["surface_channel"]
	var surface_target: PackedFloat32Array = p["surface_target"]
	var has_biomes: bool = p["has_biomes"]
	var has_surfaces: bool = p["has_surfaces"]
	var has_wet: bool = p["has_wet"]
	var slots := doc.biome_slots
	var density := doc.biome_density
	var weights := doc.surface_weights
	var wet := doc.water_dressing
	var biome_count := biome_channel.size()
	var surface_count := surface_channel.size()
	var m := w * src.size.y
	var plane_r := PackedFloat32Array()
	var plane_g := PackedFloat32Array()
	var plane_b := PackedFloat32Array()
	var plane_a := PackedFloat32Array()
	plane_r.resize(m)
	plane_g.resize(m)
	plane_b.resize(m)
	plane_a.resize(m)
	var touched := PackedByteArray([0, 0, 0, 0])
	var j := 0
	for z in range(src.position.y, src.end.y):
		for x in range(src.position.x, src.end.x):
			var i := z * sx + x
			var v := base
			if has_biomes:
				var slot := slots[i]
				if slot > 0 and slot <= biome_count:
					var channel := biome_channel[slot - 1]
					if channel >= 0:
						var pull := clampf(density[i] / 255.0 * PainterSurfaces.BIOME_PULL, 0.0, 1.0)
						v[channel] = lerpf(v[channel], biome_target[slot - 1], pull)
						touched[channel] = 1
			if has_surfaces:
				for e in 4:
					var wt := weights[n * 4 + i * 4 + e] / 255.0
					if wt > 0.0:
						var at := weights[i * 4 + e]
						if at < surface_count and surface_channel[at] >= 0:
							var channel := surface_channel[at]
							v[channel] = lerpf(v[channel], surface_target[at], wt)
							touched[channel] = 1
			if has_wet:
				var shore := maxf(wet[i * 4], wet[i * 4 + 1]) / 255.0
				if shore > v.w:
					v.w = shore
					touched[3] = 1
			plane_r[j] = v.x
			plane_g[j] = v.y
			plane_b[j] = v.z
			plane_a[j] = v.w
			j += 1
	var planes: Array[PackedFloat32Array] = [plane_r, plane_g, plane_b, plane_a]
	var bytes := PackedByteArray()
	bytes.resize(out.size.x * out.size.y * 4)
	for c in 4:
		if touched[c] == 0:
			var flat := clampi(roundi(base[c] * 255.0), 0, 255)
			for k in out.size.x * out.size.y:
				bytes[k * 4 + c] = flat
			continue
		_write(PainterFieldBlur.box(planes[c], w, src.size.y, 1), src, out, bytes, 4, c)
	return bytes


## The char map's bytes over `out` (R8), as zone_region reads its region.
static func char_region(doc: MapDocument, p: Dictionary, out: Rect2i) -> PackedByteArray:
	var sx: int = p["sx"]
	var n: int = p["n"]
	var src := _source(p, out)
	var surface_char: PackedByteArray = p["surface_char"]
	var weights := doc.surface_weights
	var has_surfaces: bool = p["has_surfaces"]
	var plane := PackedFloat32Array()
	plane.resize(src.size.x * src.size.y)
	var j := 0
	for z in range(src.position.y, src.end.y):
		for x in range(src.position.x, src.end.x):
			var i := z * sx + x
			var v := 0.0
			if has_surfaces:
				for e in 4:
					var wt := weights[n * 4 + i * 4 + e] / 255.0
					var at := weights[i * 4 + e]
					if wt > 0.0 and at < surface_char.size() and surface_char[at] == 1:
						v = maxf(v, wt)
			plane[j] = v
			j += 1
	var bytes := PackedByteArray()
	bytes.resize(out.size.x * out.size.y)
	_write(PainterFieldBlur.box(plane, src.size.x, src.size.y, 1), src, out, bytes, 1, 0)
	return bytes


## The biome zone map's bytes over `out` (RGBA8, a 0), as zone_region reads its region.
static func biome_region(doc: MapDocument, p: Dictionary, out: Rect2i) -> PackedByteArray:
	var sx: int = p["sx"]
	var src := _source(p, out)
	var targets: PackedInt32Array = p["biome_targets"]
	var dominant: int = p["dominant"]
	var slots := doc.biome_slots
	var density := doc.biome_density
	var m := src.size.x * src.size.y
	var planes: Array[PackedFloat32Array] = []
	for c in 3:
		var plane := PackedFloat32Array()
		plane.resize(m)
		planes.append(plane)
	var j := 0
	for z in range(src.position.y, src.end.y):
		for x in range(src.position.x, src.end.x):
			var i := z * sx + x
			var slot := slots[i]
			var own := -1
			if slot > 0 and slot <= targets.size():
				own = targets[slot - 1]
			if own >= 0 and own != dominant:
				planes[own][j] = clampf(density[i] / 255.0 * PainterSurfaces.BIOME_PULL, 0.0, 1.0)
			elif dominant >= 0 and (own == dominant or slot == 0):
				# The map's own dry biome paints the whole ground, not only where its scatter is dense.
				planes[dominant][j] = 1.0
			j += 1
	var bytes := PackedByteArray()
	bytes.resize(out.size.x * out.size.y * 4)
	for c in 3:
		_write(PainterFieldBlur.box(planes[c], src.size.x, src.size.y, 1), src, out, bytes, 4, c)
	return bytes


## The samples `out`'s texels read: `out` grown by ZONE_BLUR, inside the grid.
static func _source(p: Dictionary, out: Rect2i) -> Rect2i:
	return out.grow(PainterSurfaces.ZONE_BLUR).intersection(Rect2i(0, 0, p["sx"], p["sz"]))


## Writes the blurred `plane` (over `src`) into channel `c` of `bytes` (over `out`, `stride` bytes a
## texel), each value as a byte.
static func _write(
	plane: PackedFloat32Array,
	src: Rect2i,
	out: Rect2i,
	bytes: PackedByteArray,
	stride: int,
	c: int
) -> void:
	var w := src.size.x
	var k := c
	for z in range(out.position.y, out.end.y):
		var row := (z - src.position.y) * w - src.position.x
		for x in range(out.position.x, out.end.x):
			bytes[k] = clampi(roundi(plane[row + x] * 255.0), 0, 255)
			k += stride
