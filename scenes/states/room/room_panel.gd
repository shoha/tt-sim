class_name RoomPanel
extends Control

## The room: one panel, learned once, shown two ways. Between maps it fills the screen on
## paper (RoomScreen, Root's ROOM state); at a table it is the glass drawer over the board
## (RoomDrawer, opened with Tab). It is where the GM keeps the session's maps (the shelf) and
## sets one out, and where everyone sees who is here.
##
## Players are listed on the left (portrait, name, and a caption line: the GM chip, You, and
## the selected map's download state as an icon and a word; your own row ends in the Avatar
## button) with the shelf below them. In the room a selected shelf map shows large in the
## centre with its one action directly under it, Set out this map. With an empty shelf the
## centre shows a painted placeholder over what goes there, and its action is Add a map; with
## maps but none selected it says to choose one, and offers nothing. In the drawer the
## selected shelf row is the selection's only picture, and the action, Move the table to the
## map by name, follows the shelf directly (pinned to the foot only when the column scrolls).
## That action is the screen's one accent fill, and only while it is live. The room code with
## Copy and Invite sits top right (in the drawer, on its own line under the heading); Leave
## session (a player) or End session (the GM) bottom left. The GM adds maps to the shelf
## through a picker over the library; players see the shelf read-only but can select a map to
## look at it, and read their own download state first. There is no manual Ready: readiness
## is download state ("3 of 4 have it"), and Set out never waits. Clients fetch shelf maps in
## the background (SessionPrefetch), so a row reads "Getting it · 40%" while one comes; the
## percent moves in place (show_progress()), not by rebuilding the rows.
##
## A map the session changed says so on the GM's shelf row ("Changed this session", read from
## changes_source, TableMover.changed_maps()) and, selected in the room, under its picture; its
## row, once selected, has Save into map (for a map with a level folder here) and Discard
## changes on a line under it, or with no folder a caption saying why Discard is all there is;
## TableMover asks before either. After Resume a GM's row also says what Resume found of its
## map (read from notes_source, SessionKeeper.notes()), on a line of its own over the caption:
## "Changed since last time" (its map files changed, so its live edits were dropped) or
## "Missing from your library" (its folder is gone; it stays on the shelf as it was kept, its
## picture faded, it cannot be set out, and selected it has Remove from shelf on a line under
## it, SessionChannel.unshelve()). Such a map is gone for everyone (RoomModel.shelf()'s
## "gone": the GM's own holdings lack it): every player row says nobody can get it, and a
## player's row and the line under its picture say the GM no longer has it, its picture faded
## too. Selecting a row never moves the table (the
## action does), and moving the table never asks: the table is kept as it is. A full shelf
## scrolls, in the room's
## side sheet as in the drawer's column, the selected row and its line scrolled into view.
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
## The selection changed: the selected map's environment preset ("" with none), for the
## room's backdrop mood.
signal selection_shown(preset: String)
## The GM pressed a changed map's Save into map or Discard changes (TableMover asks first).
signal save_changes_requested(key: String)
signal discard_changes_requested(key: String)
## The GM pressed Remove from shelf on a map missing from the library (with connect_network,
## it is taken off).
signal remove_requested(key: String)

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
## The drawer's column scroll and the spacer under its action (null in the room).
var column_scroll: ScrollContainer
var drawer_rest: Control
var add_button: Button
var leave_button: Button
var stage: VBoxContainer
## The room's picture, name and readiness of the selected map (null in the drawer).
var preview: Panel
var map_name_label: Label
var readiness_label: Label
## The drawer's caption in its action's place when there is no move to make (null in the room).
var hint_label: Label
var action_button: Button
## Where refresh() reads which shelf maps changed this session: a Callable returning
## TableMover.changed_maps()' shape (key -> Save into map offered). Unset: none did.
var changes_source: Callable
## Where refresh() reads what Resume found of the shelf: a Callable returning
## SessionKeeper.notes()' shape (key -> SessionFile.CHANGED or MISSING). Unset: nothing.
var notes_source: Callable

var _local_id := ""
var _is_gm := false
var _selected := ""
var _table := ""
var _players: Array[Dictionary] = []
var _shelf: Array[Dictionary] = []
## folder -> {"texture": Texture2D or null, "mood": String}, read once per folder
var _pictures: Dictionary = {}
var _ready_ms := 0
## The GM's changed maps, as show_changes() was last given them.
var _changed: Dictionary = {}
## What Resume found of the shelf, as show_notes() was last given it.
var _notes: Dictionary = {}


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
	if in_drawer:
		resized.connect(_fit_drawer)
	else:
		stage.resized.connect(_fit_preview)
		body.resized.connect(_fit_side)
		resized.connect(_fit_side)
	if connect_network:
		NetworkManager.session.session_changed.connect(refresh)
		NetworkManager.session.prefetch.progress_changed.connect(refresh_progress)
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
	var progress := NetworkManager.session.prefetch.progress_changed
	if progress.is_connected(refresh_progress):
		progress.disconnect(refresh_progress)
	if NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.disconnect(_on_player_joined)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)


