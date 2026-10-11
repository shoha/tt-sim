extends "res://tests/net/enet_late_joiner.gd"

## Real-Steam scenario for a hosted session: the room, prefetch, a party avatar travelling
## between tables, a leave and rejoin under the same Steam id, and the end of the session at a
## table. The ENet scenarios (enet_session_room.gd, enet_prefetch.gd, enet_session_file.gd)
## cover the same flow with ENet standing in for Steam and the role standing in for the Steam
## id; this one runs the game's own Steam path: host_game() and a real Steam lobby on the host,
## the title's Play together card and SessionFlow.join_session() with the real room code on the
## client, SteamMultiplayerPeer peer ids, and the session id taken from the transport
## (SessionChannel.session_id_for_peer(), get_steam_id_for_peer_id()).
##
## Not part of the GUT suite: it needs the Steam client and a second Steam account, so two
## processes run it. The host runs unsandboxed under the main account; the client runs in the
## Sandboxie box that holds the alt account (docs/NETWORKING.md, "Automated runs (agents)").
## Both coordinate through files under --rendezvous and write their logs to --out, all in a
## folder the box has as an OpenFilePath. Reuses enet_late_joiner.gd's boot (the main scene,
## logging, the rendezvous helpers) and nothing of its ENet setup.
##
## host: builds map A (a flat authored map) and map B (the shipped GLB in a folder of its own)
##   in its test data root, hosts from the title (SessionFlow.host_session(), a Steam lobby),
##   and once client is in the room shelves A and B as the room's Add does. Once the session's
##   holdings show client holding both (prefetch in the room), sets A out, places Hero and
##   grants client CONTROL as Assign Control does; once client controls it, moves the table to
##   B (Hero travels with the party) and then to the room. client leaves from the room and
##   rejoins with the same code; the host records whether the rejoin arrived before Steam
##   reported the old connection gone (the stale-connection handover), sets A out again and,
##   once client controls Hero there under its new peer id, ends the session at the table as
##   Pause > Return to Title does. It then waits for client's report and reads its own engine
##   log for the teardown errors net_log_check.gd names.
## client: joins in place on the title's card with the host's room code, lands in the room,
##   lets SessionPrefetch fetch both maps there, follows the session to A (no download), to B
##   (no download) and back to the room, controlling Hero at each table; leaves from the room
##   (the room's Leave), rejoins on the card, checks that the host's summary lists it under its
##   Steam id with its new peer id, controls Hero on A again, and when the host ends the session
##   closes the "Disconnected" dialog, waits TEARDOWN_SETTLE_S and reads its own engine log.
##
## Args after `--`: --role=host|client --rendezvous=<abs path prefix> --out=<abs path>
##   --data-root=<name> (required: the host's levels and both peers' caches go there, and each
##   peer deletes its root when it finishes) --engine-log=<abs path> (the log the engine writes,
##   given to Godot as --log-file; default user://logs/godot.log) --timeout-s=<n> (default 300)
##   --rejoin-delay-s=<n> (client: seconds on the title between the leave and the rejoin,
##   default 0).
## Each process writes its log and one final `NET_RESULT {json}` line to --out and stdout, then
## quits with exit code 0 (pass) or 1 (fail).

const LogCheck := preload("res://tests/net/net_log_check.gd")

const APP_ID := 480
const MAP_A := {"name": "Net session A", "folder": "_nettest_session_a"}
const MAP_B := {"name": "Net session B", "folder": "_nettest_session_b"}
const HERO := "Hero"
const CONTROL := TokenPermissions.Permission.CONTROL
## Map A: a flat authored map (a 120 ft square)
const MAP_CELLS := 24
const MAP_SEED := 4711
## A host file older than this before the client started is a previous run's
const FRESH_S := 120
## Seconds the client waits after the session ended before it reads its engine log
const TEARDOWN_SETTLE_S := 3.0
## Seconds the host waits for client's report after ending the session
const REPORT_WAIT_S := 60.0
## Error lines (other than the teardown errors) quoted in the result
const ERROR_SAMPLE := 6

