class_name WindDrift
extends RefCounted

## Pure functions that turn the global wind (docs/systems/wind.md, phase f) into the last three
## things that read it: a fire's smoke leaning and drifting downwind, the dust a terrain event
## throws up drifting with it, and a faint chop on water. No node and no tree.
##
## Every function takes the player's motion scale (Wind.motion_scale(): reduce-motion and the
## "Wind motion" setting) and at 0 gives back exactly what the effect did before the wind
## existed: the smoke leans down the map's own wind at its old lean, dust and smoke keep their
## own drift, the water its own ripples. The shaders (fire_smoke_book.gdshader,
## water.gdshader, through wind_global.gdshaderinc) evaluate the same formulas on the GPU from
## the global uniforms; test_wind_drift.gd checks their constants against these.

## The mean speeds (m/s) of the calm and the storm stop (WindPresets.STOPS): strength01 runs
## from 0 at calm to 1 at a storm.
const CALM_SPEED := 1.5
const STORM_SPEED := 14.0

## The persistent fire's smoke column (fire_smoke_book.gdshader): its lean (a share of its rise
## at the top) at calm and at a storm. Calm is FireFieldSmoke.LEAN, the look tuned before the
## wind existed. A passing gust leans it SMOKE_GUST times the gust amplitude further (the
## gust field's 0..1 shape, centred on SMOKE_GUST_REST), so a front leans it over and it
## stands back up as the lull follows, with nothing faster than the fronts in it.
const SMOKE_LEAN_CALM := 0.45
const SMOKE_LEAN_STORM := 0.95
const SMOKE_GUST := 0.5
const SMOKE_GUST_REST := 0.4
## No lean past this (FireFieldSmoke.bounds makes room for it).
const SMOKE_LEAN_MAX := 1.25

## A fire event's drift (FireSweep: its billows, tongues and embers ride it), metres a second
## at calm and at a storm. Calm is the 0.35 m/s FireSweep drew before.
const EVENT_DRIFT_CALM := 0.35
const EVENT_DRIFT_STORM := 1.1

## Dust (EventPuffs' drifting blobs): this share of the local wind, at most DUST_MAX m/s, so a
## storm streams a tree's dust a few metres away and calm barely moves it.
const DUST_SHARE := 0.2
const DUST_MAX := 2.8

## Water chop (water.gdshader): the ripples' slope gains CHOP_BASE (everywhere) plus CHOP_GUST
## times the gust amplitude where a gust front crosses the water, both times strength01. A
## storm's gusts roughen dark patches that run downwind (cat's paws); calm is untouched.
const CHOP_BASE := 0.15
const CHOP_GUST := 0.6


## 0 at the calm stop's speed, 1 at the storm's, clamped.
static func strength01(speed: float) -> float:
	return clampf((speed - CALM_SPEED) / (STORM_SPEED - CALM_SPEED), 0.0, 1.0)


## The smoke column's lean at mean wind [param speed] with gust amplitude [param gust_amp] and
## the local gust field [param gust] (0..1, WindModel.gust_at), before the motion scale.
static func smoke_lean(speed: float, gust_amp: float, gust: float) -> float:
	var base := lerpf(SMOKE_LEAN_CALM, SMOKE_LEAN_STORM, strength01(speed))
	return minf(base * (1.0 + SMOKE_GUST * gust_amp * (gust - SMOKE_GUST_REST)), SMOKE_LEAN_MAX)


## The column's lean with the player's [param motion] scale: the old [param still_lean] at 0,
## the wind's [param wind_lean] at 1.
static func smoke_lean_at(still_lean: float, wind_lean: float, motion: float) -> float:
	return lerpf(still_lean, wind_lean, clampf(motion, 0.0, 1.0))


## The column's lean direction (unit, map XZ): the map's own [param still_dir] at motion 0,
## the wind's [param wind_dir] at 1, the wind's when the two cancel out.
static func smoke_dir_at(still_dir: Vector2, wind_dir: Vector2, motion: float) -> Vector2:
	var mixed := still_dir.lerp(wind_dir, clampf(motion, 0.0, 1.0))
	if mixed.length_squared() < 1e-6:
		return wind_dir.normalized() if wind_dir.length_squared() > 1e-8 else Vector2.RIGHT
	return mixed.normalized()


## A fire event's drift (horizontal, metres a second) under the local [param wind]
## (Wind.wind_at, gusts in its speed): the event's own [param still_drift] at motion 0,
## downwind at EVENT_DRIFT_CALM..EVENT_DRIFT_STORM at 1.
static func event_drift(still_drift: Vector3, wind: Vector3, motion: float) -> Vector3:
	var flat := Vector3(wind.x, 0.0, wind.z)
	var speed := flat.length()
	if speed < 1e-4:
		return still_drift
	var blown := flat / speed * lerpf(EVENT_DRIFT_CALM, EVENT_DRIFT_STORM, strength01(speed))
	return still_drift.lerp(blown, clampf(motion, 0.0, 1.0))


## The drift (metres a second) a dust blob takes from the local [param wind], scaled by the
## player's [param motion] (0: none).
static func dust_drift(wind: Vector3, motion: float) -> Vector3:
	var flat := Vector3(wind.x, 0.0, wind.z) * DUST_SHARE
	return flat.limit_length(DUST_MAX) * clampf(motion, 0.0, 1.0)


## The factor on the water ripples' slope at mean wind [param speed], gust amplitude
## [param gust_amp] and the local gust field [param gust] (0..1), with the player's
## [param motion] scale: 1 at calm and at motion 0.
static func chop_factor(speed: float, gust_amp: float, gust: float, motion: float) -> float:
	var rough := CHOP_BASE + CHOP_GUST * gust_amp * clampf(gust, 0.0, 1.0)
	return 1.0 + clampf(motion, 0.0, 1.0) * strength01(speed) * rough
