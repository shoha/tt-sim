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

# RMB pan thresholds (short-click vs. drag detection)
const RMB_PAN_CLICK_THRESHOLD_MS: int = 150  # Max ms for a short-click (not a drag)
const RMB_PAN_MOVE_THRESHOLD_PX: float = 5.0  # Min movement to count as drag

# Camera soft bounds / near-plane safety margin
const MAP_BOUNDS_MARGIN_FACTOR := 0.15  # Extra margin as fraction of map size on each side
const NEAR_PLANE_GROUND_MARGIN := 0.5  # Keep bottom-corner ray origins at least this far above Y=0

# Camera shake
const SHAKE_MAX_INTENSITY := 0.05  # Max shake offset in world units
const SHAKE_DURATION := 0.15  # Duration of shake effect

const EDGE_PAN_SMOOTH_SPEED: float = 8.0  # Smoothing rate for edge panning ramp-up/coast-out
const TOKEN_COLLISION_LAYER: int = 2  # Physics layer for tokens (layer 1 = terrain)
const REFERENCE_ASPECT := 16.0 / 9.0  # Reference window aspect ratio for frustum consistency

@export var move_speed: float = 10.0
@export var move_accel_speed: float = 15.0  # Smoothing rate for camera move accel/decel
@export var zoom_step: float = 1.5  # How much each scroll tick changes the target zoom
@export var zoom_smooth_speed: float = 12.0  # Smoothing rate for zoom interpolation
@export var pan_gesture_zoom_factor: float = 0.05
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

var _camera_move_dir: Vector3
var _camera_velocity: Vector3 = Vector3.ZERO  # Smoothed camera movement velocity
var _iso_vertical_comp: float = 1.0  # Foreshortening compensation for screen-vertical panning
var _target_zoom: float = 0.0  # Target zoom level (smoothly interpolated toward)
var _current_edge_pan: Vector2 = Vector2.ZERO  # Smoothed edge pan direction
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

# Pan state (middle-mouse and RMB alternative)
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _last_mouse_position: Vector2 = Vector2.ZERO  # Tracked for zoom-toward-cursor
var _rmb_pan_active: bool = false  # True when RMB is being used for panning
var _rmb_press_time: int = 0  # Timestamp (msec) of RMB press for short-click detection
var _rmb_press_pos: Vector2 = Vector2.ZERO  # Screen position of RMB press

# Camera home position (stored on level load for reset)
var _home_position: Vector3 = Vector3.ZERO
var _home_zoom: float = 0.0
var _reset_tween: Tween = null

# Camera offset scaling (prevents near-plane culling at large zoom/narrow aspect)
var _base_camera_offset: Vector3  # Camera3D local position at base zoom (from scene)
var _base_camera_size: float  # Camera3D orthographic size at base zoom (from scene)

# Camera soft bounds (computed from map geometry)
var _map_bounds: AABB = AABB()
var _has_map_bounds: bool = false

# Camera shake state
var _shake_tween: Tween = null
var _shake_offset: Vector3 = Vector3.ZERO

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


## Return the camera size needed to show at least as much horizontal world space
## as a 16:9 window at the given height. On 16:9 or wider viewports the height
## is returned unchanged; on narrower viewports it is scaled up so that
## size * actual_aspect == height * reference_aspect (same visible width).
static func compute_aspect_corrected_size(
	height: float, vp_size: Vector2i, reference_aspect: float
) -> float:
	if vp_size.y == 0 or vp_size.x == 0:
		return height
	var actual_aspect := float(vp_size.x) / float(vp_size.y)
	if actual_aspect >= reference_aspect:
		return height
	return height * reference_aspect / actual_aspect


## Return the aspect-corrected camera size for the current viewport.
func _corrected_size(height: float) -> float:
	return GameMap.compute_aspect_corrected_size(height, world_viewport.size, REFERENCE_ASPECT)


