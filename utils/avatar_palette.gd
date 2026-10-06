class_name AvatarPalette
extends RefCounted

## The per-figure gradient palette of an avatar (docs/ASSET_PIPELINE.md section 10 "Colour"),
## a port of figurine's `palette.py` `build_palette` that matches it byte for byte.
##
## A figure's colour comes from one 8 x 64 texture: a column per colour slot in the fixed
## order of SLOTS, each a vertical gradient from the slot's shadow colour (v = 0, the bottom
## row) through its base colour (v = 0.5) to its highlight (v = 1, the top row). A part's UV.x
## picks the column centre and UV.y (glTF v, down) places the vertex along it, so the image is
## stored the way it is sampled: row 0 is the highlight end. Each half of a column eases by
## smoothstep and interpolates the encoded sRGB values, sampled at texel centres
## (v = (row + 0.5) / 64), and every channel is stored as floor(x * 255 + 0.5), which is what
## paintkit's PNG writer does with figurine's floats.
##
## A colour is a triple of "#rrggbb" strings, (base, shadow, highlight), picked by index from
## the kit's `colour_sets`; `primary`, `secondary` and `accent` all pick from `cloth`.

const SLOTS: Array[String] = [
	"skin", "hair", "eyes", "primary", "secondary", "accent", "leather", "metal"
]
const SET_FOR_SLOT := {
	"skin": "skin",
	"hair": "hair",
	"eyes": "eyes",
	"primary": "cloth",
	"secondary": "cloth",
	"accent": "cloth",
	"leather": "leather",
	"metal": "metal",
}
const WIDTH := 8
const HEIGHT := 64


## The column of `slot` (its index in SLOTS), or -1.
static func slot_index(slot: String) -> int:
	return SLOTS.find(slot)


## UV.x of a slot's column centre.
static func slot_u(slot: String) -> float:
	return (slot_index(slot) + 0.5) / WIDTH


## "#rrggbb" as three floats in 0..1 (the encoded sRGB values, in double precision).
static func hex_to_rgb(code: String) -> PackedFloat64Array:
	var c := code.trim_prefix("#")
	return PackedFloat64Array(
		[
			c.substr(0, 2).hex_to_int() / 255.0,
			c.substr(2, 2).hex_to_int() / 255.0,
			c.substr(4, 2).hex_to_int() / 255.0,
		]
	)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Colour (encoded sRGB floats) at palette position v for one triple: shadow -> base over
## [0, 0.5], base -> highlight over [0.5, 1], each half eased by smoothstep.
static func gradient(triple: Array, v: float) -> PackedFloat64Array:
	var base := hex_to_rgb(String(triple[0]))
	var shadow := hex_to_rgb(String(triple[1]))
	var high := hex_to_rgb(String(triple[2]))
	var t := clampf(v, 0.0, 1.0)
	var out := PackedFloat64Array([0.0, 0.0, 0.0])
	if t < 0.5:
		var lower := _smooth(clampf(t / 0.5, 0.0, 1.0))
		for c in 3:
			out[c] = shadow[c] + (base[c] - shadow[c]) * lower
	else:
		var upper := _smooth(clampf((t - 0.5) / 0.5, 0.0, 1.0))
		for c in 3:
			out[c] = base[c] + (high[c] - base[c]) * upper
	return out


## The triple each slot uses for a set of picks (slot -> index into its set). A missing or
## out-of-range pick takes the set's first entry, as figurine's `resolve_colours` does.
static func resolve_triples(colour_sets: Dictionary, picks: Dictionary) -> Dictionary:
	var out := {}
	for slot in SLOTS:
		var entries: Array = colour_sets.get(SET_FOR_SLOT[slot], [])
		if entries.is_empty():
			out[slot] = ["#808080", "#404040", "#c0c0c0"]
			continue
		var index := int(picks.get(slot, 0))
		out[slot] = entries[index] if index >= 0 and index < entries.size() else entries[0]
	return out


## The figure palette as an 8 x 64 RGB8 image, row 0 the highlight end (glTF v = 0).
static func build_image(colour_sets: Dictionary, picks: Dictionary) -> Image:
	var triples := resolve_triples(colour_sets, picks)
	var data := PackedByteArray()
	data.resize(WIDTH * HEIGHT * 3)
	for row in HEIGHT:
		# Image row 0 is the top of the PNG, which is v = 1 in figurine's bottom-up array.
		var v := (HEIGHT - 1 - row + 0.5) / HEIGHT
		for col in WIDTH:
			var rgb := gradient(triples[SLOTS[col]], v)
			for c in 3:
				data[(row * WIDTH + col) * 3 + c] = floori(clampf(rgb[c], 0.0, 1.0) * 255.0 + 0.5)
	return Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, data)


## The palette as a texture for the figure shader.
static func build_texture(colour_sets: Dictionary, picks: Dictionary) -> ImageTexture:
	return ImageTexture.create_from_image(build_image(colour_sets, picks))
