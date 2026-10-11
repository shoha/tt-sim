class_name MapPlaceholder
extends ColorRect

## The picture of a map that has no thumbnail yet: a gentle diagonal gradient in the map's
## mood (shaders/ui_backdrop.gdshader, BackdropPaint) one step deeper than the sky behind it
## (look_for: DEEPEN darker in OKLCH lightness at the same hues), so a card reads as a picture
## on paper and never as a hole showing the sky. Its light is read through the one table the
## backdrop reads (PaintedBackdrop.mood_of of LevelData.environment_preset), so a map's card,
## its row in the room and the screen behind it when it is selected share one light.
##
## Over it the map's initial in the heading face (Fraunces, the Title role) at a share of the
## picture's height, in
## one solid role that keeps 4.5:1 on the stretch of the gradient it stands over (ink_on): soft
## ink where it reads, else ink or paper. Where the mood's step leaves neither ink nor paper at
## 4.5:1 (dusk and night sit in the middle of the lightness range), the picture deepens on
## until paper reads. It sits inside a CardThumb well, which clips it to the well's shape.

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## How far the gradient leans from straight down (the shader's tilt): a gentle diagonal.
const TILT := 0.5
## How much darker than the sky a placeholder is (OKLCH lightness), and the further steps it
## takes where neither ink nor paper reads on that.
const DEEPEN := 0.12
const DEEPEN_STEP := 0.02
const DEEPEN_MAX := 0.32
## The initial's size scales with the picture: INITIAL_SHARE of its height (45 px on a 150 px
## card picture, 54 in the map panel's, 67 on a 1080p card), never under INITIAL_MIN (a room
## row's small well) or over INITIAL_MAX; INITIAL_SIZE until the picture is laid out.
const INITIAL_SIZE := 30
const INITIAL_SHARE := 0.3
const INITIAL_MIN := 14
const INITIAL_MAX := 96
## The stretch of the gradient (0 the horizon, 1 the top) the initial stands over.
const INITIAL_SPAN: Array[float] = [0.35, 0.65]
## The initial's roles, softest first.
const INITIAL_INKS: Array[Color] = [ThemeColors.INK_SOFT, ThemeColors.INK, ThemeColors.PAPER]

static var _looks := {}

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
	_initial.theme_type_variation = &"Title"
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Its size and ink ride on label settings with no font, so the Title role's face still draws.
	_initial.label_settings = LabelSettings.new()
	_initial.label_settings.font_size = INITIAL_SIZE
	add_child(_initial)
	resized.connect(_on_resized)
	_set_look(look_for(_mood))


## Paint the map with the stable `key` (its folder, or its name when it has none) in the mood
## of environment preset `mood`, with the initial of `title` (its name; the key's without one).
func paint(key: String, mood: String = "", title: String = "") -> void:
	_mood = PaintedBackdrop.mood_of(mood)
	_set_look(look_for(_mood))
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


## The look a placeholder in `mood` paints: the mood's sky DEEPEN darker, and darker again in
## DEEPEN_STEPs (to DEEPEN_MAX) while no initial role keeps 4.5:1 on it.
static func look_for(mood_index: int) -> Dictionary:
	if _looks.has(mood_index):
		return _looks[mood_index]
	var sky := BackdropPaint.look_of(mood_index)
	var step := DEEPEN
	var look := BackdropPaint.deepened(sky, step)
	while _best_ratio(look) < 4.5 and step < DEEPEN_MAX:
		step += DEEPEN_STEP
		look = BackdropPaint.deepened(sky, step)
	_looks[mood_index] = look
	return look


## The colour an initial is drawn in over `look`'s gradient: the softest of INITIAL_INKS that
## keeps 4.5:1 across the stretch the initial stands over, else the one that keeps the most.
static func ink_on(look: Dictionary) -> Color:
	var best := ThemeColors.INK
	var best_ratio := -1.0
	for ink: Color in INITIAL_INKS:
		var ratio := BackdropPaint.worst_contrast(look, ink, INITIAL_SPAN[0], INITIAL_SPAN[1])
		if ratio >= 4.5:
			return ink
		if ratio > best_ratio:
			best = ink
			best_ratio = ratio
	return best


static func _best_ratio(look: Dictionary) -> float:
	return BackdropPaint.worst_contrast(look, ink_on(look), INITIAL_SPAN[0], INITIAL_SPAN[1])


## WCAG 2.x contrast ratio of two opaque colours.
static func contrast(a: Color, b: Color) -> float:
	return BackdropPaint.contrast(a, b)


func _set_look(look: Dictionary) -> void:
	var paint_material := material as ShaderMaterial
	var stops := BackdropPaint.uniforms(look)
	for param: String in stops:
		paint_material.set_shader_parameter(StringName(param), stops[param])
	_initial.label_settings.font_color = ink_on(look)


func _on_resized() -> void:
	var fit := roundi(size.y * INITIAL_SHARE)
	_initial.label_settings.font_size = clampi(fit, INITIAL_MIN, INITIAL_MAX)
