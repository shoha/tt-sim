extends "res://tests/net/enet_late_joiner.gd"

## ENet scenario for the session room (SessionChannel, Root.State.ROOM): a hosted session
## goes table A > room > table B on one connection, while peers join in the room at the
## start, in the room between tables, and at a table. Ported from the session-room probe
## (branch probe/session-room); the party (avatars travelling between maps) is a later card,
## so each table here has its own token and table A's must not reach table B.
##
## Five processes, one per role, reuse enet_late_joiner.gd's boot, ENet setup and
## rendezvous files. Both tables are the shipped res:// map (nothing downloads) under two
## level folders, so the shelf and the table pointer tell them apart.
##
## host: opens the session in the room; once client and client2 are in the room, sets out
##   table A and places token A; once both see it, returns everyone to the room (checks the
##   room on its side: no tokens, nothing served, the session open); once client, client2 and
##   client3 are in the room, sets out table B and places token B; finishes when every client
##   has reported and client has left, checking one peer object and room code throughout,
##   the shelf, the table pointer, and client's session entry kept with no peer.
## client, client2: join at the start (through the join screen) and land in the room, then
##   follow the session: table A, the room (GameState empty), table B. client then leaves
##   from the table the way the pause menu does and checks no "connection lost" dialog opened.
## client3: joins while the room is open between tables; must land in the room, then table B.
## client4: joins while table B is out; must go straight to the table and get token B once
##   its table has loaded, never seeing the room.
##
## Run: godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##   --data-root=net_launcher --scenario=enet_session_room --peers=5 --timeout-s=300

const TABLE_A := {"name": "Session table A", "folder": "_session_room_a"}
const TABLE_B := {"name": "Session table B", "folder": "_session_room_b"}
const START_CLIENTS: Array[String] = ["client", "client2"]
const ROOM_CLIENTS: Array[String] = ["client", "client2", "client3"]
const ALL_CLIENTS: Array[String] = ["client", "client2", "client3", "client4"]
## The client that leaves at the end, from the table
const LEAVER := "client"
## Time the host waits after the last report for the leaver's player_left to land
const SETTLE_S := 2.0

var _states: Array = []
var _token_a := ""
var _token_b := ""
var _peer_instance := 0
var _peer_by_role: Dictionary = {}
var _unique_id := 0
var _offline_events := 0


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(_rv + ".host.json", {"phase": phase, "token_a": _token_a, "token_b": _token_b})


func _on_state_changed(_old_state: int, new_state: int) -> void:
	_states.append(new_state)
	_log("state %d" % new_state)


func _has(role: String, step: String) -> bool:
	return FileAccess.file_exists("%s.%s.%s" % [_rv, role, step])


func _mark(step: String, data: Dictionary = {}) -> void:
	_write_json("%s.%s.%s" % [_rv, _role, step], data)


func _all_have(roles: Array[String], step: String) -> bool:
	return roles.all(func(role: String) -> bool: return _has(role, step))


func _level(table: Dictionary) -> LevelData:
	return LevelData.from_dict(
		{"level_name": table.name, "level_folder": table.folder, "map_path": MAP_SOURCE}
	)


## True once `table` is on this peer's board with its map built.
func _table_up(table: Dictionary) -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_name == table.name
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
	)


func _on_board(network_id: String) -> bool:
	return network_id != "" and _lpc().find_token_by_network_id(network_id) != null


func _shelf_folders() -> Array:
	return NetworkManager.session.get_shelf().map(func(r: Dictionary) -> String: return r.folder)


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_open_session()
		"room_start":
			if _all_have(START_CLIENTS, "room0"):
				_set_out(TABLE_A, "table_a_load")
		"table_a_load":
			if _table_up(TABLE_A):
				_token_a = _place_token("Hero A")
				_set_phase("table_a")
		"table_a":
			if _all_have(START_CLIENTS, "table_a"):
				_host_return_to_room()
		"room":
			if _all_have(ROOM_CLIENTS, "room"):
				_set_out(TABLE_B, "table_b_load")
		"table_b_load":
			if _table_up(TABLE_B):
				_token_b = _place_token("Hero B")
				_host_check_table_b()
				_set_phase("table_b")
		"table_b":
			if _all_have(ALL_CLIENTS, "json") and _has(LEAVER, "left"):
				_set_phase("collect")
				_host_collect()


