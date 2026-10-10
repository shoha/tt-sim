extends "res://tests/net/enet_late_joiner.gd"

## ENet scenario for the session room, its party and the table moves (SessionChannel,
## SessionParty, TableMover, Root.State.ROOM): a hosted session goes table A > room > table B
## > table A on one connection, while peers join in the room at the start, in the room
## between tables, and at the last table. client's avatar travels with the session under
## client's control; client then leaves and rejoins with a new peer id and the same session
## id, and controls it again. Table A comes back as the session left it: its moved token and
## its live terrain edit on every peer, the late joiner included. Ported from the
## session-room probe (branch probe/session-room).
##
## Five processes, one per role, reuse enet_late_joiner.gd's boot, ENet setup and
## rendezvous files. Table A is an authored flat map the host builds in its own test data
## root (its map.ttmap is downloaded by the clients), so it takes live edits; table B is the
## shipped res:// map under a level folder of its own, so the shelf and the table pointer tell
## them apart. Each client reports its role as its session key (SessionChannel.SESSION_KEY),
## the ENet stand-in for a Steam id.
##
## host: builds table A, opens the session in the room; once client and client2 are in the
##   room, sets table A out from the shelf (TableMover.set_out) and places Hero A (granted to
##   client: it leaves A's placements) and Bystander A (nobody's); raises the ground at
##   RAISE_AT with the play-side editor (a live edit) and moves Bystander A to MOVED_TO; once
##   both clients see the tokens, moves the table to the room (TableMover.move_now, Keep: A's
##   state is kept without Hero A) and checks the room on its side (no tokens, nothing served,
##   the session open, Hero A in the party); once client, client2 and client3 are in the room,
##   sets out table B, waits for Hero A to land, places Hero B and saves table B (Hero A must
##   not be in the saved placements); records client's leave (entry kept with no peer, grant
##   kept by session id) and its rejoin (same entry, a new peer, CONTROL of Hero A again).
##   Then table B must count as unchanged (saved, the party not counted), so the drawer's Move
##   the table here (TableMover.request_move) asks nothing and counts down; table A comes back with
##   Bystander A where it was moved, the raised ground and its one op, and Hero A set out
##   on it; then client4 may join. It finishes when every client has reported, checking one
##   peer object and room code throughout, the shelf and the table pointer.
## client, client2: join at the start (through the join screen) and land in the room, then
##   follow the session: table A, the room (GameState empty), table B, where Hero A is on the
##   board and only client controls it. client then leaves from the table the way the pause
##   menu does (no "connection lost" dialog), rejoins through the join screen once the host
##   saw it go, and must control Hero A again under its new peer id.
## client3: joins while the room is open between tables; must land in the room, then table B.
## client, client2, client3: see the move's notice, then table A as the session left it:
##   Bystander A at MOVED_TO, the ground at RAISE_AT as high as the host's, one op caught up.
## client4: joins while table A is out again (a late joiner); must go straight to the table
##   and get table A as the session left it, with Hero A, never seeing the room.
##
## Run: godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##   --data-root=net_launcher --scenario=enet_session_room --peers=5 --timeout-s=420

const TABLE_A := {"name": "Session table A", "folder": "_session_room_a"}
const TABLE_B := {"name": "Session table B", "folder": "_session_room_b"}
const START_CLIENTS: Array[String] = ["client", "client2"]
const ROOM_CLIENTS: Array[String] = ["client", "client2", "client3"]
const ALL_CLIENTS: Array[String] = ["client", "client2", "client3", "client4"]
## The client that owns Hero A, and leaves and rejoins at table B, from the table
const LEAVER := "client"
const HERO := "Hero A"
const BYSTANDER := "Bystander A"
const CONTROL := TokenPermissions.Permission.CONTROL
## Time the host waits after the last report before it collects
const SETTLE_S := 2.0
## How far Hero A may stand off where a drop at its spot would land (m)
const GROUND_TOLERANCE_M := 0.05
## Table A's map: a flat authored map (a 120 ft square)
const MAP_CELLS := 24
const MAP_SEED := 4711
## Where the host raises table A's ground, and where it moves Bystander A to
const RAISE_AT := Vector3(-10, 0, 10)
const MOVED_TO := Vector3(6, 0, -6)
## How far a restored token may stand off where it was moved, across the ground (m), and a
## peer's ground at RAISE_AT off the host's (m)
const MOVE_TOLERANCE_M := 0.15
const HEIGHT_TOLERANCE_M := 0.05
## Frames a client waits at table A for the restored state before it reports what it has
const RESTORE_FRAMES := 1200