var _start_unix_ms := 0
var _phase_ms := 0
var _code := ""
var _hero := ""
var _states: Array = []
var _connection_events: Array = []

# Host state.
var _client_sid := ""
var _first_peer := 0
var _rejoin_peer := 0
var _joins: Array = []
var _leaves: Array = []
var _ended_ms := 0
var _client_table_loaded := false

# Client state.
var _arrived: Array = []
var _map_downloads := 0
var _offline_events := 0
var _first_id := 0
var _signals_connected := false


func _ready() -> void:
	super._ready()
	_result["steam_ok"] = false
	if _role != "host" and _role != "client":
		_finish(false, "unknown role")
		return
	if Paths.DATA_ROOT == Paths.SHIPPED_DATA_ROOT:
		_finish(false, "run with --data-root=<name>; the scenario never uses the real stores")
		return
	if _role == "host":
		_clear_rendezvous()
	if not _init_steam():
		_finish(false, "steam init failed")


func _set_phase(phase: String) -> void:
	if _start_unix_ms == 0:
		_start_unix_ms = _unix_ms()
	_phase = phase
	_phase_ms = Time.get_ticks_msec()
	_log("phase " + phase)
	if _role == "host":
		_write_json(
			_rv + ".host.json",
			{"phase": phase, "start_unix_ms": _start_unix_ms, "code": _code, "hero": _hero},
		)


## Each peer deletes its own test data root once its run is over (the host's levels, both
## caches), then reports.
func _finish(ok: bool, reason: String) -> void:
	if _finished:
		return
	if Paths.DATA_ROOT != Paths.SHIPPED_DATA_ROOT:
		NetworkManager.disconnect_game()
		_result["data_root_removed"] = Paths.remove_test_data_root(Paths.DATA_ROOT)
	super._finish(ok, reason)


# =============================================================================
# SHARED
# =============================================================================


## As steam_map_download.gd: agent runs have no steam_appid.txt in the working directory, so
## the scenario initialises Steam with the test app id, applies the game's send rates
## (NetworkManager does both on its first multiplayer use) and tells NetworkManager it is ready.
func _init_steam() -> bool:
	var init: Dictionary = Steam.steamInitEx(APP_ID, false)
	_log("steamInitEx -> %s" % str(init))
	if int(init.get("status", -1)) != 0:
		return false
	NetworkManager.set("_steam_initialized", true)
	_result["send_rates_applied"] = SteamNetConfig.apply_defaults()
	_result["steam_id"] = str(Steam.getSteamID())
	_result["steam_ok"] = true
	NetworkManager.set_player_name(_role)
	Steam.network_connection_status_changed.connect(_on_steam_connection_status)
	return true


## Every Steam connection state change this process sees, with Steam's end reason: how a
## leave reached the host (closed by the peer, or a timeout).
func _on_steam_connection_status(handle: int, info: Dictionary, old_state: int) -> void:
	var entry := {
		"handle": handle,
		"old": old_state,
		"state": info.get("connection_state"),
		"end_reason": info.get("end_reason"),
		"end_debug": info.get("end_debug"),
		"phase": _phase,
		"unix_ms": _unix_ms(),
	}
	_connection_events.append(entry)
	_log("steam connection %s" % str(entry))


func _unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _elapsed() -> int:
	return Time.get_ticks_msec() - _start_ms


func _on_state_changed(_old_state: int, new_state: int) -> void:
	_states.append(new_state)
	_log("state %d" % new_state)


func _mover() -> TableMover:
	return _main.get("_table_mover") as TableMover


func _has(step: String) -> bool:
	return FileAccess.file_exists("%s.client.%s" % [_rv, step])


func _mark(step: String, data: Dictionary = {}) -> void:
	data["elapsed_ms"] = _elapsed()
	data["unix_ms"] = _unix_ms()
	_result[step] = data
	_write_json("%s.client.%s" % [_rv, step], data)


