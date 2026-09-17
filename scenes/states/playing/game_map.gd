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
var _sun_gizmo: SunGizmoTool = null
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
var _debug_render_toggles: DebugRenderToggles = null
var _perf_overlay_container: VBoxContainer = null

@onready var viewport_container: SubViewportContainer = $WorldViewportLayer/SubViewportContainer
@onready var world_viewport: SubViewport = $WorldViewportLayer/SubViewportContainer/SubViewport
@onready
var cameraholder_node: Node3D = $WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder
@onready var camera_node: Camera3D = get_node(
	"WorldViewportLayer/SubViewportContainer/SubViewport/CameraHolder/Camera3D"
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


## Whether [param event] must skip the active modal world tool (sun gizmo,
## measure tool) in _input() and be left for the GUI.
##
## A mouse button landing on a UI control belongs to that control -- the release
## every bit as much as the press. Godot's Slider clears its drag grab only when
## its own gui_input() sees the button-up (scene/gui/slider.cpp), so a release
## consumed out here leaves the slider tracking the pointer with the button up,
## until something else happens to drop the viewport's mouse focus. That was the
## Visuals drawer's stuck sliders while Aim Sun was on.
##
## [param tool_is_dragging] is the one exception: a drag that began out on the
## 3D view owns the whole gesture and still needs its release, even if the
## pointer has since crossed over a panel.
static func should_bypass_world_tool(
	event: InputEvent, over_gui: bool, tool_is_dragging: bool
) -> bool:
	if event is not InputEventMouseButton:
		return false
	return over_gui and not tool_is_dragging


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
				if _debug_render_toggles:
					_debug_render_toggles.set_panel_visible(_perf_overlay.is_visible_overlay())
				get_viewport().set_input_as_handled()
				return

			# 1..9 flip the first nine DebugRenderToggles switches in panel order, and 0
			# flips the tenth, but ONLY while the perf overlay (F3) is open -- so these
			# digits stay free during normal play and the shortcut is live only when the
			# panel it mirrors is on screen. Deliberately unmodified rather than
			# Shift+digit: a bare digit is the fastest thing to hit while watching the
			# overlay, and gating on the overlay already keeps it out of the way the rest
			# of the time. (The validation bridge's _inject_key() does parse chords such
			# as "Shift+1", so a modifier combo would be drivable -- that is no longer the
			# reason.) See DebugRenderToggles.toggle_by_index() for why a keyboard path is
			# needed.
			if (
				event.keycode >= KEY_1
				and event.keycode <= KEY_9
				and _debug_render_toggles
				and _perf_overlay
				and _perf_overlay.is_visible_overlay()
			):
				_debug_render_toggles.toggle_by_index(event.keycode - KEY_1)
				get_viewport().set_input_as_handled()
				return

			if (
				event.keycode == KEY_0
				and _debug_render_toggles
				and _perf_overlay
				and _perf_overlay.is_visible_overlay()
			):
				_debug_render_toggles.toggle_by_index(9)
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

	# Sun gizmo gets first look at input when active, ahead of the measure tool
	# (the two are mutually exclusive, so at most one is ever active). Skip
	# mouse buttons over GUI so the edit drawer's own controls still work.
	if _sun_gizmo and _sun_gizmo.is_active():
		if should_bypass_world_tool(event, _is_mouse_over_gui(), _sun_gizmo.is_dragging()):
			pass
		elif _sun_gizmo.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	# Measure tool gets first look at input when active.
	# handle_input returns true if the event was consumed (clicks on terrain, etc.).
	# Mouse motion is never consumed — it always falls through to camera handling.
	# Skip mouse button events over GUI so UI elements (asset browser, etc.) still work.
	# The tool has no cross-GUI drag of its own, so it never claims a release.
	if _measure_tool and _measure_tool.is_active():
		if should_bypass_world_tool(event, _is_mouse_over_gui(), false):
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


## Public wrapper around _is_mouse_over_gui() for external callers (e.g.
## DragPlaceController) that need the same GUI-hover check but aren't part
## of this class.
func is_mouse_over_gui() -> bool:
	return _is_mouse_over_gui()


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


## Create the sun-aiming gizmo. Mirrors setup_measure_tool(): the tool doesn't
## exist when CameraController is constructed in _ready(), so the reference is
## wired here instead.
func setup_sun_gizmo() -> void:
	if _sun_gizmo:
		return
	_sun_gizmo = SunGizmoTool.new()
	_sun_gizmo.name = "SunGizmoTool"
	add_child(_sun_gizmo)
	_sun_gizmo.setup(camera_node, world_viewport, self)
	_sun_gizmo.toggled.connect(_on_sun_gizmo_toggled)
	_camera_controller.set_sun_gizmo(_sun_gizmo)


## Return the SunGizmoTool instance (may be null before setup).
func get_sun_gizmo() -> SunGizmoTool:
	return _sun_gizmo


## Suppress token dragging while the sun gizmo is active, re-enable when it's not.
## Uses _update_dragging_enabled() rather than `not active` directly -- see that
## function's doc comment for why.
func _on_sun_gizmo_toggled(active: bool) -> void:
	_update_dragging_enabled()
	# Mutual exclusion between the two modal tools lives here, in the node that
	# owns both, so neither tool needs to know the other exists. No recursion:
	# deactivate() emits toggled(false), which fails this `active` guard.
	if active and _measure_tool and _measure_tool.is_active():
		_measure_tool.deactivate()


## Get the action history (for undo recording from external code).
func get_action_history() -> GameplayActionHistory:
	return _action_history


## Suppress token dragging while the measure tool is active, re-enable when
## it's not. Also auto-show/hide the grid overlay during measurement.
func _on_measure_tool_toggled(active: bool) -> void:
	_update_dragging_enabled()
	_grid_visibility.set_auto_show_measure(active)
	if active and _sun_gizmo and _sun_gizmo.is_active():
		_sun_gizmo.deactivate()


## Token dragging is suppressed while either modal map tool is active.
##
## Derived from both tools rather than from the toggling tool's own `active`
## argument: switching tools deactivates the other one synchronously, so a
## handler writing `not active` from its own perspective gets overwritten by the
## other handler's callback and leaves dragging enabled mid-aim.
func _update_dragging_enabled() -> void:
	if not drag_and_drop_node:
		return
	var tool_active: bool = (
		(_measure_tool != null and _measure_tool.is_active())
		or (_sun_gizmo != null and _sun_gizmo.is_active())
	)
	drag_and_drop_node.dragging_enabled = not tool_active


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


## Return the level play controller this GameMap was set up with (see
## setup()), or null before setup() runs. Lets other code (e.g. SettingsMenu)
## reach it through the same GameMap lookup they already use, instead of
## re-implementing GameMap's own scene-tree search a second time.
func get_level_play_controller() -> LevelPlayController:
	return _level_play_controller


## Create and configure DebugRenderToggles (the F3 overlay's checkbox panel:
## foliage visibility and per-category (tree/grass/map) shadow toggles).
## Replaces the old undiscoverable F4 foliage-visibility hotkey outright.
func setup_debug_render_toggles() -> void:
	if _debug_render_toggles:
		return
	_debug_render_toggles = DebugRenderToggles.new()
	_debug_render_toggles.name = "DebugRenderToggles"
	add_child(_debug_render_toggles)
	_debug_render_toggles.setup(self)


## Return the DebugRenderToggles instance (may be null before setup).
func get_debug_render_toggles() -> DebugRenderToggles:
	return _debug_render_toggles


## Shared top-left VBoxContainer (on Constants.LAYER_PERF_OVERLAY) that PerformanceOverlay's
## metrics panel and DebugRenderToggles' checkbox panel both add themselves to, so the two
## stack automatically as either one's content grows or shrinks -- avoids the two panels
## needing a hardcoded Y offset between them that silently goes stale (and overlaps) whenever
## a line/checkbox is added to either. Created lazily since either consumer may call this
## first depending on setup order.
func get_perf_overlay_container() -> VBoxContainer:
	if not _perf_overlay_container:
		var canvas_layer := CanvasLayer.new()
		canvas_layer.layer = Constants.LAYER_PERF_OVERLAY
		add_child(canvas_layer)

		_perf_overlay_container = VBoxContainer.new()
		_perf_overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_perf_overlay_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_perf_overlay_container.position = Vector2(16, 16)
		_perf_overlay_container.add_theme_constant_override("separation", 8)
		canvas_layer.add_child(_perf_overlay_container)
	return _perf_overlay_container


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


## Apply the player's foliage density setting to the loaded map. Called by the settings
## menu when the slider moves, and at map load. Returns nothing: the load-time caller owns
## whether to tell the player, because only it knows this is a fresh map rather than a
## slider nudge.
func apply_foliage_density(budget: int) -> void:
	if map_container:
		FoliageDensityController.apply(map_container, budget)


## Enable or disable the occlusion fade effect
func set_occlusion_fade_enabled(enabled: bool) -> void:
	_visual_effects.set_occlusion_fade_enabled(enabled)


## Set the foliage antialiasing level (a Viewport.MSAA enum value) from the settings menu.
func set_foliage_antialiasing_level(level: int) -> void:
	_visual_effects.set_foliage_antialiasing_level(level)


## Notify the occlusion fade manager that a new map has been loaded.
## Re-initializes and rebuilds the internal mesh cache so occlusion detection
## works with the new geometry. Also computes camera soft bounds from map AABB.
func notify_map_loaded() -> void:
	_visual_effects.setup_occlusion_fade()
	_visual_effects.apply_foliage_antialiasing()

	# Compute camera soft bounds from map geometry and snap the camera into
	# the allowed range immediately so the first user input doesn't jump.
	_camera_controller.notify_map_loaded()

	# Re-collect foliage/mesh references against the new map and reset every
	# toggle to its default -- the previous map's nodes are gone, and no toggle
	# persists across a map switch.
	if _debug_render_toggles:
		_debug_render_toggles.refresh()


## Clear occlusion fade state. Call before loading a new map.
## The manager will be re-activated when notify_map_loaded() is called.
func notify_map_clearing() -> void:
	_visual_effects.clear_occlusion_fade()

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


## Let the weather renderer re-add its fog on top of a freshly applied environment.
func rebase_weather_fog() -> void:
	if _weather_renderer:
		_weather_renderer.rebase_fog()


## Remove all active weather effects and free the renderer.
## A fresh renderer is created on the next setup_weather() call.
func clear_weather() -> void:
	if _weather_renderer:
		_weather_renderer.queue_free()
		_weather_renderer = null