## Read the live session (NetworkManager.session), and the changed maps from changes_source,
## and show them.
func refresh() -> void:
	var session := NetworkManager.session
	# Also runs on the state change to OFFLINE, when a client's transport may be closed.
	var peer := NetPeers.local_id(multiplayer)
	if changes_source.is_valid():
		_changed = changes_source.call()
	if notes_source.is_valid():
		_notes = notes_source.call()
	show_session(session.summary(), session.session_id_of(peer), NetworkManager.is_host())


## Show which shelf maps changed this session (`changed`: TableMover.changed_maps()' shape,
## key -> Save into map offered), for the GM: their rows say so, and the selected one has its
## Save into map and Discard changes under it.
func show_changes(changed: Dictionary) -> void:
	_changed = changed.duplicate()
	_fill_shelf()
	_show_selection()


## Show what Resume found of the shelf (`notes`: SessionKeeper.notes()' shape), for the GM:
## a map whose files changed since the session was kept says "Changed since last time" on its
## row, and one gone from this library "Missing from your library".
func show_notes(notes: Dictionary) -> void:
	_notes = notes.duplicate()
	_fill_shelf()
	_show_selection()


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


## Read the players' progress from the live session and show it in place.
func refresh_progress() -> void:
	show_progress(NetworkManager.session.summary())


## Show the players' download states from `summary` in place, as their progress moves: each
## row's icon and word and the line under the selected map change, nothing is rebuilt (a
## hovered or focused control keeps its state).
func show_progress(summary: Dictionary) -> void:
	_players = RoomModel.players(summary, _local_id)
	var gone := _is_gone(_selected)
	for player in _players:
		var row_name := "Player_%s" % str(player.id).validate_node_name()
		var row := player_rows.get_node_or_null(NodePath(row_name))
		var box := row.find_child("Download", true, false) as Control if row else null
		if box:
			RoomRows.show_download_state(box, RoomModel.download_state(player, _selected, gone))
	if not in_drawer and _selected != "":
		for entry in _shelf:
			if entry.key == _selected:
				readiness_label.text = _readiness(entry)


## The room code, as read aloud and copied.
func set_code(code: String) -> void:
	code_label.text = code if code != "" else "------"


## Select the shelf map `key` ("" for none) and show it in the centre. The GM's selection
## goes to the session, so every client fetches that map next (SessionPrefetch).
func select(key: String) -> void:
	_selected = key if _shelf.any(func(entry: Dictionary) -> bool: return entry.key == key) else ""
	if connect_network and _is_gm:
		NetworkManager.session.select_map(_selected)
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
		"End session?",
		"Everyone goes back to their title screen.",
		"End session",
		"Cancel",
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
	var gone := _is_gone(_selected)
	for player in _players:
		player_rows.add_child(
			RoomRows.player_row(player, _selected, _on_choose_avatar_pressed, gone)
		)


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
		var note: StringName = _note_of(entry.key)
		var caption := RoomModel.shelf_caption(
			entry.on_table,
			_is_gm and _changed.has(entry.key),
			RoomModel.readiness_text(_players, entry.key),
			note
		)
		if entry.gone and not _is_gm:
			caption = RoomModel.GM_LACKS
		var picture := _picture_for(entry)
		var row := RoomRows.shelf_row(
			entry,
			picture.texture,
			picture.mood,
			caption,
			true,
			RoomModel.note_text(note),
			_is_gone(entry.key)
		)
		row.pressed.connect(select.bind(str(entry.key)))
		shelf_rows.add_child(row)
	_fit_side.call_deferred()
	_fit_drawer.call_deferred()


