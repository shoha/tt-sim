class_name OpenTrace
extends RefCounted

## The first open of a new map as a player makes it, timed (card coldopen, 2026-11-09): the
## title's New map opens the dialog, the player looks for DIALOG_S and presses Create with a given
## spec, and the trace records BootTrace marks (the open path marks its stages: "dialog: ...",
## "authoring: ...", "open: ...", "load: ...") and every frame until the loading sheet drops, the
## starting cover has grown in and the surface prebake lane is idle. Off unless the command line
## asks for it (BootTrace's `--boot-trace-cold=<biome>,<size ft>,<landform>,<seed>`); with
## `--boot-trace-clear-cache` the core library's baked surface maps are deleted at the title
## first (SurfaceCache.remove_library), so the open bakes every map as a new player's first does.
##
##   godot --path <project> -- --boot-trace --boot-trace-idle=10 --boot-trace-clear-cache
##       --boot-trace-cold=temperate_forest_summer_s1,100,valley,1234 --boot-trace-quit
##
## The result (merged into BootTrace's JSON line): the three ends in ms after Create, the worst
## frame of the dialog and of the open with the stage it fell in (the last mark before it), the
## frames over HITCH_MS, and SurfaceStore's step timers (SurfaceStore.timings) in ms.

const DIALOG_S := 1.0
const TIMEOUT_S := 120.0
const HITCH_MS := 100.0
## Frames listed in the result, worst first.
const TOP_FRAMES := 8

static var _frame_ms := PackedFloat64Array()
static var _frame_stage := PackedStringArray()
static var _last_us: int = 0


## Deletes the core library's baked surface maps (the cache a new player does not have yet).
static func clear_cache() -> void:
	var cache: GDScript = load("res://utils/library/surface_cache.gd")
	var cleared: bool = cache.call("remove_library", LibraryContracts.CORE_ID)
	BootTrace.mark("cold trace: core surface cache cleared %s, bakes so far %s" % [
		cleared, str(SurfaceStore.stats)])


## Runs the open (see the class doc) and returns its result for the trace's JSON line.
static func run(tree: SceneTree, spec_text: String) -> Dictionary:
	var parts := spec_text.split(",")
	if parts.size() != 4:
		BootTrace.mark("cold trace: --boot-trace-cold wants biome,size,landform,seed")
		return {}
	var root: Node = tree.current_scene
	SurfaceStore.timings = {}
	SurfaceStore.timing_enabled = true
	_last_us = Time.get_ticks_usec()
	tree.process_frame.connect(_on_frame)
	BootTrace.mark("dialog: requested")
	root.call("request_authoring", null, &"title")
	var dialog: Node = root.get("_new_map_dialog")
	await tree.process_frame
	BootTrace.mark("dialog: first frame")
	var shown_at := Time.get_ticks_usec()
	while Time.get_ticks_usec() - shown_at < int(DIALOG_S * 1000000.0):
		await tree.process_frame
	dialog.set("_biome_id", parts[0])
	dialog.set("_size_ft", int(parts[1]))
	dialog.set("_landform", parts[2])
	(dialog.get("preset") as Dictionary)["seed"] = int(parts[3])
	var dialog_frames := _frame_ms.size()
	var created := Time.get_ticks_usec()
	BootTrace.mark("dialog: create pressed")
	dialog.call("_on_create_pressed")
	var out := {"cold_spec": spec_text}
	var ends := {
		"sheet_ms": _is_open.bind(root),
		"settled_ms": _settled.bind(root),
		"lane_idle_ms": _lane_idle,
	}
	for key: String in ends:
		while not ends[key].call():
			if Time.get_ticks_usec() - created > int(TIMEOUT_S * 1000000.0):
				BootTrace.mark("cold trace: timed out waiting for " + key)
				tree.process_frame.disconnect(_on_frame)
				return out
			await tree.process_frame
		out[key] = snappedf((Time.get_ticks_usec() - created) / 1000.0, 0.1)
		BootTrace.mark("cold trace: " + key.trim_suffix("_ms").replace("_", " "))
	tree.process_frame.disconnect(_on_frame)
	SurfaceStore.timing_enabled = false
	out["dialog_frames"] = _report(0, dialog_frames)
	out["open_frames"] = _report(dialog_frames, _frame_ms.size())
	var timings := {}
	for key: String in SurfaceStore.timings:
		var count := key.ends_with("_baked") or key.ends_with("_hit") or key.ends_with("_failed")
		var value := int(SurfaceStore.timings[key])
		timings[key] = value if count else snappedf(value / 1000.0, 0.1)
	out["surface_ms"] = timings
	out["surface_stats"] = SurfaceStore.stats.duplicate()
	for key: String in ["sheet_ms", "settled_ms", "lane_idle_ms"]:
		print("cold_trace: %s %.1f" % [key, out.get(key, -1.0)])
	print("cold_trace: dialog %s" % JSON.stringify(out["dialog_frames"]))
	print("cold_trace: open %s" % JSON.stringify(out["open_frames"]))
	print("cold_trace: surfaces %s" % JSON.stringify(timings))
	return out


static func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append((now - _last_us) / 1000.0)
	_frame_stage.append(BootTrace.last_mark())
	_last_us = now


static func _is_open(root: Node) -> bool:
	var controller: Node = root.get("_authoring_controller")
	return controller != null and is_instance_valid(controller) and bool(controller.get("_is_open"))


## The starting cover has grown in: nothing prepared, regenerating or growing.
static func _settled(root: Node) -> bool:
	var controller: Node = root.get("_authoring_controller")
	var scatter: Node = controller.get("scatter") if controller != null else null
	if scatter == null or not is_instance_valid(scatter):
		return false
	return not (
		scatter.call("has_prepared_species")
		or scatter.call("is_regenerating")
		or scatter.call("is_growing")
	)


static func _lane_idle() -> bool:
	return not SurfaceStore.is_prebaking()


## Frames [from, to): count, sum, worst first with their stages, the time over HITCH_MS.
static func _report(from: int, to: int) -> Dictionary:
	var order: Array[int] = []
	var total := 0.0
	var hitches := 0
	var frozen := 0.0
	for i in range(from, to):
		order.append(i)
		total += _frame_ms[i]
		if _frame_ms[i] > HITCH_MS:
			hitches += 1
			frozen += _frame_ms[i]
	order.sort_custom(func(a: int, b: int) -> bool: return _frame_ms[a] > _frame_ms[b])
	var worst: Array[String] = []
	for i in order.slice(0, TOP_FRAMES):
		worst.append("%.0f@%d %s" % [_frame_ms[i], i - from, _frame_stage[i]])
	return {
		"frames": to - from,
		"sum_ms": snappedf(total, 0.1),
		"over_100_ms": hitches,
		"in_frames_over_100_ms": snappedf(frozen, 0.1),
		"worst": worst,
	}
