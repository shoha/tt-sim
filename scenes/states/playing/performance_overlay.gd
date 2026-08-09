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

var _canvas_layer: CanvasLayer
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	set_process(false)


func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_create_overlay(game_map)


## Toggle overlay visibility and PerformanceMonitor instrumentation together --
## the overlay is the only consumer of the custom timers, so there is no
## reason to pay their (small) per-call overhead while it is hidden.
func toggle() -> void:
	_visible = not _visible
	PerformanceMonitor.enabled = _visible
	_panel.visible = _visible
	set_process(_visible)
	if _visible:
		_elapsed_since_sample = 0.0
		_update_display()


func is_visible_overlay() -> bool:
	return _visible


func _process(delta: float) -> void:
	_elapsed_since_sample += delta
	if _elapsed_since_sample < SAMPLE_INTERVAL_SEC:
		return
	_elapsed_since_sample = 0.0
	_update_display()


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
	]
	for monitor_name in _CUSTOM_MONITOR_NAMES:
		if Performance.has_custom_monitor(monitor_name):
			lines.append(
				"%s: %.2f ms" % [monitor_name, Performance.get_custom_monitor(monitor_name)]
			)
	_label.text = "\n".join(lines)


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
