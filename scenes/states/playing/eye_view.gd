class_name EyeView
extends ViewMode

## The eye-level view: a perspective camera at a walker's eye height, standing on the ground and
## turning in place. It takes over the single Camera3D (so every cached reference to it keeps
## working) and the CameraHolder: the holder stands at the eye's foot, on the ground under it, and
## the camera sits EyeRig.eye_height() above it. The yaw is CameraView's (Q / E and the compass
## snap turn about the holder, which is the foot, so the eye turns in place) and so is the pitch,
## with the range widened to look up as well as down (CameraPitch.set_range).
##
## What the player does here (owner verdicts SL3 to SL6, 2026-11-02):
## - WASD walks relative to the facing at EyeRig.WALK_SPEED (Shift runs), eased in and out.
## - Left drag on the ground grabs it: the ground point under the cursor stays under it
##   (EyeRig.grab_pan_foot); MMB and RMB drag do the same. A cursor ray flatter than 6 degrees
##   below the horizon grabs nothing.
## - A double-click on the ground glides the foot there; a double-click on a token glides to
##   1.5 m short of it.
## - The wheel is the lens: the vertical field of view, 40 to 75 degrees, eased.
## - The foot stays 1.5 m inside the map (the map document's whole extent when it has one, else
##   the orbit view's bounds); the eye follows the ground's height, eased.
## - Walls and doors stop the eye (owner verdict SL6): every move of the foot is swept by a
##   sphere against the map's collision and slides along what it meets (EyeCollider). Tokens,
##   grass, scatter and tree crowns have no collision and do not block.
## - A camera shake (token drops) is added on top of the pose, in the holder.
## - The world viewport is raised to MSAA 4x while here (VisualEffectsController).
##
## Entering from the orbit view stands the foot at the ground point under the screen centre and
## keeps the yaw; the orbit camera, holder, yaw pivot and pitch are remembered, and leaving puts
## them back (with any turn made at the eye applied about the orbit pivot), so the orbit view
## returns as it was. The sky is drawn at the camera's real field of view while here
## (Environment.sky_custom_fov 0, instead of the orthographic 2 degrees). The canopy fade, token
## markers, weather, grid and the other readers of Camera3D.size are not adapted yet.

## The camera's far plane at the eye, metres (fog and the sky band hide the rest).
const FAR_PLANE := 600.0
## The near plane at the eye, metres (eyeprobe: nothing slices at 0.05).
const NEAR_PLANE := 0.05

## The painted sky and edge fog installed in the level's environment while the eye is on
## (MapViewFit tells it the map's biome and seed).
var sky: EyeSky = EyeSky.new()
## The glide between the orbit view and the eye (EyeGlide): runs while this mode is active, in
## either direction, so the eye's sky and fog are live all through it.
var glide: EyeGlide = EyeGlide.new()

var _entered: bool = false
var _home_after_glide: bool = false  # the glide out is a Home: the orbit's Home runs on landing
var _leave_after_frame: int = -1  # the glide out landed behind a veil: leave after this frame
var _foot: Vector2 = Vector2.ZERO  # world XZ the eye stands on
var _foot_y: float = 0.0  # the ground's height under the foot, eased
var _pitch: float = EyeRig.PITCH_ENTRY
var _lens: float = EyeRig.FOV_DEFAULT
var _lens_target: float = EyeRig.FOV_DEFAULT
var _bounds: AABB = AABB()  # the walking area now: the document's, else the fallback
var _document_bounds: AABB = AABB()
var _fallback_bounds: AABB = AABB()
var _terrain_body: Object = null  # the authored ground's body, which the sphere ignores
var _terrain_looked: bool = false  # whether the map was searched for it (a GLB map has none)
var _velocity: Vector2 = Vector2.ZERO
var _keys: Dictionary = {&"forward": false, &"back": false, &"left": false, &"right": false}
var _running: bool = false
var _grab: Variant = null  # the ground point held under the cursor (Vector3), or null
var _grab_rmb: bool = false
var _glide: Variant = null  # the foot (Vector2) a glide is heading for, or null

# The orbit view as it was when the eye took over (restored by deactivate)
var _saved_position: Vector3 = Vector3.ZERO
var _saved_basis: Basis = Basis.IDENTITY
var _saved_near: float = 0.05
var _saved_far: float = 1000.0
var _saved_fov: float = 75.0
var _saved_size: float = 1.0
var _saved_projection: int = Camera3D.PROJECTION_ORTHOGONAL
var _saved_keep: int = Camera3D.KEEP_HEIGHT
var _saved_holder: Vector3 = Vector3.ZERO
var _saved_pivot: Vector3 = Vector3.ZERO
var _saved_pitch: float = CameraRig.HOME_PITCH
var _saved_yaw: float = CameraRig.HOME_YAW


