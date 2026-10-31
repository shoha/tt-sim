class_name StructureWind
extends RefCounted

## The pure parts of how a building's moving pieces follow the global wind (topic wind_c, 2026-10-30;
## docs/systems/wind.md "Phase (c) as built"): a windmill's cap yaw (clamped to a cone about a
## camera-friendly bearing), its sail speed, a weathervane's spring, and the easing both use. Nodes
## (MillMotion, VaneMotion) read the Wind autoload and call these; nothing here touches the scene tree
## or allocates beyond a Vector2.

## The cap may turn this far (radians, 50 degrees) from the camera-friendly bearing, so the sails never
## go edge-on to the default camera however the wind blows.
const MILL_CONE_RAD := 0.8726646
## Sail speed, radians per second: a base turn plus a share of the wind speed, capped.
const MILL_SPEED_BASE := 0.12
const MILL_SPEED_PER_MS := 0.045
const MILL_SPEED_MAX := 1.1
## The time constant (seconds) of the cap's yaw and the sails' speed following the wind.
const EASE_SECONDS := 2.0
## A weathervane is a damped spring on its yaw: natural angular frequency (rad/s) and damping ratio.
## Under-damped (0.35), so a change of direction overshoots once or twice and settles.
const VANE_OMEGA := 2.6
const VANE_ZETA := 0.35
## The wobble a gust drives into the vane's target, radians at full wind (14 m/s and up).
const VANE_WOBBLE_RAD := 0.2
const VANE_WOBBLE_FULL_MS := 14.0
## The largest step the spring integrates in one go (seconds); longer frames take several.
const VANE_MAX_STEP := 0.02


## `angle` wrapped to [-PI, PI].
static func wrap_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


## The angle about +y that turns the horizontal direction `from` onto the horizontal `to` (0 when
## either has no horizontal part). Same sense as MillMotion.facing_angle.
static func turn_between(from: Vector3, to: Vector3) -> float:
	var a := Vector3(from.x, 0.0, from.z)
	var b := Vector3(to.x, 0.0, to.z)
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return 0.0
	return a.normalized().signed_angle_to(b.normalized(), Vector3.UP)


## How far (radians, signed about +y, within +-MILL_CONE_RAD) the cap turns from its camera-friendly
## bearing `centre` to face into a wind that blows toward `wind_toward`. 0 in no wind.
static func mill_cap_offset(wind_toward: Vector3, centre: Vector3) -> float:
	return clampf(turn_between(centre, -wind_toward), -MILL_CONE_RAD, MILL_CONE_RAD)


## The sails' speed (radians per second) for a wind of `speed` metres per second: monotone, capped.
static func mill_speed(speed: float) -> float:
	return clampf(MILL_SPEED_BASE + MILL_SPEED_PER_MS * maxf(speed, 0.0), 0.0, MILL_SPEED_MAX)


## `current` moved toward `target` by an exponential ease of time constant `seconds` over `delta`.
static func ease_toward(current: float, target: float, delta: float, seconds: float) -> float:
	if seconds <= 0.0:
		return target
	return current + (target - current) * (1.0 - exp(-maxf(delta, 0.0) / seconds))


## The same for an angle: the short way round, the result wrapped to [-PI, PI].
static func ease_angle(current: float, target: float, delta: float, seconds: float) -> float:
	var step := ease_toward(0.0, wrap_angle(target - current), delta, seconds)
	return wrap_angle(current + step)


## The wobble (radians) a gust drives into a vane's target: `gust` is the gust envelope 0..1 and
## `speed` the local wind speed. Zero at 0.4 (an average moment), in step with the plants' lean.
static func vane_wobble(gust: float, speed: float) -> float:
	var strength := clampf(speed / VANE_WOBBLE_FULL_MS, 0.0, 1.0)
	return VANE_WOBBLE_RAD * strength * (gust - 0.4) * 2.0


## One step of the vane's spring: `state` is (angle, angular velocity), `target` the angle it is
## pulled to. Semi-implicit Euler in substeps of at most VANE_MAX_STEP, so a slow frame stays stable.
static func vane_step(state: Vector2, target: float, delta: float) -> Vector2:
	var angle := state.x
	var velocity := state.y
	var left := clampf(delta, 0.0, 0.25)
	while left > 0.0:
		var h := minf(left, VANE_MAX_STEP)
		var error := wrap_angle(target - angle)
		velocity += (VANE_OMEGA * VANE_OMEGA * error - 2.0 * VANE_ZETA * VANE_OMEGA * velocity) * h
		angle = wrap_angle(angle + velocity * h)
		left -= h
	return Vector2(angle, velocity)
