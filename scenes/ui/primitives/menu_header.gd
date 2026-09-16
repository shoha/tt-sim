class_name MenuHeader
extends VBoxContainer

## The block every menu screen opens with: a sentence-case title, an optional
## muted caption, an optional close button on the title's right, and the rule
## under them. Callers pass copy already in sentence case — no menu shouts.

signal close_requested

const SEPARATION := 4

var title_label: Label
var caption_label: Label
## Null until setup() is called with closable = true.
var close_button: IconButton

var _row: HBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", SEPARATION)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"H2"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(title_label)
	caption_label = Label.new()
	caption_label.name = "Caption"
	caption_label.theme_type_variation = &"Caption"
	caption_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	caption_label.visible = false
	add_child(caption_label)
	add_child(HSeparator.new())


## Safe to call before or after the header enters the tree, and safe to call
## twice: the close button is only ever built once.
func setup(title: String, caption: String = "", closable: bool = false) -> void:
	title_label.text = title
	caption_label.text = caption
	caption_label.visible = not caption.is_empty()
	if closable and close_button == null:
		close_button = IconButton.new()
		close_button.name = "Close"
		close_button.icon_name = "x"
		close_button.tooltip_text = "Close"
		close_button.pressed.connect(_on_close_pressed)
		_row.add_child(close_button)


func _on_close_pressed() -> void:
	close_requested.emit()
