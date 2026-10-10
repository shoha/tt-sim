extends RefCounted

## Render-job probe (`call` op) for the session screens of the UI tour (jobs/ui_tour.json):
## what a host and a client see from the title's Host or Join to the room, and the way back
## from the table. Nothing here hosts or joins: NetworkManager.host_game() and join_game()
## are never called. Root's real entry points are used where they need no peer (the pause
## menu's room row asks its own confirmation; the title's card is ui_play_together.gd's). What
## needs a peer is staged with sample data: the room (RoomScreen, its
## RoomPanel with connect_network false) fed a sample session summary (a room code in the real
## format, four players, a shelf of three maps: the tour's test level with the thumbnail
## `thumbnail` saved for it and two sample maps with none, showing their painted placeholders),
## the room drawer over the table fed the same summary, and the host-only pause row shown on a
## solo pause. `action`:
## - `thumbnail` (`folder`): save the authoring map on screen as `folder`'s thumbnail, as a
##   save from authoring does, so the test map shows a real picture in the library and the
##   room. Run it while authoring the map, after ui_primitives.gd `save`.
## - `opening` (`open`, default true; `cancel`, default false): the "Opening a room..." wait
##   SessionFlow.host_session shows over the title while hosting starts, on Root's loading
##   overlay (LevelFlow's), its step caption in Cancel's band; `cancel` offers its Cancel at
##   once rather than after LoadingOverlay.CANCEL_AFTER_S. `open` false hides it as
##   SessionFlow does when the room opens.
## - `map_load` (`folder`, `open`, default true): Root's loading overlay as a map load shows
##   it mid-load, titled as Root titles it for that test level and held at a sample step;
##   nothing is loaded. Over the title or over a table, wherever the job is. `open` false
##   hides it as Root does when the load completes (the sky's reveal).
## - `host_room` (`folder`, `shelf`, default true; `select`, default true; `long`, default
##   false): the GM's room over the hidden title with the sample players. With `shelf` the
##   shelf holds `folder` (the tour's test level) and the two sample maps, `folder` selected
##   for Set out, as after Host with this map (`select` false: nothing selected yet); `shelf`
##   false is a room with no map at all, as after Host a session. `long` names the GM with
##   LONG_GM_NAME (24 characters) and the second sample map LONG_MAP_NAME, and selects it.
##   `notes` stages what Resume found: Old Mill's files changed since the session was kept and
##   Fen Crossing missing from the library (RoomPanel.show_notes()), Old Mill selected
##   (`missing`: Fen Crossing, with its Remove from shelf); with `notes` the folder may be "",
##   the resumed session's shelf alone: Old Mill and 2 more maps (RESUMED_MAPS).
## - `client_room` (`folder`; `shelf`, default true; `select`, default 0): a player's room
##   with the same players and shelf, the local player one of them, the SAMPLE_MAPS entry at
##   index `select` selected to look at (their own download state first: 0 is Old Mill, which
##   they have, 1 Fen Crossing, which they are getting at 40%; -1 selects nothing, as a player
##   who just joined sees it). `shelf` false is a room with no map yet.
## - `add_map`: on the staged room, the GM's Add a map picker over the library (closed with
##   the room by `close_room`).
## - `end_confirm`: on the staged GM's room, End session's confirmation (dismiss it with
##   ui_primitives.gd `dismiss`).
## - `drawer` (`folder`, `open`, default true; `player`, default false; `long`, default
##   false): over a table, the room drawer open as the GM sees it, `folder` on the table and
##   the next sample map selected (Move the table to Old Mill live); `open` false closes it.
##   `player` shows it as the local player sees it, opened on the map on the table; `long`
##   gives the GM and the second sample map their long names and selects that map.
## - `close_room`: free the staged room and show the title again.
## - `pause_host`: on the open pause menu, show the host-only Return everyone to the room
##   row (a solo pause hides it).
## - `return_room`: press that row, which asks its confirmation. Dismiss it with
##   ui_primitives.gd `dismiss`; confirming would do nothing, since this is no hosted session.

