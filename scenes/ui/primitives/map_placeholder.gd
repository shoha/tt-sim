class_name MapPlaceholder
extends ColorRect

## The picture of a map that has no thumbnail yet: a small painted landscape (a sky with a
## soft sun, a far ridge in haze, a near landform and a foreground slope), drawn by
## shaders/ui_map_placeholder.gdshader in place of a flat slab with an initial. Every map
## paints its own. The shapes come from a seed hashed from the map's key (its folder, so a
## rename keeps the picture) and the colours from its mood (LevelData.environment_preset): a
## sunset or a tavern paints dusk, night and the underground a moonlit blue, arctic snow,
## desert sand; any other mood, or none, one of the six day palettes, which the key picks.
## The library card and the room paint the same map the same way. It sits inside a CardThumb
## well, which clips it to the well's shape.

const SHADER := preload("res://shaders/ui_map_placeholder.gdshader")
## The shader's palettes by index: the day palettes first (meadow, golden hills, heather,
## lakeside, spring blossom, teal coast), then the moods.
const DAY_PALETTES := 6
const LAKESIDE := 3
const DUSK := 6
const NIGHT := 7
const SNOW := 8
const SAND := 9
## Moods with a palette of their own.
const MOOD_PALETTES := {
	"outdoor_sunset": DUSK,
	"tavern": DUSK,
	"hell": DUSK,
	"outdoor_night": NIGHT,
	"dungeon_dark": NIGHT,
	"dungeon_crypt": NIGHT,
	"cave": NIGHT,
	"underwater": NIGHT,
	"ethereal": NIGHT,
	"arctic": SNOW,
	"desert": SAND,
	"swamp": LAKESIDE,
}


func _init() -> void:
	name = "Placeholder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	material = paint_material
	resized.connect(_fit_aspect)


## Paint the map with the stable `key` (its folder, or its name when it has none) in `mood`.
func paint(key: String, mood: String = "") -> void:
	var paint_material := material as ShaderMaterial
	paint_material.set_shader_parameter(&"seed", seed_of(key))
	paint_material.set_shader_parameter(&"palette", palette_of(key, mood))


## The seed the shapes are drawn from, in [0, 1): the same key always paints the same. MD5
## rather than String.hash(), whose high bits barely move between short keys.
static func seed_of(key: String) -> float:
	var digest := key.md5_buffer()
	return float(digest[1] << 8 | digest[2]) / 65536.0


## The palette `key` paints in under `mood`: the mood's own, or a day palette the key picks.
static func palette_of(key: String, mood: String) -> int:
	if MOOD_PALETTES.has(mood):
		return MOOD_PALETTES[mood]
	return key.md5_buffer()[0] % DAY_PALETTES


func _fit_aspect() -> void:
	if size.y > 0.0:
		(material as ShaderMaterial).set_shader_parameter(&"aspect", size.x / size.y)
