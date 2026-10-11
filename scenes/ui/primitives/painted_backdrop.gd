class_name PaintedBackdrop
extends ColorRect

## The sky every screen outside play stands on (the title, the room, a map load): a soft
## full-screen gradient drawn by shaders/ui_backdrop.gdshader, the same light a map's
## placeholder picture shows in a small rect (MapPlaceholder). Its light is one of six curated
## moods (morning, midday, golden hour, dusk, overcast, night), chosen by the selected map's
## environment preset through one table (mood_of) that the placeholders read too. With no map
## selected it is morning. The mood sets only the backdrop: controls and semantic colours never
## change with it (UI_TASTE verdict 2026-10-09).
##
## It paints no scenery. The painted sun, clouds, hills and poplars, and the layout that moved
## them clear of a screen's paper, were retired by the UI_TASTE verdict of 2026-10-10 (solid
## colours and subtle gradients until the UI's painterly side is revisited). fit_around(),
## refit() and hold_drift() stay so the screens that call them need not change; with nothing to
## place and nothing moving they do nothing.
##
## A change of map is one gradient changing, not two cross-fading: BackdropPaint mixes the
## stops in OKLCH over FADE_S, and the shader paints each frame's single look. A change part
## way through a fade starts from what is on screen.
##
## The backdrop carries no words. A screen that stands on it puts its words on paper: a sheet,
## or a plaque (the Plaque variation) for a few words such as a heading.
##
## The mood and the map last shown anywhere are kept (last_mood, last_key), so a map load that
## follows the title or the room shows the same sky rather than jumping to another.

## The moods, by BackdropPaint.MOODS index.
enum Mood { MORNING, MIDDAY, GOLDEN_HOUR, DUSK, OVERCAST, NIGHT }

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## A change of light, quick enough to follow a click: the world changing, not chrome, so past
## the overlay band (UI_TASTE M1's named exception); no control waits on it.
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
## The look the fade runs from, and the one it runs to.
var _look_from: Dictionary = {}
var _look_to: Dictionary = {}


func _init() -> void:
	name = "Backdrop"
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	material = paint_material
	_key = last_key
	_look_from = BackdropPaint.look_of(_mood)
	_look_to = _look_from
	_apply()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The mood an environment preset paints ("" or an unknown preset: morning).
static func mood_of(preset: String) -> Mood:
	return MOOD_OF_PRESET.get(preset, Mood.MORNING)


## The mood this backdrop shows or is fading to.
func mood() -> Mood:
	return _mood


## The key of the map whose mood this backdrop shows or is fading to.
func key() -> String:
	return _key


## How far the current change has run, 0 to 1 (1 at rest).
func blend() -> float:
	return _blend


## Show `next`: at once the first time (or with `instant`), else a fade from what is on screen.
func show_mood(next: Mood, instant := false) -> void:
	_show(next, _key, instant)


## Show the mood of the map with environment preset `preset` ("" with none selected).
func show_mood_of(preset: String, instant := false) -> void:
	_show(mood_of(preset), _key, instant)


## Show the map with key `map_key` (its folder, or its name without one; "" for none) and
## environment preset `preset`: its mood's sky.
func show_map(preset: String, map_key: String, instant := false) -> void:
	_show(mood_of(preset), map_key, instant)


## Show the mood and the map last shown anywhere, at once: a screen that follows the title or
## the room (a map load, the room itself) opens on the same sky.
func show_last() -> void:
	_show(last_mood, last_key, true)


## Kept for the screens and Reduce motion that call it: the gradient does not move.
func hold_drift(_held: bool) -> void:
	pass


## Kept for the screens that call it: the gradient has nothing to move clear of their paper.
func fit_around(_screen: Node) -> void:
	pass


## Kept for the screens that call it when their layout changes: nothing to measure.
func refit() -> void:
	pass


func _show(next: Mood, map_key: String, instant: bool) -> void:
	last_mood = next
	last_key = map_key
	_key = map_key
	if _shown and next == _mood and not instant:
		return
	if _fade and _fade.is_valid():
		_fade.kill()
	var look := BackdropPaint.look_of(next)
	if instant or not _shown or not is_inside_tree():
		_look_from = look
		_blend = 1.0
	else:
		# From what is on screen, part way through a fade or at rest.
		_look_from = BackdropPaint.mix_looks(_look_from, _look_to, _blend)
		_blend = 0.0
	_mood = next
	_shown = true
	_look_to = look
	_apply()
	if _blend < 1.0:
		_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fade.tween_method(_set_blend, 0.0, 1.0, FADE_S)


func _set_blend(value: float) -> void:
	_blend = value
	_apply()


## Hand the shader the stops `_blend` of the way through the change.
func _apply() -> void:
	var stops := BackdropPaint.uniforms(BackdropPaint.mix_looks(_look_from, _look_to, _blend))
	var paint_material := material as ShaderMaterial
	for param: String in stops:
		paint_material.set_shader_parameter(StringName(param), stops[param])
