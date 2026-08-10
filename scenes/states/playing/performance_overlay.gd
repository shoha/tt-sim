class_name PerformanceOverlay
extends Node

## On-screen diagnostic overlay showing engine + custom performance monitors.
## Toggled by the perf_overlay_toggle action (F3). Off by default each session.
## Renders on Constants.LAYER_PERF_OVERLAY via MapOverlayUtils' label-panel
## styling, matching the MeasureTool/DragRuler overlay conventions.
##
## Usage:
##   var overlay = PerformanceOverlay.new()
##   overlay.setup(game_map)
##   overlay.toggle()  # GameMap._input() routes the F3 key here

const SAMPLE_INTERVAL_SEC := 0.25

const _CUSTOM_MONITOR_NAMES: PackedStringArray = [
	&"perf/occlusion_fade_ms",
	&"perf/camera_update_ms",
	&"perf/grid_overlay_ms",
]

var _game_map: GameMap = null
var _visible: bool = false
var _elapsed_since_sample: float = 0.0
var _session_elapsed_sec: float = 0.0

## Fetched once in setup() -- adapter/driver identity doesn't change at
## runtime, so there is no reason to re-query RenderingServer every interval.
var _video_adapter_name: String = ""
var _video_adapter_vendor: String = ""

var _frame_time_sum_ms: float = 0.0
var _frame_time_max_ms: float = 0.0
var _frame_count: int = 0

var _log_file: FileAccess = null
var _log_file_disabled: bool = false

var _canvas_layer: CanvasLayer
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	set_process(false)


func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_video_adapter_name = RenderingServer.get_video_adapter_name()
	_video_adapter_vendor = RenderingServer.get_video_adapter_vendor()
	_create_overlay(game_map)


## Toggle overlay visibility, PerformanceMonitor instrumentation, and file
## logging together -- the overlay is the only consumer of the custom timers
## and the log file, so there is no reason to pay their overhead while hidden.
func toggle() -> void:
	_visible = not _visible
	PerformanceMonitor.enabled = _visible
	_panel.visible = _visible
	set_process(_visible)
	if _visible:
		_elapsed_since_sample = 0.0
		_session_elapsed_sec = 0.0
		_reset_frame_accumulators()
		_open_log_file()
		_update_display()
	else:
		_close_log_file()


func _exit_tree() -> void:
	_close_log_file()
	PerformanceMonitor.enabled = false


func is_visible_overlay() -> bool:
	return _visible


func _process(delta: float) -> void:
	_accumulate_frame_sample(delta)
	_elapsed_since_sample += delta
	_session_elapsed_sec += delta
	if _elapsed_since_sample < SAMPLE_INTERVAL_SEC:
		return
	_elapsed_since_sample = 0.0
	_update_display()
	_write_log_row()
	_reset_frame_accumulators()


## Maps a Viewport.MSAA enum value to the short label used in the on-screen display
## and the CSV log's antialiasing column.
static func _msaa_level_label(msaa_level: int) -> String:
	match msaa_level:
		Viewport.MSAA_2X:
			return "2x"
		Viewport.MSAA_4X:
			return "4x"
		Viewport.MSAA_8X:
			return "8x"
		_:
			return "None"


func _update_display() -> void:
	var lines: PackedStringArray = [
		"FPS: %.0f" % Performance.get_monitor(Performance.TIME_FPS),
		"Frame (script): %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		(
			"Frame (physics): %.2f ms"
			% (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		),
		"Draw calls: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"Primitives: %d" % Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		(
			"Video mem: %.1f MB"
			% (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
		),
		"Physics objects: %d" % Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"Render (CPU): %.2f ms" % _get_render_cpu_ms(),
		"GPU: %s (%s)" % [_video_adapter_name, _video_adapter_vendor],
		"Camera zoom: %.2f" % _game_map.camera_node.size,
		"Screen scale: %.2f" % DisplayServer.screen_get_scale(),
		(
			"World viewport: %dx%d"
			% [_game_map.world_viewport.size.x, _game_map.world_viewport.size.y]
		),
		"Antialiasing: %s" % _msaa_level_label(_game_map.world_viewport.msaa_3d),
		"Renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
	]
	for monitor_name in _CUSTOM_MONITOR_NAMES:
		if Performance.has_custom_monitor(monitor_name):
			lines.append(
				"%s: %.2f ms" % [monitor_name, Performance.get_custom_monitor(monitor_name)]
			)
	_label.text = "\n".join(lines)


