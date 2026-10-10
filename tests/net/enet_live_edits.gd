extends "res://tests/net/enet_late_joiner.gd"

## ENet scenario for live map edits (LiveEdits over NetworkGameSync): the GM changes the map
## during play with the authoring brushes and every peer ends with the same map, a player who
## joins afterwards included.
##
## Three processes, one per role, reuse enet_late_joiner.gd's boot, ENet setup and rendezvous
## files. The table is an authored level the host builds in its own test data root before it
## opens the room (a 120 ft map: forest west of a river, a plank bridge over it; folder
## LEVEL_FOLDER), so both clients download its map.ttmap through the ordinary map download.
##
## host: builds and saves the level, opens the session in the room; once client is in the
##   room, sets the level out. Once client's table has its live edits, runs the GM's ops on
##   the table's play-side editor one at a time: a sculpt raise, a forest clear, the bridge
##   removed, a sculpt lower, and an undo (of the lower: the before side of a height op). After
##   each it waits for its map to settle and writes its MapFingerprint and log length; client
##   compares. Then it drops Hero onto the raised ground, writes the final fingerprint and the
##   hero's resting position, and lets client2 join. It finishes when both clients reported.
## client: joins at the start and lands in the room, then at the table; after each op, once
##   its live edits hold that many ops and its map has settled, its MapFingerprint must equal
##   the host's.
## client2: joins at the table after every op (a late joiner: the map file is the original,
##   the log brings the edits); once its live edits have caught up and its map has settled,
##   its MapFingerprint must equal the host's final one and Hero must rest on its ground where
##   the host's does.
##
## Run: godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##   --data-root=net_launcher --scenario=enet_live_edits --peers=3 --timeout-s=300

const LEVEL_FOLDER := "_live_edits_net"
const TABLE_NAME := "Live edits table"
const FOREST := "temperate_forest_summer_s1"
const MAP_CELLS := 24
const MAP_SEED := 4711
const FOREST_EDGE_X := 2.0
const RIVER: Array[Vector2] = [Vector2(8, -20), Vector2(9, 0), Vector2(10, 20)]
## Where the raise is (and Hero lands), and where the lower that is undone goes.
const RAISE_AT := Vector3(-12, 0, 12)
const LOWER_AT := Vector3(-12, 0, -14)
const OPS: Array[String] = [
	"sculpt raise", "forest clear", "bridge removal", "sculpt lower", "undo"
]
## Frames a map must stay settled before it is fingerprinted.
const STILL_FRAMES := 10
## How far Hero may rest off the host's height, and off its own ground (m).
const GROUND_TOLERANCE_M := 0.05

var _op := 0
var _still := 0
var _hero_id := ""
var _building := false


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(_rv + ".host.json", {"phase": phase, "hero": _hero_id})


func _has(role: String, step: String) -> bool:
	return FileAccess.file_exists("%s.%s.%s" % [_rv, role, step])


func _read_step(role: String, step: String) -> Dictionary:
	return _read_json("%s.%s.%s" % [_rv, role, step])


func _mark(step: String, data: Dictionary = {}) -> void:
	_write_json("%s.%s.%s" % [_rv, _role, step], data)


func _edits() -> LiveEdits:
	return _lpc().live_edits if _lpc() != null else null


func _table_ready() -> bool:
	var lpc := _lpc()
	return (
		_state() == STATE_PLAYING
		and lpc.active_level_data != null
		and lpc.active_level_data.level_name == TABLE_NAME
		and not lpc.is_loading()
		and is_instance_valid(lpc.loaded_map_instance)
		and is_instance_valid(lpc.live_edits)
	)


## True once the map has had nothing left to do for STILL_FRAMES frames in a row (live
## edits sent or applied, height work, regeneration, grow-in, the water surface's refresh).
func _map_still() -> bool:
	var edits := _edits()
	var root := _lpc().loaded_map_instance
	var water := root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var busy := (
		not edits.is_settled()
		or edits.editor.scatter.is_regenerating()
		or edits.editor.scatter.is_growing()
		or edits.editor.props.is_growing()
		or (water != null and water.is_refreshing())
	)
	_still = 0 if busy else _still + 1
	return _still >= STILL_FRAMES


func _fingerprint() -> Dictionary:
	return MapFingerprint.of(_lpc().loaded_map_instance, _lpc().loaded_map_document)


# =============================================================================
# HOST
# =============================================================================


