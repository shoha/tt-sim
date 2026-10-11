class_name MapPlaceholder
extends ColorRect

## The picture of a map that has no thumbnail yet: a gentle diagonal gradient in the map's
## mood (shaders/ui_backdrop.gdshader, BackdropPaint) with the map's initial over it in Inter
## semibold (the H3 role, as a player's portrait shows theirs), sized to the picture. Its light
## is read through the one table the backdrop reads (PaintedBackdrop.mood_of of
## LevelData.environment_preset), so a map's card, its row in the room and the screen behind it
## when it is selected share one light. The initial is in ink or paper, whichever reads better
## on the middle of the mood's gradient (ink_on). It sits inside a CardThumb well, which clips
## it to the well's shape.

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## How far the gradient leans from straight down (the shader's tilt): a gentle diagonal.
const TILT := 0.5
## The initial's size as a share of the picture's height, never under the H3 role's own.
const INITIAL_SHARE := 0.4
const INITIAL_MIN := 16
## The stretch of the gradient (0 the horizon, 1 the top) the initial stands over.
const INITIAL_SPAN: Array[float] = [0.3, 0.5, 0.7]

var _mood := 0
var _initial: Label


func _init() -> void:
	name = "Placeholder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	paint_material.set_shader_parameter(&"tilt", TILT)
	material = paint_material
	_initial = Label.new()
	_initial.name = "Initial"
	_initial.theme_type_variation = &"H3"
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Its size and ink ride on label settings with no font, so the H3 role's font still draws.
	_initial.label_settings = LabelSettings.new()
	_initial.label_settings.font_size = INITIAL_MIN
	add_child(_initial)
	resized.connect(_on_resized)
	_set_look(BackdropPaint.look_of(_mood))


## Paint the map with the stable `key` (its folder, or its name when it has none) in the mood
## of environment preset `mood`, with the initial of `title` (its name; the key's without one).
func paint(key: String, mood: String = "", title: String = "") -> void:
	_mood = PaintedBackdrop.mood_of(mood)
	_set_look(BackdropPaint.look_of(_mood))
	_initial.text = LevelCard.initial_of(title if title != "" else key)


## The seed a key draws from, in [0, 1): the same key always draws the same (BiomeThumbnail
## draws its skyline from it). MD5 rather than String.hash(), whose high bits barely move
## between short keys.
static func seed_of(key: String) -> float:
	var digest := key.md5_buffer()
	return float(digest[1] << 8 | digest[2]) / 65536.0


## The mood this picture is painted in (a PaintedBackdrop.Mood).
func mood() -> int:
	return _mood


## The colour an initial is drawn in over `look`'s gradient: ink or paper, whichever keeps the
## higher contrast across the stretch the initial stands over.
static func ink_on(look: Dictionary) -> Color:
	var best := ThemeColors.INK
	var best_ratio := -1.0
	for ink: Color in [ThemeColors.INK, ThemeColors.PAPER]:
		var worst := INF
		for t: float in INITIAL_SPAN:
			var sky := _sky_luminance(BackdropPaint.colour_at(look, t))
			var lum := _luminance(ink)
			worst = minf(worst, (maxf(lum, sky) + 0.05) / (minf(lum, sky) + 0.05))
		if worst > best_ratio:
			best = ink
			best_ratio = worst
	return best


## WCAG 2.x contrast ratio of two opaque colours.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


## The relative luminance of an sRGB colour given as the shader's vec3.
static func _sky_luminance(rgb: Vector3) -> float:
	var lin := Vector3(_linear(rgb.x), _linear(rgb.y), _linear(rgb.z))
	return 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z


static func _linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _set_look(look: Dictionary) -> void:
	var paint_material := material as ShaderMaterial
	var stops := BackdropPaint.uniforms(look)
	for param: String in stops:
		paint_material.set_shader_parameter(StringName(param), stops[param])
	_initial.label_settings.font_color = ink_on(look)


func _on_resized() -> void:
	_initial.label_settings.font_size = maxi(INITIAL_MIN, roundi(size.y * INITIAL_SHARE))
