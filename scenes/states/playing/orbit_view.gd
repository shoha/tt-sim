class_name OrbitView
extends ViewMode

## The shipped view: an orthographic camera looking down at the map from a fixed distance, the
## pivot (the ground point under the screen centre) kept where it is through every turn and tilt.
## Everything that depends on the projection being orthographic lives here: pan by screen delta
## (depth independent), zoom as the camera's `size` toward the cursor, the soft pan bounds on the
## ground-level view centre, the Camera3D offset that scales with `size`, the near plane pulled
## back over the canopies, and the keys and edge pan in the holder's turned frame.
##
## CameraController owns one and forwards to it; CameraView (yaw and pitch) reaches it through the
## controller. Moved out of CameraController unchanged (card streetseam, 2026-11-02): see
## docs/CONVENTIONS.md "Camera System" for the model.

## Extra margin as a fraction of the map size on each side of the pan bounds.
const MAP_BOUNDS_MARGIN_FACTOR := 0.15
## Keep bottom-corner ray origins at least this far above the highest ground (ground_top_y).
const NEAR_PLANE_GROUND_MARGIN := 0.5
## Zoomed out past this fraction of the size at which the whole map fits, the pan range
## narrows toward the map centre, reaching it at that size (recentre_weight()), so a full
## zoom-out frames the map instead of wherever zoom-toward-cursor left the view.
const RECENTRE_START := 0.6
## Smoothing rate for the edge pan's ramp-up and coast-out.
const EDGE_PAN_SMOOTH_SPEED: float = 8.0

var move_speed: float = 10.0
var move_accel_speed: float = 15.0  # Smoothing rate for camera move accel/decel
var zoom_step: float = 1.5  # How much each scroll tick changes the target zoom
var zoom_smooth_speed: float = 12.0  # Smoothing rate for zoom interpolation
var pan_gesture_zoom_factor: float = 0.05
var min_zoom: float = 2.0
var max_zoom: float = 20.0

var camera_move_dir: Vector3 = Vector3.ZERO
var camera_velocity: Vector3 = Vector3.ZERO  # Smoothed camera movement velocity
var target_zoom: float = 0.0  # Target zoom level (smoothly interpolated toward)
var current_edge_pan: Vector2 = Vector2.ZERO  # Smoothed edge pan direction
var last_mouse_position: Vector2 = Vector2.ZERO  # Tracked for zoom-toward-cursor

# Camera home position (stored on level load for reset)
var home_position: Vector3 = Vector3.ZERO
var home_zoom: float = 0.0
var reset_tween: Tween = null

# Camera offset scaling (prevents near-plane culling at large zoom/narrow aspect)
var base_camera_offset: Vector3  # Camera3D local position at base zoom (from scene)
var base_camera_size: float  # Camera3D orthographic size at base zoom (from scene)
var base_camera_near: float = 0.001  # Camera3D near from the scene (the placement's reference)

# Camera soft bounds (computed from map geometry)
var map_bounds: AABB = AABB()
var has_map_bounds: bool = false
# Reference (16:9) size at which map_bounds fits the view; INF when unknown.
var fit_size: float = INF

var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _rmb_pan_active: bool = false  # True when RMB is being used for panning
var _initialised: bool = false
var _home_basis: Basis = Basis.IDENTITY  # the camera's local pose in the scene
var _home_offset: Vector3 = Vector3.ZERO
var _right: Vector3 = Vector3.RIGHT  # the camera's horizontal right axis, local to the holder


func mode_name() -> StringName:
	return &"orbit"


