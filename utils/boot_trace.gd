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
## `--boot-trace-map` then opens a new map and rebuilds it (first_map_ms, second_map_ms), and
## `--boot-trace-precompile` loads the on-demand scripts before the title settles, so the two
## together show what the on-demand doors moved from the start-up into the first map.
## `--boot-trace-cold=<biome>,<size ft>,<landform>,<seed>` instead opens that map through the
## new-map dialog as a player does and times it to the starting cover grown in and the surface
## lane idle (OpenTrace, loaded only then; `--boot-trace-clear-cache` deletes the core library's
## baked surface maps at the title first, for a new player's first open).
## Every frame from Root's first one to the end of the trace is also watched (watch_launch), the
## first-launch graphics warm-up included: the "launch" field holds the worst frames, each with the
## mark it followed, its draw time and the pipeline compiles in it, and the frames over HITCH_MS.
## At the end it prints the timeline and appends one JSON line to user://boot_trace.jsonl;
## `--boot-trace-quit` then quits, for scripted rounds (tools/render_jobs/local or a loop).

const SETTLE_S := 3.0
const HITCH_MS := 100.0
const LOG_PATH := "user://boot_trace.jsonl"
const MAP_TIMEOUT_S := 120
## The level --boot-trace-prep saves and --boot-trace-play plays (a topic-named test level).
const PLAY_FOLDER := "_boot2_play"
## The cold-open driver (--boot-trace-cold), loaded only when asked for (the start-up graph).
const OPEN_TRACE := "res://utils/open_trace.gd"

static var enabled: bool = _detect()
static var _marks: Array[Array] = []
static var _watching: bool = false
static var _title_at_us: int = 0
static var _last_us: int = 0
static var _frames: int = 0
static var _worst_ms: float = 0.0
static var _settled_us: int = 0
## The launch watch (watch_launch): one entry per frame, the frame's time, the mark it ended
## after, its draw time and the pipeline compiles in it ("" for none).
static var _launch_ms := PackedFloat64Array()
static var _launch_at_us := PackedInt64Array()
static var _launch_stage := PackedStringArray()
static var _launch_draw_ms := PackedFloat64Array()
static var _launch_comp := PackedStringArray()
static var _launch_last_us: int = 0
static var _launch_last_comp := PackedInt64Array()
static var _launch_comp_start := PackedInt64Array()
static var _draw_start_us: int = 0
static var _draw_ms: float = 0.0


static func _detect() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--boot-trace") or not OS.get_environment("TTSIM_BOOT_TRACE").is_empty()


## Records `label` at the current time, when the trace is on.
static func mark(label: String) -> void:
	if enabled:
		_marks.append([label, Time.get_ticks_usec()])


## The label of the latest mark ("" before the first).
static func last_mark() -> String:
	return String(_marks[-1][0]) if not _marks.is_empty() else ""


## The value of the user argument `--<name>=<value>`, "" when it is not given.
static func arg_value(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return ""


## Watches every frame from now to the end of the trace (the class doc), when the trace is on.
## Called once, at the end of Root._ready, before the first frame.
static func watch_launch(tree: SceneTree) -> void:
	if not enabled or not _launch_comp_start.is_empty():
		return
	_launch_last_us = Time.get_ticks_usec()
	_launch_last_comp = _compiles()
	_launch_comp_start = _launch_last_comp
	tree.process_frame.connect(_on_launch_frame)
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
		RenderingServer.frame_post_draw.connect(_on_post_draw)


static func _on_pre_draw() -> void:
	_draw_start_us = Time.get_ticks_usec()


static func _on_post_draw() -> void:
	_draw_ms += (Time.get_ticks_usec() - _draw_start_us) / 1000.0


static func _on_launch_frame() -> void:
	var now := Time.get_ticks_usec()
	var compiles := _compiles()
	_launch_ms.append((now - _launch_last_us) / 1000.0)
	_launch_at_us.append(now)
	_launch_stage.append(last_mark())
	_launch_draw_ms.append(_draw_ms)
	_launch_comp.append(_compile_text(_launch_last_comp, compiles))
	_launch_last_us = now
	_launch_last_comp = compiles
	_draw_ms = 0.0


## The pipeline compile counters, by the monitors' order (canvas, mesh, surface, draw,
## specialization).
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


## "cv2+su5": the compiles between counters `a` and `b`, "" for none. Pure.
static func _compile_text(a: PackedInt64Array, b: PackedInt64Array) -> String:
	var names := ["cv", "me", "su", "dr", "sp"]
	var out := PackedStringArray()
	for k in mini(a.size(), b.size()):
		if b[k] != a[k]:
			out.append("%s%d" % [names[k], b[k] - a[k]])
	return "+".join(out)


## The launch watch's summary: frames, the worst, the count and total of frames over HITCH_MS,
## the compiles by kind, and the worst `top` frames as "ms@at[stage | draw | compiles]".
static func launch_report(top: int = 12) -> Dictionary:
	var order: Array[int] = []
	var over := 0
	var over_ms := 0.0
	for i in _launch_ms.size():
		order.append(i)
		if _launch_ms[i] > HITCH_MS:
			over += 1
			over_ms += _launch_ms[i]
	order.sort_custom(func(a: int, b: int) -> bool: return _launch_ms[a] > _launch_ms[b])
	var worst: Array[String] = []
	for k in mini(top, order.size()):
		var i := order[k]
		worst.append(
			(
				"%.1f@%.0f[%s | draw %.1f | %s]"
				% [
					_launch_ms[i],
					_launch_at_us[i] / 1000.0,
					_launch_stage[i],
					_launch_draw_ms[i],
					_launch_comp[i],
				]
			)
		)
	return {
		"frames": _launch_ms.size(),
		"worst_ms": snappedf(_launch_ms[order[0]], 0.1) if not order.is_empty() else 0.0,
		"over_hitch": over,
		"over_hitch_ms": snappedf(over_ms, 0.1),
		"compiles": _compile_text(_launch_comp_start, _compiles()),
		"worst": worst,
	}


## Marks the title as built and watches the frames that follow (see the class doc). Called once,
## at the end of the title screen's _ready.
static func title_ready(tree: SceneTree) -> void:
	if not enabled or _watching:
		return
	mark("title _ready done")
	if OS.get_cmdline_user_args().has("--boot-trace-precompile"):
		_precompile()
	if OS.get_cmdline_user_args().has("--boot-trace-main-compile"):
		_main_compile()
	if OS.get_cmdline_user_args().has("--boot-trace-clear-cache"):
		load(OPEN_TRACE).call("clear_cache")
	_watching = true
	_title_at_us = Time.get_ticks_usec()
	_last_us = _title_at_us
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_on_first_draw, CONNECT_ONE_SHOT)
	tree.process_frame.connect(_on_frame.bind(tree))