## What Root does for Host once a Steam lobby exists (host_session, then ROOM on HOSTING),
## over ENet.
func _open_session() -> void:
	_main.connect("state_changed", _on_state_changed)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(_args.get("port", DEFAULT_PORT)), 8)
	if err != OK:
		_finish(false, "create_server failed: %d" % err)
		return
	var info: Dictionary = NetworkManager.get("_local_player_info")
	info["role"] = NetworkManager.PlayerRole.GM
	NetworkManager.set_player_name("host")
	multiplayer.multiplayer_peer = peer
	_peer_instance = peer.get_instance_id()
	(NetworkManager.get("_players") as Dictionary)[1] = info.duplicate()
	NetworkManager.set("_room_code", "ENET05")
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.HOSTING)
	_result["room_code_start"] = NetworkManager.room_code
	_result["session_open_at_start"] = NetworkManager.session.is_open()
	NetworkManager.player_joined.connect(_on_host_player_joined)
	NetworkManager.player_left.connect(
		func(peer_id: int, _i: Dictionary): _log("peer %d left in %s" % [peer_id, _phase])
	)
	_main.call("change_state", STATE_ROOM)
	_set_phase("room_start")


func _on_host_player_joined(peer_id: int, info: Dictionary) -> void:
	var role := str(info.get("name", ""))
	if peer_id == 1 or _peer_by_role.has(role):
		return
	_peer_by_role[role] = peer_id
	_result["joined_in_" + role] = _phase
	_log("%s joined as peer %d in phase %s" % [role, peer_id, _phase])


## Set out from the room, as the room's Start does.
func _set_out(table: Dictionary, next_phase: String) -> void:
	_main.set("_pending_level_data", _level(table))
	_main.call("_on_lobby_start_game")
	_set_phase(next_phase)


func _place_token(token_name: String) -> String:
	var token := _lpc().spawn_avatar({"format": 1}, token_name, Vector3.UP * 30, true)
	if token == null:
		_finish(false, "spawn of %s failed" % token_name)
		return ""
	_log("%s placed as %s" % [token_name, token.network_id])
	return token.network_id


func _host_return_to_room() -> void:
	_main.call("return_to_room")
	_result["room"] = {
		"state_room": _state() == STATE_ROOM,
		"tokens_in_gamestate": GameState.get_token_count(),
		"level_folder_served": NetworkManager.get_current_level_folder(),
		"game_in_progress": NetworkManager.is_game_in_progress(),
		"session_open": NetworkManager.session.is_open(),
		"table": NetworkManager.session.get_table(),
	}
	_log("returned to the room: %s" % str(_result.room))
	_set_phase("room")


func _host_check_table_b() -> void:
	_result["table_b"] = {
		"table": NetworkManager.session.get_table(),
		"shelf": _shelf_folders(),
		"session_open": NetworkManager.session.is_open(),
		"token_a_in_gamestate": GameState.get_token_state(_token_a) != null,
		"token_b_in_gamestate": GameState.get_token_state(_token_b) != null,
	}
	_log("table B: %s" % str(_result.table_b))


