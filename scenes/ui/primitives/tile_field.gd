class_name TileField
extends VBoxContainer

## A caption above a full-width TileRow. Tile rows need the whole pane width
## (four 64 px tiles per row); putting them in a PropertyRow's slider slot
## wraps them into 2-2-1 stacks. The caption carries the override tint and
## right-click reset that PropertyRow labels have, so environment-backed tile
## rows keep that affordance. show_note() puts a second caption at the end of the
## caption's line, for what a pick implies (the new-map dialog's "Ground: forest
## floor" beside Start from) without a line of its own.

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
## The caption line's right-aligned note, once show_note() has made it.
var note: Label

var _caption: Label


func _init() -> void:
	tiles = TileRow.new()
	tiles.name = "Tiles"
	tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Shows `text` at the end of the caption's line, right-aligned, and returns its label.
func show_note(text: String) -> Label:
	if note == null:
		note = Label.new()
		note.name = "Note"
		note.theme_type_variation = &"Caption"
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_place_note()
	note.text = text
	return note


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
	_place_note()
	_refresh_override()


## Puts the caption and the note on one line, once both exist.
func _place_note() -> void:
	if note == null or _caption == null or note.get_parent() != null:
		return
	var line := HBoxContainer.new()
	line.name = "CaptionLine"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	move_child(line, _caption.get_index())
	remove_child(_caption)
	line.add_child(_caption)
	line.add_child(note)


func _refresh_override() -> void:
	if not _caption:
		return
	# A value changed from its default is a state, so it reads in the state colour.
	_caption.theme_type_variation = &"CaptionState" if overridden else &"Caption"
	_caption.tooltip_text = OVERRIDE_TOOLTIP if overridden else ""


func _on_caption_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			reset_requested.emit()