## Scale the Camera3D local position so that all screen-corner ray origins
## stay above Y=0. For an orthographic camera, translating along the view
## direction has zero visual effect but keeps the near plane ahead of all
## visible ground geometry, preventing culling at any zoom or aspect ratio.
func _update_camera_offset() -> void:
	# Baseline: proportional scaling preserves the original camera geometry
	var offset_scale := camera_node.size / _base_camera_size
	camera_node.position = _base_camera_offset * offset_scale

	# The bottom screen corners have the lowest ray-origin Y because the
	# camera's right axis tilts downward.  On wide or zoomed-out viewports
	# this can push the ray origin below Y=0, causing near-plane culling.
	# Check the actual ray origins and add exactly enough extra offset.
	var vp_size := world_viewport.size
	if vp_size.x > 0 and vp_size.y > 0:
		var bl := camera_node.project_ray_origin(Vector2(0, vp_size.y))
		var br := camera_node.project_ray_origin(Vector2(vp_size.x, vp_size.y))
		var min_y := minf(bl.y, br.y)
		if min_y < NEAR_PLANE_GROUND_MARGIN:
			var deficit := NEAR_PLANE_GROUND_MARGIN - min_y
			offset_scale += deficit / _base_camera_offset.y
			camera_node.position = _base_camera_offset * offset_scale


func _ready() -> void:
	_action_history = GameplayActionHistory.new()
	_action_history.name = "GameplayActionHistory"
	add_child(_action_history)
	_setup_viewport()
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
	# Capture the scene-default camera offset and size before any modification.
	# These are the reference values for proportional offset scaling.
	_base_camera_offset = camera_node.position
	_base_camera_size = camera_node.size
	# Isometric foreshortening: the camera's elevation angle compresses vertical
	# screen movement by sin(elevation).  Compensate by 1/sin = hypotenuse/opposite.
	_iso_vertical_comp = _base_camera_offset.length() / _base_camera_offset.y
	# Initialize target zoom from the camera's current size (reference 16:9 height)
	_target_zoom = camera_node.size
	# Apply aspect correction immediately using the actual window size.
	# world_viewport.size may still hold the scene default at this point,
	# so get_window().size gives the real pixel dimensions.
	camera_node.size = GameMap.compute_aspect_corrected_size(
		_target_zoom, get_window().size, REFERENCE_ASPECT
	)
	_update_camera_offset()
	# Seed mouse position so first scroll-to-zoom targets the cursor, not (0,0)
	_last_mouse_position = get_viewport().get_mouse_position()


## Setup with a reference to the level play controller
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller
	_drag_place.setup(self, Callable(_level_play_controller, "spawn_asset"))

	# Store home camera position for reset (Home key).
	# Use _target_zoom (reference height) not camera_node.size (may be aspect-corrected).
	_home_position = cameraholder_node.global_position
	_home_zoom = _target_zoom

	# Pass the controller to the gameplay menu
	if gameplay_menu:
		var menu_controller = gameplay_menu.get_node_or_null("GameplayMenu")
		if menu_controller and menu_controller.has_method("setup"):
			menu_controller.setup(level_play_controller)
			if menu_controller.has_signal("drag_place_started"):
				menu_controller.drag_place_started.connect(_drag_place._on_drag_place_started)


func _process(delta: float) -> void:
	# Don't process camera movement while a level is loading
	if _is_level_loading():
		return
	handle_movement(delta)
	handle_zoom(delta)
	_handle_edge_pan(delta)


func handle_movement(delta: float) -> void:
	# Compensate for isometric foreshortening: scale the screen-vertical
	# component of the movement direction so W/S feels the same as A/D.
	var screen_v_axis := Vector3(-1.0, 0.0, -1.0).normalized()
	var v_component := _camera_move_dir.dot(screen_v_axis)
	var compensated_dir := (
		_camera_move_dir + screen_v_axis * v_component * (_iso_vertical_comp - 1.0)
	)

	# Smoothly accelerate toward target velocity and decelerate when keys released
	var target_velocity = compensated_dir * move_speed
	var smooth_factor = 1.0 - exp(-move_accel_speed * delta)
	_camera_velocity = _camera_velocity.lerp(target_velocity, smooth_factor)

	# Only translate if velocity is meaningful (avoid micro-drift)
	if _camera_velocity.length_squared() > 0.001:
		cameraholder_node.translate(_camera_velocity * delta)
		_clamp_camera_to_bounds()