## The staged room's node name under Root.
const STAGED := "UiTourRoom"
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
## The third map of the resumed session (`notes`): Old Mill and 2 more maps, as ui_play_together
## names it on the title's Resume.
const RESUMED_MAPS := {"_ui_tour_sample_willow": "Willow Green"}
## Long real copy (T6): a 24-character GM name and a long map name.
const LONG_GM_NAME := "Marigold Thistlewood-Ash"
const LONG_MAP_NAME := "The Drowned Lanterns of Upper Fenwick Mire"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"thumbnail":
			return _thumbnail(base, String(step.get("folder", "")))
		"opening":
			return _opening(base, bool(step.get("open", true)), bool(step.get("cancel", false)))
		"map_load":
			return _map_load(base, String(step.get("folder", "")), bool(step.get("open", true)))
		"host_room":
			return _host_room(base, String(step.get("folder", "")), step)
		"client_room":
			return _client_room(base, String(step.get("folder", "")), step)
		"add_map":
			return _add_map(base)
		"end_confirm":
			return _end_confirm(base)
		"drawer":
			return _drawer(base, String(step.get("folder", "")), step)
		"close_room":
			return _close_room(base)
		"pause_host":
			return _pause_host(base)
		"return_room":
			return _return_room(base)
	return "unknown action %s" % step.get("action", "")


