class_name LibraryReceivedStore
extends RefCounted

## The transient cache of libraries received from a host (LibraryTransfer, docs/systems/library.md
## "Multiplayer"): `LibraryRegistry.received_root()`, one folder per library id with a
## `<id>.received.json` marker beside it (version, bytes, `received_at`, `last_used`). It writes a
## library atomically (a dot-named staging folder renamed into place), lists only that root (the
## inventory), evicts the least recently used libraries over a byte cap, removes what a session
## received when it ends (and a crashed session's leftovers at start-up) and moves a library the
## player keeps into the user's libraries. The registry scans the root as its `received` source;
## nothing here reads a library's files, and every id is checked against the id grammar before it
## becomes a path.

const MARKER_SUFFIX := ".received.json"
## The cache cap: the least recently used received libraries go when a new one would pass it.
const CACHE_CAP_BYTES := 512 * 1024 * 1024

## Ids received since the process started, removed by sweep_session().
static var _this_session: Dictionary = {}


## The libraries received since the process started (still in the cache).
static func session_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_this_session.keys())
	out.sort()
	return out


## Writes the library's files under `root/<id>` through a dot-named staging folder and renames it
## into place, then its marker, and counts it as received by this session. Returns "" or the
## problem.
static func write_library(
	root: String, id: String, files: Dictionary, now: int, library: Dictionary
) -> String:
	if not LibraryIds.library_problems(id).is_empty():
		return "unsafe library id"
	var base := _base(root)
	if not base["ok"]:
		return "no safe place to keep it"
	root = String(base["path"])
	var staging := root.path_join(".staging-" + id)
	if not _delete(staging, root):
		return "cannot clear the staging folder"
	if DirAccess.make_dir_recursive_absolute(staging) != OK or not SafeDelete.mark(
		staging, "received_staging", root
	):
		return "cannot create the staging folder"
	var total := 0
	for relative: String in files:
		if (
			not LibraryIds.path_problems(relative).is_empty()
			or SafeDelete.MARKER in relative.split("/")
		):
			return "unsafe path " + relative
		var path := staging.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			return "cannot create " + path.get_base_dir()
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return "cannot write " + relative
		file.store_buffer(files[relative])
		file.close()
		total += (files[relative] as PackedByteArray).size()
	var final := root.path_join(id)
	if not _delete(final, root):
		_delete(staging, root)
		return "cannot replace the earlier copy"
	if DirAccess.rename_absolute(staging, final) != OK:
		_delete(staging, root)
		return "cannot move the library into place"
	SafeDelete.mark(final, "received", root)
	var marker := {
		"id": id,
		"version": String(library.get("version", "")),
		"bytes": total,
		"received_at": now,
		"last_used": now,
	}
	var marker_file := FileAccess.open(root.path_join(id + MARKER_SUFFIX), FileAccess.WRITE)
	if marker_file == null:
		return "cannot write the marker"
	marker_file.store_string(JSON.stringify(marker, "\t", true))
	marker_file.close()
	_this_session[id] = true
	return ""


## The received libraries: [{id, version, bytes, received_at, last_used}], least recently used
## first.
static func inventory(root: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var resolved := _base(root)
	if not resolved["ok"]:
		return out
	var base := String(resolved["path"])
	if not DirAccess.dir_exists_absolute(base):
		return out
	for file_name in DirAccess.get_files_at(base):
		if not file_name.ends_with(MARKER_SUFFIX):
			continue
		var json := JSON.new()
		var text := FileAccess.get_file_as_string(base.path_join(file_name))
		if json.parse(text) != OK or not json.data is Dictionary:
			continue
		var data: Dictionary = json.data
		var id := file_name.trim_suffix(MARKER_SUFFIX)
		if LibraryIds.library_problems(id).is_empty() and String(data.get("id", "")) == id:
			(
				out
				. append(
					{
						"id": id,
						"version": String(data.get("version", "")),
						"bytes": int(data.get("bytes", 0)),
						"received_at": int(data.get("received_at", 0)),
						"last_used": int(data.get("last_used", 0)),
					}
				)
			)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return [a["last_used"], a["id"]] < [b["last_used"], b["id"]]
	)
	return out


## Marks the received library `id` as used now, so the LRU eviction keeps it.
static func touch(id: String, now: int = -1, root: String = "") -> void:
	var resolved := _base(root)
	if not resolved["ok"] or not LibraryIds.library_problems(id).is_empty():
		return
	var path := String(resolved["path"]).path_join(id + MARKER_SUFFIX)
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			data["last_used"] = now if now >= 0 else int(Time.get_unix_time_from_system())
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(data, "\t", true))
				file.close()


