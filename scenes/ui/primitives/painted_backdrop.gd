class_name PaintedBackdrop
extends ColorRect

## The painted world every screen outside play stands on (the title, the room, a map load):
## a full-screen landscape drawn by shaders/ui_backdrop.gdshader in the map placeholder's
## language (MapPlaceholder), in place of a flat sky. Its light is one of six curated moods
## (morning, midday, golden hour, dusk, overcast, night), chosen by the selected map's own
## environment preset (mood_of) and cross-faded slowly on a change (show_mood); with no map
## selected it is morning. The mood sets only the backdrop: controls and semantic colours
## never change with it (UI_TASTE verdict 2026-10-09).
##
## Motion is the shader's own: four clouds sway about their places over 60-90 s (TIME, no
## _process), and Reduce motion (UiMotion.reduced(), M5) holds them still while the
## cross-fade stays. A hidden backdrop draws nothing, so its drift stops with it (M6).
##
## The painting carries no words. A screen that stands on it puts its words on paper: a
## sheet, or a plaque (the Plaque variation) for a few words such as a heading, so every
## caption keeps its contrast in every mood and the painting is never hazed under them.
##
## The mood last shown anywhere is kept (last_mood), so a map load that follows the title or
## the room shows the same picture rather than jumping to another.

## The moods, by the shader's palette index.
enum Mood { MORNING, MIDDAY, GOLDEN_HOUR, DUSK, OVERCAST, NIGHT }

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## The cross-fade from one mood to the next: slower than an overlay (M1), as light changes.
const FADE_S := 1.2
## Environment presets by the mood they paint. Any other preset, or none, is morning.
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

## The mood the most recently shown backdrop is fading to (or rests in).
static var last_mood: Mood = Mood.MORNING

var _mood: Mood = Mood.MORNING
var _shown := false
var _fade: Tween


func _init() -> void:
	name = "Backdrop"
	var paint_material := ShaderMaterial.new()
	paint_material.shader = SHADER
	material = paint_material
	resized.connect(_on_resized)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_param(&"drift", 0.0 if UiMotion.reduced() else 1.0)
	_on_resized()


## The mood an environment preset paints ("" or an unknown preset: morning).
static func mood_of(preset: String) -> Mood:
	return MOOD_OF_PRESET.get(preset, Mood.MORNING)


## The mood this backdrop shows or is fading to.
func mood() -> Mood:
	return _mood


## Show `mood`: at once the first time (or with `instant`), else a slow cross-fade from what is
## on screen. A fade interrupted part way starts again from whichever mood dominated.
func show_mood(next: Mood, instant := false) -> void:
	last_mood = next
	if _shown and next == _mood and not instant:
		return
	var paint_material := material as ShaderMaterial
	if _fade and _fade.is_valid():
		_fade.kill()
	if instant or not _shown or not is_inside_tree():
		_mood = next
		_shown = true
		_set_param(&"mood_from", int(next))
		_set_param(&"mood_to", int(next))
		_set_param(&"blend", 1.0)
		return
	var blend := float(paint_material.get_shader_parameter(&"blend"))
	var showing: int = paint_material.get_shader_parameter(
		&"mood_to" if blend >= 0.5 else &"mood_from"
	)
	_mood = next
	_set_param(&"mood_from", showing)
	_set_param(&"mood_to", int(next))
	_set_param(&"blend", 0.0)
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade.tween_method(_set_blend, 0.0, 1.0, FADE_S)


## Show the mood of the map with environment preset `preset` ("" with none selected).
func show_mood_of(preset: String, instant := false) -> void:
	show_mood(mood_of(preset), instant)


func _set_blend(value: float) -> void:
	_set_param(&"blend", value)


func _set_param(param: StringName, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(param, value)


func _on_resized() -> void:
	_set_param(&"rect_size", size)
