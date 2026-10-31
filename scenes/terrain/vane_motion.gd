class_name VaneMotion
extends Node3D

## A weathervane's pivot (topic wind_c, 2026-10-30): this node stands at the vane's pole and carries
## the shaft, arrow and tail meshes (StructureVane cuts them out; AuthoredStructures.vane_node builds
## this). The arrow turns to point into the global wind (the Wind autoload), as a damped spring: a
## change of wind direction overshoots a little and settles, and the gusts push the target about a
## few degrees (StructureWind.vane_wobble). One yaw per frame, no mesh is rebuilt, and the node stops
## processing when its VisibleOnScreenNotifier3D leaves the screen. The player's wind motion scale
## (Wind.motion_scale(), 0 under reduce-animation) at 0 holds the vane in its built pose; the wobble
## is not scaled in between, since the pointing itself is the information.

## The direction the arrow points as built (horizontal, unit).
var built_tip := Vector3.FORWARD

## (yaw offset from the built pose, angular velocity).
var _state := Vector2.ZERO


## Sets the pivot up; the vane starts pointing into the wind of the moment, so it never swings in.
func setup(tip: Vector3) -> void:
	built_tip = tip
	var wind := _sample()
	_state = Vector2(target_of(tip, wind, _gust(), _motion()), 0.0)
	pose()
	set_process(true)


## The yaw the vane is pulled to for `wind` (blowing toward), a gust envelope `gust` 0..1 and
## motion scale `motion`: the turn that points `tip` into the wind plus the gust's wobble; 0 at
## motion 0 or in no wind.
static func target_of(tip: Vector3, wind: Vector3, gust: float, motion: float) -> float:
	if motion <= 0.0 or wind.length_squared() < 0.000001:
		return 0.0
	var toward := StructureWind.turn_between(tip, -wind)
	return StructureWind.wrap_angle(toward + StructureWind.vane_wobble(gust, wind.length()) * motion)


## Advances the spring by `delta` seconds for the given wind and poses the vane.
func step_wind(delta: float, wind: Vector3, gust: float, motion: float) -> void:
	if motion <= 0.0:
		_state = Vector2.ZERO
	else:
		_state = StructureWind.vane_step(_state, target_of(built_tip, wind, gust, motion), delta)
	pose()


func step(delta: float) -> void:
	step_wind(delta, _sample(), _gust(), _motion())


func pose() -> void:
	basis = Basis(Vector3.UP, _state.x)


## The yaw offset from the built pose, radians.
func yaw() -> float:
	return _state.x


func _process(delta: float) -> void:
	step(delta)


func on_screen_entered() -> void:
	set_process(true)


func on_screen_exited() -> void:
	set_process(false)


func _where() -> Vector3:
	return global_position if is_inside_tree() else position


func _sample() -> Vector3:
	return Wind.wind_at(_where())


func _gust() -> float:
	return WindModel.gust_at(Wind.state, _where(), Wind.clock())


func _motion() -> float:
	return Wind.motion_scale()
