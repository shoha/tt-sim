class_name MapImport
extends RefCounted

## Bringing a Blender map into the library, and bringing it up to date (contract:
## docs/ASSET_PIPELINE.md section 11). The library screen calls these and only wires buttons.
##
## Import (import_glb) runs the import check (GlbCheck), which the UI has already shown, and
## refuses what it refuses; warnings never block. It makes a new level folder, writes
## map.glb into it before level.json (so level.json never names a file that is not there),
## records where the file came from in the local source index (ImportSources), and renders
## the card's thumbnail offscreen (LevelThumbnail, best-effort: none under the headless
## renderer). The level is named after the file, or after its folder when the file is the
## usual "map.glb".
##
## Replace (replace_map) puts a new map.glb under an existing level: Replace map file with a
## picked file, or Reload from Blender with the remembered one when ImportSources says the
## source is newer. It runs the same check, then either keeps the level's dressing document
## (KEEP_DRESSING, DressingReconcile: heights refit on the next open, rows off the new map
## dropped and counted) or starts fresh (START_FRESH: the document is kept beside it as
## map.ttmap.bak, never streamed, and the level is a plain Blender map again). Tokens and the
## level's look are untouched either way.
##
## Both are coroutines because of the thumbnail; everything they write is written before
## the first await, so the level is complete on disk when the render starts.

const KEEP_DRESSING := "keep"
const START_FRESH := "fresh"
## The suffix of the document Start fresh keeps (map.ttmap.bak).
const BACKUP_SUFFIX := ".bak"
## The file stem a Blender export usually has; such a file is named after its folder.
const PLAIN_STEM := "map"

const ERROR_NO_LEVEL := "That level could not be read."
const ERROR_WRITE := "The map could not be written into the library."
const ERROR_MODE := "Choose Keep dressing or Start fresh."
const ERROR_DOCUMENT := "The level's dressing could not be read; Start fresh keeps a copy of it."
const ERROR_NOT_DRESSING := (
	"This level's ground was built in tt-sim, so only Start fresh can put a Blender map under it."
)


## The level name an import of `path` gets: the file's stem, or its folder's name when the
## stem is "map" (D:/maps/harbour/map.glb is "Harbour"), as words ("_" and "-" are spaces),
## each with a capital first letter and the rest as the author typed it.
static func default_name(path: String) -> String:
	var stem := path.get_file().get_basename()
	if stem.to_lower() == PLAIN_STEM:
		var parent := path.get_base_dir().get_file()
		if parent != "":
			stem = parent
	var words := PackedStringArray()
	for word in stem.replace("_", " ").replace("-", " ").split(" ", false):
		words.append(word.left(1).to_upper() + word.substr(1))
	return " ".join(words) if not words.is_empty() else NewMap.DEFAULT_NAME


## Imports the map GLB at `path` as a new level called `level_name` (default_name() when
## empty). Returns {"ok", "error" (the refusal or failure, one sentence), "report" (the
## import check), "folder" (the new level folder), "thumbnail" (true when one was saved)}.
## `tree` renders the thumbnail; null skips it.
static func import_glb(path: String, level_name: String = "", tree: SceneTree = null) -> Dictionary:
	var result := write_import(path, level_name)
	if result.ok:
		result.thumbnail = await _render_thumbnail(result.folder, tree)
	return result


## import_glb() without the thumbnail: everything it writes, synchronously.
static func write_import(path: String, level_name: String = "") -> Dictionary:
	var report := GlbCheck.check(path)
	var result := {
		"ok": false, "error": report.error, "report": report, "folder": "", "thumbnail": false
	}
	if report.error != "":
		return result
	var named := level_name.strip_edges()
	var level := LevelData.new()
	level.level_name = named if named != "" else default_name(path)
	var folder := LevelManager.new_folder_name(level.level_name)
	var kept := _hold_current()
	var saved := LevelManager.save_level_folder(level, folder, path)
	_restore_current(kept)
	if saved == "":
		LevelManager.delete_level_folder(LevelManager.folder_path(folder))
		result.error = ERROR_WRITE
		return result
	ImportSources.record(folder, path)
	result.ok = true
	result.folder = folder
	return result


