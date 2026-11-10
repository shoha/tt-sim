extends RefCounted

## Render-job probe for the minimum-spec capture (card minspec2, 2026-11-10; job
## jobs/minspec_capture.json, docs/PERFORMANCE.md "Measuring on a real weak GPU"). The capture runs
## the GPU audit's in-run A/B (perfaudit_gpu.gd perf) on maps this probe saves, then bundles every
## table into one text file to send back. Actions:
##   {action: "save", folder}  writes the open authoring map as a level (as map_size/dump.gd save
##                             does), only into a user://levels/_minspec_* folder (replacing it)
##   {action: "cleanup"}       deletes every _minspec_* level folder through LevelManager
##   {action: "bundle", dir, out}  one file `out` (default minspec_report.txt) in `dir`: the machine
##                             (GPU, driver, API, CPU, cores, memory, OS, window, video memory) and
##                             then every *_table.txt and *_explore.txt in `dir`, in name order
## Never writes or deletes under user://levels/ outside a _minspec_ folder.

const PREFIX := "_minspec_"
const DEFAULT_DIR := "user://render_jobs/minspec_capture"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, String(step.get("folder", "")))
		"cleanup":
			return _cleanup()
		"bundle":
			return _bundle(
				String(step.get("dir", DEFAULT_DIR)), String(step.get("out", "minspec_report.txt"))
			)
	return "minspec: unknown action"


static func _save(base: Node, folder: String) -> String:
	if not folder.begins_with(PREFIX) or folder.length() <= PREFIX.length():
		return "save: %s is not a %s folder" % [folder, PREFIX]
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null:
		return "save: no authoring controller"
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path):
		LevelManager.delete_level_folder(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	var rows := MapDocument.row_count(ctrl.document.scatter)
	return "saved %s: %s, scatter rows %d" % [folder, str(ok), rows]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "cleanup: no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if not folder.begins_with(PREFIX) or folder.length() <= PREFIX.length():
			continue
		var ok := LevelManager.delete_level_folder(LevelManager.folder_path(folder))
		removed.append(folder if ok else folder + " (FAILED)")
	return "cleanup: removed %s" % str(removed)


static func _bundle(dir_path: String, out_name: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return "bundle: no folder %s" % dir_path
	var names: Array[String] = []
	for file in dir.get_files():
		if file.ends_with("_table.txt") or file.ends_with("_explore.txt"):
			names.append(file)
	names.sort()
	var lines := PackedStringArray(_machine())
	for file in names:
		lines.append("")
		lines.append("==== " + file)
		lines.append(FileAccess.get_file_as_string(dir_path.path_join(file)).strip_edges())
	var out := dir_path.path_join(out_name)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		return "bundle: cannot write %s" % out
	f.store_string("\n".join(lines) + "\n")
	return "bundle: %d files -> %s" % [names.size(), ProjectSettings.globalize_path(out)]


## What the numbers depend on, for the report's head.
static func _machine() -> Array[String]:
	var mem := OS.get_memory_info()
	return [
		"minspec capture report (card minspec2)",
		(
			"gpu: %s (%s, type %d), api %s, driver %s, method %s"
			% [
				RenderingServer.get_video_adapter_name(),
				RenderingServer.get_video_adapter_vendor(),
				RenderingServer.get_video_adapter_type(),
				RenderingServer.get_video_adapter_api_version(),
				RenderingServer.get_current_rendering_driver_name(),
				RenderingServer.get_current_rendering_method(),
			]
		),
		(
			"cpu: %s, %d threads; memory %.1f GB; os %s %s; godot %s"
			% [
				OS.get_processor_name(),
				OS.get_processor_count(),
				float(mem.get("physical", 0)) / 1073741824.0,
				OS.get_name(),
				OS.get_version(),
				Engine.get_version_info().get("string", ""),
			]
		),
		(
			"window %s, screen %s; video memory %.1f MB, textures %.1f MB, buffers %.1f MB"
			% [
				str(DisplayServer.window_get_size()),
				str(DisplayServer.screen_get_size()),
				_mb(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
				_mb(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
				_mb(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
			]
		),
	]


static func _mb(info: RenderingServer.RenderingInfo) -> float:
	return float(RenderingServer.get_rendering_info(info)) / 1048576.0
