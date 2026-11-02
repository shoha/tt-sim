class_name CameraYaw
extends RefCounted

## The state of the camera's yaw and its eased turns (CameraRig has the pure maths): the yaw
## drawn now, the snap it eases to and the progress of the ease. CameraController steps it
## every frame and turns the holder by what step() returns; it owns no node.
##
## The yaw is unwrapped while a turn runs (CameraRig.wrap_deg reads it) and wrapped once it lands.

var yaw: float = CameraRig.HOME_YAW
var target: float = CameraRig.HOME_YAW

var _from: float = CameraRig.HOME_YAW
var _t: float = 1.0  # 0..1 progress of the running ease; 1 when none runs
var _seconds: float = CameraRig.TURN_SECONDS


## Whether an eased turn is running.
func is_turning() -> bool:
	return _t < 1.0


## Ease to the yaw `yaw_deg` from the yaw drawn now. Stands still when it is already there.
func retarget(yaw_deg: float) -> void:
	_from = yaw
	target = yaw_deg
	_seconds = CameraRig.turn_seconds(yaw_deg - yaw)
	_t = 1.0 if is_equal_approx(yaw, yaw_deg) else 0.0


## Ease one snap on from the snap being eased to (presses made mid-turn add up), `direction`
## +1 clockwise on the compass and -1 the other way.
func turn(direction: int) -> void:
	retarget(CameraRig.snap_target(target, direction))


## Advance the ease by `delta` seconds; returns the degrees to turn the holder by this frame.
func step(delta: float) -> float:
	if _t >= 1.0:
		return 0.0
	_t = minf(_t + delta / _seconds, 1.0)
	var next := lerpf(_from, target, CameraRig.ease_turn(_t))
	var moved := next - yaw
	yaw = next
	return moved


## Turn by `degrees` at once, ending any ease (an Alt + drag orbit: the yaw is free between snaps).
func nudge(degrees: float) -> void:
	yaw += degrees
	target = yaw
	_from = yaw
	_t = 1.0


## Land on the target: the yaw is wrapped to 0..360 and no turn runs.
func land() -> void:
	yaw = CameraRig.wrap_deg(target)
	target = yaw
	_from = yaw
	_t = 1.0