## The first activation captures the scene's own camera (offset, size, near, pose) as the
## reference everything scales from; a later one puts the camera back in the orthographic pose.
func activate(owner_controller: CameraController, map: GameMap) -> void:
	super.activate(owner_controller, map)
	var camera_node := map.camera_node
	if _initialised:
		camera_node.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_node.size = corrected_size(target_zoom)
		apply_pitch(controller.current_pitch())
		return
	_initialised = true
	# Capture the scene-default camera offset and size before any modification.
	# These are the reference values for proportional offset scaling.
	base_camera_offset = camera_node.position
	base_camera_size = camera_node.size
	base_camera_near = maxf(camera_node.near, 0.001)
	_home_basis = camera_node.basis
	_home_offset = base_camera_offset  # the scene's, before any placement scaled it
	_right = Vector3(_home_basis.x.x, 0.0, _home_basis.x.z).normalized()
	# Initialize target zoom from the camera's current size (reference 16:9 height)
	target_zoom = camera_node.size
	# Apply aspect correction immediately using the actual window size.
	# world_viewport.size may still hold the scene default at this point,
	# so get_window().size gives the real pixel dimensions.
	camera_node.size = CameraController.compute_aspect_corrected_size(
		target_zoom, controller.get_window().size, CameraController.REFERENCE_ASPECT
	)
	update_camera_offset()
	# Seed mouse position so first scroll-to-zoom targets the cursor, not (0,0)
	last_mouse_position = controller.get_viewport().get_mouse_position()


## Leaves no input state behind: held keys, the smoothed velocity and edge pan, a running pan and
## a Home or focus glide all stop.
func deactivate() -> void:
	camera_move_dir = Vector3.ZERO
	camera_velocity = Vector3.ZERO
	current_edge_pan = Vector2.ZERO
	pan_cancel()
	cancel_glide()


func process(delta: float) -> void:
	handle_movement(delta)
	handle_zoom(delta)
	handle_edge_pan(delta)
	# Last, once the pose is final: the shaders' camera-pass test reads this axis (camera-3).
	CanopyFade.publish(
		game_map.camera_node, base_camera_size, Vector2(game_map.world_viewport.size), delta
	)


## WASD: the holder's local move direction, accumulated from key presses and releases.
func handle_input(event: InputEvent) -> bool:
	var input_dir := camera_move_dir

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
	camera_move_dir = input_dir
	return false


## Return the camera size needed to show at least as much horizontal world space
## as a 16:9 window at the given height. On 16:9 or wider viewports the height
## is returned unchanged; on narrower viewports it is scaled up so that
## size * actual_aspect == height * reference_aspect (same visible width).
static func aspect_corrected_size(
	height: float, vp_size: Vector2i, reference_aspect: float
) -> float:
	if vp_size.y == 0 or vp_size.x == 0:
		return height
	var actual_aspect := float(vp_size.x) / float(vp_size.y)
	if actual_aspect >= reference_aspect:
		return height
	return height * reference_aspect / actual_aspect


## The aspect-corrected camera size for the current viewport.
func corrected_size(height: float) -> float:
	return aspect_corrected_size(
		height, game_map.world_viewport.size, CameraController.REFERENCE_ASPECT
	)


## Scale the Camera3D local position so that all screen-corner ray origins
## stay above the highest ground (ground_top_y, 0 unless set). For an orthographic camera,
## translating along the view direction has zero visual effect but keeps the near plane
## ahead of all visible ground geometry, preventing culling at any zoom or aspect ratio:
## every visible ground point lies on a downward ray from an origin above it.
func update_camera_offset() -> void:
	var camera_node := game_map.camera_node
	# Ray origins lie on the near plane: measure the placement below with the scene's own
	# near, then pull the near plane back over the canopies at the end.
	camera_node.near = base_camera_near
	# Baseline: proportional scaling preserves the original camera geometry
	var offset_scale := camera_node.size / base_camera_size
	camera_node.position = base_camera_offset * offset_scale

	# The bottom screen corners have the lowest ray-origin Y because the
	# camera's right axis tilts downward.  On wide or zoomed-out viewports
	# this can push the ray origin below Y=0, causing near-plane culling.
	# Check the actual ray origins and add exactly enough extra offset.
	var vp_size := game_map.world_viewport.size
	if vp_size.x > 0 and vp_size.y > 0:
		var min_y := bottom_ray_origin_y(Vector2(vp_size))
		if min_y < NEAR_PLANE_GROUND_MARGIN:
			var deficit := NEAR_PLANE_GROUND_MARGIN - min_y
			offset_scale += deficit / base_camera_offset.y
			camera_node.position = base_camera_offset * offset_scale
		# Raised authored ground: back further along the camera's own view axis. The base
		# offset is not exactly that axis, so scaling it for the terrain's height shifted the
		# picture while sculpting (zooming hides the same drift with its cursor correction);
		# along the view axis an orthographic camera shows exactly the same frame.
		if controller.ground_top_y > 0.0:
			min_y = bottom_ray_origin_y(Vector2(vp_size))
			var floor_y := controller.ground_top_y + NEAR_PLANE_GROUND_MARGIN
			var back := camera_node.global_basis.z.normalized()
			if min_y < floor_y and back.y > 0.001:
				camera_node.global_position += back * ((floor_y - min_y) / back.y)
		_hold_near_plane_over_canopies(camera_node, Vector2(vp_size))


