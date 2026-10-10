extends RefCounted

## Render-job probe (`call` op) for the session screens of the UI tour (jobs/ui_tour.json):
## what a host and a client see from the title's Host or Join to the room, and the way back
## from the table. Nothing here hosts or joins: NetworkManager.host_game() and join_game()
## are never called. Root's real entry points are used where they need no peer (the title's
## Join opens Root's join screen and its Back closes it; the pause menu's room row asks its
## own confirmation). What needs a peer is staged with sample data: the room (RoomScreen, its
## RoomPanel with connect_network false) fed a sample session summary (a room code in the real
## format, four players, a shelf of three maps: the tour's test level with its thumbnail and two
## sample maps with none, showing the thumbnail well's initial), the room drawer over the table
## fed the same summary, and the host-only pause row shown on a solo pause. `action`:
## - `opening` (`open`, default true): the "Opening a room..." wait Root.host_session shows
##   over the title while hosting starts, on Root's own loading overlay; `open` false hides it
##   as Root does when the room opens.
## - `map_load` (`folder`, `open`, default true): Root's loading overlay as a map load shows
##   it mid-load, titled as Root titles it for that test level and held at a sample step;
##   nothing is loaded. Over the title or over a table, wherever the job is. `open` false
##   hides it as Root does when the load completes (the sky's reveal).
## - `host_room` (`folder`, `shelf`, default true): the GM's room over the hidden title with
##   the sample players. With `shelf` the shelf holds `folder` (the tour's test level) and the
##   two sample maps, `folder` selected for Set out, as after Host with this map; `shelf`
##   false is a room with no map at all, as after Host a session.
## - `client_room` (`folder`): a player's room with the same players and shelf, nothing
##   selected, the local player one of them.
## - `drawer` (`folder`, `open`, default true): over a table, the room drawer open as the GM
##   sees it, `folder` on the table and the next sample map selected (Move the table here
##   live); `open` false closes it.
## - `close_room`: free the staged room and show the title again.
## - `join` (`open`, default true): press the title's Join Game, which opens Root's join
##   screen over the hidden title; `open` false presses the join screen's Back.
## - `pause_host`: on the open pause menu, show the host-only Return everyone to the room
##   row (a solo pause hides it).
## - `return_room`: press that row, which asks its confirmation. Dismiss it with
##   ui_primitives.gd `dismiss`; confirming would do nothing, since this is no hosted session.

## The staged room's node name under Root.
const STAGED := "UiTourRoom"
## The copy Root.host_session shows while hosting starts.
const OPENING_TEXT := "Opening a room..."
## The step a staged map load is held at: a share of the bar and the loader's own caption.
const MAP_LOAD_PROGRESS := 0.35
const MAP_LOAD_STATUS := "Loading token models..."
## A Steam lobby id of the usual magnitude, for a room code in the real format.
const SAMPLE_LOBBY_ID := 109775244321098765
## Session ids and names: the GM first, the local player of client_room last.
const SAMPLE_GM := "enet-1"
const SAMPLE_PLAYERS := {"enet-ranger": "Ranger", "enet-starling": "Starling", "enet-wren": "Wren"}
const SAMPLE_LOCAL_PLAYER := "enet-wren"
## Sample shelf maps after the test level, with no thumbnail anywhere.
const SAMPLE_MAPS := {"_ui_tour_sample_mill": "Old Mill", "_ui_tour_sample_fen": "Fen Crossing"}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"opening":
			return _opening(base, bool(step.get("open", true)))
		"map_load":
			return _map_load(base, String(step.get("folder", "")), bool(step.get("open", true)))
		"host_room":
			return _host_room(base, String(step.get("folder", "")), bool(step.get("shelf", true)))
		"client_room":
			return _client_room(base, String(step.get("folder", "")))
		"drawer":
			return _drawer(base, String(step.get("folder", "")), bool(step.get("open", true)))
		"close_room":
			return _close_room(base)
		"join":
			return _join(base, bool(step.get("open", true)))
		"pause_host":
			return _pause_host(base)
		"return_room":
			return _return_room(base)
	return "unknown action %s" % step.get("action", "")


static func _opening(base: Node, open: bool) -> String:
	var overlay := base.get("_loading_overlay") as LoadingOverlay
	if overlay == null:
		return "no loading overlay"
	if open:
		overlay.show_indeterminate(OPENING_TEXT)
		return "showing %s" % OPENING_TEXT
	overlay.hide_loading()
	return "room wait hidden"


static func _map_load(base: Node, folder: String, open: bool) -> String:
	var overlay := base.get("_loading_overlay") as LoadingOverlay
	if overlay == null:
		return "no loading overlay"
	if not open:
		overlay.hide_loading()
		return "map load hidden"
	var level: LevelData = null
	if not folder.is_empty():
		level = LevelManager.load_level_folder(folder, false)
	var title := LoadingOverlay.setting_out_text(level)
	overlay.show_loading(title)
	overlay.set_progress(MAP_LOAD_PROGRESS, MAP_LOAD_STATUS)
	return "showing %s at %.2f" % [title, MAP_LOAD_PROGRESS]


