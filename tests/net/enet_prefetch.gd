extends "res://tests/net/enet_late_joiner.gd"

## ENet scenario for prefetch from the room (SessionPrefetch): clients fetch the shelf maps
## they lack while they wait in the room, in order, the room shows their progress, and set out
## uses the copy already here.
##
## Four processes, one per role, reuse enet_late_joiner.gd's boot, ENet setup and rendezvous
## files. The host builds three maps with real files in its own test data root: Fen, the
## shipped GLB (about 20 MB) copied into a level folder of its own (map.glb), and Mill and
## Pond, authored flat maps (map.ttmap); and a fourth level, Secret, that it never shelves.
## Each client reports its role as its session key (SessionChannel.SESSION_KEY).
##
## host: opens the session in the room; once client and client2 are in, shelves Fen; once both
##   report progress on it (each is fetching it, one at a time at the host), shelves Mill then
##   Pond and selects Pond (the GM's pick), so the clients' next pick is made with all three
##   known. It records every progress report it relays. Once both clients hold all three (its
##   own holdings), it sets Fen out from the shelf (Root.set_out); once Fen is up, client3 may
##   join. It finishes when every client has reported.
## client, client2: join at the start and land in the room; record the order their map files
##   arrive (Fen, then Pond, the GM's pick, before Mill, first on the shelf), wait until the
##   host's summary says they hold all three, then follow Fen to the table, which must load
##   with no download (MapDownloadCoordinator never starts). client2 also asks for Secret's map
##   file, which the host must refuse (not on the shelf).
## client3: joins while Fen is out (a late joiner); its table's load downloads Fen (the table's
##   map, first), then it fetches Pond and Mill at the table, and ends holding all three.
##
## Run: godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##   --data-root=net_launcher --scenario=enet_prefetch --peers=4 --timeout-s=240

const FEN := {"name": "Prefetch Fen", "folder": "_prefetch_fen"}
const MILL := {"name": "Prefetch Mill", "folder": "_prefetch_mill"}
const POND := {"name": "Prefetch Pond", "folder": "_prefetch_pond"}
const SECRET := {"name": "Prefetch Secret", "folder": "_prefetch_secret"}
## The order every client fetches them in: the table's map or the first shelved (Fen), the
## GM's pick (Pond), then shelf order (Mill)
const ORDER := ["_prefetch_fen", "_prefetch_pond", "_prefetch_mill"]
const ROOM_CLIENTS: Array[String] = ["client", "client2"]
const ALL_CLIENTS: Array[String] = ["client", "client2", "client3"]
## The client that asks for a map the host never shelved
const PROBER := "client2"
## Mill's map: a flat authored map (a 120 ft square)
const MAP_CELLS := 24
const MAP_SEED := 4711
## Time the host waits after the last report before it collects
const SETTLE_S := 1.0

var _shelved_ms := 0
## host: session id -> {ref key: [each percent it relayed, in order]}
var _progress_seen: Dictionary = {}
## client: the level folders of the map files that arrived, in order
var _arrived: Array = []
## client: table loads that had to download (MapDownloadCoordinator.map_download_started)
var _map_downloads := 0
## client2: the host's answer to its request for Secret ("" until it comes)
var _secret_answer := ""


func _has(role: String, step: String) -> bool:
	return FileAccess.file_exists("%s.%s.%s" % [_rv, role, step])


func _mark(step: String, data: Dictionary = {}) -> void:
	_write_json("%s.%s.%s" % [_rv, _role, step], data)


func _all_have(roles: Array[String], step: String) -> bool:
	return roles.all(func(role: String) -> bool: return _has(role, step))


func _id(role: String) -> String:
	return SessionChannel.session_id(0, 0, role)


## Whether the session's holdings say `role` holds all three shelf maps (host: as reported; a
## client: the host's summary).
func _holds_all(role: String) -> bool:
	var held: Array = NetworkManager.session.get_holdings().get(_id(role), [])
	return ORDER.all(func(folder: String) -> bool: return held.has(folder))


## Whether the host has relayed a report from `role` on Fen (it is fetching it).
func _fetching_fen(role: String) -> bool:
	return NetworkManager.session.prefetch.get_progress().get(_id(role), {}).has(FEN.folder)