## True once `table` is on this peer's board with its map built.
func _table_up(table: Dictionary) -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_folder == table.folder
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
	)


## True once the token `network_id` is on this peer's board and shown (SessionParty sets a
## travelling avatar down a physics frame after the load).
func _landed(network_id: String) -> bool:
	var token := _lpc().find_token_by_network_id(network_id) if network_id != "" else null
	return token != null and token.visible


## True when this peer holds CONTROL of `network_id` and may drag it.
func _controls(network_id: String) -> bool:
	var token := _lpc().find_token_by_network_id(network_id) if network_id != "" else null
	if token == null or token.get_dragging_object() == null:
		return false
	return (
		GameState.has_token_permission(network_id, multiplayer.get_unique_id(), CONTROL)
		and token.get_dragging_object().dragging_allowed
	)


## This process's engine log, read for the teardown errors (net_log_check.gd) and a sample of
## any other errors. `readable` false when the log could not be read, which fails the check.
func _engine_log_check() -> Dictionary:
	var path := str(_args.get("engine-log", "user://logs/godot.log"))
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text() if file != null else ""
	var out := LogCheck.teardown_errors(text)
	out["path"] = path
	out["readable"] = text.length() > 0
	var others: Array = []
	for line in text.split("\n"):
		if line.begins_with("ERROR: ") and others.size() < ERROR_SAMPLE:
			others.append(line.substr(0, 160))
	out["error_sample"] = others
	return out


func _log_clean(check: Dictionary) -> bool:
	return bool(check.get("readable", false)) and not LogCheck.fails(check)


func _all_true(checks: Dictionary) -> bool:
	for key in checks:
		if not bool(checks[key]):
			return false
	return true


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				var problem := _build_maps()
				if problem != "":
					_finish(false, problem)
					return
				_open_session()
		"hosting":
			if _state() == STATE_ROOM and _code != "":
				_result["room_code"] = _code
				_result["steam_transport"] = multiplayer.multiplayer_peer is SteamMultiplayerPeer
				_set_phase("room_start")
		"room_start":
			if _has("room0"):
				_client_sid = str(_read_json(_rv + ".client.room0").get("steam_id", ""))
				_shelve_maps()
		"prefetch":
			var held: Array = NetworkManager.session.get_holdings().get(_client_sid, [])
			if held.has(MAP_A.folder) and held.has(MAP_B.folder):
				_result["held_both_after_ms"] = Time.get_ticks_msec() - _phase_ms
				_mover().set_out(MAP_A.folder)
				_set_phase("a_load")
		"a_load":
			# A spawn that reaches the client before it has switched to the table is lost
			# (seen once, 2026-10-10), so Hero waits for the client's table_loaded report.
			if _table_up(MAP_A) and _client_table_loaded:
				_host_place_hero()
		"a":
			if _has("a"):
				_host_move(MAP_B.folder, "b_load")
		"b_load":
			if _table_up(MAP_B) and _landed(_hero):
				_result["table_b"] = _hero_record()
				_set_phase("b")
		"b":
			if _has("b"):
				_host_move(TableMover.ROOM, "room")
		"room":
			if _has("rejoined"):
				_result["room_after_rejoin"] = _session_record()
				_mover().set_out(MAP_A.folder)
				_set_phase("a2_load")
		"a2_load":
			if _table_up(MAP_A) and _landed(_hero) and _has_control_peer():
				_result["table_a2"] = _hero_record()
				_set_phase("a2")
		"a2":
			if _has("a2"):
				_host_end_session()
		"ended":
			var waited := (Time.get_ticks_msec() - _ended_ms) / 1000.0
			if _has("done") or waited > REPORT_WAIT_S:
				_host_collect()