var _states: Array = []
var _token_a := ""
var _token_b := ""
var _hero := ""
var _edit_y := 0.0
var _peer_instance := 0
var _peer_by_role: Dictionary = {}
var _rejoined_peer := 0
var _unique_id := 0
var _offline_events := 0
var _client_signals_connected := false
var _notice_text := ""
var _restore_frames := 0


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(
			_rv + ".host.json",
			{
				"phase": phase,
				"token_a": _token_a,
				"token_b": _token_b,
				"hero": _hero,
				"edit_y": _edit_y,
			}
		)


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


func _mover() -> TableMover:
	return _main.get("_table_mover") as TableMover


## True once `table` is on this peer's board with its map built (and, for table A, its live
## edits started).
func _table_up(table: Dictionary) -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_name == table.name
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
		and (table != TABLE_A or is_instance_valid(lpc.live_edits))
	)


func _on_board(network_id: String) -> bool:
	return network_id != "" and _lpc().find_token_by_network_id(network_id) != null


## The token named `token_name` on this peer's board, or null. A token a map restores comes
## back under its placement id, so it is found by name.
func _named(token_name: String) -> BoardToken:
	for value: Variant in _lpc().spawned_tokens.values():
		if is_instance_valid(value) and (value as BoardToken).token_name == token_name:
			return value as BoardToken
	return null


## True when this peer holds CONTROL of `network_id` and may drag it.
func _controls(network_id: String) -> bool:
	var token := _lpc().find_token_by_network_id(network_id)
	if token == null or token.get_dragging_object() == null:
		return false
	return (
		GameState.has_token_permission(network_id, multiplayer.get_unique_id(), CONTROL)
		and token.get_dragging_object().dragging_allowed
	)


func _shelf_folders() -> Array:
	return NetworkManager.session.get_shelf().map(func(r: Dictionary) -> String: return r.folder)


## The leaver's session id: its role, reported as its session key.
func _leaver_id() -> String:
	return SessionChannel.session_id(0, 0, LEAVER)


## Table A as this peer has it: Bystander A's place, the ground at RAISE_AT and the op log.
func _table_a_now() -> Dictionary:
	var edits := _lpc().live_edits
	var bystander := _named(BYSTANDER)
	var at: Vector3 = bystander.rigid_body.global_position if bystander != null else Vector3.INF
	return {
		"bystander": bystander != null,
		"bystander_off_m":
		Vector2(at.x, at.z).distance_to(Vector2(MOVED_TO.x, MOVED_TO.z)) if bystander else -1.0,
		"ground_y": edits.editor.ground_height_at(RAISE_AT) if is_instance_valid(edits) else -1.0,
		"ops": edits.op_log.size() if is_instance_valid(edits) else -1,
		"settled": is_instance_valid(edits) and edits.is_settled(),
	}