## True once Fen is on this peer's board with its map built.
func _fen_up() -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_folder == FEN.folder
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
	)


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
		"room_start":
			if _all_have(ROOM_CLIENTS, "room0"):
				_shelve([FEN])
				_shelved_ms = Time.get_ticks_msec()
				_set_phase("fen")
		"fen":
			if ROOM_CLIENTS.all(_fetching_fen):
				_shelve([MILL, POND])
				NetworkManager.session.select_map(POND.folder)
				_result["servable_in_room"] = NetworkManager.session.servable_folders()
				_log("shelved Mill and Pond, Pond selected")
				_set_phase("prefetch")
		"prefetch":
			if ROOM_CLIENTS.all(_holds_all):
				_result["held_after_ms"] = Time.get_ticks_msec() - _shelved_ms
				_result["holdings_before_set_out"] = NetworkManager.session.get_holdings()
				_main.call("set_out", FEN.folder)
				_set_phase("table_load")
		"table_load":
			if _fen_up():
				_set_phase("table")
		"table":
			if _all_have(ALL_CLIENTS, "json"):
				_set_phase("collect")
				_host_collect()


## Fen (the shipped GLB in a folder of its own), Mill and Pond (authored flat maps) and Secret
## (never shelved), saved in this host's test data root. "" once saved, else what failed.
func _build_maps() -> String:
	for table: Dictionary in [MILL, POND, SECRET]:
		var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "net", MAP_SEED)
		DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(table.folder))
		if MapDocumentIO.write(doc, LevelManager.map_document_path(table.folder)) != OK:
			return "%s's map document was not written" % table.name
		var level := LevelData.new()
		level.level_name = table.name
		level.level_folder = table.folder
		level.map_document = LevelManager.LEVEL_MAP_DOCUMENT_NAME
		if LevelManager.save_level_folder(level, table.folder) == "":
			return "%s was not saved" % table.name
	var data := FileAccess.get_file_as_bytes(MAP_SOURCE)
	if data.is_empty():
		return "cannot read " + MAP_SOURCE
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(FEN.folder))
	var file := FileAccess.open(Paths.get_level_map_path(FEN.folder), FileAccess.WRITE)
	if file == null:
		return "Fen's map file was not written"
	file.store_buffer(data)
	file.close()
	_result["fen_bytes"] = data.size()
	var fen := LevelData.new()
	fen.level_name = FEN.name
	fen.level_folder = FEN.folder
	fen.map_path = LevelManager.LEVEL_MAP_NAME
	if LevelManager.save_level_folder(fen, FEN.folder) == "":
		return "Fen was not saved"
	return ""


## What Root does for Host once a Steam lobby exists (host_session, then ROOM on HOSTING),
## over ENet.
func _open_session() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(int(_args.get("port", DEFAULT_PORT)), 8)
	if err != OK:
		_finish(false, "create_server failed: %d" % err)
		return
	var info: Dictionary = NetworkManager.get("_local_player_info")
	info["role"] = NetworkManager.PlayerRole.GM
	NetworkManager.set_player_name("host")
	multiplayer.multiplayer_peer = peer
	(NetworkManager.get("_players") as Dictionary)[1] = info.duplicate()
	NetworkManager.set("_room_code", "ENET07")
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.HOSTING)
	NetworkManager.session.prefetch.progress_changed.connect(_on_host_progress)
	_main.call("change_state", STATE_ROOM)
	_set_phase("room_start")


## `tables` go on the shelf in order, as the room's Add puts them there.
func _shelve(tables: Array) -> void:
	for table: Dictionary in tables:
		var level := LevelManager.load_level_folder(table.folder, false)
		if level == null:
			_finish(false, "%s is not in the host's library" % table.name)
			return
		NetworkManager.session.shelve(level.to_dict())


