extends Node
## Real-Steam regression scenario: a client downloads a level's map.glb from the host.
##
## Not part of the GUT suite: it needs the Steam client and a second Steam account, so two
## processes run it, one per role. The host runs unsandboxed under the main account; the
## client runs in the Sandboxie box that holds the alt account (docs/NETWORKING.md, "Testing
## over real Steam"). Both use the game's own NetworkManager, AssetStreamer and
## MapDownloadCoordinator; only the level state machine is left out, so the scenario
## measures the transfer alone.
##
## Host: copies --source into user://levels/<--level>/map.glb (the folder must start with
## "_nettest_" and is deleted at the end), hosts, writes the room code to --rendezvous, and
## broadcasts the level once the client has joined. It finishes when the client leaves.
## Client: drops any cached copy of that map, joins with the room code, and lets the
## coordinator download the map; it then checks the file's SHA-256 against the hash the
## host sent, leaves, and drops the cached copy again.
##
## Args after `--`: --role=host|client --rendezvous=<abs path> --out=<abs path>
##   --timeout-s=<n> (default 300) --send-rate-min=<bytes/s> --send-rate-max=<bytes/s>
##   (default: the game's SteamNetConfig rates; 0 keeps Steam's default for that setting)
##   --level=<_nettest_ folder> --source=<res:// or absolute GLB path>
## Each run writes its log and one final `NET_RESULT {json}` line to --out and stdout,
## then quits with exit code 0 (pass) or 1 (fail).

const APP_ID := 480
const LEVEL_PREFIX := "_nettest_"
const DEFAULT_LEVEL := "_nettest_map"
const DEFAULT_SOURCE := "res://assets/models/maps/oakslabpainted.glb"
## Leave time for Steam to deliver the disconnect before the process exits.
const QUIT_DELAY_S := 1.0

var _args: Dictionary = {}
var _role := ""
var _level := DEFAULT_LEVEL
var _out: FileAccess
var _start_ms := 0
var _result: Dictionary = {}
var _finished := false
var _rendezvous_path := ""

# Host state.
var _broadcast_done := false

# Client state.
var _joining := false
var _coordinator: MapDownloadCoordinator
var _download_key := ""
var _download_start_ms := -1
var _expected_hash := ""
var _last_status: Dictionary = {}


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_parse_args()
	_role = str(_args.get("role", ""))
	_level = str(_args.get("level", DEFAULT_LEVEL))
	_rendezvous_path = str(_args.get("rendezvous", ""))
	var out_path := str(_args.get("out", ""))
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		_out = FileAccess.open(out_path, FileAccess.WRITE)
	_result["role"] = _role
	_result["level"] = _level
	get_tree().create_timer(float(_args.get("timeout-s", "300"))).timeout.connect(_on_hard_timeout)
	_log("scenario start role=%s" % _role)
	if not _level.begins_with(LEVEL_PREFIX):
		_finish(false, "level folder must start with " + LEVEL_PREFIX)
		return
	if not _init_steam():
		_finish(false, "steam init failed")
		return
	_apply_send_rate()
	match _role:
		"host":
			_start_host()
		"client":
			_start_client()
		_:
			_finish(false, "unknown role")


func _process(_delta: float) -> void:
	if _joining:
		_poll_rendezvous()


# --- Setup -------------------------------------------------------------------


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--"):
			var eq := s.find("=")
			if eq > 0:
				_args[s.substr(2, eq - 2)] = s.substr(eq + 1)
			else:
				_args[s.substr(2)] = "true"


func _log(msg: String) -> void:
	var line := "[%7d ms] %s" % [Time.get_ticks_msec() - _start_ms, msg]
	print(line)
	if _out:
		_out.store_line(line)
		_out.flush()


