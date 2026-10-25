class_name LibraryFromHost
extends RefCounted

## The cache of collections downloaded from a host (docs/systems/library.md "The cache of
## downloaded collections"). A collection a host sent is an ORDINARY user library: it lives in
## `<libraries>/<id>/`, is served, switched and removed like any other, and is only MARKED
## "from host" by a small record file `.tt-from-host.json` beside `library.json` (the ownership
## marker `.tt-owned` is there too, so SafeDelete may remove it). The record keeps where it came
## from (the host's label), the version and the source hash of the host's FULL library, when it
## was received and last used, and which assets it holds. Because it is a partial copy that
## grows (a later map of the same host needs more assets), the record also lets the next request
## ask only for what is missing and merge it in (LibraryPartialMerge), and it is the memory of
## the player's consent: a collection the player agreed to download once is extended without a
## question while the delta is small (AUTO_DELTA_BYTES).
##
## The record is not part of a library's content (the registry leaves it out of the file list,
## so it never changes the hash, the size or a transfer); the importer drops a file of that name
## from anything the player imports, so an import cannot claim to be from a host. A host-sent
## library never replaces a library the player installed themselves: the folder holds a valid
## record or it is not ours to write. Everything that deletes goes through LibraryInstall.remove
## and SafeDelete. Total size on disk is capped (cap_bytes, 1 GB by default, a setting): a new
## install evicts the least recently used from-host collections that no open map uses.

const RECORD_FILE := ".tt-from-host.json"
const RECORD_FORMAT := 1
const STAGING_PREFIX := ".fromhost-staging-"
const OLD_PREFIX := ".fromhost-old-"
const MIB := 1024 * 1024
## A delta smaller than this downloads without a question once the player agreed to the
## collection (same id and source hash); a bigger one asks again.
const AUTO_DELTA_BYTES := 5 * MIB
const DEFAULT_CAP_MB := 1024
const MIN_CAP_MB := 64
const KEY_CAP_MB := "cache_cap_mb"
## Walking a folder for its size stops at these.
const MAX_WALK_FILES := 20000
const MAX_WALK_DEPTH := 8

## The library ids the open map uses (MapLibraryGate.run records them): never evicted.
static var open_ids: Dictionary = {}
## The delta size under which an agreed collection extends without a question (tests lower it).
static var auto_delta_limit: int = AUTO_DELTA_BYTES

# ---- the record ----


## `<libraries>/<id>` as a resolved path, "" when the id or the root is unusable.
static func folder_of(id: String) -> String:
	if not LibraryIds.library_problems(id).is_empty():
		return ""
	var child := LibraryPaths.child(LibraryPaths.libraries(), id)
	return String(child["path"]) if child["ok"] else ""


## The record of the folder `folder`, or {} when it has none or an unusable one (the folder is
## then an ordinary library). Strings and counts are coerced; nothing else is trusted.
static func read_record(folder: String) -> Dictionary:
	var path := folder.path_join(RECORD_FILE)
	if folder == "" or not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	if (
		int(data.get("format", 0)) != RECORD_FORMAT
		or String(data.get("id", "")) != folder.get_file()
	):
		return {}
	var assets: Array[String] = []
	if data.get("assets") is Array:
		for item: Variant in data["assets"] as Array:
			assets.append(String(item))
	return {
		"format": RECORD_FORMAT,
		"id": String(data["id"]),
		"host": String(data.get("host", "")),
		"version": String(data.get("version", "")),
		"source_hash": String(data.get("source_hash", "")),
		"received_at": int(data.get("received_at", 0)),
		"last_used": int(data.get("last_used", 0)),
		"assets": assets,
		"partial": bool(data.get("partial", true)),
		"assets_only": bool(data.get("assets_only", false)),
		"auto_delta": bool(data.get("auto_delta", true)),
	}


