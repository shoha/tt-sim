class_name RoomPanel
extends Control

## The room: one panel, learned once, shown two ways. Between maps it fills the screen on
## paper (RoomScreen, Root's ROOM state); at a table it is the glass drawer over the board
## (RoomDrawer, opened with Tab). It is where the GM keeps the session's maps (the shelf) and
## sets one out, and where everyone sees who is here.
##
## Players are listed on the left (portrait, name, GM chip, a download bar for the selected
## map; your own row has Choose avatar) with the shelf below them. A selected shelf map shows
## large in the centre with its one action directly under it: Set out this map in the room,
## Move the table here in the drawer. That action is the screen's one accent fill, and only
## while it is live. The room code with Copy and Invite sits top right; Leave (a player) or
## End session (the GM) bottom left. The GM adds maps to the shelf through a picker over the
## library; players see the shelf read-only but can select a map to look at it. There is no
## manual Ready: readiness is download state ("3 of 4 have it"), and Set out never waits.
##
## Everything shown comes from a session summary (show_session()); RoomModel holds the rules.
## With connect_network (the default) the panel reads NetworkManager.session on every change;
## tests and the UI tour clear it before adding the panel and feed summaries themselves.

signal set_out_requested(key: String)
signal move_table_requested(key: String)
## The GM picked a map to add to the shelf (with connect_network, it is shelved and selected).
signal map_picked(level_info: Dictionary)
signal leave_requested

const LEVEL_PICKER_SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")
## The side column and the drawer share the drawer width token (UI_TASTE S5).
const SIDE_WIDTH := 396.0
## The room's distance from the canvas edge, and between the side sheet and the stage.
const EDGE := 32.0
const GAP := 24.0
const PREVIEW_ASPECT := 16.0 / 9.0
const PREVIEW_MAX_WIDTH := 720.0
const PREVIEW_MIN_WIDTH := 320.0
## The drawer's picture of the selected map, beside its name.
const DRAWER_PREVIEW := Vector2(128, 72)
## The stage's height besides the preview: the name, readiness, action and their gaps.
const STAGE_CHROME := 170.0
## Joins this soon after the panel opens are the initial roster sync, not arrivals.
const JOIN_SOUND_GRACE_MS := 1000

## True for the drawer over a table, false for the full-screen room. Set before adding.
@export var in_drawer := false
@export var connect_network := true

var title_label: Label
var caption_label: Label
var code_label: Label
var copy_button: IconButton
var invite_button: IconButton
var player_rows: VBoxContainer
var shelf_rows: VBoxContainer
var add_button: Button
var leave_button: Button
var stage: VBoxContainer
var preview: Panel
var map_name_label: Label
var readiness_label: Label
var action_button: Button

var _local_id := ""
var _is_gm := false
var _selected := ""
var _table := ""
var _players: Array[Dictionary] = []
var _shelf: Array[Dictionary] = []
## folder -> Texture2D, or null for a map without a thumbnail here
var _thumbs: Dictionary = {}
var _ready_ms := 0


func _ready() -> void:
	_ready_ms = Time.get_ticks_msec()
	if in_drawer:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if connect_network:
		NetworkManager.session.session_changed.connect(refresh)
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		set_code(NetworkManager.room_code)
		refresh()
	else:
		show_session({}, "", false)


func _exit_tree() -> void:
	if not connect_network:
		return
	if NetworkManager.session.session_changed.is_connected(refresh):
		NetworkManager.session.session_changed.disconnect(refresh)
	if NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.disconnect(_on_player_joined)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)


## Read the live session (NetworkManager.session) and show it.
func refresh() -> void:
	var session := NetworkManager.session
	var peer := multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 0
	show_session(session.summary(), session.session_id_of(peer), NetworkManager.is_host())


