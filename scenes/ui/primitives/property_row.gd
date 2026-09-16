class_name PropertyRow
extends VBoxContainer

## One editable property: label | [check] [colour] | slider | value chip. The
## chip is an inline LineEdit (commit on Enter or focus loss) instead of a
## SpinBox, which recovers about 40 px per row. [member overridden] tints the
## label accent and enables right-click reset. [member ticks] draws small
## muted icons under the slider at given values (time of day markers).

signal value_changed(value: float)
signal color_changed(color: Color)
signal toggled(on: bool)
signal reset_requested

const CHIP_WIDTH := 56.0
const TICK_SIZE := 14.0
const TICKS_HEIGHT := 16.0
const OVERRIDE_TOOLTIP := "Overridden. Right-click to reset to the preset value."

@export var label: String = "":
	set(value):
		label = value
		if _label:
			_label.text = value
@export var show_slider: bool = true
@export var show_color: bool = false
@export var show_check: bool = false
@export var min_value: float = 0.0:
	set(value):
		min_value = value
		_sync_range()
@export var max_value: float = 1.0:
	set(value):
		max_value = value
		_sync_range()
@export var step: float = 0.01:
	set(value):
		step = value
		_sync_range()
@export var value: float = 0.0:
	set(new_value):
		value = new_value
		_sync_range()
@export var exp_edit: bool = false:
	set(value):
		exp_edit = value
		_sync_range()
@export var allow_greater: bool = false
@export var allow_lesser: bool = false
@export var editable: bool = true:
	set(value):
		editable = value
		_sync_range()
@export var overridden: bool = false:
	set(value):
		overridden = value
		_refresh_override()
## Each entry: {"value": float, "icon": String}.
@export var ticks: Array[Dictionary] = []:
	set(value):
		ticks = value
		_refresh_ticks()
@export var label_min_width: float = 96.0
## Short words drawn under the slider's ends ("Dim" ... "Blazing"). Either
## may be empty; the strip shows when any hint or tick exists.
@export var hint_low: String = "":
	set(value):
		hint_low = value
		_refresh_strip()
@export var hint_high: String = "":
	set(value):
		hint_high = value
		_refresh_strip()
## Show the numeric chip. Off by default: the drawer's values toggle flips
## every row at once. Never shows on a sliderless row.
@export var values_visible: bool = false:
	set(value):
		values_visible = value
		_refresh_chip_visibility()
## Optional (float) -> String used for the chip text and slider tooltip
## ("14:30", "143 deg SE", "1.52 m (5 ft)"). Typing into the chip still
## parses a plain number in the row's native unit.
var formatter: Callable = Callable():
	set(value):
		formatter = value
		_sync_range()

var color: Color:
	get:
		return _picker.color if _picker else Color.WHITE
	set(new_color):
		if _picker:
			_picker.color = new_color

var checked: bool:
	get:
		return _check.button_pressed if _check else false
	set(on):
		if _check:
			_check.set_pressed_no_signal(on)

var _row: HBoxContainer
var _label: Label
var _check: CheckBox
var _picker: ColorPickerButton
var _slider: HSlider
var _chip: LineEdit
var _ticks: Control
var _tick_textures: Array[Texture2D] = []
var _syncing: bool = false
var _hint_font: Font
var _hint_font_size: int = 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	_build_row()
	_build_ticks()
	_sync_range()
	_refresh_override()
	_refresh_ticks()


func set_value_no_signal(new_value: float) -> void:
	_syncing = true
	value = new_value
	_syncing = false


func set_color_no_signal(new_color: Color) -> void:
	if _picker:
		_picker.color = new_color


func set_checked_no_signal(on: bool) -> void:
	if _check:
		_check.set_pressed_no_signal(on)


## Put [param control] where the slider would go (for an OptionButton row).
## Hides the slider and chip.
func set_control(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(control)
	_row.move_child(control, _slider.get_index())
	show_slider = false
	_slider.visible = false
	_chip.visible = false


func _build_row() -> void:
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 6)
	add_child(_row)

	_label = Label.new()
	_label.name = "Label"
	_label.text = label
	_label.theme_type_variation = &"Body"
	_label.custom_minimum_size = Vector2(label_min_width, 0)
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.gui_input.connect(_on_label_gui_input)
	_row.add_child(_label)

	if show_check:
		_check = CheckBox.new()
		_check.name = "Check"
		_check.toggled.connect(_on_check_toggled)
		_row.add_child(_check)

	if show_color:
		_picker = ColorPickerButton.new()
		_picker.name = "Color"
		_picker.custom_minimum_size = Vector2(28, 0)
		_picker.color_changed.connect(_on_color_changed)
		_row.add_child(_picker)

	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_value_changed)
	_slider.item_rect_changed.connect(_sync_ticks_rect)
	_row.add_child(_slider)

	_chip = LineEdit.new()
	_chip.name = "Value"
	_chip.theme_type_variation = &"ValueChip"
	_chip.custom_minimum_size = Vector2(CHIP_WIDTH, 0)
	_chip.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_chip.context_menu_enabled = false
	_chip.text_submitted.connect(_on_chip_submitted)
	_chip.focus_exited.connect(_commit_chip)
	_row.add_child(_chip)

	if not show_slider:
		_slider.visible = false
		if not show_color and not show_check:
			_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_chip_visibility()


