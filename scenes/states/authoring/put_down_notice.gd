class_name PutDownNotice
extends PanelContainer

## The card a right click puts up in AuthoringPanel above a tool's pane when it puts the tool's
## brush away: what happened, a Pick up button, and the pane's tiles drawn unpicked, because no
## brush is out to hold their choice. Without it a put-down brush looks like a tool that stopped
## working. Any tile of the pane, or the Pick up button, brings the brush back; the tiles then
## show their picks again (all but the one just pressed, which keeps its own).

## The Pick up button: the tool whose brush was put down.
signal pick_up_requested(tool_id: StringName)

const TEXT := (
	"A right click puts the %s brush away. Pick it up again to carry on, or pick a tile below."
)
const BUTTON := "Pick up %s"

var _tool: StringName = &""
var _label: Label
var _button: Button
## The single-select tile rows of the pane and the tile each had picked.
var _picks: Dictionary = {}


func _init() -> void:
	name = "PutDownNotice"
	theme_type_variation = &"Card"
	visible = false
	var column := VBoxContainer.new()
	column.theme_type_variation = &"BoxContainerSnug"
	add_child(column)
	var title := Label.new()
	title.name = "PutDownTitle"
	title.text = "Brush put down"
	title.theme_type_variation = &"Heading"
	column.add_child(title)
	_label = Label.new()
	_label.name = "PutDownText"
	_label.theme_type_variation = &"Caption"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(1, 0)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label)
	_button = Button.new()
	_button.name = "PutDownPickUp"
	_button.pressed.connect(func() -> void: pick_up_requested.emit(_tool))
	column.add_child(_button)


## Shows the card for `tool`, whose pane `pane` holds the tiles to clear.
func show_for(tool: ToolDescriptor, pane: Node) -> void:
	hide_notice()
	_tool = tool.id
	var rows: Array[TileRow] = []
	_collect_rows(pane, rows)
	for row in rows:
		if not row.multi_select and row.selected != &"":
			_picks[row] = row.selected
			row.clear_selection()
	_label.text = TEXT % tool.label
	_button.text = BUTTON % tool.label
	visible = true


## Hides the card and gives back the picks nothing has replaced since.
func hide_notice() -> void:
	_tool = &""
	for row: TileRow in _picks:
		if is_instance_valid(row) and row.selected == &"":
			row.select(_picks[row])
	_picks.clear()
	visible = false


static func _collect_rows(node: Node, out: Array[TileRow]) -> void:
	if node == null:
		return
	if node is TileRow:
		out.append(node)
	for child in node.get_children():
		_collect_rows(child, out)
