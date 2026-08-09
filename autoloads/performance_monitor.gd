extends Node

## Lightweight per-frame subsystem timing, exposed through Godot's Performance
## singleton so custom timers show up next to the engine's own monitors.
##
## Instrumented call sites wrap the code they want attributed with
## start_timer(name)/stop_timer(name). Both no-op immediately when disabled,
## so there is no Time.get_ticks_usec() cost anywhere when the diagnostic
## overlay is off.
##
## Usage:
##   PerformanceMonitor.start_timer(&"perf/camera_update_ms")
##   handle_movement(delta)
##   PerformanceMonitor.stop_timer(&"perf/camera_update_ms")

var enabled: bool = false

var _timer_starts_usec: Dictionary = {}  # StringName -> int
var _last_elapsed_usec: Dictionary = {}  # StringName -> int
var _registered_monitors: Dictionary = {}  # StringName -> true


func start_timer(name: StringName) -> void:
	if not enabled:
		return
	_timer_starts_usec[name] = Time.get_ticks_usec()


func stop_timer(name: StringName) -> void:
	if not enabled:
		return
	if not _timer_starts_usec.has(name):
		if OS.is_debug_build():
			push_warning(
				"PerformanceMonitor: stop_timer(%s) called without a matching start_timer" % name
			)
		return
	var elapsed: int = Time.get_ticks_usec() - _timer_starts_usec[name]
	_timer_starts_usec.erase(name)
	_last_elapsed_usec[name] = elapsed
	_register_monitor(name)


func _register_monitor(name: StringName) -> void:
	if _registered_monitors.has(name):
		return
	_registered_monitors[name] = true
	Performance.add_custom_monitor(name, _get_elapsed_ms.bindv([name]))


func _get_elapsed_ms(name: StringName) -> float:
	return _last_elapsed_usec.get(name, 0) / 1000.0
