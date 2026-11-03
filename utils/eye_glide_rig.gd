class_name EyeGlideRig
extends RefCounted

## The pure maths of the glide between the orbit view and the eye (EyeGlide owns the state and calls
## these every frame; cards eyeentry SR-P3 and eyeglide SR3, owner verdicts EN1 and EN2,
## 2026-11-03: a dolly zoom of 1.3 s, with no fog dip in the middle).
##
## A dolly zoom: the glide starts as a perspective camera far back on the home view's axis with a
## vanishing field of view (EyeGlideRig.START_FOV), which draws the same picture as the orthographic
## home view, and drops onto the eye while the field of view widens so that the pivot plane keeps
## its size on screen (fov = 2 atan(V / 2d), V the orthographic view height, d the distance to the
## pivot) until the fov reaches the eye's lens. Progress q runs 0 (the home picture) to 1 (the eye)
## with a smoothstep of the time; d falls exponentially, so the picture grows at an even rate. The
## pitch and the height blend onto the eye's pose over the last part. The exit is the same curve
## run backwards.
##
## The companions of a far camera are here too: the fog's begin and end move out by d (EyeSky's 25
## to 85 m fog is measured from the camera, so at 974 m everything would be flat fog), the far
## plane follows d.

## The whole glide, seconds (owner verdict EN1).
const SECONDS := 1.3
## The field of view the glide starts from (and ends on, leaving), degrees.
const START_FOV := 2.0
## The offset of the exponential: d(q) = (d0 + K) e^(-lam q) - K reaches 0 at q = 1.
const K := 3.0
## The pitch and the height blend onto the eye over q = TURN_FROM..1.
const TURN_FROM := 0.45
## The near plane through the whole glide (reverse-Z float depth holds a 25000:1 ratio).
const NEAR := 0.05
## The far plane is FAR_MIN or d + FAR_MARGIN, whichever is larger.
const FAR_MIN := 600.0
const FAR_MARGIN := 300.0
## The dissolve of the frozen last frame of the old view over the new one at each end, seconds.
const VEIL_SECONDS := 0.25
## The longest time one frame advances the glide (a stalled frame slows it instead of skipping).
const MAX_STEP_SECONDS := 0.05


## The distance from the pivot at which a camera of field of view `fov_deg` frames a view of height
## `view_height` metres (974 m for the hamlet's 34 m tall home view at 2 degrees).
static func start_distance(view_height: float, fov_deg: float = START_FOV) -> float:
	return view_height / (2.0 * tan(deg_to_rad(fov_deg) * 0.5))


## Progress q (0 home picture, 1 the eye) for the glide's elapsed fraction `t` (0..1).
static func progress(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))


## The camera's distance from the pivot along the home axis at progress `q`, for a glide that
## starts `d_start` away. d_start at q = 0, exactly 0 at q = 1.
static func distance(q: float, d_start: float) -> float:
	var lam := log((d_start + K) / K)
	return maxf((d_start + K) * exp(-lam * clampf(q, 0.0, 1.0)) - K, 0.0)


## The field of view that keeps the pivot plane at the size of a `view_height` tall view from
## distance `d`, held to the eye's `lens`.
static func fov(d: float, view_height: float, lens: float) -> float:
	return minf(lens, rad_to_deg(2.0 * atan(view_height / (2.0 * maxf(d, 0.01)))))


## How far the pitch and the height have blended onto the eye's (0 until TURN_FROM, 1 at q = 1).
static func blend(q: float) -> float:
	return smoothstep(TURN_FROM, 1.0, q)


## The far plane for a camera `d` from the pivot.
static func far_plane(d: float) -> float:
	return maxf(FAR_MIN, d + FAR_MARGIN)


## How far to move the fog's begin and end out (metres) for a camera `d` from the pivot.
static func fog_offset(d: float) -> float:
	return d


## The camera pose at progress `q`. `home_basis` is the orbit camera's basis, `pivot` the ground
## point under the screen centre, `eye_basis` and `eye_position` the eye's pose, `d_start` the
## distance at q = 0. At q = 0 the camera stands on the home axis `d_start` from the pivot; at
## q = 1 it is exactly the eye's.
static func pose(
	q: float,
	home_basis: Basis,
	pivot: Vector3,
	eye_basis: Basis,
	eye_position: Vector3,
	d_start: float
) -> Transform3D:
	var d := distance(q, d_start)
	var b := blend(q)
	var basis := home_basis.slerp(eye_basis, b)
	var origin := pivot + basis.z * d + (eye_position - pivot) * b
	return Transform3D(basis, origin)
