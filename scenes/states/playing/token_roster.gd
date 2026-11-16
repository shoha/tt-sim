class_name TokenRoster
extends DrawerContainer

## The token roster: every token on the table in one list, in a glass drawer at the left edge.
## It exists so a player can find their token (under foliage, among thirty) without hunting
## the board: a row's press selects the token, centres the camera on it and pulses its glow;
## hovering a row lights the token on the board. T opens and closes it (the rail's tooltip
## says so), and the rail item shows the count.
##
## The list comes from TokenRosterModel (a player sees only tokens the GM has not hidden and
## their own first). The selected token has a card at the foot of the drawer with its name,
## its health in words and a bar, a Find button (centre and pulse again) and an Actions button
## that opens the token's own menu beside the drawer, so the roster is also the selection UI
## the board lacks: the glow on the board and the card agree on which token is picked.
## The drawer reads the table again while it is open (REFRESH_S), not while it is closed.

## A row was pressed: the host centres the camera on `token` and pulses it.
signal token_chosen(token: BoardToken)
## The card's Actions button: the host opens the token's menu at `at` (screen pixels).
signal menu_requested(token: BoardToken, at: Vector2)
## The header's Add token button (the GM): the host opens the asset browser.
signal add_requested

## A list, not a pane: narrower than the 396 drawer token (UI_TASTE S5), so at a 914 px canvas
## (1280x720 at Auto) the drawer and its rail stay left of the board centre.
const WIDTH := 304.0
const RAIL_ID := &"tokens"
## The table is read again this often while the drawer is open.
const REFRESH_S := 0.5
## A token pulses this long after a row picks it.
const PULSE_S := 1.6
const ROW_HEIGHT := 52.0

## The network id of the picked token, "" when none is.
var selected_id: String = ""

## Where the roster reads its tokens, the host sets them in setup(): `source` returns the
## BoardToken nodes, `controls` answers whether this peer controls one, `is_gm` whether this
## peer is the GM (it lists hidden tokens and shows Add token).
var _source: Callable = Callable()
var _controls: Callable = Callable()
var _is_gm: Callable = Callable()

var _rows: Array[Dictionary] = []
var _row_nodes: Dictionary = {}  ## network_id -> the row's Control
var _hovered: BoardToken = null
var _signature: String = ""
var _timer: Timer

var _count_label: Label
var _add_button: Button
var _list: VBoxContainer
var _scroll: ScrollContainer
var _card: VBoxContainer
var _card_name: Label
var _card_status: Label
var _card_bar: ProgressBar
var _empty_label: Label
var _find_button: Button
var _actions_button: Button


func _on_ready() -> void:
	drawer_width = WIDTH
	tab_width = 44.0
	tab_top_margin = 12.0
	rail_items = [{"id": RAIL_ID, "icon": "chess", "tooltip": tr("Tokens (T)")}]
	_build_content()
	_timer = Timer.new()
	_timer.name = "RefreshTimer"
	_timer.wait_time = REFRESH_S
	_timer.one_shot = false
	_timer.timeout.connect(refresh)
	add_child(_timer)
	pane_requested.connect(_on_pane_requested)


## Gives the roster its table: see the three Callables above.
func setup(source: Callable, controls: Callable, is_gm: Callable) -> void:
	_source = source
	_controls = controls
	_is_gm = is_gm
	refresh()


