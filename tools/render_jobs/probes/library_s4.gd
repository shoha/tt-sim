extends RefCounted

## Render-job probe (`call` op) for the multi-library registry (content library step S4).
## step.action:
##   report                   logs LibraryRegistry.list(): each library's id, source, version,
##                            status, served flag, biome ids and reasons.
##   document                 logs what the open authoring map would write: the libraries it
##                            uses (MapLibraries.record_for), the format number
##                            (MapLibraries.format_for) and the (library, asset ids) it needs
##                            (LibraryRegistry.assets_used_by).
##   save {folder, replace}   saves the open map as a test level into a `_libs4_` folder and logs
##                            the manifest it wrote (format and libraries), read back.
##   cleanup                  deletes every `_libs4_` level.

const SAVE_PREFIX := "_libs4_"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"report":
			return _report()
		"document":
			return _document(base)
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup()
	return "unknown action"


static func _report() -> String:
	var lines := PackedStringArray()
	for item in LibraryRegistry.list():
		lines.append(
			(
				"%s [%s] v%s status=%s served=%s biomes=%s %s"
				% [
					item["id"],
					item["source"],
					item["version"],
					item["status"],
					item["served"],
					str(item["biome_ids"]),
					str(item["reasons"]),
				]
			)
		)
	return "\n".join(lines)


static func _document(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.document == null:
		return "no open map"
	ctrl.call("_sync_document")
	var record := MapLibraries.record_for(ctrl.document)
	var used := LibraryRegistry.assets_used_by(ctrl.document)
	var counts := {}
	for library: String in used:
		counts[library] = (used[library] as PackedStringArray).size()
	return (
		"libraries %s, format %d, biomes %s, assets per library %s"
		% [
			JSON.stringify(record),
			MapLibraries.format_for(record),
			str(ctrl.document.biome_ids),
			str(counts)
		]
	)


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", ""))
	if ctrl == null or not folder.begins_with(SAVE_PREFIX):
		return "no authoring controller, or not a %s folder" % SAVE_PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	var file := LevelManager.map_document_path(folder)
	var reader := ZIPReader.new()
	var manifest := {}
	if reader.open(file) == OK:
		manifest = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
		reader.close()
	return (
		"saved %s: %s, format %s, libraries %s"
		% [folder, str(ok), str(manifest.get("format")), JSON.stringify(manifest.get("libraries"))]
	)


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(SAVE_PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %d: %s" % [removed.size(), str(removed)]


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
