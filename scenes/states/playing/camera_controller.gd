class_name CameraController
extends Node

## Owns the camera rig and routes input to the active view mode. The single Camera3D and its
## CameraHolder, the yaw and pitch state (CameraView), camera shake, the on-screen compass, the
## tool wiring that decides whether RMB may pan, and the Home / turn / top-down keys live here;
## everything that depends on how the picture is made (the projection, pan, zoom, the pan bounds,
## the near plane, edge pan, WASD) is a ViewMode behind a small interface. OrbitView is the shipped
## one (orthographic, today's behaviour unchanged); a second mode is swapped in with
## set_view_mode() and needs no edit to the orbit file (card streetseam, 2026-11-02).
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (camera_node,
## world_viewport, cameraholder_node, map_container,
## drag_and_drop_node) directly from the injected GameMap reference at call
## time, since these nodes live inside the SubViewport and are shared with
## other sub-components.
##
## Implements its own _process() and _unhandled_key_input() (mirrors
## GridVisibilityController's automatic _process() dispatch) since neither
## interleaves with any other GameMap-owned concern. The _input()-driven
## camera behavior (pan, scroll zoom, pan-gesture zoom) instead exposes plain
## methods that GameMap._input() calls explicitly in place, because that
## method's dispatch order across drag-place/measure-tool/camera concerns is
## order-sensitive and must stay owned by GameMap (mirrors DragPlaceController's
## handle_input() pattern); each forwards to the active view.
##
## MeasureTool doesn't exist yet when this controller is constructed in
## GameMap._ready() (it's created later by GameMap.setup_measure_tool()), so
## the reference used by rmb_can_start_pan() is wired in separately via
## set_measure_tool(), called at the end of setup_measure_tool().
##
## The view turns in 90 degree snaps (CameraRig, CameraYaw): the CameraHolder's yaw eases over
## about 0.35 s about the ground point under the screen centre, and the holder carries it, so
## its local pan axes (WASD, edge pan) keep W away from the viewer. Keys: CameraRig.key_turn;
## the on-screen CameraCompass always. Local to each player (nothing synced); the sun stays put
## in the world. The yaw is applied in _process, before CanopyFade publishes the camera's axis.
## The pitch (CameraPitch; 21.6 degrees home to straight down) tilts the camera child the same way,
## by Alt + left drag, O (top-down toggle) or the compass; CameraView owns both orientations.
##
## The underscore names near the end (_target_zoom, _update_camera_offset, ...) are the old private
## surface that tests and render-job probes reach with call / get / set; they forward to the orbit
## view and can go when those callers move to the view's own names.

## Emitted when a turn (or Home) has landed on its yaw; MapViewFit refits for the new basis.
signal view_turned(yaw_deg: float)
## Emitted whenever the pitch (or an orbit's yaw) moved the view's basis, every frame it moves.
signal view_tilted(pitch_deg: float)

# RMB pan thresholds (short-click vs. drag detection)
const RMB_PAN_CLICK_THRESHOLD_MS: int = 150  # Max ms for a short-click (not a drag)
const RMB_PAN_MOVE_THRESHOLD_PX: float = 5.0  # Min movement to count as drag

## The near plane is pulled back until the bottom corners' ray origins stand this far above
## the highest ground, over the tallest canopy (palette trees reach 16 m; margin for Blender
## maps' taller ones): see OrbitView.update_camera_offset.
const CANOPY_CLEARANCE := 24.0

# Camera shake
const SHAKE_MAX_INTENSITY := 0.05  # Max shake offset in world units
const SHAKE_DURATION := 0.15  # Duration of shake effect

const TOKEN_COLLISION_LAYER: int = 2  # Physics layer for tokens (layer 1 = terrain)
const REFERENCE_ASPECT := 16.0 / 9.0  # Reference window aspect ratio for frustum consistency

## World height of the highest ground the near plane must stay above: 0 for Blender maps
## (unchanged behaviour), the terrain's top for an authored map (set_ground_top).
var ground_top_y: float = 0.0
## The on-screen compass and tilt handle, or null before setup().
var compass: CameraCompass = null
## The eye-level view (always there, active or not); set_view_mode(eye) or F9 makes it active.
var eye: EyeView = EyeView.new()
## What a shake has added to the holder's position right now (read-only to others: a view that
## rewrites the holder every frame, the eye, adds it on top).
var shake_offset: Vector3 = Vector3.ZERO

## The orbit view's zoom range (the 16:9 reference height of the camera's size).
var min_zoom: float:
	get:
		return _orbit.min_zoom
	set(value):
		_orbit.min_zoom = value
var max_zoom: float:
	get:
		return _orbit.max_zoom
	set(value):
		_orbit.max_zoom = value

var _game_map: GameMap = null
var _measure_tool: MeasureTool = null
var _sun_gizmo: SunGizmoTool = null
var _brush_tool: BrushTool = null

var _orbit: OrbitView = OrbitView.new()
var _active: ViewMode = null  # the view mode in charge: _orbit, or the one set_view_mode gave

# RMB press (short-click vs. drag detection); the pan itself is the active view's
var _rmb_press_time: int = 0  # Timestamp (msec) of RMB press for short-click detection
var _rmb_press_pos: Vector2 = Vector2.ZERO  # Screen position of RMB press

# Camera shake state
var _shake_tween: Tween = null

# The view's yaw, pitch and orbit (CameraView; CameraRig has the maths); made in setup()
var _view: CameraView = null

# Old private names forwarding to the orbit view (see the class header)
var _target_zoom: float:
	get:
		return _orbit.target_zoom
	set(value):
		_orbit.target_zoom = value
var _home_zoom: float:
	get:
		return _orbit.home_zoom
var _camera_velocity: Vector3:
	get:
		return _orbit.camera_velocity
	set(value):
		_orbit.camera_velocity = value
var _camera_move_dir: Vector3:
	get:
		return _orbit.camera_move_dir
	set(value):
		_orbit.camera_move_dir = value
var _current_edge_pan: Vector2:
	get:
		return _orbit.current_edge_pan
	set(value):
		_orbit.current_edge_pan = value
var _base_camera_offset: Vector3:
	get:
		return _orbit.base_camera_offset
var _fit_size: float:
	get:
		return _orbit.fit_size
	set(value):
		_orbit.fit_size = value
var _map_bounds: AABB:
	get:
		return _orbit.map_bounds
var _last_mouse_position: Vector2:
	set(value):
		_orbit.last_mouse_position = value


## Wire this controller to its owning GameMap and perform initial camera setup: the orbit view
## captures the scene-default offset/size and applies aspect correction for the current window
## size, and the controller starts listening for viewport resizes.
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	set_view_mode(_orbit)
	# React to viewport resizes (e.g. window resize) so aspect correction stays current
	game_map.world_viewport.size_changed.connect(_on_viewport_size_changed)
	_view = CameraView.new(self, game_map)
	TokenMarkers.attach(game_map.world_viewport, game_map.camera_node, game_map.is_mouse_over_gui)
	compass = CameraCompass.attach(self)
	compass.turn_requested.connect(turn_view)
	compass.tilt_requested.connect(_view.tilt_by)
	compass.top_down_requested.connect(_toggle_top_down)


## The view mode in charge of the camera now (OrbitView unless set_view_mode gave another).
func view_mode() -> ViewMode:
	return _active


## The orthographic orbit view (always there, active or not).
func orbit_view() -> OrbitView:
	return _orbit


## Make `mode` the active view mode: the current one is deactivated (an Alt + drag orbit ends, held
## keys, pans and glides stop) and `mode` takes over the Camera3D. Null or the active mode: no-op.
func set_view_mode(mode: ViewMode) -> void:
	if mode == null or mode == _active:
		return
	if _view != null and _view.orbiting:
		_view.end_orbit()
	if _active != null:
		_active.deactivate()
	_active = mode
	_active.activate(self, _game_map)


## Store the current camera position/zoom as "home" for the Home-key reset.
## Called by GameMap.setup() once the level play controller is wired up.
func capture_home_position() -> void:
	_active.capture_home()


## The view's yaw as drawn now (CameraRig: 45 is home, a snap is 90), unwrapped mid-turn.
func current_yaw() -> float:
	return _view.yaw.yaw


## The view's pitch as drawn now, degrees above the ground (CameraRig: 21.6 home, 90 top-down).
func current_pitch() -> float:
	return _view.pitch.pitch


## Whether an eased turn or tilt, or an Alt + drag orbit, is running.
func is_turning() -> bool:
	return _view.is_moving()


## Whether an authoring brush is out, so Q / E are its footprint turn and the view turns on
## Alt+Q / Alt+E (CameraRig.key_turn).
func brush_owns_turn_keys() -> bool:
	return _brush_tool != null and _brush_tool.is_active()


## Turn the view one snap, +1 clockwise on the compass (E) and -1 the other way (Q). Presses
## made while a turn runs add up: the next snap is taken from the one being eased to.
func turn_view(direction: int) -> void:
	set_yaw_target(CameraRig.snap_target(_view.yaw.target, direction))


## Ease the view to the yaw `yaw_deg` about the ground point under the screen centre.
func set_yaw_target(yaw_deg: float) -> void:
	_view.set_yaw_target(yaw_deg)


## Put the view at the yaw `yaw_deg` at once, about the same ground point (render jobs, tests).
func set_yaw_now(yaw_deg: float) -> void:
	_view.set_yaw_now(yaw_deg)


## Put the view at the pitch `pitch_deg` at once, about the same ground point (render jobs, tests).
func set_pitch_now(pitch_deg: float) -> void:
	_view.set_pitch_now(pitch_deg)


## The view's orientation: its eased tilts (CameraView.set_pitch_target, toggle_top_down,
## tilt_by) and the Alt + drag orbit.
func view() -> CameraView:
	return _view


## Route a mouse event to the Alt + left drag orbit (GameMap._input, ahead of every tool): true
## when it is the orbit's. `over_gui` is whether the pointer is over the UI; a token, brush or tool
## drag in progress owns the mouse and the orbit does not begin.
func handle_orbit_input(event: InputEvent, over_gui: bool) -> bool:
	return _view.handle_orbit_input(event, over_gui, _another_drag_owns_mouse())


func _another_drag_owns_mouse() -> bool:
	var dnd := _game_map.drag_and_drop_node
	var token_drag: bool = dnd != null and dnd.is_dragging()
	var brush_drag: bool = _brush_tool != null and _brush_tool.is_dragging()
	return token_drag or brush_drag or (_sun_gizmo != null and _sun_gizmo.is_dragging())


## Wire the MeasureTool reference used by rmb_can_start_pan() to suppress RMB
## pan while a measurement is active. MeasureTool doesn't exist yet when this
## controller is constructed, so GameMap calls this at the end of its
## setup_measure_tool() instead of passing it in via setup().
func set_measure_tool(measure_tool: MeasureTool) -> void:
	_measure_tool = measure_tool


## Wire the SunGizmoTool reference used by rmb_can_start_pan() to suppress RMB
## pan while the gizmo is active -- the gizmo uses RMB to exit, so a pan must not
## start on the same press. Wired by GameMap.setup_sun_gizmo() for the same
## construction-order reason as set_measure_tool().
func set_sun_gizmo(sun_gizmo: SunGizmoTool) -> void:
	_sun_gizmo = sun_gizmo


## Wire authoring's BrushTool for rmb_can_start_pan(): RMB cancels a stroke or deselects
## the brush, so a pan must not start on the same press. Wired by GameMap.setup_brush_tool().
func set_brush_tool(brush_tool: BrushTool) -> void:
	_brush_tool = brush_tool


func _process(delta: float) -> void:
	# Don't process camera movement while a level is loading
	if _game_map._is_level_loading():
		return
	PerformanceMonitor.start_timer(&"perf/camera_update_ms")
	_view.advance(delta)
	compass.sync_keys(brush_owns_turn_keys())
	_active.process(delta)
	PerformanceMonitor.stop_timer(&"perf/camera_update_ms")


func _notification(what: int) -> void:
	# The window lost focus mid-drag: the button release will never arrive.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _view != null and _view.orbiting:
		_view.end_orbit()


func _unhandled_key_input(event: InputEvent) -> void:
	# Don't process camera input while a level is loading
	if _game_map._is_level_loading():
		return

	# Don't process camera input if a text input has focus
	if _game_map._is_text_input_focused():
		return

	# Camera reset (Home key) - tween back to initial position, zoom and yaw
	if event.is_action_pressed("camera_reset"):
		_reset_camera_to_home()
		return

	# F9: step into the eye view and back (debug key)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		set_view_mode(_orbit if _active == eye else eye)
		get_viewport().set_input_as_handled()
		return

	# Turn the view: Q / E, `[` / `]`, or Alt+Q / Alt+E under a brush (CameraRig.key_turn)
	var turn := CameraRig.event_turn(event, brush_owns_turn_keys())
	if turn != 0:
		turn_view(turn)
		get_viewport().set_input_as_handled()
		return
	if CameraRig.is_top_down_key(event):
		_toggle_top_down()
		get_viewport().set_input_as_handled()
		return

	# Everything else (WASD) is the active view's
	if _active.handle_input(event):
		get_viewport().set_input_as_handled()


## Return the camera size needed to show at least as much horizontal world space
## as a 16:9 window at the given height. On 16:9 or wider viewports the height
## is returned unchanged; on narrower viewports it is scaled up so that
## size * actual_aspect == height * reference_aspect (same visible width).
##
## Kept callable as GameMap.compute_aspect_corrected_size(...) via a thin
## static forward on GameMap -- test_camera_aspect_correction.gd depends on
## that exact call form.
static func compute_aspect_corrected_size(
	height: float, vp_size: Vector2i, reference_aspect: float
) -> float:
	return OrbitView.aspect_corrected_size(height, vp_size, reference_aspect)


## The highest ground on the map (world Y), so the near plane stays above raised terrain at
## the bottom of the screen (see OrbitView.update_camera_offset). Blender maps never call this and
## keep 0; an authored map passes its terrain's top, and authoring keeps it current while
## the ground is sculpted. Tells the active view at once when it changed.
func set_ground_top(y: float) -> void:
	if is_equal_approx(y, ground_top_y):
		return
	ground_top_y = y
	if is_instance_valid(_game_map) and is_instance_valid(_game_map.camera_node):
		_active.ground_top_changed()


## How far (metres along the view axis) to pull the near plane back so that a ray origin at
## height `bottom_origin_y` on it rises to `floor_y`, for a back axis rising `back_y` per
## metre. 0 when it is already there. Pure (OrbitView.near_plane_hold).
static func near_plane_hold(bottom_origin_y: float, floor_y: float, back_y: float) -> float:
	return OrbitView.near_plane_hold(bottom_origin_y, floor_y, back_y)


## Whether the camera has stopped moving on its own: no turn, tilt or Home wait, no shake tween,
## and the active view's own motion (the orbit zoom eased onto its target within handle_zoom's own
## 0.001, no home or focus tween, no key, edge or mouse pan). Render jobs wait on it before a
## capture (the `settle` op).
func is_at_rest() -> bool:
	if is_turning() or _view.is_waiting_to_glide():
		return false
	if _shake_tween != null and _shake_tween.is_valid() and _shake_tween.is_running():
		return false
	return _active.is_at_rest()


## Ends the zoom ease exactly on its target. The ease stops anywhere within 0.001 of it,
## depending on the frame times it ran at, so a view taken after it is only repeatable run
## to run once snapped (the render-job `settle` op calls this when the camera is at rest).
func finish_zoom() -> void:
	_active.finish_zoom()


## Puts the ground point `at` (map X and Z in metres) at the middle of the screen with the
## orthographic zoom `zoom`, at once, the zoom ease ended on its target: the camera a
## biome thumbnail is taken from (ThumbnailShot), the same every run.
func frame_ground(at: Vector2, zoom: float) -> void:
	_active.frame_ground(at, zoom)


## Record the latest mouse position (tracked every frame, even during
## measurement) so zoom-toward-cursor always targets the current cursor.
func record_mouse_position(screen_pos: Vector2) -> void:
	_active.record_mouse(screen_pos)


## Whether the active pan (if any) was started via RMB.
func is_rmb_pan_active() -> bool:
	return _active.is_rmb_pan_active()


## Start a pan gesture (middle-mouse) from the given screen position.
func start_pan(screen_pos: Vector2) -> void:
	_active.pan_begin(screen_pos, false)


## Stop the current pan (middle-mouse release).
func stop_pan() -> void:
	_active.pan_end(false)


## Start an RMB pan, recording the press time/position for short-click detection.
func start_rmb_pan(screen_pos: Vector2) -> void:
	_rmb_press_time = Time.get_ticks_msec()
	_rmb_press_pos = screen_pos
	_active.pan_begin(screen_pos, true)


## Stop an RMB pan (release).
func stop_rmb_pan() -> void:
	_active.pan_end(true)


## Cancel any in-progress pan immediately (e.g. mouse moved over GUI).
func cancel_pan() -> void:
	_active.pan_cancel()


## A left button press or release nothing else took: the active view's own gesture (the eye view
## grabs the ground with it). True when the event must be marked handled.
func handle_primary_button(event: InputEventMouseButton) -> bool:
	return _active.primary_button(event)


## Handle mouse motion while a pan may be active. Returns true if the
## viewport's input should be marked as handled (RMB-driven pan).
func handle_pan_mouse_motion(event: InputEventMouseMotion) -> bool:
	return _active.pan_motion(event)


## Adjust the target zoom by a raw delta, clamped to the active view's zoom range.
func adjust_zoom(delta: float) -> void:
	_active.zoom_by(delta)


## Replace the zoom range and pull the current target into it. The exported 2..20 holds until
## a map is fit; MapViewFit (play and authoring alike) raises the upper limit so a whole map
## fits.
func set_zoom_limits(low: float, high: float) -> void:
	# The orbit view keeps up while another mode is in charge, so it returns with a current range.
	_orbit.set_zoom_limits(low, high)
	if _active != _orbit:
		_active.set_zoom_limits(low, high)


## The orthographic size at which a map fits a camera with rotation `basis` (OrbitView, pure):
## the larger of the view height the content spans and the view width it spans divided by
## `aspect`. See OrbitView.fit_size_for_extent.
static func fit_size_for_extent(
	basis: Basis,
	extent_m: Vector2,
	height_m: float,
	aspect: float = REFERENCE_ASPECT,
	floor_m: float = 0.0
) -> float:
	return OrbitView.fit_size_for_extent(basis, extent_m, height_m, aspect, floor_m)


## Apply a trackpad pan-gesture zoom step (scaled by the view's gesture factor).
func handle_pan_gesture_zoom(delta_y: float) -> void:
	_active.zoom_gesture(delta_y)


## Zoom in one scroll-wheel step.
func zoom_in_step() -> void:
	_active.zoom_notch(-1)


## Zoom out one scroll-wheel step.
func zoom_out_step() -> void:
	_active.zoom_notch(1)


## Apply a subtle camera shake effect. Intensity is clamped to SHAKE_MAX_INTENSITY.
## Used for token drop feedback — larger tokens produce more shake.
func camera_shake(intensity: float, duration: float = SHAKE_DURATION) -> void:
	intensity = clampf(intensity, 0.0, SHAKE_MAX_INTENSITY)
	if intensity < 0.001:
		return

	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		# Remove old offset before starting new shake
		_game_map.cameraholder_node.global_position -= shake_offset
		shake_offset = Vector3.ZERO

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
	_game_map.cameraholder_node.global_position -= shake_offset
	shake_offset = new_offset
	_game_map.cameraholder_node.global_position += shake_offset


## Smoothly center the camera on a world position.
## Used by double-click-to-focus on tokens. Camera position is purely local.
func focus_camera_on(world_position: Vector3) -> void:
	_active.focus_on(world_position)


## Reset camera to the home position and zoom stored on level load (the active view's Home).
func _reset_camera_to_home() -> void:
	_active.reset_home()


## Check if the mouse position is over a token by raycasting against the token
## collision layer. Returns true if a token rigid body is under the cursor.
func is_mouse_over_token(screen_pos: Vector2) -> bool:
	var camera_node := _game_map.camera_node
	var world_viewport := _game_map.world_viewport
	if not camera_node or not world_viewport:
		return false
	var world: World3D = world_viewport.find_world_3d()
	if not world:
		return false
	var from = camera_node.project_ray_origin(screen_pos)
	# Rays start on the near plane, which stands well behind the camera (see
	# OrbitView's near-plane hold), so this must reach past it to the far ground.
	var to = from + camera_node.project_ray_normal(screen_pos) * 1000.0
	var space_state = world.direct_space_state
	if not space_state:
		return false
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = TOKEN_COLLISION_LAYER
	var hit = space_state.intersect_ray(query)
	return not hit.is_empty()


## Whether RMB can start a pan at this screen position.
## Requires: not over a token, not over GUI, measure tool and sun gizmo both
## inactive, not dragging.
func rmb_can_start_pan(screen_pos: Vector2) -> bool:
	if _measure_tool and _measure_tool.is_active():
		return false
	if _sun_gizmo and _sun_gizmo.is_active():
		return false
	if _brush_tool and _brush_tool.is_active():
		return false
	if _game_map.drag_and_drop_node and _game_map.drag_and_drop_node.is_dragging():
		return false
	if is_mouse_over_token(screen_pos):
		return false
	return true


## Check if an RMB release qualifies as a short click (not a pan gesture).
func rmb_is_short_click(release_pos: Vector2) -> bool:
	var elapsed := Time.get_ticks_msec() - _rmb_press_time
	var distance := release_pos.distance_to(_rmb_press_pos)
	return elapsed < RMB_PAN_CLICK_THRESHOLD_MS and distance < RMB_PAN_MOVE_THRESHOLD_PX


## The window was resized: the active view re-fits its zoom and placement.
func _on_viewport_size_changed() -> void:
	_active.viewport_resized()


## Compute camera soft bounds from map geometry and snap the camera into
## range immediately. Called after a new map finishes loading.
func notify_map_loaded() -> void:
	_active.map_loaded()


## Use `bounds` (world space) as the map's extent for pan clamping instead of the mesh walk
## notify_map_loaded() does, and snap the camera into range. Authoring gives the document's
## extent, which is the map whatever has been painted on it so far.
func set_map_bounds(bounds: AABB) -> void:
	_active.set_map_bounds(bounds)


## O (and the compass's top-down button): from the eye, leave it for the orbit view first (which
## restores the orbit pose), then toggle top-down there.
func _toggle_top_down() -> void:
	if _active == eye:
		set_view_mode(_orbit)
	_view.toggle_top_down()


## How far the pan range has narrowed toward the map centre (OrbitView, pure), 0 (full range) to
## 1 (the view centre is the map centre), at camera size `size` for a map that fits at `fit_size`.
static func recentre_weight(size: float, fit_size: float) -> float:
	return OrbitView.recentre_weight(size, fit_size)


## Reset soft-bounds and shake state. Call before loading a new map so stale
## state from the previous level doesn't leak into the next one.
func notify_map_clearing() -> void:
	_orbit.map_clearing()
	if _active != _orbit:
		_active.map_clearing()
	ground_top_y = 0.0
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if shake_offset != Vector3.ZERO:
		_game_map.cameraholder_node.global_position -= shake_offset
		shake_offset = Vector3.ZERO


# Old private names (see the class header): each forwards to the orbit view.


func _get_view_center_ground_offset() -> Vector2:
	return _active.view_center_offset()


func _update_camera_offset() -> void:
	_active.update_camera_offset()


func _clamp_camera_to_bounds() -> void:
	_active.clamp_to_bounds()


func _corrected_size(height: float) -> float:
	return _orbit.corrected_size(height)


func _bottom_ray_origin_y(vp_size: Vector2) -> float:
	return _orbit.bottom_ray_origin_y(vp_size)


func _handle_edge_pan(delta: float) -> void:
	_orbit.handle_edge_pan(delta)


func _fit_size_for_bounds(bounds: AABB) -> float:
	return _orbit.fit_size_for_bounds(bounds)
