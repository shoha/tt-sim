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
## OrbitView.update_camera_offset keeps above the ground and the canopies at every pitch. What the
## pivot is and how the camera is placed for a pitch belong to the active ViewMode
## (CameraController.view_mode()); this class asks it.
##
## Home returns to yaw 45 and the home pitch first and glides to the home position after (the glide
## would fight the pivot-keeping shift of a running turn).

var yaw := CameraYaw.new()
var pitch := CameraPitch.new()
## Whether an Alt + left drag is running.
var orbiting: bool = false

var _c: CameraController = null
var _game_map: GameMap = null
var _glide_home_after: bool = false  # Home: glide to the home position once the view is home
var _pulled_past_home: float = 0.0  # degrees an Alt + drag has pulled flatter than home
var _enter_after_frame: int = -1  # a glide in waits for its veil to be drawn (frame number)


func _init(controller: CameraController, game_map: GameMap) -> void:
	_c = controller
	_game_map = game_map


## Whether an eased turn or tilt, or an orbit drag, is running.
func is_moving() -> bool:
	return yaw.is_turning() or pitch.is_easing() or orbiting


## Whether Home is waiting for a turn or tilt to land before it glides.
func is_waiting_to_glide() -> bool:
	return _glide_home_after


## The ground point under the screen centre, found now (world space, Y = 0).
func pivot() -> Vector3:
	var holder := _game_map.cameraholder_node
	var offset := _c.view_mode().view_center_offset()
	return Vector3(holder.global_position.x + offset.x, 0.0, holder.global_position.z + offset.y)


## Ease the view to the yaw `yaw_deg` about the pivot. Ends a Home that waits to glide.
func set_yaw_target(yaw_deg: float) -> void:
	_c.view_mode().cancel_glide()
	_glide_home_after = false
	yaw.retarget(yaw_deg)


## Ease the view to the pitch `pitch_deg` (held to the rig's range) about the pivot.
func set_pitch_target(pitch_deg: float) -> void:
	_c.view_mode().cancel_glide()
	_glide_home_after = false
	pitch.retarget(pitch_deg)


## Ease the pitch on by `degrees` (the compass arrows; negative is flatter), from the pitch being
## eased to, so presses made mid-tilt add up.
func tilt_by(degrees: float) -> void:
	if degrees < 0.0 and _tilts_past_home():
		enter_street()
		return
	if degrees > 0.0 and _c.view_mode() == _c.eye and pitch.target >= EyeRig.PITCH_MAX - 0.01:
		leave_street()  # the steepest look down from the street climbs back up
		return
	set_pitch_target(pitch.target + degrees)


## Step down from the orbit view into the eye (the street): the glide of EyeGlide (a dolly zoom,
## 1.3 s), or at once when `smooth` is false, the system asks for reduced motion or the setting is
## off. The last orbit frame is held as a veil first and the switch comes the frame after (advance),
## once the veil has been drawn; a headless run has no veil and switches at once. No-op unless the
## orbit view is the view (owner verdict SL1, 2026-11-03).
func enter_street(smooth: bool = true) -> void:
	var eye := _c.eye
	if _c.view_mode() != _c.orbit_view() or _enter_after_frame >= 0:
		return
	if smooth and EyeGlide.allowed():
		if EyeGlide.freeze_veil(_game_map.viewport_container.get_parent()):
			_enter_after_frame = Engine.get_process_frames()
			return
		_c.set_view_mode(eye)
		eye.begin_glide_in()
		return
	_c.set_view_mode(eye)


## Climb from the eye back to the orbit view the eye remembered: the glide in reverse, or at once.
## No-op when the eye is not the view.
func leave_street(smooth: bool = true) -> void:
	if _c.view_mode() != _c.eye:
		return
	if smooth and EyeGlide.allowed():
		_c.eye.begin_glide_out()
	else:
		_c.set_view_mode(_c.orbit_view())


## V and F9: the street if the orbit is the view, the orbit if the street is.
func toggle_street() -> void:
	if _c.view_mode() == _c.eye:
		leave_street()
	else:
		enter_street()


## Whether a flatter tilt from here goes past home: the orbit view is at (or easing to) its
## flattest, so the next flatter step goes down to the street (owner verdict SL1, 2026-11-03).
func _tilts_past_home() -> bool:
	return (
		_c.view_mode() == _c.orbit_view()
		and not _game_map.authoring_mode
		and pitch.target <= CameraRig.MIN_PITCH + 0.01
	)


## The O key: ease straight down, or back to the pitch it left.
func toggle_top_down() -> void:
	_c.view_mode().cancel_glide()
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
	_c.view_mode().cancel_glide()
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
	if _enter_after_frame >= 0 and Engine.get_process_frames() > _enter_after_frame:
		_enter_after_frame = -1
		if _c.view_mode() == _c.orbit_view():
			_c.set_view_mode(_c.eye)
			_c.eye.begin_glide_in()
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
		_c.view_mode().refit_bounds()
		_c.view_tilted.emit(pitch.pitch)


## Turn the holder by `delta_deg` about the vertical axis through the pivot, found now.
func rotate_view(delta_deg: float) -> void:
	var holder := _game_map.cameraholder_node
	holder.global_position = CameraRig.rotate_about_pivot(
		holder.global_position, pivot(), delta_deg
	)
	holder.global_basis = Basis(Vector3.UP, deg_to_rad(delta_deg)) * holder.global_basis


## Put the camera child at the pitch drawn now: the active view swings the camera about its right
## axis and moves the holder by what the pivot slipped (OrbitView.apply_pitch).
func apply_pitch() -> void:
	_c.view_mode().apply_pitch(pitch.pitch)


## The view has landed: the holder takes the yaw's exact basis (no drift from the steps), the pan
## bounds and the zoom limit are fit again for it, and Home's glide follows if it was waiting.
func _finish() -> void:
	yaw.land()
	_game_map.cameraholder_node.global_basis = CameraRig.holder_basis(yaw.yaw)
	_c.view_mode().refit_bounds()
	_c.view_mode().clamp_to_bounds()
	_sync_compass()
	_c.view_tilted.emit(pitch.pitch)
	_c.view_turned.emit(yaw.yaw)
	if _glide_home_after:
		_glide_home_after = false
		_c.view_mode().glide_home()


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
	_c.view_mode().cancel_glide()
	_c.cancel_pan()
	_glide_home_after = false
	_pulled_past_home = 0.0
	yaw.nudge(0.0)
	pitch.set_now(pitch.pitch)
	orbiting = true


## Move the view by `change` (x: degrees of yaw, y: degrees of pitch, as CameraRig.orbit_delta).
func orbit_by(change: Vector2) -> void:
	if not is_zero_approx(change.x):
		rotate_view(change.x)
		yaw.nudge(change.x)
	if not is_zero_approx(change.y):
		# Dragging on past home, flatter, steps down to the street.
		if change.y < 0.0 and _tilts_past_home():
			_pulled_past_home -= change.y
			if _pulled_past_home >= CameraRig.STREET_PULL_DEG:
				_pulled_past_home = 0.0
				enter_street()
				return
		else:
			_pulled_past_home = 0.0
		pitch.set_now(pitch.pitch + change.y)
		apply_pitch()
	_sync_compass()
	_c.view_mode().refit_bounds()
	_c.view_tilted.emit(pitch.pitch)


## End the orbit drag: the yaw is wrapped and the bounds fit for the final view.
func end_orbit() -> void:
	orbiting = false
	_finish()
