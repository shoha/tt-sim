class_name SegmentedTabs
extends PanelContainer

## A short row of words in a sunken pill, one of them picked: the top tabs of a tool that holds
## several (Place and its erase mode, Water's River / Pond / Crossing, Build's Walls / Buildings /
## Villages). Single-select through one ButtonGroup, so exactly one tab is on. Signals fire only for
## a click; select() and the setters are silent, so a pane can follow the state without feedback.
## Each tab is a Button named for its id (the validation bridge clicks it) and shares the row's
## width equally. The look is the theme's (SegmentTrack, SegmentTab), so it follows the surface.

## A tab was picked by the user.
signal tab_selected(id: StringName)

## The tabs' height: a 44 px target in a 1280x720 window needs about 47 virtual px.
const TAB_HEIGHT := 40.0

var selected: StringName = &""

var _tabs: Dictionary = {}
var _group: ButtonGroup
var _row: HBoxContainer


func _init() -> void:
	theme_type_variation = &"SegmentTrack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.theme_type_variation = &"BoxContainerSnug"
	add_child(_row)
	_group = ButtonGroup.new()
	_group.allow_unpress = false


## Adds a tab: `id`, its words and its tooltip. Returns the button.
func add_tab(id: StringName, label: String, tooltip: String = "") -> Button:
	var tab := Button.new()
	tab.name = String(id)
	tab.text = label
	tab.toggle_mode = true
	tab.button_group = _group
	tab.theme_type_variation = &"SegmentTab"
	tab.tooltip_text = tooltip
	tab.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.clip_text = true
	tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tab.focus_mode = Control.FOCUS_ALL
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.set_meta("ui_silent", true)
	tab.toggled.connect(_on_toggled.bind(id))
	_row.add_child(tab)
	_tabs[id] = tab
	if selected == &"":
		select(id)
	return tab


## The tab ids, in order.
func tab_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _tabs:
		ids.append(id)
	return ids


func has_tab(id: StringName) -> bool:
	return _tabs.has(id)


## The button of tab `id`, or null.
func tab(id: StringName) -> Button:
	return _tabs.get(id)


## Picks tab `id` without a signal.
func select(id: StringName) -> void:
	if not _tabs.has(id):
		return
	selected = id
	(_tabs[id] as Button).set_pressed_no_signal(true)


## Enables or disables tab `id`; `tooltip` (when not empty) replaces its tooltip, so a disabled tab
## says why.
func set_tab_enabled(id: StringName, enabled: bool, tooltip: String = "") -> void:
	var button: Button = _tabs.get(id)
	if button == null:
		return
	button.disabled = not enabled
	if tooltip != "":
		button.tooltip_text = tooltip


## The id of the next enabled tab after `from`, wrapping round (`from` itself when it is the only
## one): what pressing a tool's key again goes to.
func next_enabled(from: StringName) -> StringName:
	var ids := tab_ids()
	var start := ids.find(from)
	for step in range(1, ids.size() + 1):
		var id := ids[(start + step) % ids.size()]
		if not (_tabs[id] as Button).disabled:
			return id
	return from


func _on_toggled(pressed: bool, id: StringName) -> void:
	if not pressed or id == selected:
		return
	selected = id
	AudioManager.play(&"tick")
	tab_selected.emit(id)
