class_name PaintedBackdrop
extends ColorRect

## The painted world every screen outside play stands on (the title, the room, a map load):
## a full-screen landscape drawn by shaders/ui_backdrop.gdshader, the same world a map's
## placeholder picture shows in a small rect (MapPlaceholder), in place of a flat sky. Its light
## is one of six curated moods (morning, midday, golden hour, dusk, overcast, night), chosen by
## the selected map's environment preset through one table (mood_of) that the placeholders read
## too, and its land and weather are drawn from the map's key (show_map): two maps in the same
## mood get their own skies. With no map selected it is morning. The mood sets only the
## backdrop: controls and semantic colours never change with it (UI_TASTE verdict 2026-10-09).
##
## A change of map is one picture changing, not two pictures cross-fading: BackdropPaint mixes
## the light in OKLCH and moves the one sun or moon, the skyline, the clouds and the poplars,
## over FADE_S, and the shader paints each frame's single look. A change part way through a
## fade starts from what is on screen.
##
## The screen it stands under tells it where its paper is (fit_around): the sun or moon then
## sits in the largest open square of sky, the clouds in open sky clear of the cards, and the
## poplars on a stretch of crest no sheet covers. The screen calls refit() when its layout
## changes; a resize refits by itself.
##
## Motion is the shader's own: the clouds sway about their places over 60-90 s (TIME, no
## _process), and Reduce motion (UiMotion.reduced(), M5) holds them still while a change of
## light still fades. A hidden backdrop draws nothing, so its drift stops with it (M6).
##
## The painting carries no words. A screen that stands on it puts its words on paper: a
## sheet, or a plaque (the Plaque variation) for a few words such as a heading.
##
## The mood and the map last shown anywhere are kept (last_mood, last_key), so a map load
## that follows the title or the room shows the same picture rather than jumping to another.

## The moods, by BackdropPaint.MOODS index.
enum Mood { MORNING, MIDDAY, GOLDEN_HOUR, DUSK, OVERCAST, NIGHT }

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## A change of light: an overlay's pace (M1), quick enough to follow a click.
const FADE_S := 0.6
## Environment presets by the mood they paint, for the backdrop and the placeholders alike.
## Any other preset, or none, is morning.
const MOOD_OF_PRESET := {
	"forest": Mood.MORNING,
	"outdoor_day": Mood.MIDDAY,
	"indoor_neutral": Mood.MIDDAY,
	"bright_editor": Mood.MIDDAY,
	"outdoor_sunset": Mood.GOLDEN_HOUR,
	"tavern": Mood.GOLDEN_HOUR,
	"desert": Mood.GOLDEN_HOUR,
	"hell": Mood.DUSK,
	"ethereal": Mood.DUSK,
	"outdoor_overcast": Mood.OVERCAST,
	"swamp": Mood.OVERCAST,
	"arctic": Mood.OVERCAST,
	"outdoor_night": Mood.NIGHT,
	"dungeon_dark": Mood.NIGHT,
	"dungeon_crypt": Mood.NIGHT,
	"cave": Mood.NIGHT,
	"underwater": Mood.NIGHT,
}

## The mood the most recently shown backdrop is fading to (or rests in), and its map's key.
static var last_mood: Mood = Mood.MORNING
static var last_key := ""

var _mood: Mood = Mood.MORNING
var _key := ""
var _shown := false
var _fade: Tween
var _blend := 1.0
## The look and composition the fade runs from, and the ones it runs to.
var _look_from: Dictionary = {}
var _look_to: Dictionary = {}
var _composition_from: Dictionary = {}
var _composition_to: Dictionary = {}
## The screen whose paper the painting makes way for, and its layout.
var _screen: Node
var _layout: BackdropLayout
var _refit_pending := false


func _init() -> void:
	name = "Backdrop"
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	material = paint_material
	_key = last_key
	_look_to = BackdropPaint.look_of(_mood)
	resized.connect(_on_resized)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold_drift(UiMotion.reduced())
	_on_resized()


## The mood an environment preset paints ("" or an unknown preset: morning).
static func mood_of(preset: String) -> Mood:
	return MOOD_OF_PRESET.get(preset, Mood.MORNING)


## The seed a map's key draws its picture from, in [0, 1): the same key always paints the same.
## MD5 rather than String.hash(), whose high bits barely move between short keys.
static func seed_of(key: String) -> float:
	var digest := key.md5_buffer()
	return float(digest[1] << 8 | digest[2]) / 65536.0


