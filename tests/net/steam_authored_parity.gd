extends Node
## Real-Steam parity scenario: a client given only the host's map.ttmap builds the same map.
##
## Not part of the GUT suite: it needs the Steam client and a second Steam account, so two
## processes run it, one per role. The host runs unsandboxed under the main account; the
## client runs in the Sandboxie box that holds the alt account (docs/NETWORKING.md, "Testing
## over real Steam"; the plumbing is steam_map_download.gd's). Unlike that scenario this one
## runs the whole game: the scene adds the main scene and drives its own state machine (host
## lobby, client lobby, Start), so the host plays the saved level through LevelPlayLoader and
## the client receives the level, downloads the document and loads it through the same path.
##
## Host: plays --level (a saved authored level under user://levels whose folder starts with
## "_nettest_"; built by tools/render_jobs/jobs/nettest_parity_build.json and kept), hosts,
## writes the room code to --rendezvous, starts the game once the client has joined, then
## places three tokens through the ordinary spawn path (which syncs them to clients): one on
## the arch's deck, one standing in the ford, one wading the river a few metres below the
## ford. Once they settle it writes its fingerprint (MapFingerprint) and the tokens to
## <rendezvous>.host.json. It finishes when the client leaves.
## Client: drops any cached copy of the level's map files (and any same-named local level),
## joins, lets the game download and load the map, waits for the host's file and for the
## three tokens to settle, fingerprints its own map and compares. Pass: the fingerprints
## match; every token's base Y within TOKEN_DY_M of the host's; the deck token stands on a
## surface above the water and is not submerged; the ford and wading tokens show the same
## submerged cue as on the host, and the wading token's cue shows.
##
## Args after `--`: --role=host|client --rendezvous=<abs path> --out=<abs path>
##   --level=<_nettest_ folder> (default _nettest_parity) --timeout-s=<n> (default 420)
##   --capture-dir=<abs path>: in a windowed run, after the measurement, save the home view,
##   the arch and the ford (camera zoom CLOSE_ZOOM) at 960x540 as <role>_<name>.png (window)
##   and <role>_<name>_sub.png (3D view).
## Each run writes its log and one final `NET_RESULT {json}` line to --out and stdout, then
## quits with exit code 0 (pass) or 1 (fail).

const APP_ID := 480
const LEVEL_PREFIX := "_nettest_"
const DEFAULT_LEVEL := "_nettest_parity"
const QUIT_DELAY_S := 1.0
## Root.State values the scenario drives (scenes/root.gd).
const STATE_TITLE := 0
## The host starts the game this long after the client joins.
const START_DELAY_S := 1.0
## The host records its tokens this long after placing them (the drop and its tween).
const SETTLE_S := 4.0
## The wading token stands this far downstream of the ford's middle.
const WADE_DOWNSTREAM_M := 3.5
## Token base heights may differ between peers by this much.
const TOKEN_DY_M := 0.05
## A client token counts as settled when it moved less than this over STABLE_S, and its
## height matches the host's (its model has arrived) within STABLE_HEIGHT_M.
const STABLE_M := 0.001
const STABLE_S := 1.5
const STABLE_HEIGHT_M := 0.01
## The client compares anyway after this long waiting for settled tokens.
const SETTLE_LIMIT_S := 60.0
const CLOSE_ZOOM := 8.0
const CAPTURE_SCALE := 0.5

var _args: Dictionary = {}
var _role := ""
var _level := DEFAULT_LEVEL
var _out: FileAccess
var _start_ms := 0
var _result: Dictionary = {}
var _finished := false
var _rendezvous_path := ""
var _main: Node = null
var _phase := "boot"
var _phase_ms := 0
## label -> network id of the tokens (host: placed; client: from the host's file).
var _tokens: Dictionary = {}