func _build_content() -> void:
	var header := HBoxContainer.new()
	header.theme_type_variation = &"BoxContainerSpaced"
	content_container.add_child(header)
	var title := Label.new()
	title.text = tr("Tokens")
	title.theme_type_variation = &"PanelHeader"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_button = AnimatedButton.new()
	_add_button.name = "AddTokenButton"
	_add_button.text = tr("Add token")
	_add_button.icon = IconButton.load_icon("plus")
	_add_button.theme_type_variation = &"Secondary"
	_add_button.custom_minimum_size = Vector2(0, 40)
	_add_button.pressed.connect(func() -> void: add_requested.emit())
	header.add_child(_add_button)

	_count_label = Label.new()
	_count_label.theme_type_variation = &"Caption"
	content_container.add_child(_count_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_empty_label = Label.new()
	_empty_label.theme_type_variation = &"Caption"
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label asks for a tall minimum while its width is unknown, and a drawer panel
	# that has grown to it never shrinks back: give it the column's width and keep it hidden
	# until the list is read.
	_empty_label.custom_minimum_size.x = WIDTH - 40.0
	_empty_label.visible = false
	_empty_label.text = tr("Tokens you add to the table are listed here. Press one to find it.")
	content_container.add_child(_empty_label)

	content_container.add_child(HSeparator.new())
	_build_card()


## The selected token's card at the drawer's foot.
func _build_card() -> void:
	_card = VBoxContainer.new()
	_card.name = "SelectedCard"
	_card.theme_type_variation = &"BoxContainerSpaced"
	content_container.add_child(_card)
	_card_name = Label.new()
	_card_name.theme_type_variation = &"H3"
	_card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card.add_child(_card_name)
	_card_status = Label.new()
	_card_status.theme_type_variation = &"Caption"
	_card.add_child(_card_status)
	_card_bar = ProgressBar.new()
	_card_bar.show_percentage = false
	_card_bar.custom_minimum_size = Vector2(0, 8)
	_card.add_child(_card_bar)
	var buttons := HBoxContainer.new()
	buttons.theme_type_variation = &"BoxContainerSpaced"
	_card.add_child(buttons)
	_find_button = AnimatedButton.new()
	_find_button.name = "FindButton"
	_find_button.text = tr("Find on map")
	_find_button.icon = IconButton.load_icon("target")
	_find_button.theme_type_variation = &"Secondary"
	_find_button.custom_minimum_size = Vector2(0, 40)
	_find_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_find_button.pressed.connect(_on_find_pressed)
	buttons.add_child(_find_button)
	_actions_button = AnimatedButton.new()
	_actions_button.name = "ActionsButton"
	_actions_button.text = tr("Actions")
	_actions_button.icon = IconButton.load_icon("dots-vertical")
	_actions_button.theme_type_variation = &"Secondary"
	_actions_button.custom_minimum_size = Vector2(0, 40)
	_actions_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_button.pressed.connect(_on_actions_pressed)
	buttons.add_child(_actions_button)
	_card.visible = false


# -- Reading the table ---------------------------------------------------------------------


## Reads the table again: rebuilds the list when the tokens or their order changed, else
## updates the words and bars in place. Cheap enough to call on every change.
func refresh() -> void:
	if not _source.is_valid():
		return
	var is_gm: bool = _is_gm.is_valid() and bool(_is_gm.call())
	_rows = TokenRosterModel.rows(_source.call(), is_gm, _controls)
	_add_button.visible = is_gm
	_count_label.text = TokenRosterModel.count_text(_rows.size())
	_empty_label.visible = _rows.is_empty()
	var signature := _signature_of(_rows)
	if signature != _signature:
		_signature = signature
		_rebuild_rows()
	else:
		for row in _rows:
			_update_row(row)
	_update_card()


## The ids, names and groups of `rows` in order: the list is rebuilt only when this changes.
static func _signature_of(rows: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for row in rows:
		parts.append("%s|%s|%s|%s" % [row["id"], row["name"], row["yours"], row["hidden"]])
	return "\n".join(parts)


func _rebuild_rows() -> void:
	_clear_hover()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_row_nodes.clear()
	var any_yours := false
	for row in _rows:
		if row["yours"]:
			any_yours = true
	var last_group := -1
	for row in _rows:
		var group := 0 if row["yours"] else 1
		if any_yours and group != last_group:
			_list.add_child(_group_label(tr("Yours") if group == 0 else tr("On the table")))
			last_group = group
		var node := _make_row(row)
		_list.add_child(node)
		_row_nodes[row["id"]] = node
		_update_row(row)


func _group_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	return label


## One row: a selection strip behind a transparent button (hover, focus and the press), with
## the words and the bar over both and ignoring the pointer. The strip takes the selected fill
## and the words their on-selected roles when the row is the picked one (_update_row).
func _make_row(row: Dictionary) -> Control:
	var root := Control.new()
	root.name = "Row_%s" % row["id"]
	root.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var strip := PanelContainer.new()
	strip.name = "Strip"
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	var button := Button.new()
	button.name = "Press"
	button.theme_type_variation = &"Ghost"
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.tooltip_text = String(row["name"])
	button.accessibility_name = tr("Find %s on the map") % row["name"]
	button.pressed.connect(_on_row_pressed.bind(String(row["id"])))
	button.mouse_entered.connect(_on_row_hovered.bind(String(row["id"])))
	button.mouse_exited.connect(_clear_hover)
	button.focus_entered.connect(_on_row_hovered.bind(String(row["id"])))
	button.focus_exited.connect(_clear_hover)
	root.add_child(button)
	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	# Inset by the preset's margin (not a theme override): the words clear the strip's edge.
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hbox)
	var vbox := VBoxContainer.new()
	vbox.name = "Words"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)
	var status := Label.new()
	status.name = "Status"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(status)
	var hidden := TextureRect.new()
	hidden.name = "HiddenIcon"
	hidden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hidden.texture = IconButton.load_icon("circle-off")
	hidden.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hidden.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hidden.custom_minimum_size = Vector2(20, 20)
	hidden.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(hidden)
	return root