func handle_zoom(delta: float) -> void:
	# Zoom toward cursor: capture world point under cursor before size change,
	# interpolate size, then recapture and correct camera position.
	# Compute aspect-corrected target: on narrower-than-16:9 viewports, camera.size is
	# scaled up so the visible world width matches the reference 16:9 horizontal extent.
	var corrected_target := _corrected_size(_target_zoom)
	var zooming := absf(camera_node.size - corrected_target) > 0.001

	# Skip zoom-toward-cursor when a reset/focus tween is animating the camera position,
	# because the tween would overwrite our correction each frame causing wobble.
	var tween_active := _reset_tween and _reset_tween.is_valid() and _reset_tween.is_running()

	var world_before: Vector3
	if zooming and not tween_active:
		world_before = camera_node.project_position(_last_mouse_position, 0)

	# Smoothly interpolate camera size toward corrected target
	var smooth_factor = 1.0 - exp(-zoom_smooth_speed * delta)
	camera_node.size = lerpf(camera_node.size, corrected_target, smooth_factor)

	# Correct camera position so the point under the cursor stays fixed
	if zooming and not tween_active:
		var world_after = camera_node.project_position(_last_mouse_position, 0)
		cameraholder_node.global_position += world_before - world_after
		_clamp_camera_to_bounds()

	# Scale camera offset to match current size — no visual effect for orthographic,
	# but keeps the near plane ahead of all visible ground geometry.
	_update_camera_offset()

	# Update tilt-shift DoF from logical zoom (_target_zoom, independent of aspect correction)
	var zoom_percentage: float = (_target_zoom - min_zoom) / (max_zoom - min_zoom)
	tiltshift_node.mesh.material.set_shader_parameter(&"DoF", 5 * zoom_percentage)


func _input(event: InputEvent) -> void:
	# Use _input instead of _unhandled_input because events going through
	# SubViewportContainer may not reach _unhandled_input on this node.
	if _is_level_loading():
		return

	# Always track mouse position for zoom-toward-cursor, even during measurement
	if event is InputEventMouseMotion:
		_last_mouse_position = event.position

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
		if _is_panning:
			_handle_pan_motion(event)
			if _rmb_pan_active:
				get_viewport().set_input_as_handled()
		return

	if event is InputEventPanGesture:
		InputProfile.notify_trackpad_gesture()
		if _is_mouse_over_gui():
			return
		if drag_and_drop_node and drag_and_drop_node.is_dragging():
			return
		if event.delta.y < 0:
			_target_zoom = clampf(
				_target_zoom - zoom_step * pan_gesture_zoom_factor, min_zoom, max_zoom
			)
		if event.delta.y > 0:
			_target_zoom = clampf(
				_target_zoom + zoom_step * pan_gesture_zoom_factor, min_zoom, max_zoom
			)
		return

	if event is not InputEventMouseButton:
		return

	# Don't process mouse buttons over UI
	if _is_mouse_over_gui():
		_is_panning = false
		_rmb_pan_active = false
		return

	# Middle-mouse button: pan camera
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			InputProfile.notify_middle_click()
			# Don't start panning if the mouse is over a token — let
			# BoardTokenController handle rotation via _unhandled_input.
			if not _is_mouse_over_token(event.position):
				_is_panning = true
				_pan_start_mouse = event.position
		else:
			_is_panning = false
		return

	# Right-mouse button: alternative pan (on empty space, not during measure)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _rmb_can_start_pan(event.position):
				_rmb_press_time = Time.get_ticks_msec()
				_rmb_press_pos = event.position
				_rmb_pan_active = true
				_is_panning = true
				_pan_start_mouse = event.position
				get_viewport().set_input_as_handled()
				return
		else:
			if _rmb_pan_active:
				var was_short_click := _rmb_is_short_click(event.position)
				_rmb_pan_active = false
				_is_panning = false
				if not was_short_click:
					# Consume release so it doesn't trigger context menu
					get_viewport().set_input_as_handled()
				return

	# Don't zoom when scrolling over any UI element (e.g. asset browser list)
	# Don't zoom while dragging - scroll wheel is used for token height adjustment
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		return

	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
	if event.is_action_pressed("camera_zoom_out"):
		_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)