func mode_name() -> StringName:
	return &"eye"


## The lens (vertical field of view, degrees) the player chose, eased.
func fov_deg() -> float:
	return _lens


## The world XZ the eye stands on.
func foot() -> Vector2:
	return _foot


## Where the eye is, in the world.
func eye_position() -> Vector3:
	return Vector3(_foot.x, _foot_y + _eye_height(), _foot.y)


## Put the camera at the eye: the foot goes to the ground point under the screen centre (the yaw
## is kept), the pitch range widens, the projection turns perspective.
func activate(owner_controller: CameraController, map: GameMap) -> void:
	super.activate(owner_controller, map)
	var camera := map.camera_node
	var holder := map.cameraholder_node
	_saved_position = camera.position
	_saved_basis = camera.basis
	_saved_near = camera.near
	_saved_far = camera.far
	_saved_fov = camera.fov
	_saved_size = camera.size
	_saved_projection = camera.projection
	_saved_keep = camera.keep_aspect
	_saved_holder = holder.global_position
	_saved_pitch = owner_controller.current_pitch()
	_saved_yaw = owner_controller.current_yaw()
	# Before the camera changes: the ground point under the screen centre, as the orbit sees it.
	var centre := _centre_ground_xz(camera, Vector2(map.world_viewport.size))
	_saved_pivot = Vector3(centre.x, 0.0, centre.y)
	_entered = true
	var orbit := owner_controller.orbit_view()
	_fallback_bounds = orbit.map_bounds if orbit.has_map_bounds else AABB()
	if _fallback_bounds.size == Vector3.ZERO and is_instance_valid(map.map_container):
		_fallback_bounds = LevelEnvironmentManager.compute_map_bounds(map.map_container)
	_refresh_bounds()
	_terrain_looked = false
	_foot = EyeRig.clamp_foot(centre, _bounds)
	_foot_y = _ground_y(_foot)
	_clear_input()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = NEAR_PLANE
	camera.far = FAR_PLANE
	var pitch := owner_controller.view().pitch
	pitch.set_range(EyeRig.PITCH_MIN, EyeRig.PITCH_MAX)
	pitch.set_now(EyeRig.PITCH_ENTRY)
	_lens = _lens_target
	_apply_fov()
	_sync_sky(0.0)
	_sync_painted_sky()
	map.eye_view_antialiasing = true
	UIManager.set_street_hints(true, owner_controller.brush_owns_turn_keys())
	apply_pitch(pitch.pitch)
	if owner_controller.compass != null:
		owner_controller.compass.set_view(owner_controller.current_yaw(), pitch.pitch)


## Put the orbit view back: the camera's own pose and projection, the holder where the orbit pivot
## puts it for the yaw now, the pitch range and pitch, the orthographic sky.
func deactivate() -> void:
	_clear_input()
	if not _entered:
		return
	_entered = false
	glide.end()
	_home_after_glide = false
	_leave_after_frame = -1
	sky.leave()
	UIManager.set_street_hints(false, controller.brush_owns_turn_keys())
	if not is_instance_valid(game_map) or not is_instance_valid(game_map.camera_node):
		return
	var camera := game_map.camera_node
	camera.projection = _saved_projection
	camera.keep_aspect = _saved_keep
	camera.size = _saved_size
	camera.fov = _saved_fov
	camera.near = _saved_near
	camera.far = _saved_far
	camera.position = _saved_position
	camera.basis = _saved_basis
	var turned := controller.current_yaw() - _saved_yaw
	# A shake in flight is still in the holder's position as far as the controller knows.
	game_map.cameraholder_node.global_position = (
		CameraRig.rotate_about_pivot(_saved_holder, _saved_pivot, turned)
		+ controller.shake_offset
	)
	game_map.eye_view_antialiasing = false
	var pitch := controller.view().pitch
	pitch.set_range(CameraRig.MIN_PITCH, CameraRig.TOP_DOWN_PITCH)
	pitch.set_now(_saved_pitch)
	_sync_sky(LevelEnvironmentManager.SKY_ORTHO_FOV_DEG)
	if controller.compass != null:
		controller.compass.set_view(controller.current_yaw(), pitch.pitch)


