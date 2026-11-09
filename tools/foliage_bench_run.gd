extends SceneTree

## Runner for tools/foliage_bench.gd (perfaudit foliage stream): names no project class, so it
## compiles before the autoloads exist, then loads the bench once the tree runs. Usage:
##   godot --headless --path <project> --script res://tools/foliage_bench_run.gd -- --task=build
##     [--sizes=100,200,400] [--runs=3] [--gd_runs=1]

var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var script: GDScript = load("res://tools/foliage_bench.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return true
	var bench: RefCounted = script.new()
	bench.call("run", args)
	quit(0)
	return true
