class_name AuthoringAutosave
extends RefCounted

## The authoring crash-recovery slot: the map document and its level, written every
## AuthoringSaving.AUTOSAVE_INTERVAL seconds while the session has unsaved edits, and
## offered back the next time authoring opens (the Level Editor's LevelEditorHistory
## pattern, with its own storage).
##
## It shares `user://levels/_autosave/` with the Level Editor's autosave but not its file
## names: the editor owns `level.json` there, so the level beside the map is
## `map_level.json`, and neither recovery prompt ever offers the other's work. The level is
## a full LevelData.to_dict() (a few kB); keeping its level_folder means a recovered map
## saves back into the level it came from, and a dressing map finds its map.glb there.
##
## Both files are replaced atomically (a temp file renamed over each), the document first, so a
## crash during an autosave leaves the previous autosave whole; the session writes them on a
## worker (AuthoringSaving), and a discard waits for a write in flight before it deletes.

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


## Writes `doc` and `level` into the slot on the calling thread (the session writes it on a
## worker: AuthoringSaving starts job() on a MapDocumentWriter).
static func write(doc: MapDocument, level: LevelData) -> Error:
	var made := ensure_directory()
	if made != OK:
		return made
	var autosave := job(doc, level)
	MapDocumentWriter.run(autosave)
	if autosave.error == OK:
		MapFileHash.invalidate(autosave.path)
	return autosave.error


## The slot's write as a MapDocumentWriter job: `doc` frozen now (MapDocumentSnapshot) and the
## level's JSON as a side file, each written atomically, the level only after the document.
## Main thread (the capture and LevelData.to_dict read live state); the job runs anywhere.
static func job(doc: MapDocument, level: LevelData) -> MapDocumentWriter.Job:
	var out := MapDocumentWriter.Job.new()
	out.snapshot = MapDocumentSnapshot.capture(doc)
	out.path = document_path()
	out.side_files = {level_path(): JSON.stringify(level.to_dict(), "\t").to_utf8_buffer()}
	return out


## Makes the slot's directory when it is missing.
static func ensure_directory() -> Error:
	if DirAccess.dir_exists_absolute(directory):
		return OK
	return DirAccess.make_dir_recursive_absolute(directory)


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
