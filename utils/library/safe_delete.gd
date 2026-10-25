class_name SafeDelete
extends RefCounted

## The ONE recursive delete of the library code (docs/systems/library.md "Destructive
## operations"; AGENTS.md rule). A folder is removed only when ALL of this holds:
##   a. its path resolves (LibraryPaths.resolve) to an absolute path strictly inside an allowed
##      base: the user's libraries, the quarantine, the received cache or the surface cache (or
##      the base the caller names, resolved the same way, so a test can use a scratch folder);
##   b. the folder holds the `.tt-owned` marker our code wrote when it created it. A folder
##      without one is never deleted, only reported;
##   c. neither it, nor any folder between the base and it, nor anything inside it is a link
##      (symlink, junction, reparse point). Links are never followed; one inside the tree stops
##      the whole delete before the first file is removed;
##   d. the tree has at most `max_entries` entries (default 200,000) and nests at most
##      `MAX_DEPTH` levels; a bigger one is left alone and reported;
## and it logs how many entries went. The whole tree is checked BEFORE anything is removed, and
## the marker goes last, so a failed delete leaves a folder that can be tried again.
## Every function returns {ok, deleted, error} and never raises.

const MARKER := LibraryPaths.MARKER
const MAX_ENTRIES := 200000
const MAX_DEPTH := 24

## The entry cap; tests lower it.
static var max_entries: int = MAX_ENTRIES
## How many entries the delete helpers have removed in this process (for logs and tests).
static var total_deleted: int = 0


## Deletes the folder `path` and everything in it. `base` is the folder it must lie strictly
## inside ("" = the allowed bases of LibraryPaths); `marker` is the sentinel file it must hold.
static func tree(path: String, base: String = "", marker: String = MARKER) -> Dictionary:
	var out := {"ok": false, "deleted": 0, "error": ""}
	var target := LibraryPaths.resolve(path)
	if not target["ok"]:
		return _refuse(out, String(target["error"]), path)
	var within := _base_of(String(target["path"]), base)
	if not within["ok"]:
		return _refuse(out, String(within["error"]), path)
	var root := String(target["path"])
	if marker == "" or "/" in marker or "\\" in marker or marker in [".", ".."]:
		return _refuse(out, "no marker name", path)
	var link := _link_between(String(within["path"]), root)
	if link != "":
		return _refuse(out, "'%s' is a link" % link, path)
	if not DirAccess.dir_exists_absolute(root):
		# Already gone (or a plain file): nothing to remove here.
		out["ok"] = not FileAccess.file_exists(root)
		if not out["ok"]:
			out["error"] = "'%s' is a file, not a folder" % path
		return out
	if not FileAccess.file_exists(root.path_join(marker)):
		return _refuse(out, "it has no '%s' marker (the game did not create it)" % marker, path)
	var plan := {"files": [], "dirs": [], "count": 0, "error": ""}
	_scan(root, 0, plan)
	if String(plan["error"]) != "":
		return _refuse(out, String(plan["error"]), path)
	var marker_path := root.path_join(marker)
	var failed := 0
	var deleted := 0
	for file_path: String in plan["files"]:
		if file_path == marker_path:
			continue
		if DirAccess.remove_absolute(file_path) == OK:
			deleted += 1
		else:
			failed += 1
	var dirs: Array = plan["dirs"]
	dirs.reverse()
	if failed == 0:
		# The marker goes last: until then the folder can still be deleted by a retry.
		if DirAccess.remove_absolute(marker_path) == OK:
			deleted += 1
		else:
			failed += 1
	for dir_path: String in dirs:
		if DirAccess.remove_absolute(dir_path) == OK:
			deleted += 1
		else:
			failed += 1
	out["deleted"] = deleted
	out["ok"] = not DirAccess.dir_exists_absolute(root)
	if not out["ok"]:
		out["error"] = "%d entries of '%s' could not be removed" % [maxi(failed, 1), path]
	total_deleted += deleted
	print("SafeDelete: removed %d entries of %s" % [deleted, root])
	return out


## Deletes one FILE `path` (never a folder) lying inside the base (see tree()). A missing file is
## ok; a link is refused.
static func file(path: String, base: String = "") -> Dictionary:
	var out := {"ok": false, "deleted": 0, "error": ""}
	var target := LibraryPaths.resolve(path)
	if not target["ok"]:
		return _refuse(out, String(target["error"]), path)
	var within := _base_of(String(target["path"]), base)
	if not within["ok"]:
		return _refuse(out, String(within["error"]), path)
	var full := String(target["path"])
	var link := _link_between(String(within["path"]), full)
	if link != "":
		return _refuse(out, "'%s' is a link" % link, path)
	if DirAccess.dir_exists_absolute(full):
		return _refuse(out, "it is a folder", path)
	if not FileAccess.file_exists(full):
		out["ok"] = true
		return out
	if DirAccess.remove_absolute(full) != OK:
		out["error"] = "'%s' could not be removed" % path
		return out
	out["ok"] = true
	out["deleted"] = 1
	total_deleted += 1
	return out


