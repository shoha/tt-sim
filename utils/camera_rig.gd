class_name CameraRig
extends RefCounted

## The pure maths of the camera rig's yaw: snap targets, the turn about a pivot, the pan axes
## and the vertical pan factor. CameraController owns the state and calls these every frame.
##
## The yaw is the camera's compass azimuth in degrees, seen from above: 45 is home (the camera
## stands at +x, +z over the pivot and looks toward -x, -z), and a snap is 90, so the four snaps
## are 45, 135, 225 and 315. The CameraHolder carries the yaw as a turn about +Y of
## `yaw - HOME_YAW` from the scene's own pose, so everything the holder's local axes mean (the
## WASD pan, the edge pan) follows the view with no further work. World north is -Z; the sun
## stays where it is in the world (the owner's decision, 2026-11-02), only the camera moves.
##
## Unwrapped yaws are kept while a turn runs (a state may read 495), so an eased turn never
## runs backwards over the wrap; wrap_deg() gives the 0 to 360 reading for display.

## The yaw of the scene's own camera pose, and of Home.
const HOME_YAW := 45.0
## One snap, in degrees.
const SNAP_STEP := 90.0
## The seconds a 90 degree turn takes (a quicker, flatter ease would read as a cut).
const TURN_SECONDS := 0.35
## The steepest slope an eased turn has, as a multiple of its mean speed (smoothstep: 1.5).
const EASE_PEAK := 1.5
## Never divide the vertical pan by less than this fraction of a metre of rise per metre.
const MIN_BACK_Y := 0.2


## `yaw_deg` wrapped to [0, 360).
static func wrap_deg(yaw_deg: float) -> float:
	return fposmod(yaw_deg, 360.0)


## The signed shortest turn from `from_deg` to `to_deg`, in (-180, 180].
static func shortest_turn(from_deg: float, to_deg: float) -> float:
	var d := wrapf(to_deg - from_deg, -180.0, 180.0)
	return 180.0 if is_equal_approx(d, -180.0) else d


## The snap a step in `direction` (+1 clockwise on the compass, -1 counter-clockwise) from
## `yaw_deg` lands on: the next 45 + 90k strictly past the yaw in that direction, from any yaw
## (between snaps too). Unwrapped: 315 stepped +1 gives 405, which wrap_deg() reads as 45.
static func snap_target(yaw_deg: float, direction: int) -> float:
	var steps := (yaw_deg - HOME_YAW) / SNAP_STEP
	var k := floorf(steps + 1e-4) + 1.0 if direction > 0 else ceilf(steps - 1e-4) - 1.0
	return HOME_YAW + k * SNAP_STEP


## The yaw of the snap nearest `yaw_deg`.
static func nearest_snap(yaw_deg: float) -> float:
	return HOME_YAW + roundf((yaw_deg - HOME_YAW) / SNAP_STEP) * SNAP_STEP


## The holder's turn about +Y for a view yaw.
static func holder_basis(yaw_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_deg - HOME_YAW))


## `position` turned about the vertical axis through `pivot` by `delta_deg`, its height kept.
## The rotation of a holder about the ground point under the screen centre: its basis turns by
## the same angle, and the pivot stays where it is on the screen.
static func rotate_about_pivot(position: Vector3, pivot: Vector3, delta_deg: float) -> Vector3:
	var turn := Basis(Vector3.UP, deg_to_rad(delta_deg))
	var flat := turn * Vector3(position.x - pivot.x, 0.0, position.z - pivot.z)
	return Vector3(pivot.x + flat.x, position.y, pivot.z + flat.z)


## The smoothstep of `t` in [0, 1]: the ease of a turn (and its slope is 0 at both ends).
static func ease_turn(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## The seconds a turn of `degrees` takes: TURN_SECONDS for a snap, longer (as the square
## root) for a half turn or more, so a Home from the far side is not a blur.
static func turn_seconds(degrees: float) -> float:
	return TURN_SECONDS * sqrt(maxf(absf(degrees), SNAP_STEP * 0.25) / SNAP_STEP)


## The most degrees an eased turn of `degrees` over `seconds` moves in one frame at `fps`.
static func peak_degrees_per_frame(degrees: float, seconds: float, fps: float) -> float:
	return absf(degrees) * EASE_PEAK / maxf(seconds, 0.001) / fps


## The world direction (unit, flat) that screen-up shows at `yaw_deg`: away from the viewer.
static func screen_up(yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	return Vector3(-sin(a), 0.0, -cos(a))


## The world direction (unit, flat) that screen-right shows at `yaw_deg`.
static func screen_right(yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	return Vector3(cos(a), 0.0, -sin(a))


## The world direction a holder-local pan vector (the legacy WASD axes: forward is (-1, 0, -1))
## moves the holder in at `yaw_deg`.
static func pan_direction(yaw_deg: float, local_dir: Vector3) -> Vector3:
	return holder_basis(yaw_deg) * local_dir


## Factor on the screen-vertical pan so W/S cover the same screen distance per second as A/D:
## the ground foreshortens by the sine of the view's elevation, which is the back axis' y.
## 2.7 at the home view (21.6 degrees), 1 looking straight down. Clamped so a near-level view
## cannot send the pan to infinity.
static func vertical_pan_factor(back_y: float) -> float:
	return 1.0 / clampf(absf(back_y), MIN_BACK_Y, 1.0)


## The angle, clockwise from screen-up in radians, at which world north (-Z) shows on screen.
## It is the yaw itself: at 45 north points up and to the right.
static func north_angle(yaw_deg: float) -> float:
	return deg_to_rad(yaw_deg)


## The turn direction (+1 clockwise, -1 counter-clockwise, 0 none) a key press means.
## Q and E turn the view while no brush owns them; with a brush active they are the brush's
## and Alt+Q / Alt+E turn the view instead (the brush leaves Alt chords alone). `[` and `]`
## are brush size while a brush is active (BrushTool) and turn the view otherwise.
static func key_turn(keycode: Key, alt: bool, mod_other: bool, brush_owns_keys: bool) -> int:
	if mod_other:
		return 0
	match keycode:
		KEY_Q:
			return -1 if (alt == brush_owns_keys) else 0
		KEY_E:
			return 1 if (alt == brush_owns_keys) else 0
		KEY_BRACKETLEFT:
			return -1 if (not brush_owns_keys and not alt) else 0
		KEY_BRACKETRIGHT:
			return 1 if (not brush_owns_keys and not alt) else 0
	return 0


## The turn direction `event` means (key_turn), 0 for anything that is not a fresh key press.
static func event_turn(event: InputEvent, brush_owns_keys: bool) -> int:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return 0
	var other := key.ctrl_pressed or key.meta_pressed or key.shift_pressed
	return key_turn(key.keycode, key.alt_pressed, other, brush_owns_keys)


## The hint-bar key cap and caption naming the turn keys that are live.
static func turn_hint(brush_owns_keys: bool) -> Dictionary:
	return {
		"key": "Alt + Q E" if brush_owns_keys else "Q E",
		"action": "Turn view",
	}
