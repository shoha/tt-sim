class_name WindParticles
extends RefCounted

## Pure functions that turn the global wind (docs/systems/wind.md, phase b) into the parameters
## of the weather particles: rain slant, snow drift and turbulence, wind-streak speed and amount,
## and the rate-limit rules for writing them. No node and no tree; WeatherRenderer applies the
## results to the GPUParticles3D process materials a few times a second, never per particle.

## Rain: tan of the lean from vertical is speed * RAIN_SLANT_PER_MS, clamped to RAIN_SLANT_MAX
## (about 4 degrees at the calm 1.5 m/s, 20 at windy, 32 at storm, 35 at the cap).
const RAIN_SLANT_PER_MS := 0.045
const RAIN_SLANT_MAX := 0.7
const RAIN_GRAVITY := 9.8
## Streaks fall up to this much faster when leaning at the cap.
const RAIN_SPEED_GAIN := 0.25

## Snow: horizontal drift is this fraction of the wind speed, capped; the fall slows by up to
## SNOW_FALL_RELIEF at the reference speed; turbulence rises with gusts.
const SNOW_DRIFT_FRACTION := 0.5
const SNOW_DRIFT_MAX := 4.0
const SNOW_BASE_FALL := 1.5
const SNOW_FALL_RELIEF := 0.3
const SNOW_TURBULENCE_BASE := 1.0
const SNOW_TURBULENCE_GAIN := 2.5
## How fast the noise field that swirls the flakes slides along the wind (m/s per m/s).
const SNOW_SWIRL_PER_MS := 0.03

## The wind speed that counts as "full" for scaling (the storm preset's mean).
const REFERENCE_SPEED := 14.0

## Streaks: travel speed is STREAK_BASE_SPEED plus the wind speed; the amount ratio runs from
## STREAK_MIN_RATIO (tile just on) to 1 (tile full).
const STREAK_BASE_SPEED := 2.0
const STREAK_MIN_RATIO := 0.2

## Rate limit and smoothing for writing material parameters.
const UPDATE_INTERVAL := 0.1
const SMOOTH_SECONDS := 0.4
const WIND_CHANGE_THRESHOLD := 0.15
const GUST_CHANGE_THRESHOLD := 0.04


## The unit horizontal direction of [param wind]; the default direction when it is (nearly) still.
static func horizontal_direction(wind: Vector3) -> Vector3:
	var flat := Vector3(wind.x, 0.0, wind.z)
	if flat.length_squared() < 1e-8:
		return WindPresets.default_direction()
	return flat.normalized()


static func slant_tan(speed: float) -> float:
	return clampf(speed * RAIN_SLANT_PER_MS, 0.0, RAIN_SLANT_MAX)


## Lean angle in degrees for a wind speed (for tests, docs and the debug read-out).
static func slant_degrees(speed: float) -> float:
	return rad_to_deg(atan(slant_tan(speed)))


## The rain's launch direction: down, leaned toward the wind (unit length).
static func rain_direction(wind: Vector3) -> Vector3:
	var lean := horizontal_direction(wind) * slant_tan(wind.length())
	return (lean + Vector3(0.0, -1.0, 0.0)).normalized()


## The rain's acceleration: gravity plus a horizontal part in the same ratio, so the streak
## keeps its lean as it speeds up instead of straightening out.
static func rain_gravity(wind: Vector3) -> Vector3:
	var lean := horizontal_direction(wind) * slant_tan(wind.length()) * RAIN_GRAVITY
	return lean + Vector3(0.0, -RAIN_GRAVITY, 0.0)


## Multiplier on the rain's launch speed (1 straight, 1 + RAIN_SPEED_GAIN at the slant cap).
static func rain_speed_scale(wind: Vector3) -> float:
	return 1.0 + RAIN_SPEED_GAIN * slant_tan(wind.length()) / RAIN_SLANT_MAX


## Horizontal drift speed of snow for a wind speed: half the wind, capped.
static func snow_drift_speed(speed: float) -> float:
	return minf(speed * SNOW_DRIFT_FRACTION, SNOW_DRIFT_MAX)


## The snow's acceleration: a horizontal push along the wind (the flakes' damping turns it into
## a drift of about that speed) and a gravity that eases as the wind rises.
static func snow_gravity(wind: Vector3) -> Vector3:
	var speed := wind.length()
	var drift := horizontal_direction(wind) * snow_drift_speed(speed)
	var relief := 1.0 - SNOW_FALL_RELIEF * clampf(speed / REFERENCE_SPEED, 0.0, 1.0)
	return drift + Vector3(0.0, -SNOW_BASE_FALL * relief, 0.0)


## Turbulence strength for snow: 1 in a lull, rising with the gustiness (gust amplitude times
## the local gust, 0..1) and with how hard it blows.
static func snow_turbulence(speed: float, gustiness: float) -> float:
	var s := clampf(speed / REFERENCE_SPEED, 0.0, 1.0)
	return SNOW_TURBULENCE_BASE + SNOW_TURBULENCE_GAIN * clampf(gustiness, 0.0, 1.0) * s


## The velocity the snow's turbulence noise field slides at: the gentle swirl along the wind.
static func snow_swirl(wind: Vector3) -> Vector3:
	return horizontal_direction(wind) * wind.length() * SNOW_SWIRL_PER_MS


static func streak_speed(speed: float) -> float:
	return STREAK_BASE_SPEED + speed


## Amount ratio of the wind streaks for the Wind tile's intensity: 0 off, then from
## STREAK_MIN_RATIO to 1.
static func streak_ratio(intensity: float) -> float:
	if intensity <= 0.0:
		return 0.0
	return lerpf(STREAK_MIN_RATIO, 1.0, clampf(intensity, 0.0, 1.0))


## One exponential smoothing step of [param current] toward [param target] over [param dt].
static func smooth_toward(current: Vector3, target: Vector3, dt: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-dt / SMOOTH_SECONDS))


static func smooth_scalar(current: float, target: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-dt / SMOOTH_SECONDS))


## Whether the wind or gustiness moved enough since the last write to be worth writing again.
static func changed_enough(
	applied_wind: Vector3, wind: Vector3, applied_gust: float, gust: float
) -> bool:
	return (
		applied_wind.distance_to(wind) > WIND_CHANGE_THRESHOLD
		or absf(applied_gust - gust) > GUST_CHANGE_THRESHOLD
	)