## Render-thread CPU time for the 3D game-world SubViewport specifically
## (excludes 2D UI layers), read via RenderingServer rather than the
## Performance singleton (which has no per-viewport render-time monitor).
## The matching GPU-time query is deliberately not used: it is a known,
## unfixed Godot limitation that it always returns 0.0 on Metal (the M1
## Air's backend) because Metal's tile-based renderer reorders GPU commands
## in a way that breaks Godot's timestamp-based measurement -- see
## https://github.com/godotengine/godot/issues/102968. Logging that number
## would just be a confident-looking zero, not a real measurement.
func _get_render_cpu_ms() -> float:
	var viewport_rid := _game_map.world_viewport.get_viewport_rid()
	return RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)


## [param delta] is the real per-frame wall-clock interval from _process(),
## used (rather than Performance.TIME_PROCESS, which is script-time only and
## excludes rendering/GPU/vsync) so the CSV avg/max columns reflect true
## frame time and can catch GPU-bound stutters.
func _accumulate_frame_sample(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_frame_time_sum_ms += frame_ms
	_frame_time_max_ms = maxf(_frame_time_max_ms, frame_ms)
	_frame_count += 1


func _reset_frame_accumulators() -> void:
	_frame_time_sum_ms = 0.0
	_frame_time_max_ms = 0.0
	_frame_count = 0


func _open_log_file() -> void:
	_log_file_disabled = false
	var dir_err := DirAccess.make_dir_recursive_absolute(Paths.PERF_LOG_DIR)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning(
			(
				"PerformanceOverlay: could not create %s (%s) -- file logging disabled"
				% [Paths.PERF_LOG_DIR, error_string(dir_err)]
			)
		)
		_log_file_disabled = true
		return
	var file_path := "%sperf_%d.csv" % [Paths.PERF_LOG_DIR, Time.get_unix_time_from_system()]
	_log_file = FileAccess.open(file_path, FileAccess.WRITE)
	if not _log_file:
		push_warning(
			(
				"PerformanceOverlay: could not open %s (%s) -- file logging disabled"
				% [file_path, error_string(FileAccess.get_open_error())]
			)
		)
		_log_file_disabled = true
		return
	_log_file.store_line(PerformanceLogFormatter.format_header())


func _close_log_file() -> void:
	if _log_file:
		_log_file.close()
		_log_file = null


func _write_log_row() -> void:
	if _log_file_disabled or not _log_file:
		return
	var frame_time_avg_ms: float = _frame_time_sum_ms / maxf(float(_frame_count), 1.0)
	var data := {
		"elapsed_s": _session_elapsed_sec,
		"map_name": _game_map.get_current_map_name(),
		"fps_avg": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_avg_ms": frame_time_avg_ms,
		"frame_time_max_ms": _frame_time_max_ms,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"physics_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"render_cpu_ms": _get_render_cpu_ms(),
		"video_adapter_name": _video_adapter_name,
		"video_adapter_vendor": _video_adapter_vendor,
		"camera_zoom": _game_map.camera_node.size,
		"screen_scale": DisplayServer.screen_get_scale(),
		"antialiasing": _msaa_level_label(_game_map.world_viewport.msaa_3d),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		"viewport_width": _game_map.world_viewport.size.x,
		"viewport_height": _game_map.world_viewport.size.y,
	}
	var debug_toggles := _game_map.get_debug_render_toggles()
	if debug_toggles:
		data.merge(debug_toggles.get_toggle_states())
	for monitor_name in _CUSTOM_MONITOR_NAMES:
		var column := String(monitor_name).replace("/", "_")
		data[column] = (
			Performance.get_custom_monitor(monitor_name)
			if Performance.has_custom_monitor(monitor_name)
			else 0.0
		)
	_log_file.store_line(PerformanceLogFormatter.format_row(data))
	_log_file.flush()


func _create_overlay(overlay_parent: Node) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = Constants.LAYER_PERF_OVERLAY
	overlay_parent.add_child(_canvas_layer)

	var result: Dictionary = MapOverlayUtils.create_label_panel(13, Color(0.8, 1.0, 0.8))
	_panel = result.panel
	_label = result.label
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(16, 16)
	_canvas_layer.add_child(_panel)