## Pull the near plane back behind the camera (a negative near; the camera itself stays
## put) until the bottom corners' ray origins, which lie on it, stand CANOPY_CLEARANCE above
## the highest ground. Every canopy on screen then lies in front of it at every zoom, so none
## is sliced or culled: the scene-near plane used to cut the trees at the bottom of the frame
## flat (at the home zoom a 15 m pine there vanished whole) and, closer in, slice canopies
## open. Unlike backing the camera off, this leaves everything that measures from the camera
## as it was: exponential fog, the sun's shadow distance and cascades, measured unchanged at
## the home zoom (Polish, 2026-10-05). Below the home zoom the canopy fade (CanopyFade)
## reveals the ground instead.
func _hold_near_plane_over_canopies(camera_node: Camera3D, vp_size: Vector2) -> void:
	var back := camera_node.global_basis.z.normalized()
	var hold := near_plane_hold(
		bottom_ray_origin_y(vp_size), controller.ground_top_y + CameraController.CANOPY_CLEARANCE, back.y
	)
	camera_node.near = base_camera_near - hold


## How far (metres along the view axis) to pull the near plane back so that a ray origin at
## height `bottom_origin_y` on it rises to `floor_y`, for a back axis rising `back_y` per
## metre. 0 when it is already there. Pure.
static func near_plane_hold(bottom_origin_y: float, floor_y: float, back_y: float) -> float:
	if back_y <= 0.001 or bottom_origin_y >= floor_y:
		return 0.0
	return (floor_y - bottom_origin_y) / back_y


## The lower of the two bottom screen corners' ray origins (world Y).
func bottom_ray_origin_y(vp_size: Vector2) -> float:
	var camera_node := game_map.camera_node
	var bl := camera_node.project_ray_origin(Vector2(0, vp_size.y))
	var br := camera_node.project_ray_origin(vp_size)
	return minf(bl.y, br.y)


## Factor on screen-vertical panning so W/S match A/D on screen, from the live elevation.
func _vertical_comp() -> float:
	return CameraRig.vertical_pan_factor(game_map.camera_node.global_basis.z.normalized().y)


func handle_movement(delta: float) -> void:
	# Compensate for isometric foreshortening: scale the screen-vertical
	# component of the movement direction so W/S feels the same as A/D. The axes are the
	# holder's local ones, so they turn with the view's yaw.
	var screen_v_axis := Vector3(-1.0, 0.0, -1.0).normalized()
	var v_component := camera_move_dir.dot(screen_v_axis)
	var compensated_dir := (
		camera_move_dir + screen_v_axis * v_component * (_vertical_comp() - 1.0)
	)

	# Smoothly accelerate toward target velocity and decelerate when keys released
	var target_velocity = compensated_dir * move_speed
	var smooth_factor = 1.0 - exp(-move_accel_speed * delta)
	camera_velocity = camera_velocity.lerp(target_velocity, smooth_factor)

	# Only translate if velocity is meaningful (avoid micro-drift)
	if camera_velocity.length_squared() > 0.001:
		game_map.cameraholder_node.translate(camera_velocity * delta)
		clamp_to_bounds()