func _unhandled_key_input(event: InputEvent) -> void:
	# Don't process camera input while a level is loading
	if _is_level_loading():
		return

	# Don't process camera input if a text input has focus
	if _is_text_input_focused():
		return

	# Camera reset (Home key) - tween back to initial position and zoom
	if event.is_action_pressed("camera_reset"):
		_reset_camera_to_home()
		return

	var input_dir := _camera_move_dir

	if event.is_action_released("camera_move_forward"):
		input_dir.x += 1
		input_dir.z += 1
	if event.is_action_released("camera_move_backward"):
		input_dir.x -= 1
		input_dir.z -= 1
	if event.is_action_released("camera_move_left"):
		input_dir.x += 1
		input_dir.z -= 1
	if event.is_action_released("camera_move_right"):
		input_dir.x -= 1
		input_dir.z += 1

	if event.is_action_pressed("camera_move_forward"):
		input_dir.x -= 1
		input_dir.z -= 1
	if event.is_action_pressed("camera_move_backward"):
		input_dir.x += 1
		input_dir.z += 1
	if event.is_action_pressed("camera_move_left"):
		input_dir.x -= 1
		input_dir.z += 1
	if event.is_action_pressed("camera_move_right"):
		input_dir.x += 1
		input_dir.z -= 1

	input_dir.y = 0
	_camera_move_dir = input_dir


## Check if a level is currently being loaded
func _is_level_loading() -> bool:
	return _level_play_controller and _level_play_controller.is_loading()


## Check if a text input control currently has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## Apply a subtle camera shake effect. Intensity is clamped to SHAKE_MAX_INTENSITY.
## Used for token drop feedback — larger tokens produce more shake.
func camera_shake(intensity: float, duration: float = SHAKE_DURATION) -> void:
	intensity = clampf(intensity, 0.0, SHAKE_MAX_INTENSITY)
	if intensity < 0.001:
		return

	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		# Remove old offset before starting new shake
		cameraholder_node.global_position -= _shake_offset
		_shake_offset = Vector3.ZERO

	_shake_tween = create_tween()
	var steps := 4
	var step_duration := duration / steps
	for i in range(steps):
		var t := float(i) / steps
		var decay := 1.0 - t  # Linear decay
		var offset := Vector3(
			randf_range(-intensity, intensity) * decay,
			0,
			randf_range(-intensity, intensity) * decay,
		)
		_shake_tween.tween_callback(_apply_shake_offset.bind(offset))
		_shake_tween.tween_interval(step_duration)
	# Final step: reset to zero offset
	_shake_tween.tween_callback(_apply_shake_offset.bind(Vector3.ZERO))


func _apply_shake_offset(new_offset: Vector3) -> void:
	cameraholder_node.global_position -= _shake_offset
	_shake_offset = new_offset
	cameraholder_node.global_position += _shake_offset