func _show_selection() -> void:
	for row: Node in shelf_rows.get_children():
		if row is Button:
			RoomRows.show_shelf_selected(row, row.name == "Map_%s" % _selected.validate_node_name())
	_repaint_shelf()
	_show_changes_line()
	_fill_players()
	var entry := {}
	for candidate in _shelf:
		if candidate.key == _selected:
			entry = candidate
	if not in_drawer:
		_show_stage(entry)
		selection_shown.emit(_picture_for(entry).mood if not entry.is_empty() else "")
	var action := RoomModel.action(
		in_drawer, _is_gm, _selected, _table, _shelf.size(), str(entry.get("name", ""))
	)
	# A map missing from the GM's library cannot be set out or moved to: its line under the
	# row offers the ways on.
	if _is_gone(_selected) and not action.add:
		action.enabled = false
	action_button.visible = action.shown
	action_button.text = action.text
	action_button.tooltip_text = action.text if in_drawer else ""
	action_button.disabled = not action.enabled
	action_button.set_meta(&"adds", action.add)
	# The one accent fill, and only while the action is live.
	action_button.theme_type_variation = &"Primary" if action.enabled else &""
	if in_drawer:
		hint_label.text = RoomModel.drawer_hint(_is_gm, _selected, _table, _shelf.size())
		hint_label.visible = hint_label.text != ""
		_fit_drawer.call_deferred()
	# After the frame's layout, when the column knows whether it scrolls and how far.
	if is_inside_tree() and not get_tree().process_frame.is_connected(_reveal_selected):
		get_tree().process_frame.connect(_reveal_selected, CONNECT_ONE_SHOT)


## Paint every shelf row's picture from what is known of its map now, so a row shows the same
## mood as the preview and the backdrop when the map is selected (a picture first read before
## its map's details arrived is not left in the wrong light).
func _repaint_shelf() -> void:
	for entry in _shelf:
		var row := shelf_rows.get_node_or_null(NodePath("Map_%s" % str(entry.key).validate_node_name()))
		var well := row.get_node_or_null("Inner/Well") as Panel if row else null
		if well:
			var picture := _picture_for(entry)
			RoomRows.set_map_well(
				well, picture.texture, _picture_key(entry), picture.mood, str(entry.name)
			)


## The GM's Save into map and Discard changes, on a line right under the selected shelf row
## when that map changed this session, or Remove from shelf when it is missing from the
## library; no line otherwise.
func _show_changes_line() -> void:
	for child in shelf_rows.get_children():
		var line_name := str(child.name)
		if line_name.begins_with("Changes_") or line_name.begins_with("Missing_"):
			shelf_rows.remove_child(child)
			child.queue_free()
	var missing := _is_gone(_selected)
	if not _is_gm or not (_changed.has(_selected) or missing):
		return
	var row := shelf_rows.get_node_or_null(NodePath("Map_%s" % _selected.validate_node_name()))
	if row == null:
		return
	var line: Control
	if missing:
		line = RoomRows.missing_line(_selected, _on_remove_pressed)
	else:
		line = RoomRows.changes_line(
			_selected,
			bool(_changed[_selected]),
			save_changes_requested.emit,
			discard_changes_requested.emit
		)
	shelf_rows.add_child(line)
	shelf_rows.move_child(line, row.get_index() + 1)
	# The line settles to one row once it has a width: fit the column to it again then.
	line.minimum_size_changed.connect(_refit_column)


func _refit_column() -> void:
	_fit_side.call_deferred()
	_fit_drawer.call_deferred()


## The room's centre: the selected map large with its name and readiness, or with none the
## painted placeholder under what goes there.
func _show_stage(entry: Dictionary) -> void:
	# A missing map's picture is faded here as on its row.
	RoomRows.mute_well(preview, not entry.is_empty() and _is_gone(entry.key))
	if entry.is_empty():
		RoomRows.set_map_well(preview, null, "", "")
		var empty := RoomModel.empty_stage(_is_gm, _shelf.size())
		map_name_label.text = empty.title
		map_name_label.theme_type_variation = &"Heading"
		readiness_label.text = empty.caption
	else:
		var picture := _picture_for(entry)
		RoomRows.set_map_well(
			preview, picture.texture, _picture_key(entry), picture.mood, str(entry.name)
		)
		map_name_label.text = entry.name
		map_name_label.theme_type_variation = &"Title"
		readiness_label.text = _readiness(entry)
	map_name_label.tooltip_text = map_name_label.text
	readiness_label.visible = readiness_label.text != ""


## The line under the selected map: on the table, or its readiness, a player's own first; for
## the GM, what Resume found of it leads (a missing map says that alone), and a map that
## changed this session says so first, as its shelf row does.
func _readiness(entry: Dictionary) -> String:
	var changed := _is_gm and _changed.has(entry.key)
	var note: StringName = _note_of(entry.key)
	if _is_gone(entry.key):
		return RoomModel.MISSING if _is_gm else RoomModel.GM_LACKS
	var line := ""
	if entry.on_table:
		line = RoomModel.shelf_caption(true, true, "") if changed else "On the table now"
	elif _is_gm:
		line = RoomModel.shelf_caption(false, changed, RoomModel.readiness_text(_players, entry.key))
	else:
		line = RoomModel.own_readiness_text(_players, entry.key)
	var said := RoomModel.note_text(note)
	if said == "":
		return line
	return said if line == "" else "%s · %s" % [said, line]


