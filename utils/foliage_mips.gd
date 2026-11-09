class_name FoliageMips
extends RefCounted

## Mipmaps for the textures of a library asset's mesh. Godot's runtime glTF parse
## (AssetStore._parse) makes every texture an ImageTexture with no mipmaps, while the foliage
## shaders ask for mipmapped
## filtering (`filter_linear_mipmap`, which then does nothing), so a card minified by distance,
## zoom-out or a small token read the full-size texture on every fetch: aliasing in motion and a
## texture cache that cannot hold the working set (docs/PERFORMANCE.md "Foliage mipmaps").
##
## apply() gives each texture of the mesh's materials a mip chain, the way Godot's own importer
## does for a texture it imports, plus the one thing a cutout needs that the importer does not do:
##
## - albedo with alpha (grass blades, leaf cards: the foliage shaders cut at alpha 0.5):
##   transparent texels get the colour of their opaque neighbours before the chain is built (the
##   importer's "fix alpha border", so a leaf edge does not darken with distance), and each mip's
##   alpha is scaled until the share of texels at or above the cutoff equals the base image's
##   (alpha coverage preservation). A plain box filter halves a one-texel blade's alpha at every
##   level and the card thins out and vanishes with distance; this keeps it as dense as it is up
##   close. The base level's bytes are never touched.
## - a normal map: generate_mipmaps(renormalize), which keeps the vectors unit length.
## - anything else (ORM, opaque albedo): a plain chain.
##
## Pure statics, no scene tree: it runs on the worker that parses the GLB. An image that already
## has mipmaps, is compressed, or is not 8 bits per channel is left alone.

enum Role { ALBEDO, NORMAL, DATA }

## The foliage shaders' alpha_scissor_threshold (shaders/wind_foliage_include.gdshaderinc), as the
## smallest 8-bit alpha that survives the cut.
const CUTOFF_BYTE := 128
## At most this many alpha samples per level are read to find the scale (the image is read in a
## stride; the quantile of 2,048 samples is within a percent or two of the full level's).
const SAMPLES := 2048
## The largest factor a level's alpha is scaled by; a level that needs more is already nearly empty.
const MAX_SCALE := 16.0


## Replaces each texture of `mesh`'s BaseMaterial3D surfaces by a mipmapped copy (one copy per
## distinct source texture, so a texture shared between slots stays shared). Returns
## {"textures": converted, "bytes_before": total bytes of the sources, "bytes_after": of the
## copies, "cutouts": albedo textures that got alpha coverage preservation}.
static func apply(mesh: Mesh) -> Dictionary:
	var stats := {"textures": 0, "bytes_before": 0, "bytes_after": 0, "cutouts": 0}
	if mesh == null:
		return stats
	var done := {}
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			continue
		_convert(material, "albedo_texture", Role.ALBEDO, done, stats)
		_convert(material, "normal_texture", Role.NORMAL, done, stats)
		_convert(material, "metallic_texture", Role.DATA, done, stats)
		_convert(material, "roughness_texture", Role.DATA, done, stats)
		_convert(material, "ao_texture", Role.DATA, done, stats)
		if material is ORMMaterial3D:
			_convert(material, "orm_texture", Role.DATA, done, stats)
	return stats


## `source` with a mip chain: see the class comment for what each role gets. Returns `source`'s
## duplicate unchanged when it cannot take one.
static func with_mips(source: Image, role: Role) -> Image:
	var image := source.duplicate() as Image
	if image.has_mipmaps() or image.is_compressed() or image.is_empty():
		return image
	var format := image.get_format()
	if format != Image.FORMAT_RGBA8 and format != Image.FORMAT_RGB8 and format != Image.FORMAT_L8:
		image.convert(Image.FORMAT_RGBA8)
		format = Image.FORMAT_RGBA8
	if role == Role.ALBEDO and format == Image.FORMAT_RGBA8:
		if image.detect_alpha() != Image.ALPHA_NONE:
			return _cutout_chain(image)
	image.generate_mipmaps(role == Role.NORMAL)
	return image


