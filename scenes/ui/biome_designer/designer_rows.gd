class_name DesignerRows
extends RefCounted

## Small builders for the rows the designer's inspector is made of, so each section script only
## says what it edits. They return the control; the section keeps the reference it needs to sync
## the row from the model and connects its signal. No colour, size or spacing is set here: the
## theme's variations (Caption, Chip, H3) and PropertyRow's own layout decide.


## A stacked slider row with a numeric chip: label over a full-width slider, the value typed or
## dragged. `tip` is the tooltip; `unit` is appended to the readout.
static func number(
	node_name: String,
	label: String,
	low: float,
	high: float,
	step: float,
	tip: String = "",
	unit: String = "",
	logarithmic: bool = false
) -> PropertyRow:
	var row := PropertyRow.new()
	row.name = node_name
	row.label = label
	row.stacked = true
	row.show_readout = true
	row.values_visible = true
	row.min_value = low
	row.max_value = high
	row.step = step
	row.exp_edit = logarithmic
	row.allow_greater = true
	row.tooltip_text = tip
	if unit != "":
		row.formatter = func(value: float) -> String: return "%s %s" % [_trim(value), unit]
	else:
		row.formatter = func(value: float) -> String: return _trim(value)
	return row


## A label and an OptionButton on one line; `options` is [[id, label], ...]. Returns the
## OptionButton (its parent line is `button.get_parent()`).
static func option(
	parent: Control, node_name: String, label: String, options: Array, tip: String = ""
) -> OptionButton:
	var line := HBoxContainer.new()
	line.name = node_name + "Line"
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.tooltip_text = tip
	line.add_child(text)
	var button := OptionButton.new()
	button.name = node_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = tip
	for i in options.size():
		button.add_item(String(options[i][1]), i)
		button.set_item_metadata(i, options[i][0])
	line.add_child(button)
	parent.add_child(line)
	return button


## Selects the item of `button` whose metadata is `id` (no signal); false when there is none.
static func select(button: OptionButton, id: Variant) -> bool:
	for i in button.item_count:
		if button.get_item_metadata(i) == id:
			button.select(i)
			return true
	return false


## The id (metadata) of the selected item, null for none.
static func selected(button: OptionButton) -> Variant:
	return button.get_item_metadata(button.selected) if button.selected >= 0 else null


## A caption label that wraps.
static func caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1.0, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## A foldout section titled `title`.
static func section(node_name: String, title: String, open: bool = false) -> Foldout:
	var foldout := Foldout.new()
	foldout.name = node_name
	foldout.title = title
	foldout.button_room = true
	foldout.expanded = open
	return foldout


## A small chip button.
static func chip(node_name: String, text: String, tip: String = "") -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = &"Chip"
	button.tooltip_text = tip
	return button


static func _trim(value: float) -> String:
	if absf(value) >= 100.0:
		return str(roundi(value))
	if absf(value) >= 1.0:
		return str(snappedf(value, 0.01))
	return str(snappedf(value, 0.0001))