## Smoothly center the camera on a world position.
## Used by double-click-to-focus on tokens. Camera position is purely local.
func focus_camera_on(world_position: Vector3) -> void:
	# Keep the Y component of the camera holder unchanged (only pan XZ)
	var target_pos := Vector3(
		world_position.x, cameraholder_node.global_position.y, world_position.z
	)
	# Clamp target to map bounds so the tween doesn't overshoot
	target_pos = _clamp_position_to_bounds(target_pos)
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = create_tween()
	(
		_reset_tween
		. tween_property(cameraholder_node, "global_position", target_pos, 0.3)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


## Reset camera to the home position and zoom stored on level load.
## Position is tweened; zoom is set on _target_zoom and interpolated by handle_zoom().
func _reset_camera_to_home() -> void:
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	# Let handle_zoom() smoothly interpolate size toward home zoom.
	# Don't tween camera_node.size directly — that would fight with handle_zoom().
	_target_zoom = _home_zoom
	var target_pos := _clamp_position_to_bounds(_home_position)
	_reset_tween = create_tween()
	_reset_tween.set_ease(Tween.EASE_OUT)
	_reset_tween.set_trans(Tween.TRANS_CUBIC)
	_reset_tween.tween_property(cameraholder_node, "global_position", target_pos, 0.3)


## Handle mouse motion during middle-mouse pan.
## Uses project_position to convert screen delta to world-space camera movement.
## Works correctly for orthographic cameras regardless of angle.
func _handle_pan_motion(event: InputEventMouseMotion) -> void:
	if not camera_node:
		return
	# Convert old and new screen positions to world positions at depth 0.
	# For orthographic cameras the depth doesn't matter — the delta is the same.
	var world_from = camera_node.project_position(_pan_start_mouse, 0)
	var world_to = camera_node.project_position(event.position, 0)
	# Move camera opposite to the mouse drag direction (drag right → view moves right)
	cameraholder_node.global_position -= (world_to - world_from)
	_pan_start_mouse = event.position
	_clamp_camera_to_bounds()


## Check if the mouse position is over a token by raycasting against the token
## collision layer. Returns true if a token rigid body is under the cursor.
func _is_mouse_over_token(screen_pos: Vector2) -> bool:
	if not camera_node or not world_viewport:
		return false
	var world: World3D = world_viewport.find_world_3d()
	if not world:
		return false
	var from = camera_node.project_ray_origin(screen_pos)
	var to = from + camera_node.project_ray_normal(screen_pos) * 100.0
	var space_state = world.direct_space_state
	if not space_state:
		return false
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = TOKEN_COLLISION_LAYER
	var hit = space_state.intersect_ray(query)
	return not hit.is_empty()


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


## Whether RMB can start a pan at this screen position.
## Requires: not over a token, not over GUI, measure tool not active, not dragging.
func _rmb_can_start_pan(screen_pos: Vector2) -> bool:
	if _measure_tool and _measure_tool.is_active():
		return false
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		return false
	if _is_mouse_over_token(screen_pos):
		return false
	return true


## Check if an RMB release qualifies as a short click (not a pan gesture).
func _rmb_is_short_click(release_pos: Vector2) -> bool:
	var elapsed := Time.get_ticks_msec() - _rmb_press_time
	var distance := release_pos.distance_to(_rmb_press_pos)
	return elapsed < RMB_PAN_CLICK_THRESHOLD_MS and distance < RMB_PAN_MOVE_THRESHOLD_PX


## Forward a token's context-menu request to TokenContextMenuController.
## Must keep this exact name/signature -- LevelPlayController connects
## directly to it:
## token_controller.context_menu_requested.connect(_game_map._on_token_context_menu_requested)
func _on_token_context_menu_requested(token: BoardToken, menu_position: Vector2) -> void:
	_token_context_menu.open_for_token(token, menu_position)


## Setup the SubViewport for proper rendering
## With SubViewportContainer.stretch = true, viewport size is managed automatically
func _setup_viewport() -> void:
	# React to viewport resizes (e.g. window resize) so aspect correction stays current
	world_viewport.size_changed.connect(_on_viewport_size_changed)


## Snap camera.size to the aspect-corrected value when the SubViewport is resized
## (triggered by window resize via SubViewportContainer.stretch = true).
## Snapping immediately prevents handle_zoom() from treating the ratio change as
## a user-initiated zoom-toward-cursor operation.
func _on_viewport_size_changed() -> void:
	if not is_instance_valid(camera_node):
		return
	camera_node.size = _corrected_size(_target_zoom)
	_update_camera_offset()


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
	_compute_map_bounds()
	_clamp_camera_to_bounds()


## Clear occlusion fade state. Call before loading a new map.
## The manager will be re-activated when notify_map_loaded() is called.
func notify_map_clearing() -> void:
	if occlusion_fade:
		occlusion_fade.clear()
	_has_map_bounds = false

	# Clean up any in-progress shake so the offset doesn't persist into the next level
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if _shake_offset != Vector3.ZERO:
		cameraholder_node.global_position -= _shake_offset
		_shake_offset = Vector3.ZERO


## Handle camera edge-panning when dragging a token near screen edges.
## Reads the edge_pan_direction from DragAndDrop3D and smoothly interpolates
## to provide a gentle ramp-up entering the zone and coast-out when leaving.
func _handle_edge_pan(delta: float) -> void:
	# Determine raw target pan direction (zero if not dragging)
	var target_pan = Vector2.ZERO
	if drag_and_drop_node and drag_and_drop_node.is_dragging():
		target_pan = drag_and_drop_node.edge_pan_direction

	# Smoothly interpolate toward the target pan direction
	var smooth_factor = 1.0 - exp(-EDGE_PAN_SMOOTH_SPEED * delta)
	_current_edge_pan = _current_edge_pan.lerp(target_pan, smooth_factor)

	# Only translate if pan is meaningful
	if _current_edge_pan.length_squared() < 0.0001:
		_current_edge_pan = Vector2.ZERO
		return

	# Convert screen-space pan direction to isometric camera movement.
	# Same coordinate mapping as keyboard: up=(-1,-1), down=(+1,+1), left=(-1,+1), right=(+1,-1).
	# Vertical component scaled by foreshortening compensation to match keyboard panning.
	var vert := _current_edge_pan.y * _iso_vertical_comp
	var cam_move = Vector3.ZERO
	cam_move.x = _current_edge_pan.x + vert
	cam_move.z = -_current_edge_pan.x + vert

	var pan_speed = drag_and_drop_node.edge_pan_speed if drag_and_drop_node else 4.0
	cameraholder_node.translate(cam_move * pan_speed * delta)
	_clamp_camera_to_bounds()


## Compute the bounding box of all mesh geometry in the map container.
## Used for camera soft bounds to prevent panning into the void.
func _compute_map_bounds() -> void:
	if not map_container:
		_has_map_bounds = false
		return

	var mesh_aabbs: Array[AABB] = []
	_collect_mesh_aabbs(map_container, mesh_aabbs)

	if mesh_aabbs.is_empty():
		_has_map_bounds = false
		return

	var bounds: AABB = mesh_aabbs[0]
	for i in range(1, mesh_aabbs.size()):
		bounds = bounds.merge(mesh_aabbs[i])

	_map_bounds = bounds
	_has_map_bounds = true


## Recursively collect world-space AABBs from all MeshInstance3D children.
func _collect_mesh_aabbs(node: Node, out: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh:
		out.append(node.global_transform * node.mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, out)


## Compute the XZ offset from the camera holder to the ground-level view center.
## The isometric camera is positioned at a large local offset from the holder
## and looks downward at an angle, so the point on the ground that the screen
## center maps to is NOT at the holder's XZ position.
func _get_view_center_ground_offset() -> Vector2:
	var vp_size := world_viewport.size
	var screen_center := Vector2(vp_size.x * 0.5, vp_size.y * 0.5)
	var origin := camera_node.project_ray_origin(screen_center)
	var dir := camera_node.project_ray_normal(screen_center)
	if absf(dir.y) < 0.001:
		return Vector2.ZERO
	var t := -origin.y / dir.y
	var ground := origin + dir * t
	var holder := cameraholder_node.global_position
	return Vector2(ground.x - holder.x, ground.z - holder.z)


## Return a position clamped so the view center stays within the map bounds
## plus margin. The view center is the screen center projected to Y=0 — it
## differs from the holder position due to the isometric camera offset.
## This prevents infinite panning while preserving natural padding around
## the map. When the map is very small, the view centers on it.
func _clamp_position_to_bounds(pos: Vector3) -> Vector3:
	if not _has_map_bounds:
		return pos
	if not is_instance_valid(camera_node) or not is_instance_valid(world_viewport):
		return pos

	var view_off := _get_view_center_ground_offset()

	var margin_x := _map_bounds.size.x * MAP_BOUNDS_MARGIN_FACTOR
	var margin_z := _map_bounds.size.z * MAP_BOUNDS_MARGIN_FACTOR
	var map_min_x := _map_bounds.position.x - margin_x
	var map_max_x := _map_bounds.position.x + _map_bounds.size.x + margin_x
	var map_min_z := _map_bounds.position.z - margin_z
	var map_max_z := _map_bounds.position.z + _map_bounds.size.z + margin_z

	var vc_x := pos.x + view_off.x
	var vc_z := pos.z + view_off.y

	if map_min_x >= map_max_x:
		vc_x = _map_bounds.position.x + _map_bounds.size.x * 0.5
	else:
		vc_x = clampf(vc_x, map_min_x, map_max_x)

	if map_min_z >= map_max_z:
		vc_z = _map_bounds.position.z + _map_bounds.size.z * 0.5
	else:
		vc_z = clampf(vc_z, map_min_z, map_max_z)

	pos.x = vc_x - view_off.x
	pos.z = vc_z - view_off.y
	return pos


## Clamp the camera position to the map bounds (soft limits).
## Called after any camera translation to prevent panning into the void.
func _clamp_camera_to_bounds() -> void:
	cameraholder_node.global_position = _clamp_position_to_bounds(cameraholder_node.global_position)


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
