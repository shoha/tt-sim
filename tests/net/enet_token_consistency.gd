extends "res://tests/net/enet_late_joiner.gd"

## ENet checks that a client ends with exactly the host's tokens, in the three cases the
## netspawn token wire left unverified (topic netverify): a lost reconciliation healed by the
## full-state heartbeat, a join in the middle of a placement burst, and a leave and rejoin in
## the middle of a session. Each is a mode (--opts=mode=heal|burst|reconnect), two peers, on
## enet_late_joiner's shipped res:// table (no download). Every peer's ENet peer is wrapped in
## the CountingPeer (tests/net/counting_peer.gd), whose loss play drops one message in heal.
##
## The host publishes its tokens in its rendezvous file (network_id -> board position) when it
## asks for a check; the client compares its own board (the BoardTokens under the map's drag
## node, so a token built twice shows) and GameState with it: missing, extra and duplicated
## ids, and positions further than TOLERANCE_M. The client reports in rv.client.json and the
## host finishes with the client's verdict.
##
## heal: the host places HEAL_TOKENS avatars; once the client has them, the client arms
##   drop_next for one _rpc_receive_reconcile; the host moves every token on its board
##   without a drag (so only the next reconciliation carries the move), at least three ticks
##   before a heartbeat; the client checks that the move did not arrive (every token off),
##   then waits for the heartbeat's full state and checks that every token is in place.
## burst: the host places BURST_TOKENS avatars at BURST_PER_S; the client joins when
##   BURST_JOIN_AT are down, so its join, table build and state hold all run inside the
##   burst; checked once the burst has settled.
## reconnect: the host places RECONNECT_TOKENS, the client joins and checks, then leaves
##   (Pause > Main menu, as a player does); while it is away the host removes two tokens,
##   adds three and moves two; the client joins again and checks.
##
## Run (headless; a worktree with its own user folder, a port of its own; one run per mode):
##   godot --headless --path <worktree> res://tests/net/net_launcher.tscn --
##     --data-root=net_launcher --scenario=enet_token_consistency --peers=2 --timeout-s=150
##     --port=28631 --opts=mode=heal

const CountingPeer := preload("res://tests/net/counting_peer.gd")
const RECONCILE := "_rpc_receive_reconcile"
const TOLERANCE_M := 0.05
const SETTLE_S := 3.0
## After a check is asked for: one reconciliation tick (2 s) plus the interpolation
const CHECK_DELAY_S := 3.0
const HEAL_TOKENS := 6
const HEAL_MOVE := Vector3(2.5, 0.0, 0.0)
const BURST_TOKENS := 100
const BURST_PER_S := 20.0
const BURST_JOIN_AT := 10
const RECONNECT_TOKENS := 8

var _mode := "heal"
var _meter: CountingPeer = null
var _tokens: Array[BoardToken] = []
var _phase_ms := 0
var _burst_ms := 0
var _shared: Dictionary = {}
var _marks: Dictionary = {}
var _full_state_ms := 0
var _check_at_ms := 0


func _ready() -> void:
	super._ready()
	for pair in str(_args.get("opts", "")).split(",", false):
		var kv := pair.split("=")
		if kv[0] == "mode" and kv.size() > 1:
			_mode = kv[1]
	_result["mode"] = _mode
	_log("mode " + _mode)


func _set_phase(phase: String) -> void:
	_phase = phase
	_phase_ms = Time.get_ticks_msec()
	_log("phase " + phase)
	if _role == "host":
		var data := _shared.duplicate()
		data["phase"] = phase
		_write_json(_rv + ".host.json", data)


func _since_phase_s() -> float:
	return (Time.get_ticks_msec() - _phase_ms) / 1000.0


func _host() -> Dictionary:
	return _read_json(_rv + ".host.json")


func _mark(key: String, value: Variant = true) -> void:
	_marks[key] = value
	_write_json(_rv + ".marks.json", _marks)


func _client_marks() -> Dictionary:
	return _read_json(_rv + ".marks.json")


