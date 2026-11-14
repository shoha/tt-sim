class_name PainterBaked
extends RefCounted

## The painted look's generated textures, baked: the ground's three brush masks, the trees' fourteen
## and the grass tufts' five dab layouts (PainterBrushes, PainterTreeBrushes, PainterTuftAtlas) are
## pure functions of their code, and drawing them in GDScript took about 0.5 s on the first Painted
## level of a session (painter-perf-cpu). Their base images are saved once, each array's layers
## stacked in one Image resource under painter/baked/ (godot --headless --script
## res://tools/bake_painter.gd), and loaded from there: a resource file goes into an export with the
## project's "all resources" filter, loading one is a read, and the mipmaps are cut again by the
## engine (Image.generate_mipmaps, the same call the generators end with). A name with no file is
## drawn by the generator as before, so the files are a cache and never the source:
## tests/unit/test_painter_baked.gd compares every array with its generator, so a changed brush
## fails there until the bake is run again.

const DIR := "res://painter/baked/"
const GROUND_BRUSHES := "ground_brushes"
const TREE_BRUSHES := "tree_brushes"
const TUFT_PREFIX := "tuft_"


## The baked array `array_name`, or null when there is no file (the caller draws it).
static func load_array(array_name: String) -> Texture2DArray:
	var path := file_path(array_name)
	if not ResourceLoader.exists(path):
		return null
	var strip := load(path) as Image
	if strip == null or strip.get_width() <= 0:
		return null
	var size := strip.get_width()
	var layers: Array[Image] = []
	for layer in strip.get_height() / size:
		var image := strip.get_region(Rect2i(0, layer * size, size, size))
		image.generate_mipmaps()
		layers.append(image)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array


## The baked file of `array_name`.
static func file_path(array_name: String) -> String:
	return DIR + array_name + ".res"


## Every baked array's name.
static func names() -> Array[String]:
	var out: Array[String] = [GROUND_BRUSHES, TREE_BRUSHES]
	for drawn in PainterTuftAtlas.drawn_widths():
		out.append(tuft_name(drawn))
	return out


## The baked name of the tuft array drawn at half width `drawn` (PainterTuftAtlas.drawn_width).
static func tuft_name(drawn: float) -> String:
	return TUFT_PREFIX + str(int(roundf(drawn * 1000.0)))


## The images the generator draws for `array_name` (pure), square and of one size and format.
static func generate(array_name: String) -> Array[Image]:
	if array_name == GROUND_BRUSHES:
		return PainterBrushes.images()
	if array_name == TREE_BRUSHES:
		return PainterTreeBrushes.images()
	for drawn in PainterTuftAtlas.drawn_widths():
		if tuft_name(drawn) == array_name:
			return PainterTuftAtlas.images(drawn)
	var none: Array[Image] = []
	return none


## `images` stacked top to bottom as one image, mipmaps left out (what the file holds).
static func stack(images: Array[Image]) -> Image:
	var first := images[0]
	var strip := Image.create(
		first.get_width(), first.get_height() * images.size(), false, first.get_format()
	)
	for i in images.size():
		var base := images[i].duplicate() as Image
		base.clear_mipmaps()
		strip.blit_rect(
			base, Rect2i(0, 0, base.get_width(), base.get_height()), Vector2i(0, i * base.get_height())
		)
	return strip


## Draws and saves every baked array; the names written (an empty list at the first failure).
static func bake_all() -> Array[String]:
	var written: Array[String] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for array_name in names():
		var strip := stack(generate(array_name))
		if ResourceSaver.save(strip, file_path(array_name)) != OK:
			return []
		written.append(array_name)
	return written
