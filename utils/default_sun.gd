class_name DefaultSun
extends RefCounted

## Computes DirectionalLight3D angle/color/energy for a given time-of-day
## (0.0-24.0), interpolating between hand-authored keyframes -- matching the
## existing convention of curated dictionaries (EnvironmentPresets
## .SKY_PRESETS/PRESETS) rather than a procedural formula, so each keyframe can
## be tuned independently. Time-of-day only drives the sun light itself; it
## never touches the separate ambient/Environment config (see
## LevelEnvironmentManager).

const DEFAULT_TIME_OF_DAY: float = 14.0

## Fixed azimuth (rotation around Y, degrees) so shadows fall toward the lower-
## right of the screen -- the standard isometric lighting convention -- given
## the game's fixed camera direction (see game_map.tscn's Camera3D transform).
## The camera never rotates, so one azimuth works for every level.
const AZIMUTH_DEGREES: float = 135.0

## hour (0.0-24.0) -> {elevation_degrees, color, energy}.
## 0.0 and 24.0 are both "night" (identical values) so time_of_day wraps
## seamlessly across midnight.
const KEYFRAMES = {
	0.0: {"elevation_degrees": -10.0, "color": Color(0.4, 0.5, 0.75), "energy": 0.15},
	6.0: {"elevation_degrees": 5.0, "color": Color(1.0, 0.6, 0.35), "energy": 0.5},
	12.0: {"elevation_degrees": 70.0, "color": Color(1.0, 0.98, 0.92), "energy": 1.1},
	18.0: {"elevation_degrees": 5.0, "color": Color(1.0, 0.55, 0.3), "energy": 0.5},
	24.0: {"elevation_degrees": -10.0, "color": Color(0.4, 0.5, 0.75), "energy": 0.15},
}

const _HOURS: Array[float] = [0.0, 6.0, 12.0, 18.0, 24.0]


## Configure [param light] for [param time_of_day] (clamped to 0.0-24.0).
## Interpolates elevation, color, and energy between the two nearest keyframes.
static func configure_directional_light(light: DirectionalLight3D, time_of_day: float) -> void:
	var t := clampf(time_of_day, 0.0, 24.0)

	var lo_hour := 0.0
	var hi_hour := 24.0
	for hour in _HOURS:
		if hour <= t:
			lo_hour = hour
		if hour >= t:
			hi_hour = hour
			break

	var lo: Dictionary = KEYFRAMES[lo_hour]
	var hi: Dictionary = KEYFRAMES[hi_hour]
	var span := hi_hour - lo_hour
	var f := 0.0 if span == 0.0 else (t - lo_hour) / span

	var elevation: float = lerpf(lo["elevation_degrees"], hi["elevation_degrees"], f)
	var color: Color = lo["color"].lerp(hi["color"], f)
	var energy: float = lerpf(lo["energy"], hi["energy"], f)

	light.rotation_degrees = Vector3(-elevation, AZIMUTH_DEGREES, 0.0)
	light.light_color = color
	light.light_energy = energy
