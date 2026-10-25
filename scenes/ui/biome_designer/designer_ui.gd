class_name DesignerUI
extends Control

## The biome designer's screen (design doc 4.3), laid over the live map: the header across the
## top, the asset picker above the slot list on the left, the rule inspector on the right, the
## ground strip across the bottom, and between them the map itself, untouched (the middle of the
## screen passes the pointer to the game camera and the brush's picking). Composed of one script per
## panel; this one lays them out, wires them to the session and forwards the header's buttons.
## Theme: the glass leaf, since the map plays on under it (UI_TASTE C8). Sizes are the panels'
## own minimums; nothing here sets a colour, a font or a margin.

signal save_requested
signal save_as_requested(collection_id: String, collection_name: String)
signal revert_requested
signal thumbnail_requested
signal leave_requested

const LEFT_WIDTH := 380.0
const RIGHT_WIDTH := 430.0
## The ground strip's height: two rows of pickers and chips; a taller strip scrolls.
const GROUND_HEIGHT := 128.0

var session: BiomeDesignerSession = null
var header: DesignerHeader = null
var picker: DesignerAssetPicker = null
var slots: DesignerSlotList = null
var inspector: DesignerRuleInspector = null
var ground: DesignerGroundStrip = null
## The A/B divider over the map window, and the ground look editor that takes the inspector's
## place while Look... is on.
var compare_overlay: DesignerCompareOverlay = null
var look_editor: DesignerLookEditor = null

var _dialog: DesignerCollectionDialog = null
var _inspector_scroll: ScrollContainer = null
var _look_scroll: ScrollContainer = null


func _init() -> void:
	name = "DesignerUI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeColors.glass_theme()


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	var page := VBoxContainer.new()
	page.name = "Page"
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	var top := PanelContainer.new()
	top.name = "HeaderSheet"
	header = DesignerHeader.new()
	header.setup(session)
	header.save_requested.connect(func() -> void: save_requested.emit())
	header.save_as_requested.connect(_open_dialog)
	header.revert_requested.connect(func() -> void: revert_requested.emit())
	header.thumbnail_requested.connect(func() -> void: thumbnail_requested.emit())
	header.leave_requested.connect(func() -> void: leave_requested.emit())
	top.add_child(header)
	page.add_child(top)
	var middle := HBoxContainer.new()
	middle.name = "Middle"
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(middle)
	middle.add_child(_left_column())
	var window := Control.new()
	window.name = "MapWindow"
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(window)
	compare_overlay = DesignerCompareOverlay.new()
	window.add_child(compare_overlay)
	compare_overlay.setup(session)
	middle.add_child(_right_column())
	var bottom := PanelContainer.new()
	bottom.name = "GroundSheet"
	# The strip scrolls when the window is too small for all its rows, so it never pushes the
	# map and the panels out of the window.
	var strip_scroll := ScrollContainer.new()
	strip_scroll.name = "GroundScroll"
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ShadowGutter.wrap(strip_scroll, ShadowGutter.Kind.GLASS_RING)
	strip_scroll.custom_minimum_size = Vector2(0.0, GROUND_HEIGHT)
	bottom.add_child(strip_scroll)
	ground = DesignerGroundStrip.new()
	ground.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground.setup(session)
	ground.look_requested.connect(_on_look_requested)
	strip_scroll.add_child(ground)
	page.add_child(bottom)


## Whether the ground look editor is the right column now.
func look_open() -> bool:
	return _look_scroll != null and _look_scroll.visible


## Shows the ground look editor in the inspector's place (`on`), or the inspector again.
func show_look(on: bool) -> void:
	_look_scroll.visible = on
	_look_scroll.get_parent().visible = on
	_inspector_scroll.visible = not on
	_inspector_scroll.get_parent().visible = not on
	var button := ground.look_button()
	if button.button_pressed != on:
		button.set_pressed_no_signal(on)


func _on_look_requested() -> void:
	show_look(ground.look_button().button_pressed)


