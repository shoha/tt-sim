extends "res://tests/net/enet_late_joiner.gd"

## The perfaudit net harness (docs/plans/2026-11-09-perfaudit, stream net): what hosting a
## level costs on the wire and in time, by message. Every peer's ENet peer is wrapped in a
## CountingPeer (tests/net/counting_peer.gd), which counts each packet by RPC name and can play
## a slow link on the receive side; the host cuts one counting window per scenario step and
## logs each as NETW (totals) and NETM (one line per message) lines.
##
## host: builds a temperate forest map (NewMap.create, the map scattered to the end as the
##   authoring editor does, saved as a level in its own test root) and logs what the document
##   holds and costs (DOC lines: file, entries, zstd, parse, hash, scatter regeneration), opens
##   the room; once client is in it, sets the map out (client downloads map.ttmap). Then, at
##   the table: tokens placed in steps to 1, 10, 50 and 200, each followed by an idle window
##   (IDLE_S); ten tokens dragged for DRAG_S as a GM drag sends them; the full visual settings
##   broadcast once; with --peers=3 client2 joins late (all tokens on the board). Finishes once
##   the clients reported.
## client: joins in the room, then loads the table; reports join, room and table times.
## client2: joins at the table late, reports its join-to-table and join-to-tokens times.
##
## --opts (comma separated key=value, through the launcher): size=<ft> (default 200, at most
## NewMap.MAX_FT), fill=1 (the forest at full density everywhere, the map-size sweep's worst
## case), landform=<StartingLandform> (default valley), sim=<rtt ms>:<kbit/s> (link play on
## every peer), max_tokens=<n> (token steps up to n, default 200; at least 1 for the drag),
## docs=<size>:<fill>/... (only build and measure those documents, no hosting).
##
## Run (every peer headless; a worktree with its own user folder and a port of its own):
##   godot --headless --path <worktree> res://tests/net/net_launcher.tscn --
##     --data-root=net_launcher --scenario=perfaudit_net --peers=3 --timeout-s=400
##     --port=28591 --opts=size=200,fill=1
## Logs: .godot/net_runs/perfaudit_net/<role>.log (NETW, NETM, FRAMES, DOC, STATE, SETOUT).

const CountingPeer := preload("res://tests/net/counting_peer.gd")
const FOREST := "temperate_forest_summer_s1"
const MAP_SEED := 3
const LEVEL_FOLDER := "_perfaudit_net_table"
const TABLE_NAME := "Perfaudit net table"
const TOKEN_STEPS: Array[int] = [1, 10, 50, 200]
const SETTLE_S := 3.0
const IDLE_S := 10.0
const DRAG_S := 5.0
const DRAGGED := 10
const LATE_WAIT_S := 60.0
## A drag emits transform_updated every Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL; the board
## moves the token every frame at a 60 Hz display.
const DRAG_HZ := 60.0

var _opts: Dictionary = {}
var _meter: CountingPeer = null
var _busy := false
var _step := 0
var _phase_ms := 0
var _tokens: Array[BoardToken] = []
var _drag_base: Array[Vector3] = []
var _drag_t := 0.0
var _drag_emit := 0.0
var _marks: Dictionary = {}
var _windows: Array[Dictionary] = []
var _frame_max_ms := 0.0
var _frame_over_50 := 0
var _frames := 0
var _join_ms := 0
var _late_peers := false
var _last_frame_us := 0
var _steps: Array[int] = TOKEN_STEPS.duplicate()


func _ready() -> void:
	super._ready()
	for pair in str(_args.get("opts", "")).split(",", false):
		var kv := pair.split("=")
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _opts.has("steps"):
		_steps.clear()
		for n in str(_opts.steps).split("/", false):
			_steps.append(int(n))
	_result["opts"] = _opts
	_log("opts %s" % JSON.stringify(_opts))


## Frame gaps are wall-clock time between _process calls (Time, not delta), so a main thread
## blocked for a second shows as one 1000 ms frame.
func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		var gap_ms := (now - _last_frame_us) / 1000.0
		_frames += 1
		_frame_max_ms = maxf(_frame_max_ms, gap_ms)
		if gap_ms > 50.0:
			_frame_over_50 += 1
	_last_frame_us = now
	super._process(delta)