func _wrap(peer: MultiplayerPeer) -> MultiplayerPeer:
	_meter = CountingPeer.new(peer, get_tree().root)
	return _meter


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	if _phase != "title" and FileAccess.file_exists(_rv + ".client.json"):
		var client := _read_json(_rv + ".client.json")
		_result["client"] = client
		_log_meter()
		_finish(bool(client.get("pass", false)), "client reported")
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_start_host_counted()
		"table_load":
			if _table_ready():
				_host_begin()
		"burst", "burst_join":
			_burst_frame()
		"wait_client":
			if _client_marks().has("ready") and _since_phase_s() >= SETTLE_S:
				_set_phase("arm" if _mode == "heal" else "leave")
		"arm":
			if _client_marks().has("armed") and _heartbeat_far():
				for token in _tokens:
					token.rigid_body.global_position += HEAL_MOVE
				_log("moved %d tokens by %s without a drag" % [_tokens.size(), str(HEAL_MOVE)])
				_set_phase("moved")
		"moved":
			if _since_phase_s() >= CHECK_DELAY_S:
				_publish_check("check_before")
		"check_before":
			# The tokens rest; the snapshot stays valid until the heartbeat check.
			pass
		"burst_done":
			if _client_marks().has("ready") and _since_phase_s() >= SETTLE_S:
				_publish_check("check")
		"leave":
			if _client_marks().has("left") and NetworkManager.get_players().size() <= 1:
				_host_change_while_away()
				_set_phase("rejoin")
		"rejoin":
			if _client_marks().has("ready2") and _since_phase_s() >= SETTLE_S:
				_publish_check("check")


func _start_host_counted() -> void:
	for f in [_rv + ".client.json", _rv + ".marks.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(_args.get("port", DEFAULT_PORT)), 8)
	if err != OK:
		_finish(false, "create_server failed: %d" % err)
		return
	var info: Dictionary = NetworkManager.get("_local_player_info")
	info["role"] = NetworkManager.PlayerRole.GM
	NetworkManager.set_player_name("host")
	multiplayer.multiplayer_peer = _wrap(peer)
	(NetworkManager.get("_players") as Dictionary)[1] = info.duplicate()
	NetworkManager.set("_room_code", "ENETTC")
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.HOSTING)
	NetworkManager.late_joiner_connected.connect(
		func(p: int): _log("late_joiner_connected %d (state sent)" % p)
	)
	NetworkManager.player_left.connect(func(p: int): _log("player_left %d" % p))
	_main.set(
		"pending_level", LevelData.from_dict({"level_name": LEVEL_NAME, "map_path": MAP_SOURCE})
	)
	_main.call("change_state", STATE_ROOM)
	_flow().set_out_pending()
	_set_phase("table_load")


func _host_begin() -> void:
	match _mode:
		"heal":
			if _place(HEAL_TOKENS):
				_set_phase("wait_client")
		"reconnect":
			if _place(RECONNECT_TOKENS):
				_set_phase("wait_client")
		"burst":
			_burst_ms = Time.get_ticks_msec()
			_set_phase("burst")
		_:
			_finish(false, "unknown mode " + _mode)


## Places avatars until `count` are down, on a grid over the flat table. False (the run
## failed) when one does not spawn.
func _place(count: int) -> bool:
	while _tokens.size() < count:
		var i := _tokens.size()
		var at := Vector3((i % 8) * 1.5 - 5.0, 2.0, int(i / 8.0) * 1.5 - 5.0)
		var token := _lpc().spawn_avatar({"format": 1}, "T%d" % i, at, true)
		if token == null:
			_finish(false, "avatar spawn failed at %d" % i)
			return false
		_tokens.append(token)
	return true


func _burst_frame() -> void:
	var due := mini(
		int((Time.get_ticks_msec() - _burst_ms) / 1000.0 * BURST_PER_S) + 1, BURST_TOKENS
	)
	if not _place(due):
		return
	if _phase == "burst" and _tokens.size() >= BURST_JOIN_AT:
		_set_phase("burst_join")
	if _tokens.size() >= BURST_TOKENS:
		_log("burst of %d placed in %d ms" % [BURST_TOKENS, Time.get_ticks_msec() - _burst_ms])
		_set_phase("burst_done")


