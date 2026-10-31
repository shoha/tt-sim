class_name MillMotion
extends Node3D

## A windmill's cap pivot (topic range_look, 2026-10-30; wind_c, 2026-10-30): this node stands at
## the tower's centre and carries the cap meshes; its child `wheel` stands at the hub and carries
## the sails. The cap turns to face into the global wind (the Wind autoload), clamped to a cone of
## 50 degrees about WIND_FROM, and the wheel turns about the axis from the centre to the hub at a
## speed that rises with the wind. Only two transforms change per frame, no mesh is rebuilt.
## StructureMill cuts the parts out; AuthoredStructures.mill_node builds this from a build's `mill`
## parts.
##
## The cone: the weather's own direction would put the sails edge-on to the default camera, where
## they vanish (the first render round, 2026-10-30), so the cap follows the wind only within
## StructureWind.MILL_CONE_RAD of WIND_FROM. The yaw and the speed ease toward the wind with a time
## constant of StructureWind.EASE_SECONDS, so a change of weather never pops. The player's wind
## motion scale (Wind.motion_scale(), 0 under the operating system's reduce-animation setting)
## scales the cap's offset from WIND_FROM and the sails' speed: at 0 the cap rests facing WIND_FROM
## and the sails stand still. Off screen the node stops processing (a VisibleOnScreenNotifier3D).

## The direction the wind comes from (horizontal) that the cap rests facing, and the centre of the
## cone: the sails face it, seen three-quarter on from the default camera, which looks along
## (-1, 0, -1).
const WIND_FROM := Vector3(0.2, 0.0, 1.0)
## The per-building spread of the sails' speed (a village's mills never turn in step).
const SPIN_SPREAD := 0.25

## The wheel pivot (at the hub); its transform carries the spin.
var wheel: Node3D = null
## The axis from the tower's centre to the hub as built, horizontal and unit (world frame).
var built_axis := Vector3.FORWARD
## This building's factor on the sails' speed, around 1.
var spin_speed := 1.0

var _spin := 0.0
## The cap's yaw when it faces WIND_FROM, and the eased offset from it.
var _facing := 0.0
var _offset := 0.0
## The eased sail speed, radians per second, before the per-building factor.
var _speed := 0.0
## The wind and motion scale of the last sample, and the seconds since it.
var _wind := Vector3.ZERO
var _motion_now := 1.0
var _age := 0.0


## Sets the pivots up. `seed_value` varies the speed per building. The cap and the sails start in
## the pose the wind asks for now, so a building that appears does not swing into place.
func setup(wheel_pivot: Node3D, axis: Vector3, seed_value: int) -> void:
	wheel = wheel_pivot
	built_axis = axis
	var unit := float(posmod(seed_value * 7919 + 13, 1000)) / 999.0
	spin_speed = 1.0 + (unit - 0.5) * 2.0 * SPIN_SPREAD
	_spin = unit * TAU
	_facing = facing_angle(axis, WIND_FROM)
	_wind = _sample()
	_motion_now = _motion()
	_age = unit * StructureWind.SAMPLE_SECONDS
	snap_to(_wind, _motion_now)
	set_process(true)


## The angle about +y that turns the horizontal direction `built` onto the horizontal `wanted`.
static func facing_angle(built: Vector3, wanted: Vector3) -> float:
	return StructureWind.turn_between(built, wanted)


## The cap's offset and the sails' speed that a wind of vector `wind` (blowing toward) asks for at
## motion scale `motion`: (offset radians, speed radians per second).
static func target_of(wind: Vector3, motion: float) -> Vector2:
	return Vector2(
		StructureWind.mill_cap_offset(wind, WIND_FROM) * motion,
		StructureWind.mill_speed(wind.length()) * motion
	)


## Takes the pose for `wind` and `motion` at once (no easing).
func snap_to(wind: Vector3, motion: float) -> void:
	var target := target_of(wind, motion)
	_offset = target.x
	_speed = target.y
	pose()


## Advances the animation by `delta` seconds for the global wind and poses the pivots.
func step(delta: float) -> void:
	# The wind is sampled every StructureWind.SAMPLE_SECONDS (the easing smooths between samples).
	_age += delta
	if _age >= StructureWind.SAMPLE_SECONDS:
		_age = 0.0
		_wind = _sample()
		_motion_now = _motion()
	step_wind(delta, _wind, _motion_now)


## Advances by `delta` seconds for a given wind vector and motion scale, easing the cap and the
## speed toward what that wind asks for.
func step_wind(delta: float, wind: Vector3, motion: float) -> void:
	var target := target_of(wind, motion)
	_offset = StructureWind.ease_angle(_offset, target.x, delta, StructureWind.EASE_SECONDS)
	_speed = StructureWind.ease_toward(_speed, target.y, delta, StructureWind.EASE_SECONDS)
	_spin = fposmod(_spin + _speed * spin_speed * delta, TAU)
	pose()


## Poses the pivots for the current spin and cap offset.
func pose() -> void:
	basis = Basis(Vector3.UP, _facing + _offset)
	if wheel != null:
		wheel.basis = Basis(built_axis, _spin)


## The wheel's spin so far, radians in [0, TAU).
func spin() -> float:
	return _spin


## The cap's eased offset from WIND_FROM, radians.
func cap_offset() -> float:
	return _offset


## The sails' eased speed, radians per second, with the building's factor.
func spin_rate() -> float:
	return _speed * spin_speed


func _process(delta: float) -> void:
	step(delta)


func on_screen_entered() -> void:
	set_process(true)


func on_screen_exited() -> void:
	set_process(false)


func _sample() -> Vector3:
	return Wind.wind_at(global_position if is_inside_tree() else position)


func _motion() -> float:
	return Wind.motion_scale()
