class_name EyeRig
extends RefCounted

## The pure maths of the eye-level view (EyeView owns the state and calls these every frame): the
## eye height, the lens, the walk, the foot's bounds and the grab-pan that keeps a dragged ground
## point under the cursor. Lengths are world metres; a map scaled by `map_scale` has its eye
## height and walking speed scaled the same (a half-scale map keeps a half-scale walker).
##
## The pitch here is the same scalar as the orbit rig's (CameraRig): degrees the camera looks down
## from the horizon, so a negative pitch looks up.

## The eye above the ground, metres at map scale 1 (owner verdict SL4, 2026-11-02).
const EYE_HEIGHT_M := 1.6
## Walking speed in metres per second at map scale 1, and the multiplier while Shift is held.
const WALK_SPEED := 5.0
const RUN_FACTOR := 2.0
## The lens (vertical field of view, degrees): the wheel moves it inside this range.
const FOV_DEFAULT := 60.0
const FOV_MIN := 40.0
const FOV_MAX := 75.0
## Degrees per wheel notch, and per unit of a trackpad gesture step.
const FOV_STEP := 3.0
## How far the corrected vertical fov may widen on a narrow window.
const FOV_CEILING := 110.0
## The pitch range at the eye: looking up to 35 degrees, down to 60.
const PITCH_MIN := -35.0
const PITCH_MAX := 60.0
## The pitch the eye starts at when it is entered.
const PITCH_ENTRY := 6.0
## The eye foot stays this far inside the map's edge (owner verdict SL5).
const BOUNDS_INSET_M := 1.5
## A ground ray flatter than this many degrees below the horizon is refused: terrain is not
## ray-pickable and grazing rays miss (card eyeprobe, 2026-11-02: 6 degrees reached 15 m, 3 missed).
const MIN_GROUND_RAY_DEG := 6.0
## Smoothing rates (1 / seconds of the time constant): the lens, the vertical follow, the glide.
const LENS_RATE := 12.0
const HEIGHT_RATE := 6.5
const GLIDE_RATE := 4.0
const WALK_ACCEL := 15.0
## A glide eases out like a smoothing (GLIDE_RATE) but never moves faster than GLIDE_MAX_SPEED
## (metres per second at map scale 1: a far double-click is a quick walk, not a jump) nor slower
## than GLIDE_MIN_SPEED (so its tail ends).
const GLIDE_MAX_SPEED := 20.0
const GLIDE_MIN_SPEED := 1.0
## A double-clicked token is approached to this distance.
const TOKEN_STAND_OFF_M := 1.5


## The eye's height above the ground on a map of scale `map_scale`.
static func eye_height(map_scale: float) -> float:
	return EYE_HEIGHT_M * maxf(map_scale, 0.0001)


## The lens `fov` held to FOV_MIN..FOV_MAX.
static func clamp_lens(fov: float) -> float:
	return clampf(fov, FOV_MIN, FOV_MAX)


## The lens one wheel notch from `target`: -1 zooms in (narrower), +1 out, held to the range.
static func lens_after_notch(target: float, direction: int) -> float:
	return clamp_lens(target + float(direction) * FOV_STEP)


## The vertical fov to give the camera for lens `lens` in a window of `aspect` (width over
## height): unchanged at 16:9 or wider, widened on a narrower window so the horizontal angle of
## the 16:9 view is kept, as the orthographic size is (OrbitView.aspect_corrected_size).
static func corrected_fov(lens: float, aspect: float) -> float:
	if aspect <= 0.0 or aspect >= CameraController.REFERENCE_ASPECT:
		return lens
	var half := tan(deg_to_rad(lens) * 0.5) * CameraController.REFERENCE_ASPECT / aspect
	return minf(rad_to_deg(2.0 * atan(half)), FOV_CEILING)


## `current` moved toward `target` for `seconds` at `rate` (1 / time constant), without
## overshooting; independent of the frame length.
static func smooth_toward(current: float, target: float, rate: float, seconds: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * seconds))


