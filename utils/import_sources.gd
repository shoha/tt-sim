class_name ImportSources
extends RefCounted

## The local index of where each imported level's map.glb came from: one ConfigFile section
## per level folder, holding the source path the author picked (a Blender export somewhere on
## this machine) and when it was imported. It lives under the data root beside levels/, never
## inside a level folder, so nothing lists, duplicates or streams it, and another machine's
## paths never arrive with a level.
##
## "Updated in Blender" is a comparison of two files, not a stored timestamp: the source is
## newer than the level's copy (the copy is written when the map is imported or replaced, so
## it is newer than its source until Blender exports again). A source that is gone is never
## updated.

const KEY_SOURCE := "source"
const KEY_IMPORTED_AT := "imported_at"

## The index file. Tests point this at their own file (the LevelManager.levels_dir pattern).
static var path: String = Paths.import_sources_path()


## Remembers `source_path` as where the map.glb of level folder `folder` came from.
static func record(folder: String, source_path: String) -> Error:
	var index := _load()
	index.set_value(folder, KEY_SOURCE, source_path)
	index.set_value(folder, KEY_IMPORTED_AT, int(Time.get_unix_time_from_system()))
	return index.save(path)


## The source path of level folder `folder`, or "" when it was not imported from a file.
static func source_of(folder: String) -> String:
	var value: Variant = _load().get_value(folder, KEY_SOURCE, "")
	return value if value is String else ""


## Forgets level folder `folder` (deleted levels). No-op for a folder the index lacks.
static func forget(folder: String) -> void:
	var index := _load()
	if index.has_section(folder):
		index.erase_section(folder)
		index.save(path)


## True when level folder `folder` has a recorded source file that is newer than the map.glb
## at `level_map_path` (the level's copy): Blender exported it again since.
static func is_updated(folder: String, level_map_path: String) -> bool:
	var source := source_of(folder)
	if source == "" or not FileAccess.file_exists(source):
		return false
	if not FileAccess.file_exists(level_map_path):
		return false
	return is_newer(
		FileAccess.get_modified_time(source), FileAccess.get_modified_time(level_map_path)
	)


## True when a source modified at `source_time` is newer than a copy modified at
## `copy_time` (unix seconds). Pure.
static func is_newer(source_time: int, copy_time: int) -> bool:
	return source_time > copy_time


static func _load() -> ConfigFile:
	var index := ConfigFile.new()
	if FileAccess.file_exists(path):
		index.load(path)
	return index