## Writes `row`'s words, bar and selection into its node.
func _update_row(row: Dictionary) -> void:
	var node: Control = _row_nodes.get(row["id"])
	if node == null:
		return
	var selected: bool = row["id"] == selected_id
	var content := node.get_node("Content") as Control
	var vbox := content.get_node("Words") as VBoxContainer
	var name_label := vbox.get_node("Name") as Label
	var status := vbox.get_node("Status") as Label
	name_label.text = String(row["name"])
	name_label.theme_type_variation = &"BodyOnSelected" if selected else &"Body"
	status.text = TokenRosterModel.status_text(row)
	status.theme_type_variation = &"CaptionOnSelected" if selected else &"Caption"
	(content.get_node("HiddenIcon") as Control).visible = row["hidden"]
	(node.get_node("Strip") as PanelContainer).theme_type_variation = (
		&"CardStripSelected" if selected else &"CardStrip"
	)


# -- Choosing ----------------------------------------------------------------------------


## Presses the row at `index`, as a click does. Returns the token's name, "" when out of range.
func pick_row(index: int) -> String:
	if index < 0 or index >= _rows.size():
		return ""
	_on_row_pressed(String(_rows[index]["id"]))
	return String(_rows[index]["name"])


## How many rows the list holds.
func row_count() -> int:
	return _rows.size()


## The Control of the row for token `id`, null when it is not listed.
func row_node(id: String) -> Control:
	return _row_nodes.get(id)


func _on_row_pressed(id: String) -> void:
	selected_id = id
	for row in _rows:
		_update_row(row)
	_update_card()
	var token := _token_of(id)
	if token != null:
		token_chosen.emit(token)


func _token_of(id: String) -> BoardToken:
	for row in _rows:
		if row["id"] == id:
			return row["token"] if is_instance_valid(row["token"]) else null
	return null


func _on_find_pressed() -> void:
	var token := _token_of(selected_id)
	if token != null:
		token_chosen.emit(token)


func _on_actions_pressed() -> void:
	var token := _token_of(selected_id)
	if token == null:
		return
	var rect := _actions_button.get_global_rect()
	menu_requested.emit(token, Vector2(rect.end.x + 8.0, rect.position.y))


## The card for the selected token; hidden when none is selected or it left the table.
func _update_card() -> void:
	var token := _token_of(selected_id)
	if token == null:
		selected_id = ""
		_card.visible = false
		return
	var row: Dictionary = {}
	for candidate in _rows:
		if candidate["id"] == selected_id:
			row = candidate
	_card.visible = true
	_card_name.text = String(row["name"])
	_card_status.text = TokenRosterModel.status_text(row)
	_card_bar.max_value = maxf(1.0, float(row["max_hp"]))
	_card_bar.value = clampf(float(row["hp"]), 0.0, _card_bar.max_value)
	_card_bar.theme_type_variation = (
		&"ProgressSuccess" if row["health"] == TokenRosterModel.Health.HEALTHY else &"ProgressDanger"
	)
	_card_bar.visible = row["max_hp"] > 0


# -- Board feedback ----------------------------------------------------------------------


## A row under the pointer or focus lights its token on the board.
func _on_row_hovered(id: String) -> void:
	_clear_hover()
	var token := _token_of(id)
	if token != null:
		_hovered = token
		token.add_highlight()


func _clear_hover() -> void:
	if _hovered != null and is_instance_valid(_hovered):
		_hovered.remove_highlight()
	_hovered = null


# -- Opening and closing -----------------------------------------------------------------


func _on_pane_requested(_id: StringName) -> void:
	refresh()
	_timer.start()


func _on_closed() -> void:
	_timer.stop()
	_clear_hover()


## T opens and closes the roster, at a table, with its tab shown and nothing else taking the
## key (the room drawer's rules: no overlay or text field, no brush or measure tool).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_T:
		return
	if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if not is_revealed or not is_visible_in_tree():
		return
	if UIManager.get_current_state() != UIManager.ROOT_STATE_PLAYING or _board_busy():
		return
	toggle()
	if is_open:
		refresh()
		_timer.start()
	get_viewport().set_input_as_handled()


func _board_busy() -> bool:
	if UIManager.has_open_overlay() or AnimatedCanvasLayerPanel.any_open():
		return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return true
	var node := get_parent()
	while node != null and not node.has_method(&"get_brush_tool"):
		node = node.get_parent()
	if node == null:
		return false
	var map := node
	if map.get_brush_tool() != null and map.get_brush_tool().takes_tab():
		return true
	return map.get_measure_tool() != null and map.get_measure_tool().is_active()


func _exit_tree() -> void:
	_clear_hover()
