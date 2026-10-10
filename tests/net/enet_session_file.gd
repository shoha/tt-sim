extends "res://tests/net/enet_session_room.gd"

## ENet scenario for the session file and Resume (SessionKeeper, SessionFile): a session ended
## at a table tonight comes back tomorrow in a new host process. The first host plays table A
## with a live edit and client's avatar, then ends the session from the table; a fresh host
## process on the same data root resumes it from the session file, and client, rejoining,
## gets table A as the session left it: the raised ground (its op replayed), the moved token
## and its own avatar, which it controls again by its session id.
##
## Reuses enet_session_room.gd's table A (an authored flat map the host builds in its own test
## data root), its placements (Hero A granted to client, Bystander A moved) and its raise, and
## enet_late_joiner.gd's boot, ENet setup and rendezvous files. Three processes, two of them
## started by the launcher:
##
## host: builds table A, opens the session; once client is in the room sets A out, places Hero
##   A (granted to client) and Bystander A, raises the ground and moves Bystander A; once client
##   controls Hero A, ends the session from the table (Pause > Return to Title, which ends it
##   for everyone) and checks the session file it left: table A out with one op and Bystander
##   A, the party Hero A owned by client's session id. Then it starts the resumer (this scene
##   with --role=resume, the same --data-root, its log beside the others as resume.log), waits
##   for it to exit and folds its NET_RESULT into its own.
## resume: a new host process. Resumes the session (SessionKeeper.prepare_resume(), then hosting
##   as Host does; Root.resume flows the same way through host_requested) and checks the room
##   it opens with: the shelf, A's kept state with its op, the party and its grant, no notes.
##   Once client is back in the room, sets A out; Hero A lands on it under client's control.
## client: joins at the start, sees Hero A and controls it at table A; when the host ends the
##   session it goes back to the title, rejoins the resumed session in the room, and once A is
##   out checks it: Bystander A where it was moved, the ground as high as the first host raised
##   it, one op caught up, Hero A on the board and under its control.
##
## Run: godot --headless --path D:/dev/tt-sim res://tests/net/net_launcher.tscn --
##   --data-root=net_launcher --scenario=enet_session_file --peers=2 --timeout-s=300
##   --port=28493

const RESUMER := "resume"
## Seconds the resumer gets less than the first host, so the host outlives it
const RESUMER_MARGIN_S := 30

var _session_id := ""
var _resumer_pid := -1


func _ready() -> void:
	super._ready()
	if _role == RESUMER:
		_session_id = str(_args.get("session", ""))
		_hero = str(_args.get("hero", ""))
		_token_a = str(_args.get("token-a", ""))
		_edit_y = float(_args.get("edit-y", "0"))


func _set_phase(phase: String) -> void:
	_phase = phase
	_log("phase " + phase)
	if _role == "host" or _role == RESUMER:
		_write_json(
			_rv + ".host.json",
			{"phase": phase, "token_a": _token_a, "hero": _hero, "edit_y": _edit_y},
		)


func _finish(ok: bool, reason: String) -> void:
	if _resumer_pid > 0 and OS.is_process_running(_resumer_pid):
		OS.kill(_resumer_pid)
		_result["resumer_killed"] = true
	super._finish(ok, reason)


func _process(_delta: float) -> void:
	if _finished or _main == null or not _main.is_inside_tree():
		return
	if get_tree().current_scene != _main:
		get_tree().current_scene = _main
	match _role:
		"host":
			_process_first_host()
		RESUMER:
			_process_resumer()
		_:
			_process_rejoining_client()


func _keeper() -> SessionKeeper:
	return _mover().keeper


# =============================================================================
# THE FIRST HOST
# =============================================================================


func _process_first_host() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				var problem := _build_table_a()
				if problem != "":
					_finish(false, problem)
					return
				_open_session()
		"room_start":
			if _has(LEAVER, "room0"):
				_set_out_a()
		"table_a_load":
			if _table_up(TABLE_A):
				_host_place_table_a()
		"table_a_edit":
			_host_edit_table_a()
		"table_a":
			if _has(LEAVER, "table_a"):
				_end_session()
		"resuming":
			if not OS.is_process_running(_resumer_pid):
				_collect_first_host()