## The share of texels of mip `level` whose alpha is at or above the cutoff (every texel, not a
## sample): what coverage preservation holds constant down the chain.
static func coverage(image: Image, level: int = 0) -> float:
	var data := image.get_data()
	var first := image.get_mipmap_offset(level)
	var last := image.get_mipmap_offset(level + 1) if level < image.get_mipmap_count() else data.size()
	if last <= first:
		return 0.0
	var seen := 0
	for at in range(first + 3, last, 4):
		if data[at] >= CUTOFF_BYTE:
			seen += 1
	return float(seen) / float((last - first) / 4)


## A cutout albedo's chain: the base level untouched, the others built from an edge-fixed copy
## and scaled to the base level's coverage.
static func _cutout_chain(image: Image) -> Image:
	var width := image.get_width()
	var height := image.get_height()
	var original := image.get_data()
	var target := _sampled_coverage(original, 0, original.size())
	var fixed := image.duplicate() as Image
	fixed.fix_alpha_edges()
	fixed.generate_mipmaps()
	var chain := fixed.get_data()
	var data := original + chain.slice(original.size())
	if target > 0.0 and target < 0.999:
		for level in range(1, fixed.get_mipmap_count() + 1):
			var first := fixed.get_mipmap_offset(level)
			var last := chain.size()
			if level < fixed.get_mipmap_count():
				last = fixed.get_mipmap_offset(level + 1)
			_scale_alpha(data, first, last, target)
	return Image.create_from_data(width, height, true, Image.FORMAT_RGBA8, data)


## Scales the alpha bytes of the level at data[first, last) so that the share at or above the
## cutoff is `target`.
static func _scale_alpha(data: PackedByteArray, first: int, last: int, target: float) -> void:
	var samples := _alpha_samples(data, first, last)
	var at := clampi(int((1.0 - target) * samples.size()), 0, samples.size() - 1)
	var quantile := maxi(samples[at], 1)
	if quantile >= CUTOFF_BYTE:
		return  # the level already holds at least the base coverage
	var scale := minf(float(CUTOFF_BYTE) / float(quantile), MAX_SCALE)
	var table := PackedByteArray()
	table.resize(256)
	for a in 256:
		table[a] = mini(255, int(float(a) * scale + 0.5))
	for byte_at in range(first + 3, last, 4):
		data[byte_at] = table[data[byte_at]]


## Sorted alpha bytes sampled in a stride across the level at data[first, last).
static func _alpha_samples(data: PackedByteArray, first: int, last: int) -> PackedByteArray:
	var texels := (last - first) / 4
	var stride := maxi(texels / SAMPLES, 1) | 1
	var out := PackedByteArray()
	for texel in range(0, texels, stride):
		out.append(data[first + texel * 4 + 3])
	out.sort()
	return out


## The share of sampled texels of data[first, last) at or above the cutoff.
static func _sampled_coverage(data: PackedByteArray, first: int, last: int) -> float:
	var samples := _alpha_samples(data, first, last)
	if samples.is_empty():
		return 0.0
	var seen := 0
	for alpha in samples:
		if alpha >= CUTOFF_BYTE:
			seen += 1
	return float(seen) / float(samples.size())


static func _convert(
	material: BaseMaterial3D, property: String, role: Role, done: Dictionary, stats: Dictionary
) -> void:
	var texture := material.get(property) as Texture2D
	if texture == null:
		return
	var key := texture.get_instance_id()
	if not done.has(key):
		done[key] = _mipped(texture, role, stats)
	if done[key] != texture:
		material.set(property, done[key])


## `texture` as an ImageTexture with a mip chain, or `texture` itself when it cannot take one
## (compressed, already chained, or without readable pixels).
static func _mipped(texture: Texture2D, role: Role, stats: Dictionary) -> Texture2D:
	var source := texture.get_image()
	if source == null or source.is_empty() or source.has_mipmaps() or source.is_compressed():
		return texture
	var chained := with_mips(source, role)
	if not chained.has_mipmaps():
		return texture
	stats["textures"] += 1
	stats["bytes_before"] += source.get_data().size()
	stats["bytes_after"] += chained.get_data().size()
	if role == Role.ALBEDO and source.detect_alpha() != Image.ALPHA_NONE:
		stats["cutouts"] += 1
	return ImageTexture.create_from_image(chained)