func _on_host_progress() -> void:
	var progress := NetworkManager.session.prefetch.get_progress()
	for id: String in progress:
		var player: Dictionary = _progress_seen.get_or_add(id, {})
		for key: String in progress[id]:
			var seen: Array = player.get_or_add(key, [])
			var percent := int(progress[id][key])
			if seen.is_empty() or seen.back() != percent:
				seen.append(percent)


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
	_result["progress_seen"] = _progress_seen
	_result["holdings_end"] = NetworkManager.session.get_holdings()
	_result["shelf_end"] = (
		NetworkManager.session.get_shelf().map(func(r: Dictionary) -> String: return r.folder)
	)
	var shelved := [FEN.folder, MILL.folder, POND.folder]
	var seen_partial := false
	for id: String in _progress_seen:
		for key: String in _progress_seen[id]:
			seen_partial = (
				seen_partial
				or (_progress_seen[id][key] as Array).any(func(p: int) -> bool: return p > 0)
			)
	_result["progress_partial_seen"] = seen_partial
	var checks := {
		"whitelist_is_the_shelf": _result.get("servable_in_room") == shelved,
		"progress_relayed":
		ROOM_CLIENTS.all(
			func(role: String) -> bool: return _progress_seen.get(_id(role), {}).has(FEN.folder)
		),
		"progress_partial_seen": seen_partial,
		"everyone_holds_all": ALL_CLIENTS.all(_holds_all),
		"shelf_end": _result.shelf_end == shelved,
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
	if host_phase == "done":
		_finish(false, "the host finished before this client reported (phase %s)" % _phase)
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_set_phase("wait_to_join")
		"wait_to_join":
			if _may_join(host_phase):
				_join_session()
		"wait_room0":
			if _state() == STATE_ROOM:
				_mark("room0")
				if _role == PROBER:
					AssetManager.streamer.request_map_file_from_host(SECRET.folder, "ttmap")
				_set_phase("room")
		"room":
			if _holds_all(_role) and (_role != PROBER or _secret_answer != ""):
				_result["arrived_in_room"] = _arrived.duplicate()
				_result["held_in_room"] = true
				_set_phase("wait_table")
		"wait_table":
			if _fen_up():
				_client_report()
		"late":
			if _fen_up() and _holds_all(_role):
				_client_report()


func _may_join(host_phase: String) -> bool:
	if _role == "client3":
		return host_phase == "table"
	return host_phase == "room_start"


## Joins through the join screen over the title, connecting over ENet as its Connect would
## over Steam, with the role as the session key. Root moves on when the host places this
## client (the room, or the table for client3).
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
	AssetManager.streamer.asset_received.connect(_on_file_arrived)
	AssetManager.streamer.asset_failed.connect(_on_file_failed)
	_lpc()._map_download_coordinator.map_download_started.connect(
		func(folder: String) -> void:
			_map_downloads += 1
			_log("the table's load downloads %s" % folder)
	)
	multiplayer.multiplayer_peer = peer
	_set_phase("late" if _role == "client3" else "wait_room0")


func _on_file_arrived(
	pack_id: String, asset_id: String, variant_id: String, _path: String, _file_type: String
) -> void:
	if pack_id != Paths.LEVEL_MAPS_PACK_ID:
		return
	_log("%s of %s arrived in %s" % [variant_id, asset_id, _phase])
	if _arrived.is_empty() or _arrived.back() != asset_id:
		_arrived.append(asset_id)


func _on_file_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String, _file_type: String
) -> void:
	if pack_id == Paths.LEVEL_MAPS_PACK_ID and asset_id == SECRET.folder:
		_secret_answer = error
		_log("%s of %s refused: %s" % [variant_id, asset_id, error])


func _client_report() -> void:
	_result["arrived"] = _arrived.duplicate()
	_result["map_downloads"] = _map_downloads
	_result["holdings"] = NetworkManager.session.get_holdings().get(_id(_role), [])
	_result["fen_on_table"] = NetworkManager.session.get_table() == FEN.folder
	var checks := {}
	if _role == "client3":
		# The table's map first (its load downloads it), then the GM's pick, then the shelf.
		checks["late_order"] = _arrived == ORDER
		checks["late_table_download"] = _map_downloads == 1
		checks["late_holds_all"] = _holds_all(_role)
	else:
		# Fen (under way when the others came), the GM's pick, then the shelf, all here before
		# the table, and Fen set out from the cache.
		checks["room_order"] = _result.get("arrived_in_room", []) == ORDER
		checks["held_in_room"] = bool(_result.get("held_in_room", false))
		checks["no_download_at_set_out"] = _map_downloads == 0 and _arrived == ORDER
	if _role == PROBER:
		_result["secret_answer"] = _secret_answer
		checks["secret_refused"] = _secret_answer == "Asset not found on host"
	checks["fen_on_table"] = bool(_result.fen_on_table)
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_result["pass"] = ok
	_log("report: %s" % JSON.stringify(_result))
	_write_json("%s.%s.json" % [_rv, _role], _result)
	_set_phase("wait_done")
