class_name WindState
extends RefCounted

## One wind, as a small immutable value (docs/systems/wind.md section 2.1). Built by
## WindPresets from a level's weather settings and read by WindModel; a change makes a new
## state and the Wind autoload blends from the old one. Never mutated after construction.

## Radians in the map plane: the direction the wind blows TOWARD, (cos, sin) on (x, z).
var dir_angle: float = -PI * 0.5
## Mean speed, m/s.
var speed: float = 1.5
## 0..1: how far gusts rise above and fall below the mean.
var gust_amp: float = 0.35
## 0..1: extra fast, short-wavelength ripple (storm only).
var gust_ripple: float = 0.0
## Radians: the slow swing of the direction about dir_angle.
var veer_amp: float = 0.0
## Seconds per veer cycle.
var veer_period: float = 200.0
## Multiplier on every plant's sway amplitude (1.0 = the look before the wind existed).
var sway_scale: float = 1.0
## Phases the veer and the gust fronts so two levels never share a wind. 0 = unphased.
var seed_id: int = 0


static func make(
	p_dir_angle: float,
	p_speed: float,
	p_gust_amp: float,
	p_gust_ripple: float,
	p_veer_amp: float,
	p_veer_period: float,
	p_sway_scale: float,
	p_seed_id: int
) -> WindState:
	var s := WindState.new()
	s.dir_angle = p_dir_angle
	s.speed = p_speed
	s.gust_amp = p_gust_amp
	s.gust_ripple = p_gust_ripple
	s.veer_amp = p_veer_amp
	s.veer_period = maxf(p_veer_period, 1.0)
	s.sway_scale = p_sway_scale
	s.seed_id = p_seed_id
	return s