## Steam looks for steam_appid.txt in the working directory, which agent runs do not
## have, so the scenario initialises Steam itself with the test app id and tells
## NetworkManager it is ready (NetworkManager then runs the callbacks every frame).
func _init_steam() -> bool:
	var init: Dictionary = Steam.steamInitEx(APP_ID, false)
	_log("steamInitEx -> %s" % str(init))
	if int(init.get("status", -1)) != 0:
		return false
	NetworkManager.set("_steam_initialized", true)
	_result["steam_id"] = str(Steam.getSteamID())
	return true


## Applies the send rates before any connection exists: the game's (SteamNetConfig, as
## NetworkManager does) unless --send-rate-min / --send-rate-max name others in bytes per
## second, where 0 keeps Steam's default for that setting.
func _apply_send_rate() -> void:
	var rate_min := int(_args.get("send-rate-min", str(SteamNetConfig.SEND_RATE_MIN)))
	var rate_max := int(_args.get("send-rate-max", str(SteamNetConfig.SEND_RATE_MAX)))
	var ok := SteamNetConfig.apply_send_rates(rate_min, rate_max)
	_result["send_rate_min"] = rate_min
	_result["send_rate_max"] = rate_max
	_log("send rates min=%d max=%d applied=%s" % [rate_min, rate_max, str(ok)])


# --- Host --------------------------------------------------------------------


func _start_host() -> void:
	if not _prepare_level():
		_finish(false, "could not prepare the test level")
		return
	if _rendezvous_path != "" and FileAccess.file_exists(_rendezvous_path):
		DirAccess.remove_absolute(_rendezvous_path)
	NetworkManager.room_code_received.connect(_on_room_code)
	NetworkManager.player_joined.connect(_on_host_player_joined)
	NetworkManager.player_left.connect(_on_host_player_left)
	NetworkManager.connection_failed.connect(func(reason: String): _finish(false, reason))
	NetworkManager.host_game()