func _process_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE and not _building:
				_building = true
				_build_and_open()
		"room_start":
			if _has("client", "room0"):
				var level := LevelManager.load_level_folder(LEVEL_FOLDER, false)
				_main.set("_pending_level_data", level)
				_main.call("_on_lobby_start_game")
				_set_phase("table_load")
		"table_load":
			if _table_ready() and _map_still() and _has("client", "table"):
				_run_op()
		"op":
			if _map_still():
				var edits := _edits()
				_mark("op%d" % _op, {"fingerprint": _fingerprint(), "ops": edits.op_log.size()})
				_log("op %d (%s) logged as %d ops" % [_op, OPS[_op], edits.op_log.size()])
				_set_phase("op_wait")
		"op_wait":
			if _has("client", "op%d" % _op):
				_op += 1
				if _op < OPS.size():
					_run_op()
				else:
					_place_hero()
		"landing":
			_host_check_landing()
		"table":
			if _has("client", "done") and _has("client2", "done"):
				_host_collect()


## Builds the level (forest, river, plank bridge) in this peer's own data root, then opens the
## session in the room over ENet, as Root does once a Steam lobby exists.
func _build_and_open() -> void:
	var problem := await _build_level()
	if problem != "":
		_finish(false, problem)
		return
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
	_main.call("change_state", STATE_ROOM)
	_set_phase("room_start")


## "" once the level is saved under LEVEL_FOLDER, else what failed.
func _build_level() -> String:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "net", MAP_SEED)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x < FOREST_EDGE_X:
				slots[doc.sample_index(x, z)] = 1
				density[doc.sample_index(x, z)] = 200
	doc.biome_slots = slots
	doc.biome_density = density
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	if root == null:
		return "the level did not build"
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var widths := PackedFloat32Array([1.4])
	if e.water.carve_river(PackedVector2Array(RIVER), widths, WaterBody.Depth.WAIST) <= 0:
		return "the river was not carved"
	if e.crossings.place(Crossing.Kind.PLANK, Vector3(5, 0, 0), Vector3(13, 0, 0)) <= 0:
		return "the bridge was not placed"
	e.finish_height_work()
	while e.scatter.is_regenerating() or e.scatter.is_growing():
		await get_tree().process_frame
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	remove_child(root)
	root.free()
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(LEVEL_FOLDER))
	if MapDocumentIO.write(doc, LevelManager.map_document_path(LEVEL_FOLDER)) != OK:
		return "the map document was not written"
	var level := LevelData.new()
	level.level_name = TABLE_NAME
	level.level_folder = LEVEL_FOLDER
	level.map_document = LevelManager.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(level, LEVEL_FOLDER) == "":
		return "the level was not saved"
	_log("level built: %d crossings, %d water" % [doc.crossings.size(), doc.water_bodies.size()])
	return ""


## Runs op _op on the table's play-side editor (the GM's brushes, no UI).
func _run_op() -> void:
	var e := _edits().editor
	_log("op %d: %s" % [_op, OPS[_op]])
	match OPS[_op]:
		"sculpt raise":
			e.begin_height_stroke(HeightBrush.RAISE)
			_dabs(e, [RAISE_AT, RAISE_AT + Vector3(3, 0, 2), RAISE_AT + Vector3(6, 0, 4)], 4.0, 0.8)
		"forest clear":
			e.begin_stroke(MaskBrush.CLEAR)
			_dabs(e, [Vector3(-18, 0, -2), Vector3(-10, 0, -3), Vector3(-4, 0, -4)], 4.0, 0.6)
		"bridge removal":
			e.crossings.remove(e.document.crossings[0].id)
		"sculpt lower":
			e.begin_height_stroke(HeightBrush.LOWER)
			_dabs(e, [LOWER_AT, LOWER_AT + Vector3(3, 0, 1)], 3.0, 0.5)
		"undo":
			_result["undid"] = _edits().history.undo()
	_still = 0
	_set_phase("op")


func _dabs(e: AuthoringEditor, points: Array, radius: float, seconds: float) -> void:
	var last: Vector3 = points[0]
	for p: Vector3 in points:
		e.stroke_dab(last, p, radius, seconds)
		e.flush()
		last = p
	e.end_stroke()


func _place_hero() -> void:
	var drop := RAISE_AT + Vector3(3, 30, 2)
	var token := _lpc().spawn_avatar({"format": 1}, "Hero", drop, true)
	if token == null:
		_finish(false, "the hero did not spawn")
		return
	_hero_id = token.network_id
	_still = 0
	_set_phase("landing")


