class_name TileField
extends VBoxContainer

## A caption above a full-width TileRow. Tile rows need the whole pane width
## (four 64 px tiles per row); putting them in a PropertyRow's slider slot
## wraps them into 2-2-1 stacks. The caption carries the override tint and
## right-click reset that PropertyRow labels have, so environment-backed tile
## rows keep that affordance.

signal reset_requested

const OVERRIDE_TOOLTIP := "Overridden. Right-click to reset to the preset value."

@export var caption: String = "":
	set(value):
		caption = value
		if _caption:
			_caption.text = value

@export var overridden: bool = false:
	set(value):
		overridden = value
		_refresh_override()

var tiles: TileRow

var _caption: Label


func _init() -> void:
	tiles = TileRow.new()
	tiles.name = "Tiles"
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.text = caption
	_caption.theme_type_variation = &"Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_STOP
	_caption.gui_input.connect(_on_caption_gui_input)
	add_child(_caption)
	add_child(tiles)
	_refresh_override()


func _refresh_override() -> void:
	if not _caption:
		return
	if overridden:
		_caption.add_theme_color_override("font_color", ThemeColors.ACCENT)
		_caption.tooltip_text = OVERRIDE_TOOLTIP
	else:
		_caption.remove_theme_color_override("font_color")
		_caption.tooltip_text = ""


func _on_caption_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			reset_requested.emit()