## Copies the source GLB into the test level folder; never touches any other level.
func _prepare_level() -> bool:
	var source := str(_args.get("source", DEFAULT_SOURCE))
	var data := FileAccess.get_file_as_bytes(source)
	if data.is_empty():
		_log("cannot read source " + source)
		return false
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(_level))
	var file := FileAccess.open(Paths.get_level_map_path(_level), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()
	_result["map_bytes"] = data.size()
	_result["map_compressed_bytes"] = data.compress(FileAccess.COMPRESSION_ZSTD).size()
	_log("level %s prepared from %s (%d bytes)" % [_level, source, data.size()])
	return true


func _on_room_code(code: String) -> void:
	_log("room code " + code)
	if _rendezvous_path != "":
		var f := FileAccess.open(_rendezvous_path, FileAccess.WRITE)
		f.store_string(code)
		f.close()


func _on_host_player_joined(peer_id: int, _info: Dictionary) -> void:
	if peer_id == 1 or _broadcast_done:
		return
	_broadcast_done = true
	var level_dict := {"level_name": "Net test", "level_folder": _level, "map_path": "map.glb"}
	NetworkManager.broadcast_level_data(level_dict)
	var hashes: Dictionary = NetworkManager.with_map_hashes(level_dict).get(
		MapFileHash.HASHES_KEY, {}
	)
	_result["host_hash"] = hashes.get(Paths.LEVEL_MAP_VARIANT, "")
	_result["broadcast_ms"] = Time.get_ticks_msec() - _start_ms
	_log("peer %d joined; level broadcast" % peer_id)


func _on_host_player_left(peer_id: int, _info: Dictionary) -> void:
	_log("peer %d left" % peer_id)
	_finish(_broadcast_done, "client left")


func _remove_level() -> void:
	var folder := Paths.get_level_folder(_level)
	if not _level.begins_with(LEVEL_PREFIX) or not DirAccess.dir_exists_absolute(folder):
		return
	var dir := DirAccess.open(folder)
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(folder)
	MapFileHash.invalidate(Paths.get_level_map_path(_level))


# --- Client ------------------------------------------------------------------


func _start_client() -> void:
	_drop_cached_map()
	NetworkManager.level_data_received.connect(_on_level_data)
	NetworkManager.connection_failed.connect(func(reason: String): _finish(false, reason))
	_joining = true


func _drop_cached_map() -> void:
	AssetManager.cache.remove_cached(
		Paths.LEVEL_MAPS_PACK_ID, _level, Paths.LEVEL_MAP_VARIANT, "model"
	)


func _poll_rendezvous() -> void:
	if _rendezvous_path == "" or not FileAccess.file_exists(_rendezvous_path):
		return
	var code := FileAccess.get_file_as_string(_rendezvous_path).strip_edges()
	if code == "":
		return
	_joining = false
	_log("joining room " + code)
	NetworkManager.join_game(code)


func _on_level_data(level_dict: Dictionary) -> void:
	if _coordinator != null:
		return
	var level := LevelData.from_dict(level_dict)
	_expected_hash = level.map_hashes.get(Paths.LEVEL_MAP_VARIANT, "")
	_result["expected_hash"] = _expected_hash
	_coordinator = MapDownloadCoordinator.new()
	_coordinator.setup(_check_downloaded_map, func(map: Node3D): map.free())
	_coordinator.connect_asset_streamer()
	_coordinator.map_download_failed.connect(
		func(_folder: String, error: String): _finish(false, "download failed: " + error)
	)
	_download_key = (
		"%s/%s/%s/model" % [Paths.LEVEL_MAPS_PACK_ID, level.level_folder, Paths.LEVEL_MAP_VARIANT]
	)
	AssetManager.streamer.transfer_progress.connect(_on_transfer_progress)
	_download_start_ms = Time.get_ticks_msec()
	_log("level data for %s; requesting the map" % level.level_folder)
	if not _coordinator.request_map_download(level.level_folder):
		_finish(false, "request_map_download refused")


## Records the streamer's counts after every chunk (the streamer forgets the download
## once it completes).
func _on_transfer_progress(
	_pack_id: String, _asset_id: String, _variant_id: String, _progress: float, _type: String
) -> void:
	var status: Dictionary = AssetManager.streamer.get_download_status(_download_key)
	if not status.is_empty():
		_last_status = status


## Stands in for the loader: checks the downloaded file instead of building the map.
func _check_downloaded_map(glb_path: String, _document_path: String) -> Node3D:
	var digest := MapFileHash.hash_file(glb_path)
	var ok := _expected_hash != "" and digest == _expected_hash
	_result["received_hash"] = digest
	_result["received_file_bytes"] = FileAccess.get_file_as_bytes(glb_path).size()
	_finish(ok, "downloaded" if ok else "hash mismatch")
	return Node3D.new()


# --- Shared ------------------------------------------------------------------


func _on_hard_timeout() -> void:
	_finish(false, "timeout")


func _finish(ok: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_result["pass"] = ok
	_result["reason"] = reason
	_result["elapsed_ms"] = Time.get_ticks_msec() - _start_ms
	if _role == "client":
		_result["chunks_received"] = _last_status.get("received_chunks", 0)
		_result["chunks_expected"] = _last_status.get("total_chunks", 0)
		_result["bytes_received"] = _last_status.get("received_bytes", 0)
		if _download_start_ms >= 0:
			var download_ms := Time.get_ticks_msec() - _download_start_ms
			_result["download_ms"] = download_ms
			var seconds := maxf(download_ms / 1000.0, 0.001)
			_result["kib_per_s"] = snappedf(_result["bytes_received"] / 1024.0 / seconds, 0.1)
	NetworkManager.disconnect_game()
	if _role == "client":
		_drop_cached_map()
	if _role == "host":
		_remove_level()
	_log("NET_RESULT " + JSON.stringify(_result))
	if _out:
		_out.close()
		_out = null
	await get_tree().create_timer(QUIT_DELAY_S).timeout
	get_tree().quit(0 if ok else 1)
