extends RefCounted

## Render-job probe (`call` op) for the map library's level core (2026-10-09): the import
## check on real exports and an import's offscreen thumbnail under a real renderer, which a
## headless GUT run cannot draw. step.action:
##   check {paths}        GlbCheck on each path: MB, footprint in m and ft, floor and top,
##                        what the extras hold, the warning codes, the check's time.
##   import {path, name}  starts MapImport.import_glb(path, name, tree), a coroutine: follow
##                        it with a wait. Give a name under PREFIX.
##   report {out}         the import's result and time, and its saved thumbnail copied to
##                        `out` as import_thumb.png.
##   cleanup              deletes every PREFIX level folder (which forgets its source), then
##                        the source index file when nothing else is left in it.

const PREFIX := "_test_library_"

static var _result: Dictionary = {}
static var _started_usec: int = 0
static var _done_usec: int = 0


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"check":
			return _check(step.get("paths", []))
		"import":
			return _import(base, step)
		"report":
			return _report(String(step.get("out", "user://render_jobs/import_thumb/")))
		"cleanup":
			return _cleanup()
	return "unknown action"


static func _check(paths: Array) -> String:
	var lines := PackedStringArray()
	for path: Variant in paths:
		var started := Time.get_ticks_usec()
		var r := GlbCheck.check(String(path))
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		if r.error != "":
			lines.append("%s: refused (%s)" % [String(path).get_file(), r.error])
			continue
		var codes: Array = r.warnings.map(func(w: Dictionary) -> String: return w.code)
		lines.append(
			(
				"%s: %.1f MB, %.1f x %.1f m (%.0f x %.0f ft), floor %.2f top %.2f, %s, %s, %.1f ms"
				% [
					String(path).get_file(),
					r.mb,
					r.footprint_m.x,
					r.footprint_m.y,
					r.footprint_ft.x,
					r.footprint_ft.y,
					r.floor_m,
					r.top_m,
					str(r.extras),
					str(codes),
					ms,
				]
			)
		)
	return " | ".join(lines)


static func _import(base: Node, step: Dictionary) -> String:
	var level_name := String(step.get("name", PREFIX + "import"))
	if not Paths.sanitize_level_name(level_name).begins_with(PREFIX):
		return "refused: the name must start with %s" % PREFIX
	_result = {}
	_done_usec = 0
	_started_usec = Time.get_ticks_usec()
	_run_import(String(step.get("path", "")), level_name, base.get_tree())
	return "started"


static func _run_import(path: String, level_name: String, tree: SceneTree) -> void:
	_result = await MapImport.import_glb(path, level_name, tree)
	_done_usec = Time.get_ticks_usec()


static func _report(out: String) -> String:
	if _result.is_empty():
		return "not finished"
	var ms := (_done_usec - _started_usec) / 1000.0
	var folder := String(_result.get("folder", ""))
	var line := (
		"ok %s folder %s thumbnail %s error '%s' in %.0f ms"
		% [str(_result.ok), folder, str(_result.thumbnail), _result.error, ms]
	)
	var thumb := LevelManager.thumbnail_path(folder)
	if folder != "" and FileAccess.file_exists(thumb):
		DirAccess.make_dir_recursive_absolute(out)
		var image := Image.load_from_file(ProjectSettings.globalize_path(thumb))
		image.save_png(out.path_join("import_thumb.png"))
		line += ", thumbnail %dx%d copied" % [image.get_width(), image.get_height()]
	return line


static func _cleanup() -> String:
	var removed := 0
	for folder in DirAccess.get_directories_at(LevelManager.levels_dir):
		if folder.begins_with(PREFIX):
			if LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
				removed += 1
	var index := ConfigFile.new()
	var dropped_index := false
	if index.load(ImportSources.path) == OK and index.get_sections().is_empty():
		dropped_index = DirAccess.remove_absolute(ImportSources.path) == OK
	return "removed %d level(s), empty index removed %s" % [removed, str(dropped_index)]