## Writes `record` into `folder`. False when the file cannot be written.
static func write_record(folder: String, record: Dictionary) -> bool:
	var file := FileAccess.open(folder.path_join(RECORD_FILE), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t", true))
	file.close()
	return true


## The record of installed library `id`, {} when it is not a from-host collection.
static func record_of(id: String) -> Dictionary:
	var folder := folder_of(id)
	return read_record(folder) if folder != "" else {}


static func is_from_host(id: String) -> bool:
	return not record_of(id).is_empty()


# ---- the inventory ----


## The from-host collections on disk: [{id, name, folder, host, version, source_hash,
## received_at, last_used, assets, partial, bytes}], least recently used first.
static func inventory() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var libraries := LibraryPaths.libraries()
	if not libraries["ok"] or not DirAccess.dir_exists_absolute(String(libraries["path"])):
		return out
	var base := String(libraries["path"])
	for folder_name in DirAccess.get_directories_at(base):
		if folder_name.begins_with(".") or not LibraryIds.library_problems(folder_name).is_empty():
			continue
		var folder := base.path_join(folder_name)
		var record := read_record(folder)
		if record.is_empty():
			continue
		record["folder"] = folder
		record["name"] = _name_of(folder, folder_name)
		record["bytes"] = folder_bytes(folder)
		out.append(record)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return [a["last_used"], a["id"]] < [b["last_used"], b["id"]]
	)
	return out


static func total_bytes() -> int:
	var total := 0
	for item in inventory():
		total += int(item["bytes"])
	return total


## The bytes of the files under `folder` (hidden ones included, links not followed).
static func folder_bytes(folder: String) -> int:
	var budget := [MAX_WALK_FILES]
	return _walk_bytes(folder, 0, budget)


static func _walk_bytes(folder: String, depth: int, budget: Array) -> int:
	var dir := DirAccess.open(folder)
	if dir == null or depth > MAX_WALK_DEPTH:
		return 0
	dir.include_hidden = true
	var total := 0
	for file_name in dir.get_files():
		budget[0] = int(budget[0]) - 1
		if int(budget[0]) < 0:
			return total
		var path := folder.path_join(file_name)
		if dir.is_link(path):
			continue
		var handle := FileAccess.open(path, FileAccess.READ)
		if handle != null:
			total += handle.get_length()
			handle.close()
	for sub in dir.get_directories():
		var path := folder.path_join(sub)
		if not dir.is_link(path):
			total += _walk_bytes(path, depth + 1, budget)
	return total


static func _name_of(folder: String, fallback: String) -> String:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(folder.path_join("library.json"))) == OK:
		if json.data is Dictionary and (json.data as Dictionary).get("name") is String:
			return String((json.data as Dictionary)["name"])
	return fallback


# ---- the cap ----


## The size cap in bytes (settings.cfg `[library] cache_cap_mb`, 1 GB by default).
static func cap_bytes() -> int:
	var config := ConfigFile.new()
	config.load(LibraryRegistry.settings_path)
	var megabytes := int(config.get_value(LibraryRegistry.SECTION, KEY_CAP_MB, DEFAULT_CAP_MB))
	return maxi(megabytes, MIN_CAP_MB) * MIB