# Client state.
var _host: Dictionary = {}
var _last_positions: Dictionary = {}
var _stable_since_ms := -1
var _downloaded := false


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
	get_tree().create_timer(float(_args.get("timeout-s", "420"))).timeout.connect(_on_hard_timeout)
	_log("scenario start role=%s" % _role)
	if not _level.begins_with(LEVEL_PREFIX):
		_finish(false, "level folder must start with " + LEVEL_PREFIX)
		return
	if _role != "host" and _role != "client":
		_finish(false, "unknown role")
		return
	if not _init_steam():
		_finish(false, "steam init failed")
		return
	var main_scene := load(str(ProjectSettings.get_setting("application/run/main_scene")))
	_main = (main_scene as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	_set_phase("title")


func _process(_delta: float) -> void:
	if _finished or _main == null or not _main.is_inside_tree():
		return
	match _phase:
		"title":
			if get_tree().current_scene != _main:
				get_tree().current_scene = _main
			if int(_main.call("get_current_state")) != STATE_TITLE:
				return
			if _role == "host":
				_start_host()
			else:
				_start_client()
		"join":
			_poll_rendezvous()
		"host_load", "client_load":
			_poll_loaded()
		"client_tokens":
			_poll_client_tokens()


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


func _set_phase(phase: String) -> void:
	_phase = phase
	_phase_ms = Time.get_ticks_msec()
	_log("phase " + phase)


## As steam_map_download.gd: agent runs have no steam_appid.txt in the working directory, so
## the scenario initialises Steam with the test app id and tells NetworkManager it is ready.
func _init_steam() -> bool:
	var init: Dictionary = Steam.steamInitEx(APP_ID, false)
	_log("steamInitEx -> %s" % str(init))
	if int(init.get("status", -1)) != 0:
		return false
	NetworkManager.set("_steam_initialized", true)
	_result["steam_id"] = str(Steam.getSteamID())
	return true


func _lpc() -> LevelPlayController:
	return _main.get("_level_play_controller") as LevelPlayController


func _game_map() -> GameMap:
	return _main.get("_game_map") as GameMap


## Root's SessionFlow: Host, Join, the room and Set out.
func _flow() -> SessionFlow:
	return _main.get("_session_flow") as SessionFlow


func _host_file() -> String:
	return _rendezvous_path + ".host.json"


# --- Host --------------------------------------------------------------------


## SessionFlow.host_from_title for a level folder: the level becomes the pending level and
## hosting starts (SessionFlow.host_session); the room opens once hosting.
func _start_host() -> void:
	var level := LevelManager.load_level_folder(_level, false)
	if level == null or level.map_document == "":
		_finish(false, "no authored level " + _level)
		return
	for path in [_rendezvous_path, _host_file()]:
		if path != "" and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	NetworkManager.room_code_received.connect(_on_room_code)
	NetworkManager.player_joined.connect(_on_host_player_joined)
	NetworkManager.player_left.connect(_on_host_player_left)
	NetworkManager.connection_failed.connect(func(reason: String): _finish(false, reason))
	_flow().host_session(level)
	_set_phase("lobby")


func _on_room_code(code: String) -> void:
	_log("room code " + code)
	if _rendezvous_path != "":
		var f := FileAccess.open(_rendezvous_path, FileAccess.WRITE)
		f.store_string(code)
		f.close()


func _on_host_player_joined(peer_id: int, _info: Dictionary) -> void:
	if peer_id == 1 or _phase != "lobby":
		return
	_log("peer %d joined; starting" % peer_id)
	await get_tree().create_timer(START_DELAY_S).timeout
	_flow().set_out_pending()
	_set_phase("host_load")


func _on_host_player_left(peer_id: int, _info: Dictionary) -> void:
	_log("peer %d left" % peer_id)
	while _phase == "capture":
		await get_tree().process_frame
	_finish(_result.has("fingerprint") and _tokens.size() == 3, "client left")


## Places the three tokens, waits for them to settle and writes the host's file.
func _host_place_tokens() -> void:
	var points := _token_points()
	if points.is_empty():
		_finish(false, "no arch or ford in the map")
		return
	var asset := _token_asset()
	if asset.is_empty():
		_finish(false, "no cached token asset")
		return
	_result["asset"] = "%s/%s" % asset
	for label in points:
		var at: Vector3 = points[label]
		var token := _lpc().spawn_asset(asset[0], asset[1], "default", at, true)
		if token == null:
			_finish(false, "spawn failed: " + label)
			return
		_tokens[label] = token.network_id
		_log("placed %s %s at %s" % [label, token.network_id, str(at)])
	_set_phase("host_settle")
	await get_tree().create_timer(SETTLE_S).timeout
	_result["tokens"] = _token_states()
	var f := FileAccess.open(_host_file(), FileAccess.WRITE)
	f.store_string(
		JSON.stringify(
			{"fingerprint": _result["fingerprint"], "tokens": _result["tokens"], "ids": _tokens}
		)
	)
	f.close()
	_log("host file written")
	await _maybe_capture()
	_set_phase("host_wait")


## Where the tokens go, in world space: {"deck": over the arch's middle, "ford": over the
## ford's middle, "wade": WADE_DOWNSTREAM_M down the river from the ford}, each a little over
## the top walkable surface there; {} without an arch or a ford.
func _token_points() -> Dictionary:
	var arch := _crossing_box("Arch")
	var ford := _crossing_box("Ford")
	if arch.size == Vector3.ZERO or ford.size == Vector3.ZERO:
		return {}
	var out := {}
	out["deck"] = _over_ground(arch.get_center())
	out["ford"] = _over_ground(ford.get_center())
	out["wade"] = _over_ground(_downstream_of(ford.get_center(), WADE_DOWNSTREAM_M))
	return out


## The world AABB of the crossing mesh named `part` ("Arch", "Ford") in the loaded map, or an
## empty AABB.
func _crossing_box(part: String) -> AABB:
	var map := _lpc().loaded_map_instance
	var holder := map.get_node_or_null(NodePath(MapFingerprint.CROSSINGS_NODE)) if map else null
	if holder == null:
		return AABB()
	for crossing in holder.get_children():
		var mesh := crossing.get_node_or_null(NodePath(part)) as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			return mesh.global_transform * mesh.mesh.get_aabb()
	return AABB()


func _over_ground(at: Vector3) -> Vector3:
	var space := _game_map().world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(at.x, 0, at.z))
	return Vector3(at.x, (hit.y if hit != Vector3.INF else 0.0) + 0.25, at.z)