## Whether `a` (_table_a_now()) is table A as the session left it, with the ground the host
## raised to `edit_y`.
func _restored(a: Dictionary, edit_y: float) -> bool:
	return (
		bool(a.get("bystander"))
		and float(a.get("bystander_off_m", -1.0)) >= 0.0
		and float(a.get("bystander_off_m", -1.0)) <= MOVE_TOLERANCE_M
		and absf(float(a.get("ground_y", -1.0)) - edit_y) <= HEIGHT_TOLERANCE_M
		and int(a.get("ops", -1)) == 1
	)


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				var problem := _build_table_a()
				if problem != "":
					_finish(false, problem)
					return
				_open_session()
		"room_start":
			if _all_have(START_CLIENTS, "room0"):
				_set_out_a()
		"table_a_load":
			if _table_up(TABLE_A):
				_host_place_table_a()
		"table_a_edit":
			_host_edit_table_a()
		"table_a":
			if _all_have(START_CLIENTS, "table_a"):
				_host_return_to_room()
		"room":
			if _all_have(ROOM_CLIENTS, "room"):
				_set_out(TABLE_B, "table_b_load")
		"table_b_load":
			if _table_up(TABLE_B) and _hero_landed():
				_token_b = _place_token("Hero B")
				_set_phase("table_b_drop")
		"table_b_drop":
			# Saved once it has landed, so the map holds it where it stands.
			if _rests(_token_b):
				_host_check_table_b()
				_set_phase("table_b")
		"table_b":
			if (
				_all_have(ROOM_CLIENTS, "b")
				and _has(LEAVER, "left")
				and _has(LEAVER, "rejoined")
			):
				_host_move_back()
		"a2_load":
			if _table_up(TABLE_A) and _hero_landed() and _named(BYSTANDER) != null:
				_host_check_table_a2()
		"table_a2":
			if _all_have(ALL_CLIENTS, "json"):
				_set_phase("collect")
				_host_collect()


## Table A: a flat authored map saved in this host's test data root, so the shelf can set it
## out from its folder and the table takes live edits. "" once saved, else what failed.
func _build_table_a() -> String:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "net", MAP_SEED)
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(TABLE_A.folder))
	if MapDocumentIO.write(doc, LevelManager.map_document_path(TABLE_A.folder)) != OK:
		return "table A's map document was not written"
	var level := LevelData.new()
	level.level_name = TABLE_A.name
	level.level_folder = TABLE_A.folder
	level.map_document = LevelManager.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(level, TABLE_A.folder) == "":
		return "table A was not saved"
	return ""


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
	NetworkManager.player_left.connect(_on_host_player_left)
	_main.call("change_state", STATE_ROOM)
	_set_phase("room_start")


func _on_host_player_joined(peer_id: int, info: Dictionary) -> void:
	var role := str(info.get("name", ""))
	if peer_id == 1:
		return
	if _peer_by_role.has(role):
		if role == LEAVER and peer_id != int(_peer_by_role[role]):
			_rejoined_peer = peer_id
			_log("%s rejoined as peer %d in phase %s" % [role, peer_id, _phase])
		return
	_peer_by_role[role] = peer_id
	_result["joined_in_" + role] = _phase
	_log("%s joined as peer %d in phase %s" % [role, peer_id, _phase])


func _on_host_player_left(peer_id: int, _info: Dictionary) -> void:
	_log("peer %d left in %s" % [peer_id, _phase])
	if peer_id == int(_peer_by_role.get(LEAVER, -1)):
		# After every player_left handler (the session's, the table's permission handler).
		_note_leaver_left.call_deferred()


## What the host keeps of the leaver once it has gone: its entry with no peer, and its grant
## by session id while the table forgot its peer's.
func _note_leaver_left() -> void:
	_result["on_leave"] = {
		"peer": NetworkManager.session.peer_for(_leaver_id()),
		"grants": NetworkManager.session.party.get_grants(),
		"hero_peers": GameState.get_peers_with_permission(_hero, CONTROL),
	}
	_log("leaver gone: %s" % str(_result.on_leave))
	_mark("leaver_left")


## Table A goes on the shelf as the room's Add puts it there, and out as its Set out does.
func _set_out_a() -> void:
	var level := LevelManager.load_level_folder(TABLE_A.folder, false)
	if level == null:
		_finish(false, "table A is not in the host's library")
		return
	NetworkManager.session.shelve(level.to_dict())
	_mover().set_out(TABLE_A.folder)
	_set_phase("table_a_load")


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