func _build_ticks() -> void:
	_ticks = Control.new()
	_ticks.name = "Ticks"
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.custom_minimum_size = Vector2(0, TICKS_HEIGHT)
	_ticks.visible = false
	_ticks.draw.connect(_on_ticks_draw)
	add_child(_ticks)
	_hint_font = _label.get_theme_font("font")
	_hint_font_size = _label.get_theme_font_size("font_size") - 2


func _sync_range() -> void:
	if not is_node_ready():
		return
	# Assigning min_value/max_value/step on a Range can silently re-clamp its
	# current internal value and re-emit value_changed (e.g. when the
	# slider's prior value sits outside the incoming range) before we reach
	# set_value_no_signal below. Guard the whole block so that reentrant
	# signal delivery is a no-op instead of overwriting `value`.
	_syncing = true
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = step
	_slider.exp_edit = exp_edit
	_slider.editable = editable
	_slider.set_value_no_signal(clampf(value, min_value, max_value))
	_syncing = false
	_chip.editable = editable
	_chip.text = _display(value)
	_slider.tooltip_text = _display(value) if show_slider else ""
	_ticks.queue_redraw()


func _decimals() -> int:
	if step <= 0.0:
		return 2
	return clampi(int(ceil(-log(step) / log(10.0) - 0.0001)), 0, 4)


func _format(number: float) -> String:
	# String.num() trims trailing zeros even with an explicit decimals count
	# (e.g. num(2.5, 2) == "2.5", not "2.50"), which does not match the fixed
	# decimal-width the chip needs. "%.*f" always pads to the given width and
	# drops the trailing "." when decimals is 0.
	return "%.*f" % [_decimals(), number]


func _display(number: float) -> String:
	if formatter.is_valid():
		return String(formatter.call(number))
	return _format(number)


func _refresh_chip_visibility() -> void:
	if _chip:
		_chip.visible = values_visible and show_slider


func _strip_visible() -> bool:
	return not ticks.is_empty() or not hint_low.is_empty() or not hint_high.is_empty()


func _refresh_strip() -> void:
	if not _ticks:
		return
	_ticks.visible = _strip_visible()
	_ticks.queue_redraw()


func _on_slider_value_changed(new_value: float) -> void:
	if _syncing:
		return
	_syncing = true
	value = new_value
	_syncing = false
	value_changed.emit(new_value)


func _on_chip_submitted(_text: String) -> void:
	_commit_chip()
	_chip.release_focus()


func _commit_chip() -> void:
	var text := _chip.text.strip_edges()
	if not text.is_valid_float():
		_chip.text = _display(value)
		return
	var parsed := text.to_float()
	if not allow_greater:
		parsed = minf(parsed, max_value)
	if not allow_lesser:
		parsed = maxf(parsed, min_value)
	if is_equal_approx(parsed, value):
		_chip.text = _display(value)
		return
	_syncing = true
	value = parsed
	_syncing = false
	value_changed.emit(parsed)


func _on_check_toggled(on: bool) -> void:
	toggled.emit(on)


func _on_color_changed(new_color: Color) -> void:
	color_changed.emit(new_color)


func _refresh_override() -> void:
	if not _label:
		return
	if overridden:
		_label.add_theme_color_override("font_color", ThemeColors.ACCENT)
		_label.tooltip_text = OVERRIDE_TOOLTIP
	else:
		_label.remove_theme_color_override("font_color")
		_label.tooltip_text = ""


func _on_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			reset_requested.emit()


func _refresh_ticks() -> void:
	if not _ticks:
		return
	_tick_textures.clear()
	for tick in ticks:
		_tick_textures.append(IconButton.load_icon(String(tick.get("icon", ""))))
	_refresh_strip()


func _tick_fraction(tick_value: float) -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return clampf((tick_value - min_value) / (max_value - min_value), 0.0, 1.0)


func _sync_ticks_rect() -> void:
	if _ticks and _ticks.visible:
		_ticks.queue_redraw()


func _on_ticks_draw() -> void:
	var left := _slider.position.x
	var width := _slider.size.x
	for i in range(ticks.size()):
		var texture := _tick_textures[i]
		if texture == null:
			continue
		var x := left + width * _tick_fraction(float(ticks[i].get("value", 0.0)))
		var rect := Rect2(x - TICK_SIZE / 2.0, 0.0, TICK_SIZE, TICK_SIZE)
		_ticks.draw_texture_rect(texture, rect, false, ThemeColors.TEXT_MUTED)
	if _hint_font == null:
		return
	var baseline := TICK_SIZE - 2.0
	if not hint_low.is_empty():
		_ticks.draw_string(
			_hint_font,
			Vector2(left, baseline),
			hint_low,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_hint_font_size,
			ThemeColors.TEXT_MUTED
		)
	if not hint_high.is_empty():
		var text_width := (
			_hint_font.get_string_size(hint_high, HORIZONTAL_ALIGNMENT_LEFT, -1, _hint_font_size).x
		)
		_ticks.draw_string(
			_hint_font,
			Vector2(left + width - text_width, baseline),
			hint_high,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			_hint_font_size,
			ThemeColors.TEXT_MUTED
		)
