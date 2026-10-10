class_name LibraryPlays
extends RefCounted

## The local index of when each map in the library was last played on this machine: one
## ConfigFile section per level folder holding the unix time a table of it last finished
## loading here, solo or hosted (LevelFlow records it), so the library lists the most recently
## played first and its detail strip says when. It lives under the data root beside levels/
## (Paths.library_plays_path()), never inside a level folder: playing a map never rewrites its
## level.json, whose revision a saved session compares to tell a changed map (SessionFile).

const KEY_PLAYED_AT := "played_at"

## The index file. Tests point this at their own file (the ImportSources pattern).
static var path: String = Paths.library_plays_path()


## Records that the level in `folder` was played at `when` (unix seconds; now when negative).
static func record(folder: String, when: int = -1) -> Error:
	if folder.is_empty():
		return ERR_INVALID_PARAMETER
	var index := _load()
	var at := when if when >= 0 else int(Time.get_unix_time_from_system())
	index.set_value(folder, KEY_PLAYED_AT, at)
	return index.save(path)


## Every recorded play, {level folder: unix seconds}.
static func all() -> Dictionary:
	var index := _load()
	var out := {}
	for folder in index.get_sections():
		var value: Variant = index.get_value(folder, KEY_PLAYED_AT, 0)
		if value is int and int(value) > 0:
			out[folder] = int(value)
	return out


## Forgets level folder `folder` (deleted levels). No-op for a folder the index lacks.
static func forget(folder: String) -> void:
	var index := _load()
	if index.has_section(folder):
		index.erase_section(folder)
		index.save(path)


static func _load() -> ConfigFile:
	var index := ConfigFile.new()
	if FileAccess.file_exists(path):
		index.load(path)
	return index
