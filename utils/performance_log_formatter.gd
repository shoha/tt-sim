class_name PerformanceLogFormatter
extends RefCounted

## Pure CSV formatting for performance session logs. Kept separate from
## PerformanceOverlay so the header/row format is unit-testable without a
## running scene tree (--headless cannot produce real rendering output --
## see AGENTS.md's "Headless testing cannot verify real rendering output").

const CSV_COLUMNS: PackedStringArray = [
	"elapsed_s",
	"map_name",
	"fps_avg",
	"frame_time_avg_ms",
	"frame_time_max_ms",
	"draw_calls",
	"primitives",
	"video_mem_mb",
	"physics_objects",
	"perf_occlusion_fade_ms",
	"perf_camera_update_ms",
	"perf_grid_overlay_ms",
	"render_cpu_ms",
	"video_adapter_name",
	"video_adapter_vendor",
	"camera_zoom",
	"screen_scale",
	"antialiasing",
	"rendering_method",
	"viewport_width",
	"viewport_height",
	"toggle_foliage_visible",
	"toggle_tree_shadows",
	"toggle_grass_shadows",
	"toggle_map_shadows",
	"toggle_sun_shadows",
	"toggle_hard_sun_shadows",
	"toggle_trivial_foliage_shader",
	"toggle_unshaded_foliage_textured",
	"toggle_cheap_lighting_foliage",
]

## Columns rendered with 2 decimal places; every other column uses str(value).
const _FLOAT_COLUMNS: PackedStringArray = [
	"elapsed_s",
	"fps_avg",
	"frame_time_avg_ms",
	"frame_time_max_ms",
	"video_mem_mb",
	"perf_occlusion_fade_ms",
	"perf_camera_update_ms",
	"perf_grid_overlay_ms",
	"render_cpu_ms",
	"camera_zoom",
	"screen_scale",
]

## Columns holding arbitrary text (not user-editable in every case, but never
## guaranteed comma/quote-free) -- quoted and escaped per minimal CSV quoting
## rules so they can't shift subsequent columns.
const _STRING_COLUMNS: PackedStringArray = [
	"map_name",
	"video_adapter_name",
	"video_adapter_vendor",
	"antialiasing",
	"rendering_method",
]


static func format_header() -> String:
	return ",".join(CSV_COLUMNS)


## [param data] should contain a value for every key in CSV_COLUMNS. Missing
## keys default to 0 for numeric columns or "" for string columns.
static func format_row(data: Dictionary) -> String:
	var values: Array[String] = []
	for column in CSV_COLUMNS:
		if column in _FLOAT_COLUMNS:
			values.append("%.2f" % float(data.get(column, 0.0)))
		elif column in _STRING_COLUMNS:
			var text: String = str(data.get(column, ""))
			values.append('"%s"' % text.replace('"', '""'))
		else:
			# Remaining columns are integer-valued engine monitors.
			# Performance.get_monitor() always returns float, so coerce to
			# int explicitly to avoid a trailing ".0" in the CSV.
			values.append(str(int(data.get(column, 0))))
	return ",".join(values)
