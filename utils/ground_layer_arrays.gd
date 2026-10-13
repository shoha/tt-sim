class_name GroundLayerArrays
extends RefCounted

## The four Texture2DArrays (albedo, normal, ORM, height) an authored map's ground draws its
## surfaces from (ground layers card G3; the shader's LAYERS, the list from GroundLayers):
## layer j of each array is surface j of the map's layer list, the base at layer 0.
##
## The arrays hold a capacity of layers (GroundLayers.CAPACITY_STEPS: 16, 32, 64); layers past
## the list repeat layer 0, which the shader never reads. sync() brings them to a new list:
## a list that only appends to the bound one updates the new layers in place
## (ImageTextureLayered.update_layer, the textures and so the material bindings stay); a list
## past the capacity, or one that changed a bound layer (a load's compaction), recreates them.
##
## Images come from the palette's imported textures (Texture2D.get_image(), about 1 ms per map
## and 10 ms per height map, so roughly 0.15 s on a load for a ten-surface map). The palette
## contract (docs/ASSET_PIPELINE.md section 9) gives every map of one kind the same size, mip
## chain and format (1024, BC7 / BC5 / BC1 / L8), which an array requires. A surface that
## breaks it, or a map that is missing (a surface the palette lacks: the fallback earth), is
## not refused: that kind's whole array is rebuilt uncompressed at the first image's size
## (decompressed, converted, resized, mipmapped; solid stand-ins for missing maps), with a
## warning, so the map still draws.

const KINDS: PackedStringArray = ["albedo", "normal", "orm", "height"]
## Ground shader uniform per kind.
const UNIFORMS := {
	"albedo": "layer_albedo_array",
	"normal": "layer_normal_array",
	"orm": "layer_orm_array",
	"height": "layer_height_array",
}
## Stand-in colours for a missing map: the fallback earth, a flat normal, rough, mid height.
const DEFAULTS := {
	"albedo": Color(0.36, 0.33, 0.26),
	"normal": Color(0.5, 0.5, 1.0),
	"orm": Color(1.0, 0.9, 0.0),
	"height": Color(0.5, 0.5, 0.5),
}
## Size of a stand-in when no layer of a kind has an image at all.
const STAND_IN_SIZE := 4

## The surfaces bound, in layer order, and the arrays' capacity in layers.
var layers := PackedStringArray()
var capacity: int = 0
## Kind -> Texture2DArray.
var textures: Dictionary = {}
## Milliseconds the last sync() spent reading images back and building the arrays.
var last_sync_ms: float = 0.0

var _warned: Dictionary = {}


## Brings the arrays to layer list `wanted` from palette `root`. Returns true when the
## textures were created anew (the caller rebinds them), false when they were updated in
## place or already matched.
func sync(wanted: PackedStringArray, root: String) -> bool:
	var started := Time.get_ticks_usec()
	var appended := (
		not textures.is_empty()
		and wanted.size() >= layers.size()
		and wanted.slice(0, layers.size()) == layers
		and GroundLayers.capacity(wanted.size()) <= capacity
	)
	var recreated := false
	if appended:
		for kind in KINDS:
			if not _append(kind, wanted, root):
				recreated = true
		if recreated:
			_create(wanted, root)
	else:
		_create(wanted, root)
		recreated = true
	layers = wanted.duplicate()
	last_sync_ms = (Time.get_ticks_usec() - started) / 1000.0
	return recreated


## Sets the four array uniforms on `material`.
func bind(material: ShaderMaterial) -> void:
	for kind in KINDS:
		material.set_shader_parameter(UNIFORMS[kind], textures.get(kind))


