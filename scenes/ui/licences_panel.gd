class_name LicencesPanel
extends AnimatedCanvasLayerPanel

## The Licences page, opened from Settings, About: a list of what the game is made with at the
## left and the selected item's notice in a scrolling pane at the right.
##
## The entries come from LicenceCatalog (`data/third_party.json` for the game and what it ships,
## the engine's own notices for Godot). The list is a column of ListRow buttons under small
## group headings. Focus moves the selection, as in a list box, so Up and Down (keyboard, d-pad)
## read through the items with no extra press; Right moves into the notice, which scrolls with
## Up, Down and the page keys while it has focus, and Left comes back to the item. Escape or the
## header's close button closes the sheet.
##
## Built in code, like the collections manager: the scrim, the centring and the sheet the base
## class expects.

signal closed

const SHEET_WIDTH := 960.0
const LIST_WIDTH := 264.0
const MAX_BODY_HEIGHT := 560.0
const MIN_BODY_HEIGHT := 240.0
const ROW_HEIGHT := 40.0

var header: MenuHeader
var title_label: Label
var meta_label: Label
var credit_label: Label
var text_pane: TextEdit

var _body: VBoxContainer
var _split: HBoxContainer
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array[Dictionary] = []
var _rows: Array[Button] = []
var _selected: int = -1
var _closing := false


func _init() -> void:
	name = "LicencesPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = Constants.LAYER_DIALOG
	var scrim := Scrim.new()
	scrim.name = "ColorRect"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.name = "CenterContainer"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	sheet.custom_minimum_size.x = SHEET_WIDTH
	centre.add_child(sheet)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.theme_type_variation = &"BoxContainerSpaced"
	sheet.add_child(_body)


## Opens the page under `parent` (the tree's root from Settings).
static func open(parent: Node) -> LicencesPanel:
	var panel := LicencesPanel.new()
	parent.add_child(panel)
	return panel


func _on_panel_ready() -> void:
	header = MenuHeader.new()
	header.name = "Header"
	header.setup(
		"Licences", "What this game is made with, and the terms it is shared under.", true
	)
	header.close_requested.connect(close)
	_body.add_child(header)
	_build_split()
	_entries = LicenceCatalog.entries()
	_fill_list()
	if not _rows.is_empty():
		_select(0)
	UIManager.register_overlay($ColorRect as Control)
	get_viewport().size_changed.connect(_fit_to_canvas)
	_fit_to_canvas()


func _exit_tree() -> void:
	super._exit_tree()
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_fit_to_canvas):
		viewport.size_changed.disconnect(_fit_to_canvas)


func _build_split() -> void:
	_split = HBoxContainer.new()
	_split.name = "Split"
	_split.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(_split)
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "ListScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.custom_minimum_size.x = LIST_WIDTH
	# The rows' focus rings sit at this clip's edges: room for the ring.
	ShadowGutter.wrap(_list_scroll, ShadowGutter.Kind.RING)
	_split.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	_list_scroll.add_child(ScrollFade.new())
	ScrollBarFade.attach(_list_scroll)
	_split.add_child(VSeparator.new())
	var notice := VBoxContainer.new()
	notice.name = "Notice"
	notice.theme_type_variation = &"BoxContainerSpaced"
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.add_child(notice)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"Heading"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice.add_child(title_label)
	meta_label = Label.new()
	meta_label.name = "Meta"
	meta_label.theme_type_variation = &"Caption"
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_child(meta_label)
	credit_label = Label.new()
	credit_label.name = "Credit"
	credit_label.theme_type_variation = &"Body"
	credit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit_label.visible = false
	notice.add_child(credit_label)
	# A read-only TextEdit, which the theme styles (a RichTextLabel has no theme entry and drew
	# white on the paper): it wraps, scrolls, selects and takes Up, Down and the page keys.
	text_pane = TextEdit.new()
	text_pane.name = "Text"
	text_pane.editable = false
	text_pane.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_pane.context_menu_enabled = false
	text_pane.virtual_keyboard_enabled = false
	text_pane.focus_mode = Control.FOCUS_ALL
	text_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_pane.gui_input.connect(_on_text_input)
	notice.add_child(text_pane)