## The point `distance` metres downstream along the river nearest world point `at` (rivers
## run from their first point to their last).
func _downstream_of(at: Vector3, distance: float) -> Vector3:
	var map := _lpc().loaded_map_instance
	var doc := _lpc().loaded_map_document
	var local := map.global_transform.affine_inverse() * at
	var here := Vector2(local.x, local.z)
	var best: WaterBody = null
	var best_i := 0
	var best_d := INF
	for body in doc.water_bodies:
		if body.kind != WaterBody.Kind.RIVER:
			continue
		for i in body.points.size():
			var d := body.points[i].distance_to(here)
			if d < best_d:
				best_d = d
				best = body
				best_i = i
	if best == null:
		return at
	var walked := 0.0
	var point := best.points[best_i]
	for i in range(best_i + 1, best.points.size()):
		walked += best.points[i].distance_to(best.points[i - 1])
		point = best.points[i]
		if walked >= distance:
			break
	return map.global_transform * Vector3(point.x, 0, point.y)


## The first locally cached token asset that is not a light (as probes/water.gd picks one):
## [pack id, asset id], or [].
func _token_asset() -> Array:
	for pack in AssetManager.get_packs():
		var ids: Array = (pack as AssetPack).assets.keys()
		ids.sort()
		for id in ids:
			if String(id).to_lower().contains("light"):
				continue
			var path := AssetManager.get_model_path(pack.pack_id, id)
			if (
				(path != "" and FileAccess.file_exists(path))
				or AssetManager.cache.has_cached(pack.pack_id, id, "default")
			):
				return [pack.pack_id, id]
	return []


# --- Client ------------------------------------------------------------------


## The Sandboxie box runs as the same Windows user, so it reads the host's user:// through
## (copy on write): the host's level folder is visible to the client until the box deletes
## its view of it, which leaves the host's files alone. Without that the client would load
## the host's file instead of downloading it.
func _start_client() -> void:
	_drop_cached_map()
	var local := LevelManager.folder_path(_level)
	_result["local_level_found"] = DirAccess.dir_exists_absolute(local)
	if _result["local_level_found"]:
		_remove_folder(local)
	var document := LevelManager.map_document_path(_level)
	_result["local_document_after_drop"] = FileAccess.file_exists(document)
	_result["cached_document_after_drop"] = AssetManager.streamer.get_cached_map_file(
		_level, Paths.LEVEL_MAP_DOCUMENT_VARIANT, ""
	)
	_log(
		(
			"local level %s; after the drop: document %s, cached %s"
			% [
				_result["local_level_found"],
				_result["local_document_after_drop"],
				_result["cached_document_after_drop"],
			]
		)
	)
	if _result["local_document_after_drop"]:
		_finish(false, "could not drop the local copy of " + _level)
		return
	NetworkManager.connection_failed.connect(func(reason: String): _finish(false, reason))
	_lpc().map_download_completed.connect(func(_folder: String): _downloaded = true)
	_set_phase("join")


## Drops any cached copy of the level's map files, so the client must download them.
func _drop_cached_map() -> void:
	for variant in [Paths.LEVEL_MAP_VARIANT, Paths.LEVEL_MAP_DOCUMENT_VARIANT]:
		AssetManager.cache.remove_cached(
			Paths.LEVEL_MAPS_PACK_ID, _level, variant, Paths.get_level_map_file_type(variant)
		)


