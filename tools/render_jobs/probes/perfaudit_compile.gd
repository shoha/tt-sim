extends SceneTree

## Start-up script cost (performance audit, system stream, 2026-11). Headless:
##   godot --headless --path <project> --script res://tools/render_jobs/probes/perfaudit_compile.gd
## At _initialize (engine set-up and the autoloads' script loads done, nothing in the tree yet)
## it counts the project's .gd files already in the resource cache, then times a fresh load
## (CACHE_MODE_IGNORE: a new parse, analysis and compile of that one file, its dependencies
## taken from the cache) of every .gd under the folders below, and a deep fresh load
## (CACHE_MODE_IGNORE_DEEP) of each autoload and of the main scene. Prints `RJ| compile` lines.

const FOLDERS := [
	"res://autoloads", "res://scenes", "res://utils", "res://resources", "res://procgen"
]


func _initialize() -> void:
	var init_ms := Time.get_ticks_usec() / 1000.0
	var files := PackedStringArray()
	for folder: String in FOLDERS:
		_collect(folder, files)
	var cached := 0
	for f in files:
		cached += int(ResourceLoader.has_cached(f))
	print(
		(
			"RJ| compile | ticks at _initialize %.0f ms, %d .gd files, %d already loaded"
			% [init_ms, files.size(), cached]
		)
	)
	var times: Array = []
	var total := 0.0
	for f in files:
		var t0 := Time.get_ticks_usec()
		ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		times.append([ms, f])
	times.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top := PackedStringArray()
	for k in mini(15, times.size()):
		top.append("%.1f %s" % [times[k][0], String(times[k][1]).get_file()])
	print("RJ| compile each file fresh: %.0f ms in all | %s" % [total, ", ".join(top)])
	var deep := PackedStringArray()
	for prop: Dictionary in ProjectSettings.get_property_list():
		var name := String(prop.name)
		if not name.begins_with("autoload/"):
			continue
		var path := String(ProjectSettings.get_setting(name)).trim_prefix("*")
		var t0 := Time.get_ticks_usec()
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		deep.append("%s %.0f" % [name.trim_prefix("autoload/"), (Time.get_ticks_usec() - t0) / 1000.0])
	var main := String(ProjectSettings.get_setting("application/run/main_scene"))
	var t1 := Time.get_ticks_usec()
	ResourceLoader.load(main, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	deep.append("main scene %.0f" % ((Time.get_ticks_usec() - t1) / 1000.0))
	print("RJ| compile deep fresh ms | %s" % ", ".join(deep))
	quit(0)


static func _collect(folder: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(folder.path_join(f))
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect(folder.path_join(sub), out)
