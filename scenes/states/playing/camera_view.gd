class_name CameraView
extends RefCounted

## The orientation half of the camera rig: the view's yaw and pitch, their eased turns and tilts,
## and the Alt + drag orbit. CameraController owns one and forwards its public turn and tilt calls;
## CameraRig has the pure maths and CameraYaw / CameraPitch the state.
##
## Every change of the view keeps the ground point under the screen centre (the pivot) where it is
## on the screen. A yaw turn rotates the holder about the vertical axis through the pivot; a pitch
## change swings the camera child's basis and offset about its right axis and moves the holder by
## whatever the pivot slipped. Both find the pivot live every frame, so panning or a zoom easing at
## the same time cannot pull the view off it. The camera is orthographic: the picture depends on the
## basis and the pivot alone; the offset along the view axis only matters for the near plane, which
## CameraController._update_camera_offset keeps above the ground and the canopies at every pitch.
##
## Home returns to yaw 45 and the home pitch first and glides to the home position after (the glide
## would fight the pivot-keeping shift of a running turn).

var yaw := CameraYaw.new()
var pitch := CameraPitch.new()
## Whether an Alt + left drag is running.
var orbiting: bool = false

var _c: CameraController = null
var _game_map: GameMap = null
var _home_basis: Basis = Basis.IDENTITY  # the camera's local pose in the scene
var _home_offset: Vector3 = Vector3.ZERO
var _right: Vector3 = Vector3.RIGHT  # the camera's horizontal right axis, local to the holder
var _glide_home_after: bool = false  # Home: glide to the home position once the view is home


func _init(controller: CameraController, game_map: GameMap) -> void:
	_c = controller
	_game_map = game_map
	var camera_node := game_map.camera_node
	_home_basis = camera_node.basis
	_home_offset = controller._base_camera_offset  # the scene's, before any placement scaled it
	_right = Vector3(_home_basis.x.x, 0.0, _home_basis.x.z).normalized()


## Whether an eased turn or tilt, or an orbit drag, is running.
func is_moving() -> bool:
	return yaw.is_turning() or pitch.is_easing() or orbiting


## Whether Home is waiting for a turn or tilt to land before it glides.
func is_waiting_to_glide() -> bool:
	return _glide_home_after


## The ground point under the screen centre, found now (world space, Y = 0).
func pivot() -> Vector3:
	var holder := _game_map.cameraholder_node
	var offset := _c._get_view_center_ground_offset()
	return Vector3(holder.global_position.x + offset.x, 0.0, holder.global_position.z + offset.y)


## Ease the view to the yaw `yaw_deg` about the pivot. Ends a Home that waits to glide.
func set_yaw_target(yaw_deg: float) -> void:
	_c._cancel_home_tween()
	_glide_home_after = false
	yaw.retarget(yaw_deg)


## Ease the view to the pitch `pitch_deg` (held to the rig's range) about the pivot.
func set_pitch_target(pitch_deg: float) -> void:
	_c._cancel_home_tween()
	_glide_home_after = false
	pitch.retarget(pitch_deg)


## Ease the pitch on by `degrees` (the compass arrows; negative is flatter), from the pitch being
## eased to, so presses made mid-tilt add up.
func tilt_by(degrees: float) -> void:
	set_pitch_target(pitch.target + degrees)


## The O key: ease straight down, or back to the pitch it left.
func toggle_top_down() -> void:
	_c._cancel_home_tween()
	_glide_home_after = false
	pitch.toggle_top_down()


## Put the view at the yaw `yaw_deg` at once, about the same pivot (render jobs, tests).
func set_yaw_now(yaw_deg: float) -> void:
	set_yaw_target(yaw_deg)
	if yaw.is_turning():
		rotate_view(yaw_deg - yaw.yaw)
		yaw.yaw = yaw_deg
		_finish()


## Put the view at the pitch `pitch_deg` at once, about the same pivot (render jobs, tests).
func set_pitch_now(pitch_deg: float) -> void:
	_c._cancel_home_tween()
	_glide_home_after = false
	pitch.set_now(pitch_deg)
	apply_pitch()
	_finish()


## Home: ease the yaw and the pitch back to the home view; true when one is on its way and the
## glide to the home position will follow it (else the caller glides at once).
func go_home() -> bool:
	pitch.reset_home()
	var back := CameraRig.shortest_turn(yaw.target, CameraRig.HOME_YAW)
	if not is_zero_approx(back):
		yaw.retarget(yaw.target + back)
	_glide_home_after = yaw.is_turning() or pitch.is_easing()
	return _glide_home_after


