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

## Azimuth (rotation around Y, degrees) sweeps a full 360 degrees over the day,
## matching a real sun/moon's apparent compass rotation (the Earth's rotation
## changes which direction the sun is in, not just how high) -- so shadows
## actually reverse direction between morning and evening instead of just
## changing length. Anchored (see KEYFRAMES below) so DEFAULT_TIME_OF_DAY
## (14.0) lands on 135 degrees, the value this game's fixed isometric camera
## was originally tuned against (see game_map.tscn's Camera3D transform --
## the camera never rotates, so existing/default-configured levels look
## unchanged by this anchoring).

## hour (0.0-24.0) -> {elevation_degrees, color, energy, azimuth_degrees}.
## 0.0 and 24.0 are both "night" (identical values) so time_of_day wraps
## seamlessly across midnight.
const KEYFRAMES = {
	0.0:
	{
		"elevation_degrees": -10.0,
		"color": Color(0.4, 0.5, 0.75),
		"energy": 0.15,
		"azimuth_degrees": 285.0
	},
	6.0:
	{
		"elevation_degrees": 5.0,
		"color": Color(1.0, 0.6, 0.35),
		"energy": 0.5,
		"azimuth_degrees": 15.0
	},
	12.0:
	{
		"elevation_degrees": 70.0,
		"color": Color(1.0, 0.98, 0.92),
		"energy": 1.1,
		"azimuth_degrees": 105.0
	},
	18.0:
	{
		"elevation_degrees": 5.0,
		"color": Color(1.0, 0.55, 0.3),
		"energy": 0.5,
		"azimuth_degrees": 195.0
	},
	24.0:
	{
		"elevation_degrees": -10.0,
		"color": Color(0.4, 0.5, 0.75),
		"energy": 0.15,
		"azimuth_degrees": 285.0
	},
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
	var azimuth: float = lerpf(lo["azimuth_degrees"], hi["azimuth_degrees"], f)
	var color: Color = lo["color"].lerp(hi["color"], f)
	var energy: float = lerpf(lo["energy"], hi["energy"], f)

	light.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	light.light_color = color
	light.light_energy = energy
