class_name IconRail
extends BoxContainer

## Single-select strip of IconButtons with a sliding accent indicator. Set
## [member vertical] for a side rail. With [member auto_select] the rail
## selects on click; a host that must decide first (a drawer that has to open)
## turns it off and calls [method select] itself. The indicator is drawn by the
## rail and tweened between items, so it is not a laid-out child.

signal item_pressed(id: StringName)
signal selection_changed(id: StringName)

const ITEM_SIZE := 36.0
const ITEM_GAP := 4
const INDICATOR_THICKNESS := 3.0

## Show each item's tooltip text as a caption under its icon.
@export var show_labels: bool = false
## Select an item when it is clicked. Off: the host calls select().
@export var auto_select: bool = true
## Draw the indicator on the end edge (right or bottom) instead of the start.
@export var indicator_at_end: bool = true

var selected: StringName = &""

var _buttons: Dictionary = {}
var _items: Dictionary = {}
var _indicator_tween: Tween
var _indicator_pos: float = -1.0:
	set(value):
		_indicator_pos = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", ITEM_GAP)
	resized.connect(_on_resized)


func add_item(id: StringName, icon_name: String, tooltip: String = "") -> IconButton:
	var button := IconButton.new()
	button.name = String(id)
	button.icon_name = icon_name
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(ITEM_SIZE, ITEM_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("ui_silent", true)
	button.pressed.connect(_on_item_pressed.bind(id))
	var item: Control = button
	if show_labels:
		var column := VBoxContainer.new()
		column.name = String(id) + "Item"
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 0)
		column.add_child(button)
		var label := Label.new()
		label.text = tooltip
		label.theme_type_variation = &"RailLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
		item = column
	add_child(item)
	_buttons[id] = button
	_items[id] = item
	return button


func has_item(id: StringName) -> bool:
	return _buttons.has(id)


func select(id: StringName) -> void:
	if id == selected:
		return
	if not id.is_empty() and not _buttons.has(id):
		push_warning("IconRail: unknown item %s" % id)
		return
	if _buttons.has(selected):
		_buttons[selected].active = false
	selected = id
	if _buttons.has(id):
		_buttons[id].active = true
	_animate_indicator()
	selection_changed.emit(id)


func deselect() -> void:
	select(&"")


func set_badge(id: StringName, on: bool) -> void:
	if _buttons.has(id):
		_buttons[id].badge = on


func set_enabled(id: StringName, on: bool) -> void:
	if _buttons.has(id):
		_buttons[id].disabled = not on


func set_item_visible(id: StringName, item_visible: bool) -> void:
	if _items.has(id):
		_items[id].visible = item_visible


func _on_item_pressed(id: StringName) -> void:
	if auto_select and id != selected:
		select(id)
		AudioManager.play_tick()
	item_pressed.emit(id)


func _on_resized() -> void:
	if _buttons.has(selected):
		_indicator_pos = _indicator_target()


func _indicator_target() -> float:
	var item: Control = _items[selected]
	if vertical:
		return item.position.y + item.size.y / 2.0
	return item.position.x + item.size.x / 2.0


func _animate_indicator() -> void:
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
	if not _buttons.has(selected):
		_indicator_pos = -1.0
		return
	var target := _indicator_target()
	if _indicator_pos < 0.0:
		_indicator_pos = target
		return
	_indicator_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_indicator_tween.tween_property(self, "_indicator_pos", target, Constants.ANIM_PANE_SWAP)


func _draw() -> void:
	if _indicator_pos < 0.0:
		return
	var half := ITEM_SIZE / 2.0
	var rect: Rect2
	if vertical:
		var x := size.x - INDICATOR_THICKNESS if indicator_at_end else 0.0
		rect = Rect2(x, _indicator_pos - half, INDICATOR_THICKNESS, ITEM_SIZE)
	else:
		var y := size.y - INDICATOR_THICKNESS if indicator_at_end else 0.0
		rect = Rect2(_indicator_pos - half, y, ITEM_SIZE, INDICATOR_THICKNESS)
	draw_rect(rect, ThemeColors.ACCENT)
