class_name IconRail
extends BoxContainer

## Single-select strip of IconButtons with a sliding accent indicator. Set
## [member vertical] for a side rail. With [member auto_select] the rail
## selects on click; a host that must decide first (a drawer that has to open)
## turns it off and calls [method select] itself. The indicator is drawn by the
## rail and tweened between items, so it is not a laid-out child. Its place is
## read from the selected item's laid-out rect, so it is recomputed after every
## sort of the rail's children ([signal Container.sort_children]), not on
## [signal Control.resized]: a rail resizes before it sorts, and a selection made
## before the first sort reads every item at x = 0.

signal item_pressed(id: StringName)
signal selection_changed(id: StringName)

const ITEM_SIZE := 36.0
const ITEM_GAP := 4
## Between the labelled items of a horizontal rail (the Settings tabs): the labels are
## wider than their icons, so ITEM_GAP left about 4 px between two words.
const LABEL_GAP := 24
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
## Items tinted by set_item_active(), kept through selection changes (id -> true).
var _held_active: Dictionary = {}
var _indicator_tween: Tween
## Where the running slide ends, so a re-sort mid-slide can tell a moved item.
var _indicator_goal: float = -1.0
var _indicator_pos: float = -1.0:
	set(value):
		_indicator_pos = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gap := LABEL_GAP if show_labels and not vertical else ITEM_GAP
	add_theme_constant_override("separation", gap)
	sort_children.connect(_on_children_sorted)


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
		if not vertical and indicator_at_end:
			# Room for the underline under the label, so it clears the descenders.
			var underline_room := Control.new()
			underline_room.name = "UnderlineRoom"
			underline_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
			underline_room.custom_minimum_size = Vector2(0, INDICATOR_THICKNESS + 4.0)
			column.add_child(underline_room)
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
		_buttons[selected].active = _held_active.has(selected)
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


## Tint an item as active without selecting it (footer toggles, the Events item while a brush
## is out). The tint holds through select() and deselect(): a drawer that closes deselects its
## rail, which cleared it before (the 2a critic: a tinted Events item showed nothing).
func set_item_active(id: StringName, on: bool) -> void:
	if on:
		_held_active[id] = true
	else:
		_held_active.erase(id)
	if _buttons.has(id):
		_buttons[id].active = on or id == selected


## Update an item's tooltip in place (e.g. a footer toggle whose meaning
## flips with its state).
func set_item_tooltip(id: StringName, text: String) -> void:
	if _buttons.has(id):
		_buttons[id].tooltip_text = text


func set_item_visible(id: StringName, item_visible: bool) -> void:
	if _items.has(id):
		_items[id].visible = item_visible


func _on_item_pressed(id: StringName) -> void:
	if auto_select and id != selected:
		select(id)
		AudioManager.play(&"tick")
	item_pressed.emit(id)


## The items have their final rects now. Snap the indicator onto the selected
## item, or retarget a slide that is still running so it lands there.
func _on_children_sorted() -> void:
	if not _buttons.has(selected):
		return
	var target := _indicator_target()
	if _indicator_tween and _indicator_tween.is_valid() and _indicator_tween.is_running():
		if not is_equal_approx(target, _indicator_goal):
			_slide_indicator_to(target)
		return
	_indicator_pos = target


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
	_slide_indicator_to(target)


func _slide_indicator_to(target: float) -> void:
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
	_indicator_goal = target
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
	draw_rect(rect, ThemeColors.of(self, ThemeColors.STATE))