## How long the title idles before the trace ends: SETTLE_S, or `--boot-trace-idle=<seconds>` (a
## realistic idle of 10 s lets BootPrecompile finish; 0.3 is an immediate click).
static func _settle_s() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boot-trace-idle="):
			return float(arg.get_slice("=", 1))
	return SETTLE_S


## `--boot-trace-quit-at=<seconds>`: leaves the game that long after the title is up, to probe a
## quit while BootPrecompile's worker is mid-compile. `--boot-trace-quit-via=close` sends the
## window's close request (what the OS does for the close button) instead of SceneTree.quit().
## Returns true once it has asked to quit.
static func _quit_early(tree: SceneTree, now_us: int) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--boot-trace-quit-at="):
			if now_us - _title_at_us < int(float(arg.get_slice("=", 1)) * 1000000.0):
				return false
			tree.process_frame.disconnect(_on_frame)
			mark("quitting early")
			if OS.get_cmdline_user_args().has("--boot-trace-quit-via=close"):
				tree.root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
				# The window's signal ends in SceneTree's handler, which quits when auto_accept_quit.
				tree.root.close_requested.emit()
			else:
				tree.quit()
			return true
	return false


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
	if _quit_early(tree, now):
		return
	if now - _title_at_us < int(_settle_s() * 1000000.0):
		return
	# A first launch's warm-up runs behind the title: the default settle waits for it, so the
	# trace sees the title's frames while it runs. An explicit idle acts after that long.
	var scene := tree.current_scene
	if arg_value("boot-trace-idle") == "" and scene != null and scene.get("_warmup_pending") == true:
		return
	tree.process_frame.disconnect(_on_frame)
	_finish(tree)


## `--boot-trace-precompile`: loads what the start-up leaves to first use (OnDemand,
## StructureProcgen), as the start-up compiled it before those doors: an A/B of what moved from
## the boot into the first map.
static func _precompile() -> void:
	for path: String in [
		OnDemand.BIOME_DESIGNER_HOST,
		OnDemand.LIBRARY_MANAGER,
		OnDemand.BIOME_DESIGNER_PICKER,
		OnDemand.BIOME_DESIGNER_ENTRY,
		OnDemand.NEW_MAP_DIALOG,
		OnDemand.GRAPHICS_WARMUP_SCREEN,
		StructureProcgen.STRUCTURE_REGISTRY,
		StructureProcgen.ROW_GEN,
		StructureProcgen.ROW_NODE,
	]:
		ResourceLoader.load(path)
	mark("precompiled the on-demand scripts")


## `--boot-trace-main-compile`: loads BootPrecompile's roots on the main thread, in one go (a
## hitch of seconds), to compare what the worker thread leaves at exit with the same scripts
## compiled on the main thread.
static func _main_compile() -> void:
	for path in BootPrecompile.ROOTS:
		ResourceLoader.load(path)
	mark("compiled the precompile roots on the main thread")


