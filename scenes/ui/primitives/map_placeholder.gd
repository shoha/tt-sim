class_name MapPlaceholder
extends ColorRect

## The picture of a map that has no thumbnail yet: the painted backdrop's world
## (shaders/ui_backdrop.gdshader, BackdropPaint) in a small rect, in place of a flat slab with an
## initial. Its light is the map's mood, read through the one table the backdrop reads
## (PaintedBackdrop.mood_of of LevelData.environment_preset), and its land and weather (the
## skyline, the poplars, the clouds, which side the sun stands) are drawn from a seed hashed from
## the map's key (its folder, so a rename keeps the picture). So a map's card, its row in the
## room and the screen behind it when it is selected all paint the same place in the same
## light. It sits inside a CardThumb well, which clips it to the well's shape.

const SHADER := preload("res://shaders/ui_backdrop.gdshader")

var _seed := 0.0
var _mood := 0


func _init() -> void:
	name = "Placeholder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	material = paint_material
	resized.connect(_repaint)


## Paint the map with the stable `key` (its folder, or its name when it has none) in the mood
## of environment preset `mood`.
func paint(key: String, mood: String = "") -> void:
	_seed = seed_of(key)
	_mood = PaintedBackdrop.mood_of(mood)
	_repaint()


## The seed the shapes are drawn from, in [0, 1): the same key always paints the same.
static func seed_of(key: String) -> float:
	return PaintedBackdrop.seed_of(key)


## The mood this picture is painted in (a PaintedBackdrop.Mood).
func mood() -> int:
	return _mood


func _repaint() -> void:
	var canvas := size if size.y > 0.0 else Vector2(160, 90)
	var paint_material := material as ShaderMaterial
	paint_material.set_shader_parameter(&"rect_size", canvas)
	# Still: a card's clouds hold their places, so a shelf of pictures does not shimmer.
	paint_material.set_shader_parameter(&"drift", 0.0)
	var composition := BackdropPaint.compose(_seed, canvas, null)
	var values := BackdropPaint.uniforms(BackdropPaint.look_of(_mood), composition)
	for param: String in values:
		paint_material.set_shader_parameter(StringName(param), values[param])