## One frame of the eased turn and tilt: move the view by their steps, keeping the pivot.
func advance(delta: float) -> void:
	var tilted := pitch.step(delta)
	if not yaw.is_turning() and not tilted:
		return
	if yaw.is_turning():
		rotate_view(yaw.step(delta))
	if tilted:
		apply_pitch()
	_sync_compass()
	if not yaw.is_turning() and not pitch.is_easing():
		_finish()
	elif tilted:
		_c._refit_bounds()
		_c.view_tilted.emit(pitch.pitch)


## Turn the holder by `delta_deg` about the vertical axis through the pivot, found now.
func rotate_view(delta_deg: float) -> void:
	var holder := _game_map.cameraholder_node
	holder.global_position = CameraRig.rotate_about_pivot(
		holder.global_position, pivot(), delta_deg
	)
	holder.global_basis = Basis(Vector3.UP, deg_to_rad(delta_deg)) * holder.global_basis


## Put the camera child at the pitch drawn now, then move the holder by what the pivot slipped:
## the camera's basis and its offset swing about the right axis (the home pose exactly at home).
func apply_pitch() -> void:
	var camera_node := _game_map.camera_node
	var before := pivot()
	if is_equal_approx(pitch.pitch, CameraRig.HOME_PITCH):
		camera_node.basis = _home_basis
		_c._base_camera_offset = _home_offset
	else:
		camera_node.basis = CameraRig.camera_basis(_right, pitch.pitch)
		_c._base_camera_offset = CameraRig.pitched_offset(_home_offset, _right, pitch.pitch)
	_c._update_camera_offset()
	var slip := before - pivot()
	_game_map.cameraholder_node.global_position += Vector3(slip.x, 0.0, slip.z)


## The view has landed: the holder takes the yaw's exact basis (no drift from the steps), the pan
## bounds and the zoom limit are fit again for it, and Home's glide follows if it was waiting.
func _finish() -> void:
	yaw.land()
	_game_map.cameraholder_node.global_basis = CameraRig.holder_basis(yaw.yaw)
	_c._refit_bounds()
	_c._clamp_camera_to_bounds()
	_sync_compass()
	_c.view_tilted.emit(pitch.pitch)
	_c.view_turned.emit(yaw.yaw)
	if _glide_home_after:
		_glide_home_after = false
		_c._glide_to_home()


func _sync_compass() -> void:
	if _c.compass != null:
		_c.compass.set_view(yaw.yaw, pitch.pitch)


## Handle `event` for the Alt + left drag orbit (CameraRig.orbit_action): `over_gui` is whether the
## pointer is over the UI and `blocked` whether another drag owns the mouse (a token, a brush
## stroke, a tool). True when the event is the orbit's and the caller must not pass it on.
func handle_orbit_input(event: InputEvent, over_gui: bool, blocked: bool) -> bool:
	match CameraRig.orbit_action(event, orbiting, over_gui, blocked):
		CameraRig.Orbit.BEGIN:
			begin_orbit()
			return true
		CameraRig.Orbit.MOVE:
			orbit_by(CameraRig.orbit_delta((event as InputEventMouseMotion).relative))
			return true
		CameraRig.Orbit.END:
			end_orbit()
			return true
	return false


## Start an orbit drag: a running turn, tilt or Home glide stops where it is.
func begin_orbit() -> void:
	_c._cancel_home_tween()
	_c.cancel_pan()
	_glide_home_after = false
	yaw.nudge(0.0)
	pitch.set_now(pitch.pitch)
	orbiting = true


## Move the view by `change` (x: degrees of yaw, y: degrees of pitch, as CameraRig.orbit_delta).
func orbit_by(change: Vector2) -> void:
	if not is_zero_approx(change.x):
		rotate_view(change.x)
		yaw.nudge(change.x)
	if not is_zero_approx(change.y):
		pitch.set_now(pitch.pitch + change.y)
		apply_pitch()
	_sync_compass()
	_c._refit_bounds()
	_c.view_tilted.emit(pitch.pitch)


## End the orbit drag: the yaw is wrapped and the bounds fit for the final view.
func end_orbit() -> void:
	orbiting = false
	_finish()