## One heading per group and one ListRow button per entry, in catalog order.
func _fill_list() -> void:
	var group := ""
	for index in _entries.size():
		var entry := _entries[index]
		var entry_group := str(entry.get("group", ""))
		if entry_group != group:
			if group != "":
				UiActions.spacer(8, _list)
			group = entry_group
			var heading := Label.new()
			heading.name = "Group%d" % index
			heading.theme_type_variation = &"Caption"
			heading.text = group
			_list.add_child(heading)
		_list.add_child(_make_row(index, entry))


func _make_row(index: int, entry: Dictionary) -> Button:
	var row := Button.new()
	row.name = "Item_%s" % str(entry.get("id", index)).validate_node_name()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.text = str(entry.get("name", ""))
	row.tooltip_text = row.text
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.set_meta("ui_silent", true)
	row.pressed.connect(_select.bind(index))
	row.focus_entered.connect(_select.bind(index))
	_rows.append(row)
	return row


## Shows entry `index`: the row marked, the heading, the one-line description, the credit line
## the licence asks for (when there is one) and the notice, scrolled to its top.
func _select(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	# A click on the marked row would unpress its toggle: keep it marked.
	for i in _rows.size():
		_rows[i].set_pressed_no_signal(i == index)
	if index == _selected:
		return
	var first := _selected < 0
	_selected = index
	var entry := _entries[index]
	title_label.text = str(entry.get("name", ""))
	var what := str(entry.get("what", ""))
	var licence := str(entry.get("licence", ""))
	meta_label.text = what if licence == "" else "%s  Licence: %s." % [what, licence]
	var credit := str(entry.get("credit", ""))
	credit_label.text = credit
	credit_label.visible = credit != ""
	text_pane.text = str(entry.get("text", ""))
	text_pane.set_caret_line(0)
	text_pane.scroll_vertical = 0
	text_pane.focus_neighbor_left = text_pane.get_path_to(_rows[index])
	for row in _rows:
		row.focus_neighbor_right = row.get_path_to(text_pane)
	if not first:
		AudioManager.play(&"tick")


## Left in the notice goes back to the marked item (a TextEdit would move its hidden caret).
func _on_text_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") and _selected >= 0:
		_rows[_selected].grab_focus()
		text_pane.accept_event()


## The selected entry's index (-1 before the list is filled).
func selected_index() -> int:
	return _selected


## The list row for entry `index` (tests and callers that move focus).
func row_at(index: int) -> Button:
	return _rows[index] if index >= 0 and index < _rows.size() else null


func entry_count() -> int:
	return _entries.size()


func _fit_to_canvas() -> void:
	if not is_inside_tree() or _split == null:
		return
	var canvas := get_viewport().get_visible_rect().size
	var sheet := $CenterContainer/PanelContainer as PanelContainer
	var margin := sheet.get_theme_constant(&"space_5", &"Space")
	sheet.custom_minimum_size.x = minf(SHEET_WIDTH, canvas.x - 2.0 * margin)
	var chrome := sheet.get_combined_minimum_size().y - _split.get_combined_minimum_size().y
	var room := canvas.y - 2.0 * margin - chrome
	var height := clampf(minf(MAX_BODY_HEIGHT, room), MIN_BODY_HEIGHT, MAX_BODY_HEIGHT)
	height = minf(height, maxf(room, 0.0))
	_list_scroll.custom_minimum_size.y = height
	text_pane.custom_minimum_size.y = maxf(height - _notice_chrome(), 120.0)


## The height of what stands in the notice column above the scrolling text.
func _notice_chrome() -> float:
	var chrome := 0.0
	for child in text_pane.get_parent().get_children():
		if child != text_pane and child is Control and (child as Control).visible:
			chrome += (child as Control).get_combined_minimum_size().y + 12.0
	return chrome


func _on_after_animate_in() -> void:
	var row := row_at(maxi(_selected, 0))
	if row != null:
		row.grab_focus()


func close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	animate_out()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