static func _thumbnail(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var level := LevelManager.load_level_folder(folder, false) if folder != "" else null
	if ctrl == null or level == null:
		return "no authoring controller, or no level %s" % folder
	var image := ctrl.capture_thumbnail()
	if image == null:
		return "no picture of the map"
	LevelManager.save_thumbnail(level, image)
	return "thumbnail saved for %s" % folder


## Root's loading overlay (LevelFlow's).
static func _overlay(base: Node) -> LoadingOverlay:
	var flow := base.get("_level_flow") as LevelFlow
	return flow.loading_overlay if flow else null


static func _opening(base: Node, open: bool, cancel: bool) -> String:
	var overlay := _overlay(base)
	if overlay == null:
		return "no loading overlay"
	if open:
		overlay.show_indeterminate(RoomScreen.OPENING, true, RoomScreen.OPENING_STEP)
		if cancel:
			overlay.offer_cancel()
		var shown := "Cancel" if cancel else RoomScreen.OPENING_STEP
		return "showing %s with %s" % [RoomScreen.OPENING, shown]
	overlay.hide_loading()
	return "room wait hidden"


static func _map_load(base: Node, folder: String, open: bool) -> String:
	var overlay := _overlay(base)
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
## second. The players fetch what they lack in the background ("progress"): Starling is
## getting the first sample, Wren the second, and the others wait their turn for it. `long`
## gives the GM and the second sample map their long names.
static func _summary(
	folder: String, with_shelf: bool, table: String, long := false, resumed := false
) -> Dictionary:
	var shelf: Array = []
	if with_shelf:
		if folder != "":
			var level := LevelManager.load_level_folder(folder, false)
			var level_name := level.level_name if level else folder
			shelf.append({"folder": folder, "map_path": "", "hashes": {}, "name": level_name})
		var maps := SAMPLE_MAPS.duplicate()
		if resumed:
			maps.merge(RESUMED_MAPS)
		for key: String in maps:
			var map_name: String = maps[key]
			if long and key == SAMPLE_MAPS.keys()[1]:
				map_name = LONG_MAP_NAME
			shelf.append({"folder": key, "map_path": "", "hashes": {}, "name": map_name})
	var keys: Array = shelf.map(func(ref: Dictionary) -> String: return ref.folder)
	var players := {SAMPLE_GM: {"name": LONG_GM_NAME if long else "Marigold", "peer_id": 1}}
	var holdings := {SAMPLE_GM: keys}
	var peer := 2
	for id: String in SAMPLE_PLAYERS:
		players[id] = {"name": SAMPLE_PLAYERS[id], "peer_id": peer}
		holdings[id] = keys.slice(0, 1 if id == "enet-starling" else 2)
		peer += 1
	var progress := {}
	if with_shelf:
		var mill: String = SAMPLE_MAPS.keys()[0]
		var fen: String = SAMPLE_MAPS.keys()[1]
		progress = {
			"enet-starling": {mill: 72, fen: 0},
			"enet-wren": {fen: 40},
			"enet-ranger": {fen: 0},
		}
	return {
		"open": table == "",
		"table": table,
		"shelf": shelf,
		"players": players,
		"holdings": holdings,
		"progress": progress,
	}


## Stage the room as `local_id` sees it.
static func _room(base: Node, summary: Dictionary, local_id: String) -> RoomScreen:
	var room := RoomScreen.new()
	room.connect_network = false
	_stage(base, room)
	room.panel.set_code(LobbyCode.encode(SAMPLE_LOBBY_ID))
	room.panel.show_session(summary, local_id, local_id == SAMPLE_GM)
	return room


static func _host_room(base: Node, folder: String, step: Dictionary) -> String:
	var with_shelf := bool(step.get("shelf", true))
	var long := bool(step.get("long", false))
	var notes := bool(step.get("notes", false))
	# With `notes` the test level may be left out (folder ""): the resumed session's three
	# sample maps carry them.
	var needs_level := with_shelf and not (notes and folder == "")
	if needs_level and LevelManager.load_level_folder(folder, false) == null:
		return "no level %s" % folder
	var room := _room(base, _summary(folder, with_shelf, "", long, notes), SAMPLE_GM)
	var keys: Array = SAMPLE_MAPS.keys()
	if long:
		room.panel.select(keys[1])
	elif notes:
		room.panel.select(keys[1] if bool(step.get("missing", false)) else keys[0])
	elif with_shelf and bool(step.get("select", true)):
		room.panel.select(folder)
	var panel := room.panel
	if notes:
		panel.show_notes({keys[0]: SessionFile.CHANGED, keys[1]: SessionFile.MISSING})
	return "GM's room: %s; %d maps, %s selected; action %s" % [
		panel.title_label.text,
		panel.shelf_rows.get_child_count(),
		panel.selected_key(),
		panel.action_button.text if panel.action_button.visible else "none",
	]


static func _client_room(base: Node, folder: String, step: Dictionary) -> String:
	var with_shelf := bool(step.get("shelf", true))
	var room := _room(base, _summary(folder, with_shelf, ""), SAMPLE_LOCAL_PLAYER)
	var index := int(step.get("select", 0))
	if with_shelf and index >= 0:
		room.panel.select(SAMPLE_MAPS.keys()[index])
	return "player's room: %s, %d players, %s: %s" % [
		room.panel.title_label.text,
		room.panel.player_rows.get_child_count(),
		room.panel.map_name_label.text,
		room.panel.readiness_label.text,
	]


static func _staged_panel(base: Node) -> RoomPanel:
	var room := base.get_node_or_null(STAGED) as RoomScreen
	return room.panel if room else null


static func _add_map(base: Node) -> String:
	var panel := _staged_panel(base)
	if panel == null:
		return "no staged room"
	panel.open_map_picker()
	return "Add a map picker open"


static func _end_confirm(base: Node) -> String:
	var panel := _staged_panel(base)
	if panel == null:
		return "no staged room"
	panel.ask_to_leave()
	return "asked to end the session"


static func _drawer(base: Node, folder: String, step: Dictionary) -> String:
	var map: GameMap = base.get("_game_map")
	var menu: Node = map.gameplay_menu.get_node_or_null("GameplayMenu") if map else null
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer == null:
		return "no room drawer (not at a table)"
	if not bool(step.get("open", true)):
		drawer.close()
		return "room drawer closed"
	var player := bool(step.get("player", false))
	var long := bool(step.get("long", false))
	drawer.visible = true
	drawer.panel.set_code(LobbyCode.encode(SAMPLE_LOBBY_ID))
	var local_id := SAMPLE_LOCAL_PLAYER if player else SAMPLE_GM
	drawer.panel.show_session(_summary(folder, true, folder, long), local_id, not player)
	# The drawer keeps its selection between openings; a player's is staged as on their first.
	if long:
		drawer.panel.select(SAMPLE_MAPS.keys()[1])
	else:
		drawer.panel.select(folder if player else SAMPLE_MAPS.keys()[0])
	drawer.open()
	var action := drawer.panel.action_button
	return "room drawer open as %s, %s on the table; %s" % [
		"a player" if player else "the GM",
		folder,
		action.text if action.visible else drawer.panel.hint_label.text,
	]


static func _close_room(base: Node) -> String:
	var room := base.get_node_or_null(STAGED)
	if room:
		base.remove_child(room)
		room.queue_free()
	_show_title(base, true)
	return "room closed" if room else "no staged room"


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
