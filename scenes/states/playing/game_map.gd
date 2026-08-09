class_name GameMap
extends Node3D

## Main game map controller for the playing state.
## Manages camera movement/zoom, the lo-fi visual effect, and token context menus.
##
## ARCHITECTURE (SubViewport-based rendering):
## The 3D scene renders to a SubViewport, then the lo-fi shader is applied as a
## 2D post-process via SubViewportContainer's material. This approach properly
## handles transparent objects (glass, water, particles, selection glow) - they
## all receive the lo-fi effect correctly.
##
## Scene structure:
##   GameMap (Node3D) - this script
##   ├── WorldViewportLayer (CanvasLayer, layer=-1)
##   │   └── SubViewportContainer (lo-fi shader applied here)
##   │       └── SubViewport
##   │           ├── CameraHolder/Camera3D
##   │           ├── MapContainer (map geometry, environment)
##   │           ├── DragAndDrop3D (tokens)
##   │           └── OcclusionFadeManager (fades geometry hiding tokens)
##   └── GameplayMenu (CanvasLayer - UI on top)
##
## INPUT HANDLING NOTE:
## Camera zoom uses _input() instead of _unhandled_input() because input events
## routed through SubViewportContainer may not reach _unhandled_input on this node.
## Keyboard camera movement still uses _unhandled_key_input() which works correctly.
##
## LO-FI EFFECT:
## Toggle via set_lofi_enabled(bool) or Settings menu. The effect is applied
## by setting a ShaderMaterial on viewport_container. See lofi_canvas.gdshader.

var _level_play_controller: LevelPlayController = null
var _measure_tool: MeasureTool = null
var _grid_overlay: GridOverlay = null
var _drag_ruler: DragRuler = null
var _weather_renderer: WeatherRenderer = null
var _action_history: GameplayActionHistory = null
var _visual_effects: VisualEffectsController = null
var _grid_visibility: GridVisibilityController = null
var _token_context_menu: TokenContextMenuController = null
var _drag_place: DragPlaceController = null
var _camera_controller: CameraController = null
var _perf_overlay: PerformanceOverlay = null
var _foliage_hidden: bool = false

@onready var viewport_container: SubViewportContainer = $WorldViewportLayer/SubViewportContainer
@onready var world_viewport: SubViewport = $WorldViewportLayer/SubViewportContainer/SubViewport
@onready
var cameraholder_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder
@onready var camera_node: Camera3D = get_node(
	"WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D"
)
@onready var tiltshift_node: MeshInstance3D = get_node(
	"WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D/MeshInstance3D"
)
@onready
var map_container: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/MapContainer
@onready
var drag_and_drop_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/DragAndDrop3D

# OcclusionFadeManager - type resolved at runtime after editor imports the new script
@onready var occlusion_fade: Node3D = get_node(
	"WorldViewportLayer/SubViewportContainer/SubViewport/OcclusionFadeManager"
)
@onready var gameplay_menu: CanvasLayer = $GameplayMenu


## Forward to CameraController -- kept callable as GameMap.compute_aspect_corrected_size(...)
## because test_camera_aspect_correction.gd calls it exactly that way.
static func compute_aspect_corrected_size(
	height: float, vp_size: Vector2i, reference_aspect: float
) -> float:
	return CameraController.compute_aspect_corrected_size(height, vp_size, reference_aspect)


func _ready() -> void:
	_action_history = GameplayActionHistory.new()
	_action_history.name = "GameplayActionHistory"
	add_child(_action_history)
	_visual_effects = VisualEffectsController.new()
	_visual_effects.name = "VisualEffectsController"
	add_child(_visual_effects)
	_visual_effects.setup(self)
	_grid_visibility = GridVisibilityController.new()
	_grid_visibility.name = "GridVisibilityController"
	add_child(_grid_visibility)
	_grid_visibility.setup(self)
	_token_context_menu = TokenContextMenuController.new()
	_token_context_menu.name = "TokenContextMenuController"
	add_child(_token_context_menu)
	_token_context_menu.setup(self)
	_drag_place = DragPlaceController.new()
	_drag_place.name = "DragPlaceController"
	add_child(_drag_place)
	_camera_controller = CameraController.new()
	_camera_controller.name = "CameraController"
	add_child(_camera_controller)
	_camera_controller.setup(self)


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller
	_drag_place.setup(self, Callable(_level_play_controller, "spawn_asset"))

	# Store home camera position for reset (Home key).
	_camera_controller.capture_home_position()

	# Pass the controller to the gameplay menu
	if gameplay_menu:
		var menu_controller = gameplay_menu.get_node_or_null("GameplayMenu")
		if menu_controller and menu_controller.has_method("setup"):
			menu_controller.setup(level_play_controller)
			if menu_controller.has_signal("drag_place_started"):
				menu_controller.drag_place_started.connect(_drag_place._on_drag_place_started)


