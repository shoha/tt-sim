class_name SessionFile
extends RefCounted

## The session file on disk: one folder per hosted session under Paths.SESSIONS_DIR, so the GM
## can end a session tonight and resume it tomorrow (user decision 2026-10-09; the sketch is
## docs/plans/2026-10-09-v0.2-evaluation/probes/session_probe.md "Session file sketch").
## SessionKeeper decides what goes in and when; this class is the files themselves: their
## shape, the atomic write, and reading them back as files anyone could have edited.
##
##   <id>/session.json         the session: its name and times, the GM, the shelf, the table
##                             pointer, the players, the party and its grants, and the index
##                             of the table files
##   <id>/tables/<stem>.json   one per map with a kept state (TableStates.to_data()): its
##                             placements, look and op log, and the base it was kept against
##                             (the map files' hashes and level.json's modified_at)
##   <id>/tables/<stem>.ttmap  the edited map document of a map whose terrain changed, for a
##                             Save into map from the shelf after Resume
##
## Every file is written whole to "<name>.tmp" and renamed over the old one (write_json(),
## write_document()), so a write that fails or a process that dies part way never leaves a
## partial file where a good one was. Nothing here writes into the level library
## (Paths.LEVELS_DIR); a map's folder is only read, to compare it with the base on Resume.

## session.json's format; a file of another format is not read.
const FORMAT := 1
const SESSION_NAME := "session.json"
const TABLES_DIR := "tables/"
const TMP_SUFFIX := ".tmp"
const DOCUMENT_SUFFIX := ".ttmap"
const MAX_ID := 64
const ID_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
## What Resume finds of a shelf map (map_status()).
const SAME := &"same"
const CHANGED := &"changed"
const MISSING := &"missing"
## The GM's and a player's role in session.json.
const ROLE_GM := "gm"
const ROLE_PLAYER := "player"


## The folder of session `id` (a clean_id()), ending in "/".
static func folder_of(id: String) -> String:
	return Paths.SESSIONS_DIR + clean_id(id) + "/"


## session.json of session `id`.
static func session_path(id: String) -> String:
	return folder_of(id) + SESSION_NAME


## The path of a table file of session `id`: `stem` (table_stem()) plus `suffix`.
static func table_path(id: String, stem: String, suffix := ".json") -> String:
	return folder_of(id) + TABLES_DIR + stem + suffix


## A new session's id from the time it began (unix seconds) and a random `salt`: sortable by
## time, unique across sessions begun in the same second. Pure.
static func new_id(unix_time: int, salt: int) -> String:
	var at := Time.get_datetime_dict_from_unix_time(unix_time)
	return (
		"%04d%02d%02d-%02d%02d%02d-%04x"
		% [at.year, at.month, at.day, at.hour, at.minute, at.second, salt & 0xffff]
	)


## A session id as the store may use it: 1 to MAX_ID letters, digits, "-" or "_", else "" (an
## id read from a file or given on a command line). Pure.
static func clean_id(raw: Variant) -> String:
	if not raw is String:
		return ""
	var id := raw as String
	if id.is_empty() or id.length() > MAX_ID:
		return ""
	for character in id:
		if not ID_CHARS.contains(character):
			return ""
	return id


## The file stem of shelf key `key`: the level folder itself when it is a clean name (a level
## folder always is), else "map_" and the key's hash (a res:// map path). Pure.
static func table_stem(key: String) -> String:
	if clean_id(key) != "":
		return key
	return "map_" + key.md5_text().left(16)


## A signature of an op log (its length and its last op), so a document is written once per
## state of the log and a document that lags its log is known on reading. Pure.
static func log_signature(ops: Array[PackedByteArray]) -> String:
	if ops.is_empty():
		return "0"
	return "%d:%s" % [ops.size(), Marshalls.raw_to_base64(ops.back()).md5_text()]


# =============================================================================
# FILES
# =============================================================================


## Writes `data` as JSON to `path` atomically: the whole text to "<path>.tmp", then renamed
## over `path`. On any failure `path` is left as it was. Returns the error.
static func write_json(path: String, data: Dictionary) -> Error:
	return write_text(path, to_text(data))


## `data` as the session file's JSON: tab-indented, keys sorted, every float at full precision
## (a look read back must equal the look written). Pure.
static func to_text(data: Dictionary) -> String:
	return JSON.stringify(data, "\t", true, true)