## Replaces the map.glb of level folder `folder` with the GLB at `path`, `mode` KEEP_DRESSING
## or START_FRESH (see the header). Returns {"ok", "error", "report", "mode",
## "props_dropped", "scatter_dropped" (rows Keep dressing removed), "backup" (the kept
## document's path, Start fresh), "thumbnail"}. `tree` renders the new thumbnail; null skips.
static func replace_map(
	folder: String, path: String, mode: String, tree: SceneTree = null
) -> Dictionary:
	var result := write_replace(folder, path, mode)
	if result.ok:
		result.thumbnail = await _render_thumbnail(folder, tree)
	return result


## replace_map() without the thumbnail: everything it writes, synchronously. Order: map.glb,
## then the document (rewritten, or moved to the backup), then level.json.
static func write_replace(folder: String, path: String, mode: String) -> Dictionary:
	var report := GlbCheck.check(path)
	var result := {
		"ok": false,
		"error": report.error,
		"report": report,
		"mode": mode,
		"props_dropped": 0,
		"scatter_dropped": 0,
		"backup": "",
		"thumbnail": false,
	}
	if report.error != "":
		return result
	if mode != KEEP_DRESSING and mode != START_FRESH:
		result.error = ERROR_MODE
		return result
	var kept := _hold_current()
	var level := (
		LevelManager.load_level_folder(folder, false)
		if FileAccess.file_exists(LevelManager.json_path(folder))
		else null
	)
	_restore_current(kept)
	if level == null:
		result.error = ERROR_NO_LEVEL
		return result
	var document_path := LevelManager.map_document_path(folder)
	var has_document := level.map_document != "" and FileAccess.file_exists(document_path)
	var dressing: Dictionary = {}
	if has_document and mode == KEEP_DRESSING:
		var read := MapDocumentIO.read(document_path)
		var doc: MapDocument = read.document
		if doc == null:
			result.error = ERROR_DOCUMENT
			return result
		if not doc.has_base_map:
			result.error = ERROR_NOT_DRESSING
			return result
		dressing = DressingReconcile.keep(doc, report.bounds)
	if not LevelManager.copy_map_to_level(path, folder):
		result.error = ERROR_WRITE
		return result
	if not dressing.is_empty():
		if MapDocumentIO.write(dressing.document, document_path) != OK:
			result.error = ERROR_WRITE
			return result
		result.props_dropped = dressing.props_dropped
		result.scatter_dropped = dressing.scatter_dropped
	elif has_document:
		var backup := document_path + BACKUP_SUFFIX
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(document_path, backup) != OK:
			result.error = ERROR_WRITE
			return result
		MapFileHash.invalidate(document_path)
		level.map_document = ""
		result.backup = backup
	level.map_path = Paths.LEVEL_MAP_NAME
	kept = _hold_current()
	var saved := LevelManager.save_level_folder(level, folder)
	_restore_current(kept)
	if saved == "":
		result.error = ERROR_WRITE
		return result
	ImportSources.record(folder, path)
	result.ok = true
	return result


## True when level folder `folder` was imported from a file that Blender has written since
## (the card's "Updated in Blender"; its menu's Reload from Blender is replace_map() with
## ImportSources.source_of(folder)).
static func is_updated_in_blender(folder: String) -> bool:
	return ImportSources.is_updated(folder, LevelManager.map_path(folder))


## Renders and saves the thumbnail of level folder `folder` from its map.glb. True when one
## was saved.
static func _render_thumbnail(folder: String, tree: SceneTree) -> bool:
	if tree == null or not LevelThumbnail.can_render():
		return false
	var image := await LevelThumbnail.render_glb_async(LevelManager.map_path(folder), tree)
	if image == null:
		return false
	var level := LevelData.new()
	level.level_folder = folder
	return LevelManager.save_thumbnail(level, image)


## LevelManager's current level, which its load and save calls move, to put back after them.
static func _hold_current() -> Array:
	return [LevelManager.current_level, LevelManager.current_level_path]


static func _restore_current(held: Array) -> void:
	LevelManager.current_level = held[0]
	LevelManager.current_level_path = held[1]
