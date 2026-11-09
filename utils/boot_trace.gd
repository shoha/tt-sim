class_name BootTrace
extends RefCounted

## A timeline of the game's start, from the process start to the title screen taking input
## (perf audit boot, 2026-11-09). Off unless the command line asks for it, so a normal launch pays
## one bool check per mark.
##
## Turn it on with `--boot-trace` after `--` (or the TTSIM_BOOT_TRACE environment variable):
##   godot --path <project> -- --boot-trace [--boot-trace-quit]
##   godot --main-pack <game.pck> -- --boot-trace --boot-trace-quit
## Every mark() records the milliseconds since the process started (Time.get_ticks_usec, which
## counts from the engine's own start). Marks sit in the first and last autoload's _init (their
## script graphs are compiled by then: GDScript compiles every script a script names before it
## runs), in Root._ready's steps and at the end of the title's _ready. Then the trace watches the
## frames: the first frame after the title (its first draw in a window), "interactive" (the next
## frame: input is read at the start of each frame), the worst frame in the next SETTLE_S seconds
## and "settled" (the end of the last frame over HITCH_MS in that span), so work moved past the
## first frame still shows up as a hitch.
##
## At the end it prints the timeline and appends one JSON line to user://boot_trace.jsonl;
## `--boot-trace-quit` then quits, for scripted rounds (tools/render_jobs/local or a loop).

const SETTLE_S := 3.0
const HITCH_MS := 100.0
const LOG_PATH := "user://boot_trace.jsonl"

static var enabled: bool = _detect()
static var _marks: Array[Array] = []
static var _watching: bool = false
static var _title_at_us: int = 0
static var _last_us: int = 0
static var _frames: int = 0
static var _worst_ms: float = 0.0
static var _settled_us: int = 0


static func _detect() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--boot-trace") or not OS.get_environment("TTSIM_BOOT_TRACE").is_empty()


## Records `label` at the current time, when the trace is on.
static func mark(label: String) -> void:
	if enabled:
		_marks.append([label, Time.get_ticks_usec()])


## Marks the title as built and watches the frames that follow (see the class doc). Called once,
## at the end of the title screen's _ready.
static func title_ready(tree: SceneTree) -> void:
	if not enabled or _watching:
		return
	mark("title _ready done")
	_watching = true
	_title_at_us = Time.get_ticks_usec()
	_last_us = _title_at_us
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_on_first_draw, CONNECT_ONE_SHOT)
	tree.process_frame.connect(_on_frame.bind(tree))


static func _on_first_draw() -> void:
	mark("first title frame drawn")


static func _on_frame(tree: SceneTree) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_us) / 1000.0
	_last_us = now
	_frames += 1
	if _frames == 1:
		mark("first frame after title")
	elif _frames == 2:
		mark("title interactive")
	else:
		_worst_ms = maxf(_worst_ms, frame_ms)
		if frame_ms > HITCH_MS:
			_settled_us = now
	if now - _title_at_us < int(SETTLE_S * 1000000.0):
		return
	tree.process_frame.disconnect(_on_frame)
	_finish(tree)


static func _finish(tree: SceneTree) -> void:
	if _settled_us == 0:
		_settled_us = _marks[-1][1]
	mark("settled (last frame over %d ms)" % int(HITCH_MS))
	_marks[-1][1] = _settled_us
	var rows: Array[Dictionary] = []
	var prev_us := 0
	print("boot_trace: %d marks, worst frame after the title %.1f ms" % [_marks.size(), _worst_ms])
	for entry: Array in _marks:
		var at_us: int = entry[1]
		print("boot_trace: %9.1f ms  +%8.1f  %s" % [
			at_us / 1000.0, (at_us - prev_us) / 1000.0, entry[0]])
		rows.append({"label": entry[0], "ms": snappedf(at_us / 1000.0, 0.1)})
		prev_us = at_us
	var loaded := scripts_loaded()
	print("boot_trace: %d of %d project scripts loaded at the end" % [loaded.x, loaded.y])
	var line := {
		"time": Time.get_datetime_string_from_system(),
		"scripts_loaded": loaded.x,
		"scripts_total": loaded.y,
		# An exported pack holds project.binary in place of the text project file.
		"pack": not FileAccess.file_exists("res://project.godot"),
		"display": DisplayServer.get_name(),
		"worst_frame_ms": snappedf(_worst_ms, 0.1),
		"marks": rows,
	}
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(line))
		f.close()
	if OS.get_cmdline_user_args().has("--boot-trace-quit"):
		tree.quit()


## (scripts in the resource cache, scripts in the game's folders): how much of the project the
## start-up compiled. An exported pack lists its scripts as .gdc or .gd.remap; both count as
## their .gd path.
static func scripts_loaded() -> Vector2i:
	var paths: Dictionary = {}
	for dir in ["res://autoloads", "res://scenes", "res://utils", "res://resources", "res://procgen"]:
		_collect_scripts(dir, paths)
	var loaded := 0
	for path: String in paths:
		if ResourceLoader.has_cached(path):
			loaded += 1
	return Vector2i(loaded, paths.size())


static func _collect_scripts(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(".gdc"):
			name = name.trim_suffix(".gdc") + ".gd"
		if name.ends_with(".gd"):
			out[dir.path_join(name)] = true
	for sub in d.get_directories():
		_collect_scripts(dir.path_join(sub), out)
