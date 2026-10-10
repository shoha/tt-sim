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
##   room        {"folder", "select": "mill" or "fen"}: the GM's room (ui_room.gd host_room)
##               with Old Mill changed (Save into map offered) and Fen Crossing changed (no level
##               folder here: Discard changes only), that map selected
##   drawer      {"folder"}: the room drawer over the table (ui_room.gd drawer), the table and
##               Old Mill changed, the table's row selected with its actions under it
##   close       the notice, the confirms, the staged room and drawer taken away; the session
##               staging undone
##   cleanup     deletes every _table_moves_ level

const PREFIX := "_table_moves_"
const UI_ROOM := preload("res://tools/render_jobs/probes/ui_room.gd")
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
			return _room(base, String(step.get("folder", "")), String(step.get("select", "mill")))
		"drawer":
			return _drawer(base, String(step.get("folder", "")))
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
			return "notice fading out (%.2f s left)" % shown.seconds_left()
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
static func _room(base: Node, folder: String, select: String) -> String:
	var staged := UI_ROOM.run(base, {"action": "host_room", "folder": folder, "select": false})
	var room := base.get_node_or_null(UI_ROOM.STAGED) as RoomScreen
	if room == null:
		return "no room: %s" % staged
	var keys: Array = UI_ROOM.SAMPLE_MAPS.keys()
	room.panel.show_changes({keys[0]: true, keys[1]: false})
	room.panel.select(keys[0] if select == "mill" else keys[1])
	return "room, changed %s; %s selected" % [str(keys), room.panel.selected_key()]


## The room drawer over the table with the table and Old Mill changed, the table's row
## selected (its actions under it).
static func _drawer(base: Node, folder: String) -> String:
	var staged := UI_ROOM.run(base, {"action": "drawer", "folder": folder})
	var map: GameMap = base.get("_game_map")
	var menu: Node = map.gameplay_menu.get_node_or_null("GameplayMenu") if map else null
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer == null:
		return "no drawer: %s" % staged
	var mill: String = UI_ROOM.SAMPLE_MAPS.keys()[0]
	drawer.panel.show_changes({folder: true, mill: true})
	drawer.panel.select(folder)
	return "drawer, %s and %s changed, %s selected" % [folder, mill, drawer.panel.selected_key()]


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
