class_name SessionKeeper
extends Node

## Keeps the hosted session in its session file (SessionFile) and resumes it: the GM can end a
## session tonight and resume it tomorrow with the same shelf, each map's kept state, the
## party and its grants, and the live terrain edits (user decision 2026-10-09). A child of
## Root's TableMover (`TableMover.keeper`), whose kept states it writes; host only, a client
## keeps nothing.
##
## Keeping. Hosting gives the session an id (SessionFile.new_id()); once its shelf has a map,
## the keeper writes it whole: after every table move and every change to the shelf, the table
## pointer or the players (TableMover.changes_changed, SessionChannel.session_changed, at most
## one write a frame), every SAVE_EVERY_S while hosting, when Root leaves a table
## (TableMover.table_closing(), before the table is torn down, so a session ended at a table
## keeps it as it stands) and when the window closes. It writes the shelf with each map's
## hashes and level.json revision, the table pointer, the players by session id, the party
## as it stands (SessionParty.snapshot()) and its grants, and a table file for each map with
## a kept state (TableMover.states, and the table out now as it stands,
## TableMover.table_entry()). A file is rewritten only when its text changed and a map's
## document only when its op log did; a map whose state is gone (saved into its map, or
## discarded) loses its files.
##
## Resume (resume(), from the title): the file is read (prepare_resume()), Root starts hosting
## as for Host on host_requested (a new room and code; Steam lobbies do not persist), and on
## HOSTING restore() lays the session over the one that began, so the room opens with its
## shelf. Each shelf map with a
## kept state is compared with its folder in this host's library: the map files it was kept
## against restore everything; changed files ("the map changed since") keep its tokens and look
## but drop the op log and the kept document, made against the old terrain; a missing folder
## keeps the shelf entry (with no hashes, so no client fetches it) and the kept state as it
## was. notes() says which maps changed or went missing, for the room to say so. The players
## come back as away until they rejoin, the party waits for the next table, and its grants
## map each session id to whatever peer id that player has when it joins (SessionParty).
##
## The keeper's connection handler must run after TableMover's, which forgets every kept state
## when hosting starts: TableMover creates the keeper at the end of its own setup.

## Emitted after each write of the session file.
signal saved(id: String)
## Resume read a session: Root's SessionFlow starts hosting (host_session) and the room opens
## with it.
signal host_requested

## Seconds between saves while hosting.
const SAVE_EVERY_S := 120.0
## Resume could not read the session (W3: what failed, then how to recover).
const RESUME_FAILED := "Could not resume that session: its file is missing or damaged."

var _mover: TableMover = null
## The session being kept: {"id", "name", "created"}, or {} when this peer hosts none.
var _record: Dictionary = {}
## A session prepare_resume() read, restored when hosting starts; {} otherwise.
var _resuming: Dictionary = {}
## What Resume found: shelf key -> SessionFile.CHANGED or MISSING.
var _notes: Dictionary = {}
## Shelf maps whose folder was missing on Resume: key -> the base they were kept against.
var _missing: Dictionary = {}
## The table files written last: shelf key -> file stem.
var _tables: Dictionary = {}
## path -> the text last written there, so an unchanged file is not written again.
var _written: Dictionary = {}
## shelf key -> the log signature (SessionFile.log_signature()) of its document on disk.
var _documents: Dictionary = {}
var _queued := false
var _timer: Timer = null


## The keeper of `mover`'s session (TableMover creates it; see the class doc).
func setup(mover: TableMover) -> void:
	_mover = mover
	_timer = Timer.new()
	_timer.wait_time = SAVE_EVERY_S
	_timer.timeout.connect(save_now)
	add_child(_timer)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	NetworkManager.session.session_changed.connect(_queue_save)
	mover.changes_changed.connect(_queue_save)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now(true)


# =============================================================================
# READ
# =============================================================================


## The id of the session being kept, or "".
func session_id() -> String:
	return str(_record.get("id", ""))


## What Resume found of the shelf: shelf key -> SessionFile.CHANGED (its map files changed
## since, so its live edits were dropped) or SessionFile.MISSING (its folder is gone). A copy.
func notes() -> Dictionary:
	return _notes.duplicate()


# =============================================================================
# KEEPING
# =============================================================================