## Show a session summary (SessionChannel.summary()) as the player `local_id` sees it, as the
## GM when `is_gm`. The selection survives while its map stays on the shelf; the drawer
## selects the map on the table when nothing is.
func show_session(summary: Dictionary, local_id: String, is_gm: bool) -> void:
	_local_id = local_id
	_is_gm = is_gm
	_table = str(summary.get("table", ""))
	_players = RoomModel.players(summary, local_id)
	_shelf = RoomModel.shelf(summary)
	if not _shelf.any(func(entry: Dictionary) -> bool: return entry.key == _selected):
		_selected = _table if in_drawer else ""
	add_button.visible = is_gm
	leave_button.text = "End session" if is_gm else "Leave"
	_show_header()
	_fill_shelf()
	_show_selection()


## The room code, as read aloud and copied.
func set_code(code: String) -> void:
	code_label.text = code if code != "" else "------"


## Select the shelf map `key` ("" for none) and show it in the centre.
func select(key: String) -> void:
	_selected = key if _shelf.any(func(entry: Dictionary) -> bool: return entry.key == key) else ""
	_show_selection()


func selected_key() -> String:
	return _selected


# -- Building ------------------------------------------------------------------


func _build() -> void:
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.theme_type_variation = &"BoxContainerSpaced"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	if in_drawer:
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# The code shares the heading's line, so the selected map's action stays on screen.
		var head := HBoxContainer.new()
		head.name = "TopBar"
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(head)
		var heading := _build_heading()
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(heading)
		head.add_child(_build_code_row())
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		layout.add_child(scroll)
		var column := _vbox("Column", &"BoxContainerSpaced")
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(column)
		column.add_child(_build_players())
		column.add_child(_build_shelf())
		column.add_child(_build_stage())
		layout.add_child(_build_footer())
		return
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = EDGE
	layout.offset_top = EDGE
	layout.offset_right = -EDGE
	layout.offset_bottom = -EDGE
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(top)
	var heading := _build_heading()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(_build_code_row())
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(body)
	var side := PanelContainer.new()
	side.name = "Side"
	side.custom_minimum_size.x = SIDE_WIDTH
	body.add_child(side)
	var side_box := _vbox("SideBox", &"BoxContainerSpaced")
	side.add_child(side_box)
	side_box.add_child(_build_players())
	var shelf := _build_shelf()
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_box.add_child(shelf)
	side_box.add_child(_build_footer())
	body.add_child(_spacer(Vector2(GAP, 0)))
	var stage_box := _build_stage()
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_box.resized.connect(_fit_preview)
	body.add_child(stage_box)


func _build_heading() -> VBoxContainer:
	var box := _vbox("Heading", &"")
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"Heading" if in_drawer else &"Title"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title_label)
	caption_label = Label.new()
	caption_label.name = "Caption"
	caption_label.theme_type_variation = &"Caption"
	caption_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(caption_label)
	return box


func _build_code_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CodeRow"
	row.theme_type_variation = &"" if in_drawer else &"BoxContainerSpaced"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not in_drawer:
		var caption := Label.new()
		caption.text = "Room code"
		caption.theme_type_variation = &"Caption"
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(caption)
	var chip := PanelContainer.new()
	chip.name = "CodeChip"
	chip.theme_type_variation = &"CodeChip"
	chip.tooltip_text = "Room code"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	code_label = Label.new()
	code_label.name = "Code"
	code_label.theme_type_variation = &"Code"
	chip.add_child(code_label)
	set_code("")
	copy_button = _icon_button("Copy", "copy", "Copy code", _on_copy_pressed)
	row.add_child(copy_button)
	invite_button = _icon_button("Invite", "share", "Invite friends", _on_invite_pressed)
	row.add_child(invite_button)
	return row


func _build_players() -> VBoxContainer:
	var box := _vbox("Players", &"BoxContainerSpaced")
	box.add_child(_section_label("Players"))
	player_rows = _vbox("PlayerRows", &"BoxContainerSpaced")
	box.add_child(player_rows)
	return box


