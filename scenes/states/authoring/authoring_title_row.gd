class_name AuthoringTitleRow
extends HBoxContainer

## The head of the map tools' card: the icon and the name of the rail tool the card is about (Water,
## Build, Place, Biome...), above the hub's tabs. Every pane's own title is hidden in favour of it
## (AuthoringPanes.hide_titles), so a tab ("Crossing", "Walls") never has to say which tool it
## belongs to, and a card is always labelled with the tool whose rail item is lit (card
## ui-authoring3, the critic's round-3 finding). The icon is the rail's own glyph, in the theme's
## icon colour.

var _icon: IconButton
var _label: Label


func _init() -> void:
	name = "ToolTitle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_icon = IconButton.new()
	_icon.name = "ToolTitleIcon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.focus_mode = Control.FOCUS_NONE
	_icon.rail_glyph = true
	add_child(_icon)
	_label = Label.new()
	_label.name = "ToolTitleName"
	_label.theme_type_variation = &"Title"
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_label)


## Shows the row for `rail_tool`, or hides it with none.
func show_tool(rail_tool: ToolDescriptor) -> void:
	visible = rail_tool != null
	if rail_tool != null:
		_icon.icon_name = rail_tool.icon
		_label.text = rail_tool.label


## The name on show.
func title() -> String:
	return _label.text