func handle_zoom(delta: float) -> void:
	var camera_node := game_map.camera_node
	# Zoom toward cursor: capture world point under cursor before size change,
	# interpolate size, then recapture and correct camera position.
	# Compute aspect-corrected target: on narrower-than-16:9 viewports, camera.size is
	# scaled up so the visible world width matches the reference 16:9 horizontal extent.
	var corrected_target := corrected_size(target_zoom)
	var zooming := absf(camera_node.size - corrected_target) > 0.001

	# Skip zoom-toward-cursor when a reset/focus tween is animating the camera position,
	# because the tween would overwrite our correction each frame causing wobble.
	var tween_active := reset_tween and reset_tween.is_valid() and reset_tween.is_running()

	# Already at the target size with no reset/focus tween running: the size lerp,
	# cursor-position correction, and offset update below are all no-ops. Skip them.
	if not zooming and not tween_active:
		return

	var world_before: Vector3
	if zooming and not tween_active:
		world_before = camera_node.project_position(last_mouse_position, 0)

	# Smoothly interpolate camera size toward corrected target
	var smooth_factor = 1.0 - exp(-zoom_smooth_speed * delta)
	camera_node.size = lerpf(camera_node.size, corrected_target, smooth_factor)

	# Correct camera position so the point under the cursor stays fixed
	if zooming and not tween_active:
		var world_after = camera_node.project_position(last_mouse_position, 0)
		game_map.cameraholder_node.global_position += world_before - world_after
		clamp_to_bounds()

	# Scale camera offset to match current size -- no visual effect for orthographic,
	# but keeps the near plane ahead of all visible ground geometry.
	update_camera_offset()


## Whether the zoom has eased onto its target (within handle_zoom's own 0.001), no home or focus
## tween runs, and no key, edge or mouse pan is moving the camera.
func is_at_rest() -> bool:
	if absf(game_map.camera_node.size - corrected_size(target_zoom)) > 0.001:
		return false
	if reset_tween != null and reset_tween.is_valid() and reset_tween.is_running():
		return false
	return (
		camera_velocity.length_squared() <= 0.001
		and current_edge_pan == Vector2.ZERO
		and not _is_panning
	)


func finish_zoom() -> void:
	game_map.camera_node.size = corrected_size(target_zoom)
	update_camera_offset()


func frame_ground(at: Vector2, zoom: float) -> void:
	target_zoom = zoom
	finish_zoom()
	var offset := view_center_offset()
	var holder := game_map.cameraholder_node
	holder.global_position = Vector3(at.x - offset.x, holder.global_position.y, at.y - offset.y)
	finish_zoom()


func record_mouse(screen_pos: Vector2) -> void:
	last_mouse_position = screen_pos


func is_panning() -> bool:
	return _is_panning


func is_rmb_pan_active() -> bool:
	return _rmb_pan_active


func pan_begin(screen_pos: Vector2, rmb: bool) -> void:
	_is_panning = true
	if rmb:
		_rmb_pan_active = true
	_pan_start_mouse = screen_pos


func pan_end(rmb: bool) -> void:
	_is_panning = false
	if rmb:
		_rmb_pan_active = false


func pan_cancel() -> void:
	_is_panning = false
	_rmb_pan_active = false


func pan_motion(event: InputEventMouseMotion) -> bool:
	if not _is_panning:
		return false
	_handle_pan_motion(event)
	return _rmb_pan_active


func zoom_by(delta: float) -> void:
	target_zoom = clampf(target_zoom + delta, min_zoom, max_zoom)


func zoom_notch(direction: int) -> void:
	zoom_by(direction * zoom_step)


func zoom_gesture(delta_y: float) -> void:
	if delta_y < 0:
		zoom_by(-zoom_step * pan_gesture_zoom_factor)
	elif delta_y > 0:
		zoom_by(zoom_step * pan_gesture_zoom_factor)


## Replace the zoom range and pull the current target into it. The default 2..20 holds until
## a map is fit; MapViewFit (play and authoring alike) raises the upper limit so a whole map
## fits.
func set_zoom_limits(low: float, high: float) -> void:
	min_zoom = low
	max_zoom = maxf(high, low)
	target_zoom = clampf(target_zoom, min_zoom, max_zoom)