## Host: write the session file now. With `settle` (the session ends at this table) the
## table's recorded edits become ops first. False when nothing was written (no session, an
## empty shelf) or a write failed.
func save_now(settle := false) -> bool:
	if _record.is_empty() or not NetworkManager.is_host() or _mover == null:
		return false
	var session := NetworkManager.session
	var shelf := session.get_shelf()
	if shelf.is_empty():
		return false
	var id := session_id()
	var entries := {}
	for key: String in _mover.states.keys():
		entries[key] = _mover.states.entry_for(key)
	var live: Variant = _mover.table_entry(settle)
	if live is Dictionary:
		if (live as Dictionary).is_empty():
			entries.erase(session.get_table())
		else:
			entries[session.get_table()] = live
	var shelf_out: Array = []
	var bases := {}
	for ref in shelf:
		var key := SessionChannel.ref_key(ref)
		bases[key] = _base_of(key, ref)
		var out := {"folder": ref.folder, "map_path": ref.map_path, "name": ref.name}
		out.merge(bases[key])
		shelf_out.append(out)
	var ok := true
	var tables := {}
	for key: String in entries:
		if bases.has(key):
			tables[key] = SessionFile.table_stem(key)
			ok = _write_table(id, key, tables[key], entries[key], bases[key]) and ok
	for key: String in _tables:
		if not tables.has(key):
			_forget_table(id, key, _tables[key])
	_tables = tables
	var data := {
		"format": SessionFile.FORMAT,
		"id": id,
		"name": _name(shelf),
		"created": int(_record.get("created", 0)),
		"last_played": int(Time.get_unix_time_from_system()),
		"gm": session.session_id_of(1),
		"shelf": shelf_out,
		"table": session.get_table() if session.get_table() != "" else null,
		"selected": session.get_selected(),
		"players": _players(session.get_players()),
		"party": session.party.snapshot(),
		"grants": session.party.get_grants(),
		"tables": tables,
	}
	ok = _write(SessionFile.session_path(id), SessionFile.to_text(data)) and ok
	if ok:
		saved.emit(id)
	return ok


## The base a map is kept against: its map files' hashes as the shelf has them (the files it
## was set out from) and level.json's modified_at; for a map whose folder was missing on
## Resume and still is, the base it was kept against then.
func _base_of(key: String, ref: Dictionary) -> Dictionary:
	var level := SessionFile.library_level(str(ref.get("folder", "")))
	if _missing.has(key) and level.is_empty():
		return _missing[key]
	return {"hashes": ref.get("hashes", {}), "revision": int(level.get("modified_at", 0))}


## Writes map `key`'s table file (and its document when its op log changed since the last
## one written). False when a write failed.
func _write_table(
	id: String, key: String, stem: String, entry: Dictionary, base: Dictionary
) -> bool:
	var data := TableStates.to_data(entry)
	data["key"] = key
	data["base"] = base
	var ops := TableStates.op_log_of(entry)
	var signature := SessionFile.log_signature(ops)
	var document_path := SessionFile.table_path(id, stem, SessionFile.DOCUMENT_SUFFIX)
	var ok := true
	var document := entry.get("document") as MapDocument
	if ops.is_empty():
		_documents.erase(key)
		SessionFile.remove_file(document_path)
	elif document != null and _documents.get(key, "") != signature:
		ok = SessionFile.write_document(document, document_path) == OK
		if ok:
			_documents[key] = signature
	if _documents.has(key):
		data["document"] = stem
		data["document_log"] = _documents[key]
	return _write(SessionFile.table_path(id, stem), SessionFile.to_text(data)) and ok


## Map `key` has no kept state any more: its files go.
func _forget_table(id: String, key: String, stem: String) -> void:
	for suffix in [".json", SessionFile.DOCUMENT_SUFFIX]:
		var path := SessionFile.table_path(id, stem, suffix)
		SessionFile.remove_file(path)
		_written.erase(path)
	_documents.erase(key)


## Writes `text` to `path` unless it is what was written there last. False when it failed.
func _write(path: String, text: String) -> bool:
	if _written.get(path) == text:
		return true
	if SessionFile.write_text(path, text) != OK:
		push_warning("SessionKeeper: could not write " + path)
		return false
	_written[path] = text
	return true


## The session's name: the one it has, else the first map it shelved.
func _name(shelf: Array[Dictionary]) -> String:
	if str(_record.get("name", "")) == "" and not shelf.is_empty():
		_record["name"] = str(shelf[0].get("name", ""))
	return str(_record.get("name", ""))


## The players as session.json keeps them: session id -> {"name", "role"} (the GM is peer 1).
static func _players(players: Dictionary) -> Dictionary:
	var out := {}
	for id: String in players:
		var entry: Dictionary = players[id]
		var gm := int(entry.get("peer_id", 0)) == 1
		out[id] = {
			"name": str(entry.get("name", "")),
			"role": SessionFile.ROLE_GM if gm else SessionFile.ROLE_PLAYER,
		}
	return out


func _queue_save() -> void:
	if _queued or _record.is_empty():
		return
	_queued = true
	_flush.call_deferred()


func _flush() -> void:
	_queued = false
	save_now()


# =============================================================================
# RESUME
# =============================================================================