## Writes `text` to `path` atomically (see write_json()).
static func write_text(path: String, text: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_string(text)
	file.flush()
	var error := file.get_error() if stored else ERR_FILE_CANT_WRITE
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(tmp, path)
	if error != OK:
		DirAccess.remove_absolute(tmp)
	return error


## The dictionary in the JSON file `path`, or {} when it is missing or is not one.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Writes `doc` to `path` atomically, through MapDocumentIO.write (the authoring save's
## writer) into "<path>.tmp" and a rename. Returns the error.
static func write_document(doc: MapDocument, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TMP_SUFFIX
	var error := MapDocumentIO.write(doc, tmp)
	if error == OK:
		error = DirAccess.rename_absolute(tmp, path)
	if error != OK:
		DirAccess.remove_absolute(tmp)
	return error


## The map document at `path`, or null when it is missing or does not read.
static func read_document(path: String) -> MapDocument:
	if not FileAccess.file_exists(path):
		return null
	return MapDocumentIO.read(path).get("document") as MapDocument


## Deletes the file `path` and its leftover ".tmp", if any.
static func remove_file(path: String) -> void:
	for file in [path, path + TMP_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Deletes session `id`'s folder and everything in it. False when there was none.
static func remove(id: String) -> bool:
	var clean := clean_id(id)
	if clean == "" or not DirAccess.dir_exists_absolute(folder_of(clean)):
		return false
	var tables := folder_of(clean) + TABLES_DIR
	for folder in [tables, folder_of(clean)]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for file_name in dir.get_files():
			dir.remove(file_name)
		DirAccess.remove_absolute(folder)
	return true


## Every saved session, the last played first: {"id", "name", "last_played", "maps"} each,
## for a Resume list.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(Paths.SESSIONS_DIR)
	if dir == null:
		return out
	for id in dir.get_directories():
		var data := sanitize_session(read_json(session_path(id)))
		if data.is_empty() or data.id != id:
			continue
		out.append(
			{
				"id": id,
				"name": data.name,
				"last_played": data.last_played,
				"maps": (data.shelf as Array).size(),
			}
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a.last_played) > int(b.last_played)
	)
	return out


# =============================================================================
# THE LIBRARY SIDE (read only)
# =============================================================================


## The level.json dictionary of the library folder `folder` (level_folder set), or {} when the
## folder has no level.json that reads.
static func library_level(folder: String) -> Dictionary:
	if folder == "":
		return {}
	var data := read_json(Paths.get_level_json_path(folder))
	if not data.is_empty():
		data["level_folder"] = folder
	return data


## What Resume finds of a map kept against `base_hashes`: MISSING when `current` (the map's
## hashes now) is null, CHANGED when they differ, else SAME. Pure.
static func map_status(base_hashes: Dictionary, current: Variant) -> StringName:
	if not current is Dictionary:
		return MISSING
	return SAME if MapFileHash.sanitize(current) == MapFileHash.sanitize(base_hashes) else CHANGED


# =============================================================================
# READING (untrusted: a file anyone could have edited)
# =============================================================================


## session.json as SessionKeeper may use it: known keys and types only, bounded sizes; {} when
## it is not a session file of FORMAT with a clean id. Pure.
static func sanitize_session(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	var id := clean_id(data.get("id"))
	if id == "" or int(_number(data.get("format"))) != FORMAT:
		return {}
	var out := {
		"format": FORMAT,
		"id": id,
		"name": _text(data.get("name")),
		"created": int(_number(data.get("created"))),
		"last_played": int(_number(data.get("last_played"))),
		"gm": _text(data.get("gm")),
		"shelf": [],
		"table": _text(data.get("table")),
		"selected": _text(data.get("selected")),
		"players": {},
		"party": [],
		"grants": {},
		"tables": {},
	}
	var shelf: Variant = data.get("shelf", [])
	if shelf is Array:
		for ref: Variant in (shelf as Array).slice(0, SessionChannel.MAX_SHELF):
			if ref is Dictionary:
				out.shelf.append(_shelf_ref(ref))
	var players: Variant = data.get("players", {})
	if players is Dictionary:
		for key: Variant in (players as Dictionary).keys().slice(0, SessionChannel.MAX_SESSION_PLAYERS):
			var entry: Variant = players[key]
			if key is String and key != "" and entry is Dictionary:
				var role := ROLE_GM if entry.get("role") == ROLE_GM else ROLE_PLAYER
				out.players[_text(key)] = {"name": _text(entry.get("name")), "role": role}
	var party: Variant = data.get("party", [])
	if party is Array:
		for member: Variant in party:
			if member is Dictionary and member.get("state") is Dictionary:
				out.party.append({"state": member.state, "owners": _strings(member.get("owners"))})
	var grants: Variant = data.get("grants", {})
	if grants is Dictionary:
		for key: Variant in grants:
			if key is String and key != "":
				out.grants[key] = _strings(grants[key])
	var tables: Variant = data.get("tables", {})
	if tables is Dictionary:
		for key: Variant in tables:
			var stem := clean_id(tables[key])
			if key is String and key != "" and stem != "":
				out.tables[_text(key)] = stem
	return out


## A table file as SessionKeeper may use it: its key, its base ({"hashes", "revision"}), the
## entry (TableStates.from_data()), and its document's file stem and log signature ("" when
## it kept none). Pure.
static func sanitize_table(raw: Variant) -> Dictionary:
	var data: Dictionary = raw if raw is Dictionary else {}
	var base: Dictionary = data.get("base") if data.get("base") is Dictionary else {}
	return {
		"key": _text(data.get("key")),
		"base":
		{
			"hashes": MapFileHash.sanitize(base.get("hashes", {})),
			"revision": int(_number(base.get("revision"))),
		},
		"entry": TableStates.from_data(data),
		"document": clean_id(data.get("document", "")),
		"document_log": _text(data.get("document_log")),
	}


static func _shelf_ref(ref: Dictionary) -> Dictionary:
	return {
		"folder": _text(ref.get("folder")),
		"map_path": _text(ref.get("map_path")),
		"hashes": MapFileHash.sanitize(ref.get("hashes", {})),
		"name": _text(ref.get("name")),
		"revision": int(_number(ref.get("revision"))),
	}


static func _text(value: Variant) -> String:
	return (value as String).left(SessionChannel.MAX_TEXT) if value is String else ""


static func _number(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0


static func _strings(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			if value is String and value != "" and value not in out:
				out.append(value)
	return out
