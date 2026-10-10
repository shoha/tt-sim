class_name PlayTogetherSlot
extends VBoxContainer

## The slot under the Play together card's pill (PlayTogetherCard): the title's Resume
## (set_under()) and the join's line (show_status()) trade places in it.
##
## In Join mode the slot is as tall as the taller of Resume with its caption and a
## RESERVE_LINES line failure in body type, so the join's progress or its failure never moves
## the card or anything below it. At rest with Resume showing it keeps that height too, so
## opening Join moves nothing. At rest with no Resume (no saved session yet, a first run) it
## takes no height, so no empty hole stands under the card; opening Join then eases it open
## with the card's wash (set_open()), the one time the column below moves.

## The slot holds a failure this many lines long (the version gate's message, the longest,
## wraps to three at the card's width).
const RESERVE_LINES := 3

## The join's line: its progress or why it failed (show_status()).
var status_row: HBoxContainer
var status_label: Label
var status_icon: TextureRect

var _under: Control
var _measure: Label
var _open := false
var _tween: Tween


## Builds the join's line `width` wide (the card's) with `icon` for a failure. Call once,
## before the slot is added.
func build(width: float, icon: Texture2D) -> void:
	name = "Slot"
	theme_type_variation = &"BoxContainerTight"
	status_row = HBoxContainer.new()
	status_row.name = "Status"
	status_row.theme_type_variation = &"BoxContainerSpaced"
	status_row.custom_minimum_size.x = width
	status_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status_row.visible = false
	add_child(status_row)
	status_icon = TextureRect.new()
	status_icon.name = "Icon"
	status_icon.texture = icon
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	status_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	status_row.add_child(status_icon)
	status_label = Label.new()
	status_label.name = "Message"
	status_label.theme_type_variation = &"Caption"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_label)
	# Never shown: RESERVE_LINES lines of body type, measured as a label lays them out (each
	# line's height is the shaped line's, a little over the font's own height).
	_measure = Label.new()
	_measure.name = "Measure"
	_measure.theme_type_variation = &"Body"
	var lines := PackedStringArray()
	for i in RESERVE_LINES:
		lines.append("Mg")
	_measure.text = "\n".join(lines)
	_measure.visible = false
	add_child(_measure)


## Puts `control` (the title's Resume) first in the slot. The slot follows its height and
## whether it shows.
func set_under(control: Control) -> void:
	_under = control
	add_child(control)
	move_child(control, 0)
	control.minimum_size_changed.connect(fit)
	control.visibility_changed.connect(fit)
	fit()


## Join mode opened (`on`) or closed: the slot takes its reserved height, or what rest needs,
## eased over `duration` (0: at once).
func set_open(on: bool, duration: float) -> void:
	_open = on
	fit(duration)


## The join's line: `text`, as an error (the alert icon in `danger`, body ink) or as progress
## (a soft caption).
func show_status(text: String, error: bool, danger: Color) -> void:
	status_row.visible = true
	status_label.text = text
	status_label.theme_type_variation = &"Body" if error else &"Caption"
	status_icon.visible = error
	status_icon.self_modulate = danger


func hide_status() -> void:
	status_row.visible = false


## The height Join mode reserves: the taller of Resume with its caption and a RESERVE_LINES
## line failure.
func reserved() -> float:
	var reserve := _measure.get_minimum_size().y
	if _under != null:
		reserve = maxf(reserve, _under.get_combined_minimum_size().y)
	return ceilf(reserve)


## The slot's height now (see the class doc), eased over `duration` (0: at once). The alert
## icon takes the body line's height.
func fit(duration := 0.0) -> void:
	if status_label == null:
		return
	var font := status_label.get_theme_font(&"font", &"Body")
	var font_size := status_label.get_theme_font_size(&"font_size", &"Body")
	var line := font.get_height(font_size) if font else 22.0
	status_icon.custom_minimum_size = Vector2.ONE * roundf(line)
	var shown := _open or (_under != null and _under.visible)
	var target := reserved() if shown else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if duration <= 0.0 or not is_inside_tree():
		custom_minimum_size.y = target
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "custom_minimum_size:y", target, duration)


## The height's easing while it runs, else null (for a probe holding a transition).
func easing() -> Tween:
	return _tween if _tween != null and _tween.is_valid() else null