## Resume the saved session `id` from the title: its file is read now, then host_requested
## asks Root to start hosting, and the room opens with the session once it has (restore()).
## False, with the reason shown, when the file does not read; false while connected. The
## title's Resume entry is a later card; tests and the net scenarios call this.
func resume(id: String) -> bool:
	if NetworkManager.connection_state != NetworkManager.ConnectionState.OFFLINE:
		return false
	if not prepare_resume(id):
		return false
	host_requested.emit()
	return true


## Read session `id` for Resume; it is restored when hosting starts (restore()). False, with
## the reason shown, when no session file of that id reads.
func prepare_resume(id: String) -> bool:
	var data := SessionFile.sanitize_session(SessionFile.read_json(SessionFile.session_path(id)))
	if data.is_empty() or data.id != SessionFile.clean_id(id):
		UIManager.show_error(RESUME_FAILED)
		return false
	_resuming = data
	return true


## Host: lay the session `data` (SessionFile.sanitize_session()) over the one hosting has just
## begun, and keep it under its own id from now on (see the class doc). Returns notes().
func restore(data: Dictionary) -> Dictionary:
	_reset()
	var id: String = data.id
	_record = {"id": id, "name": data.name, "created": data.created}
	var tables := {}
	for key: String in data.tables:
		var path := SessionFile.table_path(id, data.tables[key])
		var table := SessionFile.sanitize_table(SessionFile.read_json(path))
		if table.key == key:
			tables[key] = table
			_tables[key] = data.tables[key]
	var shelf: Array = []
	for stored: Dictionary in data.shelf:
		var key := SessionChannel.ref_key(stored)
		var found := _found_ref(stored, SessionFile.library_level(stored.folder))
		var table: Dictionary = tables.get(key, {})
		var status := SessionFile.MISSING
		if found.is_empty():
			found = _missing_ref(stored)
			_notes[key] = SessionFile.MISSING
			_missing[key] = table.get("base", {"hashes": stored.hashes, "revision": stored.revision})
		elif not table.is_empty():
			status = SessionFile.map_status(table.base.hashes, found.hashes)
		shelf.append(found)
		if not table.is_empty():
			_restore_table(id, key, table, status)
	var session := NetworkManager.session
	var selected: String = data.table if data.table != "" else data.selected
	session.restore(shelf, data.players, selected)
	session.party.restore(data.party, data.grants)
	_mover.changes_changed.emit()
	return notes()


## The shelf ref of `stored` as this host's library has it now: a fresh MapRef of its folder
## (`level`, its level.json) or of its res:// map, or {} when it is gone.
func _found_ref(stored: Dictionary, level: Dictionary) -> Dictionary:
	if stored.folder != "":
		if level.is_empty():
			return {}
		return SessionChannel.map_ref(NetworkManager.with_map_hashes(level))
	if stored.map_path == "" or not ResourceLoader.exists(stored.map_path):
		return {}
	return SessionChannel.map_ref({"map_path": stored.map_path, "level_name": stored.name})


## A shelf ref for a map whose folder is gone: its name and folder, no hashes (nothing to
## fetch).
static func _missing_ref(stored: Dictionary) -> Dictionary:
	return {"folder": stored.folder, "map_path": stored.map_path, "hashes": {}, "name": stored.name}


## Puts map `key`'s kept state back in TableMover.states as Resume found its map (`status`):
## whole, with its document when that matches its op log, or without its terrain when the map
## changed since.
func _restore_table(id: String, key: String, table: Dictionary, status: StringName) -> void:
	var entry: Dictionary = table.entry
	if status == SessionFile.CHANGED:
		_notes[key] = SessionFile.CHANGED
		_mover.states.store(key, TableStates.without_terrain(entry))
		return
	var ops := TableStates.op_log_of(entry)
	var signature := SessionFile.log_signature(ops)
	if table.document != "" and not ops.is_empty() and table.document_log == signature:
		var path := SessionFile.table_path(id, table.document, SessionFile.DOCUMENT_SUFFIX)
		var document := SessionFile.read_document(path)
		if document != null:
			entry["document"] = document
			_documents[key] = signature
	_mover.states.store(key, entry)


func _reset() -> void:
	_record = {}
	_notes = {}
	_missing = {}
	_tables = {}
	_written = {}
	_documents = {}


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.HOSTING:
			var resuming := _resuming
			_resuming = {}
			if resuming.is_empty():
				_reset()
				var now := int(Time.get_unix_time_from_system())
				_record = {"id": SessionFile.new_id(now, randi()), "name": "", "created": now}
			else:
				restore(resuming)
			_timer.start()
		NetworkManager.ConnectionState.CONNECTING:
			pass
		_:
			_reset()
			_resuming = {}
			_timer.stop()