## True when the next reconciliation tick is at least three ticks before a heartbeat, so the
## tick that carries heal's move is a moved-tokens message, and the check before the heartbeat
## has time to run.
func _heartbeat_far() -> bool:
	var sync: Object = _lpc().get("_network_token_sync")
	var ticks := int(sync.get("_ticks"))
	var left := NetworkTokenSync.HEARTBEAT_TICKS - ticks % NetworkTokenSync.HEARTBEAT_TICKS
	return left >= 4


## While the client is away: two tokens removed, three added, two moved without a drag.
func _host_change_while_away() -> void:
	for i in 2:
		var gone: BoardToken = _tokens.pop_back()
		_lpc().remove_token(gone)
	for i in 2:
		_tokens[i].rigid_body.global_position += HEAL_MOVE
	var before := _tokens.size()
	_place(before + 3)
	_log("while away: removed 2, moved 2, added 3; %d tokens" % _tokens.size())


func _publish_check(phase: String) -> void:
	var tokens := {}
	for token in _tokens:
		if is_instance_valid(token):
			var p := token.rigid_body.global_position
			tokens[token.network_id] = [p.x, p.y, p.z]
	_shared["tokens"] = tokens
	_set_phase(phase)


func _log_meter() -> void:
	if _meter == null:
		return
	for line in CountingPeer.window_lines(_role, _meter.cut("run")):
		_log(line)
	_log("relays_to_closed %d" % _meter.relays_to_closed)


# =============================================================================
# CLIENT
# =============================================================================


func _process_client() -> void:
	var host := _host()
	var host_phase := str(host.get("phase", ""))
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_set_phase("wait_to_join")
		"wait_to_join":
			if _mode == "burst" and host_phase in ["burst_join", "burst_done", "check"]:
				_result["joined_mid_burst"] = host_phase == "burst_join"
				_join_counted("joined")
			elif _mode != "burst" and host_phase == "wait_client":
				_join_counted("joined")
		"joined":
			if _table_ready() and _board_count() > 0 and not _marks.has("ready"):
				_mark("ready")
			_client_steps(host, host_phase)
		"left":
			if _state() == STATE_TITLE and host_phase == "rejoin":
				_join_counted("joined2")
		"joined2":
			if _table_ready() and _board_count() > 0 and not _marks.has("ready2"):
				_mark("ready2")
			if host_phase == "check":
				_check_final(host, "after_rejoin")


func _client_steps(host: Dictionary, host_phase: String) -> void:
	match _mode:
		"heal":
			if host_phase == "arm" and not _marks.has("armed"):
				_meter.drop_next[RECONCILE] = 1
				_mark("armed")
			elif host_phase == "check_before" and not _result.has("before"):
				if _check_at_ms == 0:
					_check_at_ms = Time.get_ticks_msec()
				var c := _compare(host.get("tokens", {}))
				c["dropped"] = int(_meter.dropped.get(RECONCILE, 0))
				_result["before"] = c
				_full_state_ms = 0
				_log("before the heartbeat: %s" % JSON.stringify(c))
			elif _result.has("before") and _full_state_ms > 0:
				if Time.get_ticks_msec() - _full_state_ms >= 2000:
					_check_heal(host)
		"burst":
			if host_phase == "check":
				_check_final(host, "after_burst")
		"reconnect":
			if host_phase == "leave" and not _marks.has("left"):
				var c := _compare(_own_ids())
				_result["first_join"] = c
				_log("first join: %s" % JSON.stringify(c))
				_main.call("_on_pause_main_menu_requested")
				_mark("left")
				_set_phase("left")


## This client's GameState ids, as a compare() target: the first reconnect check compares the
## board with GameState only (the host publishes no snapshot before the leave).
func _own_ids() -> Dictionary:
	var ids := {}
	for id in GameState.get_all_token_states().keys():
		ids[id] = null
	return ids


func _check_heal(host: Dictionary) -> void:
	var after := _compare(host.get("tokens", {}))
	_result["after"] = after
	_log("after the heartbeat: %s" % JSON.stringify(after))
	var before: Dictionary = _result.before
	var ok := (
		int(before.dropped) == 1
		and int(before.board_off) == HEAL_TOKENS
		and _consistent(after)
		and int(after.board_off) == 0
		and int(after.state_off) == 0
	)
	_report(ok, "healed" if ok else "not healed (see before/after)")