## Map A (a flat authored map) and map B (the shipped GLB in a folder of its own), saved in
## this host's test data root. "" once saved, else what failed.
func _build_maps() -> String:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "net", MAP_SEED)
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(MAP_A.folder))
	if MapDocumentIO.write(doc, LevelManager.map_document_path(MAP_A.folder)) != OK:
		return "map A's document was not written"
	var a := LevelData.new()
	a.level_name = MAP_A.name
	a.level_folder = MAP_A.folder
	a.map_document = LevelManager.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(a, MAP_A.folder) == "":
		return "map A was not saved"
	var data := FileAccess.get_file_as_bytes(MAP_SOURCE)
	if data.is_empty():
		return "cannot read " + MAP_SOURCE
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(MAP_B.folder))
	var file := FileAccess.open(Paths.get_level_map_path(MAP_B.folder), FileAccess.WRITE)
	if file == null:
		return "map B's file was not written"
	file.store_buffer(data)
	file.close()
	_result["map_b_bytes"] = data.size()
	var b := LevelData.new()
	b.level_name = MAP_B.name
	b.level_folder = MAP_B.folder
	b.map_path = LevelManager.LEVEL_MAP_NAME
	if LevelManager.save_level_folder(b, MAP_B.folder) == "":
		return "map B was not saved"
	return ""


## Host from the title with no map chosen, as the card's Host does: a Steam lobby, then ROOM.
func _open_session() -> void:
	_main.connect("state_changed", _on_state_changed)
	NetworkManager.room_code_received.connect(_on_room_code)
	NetworkManager.player_joined.connect(_on_host_player_joined)
	NetworkManager.player_left.connect(_on_host_player_left)
	NetworkManager.table_loaded.connect(func(_peer: int): _client_table_loaded = true)
	NetworkManager.connection_failed.connect(
		func(reason: String): _finish(false, "connection failed: " + reason)
	)
	_flow().host_session(null)
	_set_phase("hosting")


## Every rendezvous file of an earlier run (the code, the host's file and client's marks).
func _clear_rendezvous() -> void:
	var dir := DirAccess.open(_rv.get_base_dir())
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.begins_with(_rv.get_file() + "."):
			dir.remove(file_name)


func _on_room_code(code: String) -> void:
	_code = code
	_log("room code " + code)


func _steam_id_of(peer_id: int) -> String:
	var transport := multiplayer.multiplayer_peer as SteamMultiplayerPeer
	return str(transport.get_steam_id_for_peer_id(peer_id)) if transport != null else ""


func _on_host_player_joined(peer_id: int, _info: Dictionary) -> void:
	if peer_id == 1:
		return
	var join := {
		"peer": peer_id,
		"phase": _phase,
		"unix_ms": _unix_ms(),
		"steam_id": _steam_id_of(peer_id),
		"players": NetworkManager.get_player_count(),
	}
	_joins.append(join)
	if _first_peer == 0:
		_first_peer = peer_id
	elif peer_id != _first_peer and _rejoin_peer == 0:
		_rejoin_peer = peer_id
	_log("peer %d joined in %s: %s" % [peer_id, _phase, str(join)])
	# The session admits the peer after player_joined (NetworkManager._rpc_send_player_info).
	_note_admitted.call_deferred(join)


func _note_admitted(join: Dictionary) -> void:
	join["session_id"] = NetworkManager.session.session_id_of(int(join.peer))
	join["session_players"] = NetworkManager.session.get_players().size()
	_log("admitted: %s" % str(join))


func _on_host_player_left(peer_id: int, _info: Dictionary) -> void:
	var leave := {"peer": peer_id, "phase": _phase, "unix_ms": _unix_ms()}
	_leaves.append(leave)
	_log("peer %d left in %s" % [peer_id, _phase])
	# After every player_left handler (the session's, the table's permission handler).
	_note_left.call_deferred(leave)