func _input(event: InputEvent) -> void:
	# Use _input instead of _unhandled_input because events going through
	# SubViewportContainer may not reach _unhandled_input on this node.
	if _is_level_loading():
		return

	# Always track mouse position for zoom-toward-cursor, even during measurement
	if event is InputEventMouseMotion:
		_camera_controller.record_mouse_position(event.position)

	# Drag-to-place: track ghost and handle drop/cancel
	if _drag_place.handle_input(event):
		return

	# Toggle measure tool — handled in _input (not _unhandled_key_input) because
	# SubViewportContainer routing can swallow key events before they reach
	# _unhandled_key_input. Uses both the input action and a direct keycode
	# fallback in case the project hasn't reloaded the input map yet.
	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_text_input_focused():
			var is_m_key: bool = event.is_action_pressed("measure_toggle") or event.keycode == KEY_M
			if is_m_key and _measure_tool:
				_measure_tool.toggle()
				get_viewport().set_input_as_handled()
				return

			var is_g_key: bool = event.keycode == KEY_G
			if is_g_key:
				_grid_visibility.toggle_explicit()
				get_viewport().set_input_as_handled()
				return

			var is_f1_key: bool = event.is_action_pressed("help_toggle") or event.keycode == KEY_F1
			if is_f1_key:
				UIManager.toggle_help()
				get_viewport().set_input_as_handled()
				return

			var is_f3_key: bool = (
				event.is_action_pressed("perf_overlay_toggle") or event.keycode == KEY_F3
			)
			if is_f3_key and _perf_overlay:
				_perf_overlay.toggle()
				get_viewport().set_input_as_handled()
				return

			# Debug-only: hide/show scattered foliage (trees + grass) to check
			# whether foliage rendering itself is a performance cost,
			# independent of camera zoom/position. No formal input action --
			# this is a diagnostic aid, not a documented feature, matching the
			# G-key grid toggle's raw-keycode convention above.
			var is_f4_key: bool = event.keycode == KEY_F4
			if is_f4_key:
				_toggle_foliage_visibility()
				get_viewport().set_input_as_handled()
				return

			# Undo (Ctrl+Z) — GM only
			if event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
				if (
					_action_history
					and NetworkManager.has_gm_access()
					and _action_history.can_undo()
				):
					var desc := _action_history.undo()
					if desc != "":
						UIManager.show_info("Undone: %s" % desc)
					get_viewport().set_input_as_handled()
					return

	# Measure tool gets first look at input when active.
	# handle_input returns true if the event was consumed (clicks on terrain, etc.).
	# Mouse motion is never consumed — it always falls through to camera handling.
	# Skip mouse button events over GUI so UI elements (asset browser, etc.) still work.
	if _measure_tool and _measure_tool.is_active():
		var is_click: bool = event is InputEventMouseButton and event.pressed
		if is_click and _is_mouse_over_gui():
			pass
		elif _measure_tool.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	# Mouse motion: pan handling (MMB or RMB)
	if event is InputEventMouseMotion:
		if _camera_controller.handle_pan_mouse_motion(event):
			get_viewport().set_input_as_handled()
		return

	if event is InputEventPanGesture:
		InputProfile.notify_trackpad_gesture()
		if _is_mouse_over_gui():
			return
		if drag_and_drop_node and drag_and_drop_node.is_dragging():
			return
		_camera_controller.handle_pan_gesture_zoom(event.delta.y)
		return

	if event is not InputEventMouseButton:
		return

	# Don't process mouse buttons over UI
	if _is_mouse_over_gui():
		_camera_controller.cancel_pan()
		return

	# Middle-mouse button: pan camera
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			InputProfile.notify_middle_click()
			# Don't start panning if the mouse is over a token — let
			# BoardTokenController handle rotation via _unhandled_input.
			if not _camera_controller.is_mouse_over_token(event.position):
				_camera_controller.start_pan(event.position)
		else:
			_camera_controller.stop_pan()
		return

	# Right-mouse button: alternative pan (on empty space, not during measure)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _camera_controller.rmb_can_start_pan(event.position):
				_camera_controller.start_rmb_pan(event.position)
				get_viewport().set_input_as_handled()
				return
		else:
			if _camera_controller.is_rmb_pan_active():
				var was_short_click := _camera_controller.rmb_is_short_click(event.position)
				_camera_controller.stop_rmb_pan()
				if not was_short_click:
					# Consume release so it doesn't trigger context menu
					get_viewport().set_input_as_handled()
				return

	# Don't zoom when scrolling over any UI element (e.g. asset browser list)
	# Don't zoom while dragging - scroll wheel is used for token height adjustment
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		return

	if event.is_action_pressed("camera_zoom_in"):
		_camera_controller.zoom_in_step()
	if event.is_action_pressed("camera_zoom_out"):
		_camera_controller.zoom_out_step()


