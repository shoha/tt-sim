class_name LibraryPaths
extends RefCounted

## The one place a folder the library code may write to or delete from is decided
## (docs/systems/library.md "Destructive operations"). A path is answered as an ABSOLUTE,
## normalised OS path that lies strictly inside the user data folder (`user://`), or as an error:
## never as a path that quietly means "the working directory". An empty, relative, `res://`,
## `..`-bearing, drive-only or outside-the-user-folder path is refused, so a root that came out
## empty or relative (a bad setting, a test, a not yet initialised autoload) can no longer resolve
## against the project folder. Godot treats "" and "." as the working directory, which in a
## developer run is the project itself; every library delete and write goes through here.
##
## The named roots (`libraries()`, `incoming()`, `received()`, `cache()`) read the configured
## strings (`LibraryRegistry.user_root`, `LibraryImporter.incoming_override`, `SurfaceCache.root`)
## and resolve them; each is `{ok, path, error}`. SafeDelete deletes only inside them (or inside
## a base the caller passes, which is resolved the same way).

## The file that marks a folder as created by this game's code; SafeDelete refuses a folder
## without it.
const MARKER := ".tt-owned"
const INCOMING_NAME := ".incoming"
const RECEIVED_NAME := ".received"

## Extra folders (absolute, already inside a scratch area) that count as the user data folder,
## for tests that must work outside `user://`. Empty in the game.
static var extra_anchors: Array[String] = []


## The user data folder as a normalised absolute path with no trailing slash.
static func user_dir() -> String:
	return clean(ProjectSettings.globalize_path("user://"))


## The project folder, normalised, or "" in an exported game (where `res://` is a PCK).
static func project_dir() -> String:
	var globalized := ProjectSettings.globalize_path("res://")
	if globalized.begins_with("res://") or globalized == "":
		return ""
	return clean(globalized)


## Forward slashes, `.` and `..` folded, no trailing slash (except a bare root).
static func clean(path: String) -> String:
	var out := path.replace("\\", "/").simplify_path()
	while out.length() > 3 and out.ends_with("/"):
		out = out.trim_suffix("/")
	return out


## `path` and `base` both resolved: true when `path` lies strictly inside `base`.
static func inside(path: String, base: String) -> bool:
	var a := _key(clean(path))
	var b := _key(clean(base))
	return b != "" and a.begins_with(b.trim_suffix("/") + "/") and a != b


## Resolves `path` to {ok, path (absolute, normalised), anchor, error}. The only paths that pass
## are absolute (`user://`, a drive letter or a rooted path), have no `..` segment, and lie
## strictly inside the user data folder (or an extra anchor); never `res://`, never the project
## folder or one of its parents.
static func resolve(path: String) -> Dictionary:
	var out := {"ok": false, "path": "", "anchor": "", "error": ""}
	if path.strip_edges() == "":
		out["error"] = "the folder is not set"
		return out
	if path.begins_with("res://") or path.begins_with("uid://"):
		out["error"] = "'%s' is inside the game's own files" % path
		return out
	if not path.is_absolute_path():
		out["error"] = "'%s' is a relative path" % path
		return out
	if ".." in path.replace("\\", "/").split("/"):
		out["error"] = "'%s' climbs out of its folder" % path
		return out
	var full := clean(ProjectSettings.globalize_path(path))
	if not full.is_absolute_path() or full.begins_with("res://"):
		out["error"] = "'%s' is not an absolute path" % path
		return out
	var anchor := _anchor_of(full)
	if anchor == "":
		out["error"] = "'%s' is outside the user data folder" % path
		return out
	var project := project_dir()
	if project != "":
		var in_project := inside(full, project) or _key(full) == _key(project)
		if (in_project and not inside(project, anchor)) or inside(project, full):
			out["error"] = "'%s' is the project folder or contains it" % path
			return out
	out["ok"] = true
	out["path"] = full
	out["anchor"] = anchor
	return out


## "" when `path` resolves, else the reason.
static func verify(path: String) -> String:
	return String(resolve(path)["error"])


## The user's libraries folder (`LibraryRegistry.user_root`).
static func libraries() -> Dictionary:
	return resolve(String(LibraryRegistry.user_root))


## The quarantine folder `<libraries>/.incoming` (or the test override).
static func incoming() -> Dictionary:
	var forced := String(LibraryImporter.incoming_override)
	if forced != "":
		return resolve(forced)
	var libs := libraries()
	if not libs["ok"]:
		return libs
	return resolve(String(libs["path"]).path_join(INCOMING_NAME))


## The old session-only received-libraries folder `<libraries>/.received`. Nothing writes it any
## more; LibraryFromHost.migrate_received adopts what an earlier version left there.
static func received() -> Dictionary:
	var libs := libraries()
	if not libs["ok"]:
		return libs
	return resolve(String(libs["path"]).path_join(RECEIVED_NAME))


## The baked surface cache folder (`SurfaceCache.root`).
static func cache() -> Dictionary:
	return resolve(String(SurfaceCache.root))


## The resolved roots SafeDelete accepts when the caller names none (those that resolve).
static func allowed_bases() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in [libraries(), incoming(), received(), cache()]:
		if item["ok"] and not String(item["path"]) in out:
			out.append(String(item["path"]))
	return out


## `<root>/<name>` as a resolved path, or {ok: false}: `name` must be one plain segment (no
## separator, not "." or "..", not empty), so a library id or token can never leave its folder.
static func child(root: Dictionary, segment: String) -> Dictionary:
	if not root["ok"]:
		return root
	var bad := (
		segment == ""
		or segment == "."
		or segment == ".."
		or "/" in segment
		or "\\" in segment
		or ":" in segment
	)
	if bad:
		return {
			"ok": false, "path": "", "anchor": "", "error": "'%s' is not a folder name" % segment
		}
	return resolve(String(root["path"]).path_join(segment))


static func _anchor_of(full: String) -> String:
	var anchors: Array[String] = [user_dir()]
	for extra in extra_anchors:
		anchors.append(clean(extra))
	for anchor in anchors:
		if anchor != "" and inside(full, anchor):
			return anchor
	return ""


## Case-insensitive on the systems whose file systems are.
static func _key(path: String) -> String:
	if OS.get_name() in ["Windows", "macOS"]:
		return path.to_lower()
	return path
