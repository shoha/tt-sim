class_name CameraController
extends Node

## Handles camera movement, zoom, panning (middle-mouse and right-mouse drag),
## edge-panning during token drags, camera shake feedback, soft-bounds
## clamping to the map's geometry, aspect-ratio correction for
## narrower-than-16:9 viewports, and the Home-key camera reset / focus-on-token
## tweens.
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (camera_node,
## world_viewport, cameraholder_node, tiltshift_node, map_container,
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
## handle_input() pattern).
##
## MeasureTool doesn't exist yet when this controller is constructed in
## GameMap._ready() (it's created later by GameMap.setup_measure_tool()), so
## the reference used by rmb_can_start_pan() is wired in separately via
## set_measure_tool(), called at the end of setup_measure_tool().

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

var _game_map: GameMap = null
var _measure_tool: MeasureTool = null

var _camera_move_dir: Vector3
var _camera_velocity: Vector3 = Vector3.ZERO  # Smoothed camera movement velocity
var _iso_vertical_comp: float = 1.0  # Foreshortening compensation for screen-vertical panning
var _target_zoom: float = 0.0  # Target zoom level (smoothly interpolated toward)
var _current_edge_pan: Vector2 = Vector2.ZERO  # Smoothed edge pan direction

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


## Wire this controller to its owning GameMap and perform initial camera setup:
## capture the scene-default offset/size, apply aspect correction for the
## current window size, and start listening for viewport resizes.
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	var camera_node := game_map.camera_node

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
	camera_node.size = compute_aspect_corrected_size(
		_target_zoom, get_window().size, REFERENCE_ASPECT
	)
	_update_camera_offset()
	# Seed mouse position so first scroll-to-zoom targets the cursor, not (0,0)
	_last_mouse_position = get_viewport().get_mouse_position()
	# React to viewport resizes (e.g. window resize) so aspect correction stays current
	game_map.world_viewport.size_changed.connect(_on_viewport_size_changed)


## Store the current camera position/zoom as "home" for the Home-key reset.
## Called by GameMap.setup() once the level play controller is wired up.
func capture_home_position() -> void:
	_home_position = _game_map.cameraholder_node.global_position
	_home_zoom = _target_zoom


## Wire the MeasureTool reference used by rmb_can_start_pan() to suppress RMB
## pan while a measurement is active. MeasureTool doesn't exist yet when this
## controller is constructed, so GameMap calls this at the end of its
## setup_measure_tool() instead of passing it in via setup().
func set_measure_tool(measure_tool: MeasureTool) -> void:
	_measure_tool = measure_tool


func _process(delta: float) -> void:
	# Don't process camera movement while a level is loading
	if _game_map._is_level_loading():
		return
	handle_movement(delta)
	handle_zoom(delta)
	_handle_edge_pan(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	# Don't process camera input while a level is loading
	if _game_map._is_level_loading():
		return

	# Don't process camera input if a text input has focus
	if _game_map._is_text_input_focused():
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
	if vp_size.y == 0 or vp_size.x == 0:
		return height
	var actual_aspect := float(vp_size.x) / float(vp_size.y)
	if actual_aspect >= reference_aspect:
		return height
	return height * reference_aspect / actual_aspect


## Return the aspect-corrected camera size for the current viewport.
func _corrected_size(height: float) -> float:
	return compute_aspect_corrected_size(height, _game_map.world_viewport.size, REFERENCE_ASPECT)


## Scale the Camera3D local position so that all screen-corner ray origins
## stay above Y=0. For an orthographic camera, translating along the view
## direction has zero visual effect but keeps the near plane ahead of all
## visible ground geometry, preventing culling at any zoom or aspect ratio.
func _update_camera_offset() -> void:
	var camera_node := _game_map.camera_node
	# Baseline: proportional scaling preserves the original camera geometry
	var offset_scale := camera_node.size / _base_camera_size
	camera_node.position = _base_camera_offset * offset_scale

	# The bottom screen corners have the lowest ray-origin Y because the
	# camera's right axis tilts downward.  On wide or zoomed-out viewports
	# this can push the ray origin below Y=0, causing near-plane culling.
	# Check the actual ray origins and add exactly enough extra offset.
	var vp_size := _game_map.world_viewport.size
	if vp_size.x > 0 and vp_size.y > 0:
		var bl := camera_node.project_ray_origin(Vector2(0, vp_size.y))
		var br := camera_node.project_ray_origin(Vector2(vp_size.x, vp_size.y))
		var min_y := minf(bl.y, br.y)
		if min_y < NEAR_PLANE_GROUND_MARGIN:
			var deficit := NEAR_PLANE_GROUND_MARGIN - min_y
			offset_scale += deficit / _base_camera_offset.y
			camera_node.position = _base_camera_offset * offset_scale


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
		_game_map.cameraholder_node.translate(_camera_velocity * delta)
		_clamp_camera_to_bounds()


func handle_zoom(delta: float) -> void:
	var camera_node := _game_map.camera_node
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
		_game_map.cameraholder_node.global_position += world_before - world_after
		_clamp_camera_to_bounds()

	# Scale camera offset to match current size — no visual effect for orthographic,
	# but keeps the near plane ahead of all visible ground geometry.
	_update_camera_offset()

	# Update tilt-shift DoF from logical zoom (_target_zoom, independent of aspect correction)
	var zoom_percentage: float = (_target_zoom - min_zoom) / (max_zoom - min_zoom)
	_game_map.tiltshift_node.mesh.material.set_shader_parameter(&"DoF", 5 * zoom_percentage)


## Record the latest mouse position (tracked every frame, even during
## measurement) so zoom-toward-cursor always targets the current cursor.
func record_mouse_position(screen_pos: Vector2) -> void:
	_last_mouse_position = screen_pos


## Whether panning is currently active (middle-mouse or RMB).
func is_panning() -> bool:
	return _is_panning


## Whether the active pan (if any) was started via RMB.
func is_rmb_pan_active() -> bool:
	return _rmb_pan_active


## Start a pan gesture (middle-mouse) from the given screen position.
func start_pan(screen_pos: Vector2) -> void:
	_is_panning = true
	_pan_start_mouse = screen_pos


## Stop the current pan (middle-mouse release).
func stop_pan() -> void:
	_is_panning = false


## Start an RMB pan, recording the press time/position for short-click detection.
func start_rmb_pan(screen_pos: Vector2) -> void:
	_rmb_press_time = Time.get_ticks_msec()
	_rmb_press_pos = screen_pos
	_rmb_pan_active = true
	_is_panning = true
	_pan_start_mouse = screen_pos


## Stop an RMB pan (release).
func stop_rmb_pan() -> void:
	_rmb_pan_active = false
	_is_panning = false


## Cancel any in-progress pan immediately (e.g. mouse moved over GUI).
func cancel_pan() -> void:
	_is_panning = false
	_rmb_pan_active = false


## Handle mouse motion while a pan may be active. Returns true if the
## viewport's input should be marked as handled (RMB-driven pan).
func handle_pan_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _is_panning:
		return false
	_handle_pan_motion(event)
	return _rmb_pan_active


## Adjust the target zoom by a raw delta, clamped to [min_zoom, max_zoom].
func adjust_zoom(delta: float) -> void:
	_target_zoom = clampf(_target_zoom + delta, min_zoom, max_zoom)


## Apply a trackpad pan-gesture zoom step (scaled by pan_gesture_zoom_factor).
func handle_pan_gesture_zoom(delta_y: float) -> void:
	if delta_y < 0:
		adjust_zoom(-zoom_step * pan_gesture_zoom_factor)
	elif delta_y > 0:
		adjust_zoom(zoom_step * pan_gesture_zoom_factor)


## Zoom in one scroll-wheel step.
func zoom_in_step() -> void:
	adjust_zoom(-zoom_step)


## Zoom out one scroll-wheel step.
func zoom_out_step() -> void:
	adjust_zoom(zoom_step)


## Apply a subtle camera shake effect. Intensity is clamped to SHAKE_MAX_INTENSITY.
## Used for token drop feedback — larger tokens produce more shake.
func camera_shake(intensity: float, duration: float = SHAKE_DURATION) -> void:
	intensity = clampf(intensity, 0.0, SHAKE_MAX_INTENSITY)
	if intensity < 0.001:
		return

	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		# Remove old offset before starting new shake
		_game_map.cameraholder_node.global_position -= _shake_offset
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
	_game_map.cameraholder_node.global_position -= _shake_offset
	_shake_offset = new_offset
	_game_map.cameraholder_node.global_position += _shake_offset


## Smoothly center the camera on a world position.
## Used by double-click-to-focus on tokens. Camera position is purely local.
func focus_camera_on(world_position: Vector3) -> void:
	# Keep the Y component of the camera holder unchanged (only pan XZ)
	var target_pos := Vector3(
		world_position.x, _game_map.cameraholder_node.global_position.y, world_position.z
	)
	# Clamp target to map bounds so the tween doesn't overshoot
	target_pos = _clamp_position_to_bounds(target_pos)
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	_reset_tween = create_tween()
	(
		_reset_tween
		. tween_property(_game_map.cameraholder_node, "global_position", target_pos, 0.3)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


## Reset camera to the home position and zoom stored on level load.
## Position is tweened; zoom is set on _target_zoom and interpolated by handle_zoom().
func _reset_camera_to_home() -> void:
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	# Let handle_zoom() smoothly interpolate size toward home zoom.
	# Don't tween camera size directly — that would fight with handle_zoom().
	_target_zoom = _home_zoom
	var target_pos := _clamp_position_to_bounds(_home_position)
	_reset_tween = create_tween()
	_reset_tween.set_ease(Tween.EASE_OUT)
	_reset_tween.set_trans(Tween.TRANS_CUBIC)
	_reset_tween.tween_property(_game_map.cameraholder_node, "global_position", target_pos, 0.3)


## Handle mouse motion during middle-mouse pan.
## Uses project_position to convert screen delta to world-space camera movement.
## Works correctly for orthographic cameras regardless of angle.
func _handle_pan_motion(event: InputEventMouseMotion) -> void:
	var camera_node := _game_map.camera_node
	if not camera_node:
		return
	# Convert old and new screen positions to world positions at depth 0.
	# For orthographic cameras the depth doesn't matter — the delta is the same.
	var world_from = camera_node.project_position(_pan_start_mouse, 0)
	var world_to = camera_node.project_position(event.position, 0)
	# Move camera opposite to the mouse drag direction (drag right → view moves right)
	_game_map.cameraholder_node.global_position -= (world_to - world_from)
	_pan_start_mouse = event.position
	_clamp_camera_to_bounds()


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
	var to = from + camera_node.project_ray_normal(screen_pos) * 100.0
	var space_state = world.direct_space_state
	if not space_state:
		return false
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = TOKEN_COLLISION_LAYER
	var hit = space_state.intersect_ray(query)
	return not hit.is_empty()


## Whether RMB can start a pan at this screen position.
## Requires: not over a token, not over GUI, measure tool not active, not dragging.
func rmb_can_start_pan(screen_pos: Vector2) -> bool:
	if _measure_tool and _measure_tool.is_active():
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


## Snap camera.size to the aspect-corrected value when the SubViewport is resized
## (triggered by window resize via SubViewportContainer.stretch = true).
## Snapping immediately prevents handle_zoom() from treating the ratio change as
## a user-initiated zoom-toward-cursor operation.
func _on_viewport_size_changed() -> void:
	var camera_node := _game_map.camera_node
	if not is_instance_valid(camera_node):
		return
	camera_node.size = _corrected_size(_target_zoom)
	_update_camera_offset()


## Compute camera soft bounds from map geometry and snap the camera into
## range immediately. Called after a new map finishes loading.
func notify_map_loaded() -> void:
	_compute_map_bounds()
	_clamp_camera_to_bounds()


## Reset soft-bounds and shake state. Call before loading a new map so stale
## state from the previous level doesn't leak into the next one.
func notify_map_clearing() -> void:
	_has_map_bounds = false
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if _shake_offset != Vector3.ZERO:
		_game_map.cameraholder_node.global_position -= _shake_offset
		_shake_offset = Vector3.ZERO


## Handle camera edge-panning when dragging a token near screen edges.
## Reads the edge_pan_direction from DragAndDrop3D and smoothly interpolates
## to provide a gentle ramp-up entering the zone and coast-out when leaving.
func _handle_edge_pan(delta: float) -> void:
	var drag_and_drop_node := _game_map.drag_and_drop_node
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
	_game_map.cameraholder_node.translate(cam_move * pan_speed * delta)
	_clamp_camera_to_bounds()


## Compute the bounding box of all mesh geometry in the map container.
## Used for camera soft bounds to prevent panning into the void.
func _compute_map_bounds() -> void:
	var map_container := _game_map.map_container
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
	var world_viewport := _game_map.world_viewport
	var camera_node := _game_map.camera_node
	var vp_size := world_viewport.size
	var screen_center := Vector2(vp_size.x * 0.5, vp_size.y * 0.5)
	var origin := camera_node.project_ray_origin(screen_center)
	var dir := camera_node.project_ray_normal(screen_center)
	if absf(dir.y) < 0.001:
		return Vector2.ZERO
	var t := -origin.y / dir.y
	var ground := origin + dir * t
	var holder := _game_map.cameraholder_node.global_position
	return Vector2(ground.x - holder.x, ground.z - holder.z)


## Return a position clamped so the view center stays within the map bounds
## plus margin. The view center is the screen center projected to Y=0 — it
## differs from the holder position due to the isometric camera offset.
## This prevents infinite panning while preserving natural padding around
## the map. When the map is very small, the view centers on it.
func _clamp_position_to_bounds(pos: Vector3) -> Vector3:
	if not _has_map_bounds:
		return pos
	if (
		not is_instance_valid(_game_map.camera_node)
		or not is_instance_valid(_game_map.world_viewport)
	):
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
	var holder := _game_map.cameraholder_node
	holder.global_position = _clamp_position_to_bounds(holder.global_position)
