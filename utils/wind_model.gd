class_name WindModel
extends RefCounted

## The pure wind function (docs/systems/wind.md section 2.2): no node, no tree, no randomness
## beyond WindState.seed_id. The gust field here is the one wind_foliage_include.gdshaderinc
## evaluates on the GPU, term for term, so CPU consumers (particles, mills) and plants agree.

## Gust front wavelengths in metres (shader: k1, k2, and the storm ripple k3).
const WAVELENGTH_A := 12.0
const WAVELENGTH_B := 19.0
const WAVELENGTH_C := 7.0
## Front speeds, m/s. Constant on purpose: a preset change then never makes a phase jump.
const FRONT_SPEED := 3.0
const RIPPLE_SPEED := 9.0
## The unix time the wind clock counts from (2026-01-01 00:00 UTC).
const EPOCH_UNIX := 1767225600.0
## Gust amplitude of the calm preset; the shader scales a material's gust_strength by
## gust_amp / CALM_GUST_AMP so calm is the look before the wind existed.
const CALM_GUST_AMP := 0.35
## Shader cross-wind term and the second front's fixed phase offset.
const CROSS_K := 0.25
const B_OFFSET := 1.7


## The three front phases (radians, each wrapped on its own period in double precision) at
## wind-clock time [param t], as a Vector4 (a, b, c, spare). The GPU never sees a large time.
static func phases(t: float) -> Vector4:
	var ka := TAU / WAVELENGTH_A
	var kb := TAU / WAVELENGTH_B
	var kc := TAU / WAVELENGTH_C
	return Vector4(
		fposmod(t * ka * FRONT_SPEED, TAU),
		fposmod(t * kb * FRONT_SPEED * 0.8, TAU),
		fposmod(t * kc * RIPPLE_SPEED, TAU),
		0.0
	)


## The seed's phase offset in radians, 0 for the unphased seed 0.
static func seed_phase(state: WindState) -> float:
	return float(state.seed_id % 4096) / 4096.0 * TAU


## The veered direction angle at [param t].
static func direction_at(state: WindState, t: float) -> float:
	if state.veer_amp <= 0.0:
		return state.dir_angle
	var cycle := fposmod(t / state.veer_period, 1.0) * TAU + seed_phase(state)
	return state.dir_angle + state.veer_amp * sin(cycle)


## The unit wind direction on (x, z) at [param t], as a Vector2 (x, z).
static func direction_vec(state: WindState, t: float) -> Vector2:
	var a := direction_at(state, t)
	return Vector2(cos(a), sin(a))


## Gust envelope 0..1 at [param pos] (x and z) and time [param t]: the shader's wind_gust.
static func gust_at(state: WindState, pos: Vector3, t: float) -> float:
	var dir := direction_vec(state, t)
	var p := phases(t)
	var sp := seed_phase(state)
	var along := pos.x * dir.x + pos.z * dir.y
	var across := -pos.x * dir.y + pos.z * dir.x
	var ka := TAU / WAVELENGTH_A
	var kb := TAU / WAVELENGTH_B
	var kc := TAU / WAVELENGTH_C
	var wave := (
		0.55 * sin(along * ka - p.x + sp)
		+ 0.45 * sin(along * kb + across * CROSS_K - p.y + B_OFFSET + sp * 1.618)
	)
	wave += state.gust_ripple * 0.3 * sin(along * kc + across * 0.35 - p.z + 0.6 + sp * 2.414)
	return smoothstep(-0.2, 0.9, wave)


## The wind vector (m/s, y = 0) at [param pos] and time [param t]: the veered direction times
## the mean speed, raised inside a gust (by up to 0.4 * gust_amp) and lowered between them.
static func wind_at(state: WindState, pos: Vector3, t: float) -> Vector3:
	var dir := direction_vec(state, t)
	var g := gust_at(state, pos, t)
	var speed := state.speed * (1.0 + 0.67 * state.gust_amp * (g - 0.4))
	return Vector3(dir.x * speed, 0.0, dir.y * speed)


## The three global-uniform vec4s (wind_dir, wind_phase, wind_gust) for [param state] at
## [param t] with [param motion] the player's motion scale (0 stills every plant).
static func uniforms(state: WindState, t: float, motion: float) -> Array[Vector4]:
	var dir := direction_vec(state, t)
	return [
		Vector4(dir.x, dir.y, state.speed, state.sway_scale),
		phases(t),
		Vector4(state.gust_amp, state.gust_ripple, seed_phase(state), motion),
	]
