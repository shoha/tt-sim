extends "res://tools/render_jobs/run.gd"

## The render-job runner with a boot timeline (performance audit, system stream, 2026-11).
## Same command form and job files as run.gd, with this script in its place:
##   godot --path <project> --windowed --resolution 1920x1080 --position 320,120
##     --script res://tools/render_jobs/probes/perfaudit_boot.gd -- <job> [flags]
## Time.get_ticks_usec() counts from the engine's OS start, so the ticks at `_initialize` are
## the engine set-up plus the autoloads' script loads and _init (the main loop exists, the
## autoloads are built but not yet in the tree). The main scene's load (with every preload of
## root.gd: the title screen, the game map, the warm-up screen) is timed around run.gd's
## change_scene_to_file; the frames after it are recorded until the title state's first frame
## (the warm-up, when it runs, is inside that span and timed by its own end). The timeline is
## printed as one `RJ| boot` line and stored as root meta "perfaudit_boot" for the
## perfaudit_system.gd `boot` action.

const TITLE_STATE := 0
const WARMUP_STATE := 6

var _boot := {}
var _boot_frames := PackedFloat64Array()
var _boot_comp: Array = []
var _boot_last_us := 0
var _boot_last_comp := PackedInt64Array()
var _boot_done := false
var _warm_seen := false


func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	_boot["engine_and_autoload_init_ms"] = t0 / 1000.0
	_boot["autoloads"] = root.get_child_count()
	super._initialize()
	var t1 := Time.get_ticks_usec()
	_boot["main_scene_load_ms"] = (t1 - t0) / 1000.0
	_boot_last_us = t1
	_boot_last_comp = _compiles()


func _process(delta: float) -> bool:
	if not _boot_done:
		_boot_frame()
	return super._process(delta)


func _boot_frame() -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _boot_last_us) / 1000.0
	_boot_last_us = now
	_boot_frames.append(frame_ms)
	var c := _compiles()
	_boot_comp.append(_compile_text(_boot_last_comp, c))
	_boot_last_comp = c
	if _boot_frames.size() == 1:
		_boot["first_frame_ms"] = frame_ms
	var scene := current_scene
	if scene == null:
		return
	var state: Variant = null
	if scene.has_method("get_current_state"):
		state = scene.call("get_current_state")
	if state == WARMUP_STATE and not _warm_seen:
		_warm_seen = true
		_boot["warmup_start_ms"] = now / 1000.0
	if state != TITLE_STATE:
		return
	_boot_done = true
	_boot["title_ms"] = now / 1000.0
	if _warm_seen:
		_boot["warmup_ms"] = now / 1000.0 - float(_boot["warmup_start_ms"])
	_boot["frames_to_title"] = _boot_frames.size()
	var worst := PackedStringArray()
	var order := range(_boot_frames.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _boot_frames[a] > _boot_frames[b])
	for k in mini(8, order.size()):
		worst.append("%.1f@%d[%s]" % [_boot_frames[order[k]], order[k], _boot_comp[order[k]]])
	_boot["worst_frames"] = " ".join(worst)
	_boot["static_mb"] = OS.get_static_memory_usage() / 1048576.0
	_boot["video_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_boot["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	root.set_meta("perfaudit_boot", _boot)
	var parts := PackedStringArray()
	for key: String in _boot:
		var v: Variant = _boot[key]
		parts.append("%s %s" % [key, ("%.1f" % v) if v is float else str(v)])
	print("RJ| boot | " + ", ".join(parts))


static func _compiles() -> PackedInt64Array:
	return PackedInt64Array(
		[
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
		]
	)


static func _compile_text(a: PackedInt64Array, b: PackedInt64Array) -> String:
	var names := ["cv", "me", "su", "dr", "sp"]
	var out := PackedStringArray()
	for k in a.size():
		if b[k] != a[k]:
			out.append("%s%d" % [names[k], b[k] - a[k]])
	return "+".join(out) if not out.is_empty() else "-"