func _remove_folder(folder: String) -> void:
	if not folder.trim_suffix("/").get_file().begins_with(LEVEL_PREFIX):
		return
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		var err := dir.remove(file_name)
		_log("remove %s -> %s" % [file_name, error_string(err)])
	_log("remove %s -> %s" % [folder, error_string(DirAccess.remove_absolute(folder))])


## Joins in place on the title's Play together card, as a player typing the code does: Join
## opens the field, the code goes in, and Join submits it (Root's SessionFlow joins over
## Steam).
func _poll_rendezvous() -> void:
	if _rendezvous_path == "" or not FileAccess.file_exists(_rendezvous_path):
		return
	var code := FileAccess.get_file_as_string(_rendezvous_path).strip_edges()
	if code == "":
		return
	_log("joining room " + code)
	var title := _main.get("_title_screen") as TitleScreen
	if title == null:
		_finish(false, "no title card to join from")
		return
	title.play_together.open_join()
	title.play_together.code_edit.text = code
	title.play_together.submit()
	_set_phase("client_load")


func _poll_loaded() -> void:
	var lpc := _lpc()
	if lpc == null or lpc.is_loading() or not is_instance_valid(lpc.loaded_map_instance):
		return
	if lpc.loaded_map_document == null:
		_finish(false, "the loaded map has no document")
		return
	_result["fingerprint"] = MapFingerprint.of(lpc.loaded_map_instance, lpc.loaded_map_document)
	_log("map loaded; fingerprint taken")
	if _role == "host":
		_set_phase("host_place")
		_host_place_tokens()
	else:
		_result["downloaded"] = _downloaded
		_set_phase("client_tokens")


## Waits for the host's file and for its tokens to arrive and settle here, then compares.
func _poll_client_tokens() -> void:
	if _host.is_empty():
		if not FileAccess.file_exists(_host_file()):
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_host_file()))
		if not parsed is Dictionary:
			return
		_host = parsed
		_tokens = _host.get("ids", {})
	var states := _token_states()
	if states.size() < _tokens.size():
		return
	var now := Time.get_ticks_msec()
	var moved := false
	var heights_match := true
	for label in states:
		var at := Vector3(states[label].x, states[label].y, states[label].z)
		if _last_positions.get(label, Vector3.INF).distance_to(at) > STABLE_M:
			moved = true
		_last_positions[label] = at
		var host_height := float(_host.tokens.get(label, {}).get("height", 0.0))
		heights_match = heights_match and absf(states[label].height - host_height) < STABLE_HEIGHT_M
	if moved or not heights_match:
		_stable_since_ms = now
	var waited := (now - _phase_ms) / 1000.0
	if (now - _stable_since_ms) / 1000.0 < STABLE_S and waited < SETTLE_LIMIT_S:
		return
	_result["settled"] = waited < SETTLE_LIMIT_S
	_result["tokens"] = states
	_compare()


## The verdict (see the header), into the result.
func _compare() -> void:
	var problems := PackedStringArray()
	if not bool(_result.get("downloaded", false)):
		problems.append("the client loaded a local copy instead of downloading the map")
	var mismatched := MapFingerprint.diff(_host.get("fingerprint", {}), _result["fingerprint"])
	_result["fingerprint_mismatch"] = mismatched
	if not mismatched.is_empty():
		problems.append("fingerprint differs: " + ", ".join(mismatched))
	var host_tokens: Dictionary = _host.get("tokens", {})
	var mine: Dictionary = _result["tokens"]
	for label in host_tokens:
		var theirs: Dictionary = host_tokens[label]
		var here: Dictionary = mine.get(label, {})
		if here.is_empty():
			problems.append(label + " missing")
			continue
		if absf(float(here.y) - float(theirs.y)) > TOKEN_DY_M:
			problems.append("%s y %.3f vs host %.3f" % [label, here.y, theirs.y])
		if bool(here.submerged) != bool(theirs.submerged):
			problems.append(
				"%s submerged %s vs host %s" % [label, here.submerged, theirs.submerged]
			)
	var deck: Dictionary = mine.get("deck", {})
	if not deck.is_empty():
		if bool(deck.submerged):
			problems.append("deck token submerged")
		if deck.water_y != null and float(deck.y) <= float(deck.water_y):
			problems.append("deck token not above the water")
		if absf(float(deck.y) - float(deck.ground_y)) > TOKEN_DY_M:
			problems.append("deck token not on the deck surface")
	var wade: Dictionary = mine.get("wade", {})
	if not wade.is_empty() and not bool(wade.submerged):
		problems.append("wading token shows no submerged ring")
	_result["problems"] = problems
	await _maybe_capture()
	_finish(problems.is_empty(), "compared" if problems.is_empty() else "; ".join(problems))


