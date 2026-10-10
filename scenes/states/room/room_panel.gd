class_name RoomPanel
extends Control

## The room: one panel, learned once, shown two ways. Between maps it fills the screen on
## paper (RoomScreen, Root's ROOM state); at a table it is the glass drawer over the board
## (RoomDrawer, opened with Tab). It is where the GM keeps the session's maps (the shelf) and
## sets one out, and where everyone sees who is here.
##
## Players are listed on the left (portrait, name, and a caption line: the GM chip, You, and
## the selected map's download state as an icon and a word; your own row ends in Choose
## avatar) with the shelf below them. A selected shelf map shows large in the centre with its
## one action directly under it: Set out this map in the room, Move the table here in the
## drawer. With an empty shelf the centre shows a painted placeholder over what goes there,
## and its action is Add a map; with maps but none selected it says to choose one, and offers
## nothing. That action is the screen's one accent fill, and only while it is live. The room
## code with Copy and Invite sits top right (in the drawer, on its own line under the
## heading); Leave session (a player) or End session (the GM) bottom left. The GM adds maps
## to the shelf through a picker over the library; players see the shelf read-only but can
## select a map to look at it, and read their own download state first. There is no manual
## Ready: readiness is download state ("3 of 4 have it"), and Set out never waits.
##
## Everything shown comes from a session summary (show_session()); RoomModel holds the rules
## and RoomLayout builds the controls. With connect_network (the default) the panel reads
## NetworkManager.session on every change; tests and the UI tour clear it before adding the
## panel and feed summaries themselves.

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
## The stage's height besides the preview: the name, readiness, action and their gaps.
const STAGE_CHROME := 190.0
## Joins this soon after the panel opens are the initial roster sync, not arrivals.
const JOIN_SOUND_GRACE_MS := 1000

## True for the drawer over a table, false for the full-screen room. Set before adding.
@export var in_drawer := false
@export var connect_network := true

var title_label: Label
var caption_label: Label
var code_label: Label
var copy_button: Button
var invite_button: Button
var player_rows: VBoxContainer
var shelf_rows: VBoxContainer
## The room's shelf scroll and side sheet, and the body they sit in (null in the drawer).
var shelf_scroll: ScrollContainer
var side: PanelContainer
var body: HBoxContainer
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
## folder -> {"texture": Texture2D or null, "mood": String}, read once per folder
var _pictures: Dictionary = {}
var _ready_ms := 0