## What the host keeps of client once a connection of its went: its entry's peer (0 when the
## rejoin has not come yet, the new peer when it came first) and its grants.
func _note_left(leave: Dictionary) -> void:
	leave["peer_for_client"] = NetworkManager.session.peer_for(_client_sid)
	leave["grants"] = NetworkManager.session.party.get_grants()
	leave["rejoined_first"] = _rejoin_peer != 0 and _rejoin_peer != int(leave.peer)
	_log("left: %s" % str(leave))


## A and B go on the shelf in order, as the room's Add puts them there; client fetches both.
func _shelve_maps() -> void:
	for table: Dictionary in [MAP_A, MAP_B]:
		var level := LevelManager.load_level_folder(table.folder, false)
		if level == null:
			_finish(false, "%s is not in the host's library" % table.name)
			return
		NetworkManager.session.shelve(level.to_dict())
	_result["servable_in_room"] = NetworkManager.session.servable_folders()
	_set_phase("prefetch")


## Hero on map A, given to client the way the GM's Assign Control does.
func _host_place_hero() -> void:
	var token := _lpc().spawn_avatar({"format": 1}, HERO, Vector3.UP * 30, true)
	if token == null:
		_finish(false, "the spawn of Hero failed")
		return
	_hero = token.network_id
	GameState.grant_token_permission(_hero, _first_peer, CONTROL)
	NetworkManager.permissions.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)
	_result["table_a"] = _hero_record()
	_set_phase("a")


## Move the table at once (the end of the notice), keeping it: to a shelf map or the room.
func _host_move(key: String, next_phase: String) -> void:
	_set_phase("moving")
	if not await _mover().move_now(key):
		_finish(false, "the move to '%s' was refused" % key)
		return
	if key == TableMover.ROOM:
		_result["room"] = _session_record()
	_set_phase(next_phase)


func _has_control_peer() -> bool:
	return GameState.get_peers_with_permission(_hero, CONTROL) == [_rejoin_peer]


## Hero and the session as the host has them at a table.
func _hero_record() -> Dictionary:
	return {
		"table": NetworkManager.session.get_table(),
		"hero_in_gamestate": GameState.get_token_state(_hero) != null,
		"hero_peers": GameState.get_peers_with_permission(_hero, CONTROL),
		"grants": NetworkManager.session.party.get_grants(),
		"session_players": NetworkManager.session.get_players(),
		"peer_for_client": NetworkManager.session.peer_for(_client_sid),
	}


## The session as the host has it in the room.
func _session_record() -> Dictionary:
	var members := NetworkManager.session.party.get_members()
	return {
		"state_room": _state() == STATE_ROOM,
		"tokens_in_gamestate": GameState.get_token_count(),
		"session_open": NetworkManager.session.is_open(),
		"table": NetworkManager.session.get_table(),
		"party": members.map(func(m: Dictionary) -> String: return str(m.state.network_id)),
		"party_owners": members[0].owners if members.size() == 1 else [],
		"grants": NetworkManager.session.party.get_grants(),
		"session_players": NetworkManager.session.get_players(),
		"peer_for_client": NetworkManager.session.peer_for(_client_sid),
		"rejoin_steam_id": _steam_id_of(_rejoin_peer) if _rejoin_peer != 0 else "",
	}


## End the session at the table, as Pause > Return to Title does for the GM.
func _host_end_session() -> void:
	_main.call("_on_pause_main_menu_requested")
	_ended_ms = Time.get_ticks_msec()
	_result["ended"] = {
		"state_title": _state() == STATE_TITLE,
		"offline": NetworkManager.connection_state == NetworkManager.ConnectionState.OFFLINE,
	}
	_set_phase("ended")