## Updates the layers `wanted` adds to the bound list in kind `kind`'s array; false when an
## image does not fit the array (the caller recreates it).
func _append(kind: String, wanted: PackedStringArray, root: String) -> bool:
	var array: Texture2DArray = textures[kind]
	var size := Vector2i(array.get_width(), array.get_height())
	# An array already drawn uncompressed takes any image, converted, or a stand-in.
	var conformed := array.get_format() == Image.FORMAT_RGBA8
	for j in range(layers.size(), wanted.size()):
		var image := surface_image(wanted[j], kind, root)
		if conformed and (image == null or not _fits(image, array)):
			image = _uncompressed(image, size, DEFAULTS[kind])
		if image == null or not _fits(image, array):
			return false
		array.update_layer(image, j)
	return true


func _create(wanted: PackedStringArray, root: String) -> void:
	capacity = GroundLayers.capacity(maxi(wanted.size(), 1))
	textures.clear()
	for kind in KINDS:
		var images: Array[Image] = []
		for surface in wanted:
			images.append(surface_image(surface, kind, root))
		if images.is_empty():
			images.append(null)
		images = _conformed(images, kind, wanted)
		while images.size() < capacity:
			images.append(images[0])
		var array := Texture2DArray.new()
		var error := array.create_from_images(images)
		if error != OK:
			push_warning("GroundLayerArrays: the %s array failed to build (%s)" % [kind, error])
		textures[kind] = array


## `images` as one array can take them: as they are when they agree in size, format and
## mipmaps and none is missing, else all uncompressed at the first image's size.
func _conformed(images: Array[Image], kind: String, wanted: PackedStringArray) -> Array[Image]:
	var reference: Image = null
	for image in images:
		if image != null:
			reference = image
			break
	var agree := reference != null
	var missing := false
	for image in images:
		missing = missing or image == null
		agree = (
			agree
			and image != null
			and image.get_size() == reference.get_size()
			and image.get_format() == reference.get_format()
			and image.has_mipmaps() == reference.has_mipmaps()
		)
	if agree:
		return images
	# A missing map (a surface the palette lacks) was warned about where it was named; a
	# mismatch breaks the palette contract and is worth its own warning.
	if reference != null and not missing and not _warned.has(kind):
		_warned[kind] = true
		push_warning(
			(
				"GroundLayerArrays: the %s maps of %s differ or are missing; drawing them uncompressed"
				% [kind, str(wanted)]
			)
		)
	var size := reference.get_size() if reference != null else Vector2i.ONE * STAND_IN_SIZE
	var out: Array[Image] = []
	for image in images:
		out.append(_uncompressed(image, size, DEFAULTS[kind]))
	return out


## The solid stand-in for a missing map of `kind` (DEFAULTS), RGBA8 at `size` with mipmaps.
static func stand_in(size: Vector2i, kind: String) -> Image:
	return _uncompressed(null, size, DEFAULTS[kind])


## `image` (or a solid `fallback` when null) as RGBA8 at `size` with mipmaps.
static func _uncompressed(image: Image, size: Vector2i, fallback: Color) -> Image:
	var out: Image
	if image == null:
		out = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		out.fill(fallback)
	else:
		out = image.duplicate() as Image
		if out.is_compressed() and out.decompress() != OK:
			out = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
			out.fill(fallback)
		out.clear_mipmaps()
		out.convert(Image.FORMAT_RGBA8)
		if out.get_size() != size:
			out.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	out.generate_mipmaps()
	return out


## True when `image` can go into `array` as a layer.
static func _fits(image: Image, array: Texture2DArray) -> bool:
	return (
		image.get_size() == Vector2i(array.get_width(), array.get_height())
		and image.get_format() == array.get_format()
		and image.has_mipmaps() == array.has_mipmaps()
	)


## The image of map `kind` of palette surface `surface`, or null when the palette has none.
static func surface_image(surface: String, kind: String, root: String) -> Image:
	var info: Dictionary = PaletteLibrary.surfaces(root).get(surface, {})
	var texture := GroundPalette.load_texture(root, String(info.get(kind, "")))
	if texture == null:
		return null
	var image := texture.get_image()
	return image if image != null and not image.is_empty() else null