## The walking velocity (world XZ, metres per second) for `input` (x: strafe right, y: forward,
## each -1..1) at view yaw `yaw_deg`. Forward is the direction the camera faces, flattened.
static func walk_velocity(
	input: Vector2, yaw_deg: float, running: bool, map_scale: float
) -> Vector2:
	if input == Vector2.ZERO:
		return Vector2.ZERO
	var wish := input.limit_length(1.0)
	var forward := CameraRig.screen_up(yaw_deg)
	var right := CameraRig.screen_right(yaw_deg)
	var flat := (forward * wish.y + right * wish.x) * WALK_SPEED * maxf(map_scale, 0.0001)
	if running:
		flat *= RUN_FACTOR
	return Vector2(flat.x, flat.z)


## The foot after `seconds` of walking at velocity `velocity`.
static func walk_step(foot: Vector2, velocity: Vector2, seconds: float) -> Vector2:
	return foot + velocity * seconds


## `foot` held inside the map `bounds` (world AABB, XZ used) shrunk by `inset` on every side. A map
## narrower than twice the inset on an axis holds the foot at its middle. An empty AABB (no
## bounds known) leaves the foot as it is.
static func clamp_foot(foot: Vector2, bounds: AABB, inset: float = BOUNDS_INSET_M) -> Vector2:
	if bounds.size.x <= 0.0 and bounds.size.z <= 0.0:
		return foot
	return Vector2(
		_clamp_axis(foot.x, bounds.position.x, bounds.end.x, inset),
		_clamp_axis(foot.y, bounds.position.z, bounds.end.z, inset)
	)


static func _clamp_axis(value: float, low: float, high: float, inset: float) -> float:
	if high - low <= 2.0 * inset:
		return (low + high) * 0.5
	return clampf(value, low + inset, high - inset)


## Where the ray (`origin`, unit `dir`) meets the plane y = `plane_y`, or null when the ray is
## flatter than MIN_GROUND_RAY_DEG below the horizon (a grazing, horizontal or upward ray).
static func ground_hit(origin: Vector3, dir: Vector3, plane_y: float) -> Variant:
	var d := dir.normalized()
	if d.y > -sin(deg_to_rad(MIN_GROUND_RAY_DEG)):
		return null
	return origin + d * ((plane_y - origin.y) / d.y)


## The foot (world XZ) that puts the ground point `grab` under a cursor whose ray now has the unit
## direction `dir`, for an eye `eye_y` high in the world; null when that ray is too flat to reach
## the ground (ground_hit's test). The camera turns not at all during a grab, only translates, so
## the eye stands on the ray from `grab` backwards along `dir`.
static func grab_pan_foot(grab: Vector3, dir: Vector3, eye_y: float) -> Variant:
	var d := dir.normalized()
	if d.y > -sin(deg_to_rad(MIN_GROUND_RAY_DEG)):
		return null
	var eye := grab - d * ((grab.y - eye_y) / d.y)
	return Vector2(eye.x, eye.z)


## The foot one frame of `seconds` after `foot` on a glide to `goal`: an ease-out toward it, held
## between GLIDE_MIN_SPEED and GLIDE_MAX_SPEED (both times the map scale) and never past the goal.
static func glide_step(
	foot: Vector2, goal: Vector2, seconds: float, map_scale: float = 1.0
) -> Vector2:
	var gap := goal - foot
	var distance := gap.length()
	if distance <= 0.0:
		return goal
	var scale := maxf(map_scale, 0.0001)
	var eased := distance * (1.0 - exp(-GLIDE_RATE * seconds))
	var step := clampf(
		eased, GLIDE_MIN_SPEED * scale * seconds, GLIDE_MAX_SPEED * scale * seconds
	)
	if step >= distance:
		return goal
	return foot + gap / distance * step


## The point `distance` short of `target` on the way from `foot` (the foot itself when it is
## already nearer): where a glide to a token stops.
static func stop_short(foot: Vector2, target: Vector2, distance: float) -> Vector2:
	var gap := target - foot
	if gap.length() <= distance:
		return foot
	return target - gap.normalized() * distance