func process(delta: float) -> void:
	var camera := game_map.camera_node
	if _leave_after_frame >= 0:
		# The glide out has landed behind its veil; the orbit takes over once the veil was drawn.
		if Engine.get_process_frames() > _leave_after_frame:
			_leave_now()
		return
	_sync_sky(0.0)
	if glide.is_active():
		_process_glide(delta)
		return
	_sync_painted_sky()
	_step_lens(delta)
	_step_walk(delta)
	_step_glide(delta)
	_foot = EyeRig.clamp_foot(_foot, _bounds)
	var ground := _ground_y(_foot)
	_foot_y = ground if _grab != null else EyeRig.smooth_toward(
		_foot_y, ground, EyeRig.HEIGHT_RATE, delta
	)
	if absf(_foot_y - ground) < 0.001:
		_foot_y = ground
	_place()
	CanopyFade.publish(camera, camera.size, Vector2(game_map.world_viewport.size), delta)


## WASD and Shift: held keys, read from the key events (the controller passes on the ones it did
## not take as turn or Home keys).
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		_running = (event as InputEventKey).shift_pressed
	for pair in [
		[&"forward", "camera_move_forward"],
		[&"back", "camera_move_backward"],
		[&"left", "camera_move_left"],
		[&"right", "camera_move_right"],
	]:
		if event.is_action_pressed(pair[1]):
			_keys[pair[0]] = true
		elif event.is_action_released(pair[1]):
			_keys[pair[0]] = false
	return false


## The held walk keys as an input vector (x: right, y: forward), or set one directly (tests, jobs).
func walk_input() -> Vector2:
	return Vector2(
		float(_keys[&"right"]) - float(_keys[&"left"]),
		float(_keys[&"forward"]) - float(_keys[&"back"])
	)


## Hold the walk keys as `input` (x: right, y: forward, -1..1) and Shift as `running`, as the
## key events would (render jobs, tests).
func set_walk(input: Vector2, running: bool = false) -> void:
	_keys[&"forward"] = input.y > 0.1
	_keys[&"back"] = input.y < -0.1
	_keys[&"right"] = input.x > 0.1
	_keys[&"left"] = input.x < -0.1
	_running = running


## Stand at the ground point `at` (world XZ) now, no glide.
func frame_ground(at: Vector2, _zoom: float) -> void:
	_glide = null
	_foot = EyeRig.clamp_foot(at, _bounds)
	_foot_y = _ground_y(_foot)
	_place()


## Glide to stand 1.5 m short of `world_position` (a double-clicked token).
func focus_on(world_position: Vector3) -> void:
	var stop := EyeRig.stop_short(
		_foot, Vector2(world_position.x, world_position.z), EyeRig.TOKEN_STAND_OFF_M
	)
	_glide = EyeRig.clamp_foot(stop, _bounds)


## Glide the foot to world XZ `at` (clamped inside the map).
func glide_to(at: Vector2) -> void:
	_glide = EyeRig.clamp_foot(at, _bounds)


func cancel_glide() -> void:
	_glide = null
	skip_view_glide()


# The glide between the orbit view and the eye (EyeGlide)


## Whether the glide between the orbit view and the eye runs.
func is_view_gliding() -> bool:
	return glide.is_active()


## Whether a glide out has landed and waits one frame (behind its veil) to hand over to the orbit.
func is_leaving() -> bool:
	return _leave_after_frame >= 0


## Start the glide into the eye (call right after activate: the camera is at the eye then and the
## home pose is the saved orbit pose). The first frame is the home picture.
func begin_glide_in() -> void:
	_home_after_glide = false
	_begin_glide(true)


## Start the glide back to the orbit view's pose; the orbit view takes over when it lands
## (CameraController.set_view_mode). `go_home`: the orbit's Home runs on landing.
func begin_glide_out(go_home: bool = false) -> void:
	if is_leaving():
		return
	_clear_input()
	_home_after_glide = go_home
	_begin_glide(false)


## End a running glide at once, at its end: the eye's own pose going in, the orbit view going
## out. Any key or pointer input does this before it acts. No-op when no glide runs.
func skip_view_glide() -> void:
	if glide.is_active():
		_land_glide(false)