func _host_collect() -> void:
	_set_phase("collect")
	_result["client"] = _read_json(_rv + ".client.json")
	_result["joins"] = _joins
	_result["leaves"] = _leaves
	_result["states"] = _states
	_result["connection_events"] = _connection_events
	_result["engine_log"] = _engine_log_check()
	var sid := _client_sid
	var grant := {sid: [_hero]}
	var first: Dictionary = _joins[0] if _joins.size() > 0 else {}
	var again: Dictionary = _joins[1] if _joins.size() > 1 else {}
	var old_leave: Array = _leaves.filter(func(l: Dictionary) -> bool: return l.peer == _first_peer)
	var a: Dictionary = _result.get("table_a", {})
	var b: Dictionary = _result.get("table_b", {})
	var room: Dictionary = _result.get("room", {})
	var a2: Dictionary = _result.get("table_a2", {})
	_result["stale_handover"] = (
		old_leave.is_empty() or int(again.get("unix_ms", 0)) < int(old_leave[0].unix_ms)
	)
	# How long Steam took to tell the host that client's first connection went, and how long
	# after that the rejoin's connection arrived (one clock: both processes on this machine).
	var left_unix := int(_result.client.get("left", {}).get("unix_ms", 0))
	if not old_leave.is_empty() and left_unix > 0:
		_result["leave_seen_after_ms"] = int(old_leave[0].unix_ms) - left_unix
		_result["rejoin_after_leave_seen_ms"] = (
			int(again.get("unix_ms", 0)) - int(old_leave[0].unix_ms)
		)
	var checks := {
		"steam_lobby": _code != "" and bool(_result.get("steam_transport", false)),
		"session_id_is_steam_id":
		(
			sid != ""
			and first.get("steam_id") == sid
			and first.get("session_id") == sid
			and int(first.get("session_players", 0)) == 2
		),
		"shelf_served": _result.get("servable_in_room") == [MAP_A.folder, MAP_B.folder],
		"granted_at_a": a.get("grants") == grant and a.get("hero_peers") == [_first_peer],
		"travelled_to_b":
		(
			b.get("table") == MAP_B.folder
			and bool(b.get("hero_in_gamestate"))
			and b.get("hero_peers") == [_first_peer]
			and b.get("grants") == grant
		),
		"party_in_room":
		(
			bool(room.get("state_room"))
			and int(room.get("tokens_in_gamestate", -1)) == 0
			and bool(room.get("session_open"))
			and room.get("table") == ""
			and room.get("party") == [_hero]
			and room.get("party_owners") == [sid]
		),
		"old_connection_left": not old_leave.is_empty(),
		"rejoin_same_session_id":
		(
			_rejoin_peer != 0
			and _rejoin_peer != _first_peer
			and again.get("steam_id") == sid
			and again.get("session_id") == sid
		),
		"one_entry_after_rejoin":
		(
			(a2.get("session_players", {}) as Dictionary).size() == 2
			and int(a2.get("peer_for_client", 0)) == _rejoin_peer
		),
		"control_regained": a2.get("hero_peers") == [_rejoin_peer] and a2.get("grants") == grant,
		"ended_at_table":
		bool(_result.ended.get("state_title")) and bool(_result.ended.get("offline")),
		"host_teardown_clean": _log_clean(_result.engine_log),
		"client_passed": bool(_result.client.get("pass", false)),
	}
	_result["checks"] = checks
	_finish(_all_true(checks), "client reported" if _has("done") else "no report from client")


# =============================================================================
# CLIENT
# =============================================================================


