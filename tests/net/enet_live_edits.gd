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
##   room, sets the level out. Once client's table has its live edits, it stands Scout on the
##   flat ground where the raise will go, then runs the GM's ops one at a time, as the GM's
##   Events pane does: the sculpt raise, the forest clear (Thin with Ctrl) and the sculpt lower
##   are strokes of GameMap's play brush armed by PlayEvents.pick and driven over the board
##   (its pointer and press, as the render driver drives authoring's), the forest fall and the
##   bridge collapse terrain events the presets fire (TerrainEvents.start: every board plays
##   the motion, then the host's op lands; client must have played both, client2 none), and
##   the undo (of the lower: the before side of a height op) is
##   PlayEvents.undo, Ctrl+Z's path. After each it waits for its map to settle and its ground
##   follower (LiveEditGround) to set the tokens down, and writes its MapFingerprint, log
##   length and Scout's height; client compares. Then it drops Hero onto the raised ground,
##   writes the final fingerprint and the hero's resting position, and lets client2 join. It
##   finishes when both clients reported.
## client: joins at the start and lands in the room, then at the table; after each op, once
##   its live edits hold that many ops and its map has settled, its MapFingerprint must equal
##   the host's, and Scout must stand where the host's does (on the raised ground after the
##   raise: the host's re-grounding reached it).
## client2: joins at the table after every op (a late joiner: the map file is the original,
##   the log brings the edits); once its live edits have caught up and its map has settled,
##   its MapFingerprint must equal the host's final one and Hero and Scout must rest on its
##   ground where the host's do.
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
## Where the forest fall's trees topple away from, and how far it reaches.
const FALL_AT := Vector2(-14, 5)
const FALL_RADIUS := 4.0
const OPS: Array[String] = [
	"sculpt raise", "forest clear", "forest fall", "bridge collapse", "sculpt lower", "undo"
]
## The ops that are terrain events: every board plays their motion before the op lands.
const EVENT_OPS: Array[String] = ["forest fall", "bridge collapse"]
## Frames a map must stay settled before it is fingerprinted.
const STILL_FRAMES := 10
## How far Hero may rest off the host's height, and off its own ground (m).
const GROUND_TOLERANCE_M := 0.05
## How long the play brush holds each point of a stroke (real time: headless frames are short).
const HOLD_MS := 900
## Frames a client waits for Scout to reach the host's height before it reports.
const SCOUT_FRAMES := 600
## The ops the play brush strokes: [tool id, Ctrl at the press, points].
const STROKES := {
	"sculpt raise":
	[SculptTool.ID, false, [RAISE_AT, RAISE_AT + Vector3(3, 0, 2), RAISE_AT + Vector3(6, 0, 4)]],
	"forest clear":
	[ThinTool.ID, true, [Vector3(-18, 0, -2), Vector3(-10, 0, -3), Vector3(-4, 0, -4)]],
	"sculpt lower": [SculptTool.ID, true, [LOWER_AT, LOWER_AT + Vector3(3, 0, 1)]],
}

var _op := 0
var _still := 0
var _hero_id := ""
var _scout_id := ""
var _scout_frames := 0
var _building := false
## The stroke in progress: the points left, Ctrl at the press, and when the current one ends.
var _stroke: Array = []
var _stroke_ctrl := false
var _stroke_until := 0
var _events_playing := false


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host":
		_write_json(_rv + ".host.json", {"phase": phase, "hero": _hero_id, "scout": _scout_id})


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
	var ground := edits.get_node_or_null("LiveEditGround") as LiveEditGround
	_watch_events()
	var busy := (
		not edits.is_settled()
		or edits.events.active_count() > 0
		or (ground != null and not ground.is_idle())
		or edits.editor.scatter.is_regenerating()
		or edits.editor.scatter.is_growing()
		or edits.editor.props.is_growing()
		or (water != null and water.is_refreshing())
	)
	_still = 0 if busy else _still + 1
	return _still >= STILL_FRAMES


