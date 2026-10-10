class_name LoadingOverlay
extends CanvasLayer

## The wait while the game does something that stops play: a paper sheet (docs/UI_TASTE.md
## C8: if it stops play it is paper) naming the operation in the Title role (W4), with a
## caption for the current step. Two kinds of wait, two grounds under the sheet:
##
## - show_loading(): a map load ("Setting out Mossy Hollow"; Root, the authoring build and
##   the graphics warm-up). The table behind is torn down and rebuilt under the overlay, so
##   there is nothing worth seeing through it; the sheet sits on the backdrop sky, the same
##   sky the title and the room stand on, so a title or room handing over to a load does not
##   change the picture. The bar is determinate (set_progress), and the sky fades off the
##   finished table when the load ends, as its reveal.
## - show_indeterminate(): a wait over a live screen that stays ("Opening a room..." over
##   the title). The shared Scrim (C4) blurs and tints the screen behind, and with no known
##   progress a lake segment, the bar's own fill style, glides back and forth along the bar
##   so the wait reads as work under way. It is never progress (W4): it moves both ways.
##   Under Reduce motion (UiMotion.reduced(), M5) it rests in the middle and breathes in
##   opacity instead.
##
## The glide is the only loop and stops when the overlay hides (M6). A map load's bar has
## none: a faint glide over the rest of a determinate bar was tried (2026-10-09) and read as
## a muddy grey-teal second segment beside the real fill, so a long step shows as a still bar
## under its caption.

signal loading_complete

## What a map load is called when the map's name is not known.
const SETTING_OUT_ANY := "Setting out the map"
## A map load named after its map (W4, W6: one sentence with a placeholder).
const SETTING_OUT := "Setting out %s"
## The share of the bar the gliding segment covers.
const GLIDE_SHARE := 0.32
## One pass of the glide, end to end, and one half-breath under Reduce motion.
const GLIDE_S := 1.1
## The segment's lowest opacity while it breathes under Reduce motion.
const BREATH_LOW := 0.35
## How long the bar takes to reach a new progress value.
const PROGRESS_S := 0.25
## The sky's fade off a finished table: the table's entrance, a little longer than an
## overlay's exit (M1).
const REVEAL_S := 0.4

var _tween: Tween
var _progress_tween: Tween
var _glide_tween: Tween
var _target_progress := 0.0
var _indeterminate := false
var _gliding := false
## Where the gliding segment is along the bar: 0 at the start, 1 at the end.
var _glide_at := 0.0

@onready var loading_label: Label = %LoadingLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel
@onready var _sky: ColorRect = %Sky
@onready var _scrim: ColorRect = %Scrim
@onready var _center: CenterContainer = %CenterContainer
@onready var _glide: Control = %Glide


## The title of a map load, naming the map when it is known.
static func setting_out_text(level: LevelData) -> String:
	if level == null or level.level_name.strip_edges().is_empty():
		return SETTING_OUT_ANY
	return SETTING_OUT % level.level_name.strip_edges()


func _ready() -> void:
	_sky.color = ThemeColors.of(_sky, ThemeColors.BACKDROP)
	_glide.draw.connect(_draw_glide)
	for node: CanvasItem in [_sky, _scrim, _center]:
		node.modulate.a = 0.0
	hide()


## Show a map load: the sheet on the backdrop sky with a determinate bar. The sky covers the
## screen at once (the title and the room stand on the same sky); the sheet fades in.
func show_loading(title: String = SETTING_OUT_ANY) -> void:
	_open(title, false)


## Show a wait over the live screen behind it: the scrim and a gliding bar, for an
## operation whose progress is not known.
func show_indeterminate(title: String) -> void:
	_open(title, true)


## Move the bar to `value` (0.0 to 1.0) and, when given, name the current step.
func set_progress(value: float, status: String = "") -> void:
	if status != "":
		_set_status(status)
	var target := clampf(value, 0.0, 1.0)
	if is_equal_approx(target, _target_progress):
		return
	_target_progress = target
	if _progress_tween:
		_progress_tween.kill()
	_progress_tween = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_progress_tween.tween_property(progress_bar, "value", target, PROGRESS_S)


## Fade the overlay out (over a finished table, the sky's reveal) and hide it.
func hide_loading() -> void:
	if _tween:
		_tween.kill()
	var duration := REVEAL_S if _sky.visible else Constants.ANIM_FADE_OUT_DURATION
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	for node: CanvasItem in [_sky, _scrim, _center]:
		_tween.tween_property(node, "modulate:a", 0.0, duration)

	await _tween.finished
	if not is_instance_valid(self):
		return
	_stop_glide()
	hide()
	loading_complete.emit()


## Whether the glide loop runs (see the class comment).
func is_gliding() -> bool:
	return _gliding


## Whether the bar shows a wait with no known progress rather than a fill.
func is_indeterminate() -> bool:
	return _indeterminate


func _open(title: String, over_screen: bool) -> void:
	loading_label.text = title
	_indeterminate = over_screen
	_set_status("")
	_sky.visible = not over_screen
	_scrim.visible = over_screen
	if not over_screen:
		_sky.modulate.a = 1.0
	if _progress_tween:
		_progress_tween.kill()
	progress_bar.value = 0.0
	_target_progress = 0.0
	show()

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	if over_screen:
		_tween.tween_property(_scrim, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	_tween.tween_property(_center, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	_start_glide()


## The caption under the bar; an empty one leaves no gap in the sheet.
func _set_status(status: String) -> void:
	status_label.text = status
	status_label.visible = not status.is_empty()


func _start_glide() -> void:
	_stop_glide()
	if not _indeterminate:
		return
	_gliding = true
	_glide_tween = create_tween().set_loops()
	_glide_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if UiMotion.reduced():
		_set_glide_at(0.5)
		_glide_tween.tween_property(_glide, "modulate:a", BREATH_LOW, GLIDE_S)
		_glide_tween.tween_property(_glide, "modulate:a", 1.0, GLIDE_S)
	else:
		_set_glide_at(0.0)
		_glide_tween.tween_method(_set_glide_at, 0.0, 1.0, GLIDE_S)
		_glide_tween.tween_method(_set_glide_at, 1.0, 0.0, GLIDE_S)


func _stop_glide() -> void:
	if _glide_tween and _glide_tween.is_valid():
		_glide_tween.kill()
	_glide_tween = null
	_gliding = false
	_glide.modulate.a = 1.0
	_glide.queue_redraw()


func _set_glide_at(at: float) -> void:
	_glide_at = at
	_glide.queue_redraw()


## The gliding segment, drawn with the bar's own fill style (lake, a pill) so it is the bar's
## fill in motion rather than a second shape.
func _draw_glide() -> void:
	if not _gliding:
		return
	var width := _glide.size.x * GLIDE_SHARE
	var rect := Rect2((_glide.size.x - width) * _glide_at, 0.0, width, _glide.size.y)
	_glide.draw_style_box(progress_bar.get_theme_stylebox(&"fill"), rect)
