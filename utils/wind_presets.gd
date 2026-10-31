class_name WindPresets
extends RefCounted

## The wind preset table (docs/systems/wind.md section 2.5). Presets are named stops on the
## one strength dial (WeatherSettings.wind_intensity, 0..1); between stops every column
## interpolates linearly, the ripple eased so it fades in late. Start values, tuned in the
## wind_a render round (docs/systems/wind.md "Phase (a) as built").

## The direction the wind blows toward when a level sets none, the one place it is defined:
## toward (0.707, 0, -0.707), the direction the weather particles always used (owner,
## 2026-10-30, wind_b: a lateral component, so rain slant and gusts read against the camera and
## the plants). Radians on (x, z), 0 = +x, 90 degrees = +z.
const DEFAULT_DIR_ANGLE := -PI * 0.25

## Preset name -> its strength on the dial.
const STRENGTH := {"calm": 0.0, "breezy": 0.33, "windy": 0.66, "storm": 1.0}

## The presets in the order the Weather pane's chips show them.
const PRESET_ORDER: Array[String] = ["calm", "breezy", "windy", "storm"]
## How close a strength must be to a preset's stop for the chip to show as picked.
const PRESET_TOLERANCE := 0.02
## The largest wind seed (WeatherSettings stores it as a float, exact to 2^24).
const SEED_MAX := 0xFFFFFF

## One row per stop: [strength, speed m/s, gust amp, ripple, veer amp rad, veer period s,
## sway scale].
const STOPS: Array = [
	[0.0, 1.5, 0.35, 0.0, 0.0, 200.0, 1.0],
	[0.33, 4.0, 0.55, 0.0, 0.10, 150.0, 1.5],
	[0.66, 8.0, 0.75, 0.25, 0.20, 110.0, 2.2],
	[1.0, 14.0, 1.0, 0.70, 0.35, 80.0, 3.2],
]

const COL_STRENGTH := 0
const COL_SPEED := 1
const COL_GUST := 2
const COL_RIPPLE := 3
const COL_VEER_AMP := 4
const COL_VEER_PERIOD := 5
const COL_SWAY := 6


## The default direction as a unit vector on the map plane (y = 0).
static func default_direction() -> Vector3:
	return Vector3(cos(DEFAULT_DIR_ANGLE), 0.0, sin(DEFAULT_DIR_ANGLE))


## The default direction in degrees as wind_direction_deg would spell it (0 = +x, 90 = +z,
## wrapped into 0..360 so it is not the "default" sentinel below 0).
static func default_direction_deg() -> float:
	return fposmod(rad_to_deg(DEFAULT_DIR_ANGLE), 360.0)


## The state for [param strength] (clamped 0..1). [param direction_deg] below 0 means the
## default direction; otherwise degrees on (x, z), 0 = +x, 90 = +z.
static func state_for(strength: float, direction_deg: float, seed_id: int) -> WindState:
	var angle := DEFAULT_DIR_ANGLE if direction_deg < 0.0 else deg_to_rad(direction_deg)
	var row := row_at(clampf(strength, 0.0, 1.0))
	return WindState.make(
		angle,
		row[COL_SPEED],
		row[COL_GUST],
		row[COL_RIPPLE],
		row[COL_VEER_AMP],
		row[COL_VEER_PERIOD],
		row[COL_SWAY],
		seed_id
	)


## The interpolated table row at [param strength] (0..1).
static func row_at(strength: float) -> Array:
	var last := STOPS.size() - 1
	for i in range(last):
		var lo: Array = STOPS[i]
		var hi: Array = STOPS[i + 1]
		if strength <= float(hi[COL_STRENGTH]) or i == last - 1:
			var span := float(hi[COL_STRENGTH]) - float(lo[COL_STRENGTH])
			var u := clampf((strength - float(lo[COL_STRENGTH])) / span, 0.0, 1.0)
			var row: Array = []
			for c in range(lo.size()):
				var k := smoothstep(0.0, 1.0, u) if c == COL_RIPPLE else u
				row.append(lerpf(float(lo[c]), float(hi[c]), k))
			row[COL_STRENGTH] = strength
			return row
	return (STOPS[last] as Array).duplicate()


## Strength of a named preset, or -1.0 for an unknown name.
static func strength_of(preset_name: String) -> float:
	return float(STRENGTH.get(preset_name.to_lower(), -1.0))


## The preset whose stop [param strength] sits on (within PRESET_TOLERANCE), or "" between stops
## (the strength slider was dragged to a custom value).
static func name_for(strength: float) -> String:
	for preset_name in PRESET_ORDER:
		if absf(strength - float(STRENGTH[preset_name])) <= PRESET_TOLERANCE:
			return preset_name
	return ""


## The plain-words tooltip of a preset chip: what it does to the plants and the weather.
static func preset_tooltip(preset_name: String) -> String:
	var strength := strength_of(preset_name)
	if strength < 0.0:
		return ""
	var row := row_at(strength)
	var words := (
		"%s: wind of about %d metres a second. Plants lean %s, cloth and sails move to match, "
		+ "and rain and snow slant with it."
	)
	return (
		words % [preset_name.capitalize(), int(round(float(row[COL_SPEED]))), _lean_words(strength)]
	)


## A new seed for the gust pattern, from [param entropy] (any int, the pane's random draw): a
## whole number in 1..SEED_MAX that differs from [param current] (0 and the current seed are
## never returned, so the re-roll always changes the pattern).
static func reroll_seed(current: float, entropy: int) -> float:
	var drawn := 1 + posmod(entropy, SEED_MAX)
	if float(drawn) == current:
		drawn = 1 + posmod(drawn, SEED_MAX)
	return float(drawn)


static func _lean_words(strength: float) -> String:
	if strength < 0.2:
		return "only a little"
	if strength < 0.5:
		return "gently"
	if strength < 0.8:
		return "clearly"
	return "hard"


## A state a fraction [param u] of the way from [param a] to [param b] (direction by the
## short way round). The seed follows [param b].
static func blend(a: WindState, b: WindState, u: float) -> WindState:
	return WindState.make(
		lerp_angle(a.dir_angle, b.dir_angle, u),
		lerpf(a.speed, b.speed, u),
		lerpf(a.gust_amp, b.gust_amp, u),
		lerpf(a.gust_ripple, b.gust_ripple, u),
		lerpf(a.veer_amp, b.veer_amp, u),
		lerpf(a.veer_period, b.veer_period, u),
		lerpf(a.sway_scale, b.sway_scale, u),
		b.seed_id
	)


## Whether two states are close enough that a blend between them is finished.
static func near(a: WindState, b: WindState) -> bool:
	return (
		absf(angle_difference(a.dir_angle, b.dir_angle)) < 0.002
		and absf(a.speed - b.speed) < 0.01
		and absf(a.gust_amp - b.gust_amp) < 0.002
		and absf(a.gust_ripple - b.gust_ripple) < 0.002
		and absf(a.veer_amp - b.veer_amp) < 0.001
		and absf(a.sway_scale - b.sway_scale) < 0.004
		and a.seed_id == b.seed_id
	)