## `--boot-trace-map`: after the title settles, opens a new map (the new-map dialog's default
## spec, seed 7) as the player would, then rebuilds it in place (a warm second open), timing both:
## first_map_ms and second_map_ms. Gives up after MAP_TIMEOUT_S.
static func _maps(tree: SceneTree) -> Dictionary:
	var root: Node = tree.current_scene
	var dialog: Node = OnDemand.new_map_dialog({"seed": 7}, func(_spec: Dictionary) -> void: pass)
	root.add_child(dialog)
	await tree.process_frame
	var spec: Dictionary = dialog.current_spec()
	dialog.queue_free()
	await tree.process_frame
	var out := {}
	var started := Time.get_ticks_usec()
	mark("first map: open requested")
	root.call("_begin_authoring", {"level": null, "new_map": spec, "return_to": &"title"})
	# A first launch's warm-up holds the open until it is done (Root._when_warm), so the
	# controller may come later.
	var controller: Node = root.get("_authoring_controller")
	while controller == null or not bool(controller.get("_is_open")):
		if Time.get_ticks_usec() - started > MAP_TIMEOUT_S * 1000000:
			mark("first map: timed out")
			return out
		await tree.process_frame
		controller = root.get("_authoring_controller")
	out["first_map_ms"] = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)
	mark("first map: open")
	started = Time.get_ticks_usec()
	await controller.call("reopen_async")
	out["second_map_ms"] = snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)
	mark("second map (rebuilt in place): open")
	return out


## `--boot-trace-prep`: makes the level `--boot-trace-play` plays: opens a new map as _maps() does
## and saves it as PLAY_FOLDER in the user levels (delete that folder when the topic closes).
static func _prep(tree: SceneTree) -> void:
	var root: Node = tree.current_scene
	var dialog: Node = OnDemand.new_map_dialog({"seed": 7}, func(_spec: Dictionary) -> void: pass)
	root.add_child(dialog)
	await tree.process_frame
	var spec: Dictionary = dialog.current_spec()
	dialog.queue_free()
	root.call("_begin_authoring", {"level": null, "new_map": spec, "return_to": &"title"})
	var controller: Node = root.get("_authoring_controller")
	var started := Time.get_ticks_usec()
	while not bool(controller.get("_is_open")):
		if Time.get_ticks_usec() - started > MAP_TIMEOUT_S * 1000000:
			mark("prep: timed out")
			return
		await tree.process_frame
	for i in 30:
		await tree.process_frame
	var path: String = LevelManager.folder_path(PLAY_FOLDER)
	if DirAccess.dir_exists_absolute(path):
		LevelManager.delete_level_folder(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved: Resource = controller.get("level").duplicate(true)
	saved.set("level_name", PLAY_FOLDER)
	saved.set("level_folder", PLAY_FOLDER)
	controller.call("_sync_document")
	var ok: Variant = controller.get_script().write_level(saved, controller.get("document"), null)
	mark("prep: saved %s: %s" % [PLAY_FOLDER, str(ok)])


## `--boot-trace-play`: after the title settles, plays the level --boot-trace-prep saved, as the
## title's Play does: play_level_first_ms is the request until the table has loaded.
static func _play(tree: SceneTree) -> Dictionary:
	var root: Node = tree.current_scene
	var level: Variant = LevelManager.load_level_folder(PLAY_FOLDER, false)
	if level == null:
		mark("first play: no %s level (run --boot-trace-prep first)" % PLAY_FOLDER)
		return {}
	var started := Time.get_ticks_usec()
	mark("first play: requested")
	root.call("_on_play_level_requested", level)
	while true:
		await tree.process_frame
		var table: Node = root.get("_level_play_controller")
		if root.get("pending_level") == null and table != null and bool(table.call("has_active_level")):
			break
		if Time.get_ticks_usec() - started > MAP_TIMEOUT_S * 1000000:
			mark("first play: timed out")
			return {}
	mark("first play: loaded")
	return {"first_play_ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1)}


static func _finish(tree: SceneTree) -> void:
	if _settled_us == 0:
		_settled_us = _marks[-1][1]
	mark("settled (last frame over %d ms)" % int(HITCH_MS))
	_marks[-1][1] = _settled_us
	var maps := {}
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--boot-trace-prep"):
		await _prep(tree)
	if user_args.has("--boot-trace-map"):
		maps = await _maps(tree)
	if user_args.has("--boot-trace-play"):
		maps = await _play(tree)
	if arg_value("boot-trace-cold") != "":
		maps = await load(OPEN_TRACE).call("run", tree, arg_value("boot-trace-cold"))
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
		"launch": launch_report(),
	}
	print("boot_trace: launch %s" % JSON.stringify(line["launch"]))
	line.merge(maps)
	for key: String in maps:
		if maps[key] is float:
			print("boot_trace: %s %.1f" % [key, maps[key]])
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
