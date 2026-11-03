class_name CameraPitch
extends RefCounted

## The state of the camera's pitch and its eased tilts (CameraRig has the pure maths): the
## elevation drawn now, the elevation it eases to, and the pitch the top-down key returns to.
## CameraController steps it every frame and applies what step() returns; it owns no node.
##
## An Alt + drag sets the pitch directly (set_now, no ease: the hand is the ease); the O toggle
## and Home ease over CameraRig.TILT_SECONDS with the same smoothstep as a turn.

var pitch: float = CameraRig.HOME_PITCH
var target: float = CameraRig.HOME_PITCH

## The range the pitch is held to: the orbit rig's, or the eye's (EyeView swaps it, set_range).
var min_deg: float = CameraRig.MIN_PITCH
var max_deg: float = CameraRig.TOP_DOWN_PITCH

var _from: float = CameraRig.HOME_PITCH
var _t: float = 1.0  # 0..1 progress of the running ease; 1 when none runs
var _seconds: float = CameraRig.TILT_SECONDS
var _before: float = CameraRig.HOME_PITCH  # where the next top-down toggle returns to


## Whether an eased tilt is running.
func is_easing() -> bool:
	return _t < 1.0


## Ease to the pitch `pitch_deg` (held to the range) from the pitch drawn now.
func retarget(pitch_deg: float, seconds: float = CameraRig.TILT_SECONDS) -> void:
	_from = pitch
	target = clampf(pitch_deg, min_deg, max_deg)
	_seconds = seconds
	_t = 1.0 if is_equal_approx(pitch, target) else 0.0


## Hold the pitch to `low`..`high` from now on (the eye looks up as well as down); the pitch
## drawn now and the target are pulled into it at once, no ease.
func set_range(low: float, high: float) -> void:
	min_deg = low
	max_deg = high
	set_now(pitch)


## Put the pitch at `pitch_deg` (held to the rig's range) at once, ending any ease.
func set_now(pitch_deg: float) -> void:
	pitch = clampf(pitch_deg, min_deg, max_deg)
	target = pitch
	_from = pitch
	_t = 1.0


## The O key: ease straight down, or back to the pitch it left when already top-down.
func toggle_top_down() -> void:
	var next := CameraRig.top_down_target(target, _before)
	if next >= CameraRig.TOP_DOWN_PITCH - 0.5:
		_before = target
	retarget(next)


## Home: ease to the home pitch and forget the pitch to return to.
func reset_home() -> void:
	_before = CameraRig.HOME_PITCH
	retarget(CameraRig.HOME_PITCH)


## Advance the ease by `delta` seconds; returns true when the pitch moved this frame.
func step(delta: float) -> bool:
	if _t >= 1.0:
		return false
	_t = minf(_t + delta / _seconds, 1.0)
	pitch = lerpf(_from, target, CameraRig.ease_turn(_t))
	return true