func _set_phase(phase: String) -> void:
	_phase = phase
	_phase_ms = Time.get_ticks_msec()
	_log("phase " + phase)
	if _role == "host":
		_write_json(_rv + ".host.json", {"phase": phase})


func _mark(key: String, value: Variant = true) -> void:
	_marks[key] = value
	_write_json("%s.%s.json" % [_rv, _role], _marks)


func _peer_marks(role: String) -> Dictionary:
	return _read_json("%s.%s.json" % [_rv, role])


func _host_phase() -> String:
	return str(_read_json(_rv + ".host.json").get("phase", ""))


func _since_phase_s() -> float:
	return (Time.get_ticks_msec() - _phase_ms) / 1000.0


func _table_ready() -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_name == TABLE_NAME
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
	)


## Wraps `peer` in the counting peer, with the link play --opts sim asks for.
func _wrap(peer: MultiplayerPeer) -> MultiplayerPeer:
	var sim := str(_opts.get("sim", "")).split(":")
	var rtt := float(sim[0]) if sim.size() > 0 and sim[0] != "" else 0.0
	var kbps := float(sim[1]) if sim.size() > 1 else 0.0
	_meter = CountingPeer.new(peer, get_tree().root, rtt, kbps)
	return _meter


## Closes a counting window: logs it with the main thread's frame times since the last cut.
func _cut(label: String) -> Dictionary:
	if _meter == null:
		return {}
	var w := _meter.cut(label)
	w["frame_max_ms"] = snappedf(_frame_max_ms, 0.1)
	w["frames_over_50ms"] = _frame_over_50
	w["frames"] = _frames
	_frame_max_ms = 0.0
	_frame_over_50 = 0
	_frames = 0
	for line in CountingPeer.window_lines(_role, w):
		_log(line)
	_log(
		(
			"FRAMES|%s|%s|max %.1f ms|over 50 ms %d of %d|link max wait %.1f ms"
			% [_role, label, w.frame_max_ms, w.frames_over_50ms, w.frames, _meter.max_wait_ms]
		)
	)
	_meter.max_wait_ms = 0.0
	var summary := w.duplicate()
	summary.erase("rows")
	_windows.append(summary)
	return w


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE and not _busy:
				_busy = true
				if _opts.has("docs"):
					_only_documents()
				else:
					_build_and_open()
		"room_wait":
			if _peer_marks("client").has("room"):
				_cut("connect_to_room")
				var t0 := Time.get_ticks_usec()
				_main.set("pending_level", LevelManager.load_level_folder(LEVEL_FOLDER, false))
				var t1 := Time.get_ticks_usec()
				_flow().set_out_pending()
				var t2 := Time.get_ticks_usec()
				_log(
					(
						"SETOUT|load_level_folder %.1f ms|set_out_pending (main thread, sync) %.1f ms"
						% [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0]
					)
				)
				_set_phase("table_load")
		"table_load":
			if _table_ready() and _peer_marks("client").has("table"):
				_cut("set_out_to_client_table")
				_set_phase("tail")
		"tail":
			if _since_phase_s() >= 2.0:
				_cut("table_tail")
				_step = 0
				_next_step()
		"settle":
			if _since_phase_s() >= SETTLE_S:
				_cut("spawn_to_%d" % _steps[_step])
				_log_state_sizes(_steps[_step])
				if _opts.has("save"):
					_lpc().save_level()
					_set_phase("save")
				else:
					_set_phase("idle")
		"save":
			if _since_phase_s() >= 1.0:
				_cut("save_at_%d_tokens" % _steps[_step])
				_set_phase("idle")
		"idle":
			if _since_phase_s() >= IDLE_S:
				_cut("idle_%d_tokens_%ds" % [_steps[_step], int(IDLE_S)])
				_step += 1
				_next_step()
		"drag":
			_drag_frame()
		"drop":
			if _since_phase_s() >= 1.0:
				_cut("drag_drop_tail")
				var visual := LevelVisualState.from_level_data(_lpc().active_level_data)
				NetworkManager.game_sync.broadcast_visual_settings(visual.to_broadcast_dict())
				_set_phase("visual")
		"visual":
			if _since_phase_s() >= 1.0:
				_cut("visual_settings_full")
				if _late_peers:
					_set_phase("late")
				else:
					_host_done()
		"late":
			var late := _peer_marks("client2")
			if late.has("board") or _since_phase_s() >= LATE_WAIT_S:
				_cut("late_join_%d_tokens" % _tokens.size())
				_host_done()


