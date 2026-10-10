extends RefCounted

## Render-job probe for the table moves (TableMover) and the shelf rows' Save into map and
## Discard changes: saves the open authoring map as a _table_moves_ test level, then on the
## table stages the move's notice as the GM sees it (with Stay here) and as a player does
## (naming the GM), the two confirms and Save into map's error, and the room and the room
## drawer with changed maps on the shelf. Used by jobs/table_moves.json. Staged: the table is
## played solo; a confirm is opened by TableMover itself with this game standing as a session's
## host for the moment (the connection state set, a shelf of one), and the room and the drawer
## come from ui_room.gd's staging, fed the changed maps.
##
## Actions (step "action"):
##   save        {"folder", "name"}: the authoring map saved as that level (a _table_moves_
##               folder)
##   window      {"size": "WxH"}: the window at that size, Interface size Auto for the run
##   notice      {"kind": "map", "room", "reset" or "reload"; "to": the map's name; "mover":
##               the GM's name for a player's chip, "" (default) for the GM's own; "seconds"}
##   dismiss     the notice's own fade-out, as when its count ends (capture it at once)
##   confirm     {"which": "save" or "discard", "to": the map's name, "folder": a saved test
##               level}: the confirm TableMover opens from that map's shelf row
##   save_failed {"to"}: Save into map's error when the terrain file could not be written
##   room        {"folder", "select": "mill" or "fen", "full": false}: the GM's room
##               (ui_room.gd host_room) with Old Mill changed (Save into map offered) and Fen
##               Crossing changed (no level folder here: Discard changes and why), that map
##               selected; `full` puts FULL_SHELF's two more maps on the shelf (five)
##   drawer      {"folder", "select": "table" or "mill", "full": false}: the room drawer over
##               the table (ui_room.gd drawer), the table and Old Mill changed, that row selected
##               (a row click, which never moves the table) with its actions under it; `full`
##               as for the room
##   close       the notice, the confirms, the staged room and drawer taken away; the session
##               staging undone
##   cleanup     deletes every _table_moves_ level

const PREFIX := "_table_moves_"
const UI_ROOM := preload("res://tools/render_jobs/probes/ui_room.gd")
## The two maps a full shelf adds after ui_room.gd's three, with no thumbnail anywhere.
const FULL_SHELF := {
	"_ui_tour_sample_tarn": "Heron Tarn",
	"_ui_tour_sample_keep": "The Broken Keep",
}
const KINDS := {
	"map": TableMoveNotice.Kind.MAP,
	"room": TableMoveNotice.Kind.ROOM,
	"reset": TableMoveNotice.Kind.RESET,
	"reload": TableMoveNotice.Kind.RELOAD,
}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, String(step.get("folder", PREFIX + "table")), step)
		"cleanup":
			return _cleanup()
		"window":
			return _window(base, step.get("size", "1920x1080"))
		"save_failed":
			var text := TableMover.save_error(String(step.get("to", "Old Mill")), TableMover.WHY_DOCUMENT)
			UIManager.show_error(text)
			return "error: %s" % text
		"room":
			return _room(base, String(step.get("folder", "")), step)
		"drawer":
			return _drawer(base, String(step.get("folder", "")), step)
	var mover := base.get("_table_mover") as TableMover
	if mover == null:
		return "no TableMover"
	match String(step.get("action", "")):
		"notice":
			var kind: TableMoveNotice.Kind = KINDS.get(String(step.get("kind", "map")), 0)
			var to := String(step.get("to", "Fen Crossing"))
			var mover_name := String(step.get("mover", ""))
			var seconds := float(step.get("seconds", TableMover.NOTICE_S))
			mover.call("_show_notice", kind, to, seconds, mover_name)
			var notice := mover.get_node_or_null("TableMoveNotice") as TableMoveNotice
			return "notice: %s" % (notice.shown_text() if notice else "none")
		"dismiss":
			var shown := mover.get_node_or_null("TableMoveNotice") as TableMoveNotice
			if shown == null:
				return "no notice"
			shown.dismiss()
			# Its fade is 0.15 s, shorter than a capture's frame wait: hold the chip halfway
			# (its fade tween, bound to the notice, stops with it) so the frame shows it going.
			shown.process_mode = Node.PROCESS_MODE_DISABLED
			var chip := shown.find_child("Chip", true, false) as Control
			chip.modulate.a = float(step.get("alpha", 0.5))
			return "notice fading out, held at %.2f" % chip.modulate.a
		"confirm":
			return _confirm(mover, step)
		"close":
			return _close(base, mover)
	return "unknown action"


## TableMover's own confirm for the map `to` in the saved level `folder`, with this game a
## session's host for the moment and that map on its shelf with a kept state.
static func _confirm(mover: TableMover, step: Dictionary) -> String:
	NetworkManager.session.reset()
	NetworkManager.set("_connection_state", NetworkManager.ConnectionState.HOSTING)
	var level := {"level_folder": String(step.get("folder", "")), "level_name": step.get("to", "")}
	var key := NetworkManager.session.shelve(level)
	mover.states.store(key, {"placements": [], "op_log": []})
	var which := String(step.get("which", "save"))
	var dialog := mover.ask_save(key) if which == "save" else mover.ask_discard(key)
	if dialog == null:
		return "no confirm for %s (%s)" % [key, which]
	return "%s: %s / %s" % [which, dialog.title_label.text, dialog.message_label.text]


