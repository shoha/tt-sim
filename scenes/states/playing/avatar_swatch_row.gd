class_name AvatarSwatchRow
extends HFlowContainer

## A row of colour swatches for one palette slot of the avatar builder: one toggle button
## per entry of the kit's curated set, filled with the colour's base and edged with its
## shadow, so the swatch reads as the painted cloth would. The picked swatch carries the
## theme's state colour as its edge (a pick is a state). Signals fire for clicks only;
## select() is silent.

signal picked(index: int)

const SIZE := Vector2(40, 40)
const RADIUS := 9
const EDGE := 2
const PICKED_EDGE := 3

var selected := -1

var _group := ButtonGroup.new()
var _buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)
	_group.allow_unpress = false


## Fills the row from `triples` (kit.json colour_sets entries: [base, shadow, highlight]).
func build(triples: Array) -> void:
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	var picked_edge := ThemeColors.of(self, ThemeColors.STATE)
	for i in triples.size():
		var triple: Array = triples[i]
		var base := Color.html(String(triple[0]))
		var shadow := Color.html(String(triple[1])) if triple.size() > 1 else base.darkened(0.4)
		var highlight := Color.html(String(triple[2])) if triple.size() > 2 else base.lightened(0.3)
		var button := Button.new()
		button.name = "Swatch%d" % i
		button.toggle_mode = true
		button.button_group = _group
		button.custom_minimum_size = SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = String(triple[0])
		button.set_meta("ui_silent", true)
		button.add_theme_stylebox_override("normal", _style(base, shadow, EDGE))
		button.add_theme_stylebox_override("hover", _style(base, highlight, EDGE))
		button.add_theme_stylebox_override("pressed", _style(base, picked_edge, PICKED_EDGE))
		button.add_theme_stylebox_override("hover_pressed", _style(base, picked_edge, PICKED_EDGE))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.toggled.connect(_on_toggled.bind(i))
		add_child(button)
		_buttons.append(button)


## Marks `index` as the pick without a signal.
func select(index: int) -> void:
	selected = index
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == index)


func _on_toggled(pressed: bool, index: int) -> void:
	if not pressed or index == selected:
		return
	selected = index
	AudioManager.play(&"tick")
	picked.emit(index)


static func _style(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(RADIUS)
	style.anti_aliasing = true
	return style