func _begin_glide(entering: bool) -> void:
	var camera := game_map.camera_node
	var aspect := float(game_map.world_viewport.size.x) / maxf(game_map.world_viewport.size.y, 1.0)
	var home := _home_pose()
	var eye_basis := (
		game_map.cameraholder_node.global_basis
		* CameraRig.camera_basis(CameraRig.screen_right(CameraRig.HOME_YAW), _pitch)
	)
	glide.begin(
		camera,
		sky,
		entering,
		{
			"home_basis": home.basis.orthonormalized(),
			"pivot": _saved_pivot,
			"eye_basis": eye_basis.orthonormalized(),
			"eye_position": eye_position(),
			"view_height": _saved_size if _saved_keep == Camera3D.KEEP_HEIGHT else _saved_size / aspect,
			"lens": EyeRig.corrected_fov(_lens, aspect),
		}
	)
	_sync_painted_sky()


## The orbit camera's world pose as leaving would restore it (deactivate: the holder turned about
## the orbit pivot by whatever yaw the eye added).
func _home_pose() -> Transform3D:
	var turned := controller.current_yaw() - _saved_yaw
	var holder_basis := CameraRig.holder_basis(controller.current_yaw())
	var holder_at := CameraRig.rotate_about_pivot(_saved_holder, _saved_pivot, turned)
	return Transform3D(holder_basis * _saved_basis, holder_at + holder_basis * _saved_position)


func _process_glide(delta: float) -> void:
	var camera := game_map.camera_node
	var running := glide.step(delta)
	_sync_painted_sky()
	CanopyFade.publish(camera, camera.size, Vector2(game_map.world_viewport.size), delta)
	if not running:
		_land_glide(true)


## The glide has reached its end (`finished`) or is skipped: going in, the eye is placed as the
## plain eye view places it; going out, the orbit view takes over, behind a dissolve of the last
## frame when the glide ran its course (a skipped one is cut, as the input that skipped it is).
func _land_glide(finished: bool) -> void:
	var entering := glide.is_entering()
	glide.end()
	if entering:
		var camera := game_map.camera_node
		camera.near = NEAR_PLANE
		camera.far = FAR_PLANE
		_apply_fov()
		_place()
		_sync_painted_sky()
		return
	if finished and EyeGlide.freeze_veil(game_map.viewport_container.get_parent()):
		# The veil is drawn once over the last glide frame; the orbit takes over next frame.
		_leave_after_frame = Engine.get_process_frames()
		return
	_leave_now()


func _leave_now() -> void:
	var go_home := _home_after_glide
	_home_after_glide = false
	_leave_after_frame = -1
	controller.set_view_mode(controller.orbit_view())
	if go_home:
		controller.orbit_view().reset_home()


# Pointer: grab the ground


func is_panning() -> bool:
	return _grab != null


func is_rmb_pan_active() -> bool:
	return _grab != null and _grab_rmb


func pan_begin(screen_pos: Vector2, rmb: bool) -> void:
	skip_view_glide()
	_glide = null
	_grab = _pointer_ground(screen_pos)
	_grab_rmb = rmb and _grab != null


func pan_end(_rmb: bool) -> void:
	pan_cancel()


func pan_cancel() -> void:
	_grab = null
	_grab_rmb = false


func pan_motion(event: InputEventMouseMotion) -> bool:
	if _grab == null:
		return false
	var camera := game_map.camera_node
	var dir := camera.project_ray_normal(event.position)
	var foot: Variant = EyeRig.grab_pan_foot(_grab, dir, camera.global_position.y)
	if foot != null:
		_foot = EyeRig.clamp_foot(_collide(_foot, foot), _bounds)
		_place()
	return _grab_rmb


