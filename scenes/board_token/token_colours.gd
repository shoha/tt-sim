class_name TokenColours
extends RefCounted

## What colours a token shows, read from its meshes' palette textures, materials and vertex
## colours, and the one vivid colour that stands for it: the colour of its map pin
## (TokenMarkers) and of its ghost outline (TokenGhost). Static and cached by source, so a
## palette that every part of an avatar shares is read once for the whole map.

## The colour of a token whose colours cannot be read at all: a soft periwinkle, never white.
const NO_COLOUR := Color(0.62, 0.66, 0.78)
## Most vertex colours sampled from a mesh surface.
const VERTEX_SAMPLES := 64
## The hues (0..1, yellow-green to green) that `vivid` can count for less, and by how much.
const FOLIAGE_HUE_MIN := 0.17
const FOLIAGE_HUE_MAX := 0.45
const FOLIAGE_WEIGHT := 0.12
## The cache is emptied past this many sources (instance ids are never reused, so an entry
## for a freed palette is only dead weight).
const CACHE_LIMIT := 256

## Palette, material or mesh (by instance id) -> its colours.
static var _colours: Dictionary = {}
## Hash of a token's source and mesh ids -> its vivid colour.
static var _vivid: Dictionary = {}


## The most vivid of `colours` (saturation times value, ignoring near-white and near-black),
## made readable on the board: at least half saturated (unless it is grey) and bright.
## NO_COLOUR when there are none.
## With `avoid_foliage` the greens count for an eighth (a ghost line in leaf green is lost on the
## leaves it shows through: the line takes the token's next most vivid colour).
static func vivid(colours: PackedColorArray, avoid_foliage: bool = false) -> Color:
	var best := NO_COLOUR
	var best_score := -1.0
	for c in colours:
		if c.a < 0.5 or c.v < 0.12 or (c.s < 0.12 and c.v > 0.92):
			continue
		var score := c.s * c.v + 0.05 * c.v
		if avoid_foliage and c.s > 0.25 and c.h > FOLIAGE_HUE_MIN and c.h < FOLIAGE_HUE_MAX:
			score *= FOLIAGE_WEIGHT
		if score > best_score:
			best_score = score
			best = c
	if best_score < 0.0:
		return NO_COLOUR
	# A grey token keeps a grey pin (forcing saturation on it would paint it pink).
	var saturation := best.s if best.s < 0.15 else maxf(best.s, 0.5)
	return Color.from_hsv(best.h, saturation, maxf(best.v, 0.8))


## Up to `count` colours spread over a vertex colour array, each times `tint` (the material's
## albedo colour).
static func sample_colours(
	vertex_colours: PackedColorArray, tint: Color, count: int = VERTEX_SAMPLES
) -> PackedColorArray:
	var out := PackedColorArray()
	var step := maxi(1, vertex_colours.size() / maxi(count, 1))
	for i in range(0, vertex_colours.size(), step):
		out.append(vertex_colours[i] * tint)
	return out


## The colours of every mesh in `meshes` (TokenGhost.source_of for each), joined.
static func colours_of_meshes(meshes: Array[MeshInstance3D]) -> PackedColorArray:
	var out := PackedColorArray()
	for mi in meshes:
		out.append_array(colours_of(TokenGhost.source_of(mi), mi.mesh))
	return out


## A token's vivid colour (`vivid` of all its meshes' colours), remembered per set of sources
## and meshes: a token is dressed again at every highlight, and an avatar has about 18 meshes.
static func vivid_of_meshes(
	meshes: Array[MeshInstance3D], avoid_foliage: bool = false
) -> Color:
	var ids := PackedInt64Array([1 if avoid_foliage else 0])
	for mi in meshes:
		var source: Variant = TokenGhost.source_of(mi)
		ids.append((source as Object).get_instance_id() if source != null else 0)
		ids.append(mi.mesh.get_instance_id())
	var key := hash(ids)
	if _vivid.has(key):
		return _vivid[key]
	var out := vivid(colours_of_meshes(meshes), avoid_foliage)
	if _vivid.size() >= CACHE_LIMIT:
		_vivid.clear()
	_vivid[key] = out
	return out


## The colours a mesh source (a palette texture or a material) shows, a few dozen at most. A
## material that takes its colour from the vertices (the free "chunky" game art does, its
## albedo is plain white) is read from the mesh's vertex colours, which was the white pin.
static func colours_of(source: Variant, mesh: Mesh) -> PackedColorArray:
	var out := PackedColorArray()
	if source == null:
		return out
	var from_vertices := (
		source is BaseMaterial3D
		and (source as BaseMaterial3D).vertex_color_use_as_albedo
		and mesh != null
	)
	var key: int = mesh.get_instance_id() if from_vertices else (source as Object).get_instance_id()
	if _colours.has(key):
		return _colours[key]
	var texture: Texture2D = null
	if source is Texture2D:
		texture = source
	elif source is BaseMaterial3D:
		var material := source as BaseMaterial3D
		if from_vertices:
			out.append_array(sample_colours(_vertex_colours(mesh), material.albedo_color))
		else:
			out.append(material.albedo_color)
		texture = material.albedo_texture
	if texture != null:
		var image := texture.get_image()
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			if image.get_width() * image.get_height() > 1024:
				image.resize(16, 16, Image.INTERPOLATE_NEAREST)
			for y in image.get_height():
				for x in image.get_width():
					out.append(image.get_pixel(x, y))
	if _colours.size() >= CACHE_LIMIT:
		_colours.clear()
	_colours[key] = out
	return out


## Every surface's vertex colours, spread to at most VERTEX_SAMPLES each.
static func _vertex_colours(mesh: Mesh) -> PackedColorArray:
	var out := PackedColorArray()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var colours: Variant = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR else null
		if colours is PackedColorArray:
			out.append_array(sample_colours(colours, Color.WHITE))
	return out