func _process_client() -> void:
	var host := _host_file()
	var host_phase := str(host.get("phase", ""))
	if host_phase == "done" and _phase != "teardown":
		_finish(false, "the host finished before this client reported (phase %s)" % _phase)
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_client_setup()
				_set_phase("wait_code")
		"wait_code":
			if host_phase == "room_start" and str(host.get("code", "")) != "":
				_code = str(host.code)
				if _submit_code():
					_set_phase("wait_room0")
		"wait_room0":
			if _state() == STATE_ROOM:
				_first_id = multiplayer.get_unique_id()
				_mark("room0", _identity())
				_set_phase("room")
		"room":
			if _table_up(MAP_A):
				_set_phase("a")
		"a":
			_hero = str(host.get("hero", ""))
			if _table_up(MAP_A) and _landed(_hero) and _controls(_hero):
				_mark("a", {"map_downloads": _map_downloads})
				_set_phase("b")
		"b":
			if _table_up(MAP_B) and _landed(_hero) and _controls(_hero):
				_mark("b", {"map_downloads": _map_downloads})
				_set_phase("back_to_room")
		"back_to_room":
			if _state() == STATE_ROOM and host_phase == "room":
				_client_leave()
		"left":
			_client_rejoin()
		"rejoining":
			if _state() == STATE_ROOM:
				_mark("rejoined", _identity())
				_set_phase("a2")
		"a2":
			if _table_up(MAP_A) and _landed(_hero) and _controls(_hero):
				_mark("a2", _identity())
				_set_phase("wait_end")
		"wait_end":
			if NetworkManager.connection_state == NetworkManager.ConnectionState.OFFLINE:
				_client_session_ended()


## The host's file of this run, or {} (none yet, or an earlier run's).
func _host_file() -> Dictionary:
	var host := _read_json(_rv + ".host.json")
	if int(host.get("start_unix_ms", 0)) < _start_unix_ms - FRESH_S * 1000:
		return {}
	return host


## A clean cache for both maps (the box keeps its copy between runs), the signals the client
## reads, and the session's state changes.
func _client_setup() -> void:
	for table: Dictionary in [MAP_A, MAP_B]:
		for variant in [Paths.LEVEL_MAP_VARIANT, Paths.LEVEL_MAP_DOCUMENT_VARIANT]:
			AssetManager.cache.remove_cached(
				Paths.LEVEL_MAPS_PACK_ID,
				table.folder,
				variant,
				Paths.get_level_map_file_type(variant)
			)
	_main.connect("state_changed", _on_state_changed)
	AssetManager.streamer.asset_received.connect(_on_file_arrived)
	_lpc()._map_download_coordinator.map_download_started.connect(
		func(folder: String) -> void:
			_map_downloads += 1
			_log("the table's load downloads %s" % folder)
	)
	NetworkManager.connection_state_changed.connect(_on_client_connection_state)
	NetworkManager.connection_failed.connect(_on_client_connection_failed)


## Join in place on the title's Play together card, as a player typing the code does: Join
## opens the field, the code goes in, and Join submits it (the title's join_requested reaches
## SessionFlow.join_session(), which joins the Steam lobby). False while the card is not there
## or still busy.
func _submit_code() -> bool:
	var title := _main.get("_title_screen") as TitleScreen
	if title == null or title.play_together == null or title.play_together.busy:
		return false
	title.play_together.open_join()
	title.play_together.code_edit.text = _code
	title.play_together.submit()
	var key := "join_under_way" if _first_id == 0 else "rejoin_under_way"
	_result[key] = _flow().is_joining()
	_log("joining room %s (under way: %s)" % [_code, str(_result[key])])
	return true


## This client as the host's summary has it: its Steam id, its peer id, and the session's
## entry for that Steam id (the host keys players by session id, the Steam id over Steam).
func _identity() -> Dictionary:
	var sid := str(Steam.getSteamID())
	var players := NetworkManager.session.get_players()
	return {
		"steam_id": sid,
		"peer": multiplayer.get_unique_id(),
		"own_session_id": NetworkManager.session.session_id_for_peer(multiplayer.get_unique_id()),
		"listed": players.has(sid),
		"listed_peer": int(players.get(sid, {}).get("peer_id", 0)),
		"session_players": players.size(),
		"tokens_in_gamestate": GameState.get_token_count(),
	}


func _on_file_arrived(
	pack_id: String, asset_id: String, variant_id: String, _path: String, _file_type := ""
) -> void:
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return
	_arrived.append({"folder": asset_id, "variant": variant_id, "phase": _phase})
	_log("%s of %s arrived in %s" % [variant_id, asset_id, _phase])


