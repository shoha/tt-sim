class_name LevelEditPane
extends VBoxContainer

## Base for the Visuals drawer panes. A pane owns a working copy of the fields
## it edits, loads them from a LevelVisualState, writes them back on Save,
## emits [signal changed] on every user edit (the panel marks dirty and badges
## the rail item) and emits its own domain signal with the live payload. Panes
## build their controls in code from [method _build]; there is no .tscn.

signal changed

const ROW_SEPARATION := 6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", ROW_SEPARATION)
	_build()


## Create controls. Called once from _ready().
func _build() -> void:
	pass


## Set controls from [param state] without emitting anything.
func load_state(_state: LevelVisualState) -> void:
	pass


## Write this pane's fields into [param state] as independent copies.
func write_state(_state: LevelVisualState) -> void:
	pass


func _add_heading(text: String) -> Label:
	var heading := Label.new()
	heading.text = text
	heading.theme_type_variation = &"SectionHeader"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(heading)
	return heading


func _add_caption(text: String, parent: Node = self) -> Label:
	var caption := Label.new()
	caption.text = text
	caption.theme_type_variation = &"Caption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(caption)
	return caption


## opts: exp_edit, allow_greater, allow_lesser, show_color, show_check,
## show_slider (default true), tooltip, hint_low, hint_high, formatter
## (Callable), parent (default self; pass a Foldout's body to place the row
## inside it).
func _add_row(
	label: String,
	min_value: float,
	max_value: float,
	step: float,
	value: float,
	opts: Dictionary = {}
) -> PropertyRow:
	var row := PropertyRow.new()
	row.label = label
	row.show_slider = opts.get("show_slider", true)
	row.show_color = opts.get("show_color", false)
	row.show_check = opts.get("show_check", false)
	row.min_value = min_value
	row.max_value = max_value
	row.step = step
	row.value = value
	row.exp_edit = opts.get("exp_edit", false)
	row.allow_greater = opts.get("allow_greater", false)
	row.allow_lesser = opts.get("allow_lesser", false)
	row.tooltip_text = opts.get("tooltip", "")
	row.hint_low = opts.get("hint_low", "")
	row.hint_high = opts.get("hint_high", "")
	if opts.has("formatter"):
		row.formatter = opts["formatter"]
	var parent: Node = opts.get("parent", self)
	parent.add_child(row)
	return row


func _add_foldout(title: String = "Advanced") -> Foldout:
	var foldout := Foldout.new()
	foldout.title = title
	add_child(foldout)
	return foldout


## A captioned, full-width tile row. [param specs] entries are [id, label,
## icon_name]; pass an empty array to add tiles yourself (painted textures).
func _add_tile_field(caption: String, specs: Array, parent: Node = self) -> TileField:
	var field := TileField.new()
	field.caption = caption
	for spec in specs:
		field.tiles.add_tile(StringName(spec[0]), spec[1], spec[2])
	parent.add_child(field)
	return field