static func _show_title(base: Node, shown: bool) -> void:
	var title: CanvasLayer = base.get("_title_screen")
	if title:
		title.visible = shown


## Add a room screen under Root in place of the title, as Root's ROOM state would show it.
static func _stage(base: Node, room: Node) -> void:
	room.name = STAGED
	_show_title(base, false)
	base.add_child(room)


## A sample session summary (SessionChannel.summary()'s shape): the GM and SAMPLE_PLAYERS
## here, and with `with_shelf` the test level `folder` and SAMPLE_MAPS on the shelf, `table` on
## the table. Everyone holds the test level, three of four the first sample, the GM alone the
## second.
static func _summary(folder: String, with_shelf: bool, table: String) -> Dictionary:
	var shelf: Array = []
	if with_shelf:
		var level := LevelManager.load_level_folder(folder, false) if folder != "" else null
		var level_name := level.level_name if level else folder
		shelf.append({"folder": folder, "map_path": "", "hashes": {}, "name": level_name})
		for key: String in SAMPLE_MAPS:
			shelf.append({"folder": key, "map_path": "", "hashes": {}, "name": SAMPLE_MAPS[key]})
	var keys: Array = shelf.map(func(ref: Dictionary) -> String: return ref.folder)
	var players := {SAMPLE_GM: {"name": "Marigold", "peer_id": 1}}
	var holdings := {SAMPLE_GM: keys}
	var peer := 2
	for id: String in SAMPLE_PLAYERS:
		players[id] = {"name": SAMPLE_PLAYERS[id], "peer_id": peer}
		holdings[id] = keys.slice(0, 1 if id == "enet-starling" else 2)
		peer += 1
	return {
		"open": table == "", "table": table, "shelf": shelf, "players": players, "holdings": holdings
	}


## Stage the room as `local_id` sees it.
static func _room(base: Node, summary: Dictionary, local_id: String) -> RoomScreen:
	var room := RoomScreen.new()
	room.connect_network = false
	_stage(base, room)
	room.panel.set_code(LobbyCode.encode(SAMPLE_LOBBY_ID))
	room.panel.show_session(summary, local_id, local_id == SAMPLE_GM)
	return room


static func _host_room(base: Node, folder: String, with_shelf: bool) -> String:
	if with_shelf and LevelManager.load_level_folder(folder, false) == null:
		return "no level %s" % folder
	var room := _room(base, _summary(folder, with_shelf, ""), SAMPLE_GM)
	if with_shelf:
		room.panel.select(folder)
	var panel := room.panel
	return "GM's room: %s; %d maps, %s selected" % [
		panel.title_label.text, panel.shelf_rows.get_child_count(), panel.selected_key()
	]


static func _client_room(base: Node, folder: String) -> String:
	var room := _room(base, _summary(folder, true, ""), SAMPLE_LOCAL_PLAYER)
	return "player's room: %s, %d players" % [
		room.panel.title_label.text, room.panel.player_rows.get_child_count()
	]


static func _drawer(base: Node, folder: String, open: bool) -> String:
	var map: GameMap = base.get("_game_map")
	var menu: Node = map.gameplay_menu.get_node_or_null("GameplayMenu") if map else null
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer == null:
		return "no room drawer (not at a table)"
	if not open:
		drawer.close()
		return "room drawer closed"
	drawer.visible = true
	drawer.panel.set_code(LobbyCode.encode(SAMPLE_LOBBY_ID))
	drawer.panel.show_session(_summary(folder, true, folder), SAMPLE_GM, true)
	drawer.panel.select(SAMPLE_MAPS.keys()[0])
	drawer.open()
	return "room drawer open, %s on the table" % folder


static func _close_room(base: Node) -> String:
	var room := base.get_node_or_null(STAGED)
	if room:
		base.remove_child(room)
		room.queue_free()
	_show_title(base, true)
	return "room closed" if room else "no staged room"


static func _join(base: Node, open: bool) -> String:
	if open:
		var title: CanvasLayer = base.get("_title_screen")
		var button: Button = title.get("join_button") if title else null
		if button == null:
			return "no title Join Game button"
		button.pressed.emit()
	else:
		var screen: Variant = base.get("_join_screen")
		if not is_instance_valid(screen):
			return "no join screen"
		(screen as LobbyClient).leave_button.pressed.emit()
	var shown: Variant = base.get("_join_screen")
	return "join screen %s" % ("open" if is_instance_valid(shown) else "closed")


static func _pause_overlay(base: Node) -> PauseOverlay:
	var overlay: Variant = base.get("_pause_overlay")
	return overlay as PauseOverlay if is_instance_valid(overlay) else null


static func _pause_host(base: Node) -> String:
	var pause := _pause_overlay(base)
	if pause == null:
		return "the pause menu is not open"
	pause.room_button.visible = true
	pause.rebuild_focus_trap()
	return "pause menu with %s" % pause.room_button.text


static func _return_room(base: Node) -> String:
	var pause := _pause_overlay(base)
	if pause == null or not pause.room_button.visible:
		return "no Return everyone to the room row"
	pause.room_button.pressed.emit()
	return "asked to return everyone to the room"