# --- Shared ------------------------------------------------------------------


## label -> {network_id, x, y (the base), z, height, submerged (the cue shows), ground_y (the
## top walkable surface under the base, deck or bed), water_y (the water surface under the
## top, or null)} for every token in _tokens present here.
func _token_states() -> Dictionary:
	var by_id := {}
	for node in get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token == null:
			continue
		var found := token.find_children("*", "DraggableToken", true, false)
		if not found.is_empty():
			by_id[token.network_id] = found[0]
	var space := _game_map().world_viewport.find_world_3d().direct_space_state
	var out := {}
	for label in _tokens:
		var draggable := by_id.get(_tokens[label]) as DraggableToken
		if draggable == null:
			continue
		var base: Vector3 = draggable.water.base_position()
		var height: float = draggable.cue_box().size.y
		var ground := DragPlaceController.raycast_terrain_down(space, base, base.y + 0.5)
		var water := WaterSurface.water_below(space, base, base.y + height + 3.0)
		out[label] = {
			"network_id": _tokens[label],
			"x": snappedf(base.x, 0.001),
			"y": snappedf(base.y, 0.001),
			"z": snappedf(base.z, 0.001),
			"height": snappedf(height, 0.001),
			"submerged": draggable.is_submerged_cue_shown(),
			"ground_y": snappedf(ground.y, 0.001) if ground != Vector3.INF else null,
			"water_y": snappedf(float(water.y), 0.001) if not water.is_empty() else null,
		}
	return out


## With --capture-dir: the home view, then the arch and the ford at CLOSE_ZOOM.
func _maybe_capture() -> void:
	var dir := str(_args.get("capture-dir", ""))
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	var previous := _phase
	_set_phase("capture")
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1920, 1080)
	var gm := _game_map()
	var cc := gm.get_camera_controller()
	cc.call("_reset_camera_to_home")
	await get_tree().create_timer(2.0).timeout
	await _grab(dir, "home")
	# Zoom first: the view centre's ground offset changes with the zoom (render jobs order it
	# the same way).
	cc.set("_target_zoom", CLOSE_ZOOM)
	await get_tree().create_timer(1.5).timeout
	for part in ["Arch", "Ford"]:
		# The view offset centres a point on y = 0; a surface `h` higher projects like the
		# plane point h / tan(pitch) further along the view (probes/landform.gd's parallax).
		var top := _over_ground(_crossing_box(part).get_center()) - Vector3(0, 0.25, 0)
		var forward := -gm.camera_node.global_transform.basis.z
		var flat := Vector2(forward.x, forward.z)
		var at := Vector2(top.x, top.z) + flat * (top.y / maxf(-forward.y, 0.01))
		var off: Vector2 = cc.call("_get_view_center_ground_offset")
		var holder := gm.cameraholder_node
		holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)
		await get_tree().create_timer(2.0).timeout
		await _grab(dir, part.to_lower())
	_set_phase(previous)


func _grab(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var images: Array[Image] = [
		get_viewport().get_texture().get_image(),
		_game_map().world_viewport.get_texture().get_image(),
	]
	var suffixes := ["", "_sub"]
	for k in images.size():
		var img := images[k]
		img.resize(
			int(img.get_width() * CAPTURE_SCALE),
			int(img.get_height() * CAPTURE_SCALE),
			Image.INTERPOLATE_LANCZOS
		)
		img.save_png(dir.path_join("%s_%s%s.png" % [_role, name, suffixes[k]]))
	_log("captured %s (%s)" % [name, str(images[0].get_size())])


func _on_hard_timeout() -> void:
	_finish(false, "timeout in phase " + _phase)


func _finish(ok: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	_result["pass"] = ok
	_result["reason"] = reason
	_result["elapsed_ms"] = Time.get_ticks_msec() - _start_ms
	NetworkManager.disconnect_game()
	if _role == "client":
		_drop_cached_map()
	_log("NET_RESULT " + JSON.stringify(_result))
	if _out:
		_out.close()
		_out = null
	await get_tree().create_timer(QUIT_DELAY_S).timeout
	get_tree().quit(0 if ok else 1)
