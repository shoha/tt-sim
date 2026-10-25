class_name LibraryRow
extends HBoxContainer

## One collection in the manager's list: the selectable row (name, a caption, what it holds or
## why it fails, the origin chip) and, at its right, the state: the on/off switch, or for a
## collection that fails the "Needs attention" pill in place of the switch (owner decision
## 2026-10-25).
##
## The columns are FIXED so every row lines up (review UX-4: the old alert icon sat between the
## chip and the switch of failing rows only and pushed their chips out of line): the origin chip
## lives in an ORIGIN_SLOT wide slot, the switch or the pill in a STATE_SLOT wide slot, both on
## every row. A failing row is dimmed (its text and chip), never its pill. Every state has a
## non-colour cue: the switch position, "Off" in the caption, the pill's icon and words, and the
## marker at the left of the selected row.

signal chosen(key: String)
signal switched(on: bool, key: String)

const ROW_HEIGHT := 76.0
const ORIGIN_SLOT := 84.0
## At least as wide as the "Needs attention" pill, or the failing rows' columns would shift.
const STATE_SLOT := 152.0
const ICON_PX := 20.0
const MARKER_PX := 14.0
const DIM_ALPHA := 0.62
const ALWAYS_ON := "This one comes with the game and is always on."

var key: String = ""
var item: Dictionary = {}
var button: Button
var toggle: CheckButton = null
var pill: PanelContainer = null
var origin_chip: PanelContainer
var marker: TextureRect


## Builds the row of `entry` (a LibraryRegistry.list() entry plus the manager's `key`,
## `same_id`). Call once, before it enters the tree.
func setup(entry: Dictionary) -> void:
	item = entry
	key = String(entry.get("key", entry["id"]))
	name = "Item_%s" % key.validate_node_name()
	theme_type_variation = &"BoxContainerTight"
	var failing := String(entry["status"]) == LibraryResolver.ERROR
	button = Button.new()
	button.name = "Row"
	button.theme_type_variation = &"ListRow"
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s\n%s" % [entry["name"], facts_of(entry)]
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void: chosen.emit(key))
	add_child(button)
	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8
	inner.offset_right = -8
	button.add_child(inner)
	marker = TextureRect.new()
	marker.name = "Marker"
	marker.texture = IconButton.load_icon("chevron-right")
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker.custom_minimum_size = Vector2(MARKER_PX, MARKER_PX)
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.modulate.a = 0.0
	inner.add_child(marker)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)
	_row_label(String(entry["name"]), &"Body", "Name", text)
	_row_label(caption_of(entry), &"Caption", "Caption", text)
	_row_label(facts_of(entry), &"Caption", "Facts", text)
	var slot := _slot("OriginSlot", ORIGIN_SLOT, BoxContainer.ALIGNMENT_BEGIN)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(slot)
	origin_chip = LibraryDetail.chip(LibraryDetail.origin_badge(entry), "Origin")
	origin_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(origin_chip)
	var state_slot := _slot("StateSlot", STATE_SLOT, BoxContainer.ALIGNMENT_BEGIN)
	add_child(state_slot)
	if failing:
		text.modulate.a = DIM_ALPHA
		slot.modulate.a = DIM_ALPHA
		pill = attention_pill()
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pill.mouse_filter = Control.MOUSE_FILTER_STOP
		pill.gui_input.connect(_on_pill_input)
		pill.tooltip_text = LibraryReasons.headline(entry)
		state_slot.add_child(pill)
		return
	toggle = CheckButton.new()
	toggle.name = "Toggle"
	toggle.button_pressed = bool(entry["enabled"])
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A collection a host sent is an ordinary one that is only marked (libcache): it switches.
	var locked := (
		String(entry["id"]) == LibraryContracts.CORE_ID or String(entry["source"]) == "dev"
	)
	toggle.disabled = locked
	toggle.tooltip_text = (
		ALWAYS_ON
		if locked
		else ("Turn off %s" if toggle.button_pressed else "Turn on %s") % String(entry["name"])
	)
	toggle.toggled.connect(func(on: bool) -> void: switched.emit(on, key))
	state_slot.add_child(toggle)


## Marks the row as the selected one: pressed, the on-selected text roles and the marker.
func set_selected(on: bool) -> void:
	button.set_pressed_no_signal(on)
	marker.modulate.a = 1.0 if on else 0.0
	var text := button.get_node("Inner/Text")
	(text.get_node("Name") as Label).theme_type_variation = &"BodyOnSelected" if on else &"Body"
	for line: String in ["Caption", "Facts"]:
		(text.get_node(line) as Label).theme_type_variation = (
			&"CaptionOnSelected" if on else &"Caption"
		)


## The "Needs attention" pill: an alert icon and the words in the danger tone, on a raised chip
## with a danger edge, so it reads without the colour (icon and text) and with it.
static func attention_pill() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Attention"
	panel.theme_type_variation = &"Chip"
	var line := HBoxContainer.new()
	line.theme_type_variation = &"BoxContainerTight"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var mark := TextureRect.new()
	mark.name = "Icon"
	mark.texture = IconButton.load_icon("alert-circle")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(ICON_PX - 4.0, ICON_PX - 4.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(mark)
	var label := Label.new()
	label.name = "Label"
	label.theme_type_variation = &"Caption"
	label.text = LibraryNames.NEEDS_ATTENTION
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	panel.tree_entered.connect(
		func() -> void:
			var danger := ThemeColors.of(panel, ThemeColors.DANGER)
			mark.self_modulate = danger
			label.add_theme_color_override(&"font_color", danger)
			var base := panel.get_theme_stylebox(&"panel") as StyleBoxFlat
			if base != null:
				var edged := base.duplicate() as StyleBoxFlat
				edged.border_color = danger
				edged.set_border_width_all(2)
				panel.add_theme_stylebox_override(&"panel", edged)
	)
	return panel


## The second line of a row: "v0.3.1 by Test Author", with "Off · " in front of a library that is
## turned off and the folder's name after it when two folders hold the same id. Pure.
static func caption_of(entry: Dictionary) -> String:
	var line := LibraryDetail.subtitle_of(entry).split(" · ")[0]
	if not bool(entry["enabled"]):
		line = ("Off · " + line) if line != "" else "Off"
	if bool(entry.get("same_id", false)):
		var where := "folder %s" % String(entry["folder"]).get_file()
		line = (line + " · " + where) if line != "" else where
	return line


## The third line: what it holds ("2 assets, 1 biome · 5 KB"), or, for a library that fails, why
## in one plain sentence (LibraryReasons). Pure.
static func facts_of(entry: Dictionary) -> String:
	if String(entry["status"]) == LibraryResolver.ERROR:
		var all := LibraryReasons.explain_all(entry)
		return String(all[0]["message"]) if not all.is_empty() else ""
	var line := LibraryDetail.contents_text(entry)
	if not bool(entry.get("official", false)):
		line += " · " + LibraryImporter.size_text(int(entry["bytes"]))
	return line


## A fixed-width column of the row (the same width on every row, so chips line up).
static func _slot(
	node_name: String, width: float, align: BoxContainer.AlignmentMode
) -> HBoxContainer:
	var slot := HBoxContainer.new()
	slot.name = node_name
	slot.custom_minimum_size.x = width
	slot.alignment = align
	return slot


func _row_label(text: String, variation: StringName, node_name: String, parent: Control) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = variation
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _on_pill_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(key)