func _fingerprint() -> Dictionary:
	return MapFingerprint.of(_lpc().loaded_map_instance, _lpc().loaded_map_document)


## Counts the terrain events this peer's board played (each start of one while none was).
func _watch_events() -> void:
	var playing := _edits().events.active_count() > 0
	if playing and not _events_playing:
		_result["events_played"] = int(_result.get("events_played", 0)) + 1
	_events_playing = playing


## The table's Events pane controller (the GM's live brushes).
func _events() -> PlayEvents:
	var menu := _lpc().get_game_map().gameplay_menu.get_node("GameplayMenu")
	return menu.get("play_events") as PlayEvents


## Scout's base height on this peer, or NAN while it is not on the board.
func _scout_y() -> float:
	var scout_id := _scout_id
	if _role != "host":
		scout_id = str(_read_json(_rv + ".host.json").get("scout", ""))
	var scout := _lpc().find_token_by_network_id(scout_id) if scout_id != "" else null
	return scout.rigid_body.global_position.y if scout != null else NAN


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
				_main.set("pending_level", level)
				_flow().set_out_pending()
				_set_phase("table_load")
		"table_load":
			if _table_ready() and _map_still() and _has("client", "table"):
				_place_scout()
		"scout":
			_host_check_scout()
		"brushing":
			_step_stroke()
		"op":
			if _map_still():
				var edits := _edits()
				_mark(
					"op%d" % _op,
					{"fingerprint": _fingerprint(), "ops": edits.op_log.size(), "scout": _scout_y()}
				)
				_log("op %d (%s) logged as %d ops" % [_op, OPS[_op], edits.op_log.size()])
				if OPS[_op] == "sculpt raise":
					_result["scout_raised_m"] = snappedf(_scout_y(), 0.001)
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


## Stands Scout on the flat ground where the raise goes (a drop from above), before the ops.
func _place_scout() -> void:
	var token := _lpc().spawn_avatar({"format": 1}, "Scout", RAISE_AT + Vector3(1, 30, 1), true)
	if token == null:
		_finish(false, "the scout did not spawn")
		return
	_scout_id = token.network_id
	_set_phase("scout")


## Once Scout rests on the ground, the ops begin.
func _host_check_scout() -> void:
	var scout := _lpc().find_token_by_network_id(_scout_id)
	if scout == null or not scout.visible:
		return
	var rest := TokenGrounding.resting_position(scout, TokenGrounding.cast_top(_lpc().get_game_map()))
	if rest == Vector3.INF or absf(rest.y - scout.rigid_body.global_position.y) > GROUND_TOLERANCE_M:
		return
	_result["scout_before_m"] = snappedf(scout.rigid_body.global_position.y, 0.001)
	_run_op()


## Runs op _op as the GM's Events pane does: a stroke of the play brush, the bridge removal on
## the play-side editor, the undo through PlayEvents (Ctrl+Z's path).
func _run_op() -> void:
	_log("op %d: %s" % [_op, OPS[_op]])
	if STROKES.has(OPS[_op]):
		_begin_stroke(STROKES[OPS[_op]])
		return
	var events := _edits().events
	var why := ""
	match OPS[_op]:
		"forest fall":
			why = events.start(TerrainEvent.forest_fall(FALL_AT, FALL_RADIUS, 7))
		"bridge collapse":
			var bridge: Crossing = _edits().editor.document.crossings[0]
			var middle := (bridge.start + bridge.end) * 0.5
			why = events.start(TerrainEvent.bridge_collapse(bridge.id, middle, 9))
		"undo":
			_result["undid"] = _events().undo()
	if why != "":
		_finish(false, "the %s did not start: %s" % [OPS[_op], why])
		return
	_still = 0
	_set_phase("op")