## True when `folder` carries the marker.
static func is_owned(folder: String) -> bool:
	var target := LibraryPaths.resolve(folder)
	return (
		target["ok"]
		and DirAccess.dir_exists_absolute(String(target["path"]))
		and FileAccess.file_exists(String(target["path"]).path_join(MARKER))
	)


## Writes the marker into `folder` (which must exist, lie inside the base and not be a link).
## Call it where our code creates a folder, and for the migration of a folder that exists
## already (`adopt`). False when refused or unwritable.
static func mark(folder: String, kind: String, base: String = "") -> bool:
	var target := LibraryPaths.resolve(folder)
	if not target["ok"]:
		return false
	var within := _base_of(String(target["path"]), base)
	if not within["ok"]:
		return false
	var full := String(target["path"])
	if _link_between(String(within["path"]), full) != "" or not DirAccess.dir_exists_absolute(full):
		return false
	var handle := FileAccess.open(full.path_join(MARKER), FileAccess.WRITE)
	if handle == null:
		return false
	var body := {"owner": "tt-sim", "kind": kind, "created": int(Time.get_unix_time_from_system())}
	handle.store_string(JSON.stringify(body))
	handle.close()
	return true


## The migration for a folder of regenerable files: marks `folder` only when everything in it
## (at most a few levels deep, no links) has one of `extensions`. True when it is marked.
static func mark_if_only(
	folder: String, kind: String, extensions: PackedStringArray, base: String = ""
) -> bool:
	var target := LibraryPaths.resolve(folder)
	if not target["ok"]:
		return false
	var plan := {"files": [], "dirs": [], "count": 0, "error": ""}
	_scan(String(target["path"]), MAX_DEPTH - 4, plan)
	if String(plan["error"]) != "":
		return false
	for file_path: String in plan["files"]:
		if not file_path.get_extension() in extensions:
			return false
	return mark(folder, kind, base)


## The migration: marks an existing `folder` that has no marker yet. Callers decide that the
## folder is ours (a direct child of the libraries folder holding library.json, a received
## folder with its own record); this only refuses what cannot be ours at all. True when it holds
## a marker afterwards.
static func adopt(folder: String, kind: String, base: String = "") -> bool:
	return is_owned(folder) or mark(folder, kind, base)


# ---- internals ----


## {ok, path, error}: the resolved base that `full` lies strictly inside.
static func _base_of(full: String, base: String) -> Dictionary:
	var bases: Array[String] = []
	if base != "":
		var named := LibraryPaths.resolve(base)
		if not named["ok"]:
			return {"ok": false, "path": "", "error": "the base folder: %s" % named["error"]}
		bases.append(String(named["path"]))
	else:
		bases = LibraryPaths.allowed_bases()
	for candidate in bases:
		if LibraryPaths.inside(full, candidate):
			return {"ok": true, "path": candidate, "error": ""}
	return {"ok": false, "path": "", "error": "it is not inside a folder this game manages"}


## The first folder from `base` down to `full` (inclusive) that is a link, or "".
static func _link_between(base: String, full: String) -> String:
	var relative := full.substr(base.length()).trim_prefix("/")
	var here := base
	for segment in relative.split("/", false):
		here = here.path_join(segment)
		var parent := DirAccess.open(here.get_base_dir())
		if parent != null and parent.is_link(here):
			return here
	return ""


## Lists `dir` into `plan` ({files, dirs, count, error}); stops at the first problem.
static func _scan(dir: String, depth: int, plan: Dictionary) -> void:
	if String(plan["error"]) != "":
		return
	if depth > MAX_DEPTH:
		plan["error"] = "it nests more than %d folders deep" % MAX_DEPTH
		return
	var handle := DirAccess.open(dir)
	if handle == null:
		plan["error"] = "'%s' cannot be listed" % dir
		return
	handle.include_hidden = true
	(plan["dirs"] as Array).append(dir)
	for entry in handle.get_files():
		var path := dir.path_join(entry)
		if not _count(plan, path):
			return
		if handle.is_link(path):
			plan["error"] = "'%s' is a link" % path
			return
		(plan["files"] as Array).append(path)
	for entry in handle.get_directories():
		var path := dir.path_join(entry)
		if not _count(plan, path):
			return
		if handle.is_link(path):
			plan["error"] = "'%s' is a link" % path
			return
		_scan(path, depth + 1, plan)
		if String(plan["error"]) != "":
			return


static func _count(plan: Dictionary, path: String) -> bool:
	plan["count"] = int(plan["count"]) + 1
	if int(plan["count"]) > max_entries:
		plan["error"] = "it holds more than %d entries (%s)" % [max_entries, path.get_file()]
		return false
	return true


static func _refuse(out: Dictionary, reason: String, path: String) -> Dictionary:
	out["ok"] = false
	out["error"] = "refusing to delete '%s': %s" % [path, reason]
	printerr("SafeDelete: " + String(out["error"]))
	return out