func _check_final(host: Dictionary, label: String) -> void:
	if _check_at_ms == 0:
		_check_at_ms = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _check_at_ms < int(CHECK_DELAY_S * 1000.0):
		return
	var c := _compare(host.get("tokens", {}))
	_result[label] = c
	_log("%s: %s" % [label, JSON.stringify(c)])
	var ok := _consistent(c) and int(c.board_off) == 0 and int(c.state_off) == 0
	if _mode == "reconnect":
		ok = ok and _consistent(_result.get("first_join", {}))
	if _mode == "burst" and not bool(_result.get("joined_mid_burst", false)):
		ok = false
		label += ", but the join was not inside the burst"
	_report(ok, "consistent" if ok else "inconsistent (see %s)" % label)


func _consistent(c: Dictionary) -> bool:
	return (
		not c.is_empty()
		and (c.missing as Array).is_empty()
		and (c.extra as Array).is_empty()
		and (c.duplicates as Array).is_empty()
		and (c.state_missing as Array).is_empty()
		and (c.state_extra as Array).is_empty()
	)


func _report(ok: bool, reason: String) -> void:
	_result["pass"] = ok
	_result["reason"] = reason
	_write_json(_rv + ".client.json", _result)
	_finish(ok, reason)


## The BoardTokens on this client's board (under the map's drag node, not queued for deletion).
func _board_tokens() -> Array[BoardToken]:
	var out: Array[BoardToken] = []
	var game_map: Node = _main.call("get_game_map")
	if game_map == null or game_map.get("drag_and_drop_node") == null:
		return out
	for child in (game_map.get("drag_and_drop_node") as Node).get_children():
		var token := child as BoardToken
		if token != null and not token.is_queued_for_deletion():
			out.append(token)
	return out


func _board_count() -> int:
	return _board_tokens().size()


## This client's board and GameState against the host's `want` (network_id -> [x, y, z], or
## null to compare ids only).
func _compare(want: Dictionary) -> Dictionary:
	var seen := {}
	var board_off := 0
	var state_off := 0
	var max_off := 0.0
	for token in _board_tokens():
		seen[token.network_id] = int(seen.get(token.network_id, 0)) + 1
		var p: Variant = want.get(token.network_id)
		if p is Array:
			var off := token.rigid_body.global_position.distance_to(Vector3(p[0], p[1], p[2]))
			max_off = maxf(max_off, off)
			if off > TOLERANCE_M:
				board_off += 1
	var states := GameState.get_all_token_states()
	for id: String in states:
		var p: Variant = want.get(id)
		if p is Array:
			var s: TokenState = states[id]
			if s.position.distance_to(Vector3(p[0], p[1], p[2])) > TOLERANCE_M:
				state_off += 1
	return {
		"want": want.size(),
		"board": seen.size(),
		"missing": want.keys().filter(func(id: String) -> bool: return not seen.has(id)),
		"extra": seen.keys().filter(func(id: String) -> bool: return not want.has(id)),
		"duplicates": seen.keys().filter(func(id: String) -> bool: return seen[id] > 1),
		"state_missing": want.keys().filter(func(id: String) -> bool: return not states.has(id)),
		"state_extra": states.keys().filter(func(id: String) -> bool: return not want.has(id)),
		"board_off": board_off,
		"state_off": state_off,
		"max_off_m": snappedf(max_off, 0.001),
	}


## Joins in place from the title with the ENet peer counted, then moves to `next_phase`.
func _join_counted(next_phase: String) -> void:
	if not _join_in_place():
		return
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
	if not NetworkStateSync.full_state_received.is_connected(_on_full_state):
		NetworkStateSync.full_state_received.connect(_on_full_state)
	multiplayer.multiplayer_peer = _wrap(peer)
	_set_phase(next_phase)


func _on_full_state(_state: Dictionary) -> void:
	_full_state_ms = Time.get_ticks_msec()
	_log(
		(
			"full state received: %d in GameState, %d on the board"
			% [GameState.get_token_count(), _board_count()]
		)
	)
