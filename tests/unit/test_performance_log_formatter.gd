extends GutTest

## Unit tests for PerformanceLogFormatter (utils/performance_log_formatter.gd).


func test_format_header_matches_column_order() -> void:
	var header := PerformanceLogFormatter.format_header()
	assert_eq(
		header,
		(
			"elapsed_s,map_name,fps_avg,frame_time_avg_ms,frame_time_max_ms,"
			+ "draw_calls,primitives,video_mem_mb,physics_objects,"
			+ "perf_occlusion_fade_ms,perf_camera_update_ms,perf_grid_overlay_ms"
		),
	)


func test_format_row_orders_and_formats_values() -> void:
	var row := PerformanceLogFormatter.format_row(
		{
			"elapsed_s": 12.3,
			"map_name": "River",
			"fps_avg": 34.5,
			"frame_time_avg_ms": 29.4,
			"frame_time_max_ms": 51.0,
			"draw_calls": 812,
			"primitives": 1200000,
			"video_mem_mb": 780.5,
			"physics_objects": 340,
			"perf_occlusion_fade_ms": 4.1,
			"perf_camera_update_ms": 0.2,
			"perf_grid_overlay_ms": 0.15,
		}
	)
	assert_eq(row, "12.30,River,34.50,29.40,51.00,812,1200000,780.50,340,4.10,0.20,0.15")


func test_format_row_defaults_missing_columns() -> void:
	var row := PerformanceLogFormatter.format_row({})
	assert_eq(row, "0.00,,0.00,0.00,0.00,0,0,0.00,0,0.00,0.00,0.00")