## End session at the table, as Pause > Return to Title does for the GM; then what the session
## file holds, and the resumer started on this host's data root.
func _end_session() -> void:
	_session_id = _keeper().session_id()
	_main.call("_on_pause_main_menu_requested")
	var data := SessionFile.sanitize_session(
		SessionFile.read_json(SessionFile.session_path(_session_id))
	)
	var table: Dictionary = {}
	if data.get("tables", {}).has(TABLE_A.folder):
		table = SessionFile.sanitize_table(
			SessionFile.read_json(SessionFile.table_path(_session_id, data.tables[TABLE_A.folder]))
		)
	var entry: Dictionary = table.get("entry", {})
	var party: Array = data.get("party", [])
	_result["ended"] = {
		"state_title": _state() == STATE_TITLE,
		"offline": NetworkManager.connection_state == NetworkManager.ConnectionState.OFFLINE,
		"shelf": (data.get("shelf", []) as Array).map(func(r: Dictionary) -> String: return r.folder),
		"table": data.get("table", ""),
		"party": party.map(func(m: Dictionary) -> String: return str(m.state.get("network_id"))),
		"party_owners": party[0].owners if party.size() == 1 else [],
		"grants": data.get("grants", {}),
		"kept_names":
		(entry.get("placements", []) as Array).map(func(p: Dictionary) -> String: return p.token_name),
		"kept_ops": TableStates.op_log_of(entry).size(),
		"document": str(table.get("document", "")) != "",
	}
	_log("session ended: %s %s" % [_session_id, str(_result.ended)])
	_set_phase("ended")
	_resumer_pid = _start_resumer()
	if _resumer_pid <= 0:
		_finish(false, "the resumer did not start")
		return
	_set_phase("resuming")


## This scene again as a new host process on this host's data root (--role=resume).
func _start_resumer() -> int:
	var logs := str(_args.get("out", "")).get_base_dir() + "/"
	var timeout_s := maxi(60, int(_args.get("timeout-s", "300")) - RESUMER_MARGIN_S)
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--log-file",
			logs + RESUMER + ".godot.log",
			scene_file_path,
			"--",
			"--role=" + RESUMER,
			"--out=" + logs + RESUMER + ".log",
			"--data-root=" + str(_args.get("data-root", "")),
			"--rendezvous=" + _rv,
			"--timeout-s=%d" % timeout_s,
			"--port=" + str(_args.get("port", DEFAULT_PORT)),
			"--session=" + _session_id,
			"--hero=" + _hero,
			"--token-a=" + _token_a,
			"--edit-y=%f" % _edit_y,
		]
	)
	var pid := OS.create_process(OS.get_executable_path(), args)
	_log("resumer started (pid %d)" % pid)
	return pid


## The resumer has exited: its result and client's report, then the verdict.
func _collect_first_host() -> void:
	var logs := str(_args.get("out", "")).get_base_dir() + "/"
	var resumed := _last_net_result(logs + RESUMER + ".log")
	var client := _read_json("%s.%s.json" % [_rv, LEAVER])
	_result["resumer"] = resumed
	_result["client"] = client
	var ended: Dictionary = _result.get("ended", {})
	var grant := {_leaver_id(): [_hero]}
	var checks := {
		"ended_at_title": bool(ended.get("state_title")) and bool(ended.get("offline")),
		"file_shelf": ended.get("shelf") == [TABLE_A.folder],
		"file_table": ended.get("table") == TABLE_A.folder,
		"file_party": ended.get("party") == [_hero] and ended.get("party_owners") == [_leaver_id()],
		"file_grants": ended.get("grants") == grant,
		"file_kept": ended.get("kept_names") == [BYSTANDER] and int(ended.get("kept_ops")) == 1,
		"resumer_passed": bool(resumed.get("pass", false)),
		"client_passed": bool(client.get("pass", false)),
	}
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_finish(ok, "resumed and rejoined" if ok else "a check failed")


## The last NET_RESULT {json} line of the log at `path`, or {}.
func _last_net_result(path: String) -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(path):
		return result
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var at := line.find("NET_RESULT ")
		if at >= 0:
			var parsed: Variant = JSON.parse_string(line.substr(at + "NET_RESULT ".length()))
			result = parsed if parsed is Dictionary else {}
	return result


# =============================================================================
# THE RESUMER (a new host process)
# =============================================================================


func _process_resumer() -> void:
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_resume()
		"resumed":
			if _has(LEAVER, "room1"):
				_mover().set_out(TABLE_A.folder)
				_set_phase("a2_load")
		"a2_load":
			if _table_up(TABLE_A) and _hero_landed() and _named(BYSTANDER) != null:
				_host_check_table_a2()
		"table_a2":
			if _has(LEAVER, "json"):
				_collect_resumer()


## Resume as the title will: the file read, then hosting (over ENet here); the room opens with
## the session restored.
func _resume() -> void:
	if not _keeper().prepare_resume(_session_id):
		_finish(false, "session %s did not read" % _session_id)
		return
	_open_session()
	var kept := _mover().states.entry_for(TABLE_A.folder)
	var members := NetworkManager.session.party.get_members()
	_result["restored"] = {
		"session_id": _keeper().session_id(),
		"notes": _keeper().notes(),
		"state_room": _state() == STATE_ROOM,
		"shelf": _shelf_folders(),
		"kept_names":
		(kept.get("placements", []) as Array).map(func(p: Dictionary) -> String: return p.token_name),
		"kept_ops": TableStates.op_log_of(kept).size(),
		"document": kept.get("document") != null,
		"party": members.map(func(m: Dictionary) -> String: return str(m.state.network_id)),
		"party_owners": members[0].owners if members.size() == 1 else [],
		"grants": NetworkManager.session.party.get_grants(),
		"client_entry": NetworkManager.session.get_players().get(_leaver_id(), {}),
	}
	_log("resumed: %s" % str(_result.restored))
	_set_phase("resumed")


