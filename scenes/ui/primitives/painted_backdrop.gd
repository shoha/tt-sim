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
## Words that sit straight on the backdrop register their controls (keep_legible): under
## them the shader lifts anything darker than its legible floor toward the mood's haze, so
## captions keep their contrast at night and over the meadow without changing colour.
##
## The mood last shown anywhere is kept (last_mood), so a map load that follows the title or
## the room shows the same picture rather than jumping to another.

## The moods, by the shader's palette index.
enum Mood { MORNING, MIDDAY, GOLDEN_HOUR, DUSK, OVERCAST, NIGHT }

const SHADER := preload("res://shaders/ui_backdrop.gdshader")
## The cross-fade from one mood to the next: slower than an overlay (M1), as light changes.
const FADE_S := 1.2
## The shader takes at most this many legible zones.
const MAX_ZONES := 4
## Space kept around a registered control's rect, in canvas pixels.
const ZONE_PAD := 12.0
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
## Groups of controls whose words sit on the backdrop; each group is one zone, the union of
## its controls' rects (a container counts by its shown children).
var _zone_groups: Array = []


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


## Keep the words of these controls legible: each array is one zone, the union of its
## controls' rects. Zones follow the controls as they move, resize, show and hide.
func keep_legible(groups: Array) -> void:
	_zone_groups = groups.slice(0, MAX_ZONES)
	for group: Array in _zone_groups:
		for control: Control in group:
			if not control.item_rect_changed.is_connected(_queue_zones):
				control.item_rect_changed.connect(_queue_zones)
				control.visibility_changed.connect(_queue_zones)
			for child in control.get_children():
				if child is Control and not child.visibility_changed.is_connected(_queue_zones):
					child.visibility_changed.connect(_queue_zones)
	_queue_zones()


## The zones as the shader takes them, in this rect's pixels.
func zone_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var origin := get_global_rect().position
	for group: Array in _zone_groups:
		var union := Rect2()
		for control: Control in group:
			if not is_instance_valid(control) or not control.is_visible_in_tree():
				continue
			var rect := _content_rect(control)
			if rect.has_area():
				union = rect if not union.has_area() else union.merge(rect)
		if union.has_area():
			rects.append(Rect2(union.position - origin, union.size).grow(ZONE_PAD))
	return rects


## Where a control's words are: a label's text as it is aligned, a box container's shown
## children, anything else its own rect.
static func _content_rect(control: Control) -> Rect2:
	if control is Label:
		return _text_rect(control as Label)
	if not control is BoxContainer:
		return control.get_global_rect()
	var union := Rect2()
	for child in control.get_children():
		var item := child as Control
		if item == null or not item.visible or item.size == Vector2.ZERO:
			continue
		var rect := _content_rect(item)
		if rect.has_area():
			union = rect if not union.has_area() else union.merge(rect)
	return union


## A label's rect narrowed to its text's width, where its alignment puts the text.
static func _text_rect(label: Label) -> Rect2:
	var rect := label.get_global_rect()
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	width = minf(width, rect.size.x)
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			rect.position.x += (rect.size.x - width) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			rect.position.x += rect.size.x - width
	rect.size.x = width
	return rect


## Measure the zones again after this frame's layout: for words that changed without their
## control moving (a label's new text).
func refresh_zones() -> void:
	_queue_zones()


func _queue_zones() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_update_zones):
		get_tree().process_frame.connect(_update_zones, CONNECT_ONE_SHOT)


func _update_zones() -> void:
	var rects := zone_rects()
	var packed := PackedVector4Array()
	for rect in rects:
		packed.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
	while packed.size() < MAX_ZONES:
		packed.append(Vector4.ZERO)
	_set_param(&"zones", packed)
	_set_param(&"zone_count", rects.size())


func _set_blend(value: float) -> void:
	_set_param(&"blend", value)


func _set_param(param: StringName, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(param, value)


func _on_resized() -> void:
	_set_param(&"rect_size", size)
	_queue_zones()