## Table A: Hero A, given to client the way the GM's Assign Control does, and Bystander A,
## nobody's. Then the GM raises the ground at RAISE_AT (one sculpt stroke on the play-side
## editor, which the live edits log and send).
func _host_place_table_a() -> void:
	_result["changes_at_set_out"] = _mover().changes()
	_hero = _place_token(HERO)
	_token_a = _place_token(BYSTANDER)
	var hero := _lpc().find_token_by_network_id(_hero)
	var bystander := _lpc().find_token_by_network_id(_token_a)
	GameState.grant_token_permission(_hero, int(_peer_by_role.get(LEAVER, 0)), CONTROL)
	NetworkManager.permissions.broadcast_token_permissions(
		TokenPermissions.to_dict(GameState.get_token_permissions())
	)
	var level := _lpc().active_level_data
	_result["table_a"] = {
		"hero_placed": level.get_token_placement(str(hero.get_meta("placement_id"))) != null,
		"bystander_placed":
		level.get_token_placement(str(bystander.get_meta("placement_id"))) != null,
		"grants": NetworkManager.session.party.get_grants(),
	}
	_log("table A: %s" % str(_result.table_a))
	var editor := _lpc().live_edits.editor
	_result["ground_before_y"] = editor.ground_height_at(RAISE_AT)
	if not editor.begin_height_stroke(HeightBrush.RAISE):
		_finish(false, "table A's ground cannot be sculpted")
		return
	for i in 8:
		editor.height_dab(RAISE_AT, RAISE_AT, 3.0, 0.25)
		editor.flush()
	editor.end_stroke()
	_lpc().live_edits.send_now()
	_set_phase("table_a_edit")


## True once the token `network_id` is shown and rests on the ground: its drop has landed
## and its settle tween, which would overwrite a move, has finished.
func _rests(network_id: String) -> bool:
	var token := _lpc().find_token_by_network_id(network_id)
	if token == null or not token.visible or token.get_dragging_object() == null:
		return false
	var settle := token.get_dragging_object().get("_settle_tween") as Tween
	if settle != null and settle.is_valid() and settle.is_running():
		return false
	var rest := TokenGrounding.resting_position(
		token, TokenGrounding.cast_top(_lpc().get_game_map())
	)
	return (
		rest != Vector3.INF
		and absf(rest.y - token.rigid_body.global_position.y) <= GROUND_TOLERANCE_M
	)


## Once the raise is logged and settled and Bystander A has landed, the GM moves it to
## MOVED_TO; then table A is what the session made of it.
func _host_edit_table_a() -> void:
	var edits := _lpc().live_edits
	var bystander := _lpc().find_token_by_network_id(_token_a)
	if edits.op_log.size() < 1 or not edits.is_settled() or not _rests(_token_a):
		return
	var cast_top := TokenGrounding.cast_top(_lpc().get_game_map())
	var to := Vector3(MOVED_TO.x, edits.editor.ground_height_at(MOVED_TO), MOVED_TO.z)
	bystander.set_transform_immediate(
		to, bystander.rigid_body.global_rotation, bystander.rigid_body.scale
	)
	TokenGrounding.reground(bystander, cast_top)
	GameState.sync_from_board_token(bystander)
	bystander.transform_changed.emit()
	_edit_y = edits.editor.ground_height_at(RAISE_AT)
	_result["table_a"]["edit_y"] = _edit_y
	_result["table_a"]["changes"] = _mover().changes()
	_log("table A edited: raised to %.3f, %s" % [_edit_y, str(_result.table_a.changes)])
	_set_phase("table_a")


## Return everyone to the room, as the notice's end does: table A's state is kept (Keep).
func _host_return_to_room() -> void:
	if not await _mover().move_now(TableMover.ROOM):
		_finish(false, "the move to the room was refused")
		return
	var members := NetworkManager.session.party.get_members()
	var kept := _mover().states.entry_for(TABLE_A.folder)
	var kept_names: Array = (kept.get("placements", []) as Array).map(
		func(p: Dictionary) -> String: return str(p.token_name)
	)
	_result["room"] = {
		"state_room": _state() == STATE_ROOM,
		"tokens_in_gamestate": GameState.get_token_count(),
		"level_folder_served": NetworkManager.get_current_level_folder(),
		"game_in_progress": NetworkManager.is_game_in_progress(),
		"session_open": NetworkManager.session.is_open(),
		"table": NetworkManager.session.get_table(),
		"party": members.map(func(m: Dictionary) -> String: return str(m.state.network_id)),
		"party_owners": members[0].owners if members.size() == 1 else [],
		"kept_names": kept_names,
		"kept_ops": (kept.get("op_log", []) as Array).size(),
	}
	_log("returned to the room: %s" % str(_result.room))
	_set_phase("room")


