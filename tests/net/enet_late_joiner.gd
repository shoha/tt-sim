extends Node

## ENet check for the late-joiner state hold (LateJoinerSync): a host plays the shipped
## res:// map (no download), places an avatar, and a client joins afterwards. The client
## passes when the avatar is on its board once its table has loaded.
##
## Not part of the GUT suite: two processes run it, one per role, over ENet on 127.0.0.1
## (no Steam), each running the whole game. NetworkManager has no ENet path, so the scenario
## sets its peer and state the way _on_lobby_created / join_game would (adapted from the
## session-room probe's tests/net/enet_session_room.gd).
##
## Run it, and every scenario built on it, through tests/net/net_launcher.gd
## (--scenario=enet_late_joiner), which starts each peer with its own test data root
## (Paths) and passes these args after `--`: --role=host|client
## --rendezvous=<abs path prefix> --out=<abs path> --timeout-s=<n> (default 120)
## --port=<n> (default 28471) --data-root=<name>.
## Each process writes its log and one final `NET_RESULT {json}` line to --out and stdout,
## then quits with exit code 0 (pass) or 1 (fail).

const MAP_SOURCE := "res://assets/models/maps/oakslabpainted.glb"
const LEVEL_NAME := "Late joiner table"
const DEFAULT_PORT := 28471
const QUIT_DELAY_S := 1.0
const STATE_TITLE := 0
const STATE_LOBBY_HOST := 1
const STATE_LOBBY_CLIENT := 2
const STATE_PLAYING := 3

var _args: Dictionary = {}
var _role := ""
var _rv := ""
var _out: FileAccess
var _start_ms := 0
var _result: Dictionary = {}
var _finished := false
var _main: Node = null
var _phase := "boot"
var _avatar_id := ""


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		var eq := s.find("=")
		if s.begins_with("--") and eq > 0:
			_args[s.substr(2, eq - 2)] = s.substr(eq + 1)
	_role = str(_args.get("role", ""))
	_rv = str(_args.get("rendezvous", ""))
	var out_path := str(_args.get("out", ""))
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		_out = FileAccess.open(out_path, FileAccess.WRITE)
	_result["role"] = _role
	get_tree().create_timer(float(_args.get("timeout-s", "120"))).timeout.connect(
		func(): _finish(false, "timeout in phase " + _phase)
	)
	_log("scenario start role=%s" % _role)
	var main_scene := load(str(ProjectSettings.get_setting("application/run/main_scene")))
	_main = (main_scene as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_set_phase("title")


func _process(_delta: float) -> void:
	if _finished or _main == null or not _main.is_inside_tree():
		return
	if get_tree().current_scene != _main:
		get_tree().current_scene = _main
	if _role == "host":
		_process_host()
	else:
		_process_client()


func _log(msg: String) -> void:
	var line := "[%7d ms] %s" % [Time.get_ticks_msec() - _start_ms, msg]
	print(line)
	if _out:
		_out.store_line(line)
		_out.flush()


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(_rv + ".host.json", {"phase": phase, "avatar": _avatar_id})


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _state() -> int:
	return int(_main.call("get_current_state"))


func _lpc() -> LevelPlayController:
	return _main.get("_level_play_controller") as LevelPlayController


func _table_ready() -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_name == LEVEL_NAME
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
	)


func _finish(ok: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_result["pass"] = ok
	_result["reason"] = reason
	_result["elapsed_ms"] = Time.get_ticks_msec() - _start_ms
	if _role == "host":
		_set_phase("done")
		await get_tree().create_timer(QUIT_DELAY_S * 2).timeout
	NetworkManager.disconnect_game()
	_log("NET_RESULT " + JSON.stringify(_result))
	if _out:
		_out.close()
		_out = null
	await get_tree().create_timer(QUIT_DELAY_S).timeout
	get_tree().quit(0 if ok else 1)


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_start_host()
		"table_load":
			if _table_ready():
				_host_place_avatar()
		"table":
			var client := _read_json(_rv + ".client.json")
			if not client.is_empty():
				_result["client"] = client
				_finish(bool(client.get("pass", false)), "client reported")


func _start_host() -> void:
	if FileAccess.file_exists(_rv + ".client.json"):
		DirAccess.remove_absolute(_rv + ".client.json")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(_args.get("port", DEFAULT_PORT)), 8)
	if err != OK:
		_finish(false, "create_server failed: %d" % err)
		return
	# What NetworkManager._on_lobby_created does once a Steam lobby exists.
	var info: Dictionary = NetworkManager.get("_local_player_info")
	info["role"] = NetworkManager.PlayerRole.GM
	NetworkManager.set_player_name("host")
	multiplayer.multiplayer_peer = peer
	(NetworkManager.get("_players") as Dictionary)[1] = info.duplicate()
	NetworkManager.set("_room_code", "ENET02")
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.HOSTING)
	NetworkManager.table_loaded.connect(func(p: int): _log("table_loaded from peer %d" % p))
	NetworkManager.late_joiner_connected.connect(
		func(p: int): _log("late_joiner_connected %d (state sent)" % p)
	)
	_main.set(
		"_pending_level_data",
		LevelData.from_dict({"level_name": LEVEL_NAME, "map_path": MAP_SOURCE})
	)
	_main.call("change_state", STATE_LOBBY_HOST)
	_main.call("_on_lobby_start_game")
	_set_phase("table_load")


func _host_place_avatar() -> void:
	var token := _lpc().spawn_avatar({"format": 1}, "Late Hero", Vector3.UP * 30, true)
	if token == null:
		_finish(false, "avatar spawn failed")
		return
	_avatar_id = token.network_id
	_result["avatar_id"] = _avatar_id
	_log("avatar %s placed; game in progress, client may join" % _avatar_id)
	_set_phase("table")


func _process_client() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_set_phase("wait_to_join")
		"wait_to_join":
			if _read_json(_rv + ".host.json").get("phase", "") == "table":
				_join()
		"joined":
			_client_check()


func _join() -> void:
	_main.call("change_state", STATE_LOBBY_CLIENT)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", int(_args.get("port", DEFAULT_PORT)))
	if err != OK:
		_finish(false, "create_client failed: %d" % err)
		return
	# What NetworkManager.join_game and _on_lobby_joined do around the Steam lobby.
	NetworkManager.set_player_name("client")
	(NetworkManager.get("_local_player_info") as Dictionary)["role"] = (
		NetworkManager.PlayerRole.PLAYER
	)
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.CONNECTING)
	NetworkStateSync.full_state_received.connect(
		func(_s: Dictionary):
			_log(
				(
					"full state received: %d tokens, loading=%s"
					% [GameState.get_token_count(), str(_lpc().is_loading())]
				)
			)
	)
	GameState.state_reset.connect(func(): _log("GameState reset"))
	multiplayer.multiplayer_peer = peer
	_set_phase("joined")


func _client_check() -> void:
	var avatar_id := str(_read_json(_rv + ".host.json").get("avatar", ""))
	if avatar_id == "" or not _table_ready():
		return
	var token := _lpc().find_token_by_network_id(avatar_id)
	if token == null:
		return
	_result["avatar_on_board"] = token.is_avatar()
	_result["avatar_in_gamestate"] = GameState.get_token_state(avatar_id) != null
	_result["pass"] = token.is_avatar()
	_log("avatar %s on the board" % avatar_id)
	_write_json(_rv + ".client.json", _result)
	_finish(token.is_avatar(), "avatar seen")
