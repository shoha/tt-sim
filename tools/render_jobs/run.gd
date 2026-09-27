extends SceneTree

## Render-job runner (see README.md in this folder). A plain godot command, no bridge:
##   godot --path D:/dev/tt-sim --windowed --resolution 1920x1080 --position 320,120
##     --script res://tools/render_jobs/run.gd -- <job> [--out <dir>]
## <job> is a JSON file path, or a name under res://tools/render_jobs/jobs/ (".json" optional).
## Loads the project's main scene, forces a 1920x1080 window on the primary screen, runs the
## job's steps through driver.gd (same folder), then quits. Job keys besides "steps":
##   "out_dir"          output folder; relative paths resolve under user://
##                      (default user://render_jobs/<job name>); --out overrides it
##   "timeout_s"        hard stop (default 300)
##   "remove_override"  delete res://override.cfg once the engine has read it

const JOBS_DIR := "res://tools/render_jobs/jobs"
const DEFAULT_OUT_ROOT := "user://render_jobs"
const OVERRIDE := "res://override.cfg"

var _job: Dictionary = {}
var _out_dir: String = ""
var _frames: int = 0
var _started: bool = false
var _start_ms: int = 0


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var path := _resolve_job_path(args[0] if args.size() > 0 else "")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		print("RJ| bad job %s" % path)
		quit(2)
		return
	_job = parsed
	var out_arg := _option(args, "--out")
	_out_dir = _resolve_out_dir(out_arg if out_arg != "" else String(_job.get("out_dir", "")), path)
	var override_abs := ProjectSettings.globalize_path(OVERRIDE)
	if bool(_job.get("remove_override", false)) and FileAccess.file_exists(override_abs):
		DirAccess.remove_absolute(override_abs)
		print("RJ| override.cfg removed after startup")
	print("RJ| job %s -> %s" % [path, _out_dir])
	change_scene_to_file(String(ProjectSettings.get_setting("application/run/main_scene")))


func _process(_delta: float) -> bool:
	_frames += 1
	var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
	if elapsed > float(_job.get("timeout_s", 300.0)):
		print("RJ| TIMEOUT after %.0f s" % elapsed)
		return true
	if not _started:
		if _frames > 30 and current_scene != null and elapsed > 3.0:
			_start()
		return false
	var done: Variant = root.get_meta("render_job_done", "")
	if done is String and done != "":
		print("RJ| done in %.1f s" % elapsed)
		return true
	return false


func _start() -> void:
	_started = true
	var window := root.get_window()
	var primary := DisplayServer.get_primary_screen()
	window.current_screen = primary
	window.position = DisplayServer.screen_get_position(primary) + Vector2i(200, 60)
	window.size = Vector2i(1920, 1080)
	var dir := (get_script() as Script).resource_path.get_base_dir()
	var driver_script := load(dir.path_join("driver.gd")) as GDScript
	var driver: Node = driver_script.new()
	driver.set("steps", _job.steps)
	driver.set("out_dir", _out_dir)
	driver.set("root_node", current_scene)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.add_child(driver)
	print("RJ| started %d steps" % _job.steps.size())


## The job argument as given if that file exists, else the same name under JOBS_DIR,
## with ".json" appended when missing.
static func _resolve_job_path(arg: String) -> String:
	if arg == "" or FileAccess.file_exists(arg):
		return arg
	var named := JOBS_DIR.path_join(arg)
	if FileAccess.file_exists(named):
		return named
	if not arg.ends_with(".json") and FileAccess.file_exists(named + ".json"):
		return named + ".json"
	return arg


## Absolute paths (including res:// and user://) stay as they are, relative ones resolve
## under user://, and an empty one becomes user://render_jobs/<job file name>.
static func _resolve_out_dir(out_dir: String, job_path: String) -> String:
	if out_dir == "":
		return DEFAULT_OUT_ROOT.path_join(job_path.get_file().get_basename())
	if out_dir.is_absolute_path():
		return out_dir
	return "user://".path_join(out_dir)


## The value after `name` ("--out dir") or after "=" ("--out=dir"), else "".
static func _option(args: PackedStringArray, name: String) -> String:
	for k in args.size():
		if args[k] == name and k + 1 < args.size():
			return args[k + 1]
		if args[k].begins_with(name + "="):
			return args[k].substr(name.length() + 1)
	return ""