func _next_step() -> void:
	var cap := int(_opts.get("max_tokens", "200"))
	if _step >= _steps.size() or _steps[_step] > cap:
		_start_drag()
		return
	var lpc := _lpc()
	while _tokens.size() < _steps[_step]:
		var i := _tokens.size()
		var at := Vector3((i % 20) * 1.6 - 15.0, 12.0, int(i / 20.0) * 1.6 - 8.0)
		var token := lpc.spawn_avatar({"format": 1}, "T%d" % i, at, true)
		if token == null:
			_finish(false, "avatar spawn failed at %d" % i)
			return
		_tokens.append(token)
	_set_phase("settle")


func _start_drag() -> void:
	if _tokens.is_empty():
		_finish(false, "no tokens to drag (max_tokens below 1)")
		return
	_drag_base.clear()
	for i in mini(DRAGGED, _tokens.size()):
		_drag_base.append(_tokens[i].rigid_body.global_position)
	_drag_t = 0.0
	_drag_emit = 0.0
	_cut("before_drag")
	_set_phase("drag")


## One display frame of the drag: every dragged token moves on a 2 m circle, and every
## NETWORK_TRANSFORM_UPDATE_INTERVAL emits transform_updated, as DraggableToken does.
func _drag_frame() -> void:
	var dt := 1.0 / DRAG_HZ
	var now_s := _since_phase_s()
	while _drag_t < now_s:
		_drag_t += dt
		_drag_emit += dt
		var emit := _drag_emit >= Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL
		if emit:
			_drag_emit = 0.0
		for i in _drag_base.size():
			var token := _tokens[i]
			var a := _drag_t * TAU * 0.25 + i
			token.rigid_body.global_position = _drag_base[i] + Vector3(cos(a), 0.0, sin(a)) * 2.0
			if emit:
				token.transform_updated.emit()
	if now_s >= DRAG_S:
		for i in _drag_base.size():
			_tokens[i].transform_changed.emit()
		_cut("drag_%d_tokens_%ds" % [_drag_base.size(), int(DRAG_S)])
		_set_phase("drop")