## What Resume found of the map `key`, for the GM alone (a player's library is their own). A
## map the GM's holdings lack is missing to the GM whatever the notes say.
func _note_of(key: String) -> StringName:
	if not _is_gm:
		return &""
	if _shelf.any(func(entry: Dictionary) -> bool: return entry.key == key and entry.gone):
		return SessionFile.MISSING
	return _notes.get(key, &"")


## Whether the map `key` is gone from the GM's library (what Resume found, for the GM; the
## GM's holdings lack it, for everyone): nobody can get it and it cannot be set out.
func _is_gone(key: String) -> bool:
	if key == "":
		return false
	if _note_of(key) == SessionFile.MISSING:
		return true
	return _shelf.any(func(entry: Dictionary) -> bool: return entry.key == key and entry.gone)


## Remove from shelf on a missing map's line: off the shelf (with connect_network, through the
## session; the map on the table never goes).
func _on_remove_pressed(key: String) -> void:
	remove_requested.emit(key)
	if connect_network:
		NetworkManager.session.unshelve(key)


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
## Measured against the panel, never the body, which a sheet too tall for the screen stretches
## past the canvas (a full shelf with a changed map's actions under its selected row).
func _fit_side() -> void:
	if in_drawer or body == null or not is_inside_tree():
		return
	var rows_height := shelf_rows.get_combined_minimum_size().y
	var scrolling := shelf_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var needed := side.get_combined_minimum_size().y + (rows_height if scrolling else 0.0)
	var layout := body.get_parent() as Control
	var others := layout.get_combined_minimum_size().y - body.get_combined_minimum_size().y
	var fits := needed <= size.y - EDGE * 2.0 - others
	var mode := ScrollContainer.SCROLL_MODE_DISABLED if fits else ScrollContainer.SCROLL_MODE_AUTO
	if shelf_scroll.vertical_scroll_mode != mode:
		shelf_scroll.vertical_scroll_mode = mode
	var flags := Control.SIZE_SHRINK_BEGIN if fits else Control.SIZE_FILL
	if side.size_flags_vertical != flags:
		side.size_flags_vertical = flags


## The drawer's action follows its content: while the players and the shelf fit, the column is
## as tall as they are and the action sits right under the shelf, the rest of the height below
## it; when they run past the drawer, the column takes that height and scrolls, and the action
## pins to the foot. Measured against the panel (which the drawer sizes), never the layout
## inside it, which a column too tall for the drawer would stretch.
func _fit_drawer() -> void:
	if not in_drawer or column_scroll == null or not is_inside_tree():
		return
	var layout := column_scroll.get_parent() as Control
	var column := column_scroll.get_child(0) as Control
	var others := layout.get_combined_minimum_size().y - column_scroll.get_combined_minimum_size().y
	if not drawer_rest.visible:
		# The spacer and its separation come back when the column fits again.
		others += layout.get_theme_constant(&"separation")
	var fits := column.get_combined_minimum_size().y <= size.y - others
	var mode := ScrollContainer.SCROLL_MODE_DISABLED if fits else ScrollContainer.SCROLL_MODE_AUTO
	if column_scroll.vertical_scroll_mode != mode:
		column_scroll.vertical_scroll_mode = mode
	var flags := Control.SIZE_FILL if fits else Control.SIZE_EXPAND_FILL
	if column_scroll.size_flags_vertical != flags:
		column_scroll.size_flags_vertical = flags
	if drawer_rest.visible != fits:
		drawer_rest.visible = fits
	# The column's minimum can move and settle back within one frame of deferred updates (a
	# changes line rebuilt under another row while its flow takes its width), and the layout,
	# sorted in between, is then never told again: a fitting column a row short of its content
	# (488 of 540 px) is sorted once more.
	if fits and column_scroll.size.y + 0.5 < column.get_combined_minimum_size().y:
		(layout as Container).queue_sort()


## Scroll the drawer's column, or the room's shelf, to the selected shelf row and the changes or
## missing line under it when it scrolls, so the map the action names, and its own actions, are
## in view.
func _reveal_selected() -> void:
	var scroll := column_scroll if in_drawer else shelf_scroll
	if scroll == null or not is_inside_tree() or _selected == "":
		return
	if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return
	var key := _selected.validate_node_name()
	for prefix in ["Changes_", "Missing_"]:
		var line := shelf_rows.get_node_or_null(NodePath(prefix + key))
		if line is Control:
			scroll.ensure_control_visible(line)
	var row := shelf_rows.get_node_or_null(NodePath("Map_%s" % key))
	if row is Control:
		scroll.ensure_control_visible(row)


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