## True once Hero A is on the table, set down and shown (SessionParty grounds it a physics
## frame after the load).
func _hero_landed() -> bool:
	var token := _lpc().find_token_by_network_id(_hero)
	return token != null and token.visible


func _host_check_table_b() -> void:
	var lpc := _lpc()
	var hero := lpc.find_token_by_network_id(_hero)
	var rest := TokenGrounding.resting_position(hero, TokenGrounding.cast_top(lpc.get_game_map()))
	var at := hero.rigid_body.global_position
	var camera_point := SessionParty.camera_ground_point(lpc.get_game_map())
	var placed_names := lpc.active_level_data.token_placements.map(
		func(p: TokenPlacement) -> String: return p.token_name
	)
	var saved_path := lpc.save_level()
	var saved := LevelManager.load_level(saved_path, false) if saved_path != "" else null
	var saved_names := (
		saved.token_placements.map(func(p: TokenPlacement) -> String: return p.token_name)
		if saved != null
		else []
	)
	_result["table_b"] = {
		"table": NetworkManager.session.get_table(),
		"shelf": _shelf_folders(),
		"session_open": NetworkManager.session.is_open(),
		"token_a_in_gamestate": GameState.get_token_state(_token_a) != null,
		"token_b_in_gamestate": GameState.get_token_state(_token_b) != null,
		"hero_in_gamestate": GameState.get_token_state(_hero) != null,
		"hero_peers": GameState.get_peers_with_permission(_hero, CONTROL),
		"hero_at": [at.x, at.y, at.z],
		"hero_rest_off_m": at.distance_to(rest) if rest != Vector3.INF else -1.0,
		"hero_from_camera_point_m": Vector2(at.x, at.z).distance_to(
			Vector2(camera_point.x, camera_point.z)
		),
		"placed_names": placed_names,
		"saved_path": saved_path,
		"saved_names": saved_names,
		"grants": NetworkManager.session.party.get_grants(),
	}
	_log("table B: %s" % str(_result.table_b))


## The drawer's Move the table here, back to table A. Table B is saved and the party is not
## the map's, so nothing changed: no prompt, only the notice.
func _host_move_back() -> void:
	var changes := _mover().changes()
	_result["changes_at_b"] = changes
	if changes.values().has(true):
		_finish(false, "table B counted as changed: %s" % str(changes))
		return
	_mover().request_move(TABLE_A.folder)
	var notice := _mover().get_node_or_null("TableMoveNotice") as TableMoveNotice
	_result["host_notice"] = notice.shown_text() if notice != null else ""
	_result["prompted"] = _mover().is_moving() and notice == null
	_set_phase("a2_load")