## Check if a level is currently being loaded
func _is_level_loading() -> bool:
	return _level_play_controller and _level_play_controller.is_loading()


## Check if a text input control currently has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## Forward focus requests to CameraController -- must keep this exact name/signature,
## LevelPlayController connects directly to it:
## token_controller.focus_requested.connect(_game_map.focus_camera_on)
func focus_camera_on(world_position: Vector3) -> void:
	_camera_controller.focus_camera_on(world_position)


## Check if the mouse is currently hovering over any UI control (not the 3D viewport).
## Uses gui_get_hovered_control() for a general check that works with any UI overlay.
func _is_mouse_over_gui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	# The SubViewportContainer is our 3D rendering surface, not a UI element
	if hovered == viewport_container:
		return false
	return true


## Forward a token's context-menu request to TokenContextMenuController.
## Must keep this exact name/signature -- LevelPlayController connects
## directly to it:
## token_controller.context_menu_requested.connect(_game_map._on_token_context_menu_requested)
func _on_token_context_menu_requested(token: BoardToken, menu_position: Vector2) -> void:
	_token_context_menu.open_for_token(token, menu_position)


## Create and configure the MeasureTool.
## The tool lives in the SubViewport for raycasting access, but its 2D overlay
## (lines + label) is parented to GameMap so it renders above the lo-fi shader.
func setup_measure_tool() -> void:
	if _measure_tool:
		return
	_measure_tool = MeasureTool.new()
	_measure_tool.name = "MeasureTool"
	add_child(_measure_tool)
	_measure_tool.setup(camera_node, world_viewport, self)
	_measure_tool.toggled.connect(_on_measure_tool_toggled)
	# MeasureTool doesn't exist yet when CameraController is constructed in
	# _ready() -- wire the reference here instead, once it does, so
	# rmb_can_start_pan() can check whether a measurement is active.
	_camera_controller.set_measure_tool(_measure_tool)


## Return the MeasureTool instance (may be null before setup).
func get_measure_tool() -> MeasureTool:
	return _measure_tool


## Get the action history (for undo recording from external code).
func get_action_history() -> GameplayActionHistory:
	return _action_history


## Disable token dragging while the measure tool is active, re-enable when it's not.
## Also auto-show/hide the grid overlay during measurement.
func _on_measure_tool_toggled(active: bool) -> void:
	if drag_and_drop_node:
		drag_and_drop_node.dragging_enabled = not active
	_grid_visibility.set_auto_show_measure(active)


## Create and configure the GridOverlay.
## Parented to Camera3D inside the SubViewport so it receives the lo-fi effect.
func setup_grid_overlay() -> void:
	if _grid_overlay:
		return
	_grid_overlay = GridOverlay.create(camera_node)
	_visual_effects.load_grid_visual_settings()


## Return the GridOverlay instance (may be null before setup).
func get_grid_overlay() -> GridOverlay:
	return _grid_overlay


## Create and configure the DragRuler.
## Connects to DragAndDrop3D signals for automatic activation during drags.
func setup_drag_ruler() -> void:
	if _drag_ruler:
		return
	_drag_ruler = DragRuler.new()
	_drag_ruler.name = "DragRuler"
	add_child(_drag_ruler)
	_drag_ruler.setup(camera_node, world_viewport, self, drag_and_drop_node)

	# Auto-show/hide grid during drags
	drag_and_drop_node.dragging_started.connect(_grid_visibility._on_drag_started_grid)
	drag_and_drop_node.dragging_stopped.connect(_grid_visibility._on_drag_stopped_grid)
	drag_and_drop_node.dragging_cancelled.connect(_grid_visibility._on_drag_stopped_grid)


## Return the DragRuler instance (may be null before setup).
func get_drag_ruler() -> DragRuler:
	return _drag_ruler