## Shows the "Save as new collection" dialog. `taken`: the library ids that exist.
func _open_dialog() -> void:
	if is_instance_valid(_dialog):
		return
	_dialog = DesignerCollectionDialog.new()
	_dialog.cancelled.connect(_close_dialog)
	_dialog.confirmed.connect(
		func(id: String, display_name: String) -> void:
			_close_dialog()
			save_as_requested.emit(id, display_name)
	)
	add_child(_dialog)
	var taken: Array[String] = []
	for entry in LibraryRegistry.list():
		taken.append(String(entry["id"]))
	_dialog.open("%s copy" % String(session.model.def.get("name", session.model.biome_id)), taken)


func _close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


## Whether a modal dialog of the designer is up (the host leaves the keyboard to it).
func has_dialog() -> bool:
	return is_instance_valid(_dialog)


func _left_column() -> Control:
	var sheet := PanelContainer.new()
	sheet.name = "LeftSheet"
	sheet.custom_minimum_size = Vector2(LEFT_WIDTH, 0.0)
	var column := VBoxContainer.new()
	column.name = "LeftColumn"
	sheet.add_child(column)
	picker = DesignerAssetPicker.new()
	picker.size_flags_stretch_ratio = 1.0
	picker.setup(session)
	picker.add_requested.connect(_on_add_asset)
	picker.pin_requested.connect(_on_pin_asset)
	picker.new_rule_requested.connect(_on_new_rule_from_asset)
	column.add_child(picker)
	column.add_child(HSeparator.new())
	slots = DesignerSlotList.new()
	slots.size_flags_stretch_ratio = 1.0
	slots.setup(session)
	slots.rule_selected.connect(session.select_rule)
	slots.add_rule_requested.connect(_on_add_rule)
	column.add_child(slots)
	return sheet


func _right_column() -> Control:
	var sheet := PanelContainer.new()
	sheet.name = "RightSheet"
	sheet.custom_minimum_size = Vector2(RIGHT_WIDTH, 0.0)
	var scroll := ScrollContainer.new()
	scroll.name = "InspectorScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The scroll's clip reaches out by the glass ring's room, so a button at the inspector's edge
	# keeps its shadow and focus ring while the rows stay where they are.
	sheet.add_child(ShadowGutter.outset(scroll, ShadowGutter.Kind.GLASS_RING))
	inspector = DesignerRuleInspector.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.setup(session)
	scroll.add_child(inspector)
	_inspector_scroll = scroll
	_look_scroll = ScrollContainer.new()
	_look_scroll.name = "LookScroll"
	_look_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_look_scroll.visible = false
	var look_holder := ShadowGutter.outset(_look_scroll, ShadowGutter.Kind.GLASS_RING)
	look_holder.visible = false
	sheet.add_child(look_holder)
	look_editor = DesignerLookEditor.new()
	look_editor.visible = true
	look_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_editor.setup(session)
	look_editor.closed.connect(func() -> void: show_look(false))
	_look_scroll.add_child(look_editor)
	return sheet


func _on_add_asset(ref: String) -> void:
	if session.selected_rule == "":
		_on_new_rule_from_asset(ref)
	else:
		session.model.add_ref(session.selected_rule, ref)


func _on_pin_asset(ref: String) -> void:
	if session.selected_rule != "":
		session.model.set_pin(session.selected_rule, ref, true)


func _on_new_rule_from_asset(ref: String) -> void:
	var category := ""
	var size_class := ""
	for candidate in session.model.catalog():
		if candidate["ref"] == ref or candidate["group"] == ref:
			var entry: Dictionary = candidate["entry"]
			category = String(entry.get("category", ""))
			size_class = String(entry.get("size_class", ""))
			break
	var role := DesignerSlots.role_for(category, size_class)
	var key := session.model.add_rule(role, {"match": [{"ref": ref}]}, ref)
	if key != "":
		session.select_rule(key)


func _on_add_rule(role: String) -> void:
	var key := session.model.add_rule(role)
	if key != "":
		session.select_rule(key)