func _on_client_connection_state(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state == NetworkManager.ConnectionState.OFFLINE and _phase not in ["left", "wait_end"]:
		_offline_events += 1
		_log("went offline in phase " + _phase)


## A failure fails the run, except the host ending the session ("Host disconnected").
func _on_client_connection_failed(reason: String) -> void:
	_log("connection failed in %s: %s" % [_phase, reason])
	if _phase != "wait_end":
		_finish(false, "connection failed in %s: %s" % [_phase, reason])


## Leave from the room, as the room's Leave does, and rejoin at once with the same code.
func _client_leave() -> void:
	var room_screen := _flow().get("_room_screen") as RoomScreen
	if room_screen == null:
		_finish(false, "no room screen to leave from")
		return
	_mark("room", _identity())
	_set_phase("left")
	room_screen.panel.leave_requested.emit()
	_mark("left", {"state": _state()})


func _client_rejoin() -> void:
	var delay_ms := int(float(_args.get("rejoin-delay-s", "0")) * 1000.0)
	if _state() != STATE_TITLE or Time.get_ticks_msec() - _phase_ms < delay_ms:
		return
	if _submit_code():
		_set_phase("rejoining")


## The host ended the session: close the "Disconnected" dialog the way its button does (back
## to the title), let the teardown finish, then read this process's engine log and report.
func _client_session_ended() -> void:
	_set_phase("teardown")
	var dialog_path: String = UIManager.CONFIRMATION_DIALOG_SCENE.resource_path
	var dialogs := get_tree().root.get_children().filter(
		func(n: Node) -> bool: return n.scene_file_path == dialog_path
	)
	_result["ended"] = {"dialogs": dialogs.size(), "state": _state()}
	for dialog in dialogs:
		dialog.queue_free()
	_main.call("change_state", STATE_TITLE)
	await get_tree().create_timer(TEARDOWN_SETTLE_S).timeout
	_result["engine_log"] = _engine_log_check()
	_result["arrived"] = _arrived
	_result["states"] = _states
	_result["connection_events"] = _connection_events
	_result["offline_events"] = _offline_events
	var room0: Dictionary = _result.get("room0", {})
	var room: Dictionary = _result.get("room", {})
	var again: Dictionary = _result.get("rejoined", {})
	var a2: Dictionary = _result.get("a2", {})
	var prefetched := [MAP_A.folder, MAP_B.folder].all(
		func(folder: String) -> bool:
			return _arrived.any(
				func(e: Dictionary) -> bool: return e.folder == folder and e.phase == "room"
			)
	)
	var checks := {
		"joined_via_card":
		bool(_result.get("join_under_way", false)) and bool(_result.get("rejoin_under_way", false)),
		"listed_under_steam_id":
		(
			bool(room0.get("listed"))
			and int(room0.get("listed_peer", 0)) == _first_id
			and room0.get("own_session_id") == room0.get("steam_id")
		),
		"prefetched_in_room": prefetched,
		"no_table_downloads": _map_downloads == 0,
		"control_at_a_and_b": _result.has("a") and _result.has("b"),
		"room_after_b": room.has("peer") and int(room.get("tokens_in_gamestate", -1)) == 0,
		"rejoined_same_steam_id":
		(
			int(again.get("peer", 0)) != 0
			and int(again.get("peer", 0)) != _first_id
			and bool(again.get("listed"))
			and int(again.get("listed_peer", 0)) == int(again.get("peer", 0))
			and int(again.get("session_players", 0)) == 2
		),
		"control_after_rejoin": a2.has("peer"),
		"never_dropped": _offline_events == 0,
		"ended_to_title": _state() == STATE_TITLE,
		"teardown_clean": _log_clean(_result.engine_log),
	}
	_result["checks"] = checks
	var ok := _all_true(checks)
	_result["pass"] = ok
	_write_json(_rv + ".client.json", _result)
	# The host reads the report once this marker is there, never a half-written file.
	_write_json(_rv + ".client.done", {})
	_finish(ok, "session ended")