## Create and configure the PerformanceOverlay.
## Toggled by the perf_overlay_toggle action (F3); off by default each session.
func setup_performance_overlay() -> void:
	if _perf_overlay:
		return
	_perf_overlay = PerformanceOverlay.new()
	_perf_overlay.name = "PerformanceOverlay"
	add_child(_perf_overlay)
	_perf_overlay.setup(self)


## Return the PerformanceOverlay instance (may be null before setup).
func get_performance_overlay() -> PerformanceOverlay:
	return _perf_overlay


## Return the currently loaded level's display name, or "unknown" if none is
## loaded. Used by PerformanceOverlay to tag log rows with the active map.
func get_current_map_name() -> String:
	if _level_play_controller and _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.level_name
	return "unknown"


## Debug-only performance diagnostic (F4): show/hide every scattered-foliage
## MultiMeshInstance3D (trees + grass) so the F3 overlay's FPS reading can be
## compared with and without foliage rendering, isolating foliage cost from
## camera zoom/position. Does not persist across a map reload -- a freshly
## loaded map's foliage always starts visible regardless of this flag.
func _toggle_foliage_visibility() -> void:
	_foliage_hidden = not _foliage_hidden
	_set_foliage_visible_recursive(map_container, not _foliage_hidden)


## wind_foliage_category meta is set on tree AND grass MultiMeshInstance3D
## nodes by GlbUtils._build_multimesh_from_transforms (see WindFoliage.classify_category)
## -- untagged MultiMeshInstance3D nodes, if any, are left untouched.
static func _set_foliage_visible_recursive(node: Node, should_be_visible: bool) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D and child.get_meta("wind_foliage_category", "") != "":
			child.visible = should_be_visible
		_set_foliage_visible_recursive(child, should_be_visible)


## Configure grid overlay and drag systems from LevelData.
func configure_grid(level_data: LevelData) -> void:
	_grid_visibility.configure_grid(level_data)


## Reset grid state when a level is cleared.
func reset_grid_state() -> void:
	_grid_visibility.reset_grid_state()


## Enable or disable the lo-fi visual filter
func set_lofi_enabled(enabled: bool) -> void:
	_visual_effects.set_lofi_enabled(enabled)


## Apply grid visual settings from the settings menu.
func apply_grid_visual_settings(
	cell_tint_opacity: float, line_thickness: float, fade_radius: float
) -> void:
	_visual_effects.apply_grid_visual_settings(cell_tint_opacity, line_thickness, fade_radius)


## Enable or disable the occlusion fade effect
func set_occlusion_fade_enabled(enabled: bool) -> void:
	_visual_effects.set_occlusion_fade_enabled(enabled)


## Notify the occlusion fade manager that a new map has been loaded.
## Re-initializes and rebuilds the internal mesh cache so occlusion detection
## works with the new geometry. Also computes camera soft bounds from map AABB.
func notify_map_loaded() -> void:
	_visual_effects.setup_occlusion_fade()

	# Compute camera soft bounds from map geometry and snap the camera into
	# the allowed range immediately so the first user input doesn't jump.
	_camera_controller.notify_map_loaded()


## Clear occlusion fade state. Call before loading a new map.
## The manager will be re-activated when notify_map_loaded() is called.
func notify_map_clearing() -> void:
	if occlusion_fade:
		occlusion_fade.clear()

	# Clean up any in-progress shake so the offset doesn't persist into the next level
	_camera_controller.notify_map_clearing()


## Override lo-fi shader parameters from map data
## Call this after loading a map to apply map-specific visual settings
## Parameters dict can contain any subset of shader parameter names
func apply_lofi_overrides(overrides: Dictionary) -> void:
	_visual_effects.apply_lofi_overrides(overrides)


## Create and attach a WeatherRenderer to the world viewport.
## Called once per level load; subsequent calls are no-ops.
func setup_weather(environment_manager: LevelEnvironmentManager) -> void:
	if _weather_renderer:
		return
	_weather_renderer = WeatherRenderer.new()
	_weather_renderer.name = "WeatherRenderer"
	world_viewport.add_child(_weather_renderer)
	_weather_renderer.setup(camera_node, environment_manager)


## Forward weather override parameters to the active WeatherRenderer.
func apply_weather_overrides(overrides: Dictionary) -> void:
	if _weather_renderer:
		_weather_renderer.apply_weather(overrides)


## Remove all active weather effects and free the renderer.
## A fresh renderer is created on the next setup_weather() call.
func clear_weather() -> void:
	if _weather_renderer:
		_weather_renderer.queue_free()
		_weather_renderer = null