func _ready() -> void:
	_ready_ms = Time.get_ticks_msec()
	if in_drawer:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RoomLayout.build(self)
	copy_button.pressed.connect(_on_copy_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	add_button.pressed.connect(_on_add_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	action_button.pressed.connect(_on_action_pressed)
	if not in_drawer:
		stage.resized.connect(_fit_preview)
		body.resized.connect(_fit_side)
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
	# With an empty shelf, Add a map is the centre's action rather than a second button here.
	add_button.visible = is_gm and not _shelf.is_empty()
	leave_button.text = "End session" if is_gm else "Leave session"
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


## Open the picker that adds a library map to the shelf (the GM's Add a map).
func open_map_picker() -> void:
	var picker: LevelPickerDialog = LEVEL_PICKER_SCENE.instantiate()
	picker.setup("Add a map to the shelf")
	picker.level_chosen.connect(_on_level_picked)
	get_tree().root.add_child(picker)
	picker.choose_button.text = "Add to the shelf"
	# Leaving the room with the picker still open must not strand it over what comes next.
	tree_exiting.connect(picker.queue_free)


## Ask to leave: a player leaves at once, the GM confirms ending the session for everyone (W2:
## the action and its consequence on the message and on the button).
func ask_to_leave() -> void:
	if not _is_gm:
		leave_requested.emit()
		return
	UIManager.show_confirmation(
		"End the session?",
		"Everyone goes back to their title screen.",
		"End session",
		"Stay",
		leave_requested.emit,
		Callable(),
		"Danger",
		&"leave_game"
	)


# -- Showing -------------------------------------------------------------------


func _show_header() -> void:
	var table_name := ""
	for entry in _shelf:
		if entry.on_table:
			table_name = entry.name
	var gm := RoomModel.gm_name(_players)
	var text := RoomModel.header(in_drawer, _is_gm, gm, _shelf.size(), table_name)
	title_label.text = text.title
	title_label.tooltip_text = text.title
	caption_label.text = text.caption
	caption_label.tooltip_text = text.caption
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
	for entry in _shelf:
		var caption := "On the table" if entry.on_table else ""
		if caption == "":
			caption = RoomModel.readiness_text(_players, entry.key)
		var picture := _picture_for(entry)
		var row := RoomRows.shelf_row(entry, picture.texture, picture.mood, caption, true)
		row.pressed.connect(select.bind(str(entry.key)))
		shelf_rows.add_child(row)
	_fit_side.call_deferred()


func _show_selection() -> void:
	for row: Node in shelf_rows.get_children():
		if row is Button:
			RoomRows.show_shelf_selected(row, row.name == "Map_%s" % _selected.validate_node_name())
	_fill_players()
	var entry := {}
	for candidate in _shelf:
		if candidate.key == _selected:
			entry = candidate
	# The drawer shows only a selected map; the room paints the placeholder when none is.
	preview.visible = not (entry.is_empty() and in_drawer)
	if entry.is_empty():
		RoomRows.set_map_well(preview, null, "", "")
		var empty := RoomModel.empty_stage(_is_gm, _shelf.size())
		map_name_label.text = empty.title
		map_name_label.theme_type_variation = &"Body" if in_drawer else &"Heading"
		readiness_label.text = "" if in_drawer else empty.caption
	else:
		var picture := _picture_for(entry)
		RoomRows.set_map_well(preview, picture.texture, _picture_key(entry), picture.mood)
		map_name_label.text = entry.name
		map_name_label.theme_type_variation = &"Heading" if in_drawer else &"Title"
		readiness_label.text = _readiness(entry)
	map_name_label.tooltip_text = map_name_label.text
	readiness_label.visible = readiness_label.text != ""
	var action := RoomModel.action(in_drawer, _is_gm, _selected, _table, _shelf.size())
	action_button.visible = action.shown
	action_button.text = action.text
	action_button.disabled = not action.enabled
	action_button.set_meta(&"adds", action.add)
	# The one accent fill, and only while the action is live: a held-back Move stays quiet.
	action_button.theme_type_variation = &"Primary" if action.enabled else &""


## The line under the selected map: on the table, or its readiness, a player's own first.
func _readiness(entry: Dictionary) -> String:
	if entry.on_table:
		return "On the table now"
	if _is_gm:
		return RoomModel.readiness_text(_players, entry.key)
	return RoomModel.own_readiness_text(_players, entry.key)


## The placeholder's key for a shelf entry: its folder, or its name without one.
func _picture_key(entry: Dictionary) -> String:
	return str(entry.folder) if str(entry.folder) != "" else str(entry.name)


## A shelf map's thumbnail (null without one here) and mood, read once per folder.
func _picture_for(entry: Dictionary) -> Dictionary:
	var folder := str(entry.folder)
	if folder == "":
		return {"texture": null, "mood": ""}
	if not _pictures.has(folder):
		var texture: Texture2D = null
		var path := LevelManager.thumbnail_path(folder)
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image:
				texture = ImageTexture.create_from_image(image)
		var info := LevelManager.folder_info(folder)
		_pictures[folder] = {"texture": texture, "mood": str(info.get("environment_preset", ""))}
	return _pictures[folder]


## The room's preview: as wide as the stage allows up to PREVIEW_MAX_WIDTH, 16:9, leaving the
## stage room for the name and the action under it.
func _fit_preview() -> void:
	var width := minf(stage.size.x - GAP * 2.0, PREVIEW_MAX_WIDTH)
	width = minf(width, (stage.size.y - STAGE_CHROME) * PREVIEW_ASPECT)
	width = maxf(width, PREVIEW_MIN_WIDTH)
	var target := Vector2(width, width / PREVIEW_ASPECT).floor()
	if preview.custom_minimum_size != target:
		preview.custom_minimum_size = target


## The room's side sheet ends at its content (no empty paper under a short shelf); when the
## shelf is too long for the screen, the sheet takes the full height and the shelf scrolls.
func _fit_side() -> void:
	if in_drawer or body == null or not is_inside_tree():
		return
	var rows_height := shelf_rows.get_combined_minimum_size().y
	var scrolling := shelf_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var needed := side.get_combined_minimum_size().y + (rows_height if scrolling else 0.0)
	var fits := needed <= body.size.y
	var mode := ScrollContainer.SCROLL_MODE_DISABLED if fits else ScrollContainer.SCROLL_MODE_AUTO
	if shelf_scroll.vertical_scroll_mode != mode:
		shelf_scroll.vertical_scroll_mode = mode
	var flags := Control.SIZE_SHRINK_BEGIN if fits else Control.SIZE_FILL
	if side.size_flags_vertical != flags:
		side.size_flags_vertical = flags


# -- Actions -------------------------------------------------------------------


func _on_action_pressed() -> void:
	if action_button.disabled:
		return
	if action_button.get_meta(&"adds", false):
		open_map_picker()
	elif _selected == "":
		return
	elif in_drawer:
		move_table_requested.emit(_selected)
	else:
		set_out_requested.emit(_selected)


func _on_add_pressed() -> void:
	open_map_picker()


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
	ask_to_leave()


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