## Once Hero rests on the raised ground, the final fingerprint and its position go out and the
## late joiner may join.
func _host_check_landing() -> void:
	var hero := _lpc().find_token_by_network_id(_hero_id)
	if hero == null or not hero.visible:
		return
	var at := hero.rigid_body.global_position
	var rest := TokenGrounding.resting_position(hero, TokenGrounding.cast_top(_lpc().get_game_map()))
	if rest == Vector3.INF or absf(rest.y - at.y) > GROUND_TOLERANCE_M or not _map_still():
		return
	# The map was flat at 0 before the raise.
	_result["hero_raised_m"] = snappedf(at.y, 0.001)
	_mark(
		"final",
		{
			"fingerprint": _fingerprint(),
			"ops": _edits().op_log.size(),
			"hero": {"x": at.x, "y": at.y, "z": at.z},
		}
	)
	_log("hero %s rests at %s; the late joiner may join" % [_hero_id, str(at)])
	_set_phase("table")


func _host_collect() -> void:
	var client := _read_step("client", "done")
	var joiner := _read_step("client2", "done")
	_result["client"] = client
	_result["client2"] = joiner
	_result["ops_logged"] = _edits().op_log.size()
	var ok := (
		bool(client.get("pass", false))
		and bool(joiner.get("pass", false))
		and _edits().op_log.size() == OPS.size()
		and str(_result.get("undid", "")) != ""
	)
	_finish(ok, "both clients reported")


# =============================================================================
# CLIENTS
# =============================================================================


func _process_client() -> void:
	var host_phase := str(_read_json(_rv + ".host.json").get("phase", ""))
	if _phase == "wait_done":
		if host_phase == "done":
			_finish(bool(_result.get("pass", false)), "host done")
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_set_phase("wait_to_join")
		"wait_to_join":
			if (_role == "client" and host_phase == "room_start") or host_phase == "table":
				_join_live()
		"wait_room0":
			if _state() == STATE_ROOM:
				_mark("room0")
				_set_phase("table_wait")
		"table_wait":
			if _table_ready() and _edits().table_key != 0 and _map_still():
				_mark("table")
				_set_phase("ops")
		"ops":
			_client_follow_op()
		"joiner_wait":
			_joiner_check()


## Joins through the join screen over the title, as enet_session_room does.
func _join_live() -> void:
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
	multiplayer.multiplayer_peer = peer
	_set_phase("wait_room0" if _role == "client" else "joiner_wait")


## After the host's op _op: once this peer holds that many ops and its map is still, the
## fingerprints must match.
func _client_follow_op() -> void:
	var step := "op%d" % _op
	if not _has("host", step):
		return
	var host := _read_step("host", step)
	if _edits().op_log.size() < int(host.get("ops", 0)) or not _map_still():
		return
	var mismatch := MapFingerprint.diff(host.get("fingerprint", {}), _fingerprint())
	_result[OPS[_op]] = {"ops": _edits().op_log.size(), "mismatch": mismatch}
	_log("%s: %d ops, mismatch %s" % [OPS[_op], _edits().op_log.size(), str(mismatch)])
	_mark(step)
	_op += 1
	if _op < OPS.size():
		return
	var ok := _edits().problem == ""
	for label in OPS:
		ok = ok and (_result[label].mismatch as Array).is_empty()
	_result["pass"] = ok
	_mark("done", _result)
	_set_phase("wait_done")


## The late joiner: its live edits caught up with the host's final log, its map still, Hero on
## its board.
func _joiner_check() -> void:
	if not _has("host", "final") or not _table_ready():
		return
	var host := _read_step("host", "final")
	var edits := _edits()
	var hero_id := str(_read_json(_rv + ".host.json").get("hero", ""))
	var hero := _lpc().find_token_by_network_id(hero_id)
	if edits.op_log.size() < int(host.get("ops", 0)) or hero == null or not _map_still():
		return
	var mismatch := MapFingerprint.diff(host.get("fingerprint", {}), _fingerprint())
	var at := hero.rigid_body.global_position
	var rest := TokenGrounding.resting_position(hero, TokenGrounding.cast_top(_lpc().get_game_map()))
	var host_y := float((host.get("hero", {}) as Dictionary).get("y", INF))
	_result["mismatch"] = mismatch
	_result["ops"] = edits.op_log.size()
	_result["hero_y"] = snappedf(at.y, 0.001)
	_result["hero_rest_y"] = snappedf(rest.y, 0.001)
	_result["host_hero_y"] = snappedf(host_y, 0.001)
	_result["pass"] = (
		mismatch.is_empty()
		and edits.problem == ""
		and absf(at.y - host_y) <= GROUND_TOLERANCE_M
		and absf(rest.y - at.y) <= GROUND_TOLERANCE_M
	)
	_log("late joiner: %s" % str(_result))
	_mark("done", _result)
	_set_phase("wait_done")