## The left button: a press on empty ground grabs it, a double-click glides there, a release lets
## go. Nothing is marked handled: a click on the ground still reaches whatever else listens.
func primary_button(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.pressed and glide.is_active():
		skip_view_glide()
		if controller.view_mode() != self:
			return false
	if not event.pressed:
		if _grab != null and not _grab_rmb:
			pan_cancel()
		return false
	if not controller.rmb_can_start_pan(event.position):
		return false
	if event.double_click:
		var hit: Variant = _pointer_ground(event.position)
		if hit != null:
			glide_to(Vector2(hit.x, hit.z))
		return false
	pan_begin(event.position, false)
	return false


# Lens


func zoom_by(delta: float) -> void:
	skip_view_glide()
	_lens_target = EyeRig.clamp_lens(_lens_target + delta)


func zoom_notch(direction: int) -> void:
	skip_view_glide()
	_lens_target = EyeRig.lens_after_notch(_lens_target, direction)


func zoom_gesture(delta_y: float) -> void:
	zoom_by(signf(delta_y) * EyeRig.FOV_STEP * 0.2)


func finish_zoom() -> void:
	_lens = _lens_target
	_apply_fov()


func viewport_resized() -> void:
	_apply_fov()


## Look at `pitch_deg` (held to the eye's range): the camera child's basis, the eye height above
## the holder.
func apply_pitch(pitch_deg: float) -> void:
	_pitch = clampf(pitch_deg, EyeRig.PITCH_MIN, EyeRig.PITCH_MAX)
	_place()


## The offset from the holder to the foot: zero, the holder stands on it, so a turn pivots there.
func view_center_offset() -> Vector2:
	if not is_instance_valid(game_map):
		return Vector2.ZERO
	var holder := game_map.cameraholder_node.global_position - controller.shake_offset
	return _foot - Vector2(holder.x, holder.z)


## Home leaves the eye for the orbit view and runs the orbit's Home from there.
func reset_home() -> void:
	if is_leaving():
		return
	if glide.is_active():
		skip_view_glide()
		if controller.view_mode() != self:
			return
	if EyeGlide.allowed():
		begin_glide_out(true)
		return
	var orbit := controller.orbit_view()
	controller.set_view_mode(orbit)
	orbit.reset_home()


func clamp_to_bounds() -> void:
	_foot = EyeRig.clamp_foot(_foot, _bounds)
	_place()


func map_loaded() -> void:
	if is_instance_valid(game_map.map_container):
		_fallback_bounds = LevelEnvironmentManager.compute_map_bounds(game_map.map_container)
	_terrain_looked = false
	_refresh_bounds()
	clamp_to_bounds()


func set_map_bounds(bounds: AABB) -> void:
	_fallback_bounds = bounds
	_refresh_bounds()
	clamp_to_bounds()


## The map document's extent in world space (an empty AABB for none), set by MapViewFit whenever
## the map is fit, whichever view is active. It is the walking area when it has a size, so the
## whole map is walkable even where a dressed GLB's meshes end sooner.
func set_document_bounds(bounds: AABB) -> void:
	_document_bounds = bounds
	_refresh_bounds()
	if _entered:
		clamp_to_bounds()


func map_clearing() -> void:
	_fallback_bounds = AABB()
	_document_bounds = AABB()
	_terrain_looked = false
	_bounds = AABB()


func is_at_rest() -> bool:
	return (
		_velocity.length_squared() < 0.0001
		and walk_input() == Vector2.ZERO
		and _glide == null
		and _grab == null
		and absf(_lens - _lens_target) < 0.01
	)


# Internals


func _eye_height() -> float:
	return EyeRig.eye_height(_map_scale())


## The map root's scale (world metres per map metre), 1 with no map.
func _map_scale() -> float:
	if not is_instance_valid(game_map) or not is_instance_valid(game_map.map_container):
		return 1.0
	var map := game_map.map_container.get_node_or_null("LevelMap") as Node3D
	if map == null:
		return 1.0
	return maxf(map.global_transform.basis.get_scale().x, 0.0001)


## The ground's world height under world XZ `at`: the map's ground field, 0 on the fixed band.
func _ground_y(at: Vector2) -> float:
	var field := game_map.get_grid_ground()
	if field == null or not field.is_valid():
		return 0.0
	return field.world_height_at(at)


## The ground point (world) under the cursor, or null when its ray is flatter than the limit.
func _pointer_ground(screen_pos: Vector2) -> Variant:
	var camera := game_map.camera_node
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var y := _foot_y
	for _i in 3:
		var hit: Variant = EyeRig.ground_hit(origin, dir, y)
		if hit == null:
			return null
		y = _ground_y(Vector2(hit.x, hit.z))
	return EyeRig.ground_hit(origin, dir, y)


## The XZ of the ground under the screen centre of `camera` (the y = 0 plane), or the holder's.
func _centre_ground_xz(camera: Camera3D, viewport_px: Vector2) -> Vector2:
	var centre := viewport_px * 0.5
	var origin := camera.project_ray_origin(centre)
	var dir := camera.project_ray_normal(centre)
	if absf(dir.y) < 0.001:
		var holder := game_map.cameraholder_node.global_position
		return Vector2(holder.x, holder.z)
	var hit := origin + dir * (-origin.y / dir.y)
	return Vector2(hit.x, hit.z)


## Write the foot, the eased ground height and the pitch to the holder and the camera.
func _place() -> void:
	var holder := game_map.cameraholder_node
	var camera := game_map.camera_node
	var at := Vector3(_foot.x, _foot_y, _foot.y) + controller.shake_offset
	if not holder.global_position.is_equal_approx(at):
		holder.global_position = at
	camera.position = Vector3(0.0, _eye_height(), 0.0)
	camera.basis = CameraRig.camera_basis(CameraRig.screen_right(CameraRig.HOME_YAW), _pitch)


func _apply_fov() -> void:
	var size := game_map.world_viewport.size
	var aspect := float(size.x) / float(size.y) if size.y > 0 else CameraController.REFERENCE_ASPECT
	game_map.camera_node.fov = EyeRig.corrected_fov(_lens, aspect)


func _step_lens(delta: float) -> void:
	if absf(_lens - _lens_target) < 0.01:
		_lens = _lens_target
	else:
		_lens = EyeRig.smooth_toward(_lens, _lens_target, EyeRig.LENS_RATE, delta)
	_apply_fov()


func _step_walk(delta: float) -> void:
	var wish := walk_input()
	var target := EyeRig.walk_velocity(wish, controller.current_yaw(), _running, _map_scale())
	_velocity = _velocity.lerp(target, 1.0 - exp(-EyeRig.WALK_ACCEL * delta))
	if wish == Vector2.ZERO and _velocity.length_squared() < 0.0001:
		_velocity = Vector2.ZERO
	if wish != Vector2.ZERO:
		_glide = null
	_foot = _collide(_foot, EyeRig.walk_step(_foot, _velocity, delta))


func _step_glide(delta: float) -> void:
	if _glide == null:
		return
	var goal: Vector2 = _glide
	var wanted := EyeRig.glide_step(_foot, goal, delta, _map_scale())
	_foot = _collide(_foot, wanted)
	# A glide that met a wall ends there rather than grinding along it.
	if _foot == goal or not _foot.is_equal_approx(wanted):
		_glide = null


## The foot after moving from `from` toward `to`, stopped at walls and slid along them
## (EyeCollider). The sphere's centre is at the eye. A move of nothing, or with no map to touch,
## is returned as asked.
func _collide(from: Vector2, to: Vector2) -> Vector2:
	var motion := to - from
	if motion.length_squared() < 0.0000001 or not is_instance_valid(game_map.map_container):
		return to
	var scale := _map_scale()
	var collider := EyeCollider.new(
		game_map.map_container.get_world_3d().direct_space_state,
		_excluded_bodies(),
		EyeCollider.RADIUS_M * scale
	)
	return collider.move(from, motion, _foot_y + _eye_height())


## The bodies the sphere ignores: the authored ground's. The eye follows the ground by height.
func _excluded_bodies() -> Array[RID]:
	var rids: Array[RID] = []
	if not _terrain_looked or (_terrain_body != null and not is_instance_valid(_terrain_body)):
		_terrain_looked = true
		_terrain_body = game_map.map_container.find_child(
			AuthoredTerrain.COLLISION_NAME, true, false
		)
	var body := _terrain_body as CollisionObject3D
	if body != null:
		rids.append(body.get_rid())
	return rids


## The walking area: the map document's extent when it has one, else the orbit view's bounds.
func _refresh_bounds() -> void:
	_bounds = EyeRig.walk_bounds(_document_bounds, _fallback_bounds)


func _clear_input() -> void:
	for key in _keys:
		_keys[key] = false
	_running = false
	_velocity = Vector2.ZERO
	_grab = null
	_grab_rmb = false
	_glide = null


## Set the sky's drawn field of view (0: the camera's own; the orthographic view uses 2 degrees).
## Written every frame because a settings change re-applies the orthographic value.
func _sync_sky(fov: float) -> void:
	var env := level_environment()
	if env != null and not is_equal_approx(env.sky_custom_fov, fov):
		env.sky_custom_fov = fov


## The Environment the world viewport renders under (the level's WorldEnvironment sets it on the
## world the viewport shares; the viewport's own world_3d property is null here), or null.
func level_environment() -> Environment:
	if not is_instance_valid(game_map):
		return null
	var world := game_map.world_viewport.find_world_3d()
	return world.environment if world != null else null


## Keep the painted sky and the edge fog installed in the environment (EyeSky.sync): a settings
## change that re-applies the environment is put right the next frame. The sun is the one the
## foliage light follows (the level's, or the map's own), or a high southern one when none shines.
func _sync_painted_sky() -> void:
	var sun := FoliageLight.last_sun
	var to_sun := Vector3(sun.x, sun.y, sun.z)
	if to_sun.length() < 0.5:
		to_sun = Vector3(0.0, 0.64, 0.77)
	sky.sync(level_environment(), to_sun.normalized())
