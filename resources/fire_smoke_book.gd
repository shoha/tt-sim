class_name FireSmokeBook
extends Resource

## The persistent fire's smoke book as a shipped resource (res://assets/fire/fire_smoke_book.res,
## Git LFS). The smoke columns (FireFieldSmoke) are drawn from it instead of being worked out per
## pixel: SEEDS plumes, each a closed loop of FRAMES held frames, baked once offline by a windowed
## render-job probe (tools/render_jobs/probes/fire_smoke_book.gd with
## tools/fire_sim/fire_smoke_book_bake.gdshader; tools/fire_sim/README.md has the procedure).
## Every peer ships the same book, so nothing about it travels over the network.
##
## Each layer is a TILE-sized RGBA8 Image, no mips (the draw reads it with a plain linear
## filter), and stores what the draw shader (shaders/fire_smoke_book.gdshader) tones, not
## colours: R the plume's signed distance (inside positive), G and B the fake normal's x and y,
## A the tone's multiplier. Seed k's frame f is layer k * frames + f. The frame spans `domain` in
## the column's units (its half width, its foot and its top above the source), and the plume
## was baked at the column's `rise` and `width` (FireFieldSmoke.RISE and WIDTH), which the draw
## must match for the lobes' edges and the opacity profile to line up.
##
## Images rather than a Texture2DArray, because Images serialise from any run; the runtime
## builds the GPU array once with create_texture(). FireBook is the flames' book; its layout
## (sequences, classes, a tear layer, mips) does not fit this one, so the two stay apart.

const PATH := "res://assets/fire/fire_smoke_book.res"
const FORMAT := "TTSMOKE1"
const TILE := Vector2i(128, 160)
const SEEDS := 2
const FRAMES := 24
const DOMAIN := Vector3(1.8, -0.45, 4.15)

@export var format := FORMAT
@export var tile := Vector2i.ZERO
@export var seeds := 0
@export var frames := 0
@export var domain := Vector3.ZERO
@export var rise := 0.0
@export var width := Vector2.ZERO
@export var layers: Array[Image] = []


## The layer index of seed `seed`'s frame `frame` (the frame wraps round the loop).
func layer_of(seed: int, frame: int) -> int:
	return seed * frames + posmod(frame, frames)


## What is wrong with the book, or "" when it is whole: the format, the tile, the seed and frame
## counts, the layer count and every layer's size and format.
func problem() -> String:
	if format != FORMAT:
		return "format %s, expected %s" % [format, FORMAT]
	if tile != TILE:
		return "tile %s, expected %s" % [tile, TILE]
	if seeds < 1 or frames < 2:
		return "%d seeds of %d frames" % [seeds, frames]
	if layers.size() != seeds * frames:
		return "%d layers, expected %d" % [layers.size(), seeds * frames]
	for k in layers.size():
		var image := layers[k]
		if image == null:
			return "layer %d is missing" % k
		if image.get_size() != tile or image.get_format() != Image.FORMAT_RGBA8:
			return "layer %d is %s format %d" % [k, image.get_size(), image.get_format()]
	return ""


## The book as one Texture2DArray (every layer), or null with an error when the layers do not
## build. The caller owns it; dropping the last reference frees the GPU copy.
func create_texture() -> Texture2DArray:
	var texture := Texture2DArray.new()
	var error := texture.create_from_images(layers)
	if error != OK:
		push_error("FireSmokeBook: the layers did not build a texture (%s)" % error_string(error))
		return null
	return texture