## The orthographic size (the 16:9 reference height, as target_zoom) at which a map of
## `extent_m` (X by Z metres, centred on the origin) whose content spans heights
## `floor_m` (the lowest ground, 0 unless sculpted below it) to `height_m` fits a camera
## with rotation `basis`: the larger of the view height the content spans and the view
## width it spans divided by `aspect`. Pure. For a 200 ft map at this camera's 45 degree
## yaw the width decides: the square's diagonal is sqrt(2) x 61 m.
static func fit_size_for_extent(
	basis: Basis, extent_m: Vector2, height_m: float, aspect: float, floor_m: float
) -> float:
	var right := basis.x.normalized()
	var up := basis.y.normalized()
	var half := extent_m * 0.5
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x in [-half.x, half.x]:
		for z in [-half.y, half.y]:
			for y in [minf(floor_m, 0.0), height_m]:
				var corner := Vector3(x, y, z)
				var screen := Vector2(corner.dot(right), corner.dot(up))
				low = low.min(screen)
				high = high.max(screen)
	var span := high - low
	return maxf(span.y, span.x / aspect)


## How far the pan range has narrowed toward the map centre, 0 (full range) to 1 (the view
## centre is the map centre), at camera size `size` for a map that fits at `fit`.
## Pure. Zero when the fit is unknown or not positive.
static func recentre_weight(size: float, fit: float) -> float:
	if fit <= 0.0 or is_inf(fit):
		return 0.0
	return smoothstep(fit * RECENTRE_START, fit, size)


