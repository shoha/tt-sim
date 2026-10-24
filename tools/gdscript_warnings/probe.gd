extends Node

## Loads and recompiles every project script so the GDScript analyzer reports its warnings
## to the attached debugger (collect.py is the debugger). Autoloads exist because this runs
## as a scene, not as a `--script` main loop. Skips addons, the native build and dot folders.

const SKIPPED_DIRS: PackedStringArray = ["addons", "native", "build"]


func _ready() -> void:
	var files: Array[String] = []
	_walk("res://", files)
	for path in files:
		if path == get_script().resource_path:
			continue  # recompiling the running script stalls the run
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		if script == null:
			print("PROBE_NULL ", path)
		else:
			script.reload(true)
	print("PROBE_DONE ", files.size())
	get_tree().quit()


func _walk(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or SKIPPED_DIRS.has(sub):
			continue
		_walk(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
