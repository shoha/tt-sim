extends RefCounted

## Render-job probe (`call` op) for the session screens of the UI tour (jobs/ui_tour.json):
## what a host and a client see from the title's Host or Join to the room, and the way back
## from the table. Nothing here hosts or joins: NetworkManager.host_game() and join_game()
## are never called. Root's real entry points are used where they need no peer (the title's
## Join opens Root's join screen and its Back closes it; the pause menu's room row asks its
## own confirmation). What needs a peer is staged with sample data: the room screens with
## connect_network false, a room code in the real format through LobbyHost's own code path,
## sample player lists, and the host-only pause row shown on a solo pause. `action`:
## - `opening` (`open`, default true): the "Opening a room..." wait Root.host_session shows
##   over the title while hosting starts, on Root's own loading overlay; `open` false hides it
##   as Root does when the room opens.
## - `map_load` (`folder`, `open`, default true): Root's loading overlay as a map load shows
##   it mid-load, titled as Root titles it for that test level and held at a sample step;
##   nothing is loaded. Over the title or over a table, wherever the job is. `open` false
##   hides it as Root does when the load completes (the sky's reveal).
## - `host_room` (`folder`, optional): the host's room (LobbyHost) over the hidden title with
##   a sample code and three sample players. With `folder` that test level is the map to set
##   out, as after Host on the title; without, no map is picked yet, as after Return everyone
##   to the room.
## - `client_room`: the client's room, LobbyClient's waiting view, with the host and two more
##   sample players, and the local player marked (You) as LobbyClient marks it.
## - `close_room`: free the staged room and show the title again.
## - `join` (`open`, default true): press the title's Join Game, which opens Root's join
##   screen over the hidden title; `open` false presses the join screen's Back.
## - `pause_host`: on the open pause menu, show the host-only Return everyone to the room
##   row (a solo pause hides it).
## - `return_room`: press that row, which asks its confirmation. Dismiss it with
##   ui_primitives.gd `dismiss`; confirming would do nothing, since this is no hosted session.

const LOBBY_HOST_SCENE := preload("res://scenes/states/lobby/lobby_host.tscn")
const LOBBY_CLIENT_SCENE := preload("res://scenes/states/lobby/lobby_client.tscn")
## The staged room's node name under Root.
const STAGED := "UiTourRoom"
## The copy Root.host_session shows while hosting starts.
const OPENING_TEXT := "Opening a room..."
## The step a staged map load is held at: a share of the bar and the loader's own caption.
const MAP_LOAD_PROGRESS := 0.35
const MAP_LOAD_STATUS := "Loading token models..."
## A Steam lobby id of the usual magnitude, for a room code in the real format.
const SAMPLE_LOBBY_ID := 109775244321098765
const SAMPLE_PLAYERS: Array[String] = ["Marigold", "Ranger", "Starling"]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"opening":
			return _opening(base, bool(step.get("open", true)))
		"map_load":
			return _map_load(base, String(step.get("folder", "")), bool(step.get("open", true)))
		"host_room":
			return _host_room(base, String(step.get("folder", "")))
		"client_room":
			return _client_room(base)
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


static func _host_room(base: Node, folder: String) -> String:
	var level: LevelData = null
	if not folder.is_empty():
		level = LevelManager.load_level_folder(folder, false)
		if level == null:
			return "no level %s" % folder
	var room := LOBBY_HOST_SCENE.instantiate() as LobbyHost
	room.connect_network = false
	_stage(base, room)
	if level:
		room.set_level(level)
	room._on_room_code_received(LobbyCode.encode(SAMPLE_LOBBY_ID))
	room.player_list.clear()
	room.player_list.add_item("%s (Host)" % NetworkManager.get_player_name())
	for player in SAMPLE_PLAYERS:
		room.player_list.add_item(player)
	room.status_label.text = LobbyHost.players_connected_text(SAMPLE_PLAYERS.size() + 1)
	return "host room on %s, code %s" % [room.level_name.text, room.room_code_value.text]


static func _client_room(base: Node) -> String:
	var room := LOBBY_CLIENT_SCENE.instantiate() as LobbyClient
	room.connect_network = false
	_stage(base, room)
	# The waiting view, opened as Root's room opens it on a connection the join screen
	# already announced.
	room._show_connected_state(false)
	room.player_list.clear()
	room.player_list.add_item("%s (Host)" % SAMPLE_PLAYERS[0])
	for player in SAMPLE_PLAYERS.slice(1):
		room.player_list.add_item(player)
	room.player_list.add_item("%s (You)" % NetworkManager.get_player_name())
	return "client room, %d players" % room.player_list.item_count


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