func _build_shelf() -> VBoxContainer:
	var box := _vbox("Shelf", &"BoxContainerSpaced")
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var label := _section_label("Shelf")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	add_button = Button.new()
	add_button.name = "AddMap"
	add_button.text = "Add a map"
	add_button.icon = IconButton.load_icon("plus")
	add_button.pressed.connect(_on_add_pressed)
	head.add_child(add_button)
	shelf_rows = _vbox("ShelfRows", &"")
	if in_drawer:
		box.add_child(shelf_rows)
		return box
	var scroll := ScrollContainer.new()
	scroll.name = "ShelfScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	shelf_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shelf_rows)
	return box


## The selected map and its action. The room shows it large in the centre; the drawer, where
## the column is narrow and the action must stay on screen, as a strip (a small picture beside
## the name) with the action directly under it.
func _build_stage() -> VBoxContainer:
	stage = _vbox("Stage", &"BoxContainerSpaced")
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	var initial := &"Heading" if in_drawer else &"CardInitial"
	preview = RoomRows.thumb_well(DRAWER_PREVIEW if in_drawer else Vector2.ZERO, null, "", initial)
	preview.name = "Preview"
	map_name_label = Label.new()
	map_name_label.name = "MapName"
	map_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	readiness_label = Label.new()
	readiness_label.name = "Readiness"
	readiness_label.theme_type_variation = &"Caption"
	if in_drawer:
		var strip := HBoxContainer.new()
		strip.name = "Strip"
		strip.theme_type_variation = &"BoxContainerSpaced"
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(strip)
		strip.add_child(preview)
		var text := _vbox("Text", &"")
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(text)
		text.add_child(map_name_label)
		text.add_child(readiness_label)
	else:
		preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		readiness_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage.add_child(preview)
		stage.add_child(map_name_label)
		stage.add_child(readiness_label)
	action_button = Button.new()
	action_button.name = "Action"
	action_button.custom_minimum_size = Vector2(0 if in_drawer else 280, 44)
	if not in_drawer:
		action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_button.pressed.connect(_on_action_pressed)
	stage.add_child(action_button)
	return stage


func _build_footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave_button = Button.new()
	leave_button.name = "Leave"
	leave_button.icon = IconButton.load_icon("logout")
	leave_button.pressed.connect(_on_leave_pressed)
	footer.add_child(leave_button)
	return footer


func _vbox(node_name: String, variation: StringName) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.theme_type_variation = variation
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionHeader"
	return label


func _spacer(min_size: Vector2) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = min_size
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _icon_button(node_name: String, icon: String, tip: String, action: Callable) -> IconButton:
	var button := IconButton.new()
	button.name = node_name
	button.icon_name = icon
	button.tooltip_text = tip
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	return button


# -- Showing -------------------------------------------------------------------


func _show_header() -> void:
	var table_name := ""
	for entry in _shelf:
		if entry.on_table:
			table_name = entry.name
	var gm := RoomModel.gm_name(_players)
	var text := RoomModel.header(in_drawer, _is_gm, gm, _shelf.size(), table_name)
	title_label.text = text.title
	caption_label.text = text.caption
	caption_label.visible = text.caption != ""


func _fill_players() -> void:
	for child in player_rows.get_children():
		player_rows.remove_child(child)
		child.queue_free()
	for player in _players:
		player_rows.add_child(RoomRows.player_row(player, _selected, _on_choose_avatar_pressed))


func _fill_shelf() -> void:
	for child in shelf_rows.get_children():
		shelf_rows.remove_child(child)
		child.queue_free()
	if _shelf.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.theme_type_variation = &"Caption"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "No maps yet" if _is_gm else "The GM has not added a map yet"
		shelf_rows.add_child(empty)
		return
	for entry in _shelf:
		var caption := "On the table" if entry.on_table else ""
		if caption == "" and not in_drawer:
			caption = RoomModel.readiness_text(_players, entry.key)
		var row := RoomRows.shelf_row(entry, _thumb_for(entry), caption, true)
		row.pressed.connect(select.bind(str(entry.key)))
		shelf_rows.add_child(row)