## Smoothly center the camera on a world position.
## Used by double-click-to-focus on tokens. Camera position is purely local.
func focus_on(world_position: Vector3) -> void:
	# Keep the Y component of the camera holder unchanged (only pan XZ)
	var target_pos := Vector3(
		world_position.x, game_map.cameraholder_node.global_position.y, world_position.z
	)
	# Clamp target to map bounds so the tween doesn't overshoot
	target_pos = _clamp_position_to_bounds(target_pos)
	if reset_tween and reset_tween.is_valid():
		reset_tween.kill()
	reset_tween = controller.create_tween()
	(
		reset_tween
		. tween_property(game_map.cameraholder_node, "global_position", target_pos, 0.3)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


## Home: target the home zoom (handle_zoom eases it; a tween on camera size would fight it), ease
## a turned or tilted view back to the home yaw and pitch first (a glide would fight the
## pivot-keeping shift of the ease), then glide.
func reset_home() -> void:
	cancel_glide()
	target_zoom = home_zoom
	if not controller.view().go_home():
		glide_home()


func capture_home() -> void:
	home_position = game_map.cameraholder_node.global_position
	home_zoom = target_zoom


## Tween the holder to the home position (the clamped one).
func glide_home() -> void:
	var target_pos := _clamp_position_to_bounds(home_position)
	reset_tween = controller.create_tween()
	reset_tween.set_ease(Tween.EASE_OUT)
	reset_tween.set_trans(Tween.TRANS_CUBIC)
	reset_tween.tween_property(game_map.cameraholder_node, "global_position", target_pos, 0.3)


func cancel_glide() -> void:
	if reset_tween and reset_tween.is_valid():
		reset_tween.kill()


## Put the camera child at the pitch drawn now, then move the holder by what the pivot slipped:
## the camera's basis and its offset swing about the right axis (the home pose exactly at home).
func apply_pitch(pitch_deg: float) -> void:
	var camera_node := game_map.camera_node
	var before := controller.view().pivot()
	if is_equal_approx(pitch_deg, CameraRig.HOME_PITCH):
		camera_node.basis = _home_basis
		base_camera_offset = _home_offset
	else:
		camera_node.basis = CameraRig.camera_basis(_right, pitch_deg)
		base_camera_offset = CameraRig.pitched_offset(_home_offset, _right, pitch_deg)
	update_camera_offset()
	var slip := before - controller.view().pivot()
	game_map.cameraholder_node.global_position += Vector3(slip.x, 0.0, slip.z)


func ground_top_changed() -> void:
	update_camera_offset()


## Snap camera.size to the aspect-corrected value when the SubViewport is resized
## (triggered by window resize via SubViewportContainer.stretch = true).
## Snapping immediately prevents handle_zoom() from treating the ratio change as
## a user-initiated zoom-toward-cursor operation.
func viewport_resized() -> void:
	var camera_node := game_map.camera_node
	if not is_instance_valid(camera_node):
		return
	camera_node.size = corrected_size(target_zoom)
	update_camera_offset()


## Handle mouse motion during middle-mouse pan.
## Uses project_position to convert screen delta to world-space camera movement.
## Works correctly for orthographic cameras regardless of angle.
func _handle_pan_motion(event: InputEventMouseMotion) -> void:
	var camera_node := game_map.camera_node
	if not camera_node:
		return
	# Convert old and new screen positions to world positions at depth 0.
	# For orthographic cameras the depth doesn't matter -- the delta is the same.
	var world_from = camera_node.project_position(_pan_start_mouse, 0)
	var world_to = camera_node.project_position(event.position, 0)
	# Move camera opposite to the mouse drag direction (drag right -> view moves right)
	game_map.cameraholder_node.global_position -= (world_to - world_from)
	_pan_start_mouse = event.position
	clamp_to_bounds()


## Compute camera soft bounds from map geometry and snap the camera into
## range immediately. Called after a new map finishes loading.
func map_loaded() -> void:
	_compute_map_bounds()
	clamp_to_bounds()


## Use `bounds` (world space) as the map's extent for pan clamping instead of the mesh walk
## map_loaded() does, and snap the camera into range. Authoring gives the document's
## extent, which is the map whatever has been painted on it so far.
func set_map_bounds(bounds: AABB) -> void:
	map_bounds = bounds
	has_map_bounds = true
	fit_size = fit_size_for_bounds(bounds)
	clamp_to_bounds()


func refit_bounds() -> void:
	if has_map_bounds:
		fit_size = fit_size_for_bounds(map_bounds)


func fit_size_for_bounds(bounds: AABB) -> float:
	var camera_node := game_map.camera_node
	if not is_instance_valid(camera_node):
		return INF
	return fit_size_for_extent(
		camera_node.global_transform.basis,
		Vector2(bounds.size.x, bounds.size.z),
		bounds.size.y,
		CameraController.REFERENCE_ASPECT,
		0.0
	)


## Forget the map's bounds so stale state from the previous level doesn't leak into the next.
func map_clearing() -> void:
	has_map_bounds = false
	fit_size = INF


## Handle camera edge-panning when dragging a token near screen edges.
## Reads the edge_pan_direction from DragController and smoothly interpolates
## to provide a gentle ramp-up entering the zone and coast-out when leaving.
func handle_edge_pan(delta: float) -> void:
	var drag_and_drop_node := game_map.drag_and_drop_node
	# Determine raw target pan direction (zero if not dragging)
	var target_pan = Vector2.ZERO
	var paused := CameraRig.edge_pan_paused(Input.is_key_pressed(KEY_ALT), controller.view().orbiting)
	if drag_and_drop_node and drag_and_drop_node.is_dragging() and not paused:
		target_pan = drag_and_drop_node.edge_pan_direction

	# Smoothly interpolate toward the target pan direction
	var smooth_factor = 1.0 - exp(-EDGE_PAN_SMOOTH_SPEED * delta)
	current_edge_pan = current_edge_pan.lerp(target_pan, smooth_factor)

	# Only translate if pan is meaningful
	if current_edge_pan.length_squared() < 0.0001:
		current_edge_pan = Vector2.ZERO
		return

	# Convert screen-space pan direction to isometric camera movement.
	# Same coordinate mapping as keyboard: up=(-1,-1), down=(+1,+1), left=(-1,+1), right=(+1,-1).
	# Vertical component scaled by foreshortening compensation to match keyboard panning.
	var vert := current_edge_pan.y * _vertical_comp()
	var cam_move = Vector3.ZERO
	cam_move.x = current_edge_pan.x + vert
	cam_move.z = -current_edge_pan.x + vert

	var pan_speed = drag_and_drop_node.edge_pan_speed if drag_and_drop_node else 4.0
	game_map.cameraholder_node.translate(cam_move * pan_speed * delta)
	clamp_to_bounds()


## Compute the bounding box of all mesh geometry in the map container.
## Used for camera soft bounds to prevent panning into the void.
func _compute_map_bounds() -> void:
	# The mesh walk skips decoration beyond the map (Constants.BOUNDS_EXEMPT_META).
	has_map_bounds = false
	if not game_map.map_container:
		return
	var bounds := LevelEnvironmentManager.compute_map_bounds(game_map.map_container)
	has_map_bounds = bounds != AABB()
	if has_map_bounds:
		map_bounds = bounds
		fit_size = fit_size_for_bounds(bounds)


## Compute the XZ offset from the camera holder to the ground-level view center.
## The isometric camera is positioned at a large local offset from the holder
## and looks downward at an angle, so the point on the ground that the screen
## center maps to is NOT at the holder's XZ position. Zero when the centre ray is flatter than
## 0.001 (never meets the ground): an orthographic orbit never looks that flat.
func view_center_offset() -> Vector2:
	var vp_size := game_map.world_viewport.size
	var camera_node := game_map.camera_node
	var screen_center := Vector2(vp_size.x * 0.5, vp_size.y * 0.5)
	var origin := camera_node.project_ray_origin(screen_center)
	var dir := camera_node.project_ray_normal(screen_center)
	if absf(dir.y) < 0.001:
		return Vector2.ZERO
	var t := -origin.y / dir.y
	var ground := origin + dir * t
	var holder := game_map.cameraholder_node.global_position
	return Vector2(ground.x - holder.x, ground.z - holder.z)


## Return a position clamped so the view center stays within the map bounds
## plus margin. The view center is the screen center projected to Y=0 -- it
## differs from the holder position due to the isometric camera offset.
## This prevents infinite panning while preserving natural padding around
## the map. When the map is very small, the view centers on it.
func _clamp_position_to_bounds(pos: Vector3) -> Vector3:
	if not has_map_bounds:
		return pos
	if not is_instance_valid(game_map.camera_node) or not is_instance_valid(game_map.world_viewport):
		return pos

	var view_off := view_center_offset()

	var margin_x := map_bounds.size.x * MAP_BOUNDS_MARGIN_FACTOR
	var margin_z := map_bounds.size.z * MAP_BOUNDS_MARGIN_FACTOR
	var map_min_x := map_bounds.position.x - margin_x
	var map_max_x := map_bounds.position.x + map_bounds.size.x + margin_x
	var map_min_z := map_bounds.position.z - margin_z
	var map_max_z := map_bounds.position.z + map_bounds.size.z + margin_z

	# Zooming out toward the whole-map view, the range narrows onto the map centre.
	var recentre := recentre_weight(game_map.camera_node.size, corrected_size(fit_size))
	if recentre > 0.0:
		var centre := map_bounds.get_center()
		map_min_x = lerpf(map_min_x, centre.x, recentre)
		map_max_x = lerpf(map_max_x, centre.x, recentre)
		map_min_z = lerpf(map_min_z, centre.z, recentre)
		map_max_z = lerpf(map_max_z, centre.z, recentre)

	var vc_x := pos.x + view_off.x
	var vc_z := pos.z + view_off.y

	if map_min_x >= map_max_x:
		vc_x = map_bounds.position.x + map_bounds.size.x * 0.5
	else:
		vc_x = clampf(vc_x, map_min_x, map_max_x)

	if map_min_z >= map_max_z:
		vc_z = map_bounds.position.z + map_bounds.size.z * 0.5
	else:
		vc_z = clampf(vc_z, map_min_z, map_max_z)

	pos.x = vc_x - view_off.x
	pos.z = vc_z - view_off.y
	return pos


## Clamp the camera position to the map bounds (soft limits).
## Called after any camera translation to prevent panning into the void.
func clamp_to_bounds() -> void:
	var holder := game_map.cameraholder_node
	holder.global_position = _clamp_position_to_bounds(holder.global_position)
