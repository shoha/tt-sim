extends GutTest

## Unit tests for PerformanceMonitor (autoloads/performance_monitor.gd).


func after_each() -> void:
	PerformanceMonitor.enabled = false


func test_start_and_stop_timer_noop_when_disabled() -> void:
	PerformanceMonitor.enabled = false
	PerformanceMonitor.start_timer(&"perf/test_noop_ms")
	PerformanceMonitor.stop_timer(&"perf/test_noop_ms")
	assert_false(Performance.has_custom_monitor(&"perf/test_noop_ms"))


func test_stop_timer_after_start_records_elapsed_and_registers_monitor() -> void:
	PerformanceMonitor.enabled = true
	PerformanceMonitor.start_timer(&"perf/test_elapsed_ms")
	PerformanceMonitor.stop_timer(&"perf/test_elapsed_ms")
	assert_true(Performance.has_custom_monitor(&"perf/test_elapsed_ms"))
	var value: float = Performance.get_custom_monitor(&"perf/test_elapsed_ms")
	assert_true(value >= 0.0)


func test_stop_timer_without_matching_start_does_not_register_monitor() -> void:
	PerformanceMonitor.enabled = true
	PerformanceMonitor.stop_timer(&"perf/test_unmatched_ms")
	# The warning from stop_timer is expected when called without a matching start_timer
	assert_false(Performance.has_custom_monitor(&"perf/test_unmatched_ms"))
	# stop_timer's debug-build push_warning is expected here -- mark it handled
	# so GUT doesn't fail the test on an "unexpected" engine error.
	for err in get_errors():
		err.handled = true
