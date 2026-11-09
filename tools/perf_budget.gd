extends SceneTree

## Prints the performance budget table (topic perfguard): every counter of
## tools/perf_budget_counters.gd with its value, its limit and the finding it guards. Headless, no
## window, a few seconds; exits 1 when a counter is over its budget. The same rows are asserted by
## tests/unit/test_perf_budget.gd in the gate and on CI.
##
##   godot --headless --path <project> --script res://tools/perf_budget.gd
##
## Also prints what the headless renderer reports for draw calls, so nobody builds a draw-call
## guard on it: the dummy rendering server counts nothing.

## Loaded at run time, not preloaded: a SceneTree script compiles before the autoloads exist, and
## the counters reach AssetManager through the token code.
const COUNTERS_PATH := "res://tools/perf_budget_counters.gd"
## Frames after which the run gives up (a script error inside _run would otherwise leave the
## process waiting forever).
const WATCHDOG_FRAMES := 2000

var _started := false
var _frames := 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > WATCHDOG_FRAMES:
		printerr("perf_budget: no result after %d frames" % WATCHDOG_FRAMES)
		quit(3)
	if _started:
		return false
	_started = true
	_run.call_deferred()
	return false


func _run() -> void:
	var counters: GDScript = load(COUNTERS_PATH)
	if counters == null or not counters.can_instantiate():
		printerr("perf_budget: %s does not compile" % COUNTERS_PATH)
		quit(2)
		return
	# An avatar token waits on the current scene when it enters the tree: a bare node stands in.
	var scene := Node.new()
	scene.name = "PerfBudgetScene"
	root.add_child(scene)
	current_scene = scene
	var rows: Array[Dictionary] = counters.rows(scene)
	print(counters.table(rows))
	await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var objects := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	)
	print("headless renderer: %d draw calls, %d objects in the last frame" % [draws, objects])
	var over := rows.filter(func(row: Dictionary) -> bool: return not counters.ok(row))
	for row: Dictionary in over:
		printerr(counters.message(row))
	scene.free()
	quit(1 if not over.is_empty() else 0)