func _show_selection() -> void:
	for row: Node in shelf_rows.get_children():
		if row is Button:
			RoomRows.show_shelf_selected(row, row.name == "Map_%s" % _selected.validate_node_name())
	_fill_players()
	var entry := {}
	for candidate in _shelf:
		if candidate.key == _selected:
			entry = candidate
	preview.visible = not entry.is_empty()
	if entry.is_empty():
		map_name_label.text = RoomModel.empty_stage_text(_is_gm, _shelf.size())
		map_name_label.theme_type_variation = &"Body" if in_drawer else &"Heading"
		readiness_label.text = ""
	else:
		RoomRows.set_well(preview, _thumb_for(entry), str(entry.name))
		map_name_label.text = entry.name
		map_name_label.theme_type_variation = &"Heading" if in_drawer else &"Title"
		readiness_label.text = (
			"On the table now" if entry.on_table else RoomModel.readiness_text(_players, _selected)
		)
	readiness_label.visible = readiness_label.text != ""
	var action := RoomModel.action(in_drawer, _is_gm, _selected, _table)
	action_button.visible = action.shown
	action_button.text = action.text
	action_button.disabled = not action.enabled
	# The one accent fill, and only while the action is live: a disabled Set out stays quiet.
	action_button.theme_type_variation = &"Primary" if action.enabled else &""


func _thumb_for(entry: Dictionary) -> Texture2D:
	var folder := str(entry.folder)
	if folder == "":
		return null
	if not _thumbs.has(folder):
		var texture: Texture2D = null
		var path := LevelManager.thumbnail_path(folder)
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image:
				texture = ImageTexture.create_from_image(image)
		_thumbs[folder] = texture
	return _thumbs[folder]


## The room's preview: as wide as the stage allows up to PREVIEW_MAX_WIDTH, 16:9, leaving the
## stage room for the name and the action under it.
func _fit_preview() -> void:
	var width := minf(stage.size.x - GAP * 2.0, PREVIEW_MAX_WIDTH)
	width = minf(width, (stage.size.y - STAGE_CHROME) * PREVIEW_ASPECT)
	width = maxf(width, PREVIEW_MIN_WIDTH)
	var target := Vector2(width, width / PREVIEW_ASPECT).floor()
	if preview.custom_minimum_size != target:
		preview.custom_minimum_size = target


# -- Actions -------------------------------------------------------------------


func _on_action_pressed() -> void:
	if _selected == "" or action_button.disabled:
		return
	if in_drawer:
		move_table_requested.emit(_selected)
	else:
		set_out_requested.emit(_selected)


func _on_add_pressed() -> void:
	var picker: LevelPickerDialog = LEVEL_PICKER_SCENE.instantiate()
	picker.setup("Add a map to the shelf")
	picker.level_chosen.connect(_on_level_picked)
	get_tree().root.add_child(picker)
	# Leaving the room with the picker still open must not strand it over what comes next.
	tree_exiting.connect(picker.queue_free)


func _on_level_picked(info: Dictionary) -> void:
	map_picked.emit(info)
	if not connect_network:
		return
	var level := LevelManager.load_level(String(info.get("path", "")), false)
	if level == null:
		UIManager.show_error("Could not load that map")
		return
	var key := NetworkManager.session.shelve(level.to_dict())
	if key != "":
		select(key)


func _on_leave_pressed() -> void:
	if not _is_gm:
		leave_requested.emit()
		return
	UIManager.show_confirmation(
		"End the session?",
		"Everyone leaves the room and the table.",
		"End session",
		"Stay",
		leave_requested.emit,
		Callable(),
		"Danger",
		&"leave_game"
	)


func _on_choose_avatar_pressed() -> void:
	AvatarRoster.open(get_tree().root)


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(code_label.text)
	UIManager.show_success("Code copied")


func _on_invite_pressed() -> void:
	NetworkManager.open_invite_overlay()


func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	if Time.get_ticks_msec() - _ready_ms >= JOIN_SOUND_GRACE_MS:
		AudioManager.play(&"success")


func _on_player_left(_peer_id: int, _info: Dictionary) -> void:
	AudioManager.play(&"tick")
