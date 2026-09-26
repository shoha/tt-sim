class_name AuthoringAutosave
extends RefCounted

## The authoring crash-recovery slot: the map document and its level, written every
## AuthoringController.AUTOSAVE_INTERVAL seconds while the session has unsaved edits, and
## offered back the next time authoring opens (the Level Editor's LevelEditorHistory
## pattern, with its own storage).
##
## It shares `user://levels/_autosave/` with the Level Editor's autosave but not its file
## names: the editor owns `level.json` there, so the level beside the map is
## `map_level.json`, and neither recovery prompt ever offers the other's work. The level is
## a full LevelData.to_dict() (a few kB); keeping its level_folder means a recovered map
## saves back into the level it came from, and a dressing map finds its map.glb there.

const DOCUMENT_NAME := "map.ttmap"
const LEVEL_NAME := "map_level.json"

## The slot's directory. Tests point it at a temp directory.
static var directory: String = Paths.LEVELS_DIR + "_autosave/"


static func document_path() -> String:
	return directory + DOCUMENT_NAME


static func level_path() -> String:
	return directory + LEVEL_NAME


## True when both halves of an autosave are on disk.
static func exists() -> bool:
	return FileAccess.file_exists(document_path()) and FileAccess.file_exists(level_path())


## Writes `doc` (atomically, through MapDocumentIO) and `level` into the slot.
static func write(doc: MapDocument, level: LevelData) -> Error:
	if not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return made
	var err := MapDocumentIO.write(doc, document_path())
	if err != OK:
		return err
	var file := FileAccess.open(level_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(level.to_dict(), "\t"))
	file.close()
	return OK


## The autosaved level, or null when it is missing or unreadable. Its map_document names
## the document even if the level never had one saved, since the slot always holds one.
static func read_level() -> LevelData:
	if not FileAccess.file_exists(level_path()):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(level_path())) != OK:
		return null
	if not json.data is Dictionary:
		return null
	var level := LevelData.from_dict(json.data)
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	return level


## Removes both files (after a save, a discard, or a recovery that was declined).
static func discard() -> void:
	for path in [document_path(), level_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