func _host_collect() -> void:
	await get_tree().create_timer(SETTLE_S).timeout
	if _finished:
		return
	var reports := {}
	var ok := true
	for role in ALL_CLIENTS:
		reports[role] = _read_json("%s.%s.json" % [_rv, role])
		ok = ok and bool(reports[role].get("pass", false))
	_result["clients"] = reports
	_result["left"] = _read_json("%s.%s.left" % [_rv, LEAVER])
	var leaver_id := NetworkManager.session.session_id_of(int(_peer_by_role.get(LEAVER, -1)))
	var leaver_entry := SessionChannel.session_id(0, int(_peer_by_role.get(LEAVER, -1)))
	_result["room_code_end"] = NetworkManager.room_code
	_result["same_peer"] = (
		multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_instance_id() == _peer_instance
	)
	_result["players_end"] = NetworkManager.get_player_count()
	_result["session_players"] = NetworkManager.session.get_players()
	_result["states"] = _states
	var room: Dictionary = _result.get("room", {})
	var table_b: Dictionary = _result.get("table_b", {})
	var checks := {
		"session_open_at_start": bool(_result.get("session_open_at_start", false)),
		"same_peer": bool(_result.same_peer),
		"same_room_code": _result.room_code_end == _result.room_code_start,
		"states": _states == [STATE_ROOM, STATE_PLAYING, STATE_ROOM, STATE_PLAYING],
		"room_cleared":
		(
			bool(room.get("state_room"))
			and int(room.get("tokens_in_gamestate", -1)) == 0
			and room.get("level_folder_served") == ""
			and not bool(room.get("game_in_progress", true))
			and bool(room.get("session_open"))
			and room.get("table") == ""
		),
		"table_b":
		(
			table_b.get("table") == TABLE_B.folder
			and table_b.get("shelf") == [TABLE_A.folder, TABLE_B.folder]
			and not bool(table_b.get("session_open", true))
			and not bool(table_b.get("token_a_in_gamestate", true))
			and bool(table_b.get("token_b_in_gamestate"))
		),
		"leaver_left": int(_result.players_end) == 4 and leaver_id == "",
		"leaver_kept":
		(
			_result.session_players.size() == 5
			and NetworkManager.session.peer_for(leaver_entry) == 0
			and _result.session_players.has(leaver_entry)
		),
		"leaver_no_dialog": int(_result.left.get("dialogs", -1)) == 0,
	}
	_result["checks"] = checks
	for key in checks:
		ok = ok and bool(checks[key])
	_finish(ok, "all clients reported")


# =============================================================================
# CLIENTS
# =============================================================================


func _process_client() -> void:
	var host_phase := str(_read_json(_rv + ".host.json").get("phase", ""))
	if _phase == "wait_done" and host_phase == "done":
		_finish(bool(_result.get("pass", false)), "host done")
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_main.connect("state_changed", _on_state_changed)
				_set_phase("wait_to_join")
		"wait_to_join":
			if _may_join(host_phase):
				_join_session()
		"wait_room0":
			if _state() == STATE_ROOM:
				_mark("room0", {"join_screen_freed": _main.get("_join_screen") == null})
				_set_phase("table_a")
		"table_a":
			if _table_up(TABLE_A) and _on_board(_token("token_a")):
				_mark("table_a")
				_set_phase("wait_room")
		"wait_room":
			if _state() == STATE_ROOM:
				_client_in_room()
		"table_b":
			if _table_up(TABLE_B) and _on_board(_token("token_b")):
				_client_report()


func _token(key: String) -> String:
	return str(_read_json(_rv + ".host.json").get(key, ""))


func _may_join(host_phase: String) -> bool:
	match _role:
		"client", "client2":
			return host_phase == "room_start"
		"client3":
			return host_phase == "room"
		"client4":
			return host_phase == "table_b"
	return false