## Logs what the full state and the level dict weigh as a Variant and compressed, at `n`
## tokens: the late joiner's payloads.
func _log_state_sizes(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	var state := var_to_bytes(GameState.get_full_state_dict())
	var t1 := Time.get_ticks_usec()
	var level: Variant = NetworkManager.get("_current_level_dict")
	var level_bytes := var_to_bytes(level if level is Dictionary else {})
	_log(
		(
			"STATE|%d tokens|full state %d B in %.2f ms (zstd %d, deflate %d)|level dict %d B (zstd %d)"
			% [
				n,
				state.size(),
				(t1 - t0) / 1000.0,
				state.compress(FileAccess.COMPRESSION_ZSTD).size(),
				state.compress(FileAccess.COMPRESSION_DEFLATE).size(),
				level_bytes.size(),
				level_bytes.compress(FileAccess.COMPRESSION_ZSTD).size(),
			]
		)
	)


func _host_done() -> void:
	_set_phase("collect")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var ok := _peer_marks("client").has("final")
		if _late_peers:
			ok = ok and _peer_marks("client2").has("final")
		if ok:
			break
		await get_tree().create_timer(0.25).timeout
	_result["client"] = _peer_marks("client")
	if _late_peers:
		_result["client2"] = _peer_marks("client2")
	_result["host_windows"] = _windows
	_finish(true, "measured")


func _build_and_open() -> void:
	var problem := await _build_level()
	if problem != "":
		_finish(false, problem)
		return
	_late_peers = FileAccess.file_exists(_rv.get_base_dir().path_join("client2.log"))
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
	NetworkManager.set("_room_code", "ENETPA")
	NetworkManager.call("_set_connection_state", NetworkManager.ConnectionState.HOSTING)
	_main.call("change_state", STATE_ROOM)
	_cut("host_open")
	_set_phase("room_wait")


## --opts docs=<size>:<fill>/<size>:<fill>...: only builds and measures those documents (DOC
## lines), one after another, and finishes without hosting; the clients finish with it.
func _only_documents() -> void:
	for spec in str(_opts.docs).split("/", false):
		var parts := spec.split(":")
		_opts["size"] = parts[0]
		_opts["fill"] = parts[1] if parts.size() > 1 else "0"
		var problem := await _build_level()
		if problem != "":
			_finish(false, problem)
			return
	_set_phase("collect")
	_finish(true, "documents measured")


## Builds the map as a new map's open does, scatters it to the end, saves it as LEVEL_FOLDER
## and logs what its document weighs. "" or what failed.
func _build_level() -> String:
	var size := int(_opts.get("size", "200"))
	var landform := str(_opts.get("landform", StartingLandform.VALLEY))
	var t0 := Time.get_ticks_usec()
	var doc := NewMap.create(size, FOREST, MAP_SEED, PaletteLibrary.DEFAULT_ROOT, landform)
	if doc == null:
		return "NewMap.create refused %d ft" % size
	if str(_opts.get("fill", "0")) == "1":
		if doc.biome_ids.is_empty():
			doc.biome_ids = PackedStringArray([FOREST])
		var slot := doc.biome_ids.find(FOREST) + 1
		doc.biome_slots.fill(slot)
		doc.biome_density.fill(255)
	var t1 := Time.get_ticks_usec()
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	if root == null:
		return "the map did not build"
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	var t2 := Time.get_ticks_usec()
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	e.finish_height_work()
	while e.scatter.is_regenerating() or e.scatter.is_growing():
		await get_tree().process_frame
	var t3 := Time.get_ticks_usec()
	doc.scatter = e.scatter.rows_by_asset()
	doc.mass_anchors = ScatterMass.anchors_entry(e.scatter.mass_anchors, doc.scatter)
	doc.props = e.props.rows_by_asset()
	remove_child(root)
	root.free()
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(LEVEL_FOLDER))
	var path := LevelManager.map_document_path(LEVEL_FOLDER)
	var t4 := Time.get_ticks_usec()
	if MapDocumentIO.write(doc, path) != OK:
		return "the map document was not written"
	var t5 := Time.get_ticks_usec()
	var level := LevelData.new()
	level.level_name = TABLE_NAME
	level.level_folder = LEVEL_FOLDER
	level.map_document = LevelManager.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(level, LEVEL_FOLDER) == "":
		return "the level was not saved"
	_log(
		(
			(
				"DOC|%d ft %s fill=%s|samples %dx%d|create %.0f ms|map build %.0f ms"
				+ "|scatter regen %.0f ms|write %.0f ms"
			)
			% [
				size,
				landform,
				str(_opts.get("fill", "0")),
				doc.samples_x(),
				doc.samples_z(),
				(t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0,
				(t3 - t2) / 1000.0,
				(t5 - t4) / 1000.0,
			]
		)
	)
	_log_document(doc, path)
	return ""


## DOC lines: what the saved document weighs on disk and as AssetStreamer sends it, entry by
## entry, and the client-side costs of taking it in (decompress, parse, hash).
func _log_document(doc: MapDocument, path: String) -> void:
	var file := FileAccess.get_file_as_bytes(path)
	var t0 := Time.get_ticks_usec()
	var zstd := file.compress(FileAccess.COMPRESSION_ZSTD)
	var t1 := Time.get_ticks_usec()
	zstd.decompress(file.size(), FileAccess.COMPRESSION_ZSTD)
	var t2 := Time.get_ticks_usec()
	var read := MapDocumentIO.read(path)
	var t3 := Time.get_ticks_usec()
	MapFileHash.hash_bytes(file)
	var t4 := Time.get_ticks_usec()
	_log(
		(
			(
				"DOC|file %d B|zstd %d B (compress %.1f ms, decompress %.1f ms)"
				+ "|read+parse %.0f ms (%s)|sha256 %.1f ms|rows %d in %d assets, props %d"
			)
			% [
				file.size(),
				zstd.size(),
				(t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0,
				(t3 - t2) / 1000.0,
				"ok" if read.document != null else "FAILED",
				(t4 - t3) / 1000.0,
				MapDocument.row_count(doc.scatter),
				doc.scatter.size(),
				MapDocument.row_count(doc.props),
			]
		)
	)
	var packed := MapDocumentIO.serialize(doc)
	var entries: Dictionary = packed.entries
	var raw_all := PackedByteArray()
	var recipe := PackedByteArray()
	for entry_name: String in entries:
		var bytes: PackedByteArray = entries[entry_name]
		raw_all.append_array(bytes)
		if entry_name not in ["scatter.json", "mass_anchors.json"]:
			recipe.append_array(bytes)
		_log(
			(
				"DOC|entry %s|raw %d B|zstd %d B|deflate %d B"
				% [
					entry_name,
					bytes.size(),
					bytes.compress(FileAccess.COMPRESSION_ZSTD).size(),
					bytes.compress(FileAccess.COMPRESSION_DEFLATE).size(),
				]
			)
		)
	var rows_f32 := PackedByteArray()
	for asset_id: String in doc.scatter:
		rows_f32.append_array((doc.scatter[asset_id] as PackedFloat32Array).to_byte_array())
	_log(
		(
			(
				"DOC|all entries raw %d B, zstd %d B"
				+ "|without scatter and anchors (a recipe) raw %d B, zstd %d B"
				+ "|scatter rows as float32 %d B, zstd %d B"
			)
			% [
				raw_all.size(),
				raw_all.compress(FileAccess.COMPRESSION_ZSTD).size(),
				recipe.size(),
				recipe.compress(FileAccess.COMPRESSION_ZSTD).size(),
				rows_f32.size(),
				rows_f32.compress(FileAccess.COMPRESSION_ZSTD).size(),
			]
		)
	)


# =============================================================================
# CLIENTS
# =============================================================================


func _process_client() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_set_phase("wait_to_join")
		"wait_to_join":
			var host := _host_phase()
			if (
				(_role == "client" and host == "room_wait")
				or (_role == "client2" and host == "late")
			):
				_join_counted()
			elif host in ["collect", "done"]:
				_finish(true, "the host finished without a late join")
		"joined":
			if _state() == STATE_ROOM and not _marks.has("room"):
				_mark("room_ms", Time.get_ticks_msec() - _join_ms)
				_cut("join_to_room")
				_mark("room")
			if _table_ready() and not _marks.has("table"):
				_mark("table_ms", Time.get_ticks_msec() - _join_ms)
				_mark("table_unix", Time.get_unix_time_from_system())
				_cut("to_table")
				_mark("table")
			if _marks.has("table") and GameState.get_token_count() > 0 and not _marks.has("tokens"):
				_mark("tokens_ms", Time.get_ticks_msec() - _join_ms)
				_mark("token_count", GameState.get_token_count())
				var tw := _cut("to_tokens")
				_mark("tokens_frame_max_ms", tw.get("frame_max_ms", 0.0))
				_mark("tokens")
			# Every token GameState holds is on the board: "to_tokens" (table to state) and this
			# window (state to board) hold the token builds of the join, built in the frame the
			# state lands or spread over the frames after it.
			if (
				_marks.has("tokens")
				and not _marks.has("board")
				and _lpc()._token_spawner.get_spawned_tokens().size() >= GameState.get_token_count()
			):
				_mark("board_ms", Time.get_ticks_msec() - _join_ms)
				var w := _cut("tokens_to_board")
				_mark("board_frame_max_ms", w.get("frame_max_ms", 0.0))
				_mark("board")
			if _host_phase() in ["collect", "done"]:
				_cut("rest")
				_mark("windows", _windows)
				_mark("final")
				_set_phase("final")
		"final":
			if _host_phase() == "done":
				_finish(true, "measured")


## Joins in place from the title (enet_late_joiner's _join) with the ENet peer counted.
func _join_counted() -> void:
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
	_join_ms = Time.get_ticks_msec()
	# The load's timeline: game starting, level data, the first map chunk, the map file whole.
	NetworkManager.game_starting.connect(
		func(): _mark("game_starting_ms", Time.get_ticks_msec() - _join_ms)
	)
	NetworkManager.level_data_received.connect(
		func(_d: Dictionary): _mark("level_data_ms", Time.get_ticks_msec() - _join_ms)
	)
	AssetManager.streamer.transfer_progress.connect(
		func(_p: String, _a: String, _v: String, _progress: float, _t: String):
			if not _marks.has("first_chunk_ms"):
				_mark("first_chunk_ms", Time.get_ticks_msec() - _join_ms)
	)
	AssetManager.streamer.asset_received.connect(
		func(_p: String, _a: String, v: String, _l: String, _t: String):
			_mark("received_%s_ms" % v, Time.get_ticks_msec() - _join_ms)
	)
	multiplayer.multiplayer_peer = _wrap(peer)
	_set_phase("joined")