static func _close(base: Node, mover: TableMover) -> String:
	mover.cancel()
	# A notice held mid-fade (dismiss) never finishes its fade by itself.
	var held := mover.get_node_or_null("TableMoveNotice")
	if held:
		held.queue_free()
	for child in base.get_tree().root.get_children():
		if child is ConfirmationDialogUI:
			child.queue_free()
	mover.states.clear()
	if NetworkManager.connection_state == NetworkManager.ConnectionState.HOSTING:
		NetworkManager.set("_connection_state", NetworkManager.ConnectionState.OFFLINE)
		NetworkManager.session.reset()
	if base.get_node_or_null(UI_ROOM.STAGED):
		UI_ROOM.run(base, {"action": "close_room"})
	UI_ROOM.run(base, {"action": "drawer", "open": false})
	return "closed"


## The GM's room with changed maps: Old Mill with Save into map offered, Fen Crossing with no
## level folder here (Discard changes only); `select` picks which one's actions show.
static func _room(base: Node, folder: String, step: Dictionary) -> String:
	var staged := UI_ROOM.run(base, {"action": "host_room", "folder": folder, "select": false})
	var room := base.get_node_or_null(UI_ROOM.STAGED) as RoomScreen
	if room == null:
		return "no room: %s" % staged
	if bool(step.get("full", false)):
		_fill_shelf(room.panel, "")
	var keys: Array = UI_ROOM.SAMPLE_MAPS.keys()
	room.panel.show_changes({keys[0]: true, keys[1]: false})
	room.panel.select(keys[0] if String(step.get("select", "mill")) == "mill" else keys[1])
	return "room, %d maps, changed %s; %s selected" % [
		room.panel.shelf_rows.get_child_count(), str(keys), room.panel.selected_key()
	]


## The room drawer over the table with the table and Old Mill changed, the table's row or Old
## Mill's selected by a row click (its actions under it), as the GM does it.
static func _drawer(base: Node, folder: String, step: Dictionary) -> String:
	var staged := UI_ROOM.run(base, {"action": "drawer", "folder": folder})
	var map: GameMap = base.get("_game_map")
	var menu: Node = map.gameplay_menu.get_node_or_null("GameplayMenu") if map else null
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer == null:
		return "no drawer: %s" % staged
	if bool(step.get("full", false)):
		_fill_shelf(drawer.panel, folder)
	var mill: String = UI_ROOM.SAMPLE_MAPS.keys()[0]
	drawer.panel.show_changes({folder: true, mill: true})
	var key := mill if String(step.get("select", "table")) == "mill" else folder
	var row := drawer.panel.shelf_rows.get_node_or_null("Map_%s" % key.validate_node_name())
	var moved := [false]
	var on_move := func(_key: String) -> void: moved[0] = true
	drawer.panel.move_table_requested.connect(on_move)
	if row is Button:
		(row as Button).pressed.emit()
	drawer.panel.move_table_requested.disconnect(on_move)
	return "drawer, %s and %s changed, %s selected by its row; the table moved: %s" % [
		folder, mill, drawer.panel.selected_key(), str(moved[0])
	]


## Show `panel` the GM's session with FULL_SHELF after ui_room.gd's three maps: the test level
## (`table` on the table, "" in the room), Old Mill, Fen Crossing, Heron Tarn, The Broken Keep.
static func _fill_shelf(panel: RoomPanel, table: String) -> void:
	var shelf: Array = []
	var holdings := {}
	for row: Node in panel.shelf_rows.get_children():
		if row is Button:
			var key := String(row.name).trim_prefix("Map_")
			var label := row.find_child("Name", true, false) as Label
			shelf.append({"folder": key, "map_path": "", "hashes": {}, "name": label.text})
	for key: String in FULL_SHELF:
		shelf.append({"folder": key, "map_path": "", "hashes": {}, "name": FULL_SHELF[key]})
	var keys: Array = shelf.map(func(ref: Dictionary) -> String: return ref.folder)
	var players := {UI_ROOM.SAMPLE_GM: {"name": "Marigold", "peer_id": 1}}
	holdings[UI_ROOM.SAMPLE_GM] = keys
	var peer := 2
	for id: String in UI_ROOM.SAMPLE_PLAYERS:
		players[id] = {"name": UI_ROOM.SAMPLE_PLAYERS[id], "peer_id": peer}
		holdings[id] = keys.slice(0, 2)
		peer += 1
	var summary := {
		"open": table == "",
		"table": table,
		"shelf": shelf,
		"players": players,
		"holdings": holdings,
	}
	panel.show_session(summary, UI_ROOM.SAMPLE_GM, true)


## The window at `size` ("WxH") with the Interface size at Auto for the run, as
## ui_primitives.gd's window step sets it (never saved).
static func _window(base: Node, size: Variant) -> String:
	var parts := String(size).split("x")
	var window := base.get_window()
	window.size = Vector2i(parts[0].to_int(), parts[1].to_int())
	UIManager.set("_interface_size", InterfaceSize.AUTO)
	UIManager.apply_interface_size()
	return "window %s, content scale %.2f" % [str(window.size), window.content_scale_factor]


static func _save(base: Node, folder: String, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = String(step.get("name", "Mossy Hollow"))
	saved.level_folder = folder
	ctrl.call("_sync_document")
	return "saved %s: %s" % [folder, str(AuthoringController.write_level(saved, ctrl.document, null))]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