## Joins through the join screen over the title, connecting over ENet as its Connect would
## over Steam. Root moves on when the host places this client.
func _join_session() -> void:
	_main.call("_on_join_game_requested")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", int(_args.get("port", DEFAULT_PORT)))
	if err != OK:
		_finish(false, "create_client failed: %d" % err)
		return
	NetworkManager.set_player_name(_role)
	(NetworkManager.get("_local_player_info") as Dictionary)["role"] = (
		NetworkManager.PlayerRole.PLAYER
	)
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.CONNECTING)
	NetworkManager.connection_state_changed.connect(_on_client_connection_state)
	NetworkManager.session.room_opened.connect(func(): _log("room_opened in " + _phase))
	GameState.state_reset.connect(func(): _log("GameState reset in " + _phase))
	multiplayer.multiplayer_peer = peer
	match _role:
		"client", "client2":
			_set_phase("wait_room0")
		"client3":
			_set_phase("wait_room")
		_:
			_set_phase("table_b")


func _on_client_connection_state(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state == NetworkManager.ConnectionState.JOINED and _unique_id == 0:
		_unique_id = multiplayer.get_unique_id()
		_log("joined as peer %d" % _unique_id)
	elif new_state == NetworkManager.ConnectionState.OFFLINE and _phase != "leaving":
		_offline_events += 1
		_log("went offline in phase " + _phase)


func _client_in_room() -> void:
	_result["room"] = {
		"tokens_in_gamestate": GameState.get_token_count(),
		"joined": NetworkManager.is_client(),
		"session_open": NetworkManager.session.is_open(),
		"table": NetworkManager.session.get_table(),
		"join_screen_freed": _main.get("_join_screen") == null,
	}
	_log("in the room: %s" % str(_result.room))
	_mark("room")
	_set_phase("table_b")


func _client_report() -> void:
	var token_a := _token("token_a")
	_result["unique_id"] = multiplayer.get_unique_id()
	_result["offline_events"] = _offline_events
	_result["states"] = _states
	_result["token_a_gone"] = (
		GameState.get_token_state(token_a) == null and not _on_board(token_a)
	)
	_result["session_table"] = NetworkManager.session.get_table()
	_result["shelf"] = _shelf_folders()
	var room: Dictionary = _result.get("room", {})
	var room_ok: bool = (
		int(room.get("tokens_in_gamestate", -1)) == 0
		and bool(room.get("joined"))
		and bool(room.get("session_open"))
		and room.get("table") == ""
		and bool(room.get("join_screen_freed"))
	)
	var expected_states := {
		"client": [STATE_ROOM, STATE_PLAYING, STATE_ROOM, STATE_PLAYING],
		"client2": [STATE_ROOM, STATE_PLAYING, STATE_ROOM, STATE_PLAYING],
		"client3": [STATE_ROOM, STATE_PLAYING],
		"client4": [STATE_PLAYING],
	}
	var checks := {
		"same_peer_id": _unique_id != 0 and _result.unique_id == _unique_id,
		"never_offline": _offline_events == 0,
		"states": _states == expected_states[_role],
		"token_a_gone": bool(_result.token_a_gone),
		"session_table": _result.session_table == TABLE_B.folder,
		"shelf": _result.shelf == [TABLE_A.folder, TABLE_B.folder],
		"room": _role == "client4" or room_ok,
		"join_screen_freed": _main.get("_join_screen") == null,
	}
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_result["pass"] = ok
	_log("table B: %s" % str(checks))
	_mark("json", _result)
	if _role == LEAVER:
		_leave()
	else:
		_set_phase("wait_done")


## Leave from the table the way the pause menu's Return to Title does, and count the
## confirmation dialogs left open (a voluntary leave used to open "connection lost").
func _leave() -> void:
	_set_phase("leaving")
	_main.call("_on_pause_main_menu_requested")
	await get_tree().create_timer(0.5).timeout
	var dialog_path: String = UIManager.CONFIRMATION_DIALOG_SCENE.resource_path
	var dialogs := get_tree().root.get_children().filter(
		func(n: Node) -> bool: return n.scene_file_path == dialog_path
	)
	var left := {"dialogs": dialogs.size(), "state": _state()}
	_mark("left", left)
	_result["left"] = left
	var ok := bool(_result.get("pass", false)) and dialogs.is_empty() and _state() == STATE_TITLE
	_finish(ok, "left the session")