## The mood this backdrop shows or is fading to.
func mood() -> Mood:
	return _mood


## The map key whose land this backdrop shows or is fading to.
func key() -> String:
	return _key


## How far the current change has run, 0 to 1 (1 at rest).
func blend() -> float:
	return _blend


## Show `next` over the current land: at once the first time (or with `instant`), else a fade
## from what is on screen.
func show_mood(next: Mood, instant := false) -> void:
	_show(next, _key, instant)


## Show the mood of the map with environment preset `preset` ("" with none selected).
func show_mood_of(preset: String, instant := false) -> void:
	_show(mood_of(preset), _key, instant)


## Show the map with key `map_key` (its folder, or its name without one; "" for none) and
## environment preset `preset`: its mood's light over its own land.
func show_map(preset: String, map_key: String, instant := false) -> void:
	_show(mood_of(preset), map_key, instant)


## Show the mood and the land last shown anywhere, at once: a screen that follows the title or
## the room (a map load, the room itself) opens on the same picture.
func show_last() -> void:
	_show(last_mood, last_key, true)


## Hold the clouds still (Reduce motion) or let them drift.
func hold_drift(held: bool) -> void:
	_set_param(&"drift", 0.0 if held else 1.0)


## Make way for the paper of `screen` (its sheets, plaques, cards and pictures), now and on
## every refit().
func fit_around(screen: Node) -> void:
	_screen = screen
	refit()


## Measure the screen's paper again on the next frame, once its containers have sorted.
func refit() -> void:
	if _refit_pending or not is_inside_tree():
		return
	_refit_pending = true
	get_tree().process_frame.connect(_refit_now, CONNECT_ONE_SHOT)


func _refit_now() -> void:
	_refit_pending = false
	if not is_instance_valid(_screen) or size.y <= 0.0:
		return
	var layout := BackdropLayout.new(size, BackdropLayout.paper_of(_screen))
	_layout = layout
	_composition_to = _compose(_key)
	if not _composition_from.is_empty():
		_composition_from = BackdropPaint.compose(
			float(_composition_from.seed), size, _layout
		)
	_apply()


func _show(next: Mood, map_key: String, instant: bool) -> void:
	last_mood = next
	last_key = map_key
	if _shown and next == _mood and map_key == _key and not instant:
		return
	if _fade and _fade.is_valid():
		_fade.kill()
	var look := BackdropPaint.look_of(next)
	var composition := _compose(map_key)
	if instant or not _shown or not is_inside_tree():
		_look_from = look
		_composition_from = composition
		_blend = 1.0
	else:
		# From what is on screen, part way through a fade or at rest.
		_look_from = BackdropPaint.mix_looks(_look_from, _look_to, _blend)
		_composition_from = BackdropPaint.mix_compositions(
			_composition_from, _composition_to, _blend
		)
		_blend = 0.0
	_mood = next
	_key = map_key
	_shown = true
	_look_to = look
	_composition_to = composition
	_apply()
	if _blend < 1.0:
		_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fade.tween_method(_set_blend, 0.0, 1.0, FADE_S)


func _compose(map_key: String) -> Dictionary:
	var canvas := size if size.y > 0.0 else Vector2(1920, 1080)
	return BackdropPaint.compose(seed_of(map_key), canvas, _layout)


func _set_blend(value: float) -> void:
	_blend = value
	_apply()


## Hand the shader the look and composition `_blend` of the way through the change.
func _apply() -> void:
	if _composition_to.is_empty():
		_composition_to = _compose(_key)
	var look := BackdropPaint.mix_looks(_look_from, _look_to, _blend)
	if _look_from.is_empty():
		look = _look_to
	var composition := BackdropPaint.mix_compositions(_composition_from, _composition_to, _blend)
	var values := BackdropPaint.uniforms(look, composition)
	for param: String in values:
		_set_param(StringName(param), values[param])


func _set_param(param: StringName, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(param, value)


func _on_resized() -> void:
	_set_param(&"rect_size", size)
	if size.y <= 0.0:
		return
	# The layout is in the old size's pixels: measure again, and paint the land at this aspect.
	_layout = null
	_composition_to = _compose(_key)
	_composition_from = {}
	_apply()
	if _screen:
		refit()
