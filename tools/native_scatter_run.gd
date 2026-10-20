extends SceneTree

## Runner for tools/native_scatter_bench.gd (card native-scatter): names no project class, so it
## compiles before the autoloads exist, then loads the bench once the tree runs. Usage:
##   godot --headless --path <project> --script res://tools/native_scatter_run.gd -- --task=<task>
##     [--runs=N] [--warm=N]
## Tasks: job (the probe cell's job, native against GDScript, one thread), threads (1, 6 and 12
## concurrent jobs), map (a whole new map's scatter build through ScatterRegen's jobs), counts
## (native and fallback jobs over the five landform recipe maps).

var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var bench: RefCounted = load("res://tools/native_scatter_bench.gd").new()
	bench.call("run", args)
	quit(0)
	return true