## Table A again, as the session left it: Bystander A where it was moved, the raised ground
## and its op, the template's placements as the baseline (the table still differs from it).
func _host_check_table_a2() -> void:
	var a := _table_a_now()
	if not bool(a.settled):
		return
	_result["table_a2"] = a
	_result["table_a2"]["changes"] = _mover().changes()
	_result["table_a2"]["table"] = NetworkManager.session.get_table()
	_log("table A again: %s" % str(_result.table_a2))
	_set_phase("table_a2")


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
	_result["rejoined"] = _read_json("%s.%s.rejoined" % [_rv, LEAVER])
	_result["room_code_end"] = NetworkManager.room_code
	_result["same_peer"] = (
		multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer.get_instance_id() == _peer_instance
	)
	_result["players_end"] = NetworkManager.get_player_count()
	_result["session_players"] = NetworkManager.session.get_players()
	_result["hero_peers_end"] = GameState.get_peers_with_permission(_hero, CONTROL)
	_result["states"] = _states
	var leaver_peer := int(_peer_by_role.get(LEAVER, -1))
	var leaver_grant := {_leaver_id(): [_hero]}
	var table_a: Dictionary = _result.get("table_a", {})
	var room: Dictionary = _result.get("room", {})
	var table_b: Dictionary = _result.get("table_b", {})
	var table_a2: Dictionary = _result.get("table_a2", {})
	var on_leave: Dictionary = _result.get("on_leave", {})
	var unchanged := {"tokens": false, "look": false, "terrain": false}
	var checks := {
		"session_open_at_start": bool(_result.get("session_open_at_start", false)),
		"same_peer": bool(_result.same_peer),
		"same_room_code": _result.room_code_end == _result.room_code_start,
		"states": _states == [STATE_ROOM, STATE_PLAYING, STATE_ROOM, STATE_PLAYING],
		"unchanged_at_set_out": _result.get("changes_at_set_out") == unchanged,
		"hero_adopted_at_a":
		(
			not bool(table_a.get("hero_placed", true))
			and bool(table_a.get("bystander_placed"))
			and table_a.get("grants") == leaver_grant
		),
		"a_changed":
		table_a.get("changes") == {"tokens": true, "look": false, "terrain": true},
		"room_cleared":
		(
			bool(room.get("state_room"))
			and int(room.get("tokens_in_gamestate", -1)) == 0
			and room.get("level_folder_served") == ""
			and not bool(room.get("game_in_progress", true))
			and bool(room.get("session_open"))
			and room.get("table") == ""
		),
		"party_taken": room.get("party") == [_hero] and room.get("party_owners") == [_leaver_id()],
		"a_kept_without_party":
		room.get("kept_names") == [BYSTANDER] and int(room.get("kept_ops", -1)) == 1,
		"table_b":
		(
			table_b.get("table") == TABLE_B.folder
			and table_b.get("shelf") == [TABLE_A.folder, TABLE_B.folder]
			and not bool(table_b.get("session_open", true))
			and not bool(table_b.get("token_a_in_gamestate", true))
			and bool(table_b.get("token_b_in_gamestate"))
		),
		"hero_travelled":
		(
			bool(table_b.get("hero_in_gamestate"))
			and table_b.get("hero_peers") == [leaver_peer]
			and table_b.get("grants") == leaver_grant
		),
		"hero_grounded":
		(
			float(table_b.get("hero_rest_off_m", -1.0)) >= 0.0
			and float(table_b.get("hero_rest_off_m", -1.0)) <= GROUND_TOLERANCE_M
		),
		"hero_not_saved":
		(
			HERO not in table_b.get("placed_names", [HERO])
			and str(table_b.get("saved_path", "")) != ""
			and HERO not in table_b.get("saved_names", [HERO])
			and "Hero B" in table_b.get("saved_names", [])
		),
		"b_unchanged": _result.get("changes_at_b") == unchanged,
		"move_noticed":
		(
			not bool(_result.get("prompted", true))
			and _result.get("host_notice", "") == "Moving the table to %s in 3" % TABLE_A.name
		),
		"a_restored":
		(
			_restored(table_a2, _edit_y)
			and _edit_y > float(_result.get("ground_before_y", 0.0)) + 0.1
			and table_a2.get("table") == TABLE_A.folder
			and table_a2.get("changes") == {"tokens": true, "look": false, "terrain": true}
		),
		"leaver_kept_on_leave":
		(
			int(on_leave.get("peer", -1)) == 0
			and on_leave.get("grants") == leaver_grant
			and (on_leave.get("hero_peers", [0]) as Array).is_empty()
		),
		"leaver_rejoined":
		(
			_rejoined_peer > 0
			and _rejoined_peer != leaver_peer
			and int(_result.players_end) == 5
			and _result.session_players.size() == 5
			and NetworkManager.session.peer_for(_leaver_id()) == _rejoined_peer
			and _result.hero_peers_end == [_rejoined_peer]
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
	if host_phase == "done" and _phase != "leaving":
		_finish(false, "the host finished before this client reported (phase %s)" % _phase)
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
			_client_at_table_a()
		"wait_room":
			if _state() == STATE_ROOM:
				_client_in_room()
		"table_b":
			# After the host has checked and saved table B (the leaver leaves on reporting).
			if host_phase != "table_b":
				return
			if _table_up(TABLE_B) and _on_board(_token("token_b")) and _on_board(_token("hero")):
				if _role != LEAVER or _controls(_token("hero")):
					_client_report_b()
		"wait_rejoin":
			if _has("host", "leaver_left"):
				_join_session()
		"rejoining":
			if _table_up(TABLE_B) and _on_board(_token("hero")) and _controls(_token("hero")):
				_client_rejoined()
			elif Engine.get_process_frames() % 300 == 0:
				_log(
					"rejoining: table %s, hero %s on board %s, controls %s"
					% [
						_table_up(TABLE_B),
						_token("hero"),
						_on_board(_token("hero")),
						_controls(_token("hero"))
					]
				)
		"table_a2":
			_client_at_table_a2(host_phase)


func _token(key: String) -> String:
	return str(_read_json(_rv + ".host.json").get(key, ""))


func _may_join(host_phase: String) -> bool:
	match _role:
		"client", "client2":
			return host_phase == "room_start"
		"client3":
			return host_phase == "room"
		"client4":
			return host_phase == "table_a2"
	return false


## Joins (or, for the leaver, rejoins) through the join screen over the title, connecting
## over ENet as its Connect would over Steam, with the role as the session key. Root moves on
## when the host places this client.
func _join_session() -> void:
	_main.call("_on_join_game_requested")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", int(_args.get("port", DEFAULT_PORT)))
	if err != OK:
		_finish(false, "create_client failed: %d" % err)
		return
	NetworkManager.set_player_name(_role)
	var info: Dictionary = NetworkManager.get("_local_player_info")
	info["role"] = NetworkManager.PlayerRole.PLAYER
	info[SessionChannel.SESSION_KEY] = _role
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.CONNECTING)
	if not _client_signals_connected:
		_client_signals_connected = true
		NetworkManager.connection_state_changed.connect(_on_client_connection_state)
		NetworkManager.session.room_opened.connect(func(): _log("room_opened in " + _phase))
		NetworkManager.session.table_moving.connect(_on_table_moving)
		GameState.state_reset.connect(func(): _log("GameState reset in " + _phase))
	multiplayer.multiplayer_peer = peer
	if _phase == "wait_rejoin":
		_set_phase("rejoining")
		return
	match _role:
		"client", "client2":
			_set_phase("wait_room0")
		"client3":
			_set_phase("wait_room")
		_:
			_set_phase("table_a2")


## The host announced a move: the chip this client's TableMover shows for it (a player's,
## naming the GM and the destination).
func _on_table_moving(kind: int, map_name: String, seconds: float) -> void:
	var notice := _mover().get_node_or_null("TableMoveNotice") as TableMoveNotice
	_notice_text = notice.shown_text() if notice != null else ""
	_log("notice %d %s: %s (%.1f s) in %s" % [kind, map_name, _notice_text, seconds, _phase])


func _on_client_connection_state(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state == NetworkManager.ConnectionState.JOINED and _unique_id == 0:
		_unique_id = multiplayer.get_unique_id()
		_log("joined as peer %d" % _unique_id)
	elif new_state == NetworkManager.ConnectionState.OFFLINE and _phase != "leaving":
		_offline_events += 1
		_log("went offline in phase " + _phase)


## Table A is up with both tokens; client waits for its CONTROL of Hero A to arrive.
func _client_at_table_a() -> void:
	var hero := _token("hero")
	if not (_table_up(TABLE_A) and _on_board(hero) and _on_board(_token("token_a"))):
		return
	if _role == LEAVER and not _controls(hero):
		return
	_result["control_at_a"] = _controls(hero)
	_mark("table_a")
	_set_phase("wait_room")


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


func _client_report_b() -> void:
	var token_a := _token("token_a")
	var hero := _token("hero")
	_result["unique_id"] = multiplayer.get_unique_id()
	_result["offline_events"] = _offline_events
	_result["states"] = _states.duplicate()
	_result["token_a_gone"] = (
		GameState.get_token_state(token_a) == null and not _on_board(token_a)
	)
	_result["hero_travelled"] = GameState.get_token_state(hero) != null and _on_board(hero)
	_result["hero_control"] = _controls(hero)
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
	}
	var owner := _role == LEAVER
	var checks := {
		"same_peer_id": _unique_id != 0 and _result.unique_id == _unique_id,
		"never_offline": _offline_events == 0,
		"states": _states == expected_states[_role],
		"token_a_gone": bool(_result.token_a_gone),
		"hero_travelled": bool(_result.hero_travelled),
		"hero_control": bool(_result.hero_control) == owner,
		"control_at_a":
		_role not in START_CLIENTS or bool(_result.get("control_at_a", not owner)) == owner,
		"session_table": _result.session_table == TABLE_B.folder,
		"shelf": _result.shelf == [TABLE_A.folder, TABLE_B.folder],
		"room": room_ok,
		"join_screen_freed": _main.get("_join_screen") == null,
	}
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_result["pass"] = ok
	_log("table B: %s" % str(checks))
	_mark("b", _result)
	if _role == LEAVER:
		_leave()
	else:
		_set_phase("table_a2")


## Leave from the table the way the pause menu's Return to Title does, and count the
## confirmation dialogs left open (a voluntary leave used to open "connection lost"). The
## leaver rejoins once the host has seen it go.
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
	_result["pass"] = (
		bool(_result.get("pass", false)) and dialogs.is_empty() and _state() == STATE_TITLE
	)
	_set_phase("wait_rejoin")


## Back at table B under a new peer id, controlling Hero A again.
func _client_rejoined() -> void:
	var rejoined := {
		"old_id": _unique_id,
		"new_id": multiplayer.get_unique_id(),
		"controls": _controls(_token("hero")),
		"state": _state(),
	}
	var ok: bool = rejoined.new_id != rejoined.old_id and bool(rejoined.controls)
	_result["rejoined"] = rejoined
	_result["pass"] = bool(_result.get("pass", false)) and ok
	_log("rejoined: %s" % str(rejoined))
	_mark("rejoined", rejoined)
	_set_phase("table_a2")


## Table A again, as the session left it: once the host has it up (host phase table_a2) and
## this peer's table matches it, or RESTORE_FRAMES later with what this peer has. client4
## joins here (a late joiner) and never saw table B or the room.
func _client_at_table_a2(host_phase: String) -> void:
	if host_phase not in ["table_a2", "collect", "done"]:
		return
	if not (_table_up(TABLE_A) and _on_board(_token("hero"))):
		return
	var edit_y := float(_read_json(_rv + ".host.json").get("edit_y", 0.0))
	var a := _table_a_now()
	_restore_frames += 1
	if not (bool(a.settled) and _restored(a, edit_y)) and _restore_frames < RESTORE_FRAMES:
		return
	var late := _role == "client4"
	var checks := {
		"a_restored": bool(a.settled) and _restored(a, edit_y),
		"hero_at_a": GameState.get_token_state(_token("hero")) != null,
		"hero_control": _controls(_token("hero")) == (_role == LEAVER),
		"session_table": NetworkManager.session.get_table() == TABLE_A.folder,
		"notice":
		(
			late
			or (
				_notice_text.ends_with(" is moving the table to %s in 3" % TABLE_A.name)
				and not _notice_text.begins_with(TableMoveNotice.SOMEONE)
			)
		),
	}
	if late:
		checks["states"] = _states == [STATE_PLAYING]
		checks["never_offline"] = _offline_events == 0
	_result["table_a2"] = a
	_result["a2_checks"] = checks
	var ok := late or bool(_result.get("pass", false))
	for key in checks:
		ok = ok and bool(checks[key])
	_result["pass"] = ok
	_log("table A again: %s %s" % [str(a), str(checks)])
	_mark("json", _result)
	_set_phase("wait_done")
