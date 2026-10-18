class_name FireBook
extends Resource

## The fire's drawing book as a shipped resource (res://assets/fire/fire_book.res, Git LFS).
## The flames are drawn from it, not from noise: a few looping sequences of DRAWINGS drawings
## each, baked offline from a small 2D fire simulation (tools/fire_sim/bake_fire_book.py) and
## packed into this resource by tools/fire_sim/pack_fire_book.gd; tools/fire_sim/README.md has
## the procedure. Every peer ships the same book, so nothing about it travels over the network.
##
## Each layer is a TILE-sized RGBA8 Image with its mips, and stores what the draw thresholds, not
## colours: R the flame field (0.5 at the edge), G the heat (the colour ramp's input), B the
## sparks, A a soft halo. `layers` holds every sequence's drawings in turn (sequence k's drawing
## d at k * drawings + d), then one tiling tear layer at `tear_layer` (the last): R and G a
## pattern of creases and ridges the draw adds to the field and the heat at a few times the
## book's resolution, B the coarse lumps it fades to at the default zoom.
##
## The sequences are sorted by width class (0 a small lively flame, 1 a medium mass, 2 a wide
## mass). `class_first` holds each class's first sequence in x, y and z and the sequence count in
## w, so class c's sequences are class_first[c] up to class_first[c + 1] (a class with none
## borrows the next one's first). `seq_bounds` holds each sequence's used rectangle over all its
## drawings, in the tile's UV (left, top, right, bottom; top-left origin), one entry a sequence;
## the shader's array holds MAX_SEQUENCES, so its binder pads it.
##
## Images rather than a Texture2DArray, because Images serialise from a headless packer run.
## The runtime builds the GPU array once with create_texture() (the mips come from the Images,
## so no CPU mip work at load). `format` names the bake's binary layout ("TTFSIM02") and
## `source_sha256` the .bin the packer read, so a re-bake can be told from the shipped book.

const PATH := "res://assets/fire/fire_book.res"
const FORMAT := "TTFSIM02"
const TILE := Vector2i(96, 128)
## The flame shader's sequence array size.
const MAX_SEQUENCES := 16
const CLASSES := 3
## What a Git LFS pointer file starts with (a clone without `git lfs pull`).
const LFS_POINTER_PREFIX := "version https://git-lfs"

@export var format := FORMAT
@export var source_sha256 := ""
@export var tile := Vector2i.ZERO
@export var drawings := 0
@export var tear_layer := -1
@export var class_first := Vector4i.ZERO
@export var seq_bounds := PackedVector4Array()
@export var layers: Array[Image] = []


## The number of sequences (each `drawings` long).
func sequence_count() -> int:
	return seq_bounds.size()


## The layer index of sequence `sequence`'s drawing `drawing` (the drawing wraps round the loop).
func layer_of(sequence: int, drawing: int) -> int:
	return sequence * drawings + posmod(drawing, drawings)


## What is wrong with the book, or "" when it is whole: the format, the tile, the sequence count,
## the classes' order, the layer count, the tear layer's place and every layer's size, format
## and mips.
func problem() -> String:
	if format != FORMAT:
		return "format %s, expected %s" % [format, FORMAT]
	if tile != TILE:
		return "tile %s, expected %s" % [tile, TILE]
	var count := sequence_count()
	if count < 1 or count > MAX_SEQUENCES:
		return "%d sequences, expected 1 to %d" % [count, MAX_SEQUENCES]
	if drawings < 1:
		return "%d drawings a sequence" % drawings
	if class_first.w != count:
		return "class_first.w %d, expected the sequence count %d" % [class_first.w, count]
	for c in CLASSES:
		if class_first[c] < 0 or class_first[c] > class_first[c + 1]:
			return "class_first %s is not sorted" % class_first
	for b in seq_bounds:
		if b.x < 0.0 or b.y < 0.0 or b.z > 1.0 or b.w > 1.0 or b.x >= b.z or b.y >= b.w:
			return "sequence bounds %s outside the tile" % b
	var expected := count * drawings + 1
	if layers.size() != expected:
		return "%d layers, expected %d" % [layers.size(), expected]
	if tear_layer != expected - 1:
		return "tear layer %d, expected %d" % [tear_layer, expected - 1]
	for k in layers.size():
		var image := layers[k]
		if image == null:
			return "layer %d is missing" % k
		if image.get_size() != tile or image.get_format() != Image.FORMAT_RGBA8:
			return "layer %d is %s format %d" % [k, image.get_size(), image.get_format()]
		if not image.has_mipmaps():
			return "layer %d has no mips" % k
	return ""


## The book as one Texture2DArray (every layer, mips included), or null with an error when the
## layers do not build. The caller owns it; dropping the last reference frees the GPU copy.
func create_texture() -> Texture2DArray:
	var texture := Texture2DArray.new()
	var error := texture.create_from_images(layers)
	if error != OK:
		push_error("FireBook: the book's layers did not build a texture (%s)" % error_string(error))
		return null
	return texture


## True when the file at `path` is a Git LFS pointer rather than the book (a clone that never ran
## `git lfs pull`), so a failed load can say why.
static func is_lfs_pointer(path: String = PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var head := file.get_buffer(LFS_POINTER_PREFIX.length()).get_string_from_ascii()
	return head == LFS_POINTER_PREFIX