func _collect_resumer() -> void:
	var restored: Dictionary = _result.get("restored", {})
	var table_a2: Dictionary = _result.get("table_a2", {})
	var client_peer := NetworkManager.session.peer_for(_leaver_id())
	var checks := {
		"same_session": restored.get("session_id") == _session_id,
		"no_notes": (restored.get("notes", {1: 1}) as Dictionary).is_empty(),
		"room": bool(restored.get("state_room")) and restored.get("shelf") == [TABLE_A.folder],
		"kept": restored.get("kept_names") == [BYSTANDER] and int(restored.get("kept_ops")) == 1,
		"party":
		(
			restored.get("party") == [_hero]
			and restored.get("party_owners") == [_leaver_id()]
			and restored.get("grants") == {_leaver_id(): [_hero]}
		),
		"client_away_until_rejoin": int(restored.get("client_entry", {}).get("peer_id", -1)) == 0,
		"a_restored": _restored(table_a2, _edit_y) and table_a2.get("table") == TABLE_A.folder,
		"hero_granted":
		client_peer > 0 and GameState.get_peers_with_permission(_hero, CONTROL) == [client_peer],
	}
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_finish(ok, "table A resumed")


# =============================================================================
# CLIENT
# =============================================================================


func _process_rejoining_client() -> void:
	var host_phase := str(_read_json(_rv + ".host.json").get("phase", ""))
	if host_phase == "done":
		_finish(_phase == "wait_done" and bool(_result.get("pass", false)), "host done")
		return
	match _phase:
		"title":
			if _state() == STATE_TITLE:
				_main.connect("state_changed", _on_state_changed)
				_set_phase("wait_to_join")
		"wait_to_join":
			if host_phase == "room_start":
				_join_session()
		"wait_room0":
			if _state() == STATE_ROOM:
				_mark("room0")
				_set_phase("table_a")
		"table_a":
			var hero := _token("hero")
			if _table_up(TABLE_A) and _on_board(hero) and _controls(hero):
				_result["control_at_a"] = true
				_mark("table_a")
				_set_phase("wait_end")
		"wait_end":
			if NetworkManager.connection_state == NetworkManager.ConnectionState.OFFLINE:
				_session_ended()
		"wait_resume":
			if host_phase == "resumed":
				_join_session()
				_set_phase("wait_room1")
		"wait_room1":
			if _state() == STATE_ROOM:
				_mark("room1")
				_set_phase("table_a2")
		"table_a2":
			_client_at_resumed_a(host_phase)


## The host ended the session: the "connection lost" dialog this client gets is closed the way
## its button does (back to the title), ready to rejoin.
func _session_ended() -> void:
	var dialog_path: String = UIManager.CONFIRMATION_DIALOG_SCENE.resource_path
	var dialogs := get_tree().root.get_children().filter(
		func(n: Node) -> bool: return n.scene_file_path == dialog_path
	)
	_result["ended"] = {"dialogs": dialogs.size(), "state": _state()}
	for dialog in dialogs:
		dialog.queue_free()
	_main.call("change_state", STATE_TITLE)
	_set_phase("wait_resume")


## Table A in the resumed session, once the resumer has it up and this peer's matches it (or
## RESTORE_FRAMES later with what it has): the edit, the moved token and its own avatar.
func _client_at_resumed_a(host_phase: String) -> void:
	var hero := _token("hero")
	if host_phase != "table_a2" or not (_table_up(TABLE_A) and _on_board(hero)):
		return
	var edit_y := float(_read_json(_rv + ".host.json").get("edit_y", 0.0))
	var a := _table_a_now()
	_restore_frames += 1
	var restored := bool(a.settled) and _restored(a, edit_y) and _controls(hero)
	if not restored and _restore_frames < RESTORE_FRAMES:
		return
	var checks := {
		"a_restored": bool(a.settled) and _restored(a, edit_y),
		"hero_control": _controls(hero),
		"session_table": NetworkManager.session.get_table() == TABLE_A.folder,
		"controlled_before": bool(_result.get("control_at_a", false)),
	}
	_result["table_a2"] = a
	_result["checks"] = checks
	var ok := true
	for key in checks:
		ok = ok and bool(checks[key])
	_result["pass"] = ok
	_log("table A resumed: %s %s" % [str(a), str(checks)])
	_mark("json", _result)
	_set_phase("wait_done")
