class_name LevelEditPane
extends VBoxContainer

## Base for the Visuals drawer panes. A pane owns a working copy of the fields
## it edits, loads them from a LevelVisualState, writes them back on Save,
## emits [signal changed] on every user edit (the panel marks dirty and badges
## the rail item) and emits its own domain signal with the live payload. Panes
## build their controls in code from [method _build]; there is no .tscn.

signal changed

const ROW_SEPARATION := 6
## The eraser on the Sky and Color panes (_add_look_heading): both edit one look. It takes
## Sky and Color back to the Look picked (the drawer's Revert look puts every pane back as
## last saved), so its words say what it undoes and to what.
const LOOK_CLEAR_TIP := "Back to the Look: clear the changes made over it in Sky and Color"
const LOOK_CLEARED := "Sky and Color changes undone."


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


## The heading of a pane on the shared EnvironmentEditModel (Sky, Color) with the one way to
## undo the look's changes at its end: the eraser, the same on both panes (LOOK_CLEAR_TIP).
## Returns the eraser; the pane wires it to its model and shows it only while something is
## changed over the Look (show_look_clear), so a clean pane offers no second revert beside the
## drawer's Revert look. The heading's line keeps the eraser's height either way.
func _add_look_heading(text: String) -> IconButton:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	var heading := _add_heading(text)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.reparent(header)
	var clear := IconButton.new()
	clear.name = "ClearLook"
	clear.icon_name = "eraser"
	clear.tooltip_text = LOOK_CLEAR_TIP
	header.add_child(clear)
	header.custom_minimum_size.y = clear.get_combined_minimum_size().y
	show_look_clear(clear, false)
	return clear


## The eraser `clear` shown (and able) while `changed`, hidden while the pane matches its Look.
static func show_look_clear(clear: IconButton, changed: bool) -> void:
	clear.visible = changed
	clear.disabled = not changed


## A muted caption: a subhead over the rows it names (Water's Advanced groups), or with
## _add_note a sentence under a control. Captions wrap (docs/UI_TASTE.md), so a long one never
## widens the pane.
func _add_caption(text: String, parent: Node = self) -> Label:
	var caption := Label.new()
	caption.text = text
	caption.theme_type_variation = &"Caption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(caption)
	return caption


## A sentence under the control above it (what the picked sky, look or Sunlight mode does),
## with a stacked row's gap under it, so it reads with its control rather than the next one.
func _add_note(text: String, parent: Node = self) -> Label:
	var note := _add_caption(text, parent)
	var gap := Control.new()
	gap.name = "NoteGap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0, PropertyRow.STACKED_ROW_GAP)
	parent.add_child(gap)
	return note


## opts: exp_edit, allow_greater, allow_lesser, show_color, show_check,
## show_slider (default true), tooltip, hint_low, hint_high, formatter
## (Callable), show_readout (the value always at the label line's end), parent
## (default self; pass a Foldout's body to place the row inside it). A slider row is
## stacked (PropertyRow.stacked): the label and its value on one line, the slider the
## pane's full width under it, since the drawer is too narrow for both on one line.
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
	row.stacked = row.show_slider
	row.show_readout = opts.get("show_readout", false)
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