## Arms the stroke's brush through the Events pane's controller and starts driving it.
func _begin_stroke(stroke: Array) -> void:
	var events := _events()
	events.pick(stroke[0])
	var brush := events.brush()
	if brush == null or not brush.is_active() or brush.editor != _edits().editor:
		_finish(false, "the %s brush did not arm over the live editor" % stroke[0])
		return
	if stroke[0] == SculptTool.ID:
		SculptTool.of(brush).tile = HeightBrush.RAISE
	_stroke = (stroke[2] as Array).duplicate()
	_stroke_ctrl = stroke[1]
	_set_phase("brushing")


## One frame of the stroke: the pointer on the current point (pressed with the stroke's Ctrl
## on the first frame), held HOLD_MS a point, released and put away after the last.
func _step_stroke() -> void:
	var events := _events()
	var brush := events.brush()
	if _stroke.is_empty():
		brush.pressed = false
		brush.finish_gesture()
		events.put_away()
		_still = 0
		_set_phase("op")
		return
	var point: Vector3 = _stroke[0]
	point.y = _edits().editor.ground_height_at(point)
	brush.pointer = _lpc().get_game_map().camera_node.unproject_position(point)
	brush.has_pointer = true
	if not brush.pressed:
		brush.pressed = true
		brush.press_pending = true
		brush.press_ctrl = _stroke_ctrl
		brush.press_shift = false
		_stroke_until = Time.get_ticks_msec() + HOLD_MS
	elif Time.get_ticks_msec() >= _stroke_until:
		_stroke.pop_front()
		_stroke_until = Time.get_ticks_msec() + HOLD_MS


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
			"scout": _scout_y(),
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
		# The host's ground follower set Scout down on the ground the brush raised.
		and float(_result.get("scout_raised_m", 0.0)) > float(_result.get("scout_before_m", 0.0)) + 0.1
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
	_flow().open_join_screen()
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
	_watch_events()
	var step := "op%d" % _op
	if not _has("host", step):
		return
	var host := _read_step("host", step)
	if _edits().op_log.size() < int(host.get("ops", 0)) or not _map_still():
		return
	# Scout follows the host's re-grounding (a reliable state send; it eases there).
	var scout_off := absf(_scout_y() - float(host.get("scout", NAN)))
	if not scout_off <= GROUND_TOLERANCE_M and _scout_frames < SCOUT_FRAMES:
		_scout_frames += 1
		return
	_scout_frames = 0
	var mismatch := MapFingerprint.diff(host.get("fingerprint", {}), _fingerprint())
	_result[OPS[_op]] = {
		"ops": _edits().op_log.size(),
		"mismatch": mismatch,
		"scout_y": snappedf(_scout_y(), 0.001),
		"scout_ok": scout_off <= GROUND_TOLERANCE_M,
	}
	_log("%s: %s" % [OPS[_op], str(_result[OPS[_op]])])
	_mark(step)
	_op += 1
	if _op < OPS.size():
		return
	var ok := _edits().problem == ""
	for label in OPS:
		ok = ok and (_result[label].mismatch as Array).is_empty() and bool(_result[label].scout_ok)
	# Every terrain event played on this board too, before its op landed.
	ok = ok and int(_result.get("events_played", 0)) == EVENT_OPS.size()
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
	_result["scout_y"] = snappedf(_scout_y(), 0.001)
	# A late joiner gets the events' ops only: no motion plays on its board.
	_result["pass"] = (
		mismatch.is_empty()
		and edits.problem == ""
		and int(_result.get("events_played", 0)) == 0
		and absf(_scout_y() - float(host.get("scout", NAN))) <= GROUND_TOLERANCE_M
		and absf(at.y - host_y) <= GROUND_TOLERANCE_M
		and absf(rest.y - at.y) <= GROUND_TOLERANCE_M
	)
	_log("late joiner: %s" % str(_result))
	_mark("done", _result)
	_set_phase("wait_done")
