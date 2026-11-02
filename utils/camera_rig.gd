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

## What an event means to an Alt + drag in progress (orbit_action).
enum Orbit { NONE, BEGIN, MOVE, END }

## The yaw of the scene's own camera pose, and of Home.
const HOME_YAW := 45.0
## The home view's elevation above the ground in degrees (the scene's own camera pose), and the
## flattest the rig allows: no flatter than home, which the owner has not judged (2026-11-02).
const HOME_PITCH := 21.6
const MIN_PITCH := 21.6
## Straight down.
const TOP_DOWN_PITCH := 90.0
## The seconds the O toggle and Home take over the whole range (eased like a turn).
const TILT_SECONDS := 0.5
## Alt + drag: degrees of yaw per pixel dragged sideways, and of pitch per pixel dragged down.
## A 1080 px drag down the screen covers the 68 degree pitch range three times over.
const ORBIT_YAW_PER_PX := 0.3
const ORBIT_PITCH_PER_PX := 0.2
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


## `pitch_deg` held to the rig's range, [MIN_PITCH, TOP_DOWN_PITCH].
static func clamp_pitch(pitch_deg: float) -> float:
	return clampf(pitch_deg, MIN_PITCH, TOP_DOWN_PITCH)


## The elevation in degrees of a camera whose back axis rises `back_y` per metre.
static func pitch_of_back_y(back_y: float) -> float:
	return rad_to_deg(asin(clampf(back_y, -1.0, 1.0)))


## The camera's basis (local to the yawed holder) at elevation `pitch_deg`, built from an explicit
## horizontal `right` axis so that exactly 90 degrees has no gimbal: back leans over the ground
## along right x up by `cos` and rises by `sin`. At HOME_PITCH it is the scene's own pose.
static func camera_basis(right: Vector3, pitch_deg: float) -> Basis:
	var p := deg_to_rad(pitch_deg)
	var back := right.cross(Vector3.UP) * cos(p) + Vector3.UP * sin(p)
	return Basis(right, back.cross(right).normalized(), back)


## The camera's local offset from the holder at `pitch_deg`: the scene's `home_offset` swung about
## the right axis by the rotation that takes the home back axis to the pitched one, so its length
## and its place relative to the view axis are kept (an orthographic picture does not depend on
## the offset, only the near plane and the pivot do; CameraController re-fits both).
static func pitched_offset(home_offset: Vector3, right: Vector3, pitch_deg: float) -> Vector3:
	var home_back := camera_basis(right, HOME_PITCH).z
	var back := camera_basis(right, pitch_deg).z
	return Basis(Quaternion(home_back, back)) * home_offset


## The pitch to ease to when the top-down key is pressed: straight down, or back to `before` (the
## pitch it was pressed at; home when that was already steep) when the view is already top-down.
static func top_down_target(current_target: float, before: float) -> float:
	if current_target < TOP_DOWN_PITCH - 0.5:
		return TOP_DOWN_PITCH
	return HOME_PITCH if before > TOP_DOWN_PITCH - 0.5 else clamp_pitch(before)


## The yaw and pitch change in degrees (x, y) a mouse move of `motion` pixels means during an
## Alt + drag: dragging the picture right turns the camera to the left (yaw falls), dragging it down
## tilts the camera higher (pitch rises), as if the ground were held.
static func orbit_delta(motion: Vector2) -> Vector2:
	return Vector2(-motion.x * ORBIT_YAW_PER_PX, motion.y * ORBIT_PITCH_PER_PX)


## What `event` means to an Alt + left drag: it BEGINs on a left press with Alt held (and no Ctrl
## or Meta) when the pointer is not over the UI and no other drag owns the mouse (`blocked`: a
## token, brush or tool drag), MOVEs the view while `orbiting`, and ENDs on the left release
## wherever the pointer is.
static func orbit_action(
	event: InputEvent, orbiting: bool, over_gui: bool, blocked: bool
) -> Orbit:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if not button.pressed:
			return Orbit.END if orbiting else Orbit.NONE
		var chord := button.alt_pressed and not button.ctrl_pressed and not button.meta_pressed
		if chord and not orbiting and not over_gui and not blocked:
			return Orbit.BEGIN
		return Orbit.NONE
	if orbiting and event is InputEventMouseMotion:
		return Orbit.MOVE
	return Orbit.NONE


## Whether `event` is a fresh bare O press: the top-down toggle.
static func is_top_down_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_O:
		return false
	return not (key.alt_pressed or key.ctrl_pressed or key.meta_pressed or key.shift_pressed)


## Whether edge panning (a token dragged to the screen edge) waits: Alt is the orbit chord, so the
## view must not slide while it is held or an Alt drag runs.
static func edge_pan_paused(alt_held: bool, orbiting: bool) -> bool:
	return alt_held or orbiting


## The 0..1 strength of the top-down token marker at `pitch_deg`: off below 55 degrees, full from
## 70, smooth between (the token's own model is readable up to about 60).
static func marker_strength(pitch_deg: float) -> float:
	return smoothstep(55.0, 70.0, pitch_deg)


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


## The hint-bar key cap and caption for the tilt gesture (O and Home are in the help overlay).
static func tilt_hint() -> Dictionary:
	return {"key": "Alt + drag", "action": "Tilt (O top-down)"}


## The hint-bar key cap and caption naming the turn keys that are live.
static func turn_hint(brush_owns_keys: bool) -> Dictionary:
	return {
		"key": "Alt + Q E" if brush_owns_keys else "Q E",
		"action": "Turn view",
	}