## Saves the cap in megabytes (at least MIN_CAP_MB). False when the settings cannot be written.
static func set_cap_mb(megabytes: int) -> bool:
	var config := ConfigFile.new()
	var err := config.load(LibraryRegistry.settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning(
			"LibraryFromHost: failed to load settings (err=%d), writing section only" % err
		)
	config.set_value(LibraryRegistry.SECTION, KEY_CAP_MB, maxi(megabytes, MIN_CAP_MB))
	return config.save(LibraryRegistry.settings_path) == OK


## Removes the least recently used from-host collections (not those in `keep` and not those the
## open map uses) until `incoming` more bytes fit under `cap` (cap_bytes() when negative).
## Returns the ids removed. Collections in use stay even when that leaves the cache over its cap.
static func evict_to_fit(incoming: int, keep: Array[String], cap: int = -1) -> Array[String]:
	var removed: Array[String] = []
	var limit := cap if cap >= 0 else cap_bytes()
	var items := inventory()
	var total := incoming
	for item in items:
		total += int(item["bytes"])
	for item in items:
		if total <= limit:
			break
		var id := String(item["id"])
		if id in keep or open_ids.has(id):
			continue
		if bool(remove(id)["ok"]):
			total -= int(item["bytes"])
			removed.append(id)
	return removed


# ---- use ----


## A map using `ids` was opened: remember them as in use (never evicted) and stamp the from-host
## ones as used now.
static func note_open_map(ids: Array[String], now: int = -1) -> void:
	open_ids = {}
	for id in ids:
		open_ids[id] = true
		touch(id, now)


## Stamps from-host collection `id` as used at `now` (the clock when negative).
static func touch(id: String, now: int = -1) -> void:
	var folder := folder_of(id)
	var record := read_record(folder) if folder != "" else {}
	if record.is_empty():
		return
	record["last_used"] = now if now >= 0 else int(Time.get_unix_time_from_system())
	write_record(folder, record)


# ---- removing ----


## Removes from-host collection `id` (LibraryInstall.remove: SafeDelete, the baked surface cache
## goes too). Refused for anything that is not from a host. {ok, error}.
static func remove(id: String) -> Dictionary:
	if not is_from_host(id):
		return {"ok": false, "error": "'%s' was not downloaded from a host." % id}
	return LibraryInstall.remove(id)


## Removes every from-host collection. {removed: ids, failed: ids, bytes: freed}. The caller
## serves the libraries again.
static func clear_all() -> Dictionary:
	var out := {"removed": [] as Array[String], "failed": [] as Array[String], "bytes": 0}
	for item in inventory():
		var id := String(item["id"])
		if bool(remove(id)["ok"]):
			(out["removed"] as Array[String]).append(id)
			out["bytes"] = int(out["bytes"]) + int(item["bytes"])
		else:
			(out["failed"] as Array[String]).append(id)
	return out


# ---- consent ----


## True when the player's earlier "Download" covers this one: a record for the same collection
## (same source hash), kept as ask-free, and a delta under AUTO_DELTA_BYTES.
static func covers(record: Dictionary, source_hash: String, delta_bytes: int) -> bool:
	return (
		not record.is_empty()
		and bool(record.get("auto_delta", true))
		and String(record.get("source_hash", "")) == source_hash
		and delta_bytes < auto_delta_limit
	)


# ---- planning and writing an install ----


## What to do with the incoming `partial` block of library `id`: {mode, record} where mode is
## "new" (no folder), "merge" (a from-host copy of the same version and source hash), "replace"
## (a from-host copy of another version or hash), "own" (the player's own copy: never touched) or
## "unsafe" (the id is not a usable folder name).
static func decide(id: String, partial: Dictionary, version: String) -> Dictionary:
	var folder := folder_of(id)
	if folder == "":
		return {"mode": "unsafe", "record": {}}
	if not DirAccess.dir_exists_absolute(folder):
		return {"mode": "new", "record": {}}
	var record := read_record(folder)
	if record.is_empty():
		return {"mode": "own", "record": {}}
	var same := (
		String(record["version"]) == version
		and String(record["source_hash"]) == String(partial.get("source_hash", ""))
	)
	return {"mode": "merge" if same else "replace", "record": record}


## The files of the folder of `id` as {relative path: bytes} (the marker and the record left out),
## or {} when it cannot be read within the bundle caps.
static func read_folder_files(id: String) -> Dictionary:
	var folder := folder_of(id)
	var out := {}
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return out
	var listing := LibraryRegistry.read_sources(folder)
	if listing.has("error"):
		return {}
	var total := 0
	for relative: String in listing["files"]:
		var data := FileAccess.get_file_as_bytes(folder.path_join(relative))
		total += data.size()
		if out.size() >= LibraryPartial.MAX_ENTRIES or total > LibraryPartial.MAX_TOTAL_BYTES:
			return {}
		out[relative] = data
	return out


## Writes the libraries of `plans` ([{id, files, library (the parsed library.json), mode}]) as
## from-host collections, all or nothing: every folder is built next to its place first, then the
## folders are swapped in (an earlier copy set aside and put back if a later swap fails). `ctx`:
## {host (label), now, requested (the id asked for), cap (bytes, default cap_bytes())}. Evicts old
## from-host collections first. {ok, error, written: ids, evicted: ids, bytes}.
static func commit(plans: Array, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "written": [] as Array[String], "evicted": [], "bytes": 0}
	var libraries := LibraryPaths.libraries()
	if (
		not libraries["ok"]
		or DirAccess.make_dir_recursive_absolute(String(libraries["path"])) != OK
	):
		out["error"] = "no safe place to keep it"
		return out
	var root := String(libraries["path"])
	var total := 0
	var keep: Array[String] = []
	for plan: Dictionary in plans:
		if not LibraryIds.library_problems(String(plan["id"])).is_empty():
			out["error"] = "'%s' is not a usable id" % plan["id"]
			return out
		keep.append(String(plan["id"]))
		for data: PackedByteArray in (plan["files"] as Dictionary).values():
			total += data.size()
	var cap := int(ctx.get("cap", -1))
	out["evicted"] = evict_to_fit(total, keep, cap)
	var built: Array[Dictionary] = []
	for plan: Dictionary in plans:
		var problem := _build(root, plan, ctx)
		if problem != "":
			_discard(built, root)
			out["error"] = problem
			return out
		built.append(plan)
	var swapped: Array[Dictionary] = []
	for plan: Dictionary in built:
		var problem := _swap(root, String(plan["id"]))
		if problem != "":
			_undo(swapped, root)
			_discard(built, root)
			out["error"] = problem
			return out
		swapped.append(plan)
	for plan: Dictionary in swapped:
		_delete(root.path_join(OLD_PREFIX + String(plan["id"])), root)
		SurfaceCache.remove_library(String(plan["id"]))
		(out["written"] as Array[String]).append(String(plan["id"]))
	out["bytes"] = total
	out["ok"] = true
	return out


## Builds `<root>/.fromhost-staging-<id>` for `plan`: the files, the ownership marker, the record.
static func _build(root: String, plan: Dictionary, ctx: Dictionary) -> String:
	var id := String(plan["id"])
	var staging := root.path_join(STAGING_PREFIX + id)
	if not _delete(staging, root):
		return "cannot clear the staging folder"
	if (
		DirAccess.make_dir_recursive_absolute(staging) != OK
		or not SafeDelete.mark(staging, "from_host_staging", root)
	):
		return "cannot create the staging folder"
	var files: Dictionary = plan["files"]
	for relative: String in files:
		var parts := relative.split("/")
		if (
			not LibraryIds.path_problems(relative).is_empty()
			or relative in [SafeDelete.MARKER, RECORD_FILE]
			or parts[0].begins_with(".")
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
	if not write_record(staging, _record_for(plan, ctx)):
		return "cannot write the record"
	return ""


static func _record_for(plan: Dictionary, ctx: Dictionary) -> Dictionary:
	var library: Dictionary = plan["library"]
	var partial: Dictionary = library.get(LibraryPartial.PARTIAL_KEY, {})
	var now := int(ctx.get("now", Time.get_unix_time_from_system()))
	var before: Dictionary = plan.get("record", {})
	var assets: Array[String] = []
	for item: Variant in partial.get("assets", []) as Array:
		assets.append(String(item))
	return {
		"format": RECORD_FORMAT,
		"id": String(plan["id"]),
		"host": String(ctx.get("host", "")),
		"version": String(library.get("version", "")),
		"source_hash": String(partial.get("source_hash", "")),
		"received_at": int(before.get("received_at", now)) if plan["mode"] == "merge" else now,
		"last_used": now,
		"assets": assets,
		"partial": true,
		"assets_only": bool(partial.get("assets_only", false)),
		"auto_delta": bool(before.get("auto_delta", true)),
	}


## Moves the staging folder of `id` into place; an earlier copy goes to `.fromhost-old-<id>` first.
static func _swap(root: String, id: String) -> String:
	var staging := root.path_join(STAGING_PREFIX + id)
	var target := root.path_join(id)
	var old := root.path_join(OLD_PREFIX + id)
	if not _delete(old, root):
		return "cannot clear the earlier copy of '%s'" % id
	if DirAccess.dir_exists_absolute(target):
		if not SafeDelete.is_owned(target) or read_record(target).is_empty():
			var own := "'%s' is not a %s that came from a host, so it is not replaced"
			return own % [id, LibraryNames.lower()]
		if DirAccess.rename_absolute(target, old) != OK:
			return "the copy of '%s' is in use and could not be set aside" % id
	if DirAccess.rename_absolute(staging, target) != OK:
		if DirAccess.dir_exists_absolute(old):
			DirAccess.rename_absolute(old, target)
		return "cannot move '%s' into place" % id
	return ""


## Puts back what _swap moved for `swapped`.
static func _undo(swapped: Array[Dictionary], root: String) -> void:
	for plan in swapped:
		var id := String(plan["id"])
		var target := root.path_join(id)
		var old := root.path_join(OLD_PREFIX + id)
		_delete(target, root)
		if DirAccess.dir_exists_absolute(old):
			DirAccess.rename_absolute(old, target)


static func _discard(built: Array[Dictionary], root: String) -> void:
	for plan in built:
		_delete(root.path_join(STAGING_PREFIX + String(plan["id"])), root)


static func _delete(path: String, root: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	return bool(SafeDelete.tree(path, root)["ok"])


# ---- start-up ----


## Start-up housekeeping: staging and set-aside folders a crashed install left behind go, and a
## `.received` folder of the earlier transient cache is adopted (see migrate_received).
## Returns {swept, adopted: ids, left: [{id, reason}]}.
static func startup() -> Dictionary:
	var out := {"swept": 0, "adopted": [] as Array[String], "left": []}
	var libraries := LibraryPaths.libraries()
	if not libraries["ok"] or not DirAccess.dir_exists_absolute(String(libraries["path"])):
		return out
	var root := String(libraries["path"])
	for folder_name in DirAccess.get_directories_at(root):
		if folder_name.begins_with(STAGING_PREFIX) or folder_name.begins_with(OLD_PREFIX):
			if _delete(root.path_join(folder_name), root):
				out["swept"] = int(out["swept"]) + 1
	var migrated := migrate_received()
	out["adopted"] = migrated["adopted"]
	out["left"] = migrated["left"]
	return out


## The earlier version kept received collections for the session only, in `<libraries>/.received/
## <id>/` with a `<id>.received.json` record beside. Each one that is a valid partial copy and
## whose id is not already installed is moved once into the normal libraries folder and flagged
## from-host; anything else is reported and left where it is (nothing is deleted). {adopted: ids,
## left: [{id, reason}]}. Reads the registry for the official ids.
static func migrate_received() -> Dictionary:
	var out := {"adopted": [] as Array[String], "left": []}
	var legacy := LibraryPaths.received()
	if not legacy["ok"] or not DirAccess.dir_exists_absolute(String(legacy["path"])):
		return out
	var base := String(legacy["path"])
	for folder_name in DirAccess.get_directories_at(base):
		if folder_name.begins_with("."):
			continue
		var reason := _adopt_one(base, folder_name)
		if reason == "":
			(out["adopted"] as Array[String]).append(folder_name)
		else:
			(out["left"] as Array).append({"id": folder_name, "reason": reason})
			printerr(
				"LibraryFromHost: the old received folder '%s' was left: %s" % [folder_name, reason]
			)
	return out


static func _adopt_one(base: String, id: String) -> String:
	if not LibraryIds.library_problems(id).is_empty():
		return "not a usable id"
	var source := base.path_join(id)
	var record_text := FileAccess.get_file_as_string(base.path_join(id + ".received.json"))
	var json := JSON.new()
	var old: Dictionary = (
		json.data if json.parse(record_text) == OK and json.data is Dictionary else {}
	)
	var files := {}
	var listing := LibraryRegistry.read_sources(source)
	if listing.has("error"):
		return "cannot be read"
	for relative: String in listing["files"]:
		files[relative] = FileAccess.get_file_as_bytes(source.path_join(relative))
	var split := {id: files}
	var checked := (
		LibraryPartial
		. inspect(
			files,
			{
				"id": id,
				"official_ids": LibraryTransfer.official_ids(),
				"surfaces": PaletteLibrary.get_palette()["surfaces"],
				"dependencies": {},
			}
		)
	)
	if not checked["ok"]:
		return "does not pass the checks (%s)" % String((checked["errors"] as Array)[0]["text"])
	var library: Dictionary = checked["library"]
	var decision := decide(id, checked["partial"], String(library.get("version", "")))
	if decision["mode"] != "new":
		return "%s with that id is already installed" % LibraryNames.article()
	var made := commit(
		[{"id": id, "files": split[id], "library": library, "mode": "new", "record": {}}],
		{"host": "an earlier session", "now": int(old.get("received_at", 0))}
	)
	if not bool(made["ok"]):
		return String(made["error"])
	# The old folder is ours when its own record sits beside it: mark it so SafeDelete may go.
	if record_text != "" and SafeDelete.adopt(source, "received", base):
		SafeDelete.tree(source, base)
		SafeDelete.file(base.path_join(id + ".received.json"), base)
	return ""
