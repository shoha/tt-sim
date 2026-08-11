extends GutTest

## Unit tests for PerformanceLogFormatter (utils/performance_log_formatter.gd).


func test_format_header_matches_column_order() -> void:
	var header := PerformanceLogFormatter.format_header()
	assert_eq(
		header,
		(
			"elapsed_s,map_name,fps_avg,frame_time_avg_ms,frame_time_max_ms,"
			+ "draw_calls,primitives,video_mem_mb,physics_objects,"
			+ "perf_occlusion_fade_ms,perf_camera_update_ms,perf_grid_overlay_ms,"
			+ "render_cpu_ms,video_adapter_name,video_adapter_vendor,camera_zoom,"
			+ "screen_scale,antialiasing,rendering_method,viewport_width,"
			+ "viewport_height,toggle_foliage_visible,toggle_tree_shadows,"
			+ "toggle_grass_shadows,toggle_map_shadows,toggle_sun_shadows,"
			+ "toggle_hard_sun_shadows,toggle_trivial_foliage_shader,"
			+ "toggle_unshaded_foliage_textured,toggle_cheap_lighting_foliage"
		),
	)


func test_format_row_orders_and_formats_values() -> void:
	# draw_calls/primitives/physics_objects are passed as floats here to match
	# what Performance.get_monitor() actually returns in production -- the
	# int() coercion in format_row() must still produce "812" not "812.0".
	var row := (
		PerformanceLogFormatter
		. format_row(
			{
				"elapsed_s": 12.3,
				"map_name": "River",
				"fps_avg": 34.5,
				"frame_time_avg_ms": 29.4,
				"frame_time_max_ms": 51.0,
				"draw_calls": 812.0,
				"primitives": 1200000.0,
				"video_mem_mb": 780.5,
				"physics_objects": 340.0,
				"perf_occlusion_fade_ms": 4.1,
				"perf_camera_update_ms": 0.2,
				"perf_grid_overlay_ms": 0.15,
				"render_cpu_ms": 3.7,
				"video_adapter_name": "Apple M1",
				"video_adapter_vendor": "Apple",
				"camera_zoom": 5.5,
				"screen_scale": 2.0,
				"antialiasing": "4x",
				"rendering_method": "forward_plus",
				"viewport_width": 1280.0,
				"viewport_height": 800.0,
				"toggle_foliage_visible": true,
				"toggle_tree_shadows": true,
				"toggle_grass_shadows": true,
				"toggle_map_shadows": false,
				"toggle_sun_shadows": true,
				"toggle_hard_sun_shadows": false,
				"toggle_trivial_foliage_shader": false,
				"toggle_unshaded_foliage_textured": false,
				"toggle_cheap_lighting_foliage": false,
			}
		)
	)
	assert_eq(
		row,
		(
			'12.30,"River",34.50,29.40,51.00,812,1200000,780.50,340,4.10,0.20,0.15,3.70,'
			+ '"Apple M1","Apple",5.50,2.00,"4x","forward_plus",1280,800,1,1,1,0,1,0,0,0,0'
		),
	)


func test_format_row_quotes_map_name_containing_comma_and_quote() -> void:
	# map_name is arbitrary user-editable text; a comma here would otherwise
	# split into an extra CSV field and shift every later column.
	var row := PerformanceLogFormatter.format_row({"map_name": 'River, Night "Update"'})
	assert_eq(
		row,
		(
			'0.00,"River, Night ""Update""",0.00,0.00,0.00,0,0,0.00,0,0.00,0.00,0.00,0.00,"","",'
			+ '0.00,0.00,"","",0,0,0,0,0,0,0,0,0,0,0'
		),
	)


func test_format_row_quotes_video_adapter_name_containing_comma() -> void:
	# Some GPU driver strings legitimately contain commas (e.g. vendor lists),
	# so the same quoting must apply to every string column, not just map_name.
	var row := PerformanceLogFormatter.format_row({"video_adapter_name": "Apple M1, 8-core GPU"})
	assert_eq(
		row,
		(
			'0.00,"",0.00,0.00,0.00,0,0,0.00,0,0.00,0.00,0.00,0.00,"Apple M1, 8-core GPU","",'
			+ '0.00,0.00,"","",0,0,0,0,0,0,0,0,0,0,0'
		),
	)


func test_format_row_defaults_missing_columns() -> void:
	var row := PerformanceLogFormatter.format_row({})
	assert_eq(
		row,
		(
			'0.00,"",0.00,0.00,0.00,0,0,0.00,0,0.00,0.00,0.00,0.00,"","",0.00,0.00,"","",'
			+ "0,0,0,0,0,0,0,0,0,0,0"
		),
	)