## Removes the least recently used received libraries (not those in `keep`) until `incoming` more
## bytes fit under `cap`. Returns the ids removed.
static func evict_to_fit(
	incoming: int, keep: Array[String], cap: int = CACHE_CAP_BYTES, root: String = ""
) -> Array[String]:
	var removed: Array[String] = []
	var resolved := _base(root)
	if not resolved["ok"]:
		return removed
	var base := String(resolved["path"])
	var items := inventory(base)
	var total := incoming
	for item in items:
		total += int(item["bytes"])
	for item in items:
		if total <= cap:
			break
		if String(item["id"]) in keep:
			continue
		total -= int(item["bytes"])
		remove(String(item["id"]), base)
		removed.append(String(item["id"]))
	return removed


## Deletes one received library and its marker. False for an id that is not a library id.
static func remove(id: String, root: String = "") -> bool:
	if not LibraryIds.library_problems(id).is_empty():
		return false
	var resolved := _base(root)
	if not resolved["ok"]:
		return false
	var base := String(resolved["path"])
	var folder_gone := _delete(base.path_join(id), base)
	# The record goes only with its folder: a folder that could not be deleted keeps its record,
	# so the next sweep sees it again.
	if folder_gone:
		SafeDelete.file(base.path_join(id + MARKER_SUFFIX), base)
	_this_session.erase(id)
	return true


## The session ended: removes every library received since the process started. Returns the ids.
static func sweep_session(root: String = "") -> Array[String]:
	var removed: Array[String] = []
	for id: String in _this_session.keys():
		if remove(id, root):
			removed.append(id)
	_this_session.clear()
	return removed


## Start-up: a received library no session of this process owns is a leftover of a crash.
static func sweep_leftovers(root: String = "") -> Array[String]:
	var removed: Array[String] = []
	var resolved := _base(root)
	if not resolved["ok"]:
		return removed
	var base := String(resolved["path"])
	if not DirAccess.dir_exists_absolute(base):
		return removed
	for item in inventory(base):
		if not _this_session.has(item["id"]):
			remove(String(item["id"]), base)
			removed.append(String(item["id"]))
	# Folders left without a record (a crashed write): ours only when they carry the marker.
	for folder in DirAccess.get_directories_at(base):
		if not _this_session.has(folder):
			_delete(base.path_join(folder), base)
	return removed


## Keeps a received library: moves it into the user's libraries (`user_root`, default the
## registry's) unless one of that id is installed. `importer` is the library importer's entry
## when it exists (a Callable taking the folder and returning an Error); until it is merged the
## folder is moved directly. TODO(libmanager): route through LibraryImporter's quarantine flow.
## Returns {ok, error}.
static func promote(
	id: String, importer: Callable = Callable(), user_root: String = "", root: String = ""
) -> Dictionary:
	var out := {"ok": false, "error": ""}
	var resolved := _base(root)
	var destination := (
		LibraryPaths.resolve(user_root) if user_root != "" else LibraryPaths.libraries()
	)
	if not resolved["ok"] or not destination["ok"]:
		out["error"] = "no safe place to keep it"
		return out
	var base := String(resolved["path"])
	var target_root := String(destination["path"])
	if (
		not LibraryIds.library_problems(id).is_empty()
		or not DirAccess.dir_exists_absolute(base.path_join(id))
	):
		out["error"] = "no received library '%s'" % id
		return out
	var target := target_root.path_join(id)
	if DirAccess.dir_exists_absolute(target):
		out["error"] = "'%s' is already installed" % id
		return out
	if importer.is_valid():
		var err: int = importer.call(base.path_join(id))
		out["ok"] = err == OK
		out["error"] = "" if err == OK else "the importer refused it"
	else:
		DirAccess.make_dir_recursive_absolute(target_root)
		var moved := DirAccess.rename_absolute(base.path_join(id), target)
		out["ok"] = moved == OK
		out["error"] = "" if moved == OK else "cannot move the library"
	if out["ok"]:
		SafeDelete.file(base.path_join(id + MARKER_SUFFIX), base)
		_this_session.erase(id)
	return out


## The resolved received folder: `root` when given (it must pass LibraryPaths.resolve), else the
## registry's. {ok, path, error}; never an empty or relative path.
static func _base(root: String) -> Dictionary:
	if root == "":
		return LibraryPaths.received()
	return LibraryPaths.resolve(root)


## Deletes the folder `path` (inside `base`) through SafeDelete; true when it is gone. A folder
## the game wrote before the ownership marker existed is adopted first when its own record
## (`<id>.received.json`) sits beside it, or when it is a `.staging-` folder of this store.
static func _delete(path: String, base: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	if not SafeDelete.is_owned(path):
		var name := path.get_file()
		var recorded := FileAccess.file_exists(base.path_join(name + MARKER_SUFFIX))
		if recorded or name.begins_with(".staging-"):
			SafeDelete.mark(path, "received", base)
	return bool(SafeDelete.tree(path, base)["ok"])
