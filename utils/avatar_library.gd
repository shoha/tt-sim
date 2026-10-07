class_name AvatarLibrary
extends RefCounted

## The player's saved avatars (the avatar library): figures made in the avatar builder,
## kept on this machine so a player can make their character ahead of time on the title
## screen and place it in any game from the Add Token browser's Avatar tab. Local only
## (no Steam Cloud yet).
##
## One JSON file per avatar in `directory` (user://avatars/), named by its id:
##   {"format": 1, "id": "av_...", "name": "Plum", "recipe": {...},
##    "created": <unix seconds>, "updated": <unix seconds>}
## `recipe` is an avatar recipe (docs/ASSET_PIPELINE.md section 10 "Recipe"), normalised on
## load (AvatarRecipe.normalized). A file that does not parse, lacks an id or a recipe, or
## carries a format this client does not know is skipped with a warning, never fatal, and
## is left on disk untouched.
##
## Every function takes the directory as an optional last argument (`directory` when
## empty); tests pass their own. `changed`, on the shared events() instance, tells open
## views (the roster, the Avatar tab) to refresh.

## Fired after any write through this class.
signal changed

const FORMAT := 1
const DEFAULT_DIRECTORY := "user://avatars/"
const ID_PREFIX := "av_"
const DEFAULT_NAME := "Avatar"

## Where avatars live; tests point it at a directory of their own and put it back.
static var directory := DEFAULT_DIRECTORY
static var _events: AvatarLibrary = null
static var _last_ms := 0


## The shared instance views connect to for `changed`.
static func events() -> AvatarLibrary:
	if _events == null:
		_events = AvatarLibrary.new()
	return _events


## Every readable avatar, newest made first (id breaks a tie).
static func list(dir: String = "") -> Array[Dictionary]:
	var root := _dir(dir)
	var out: Array[Dictionary] = []
	var access := DirAccess.open(root)
	if access == null:
		return out
	for file in access.get_files():
		if not file.ends_with(".json"):
			continue
		var entry := _read(root.path_join(file))
		if not entry.is_empty():
			out.append(entry)
	out.sort_custom(_newer_first)
	return out


## The avatar with `id`, or an empty Dictionary.
static func get_entry(id: String, dir: String = "") -> Dictionary:
	if not _valid_id(id):
		return {}
	var path := _dir(dir).path_join(id + ".json")
	return _read(path) if FileAccess.file_exists(path) else {}


## Saves `recipe` under `name`: a new avatar when `id` is empty or unknown, else that
## avatar updated (its created time kept). Returns the stored entry, empty on failure.
static func save(name: String, recipe: Dictionary, id: String = "", dir: String = "") -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var existing := get_entry(id, dir) if not id.is_empty() else {}
	var entry := {
		"format": FORMAT,
		"id": String(existing.get("id", "")) if not existing.is_empty() else new_id(),
		"name": _clean_name(name),
		"recipe": AvatarRecipe.normalized(recipe),
		"created": int(existing.get("created", now)),
		"updated": now,
	}
	return entry if _write(entry, dir) else {}


## A copy of avatar `id` as a new avatar named "<name> copy". Returns it, empty on failure.
static func duplicate_entry(id: String, dir: String = "") -> Dictionary:
	var source := get_entry(id, dir)
	if source.is_empty():
		return {}
	return save(String(source.name) + " copy", source.recipe, "", dir)


## Renames avatar `id`. False when it does not exist or the write fails.
static func rename(id: String, name: String, dir: String = "") -> bool:
	var entry := get_entry(id, dir)
	if entry.is_empty():
		return false
	entry["name"] = _clean_name(name)
	entry["updated"] = int(Time.get_unix_time_from_system())
	return _write(entry, dir)


## Deletes avatar `id`. False when it does not exist.
static func delete(id: String, dir: String = "") -> bool:
	if not _valid_id(id):
		return false
	var path := _dir(dir).path_join(id + ".json")
	if not FileAccess.file_exists(path):
		return false
	var ok := DirAccess.remove_absolute(path) == OK
	if ok:
		events().changed.emit()
	return ok


## A fresh id: the prefix, the time in milliseconds (never repeated by one session, so ids
## made in the same millisecond still sort in the order they were made) and a random tail.
static func new_id() -> String:
	var ms := maxi(int(Time.get_unix_time_from_system() * 1000.0), _last_ms + 1)
	_last_ms = ms
	return "%s%d_%06x" % [ID_PREFIX, ms, randi() % 0x1000000]


static func _dir(dir: String) -> String:
	return dir if not dir.is_empty() else directory


## Ids are file names: letters, digits and underscores only, so a stray id never reaches
## outside the directory.
static func _valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for c in id:
		if not (c == "_" or c.is_valid_int() or (c.to_lower() >= "a" and c.to_lower() <= "z")):
			return false
	return true


static func _clean_name(name: String) -> String:
	var clean := name.strip_edges()
	return clean if not clean.is_empty() else DEFAULT_NAME


static func _newer_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a.created) != int(b.created):
		return int(a.created) > int(b.created)
	return String(a.id) > String(b.id)


## The entry in the file at `path`, normalised; empty (with a warning) when the file is
## unreadable, malformed or of an unknown format.
static func _read(path: String) -> Dictionary:
	var json := JSON.new()
	# JSON.parse (not parse_string) so a broken file is one warning here, not an engine error.
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not data is Dictionary:
		push_warning("AvatarLibrary: skipping %s (not a JSON object)" % path)
		return {}
	var raw: Dictionary = data
	if int(raw.get("format", -1)) != FORMAT:
		push_warning("AvatarLibrary: skipping %s (format %s)" % [path, str(raw.get("format"))])
		return {}
	var id := String(raw.get("id", ""))
	if not _valid_id(id) or not raw.get("recipe") is Dictionary:
		push_warning("AvatarLibrary: skipping %s (no id or recipe)" % path)
		return {}
	return {
		"format": FORMAT,
		"id": id,
		"name": _clean_name(String(raw.get("name", ""))),
		"recipe": AvatarRecipe.normalized(raw.recipe),
		"created": int(raw.get("created", 0)),
		"updated": int(raw.get("updated", 0)),
	}


static func _write(entry: Dictionary, dir: String) -> bool:
	var root := _dir(dir)
	if not DirAccess.dir_exists_absolute(root):
		DirAccess.make_dir_recursive_absolute(root)
	var path := root.path_join(String(entry.id) + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("AvatarLibrary: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(entry, "\t"))
	file.close()
	events().changed.emit()
	return true
