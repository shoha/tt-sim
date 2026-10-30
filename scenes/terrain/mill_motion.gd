class_name MillMotion
extends Node3D

## A windmill's cap pivot (topic range_look, 2026-10-30): this node stands at the tower's centre and
## carries the cap meshes; its child `wheel` stands at the hub and carries the sails. The cap turns
## to face the wind (slowly swaying about it), the wheel turns about the axis from the centre to the
## hub. Only two transforms change per frame, no mesh is rebuilt. StructureMill cuts the parts out;
## AuthoredStructures.mill_node builds this from a build's `mill` parts.
##
## The wind: tt-sim has no global wind value (the weather renderer's wind particles use a fixed
## direction, (1, 0, -1), and the plants sway on their own shader parameters), so the cap faces a
## fixed wind and the wheel runs at a constant gentle speed, scaled a little per building. The
## weather's own direction is not used: it puts the wheel edge-on to the default camera (the first
## render round, 2026-10-30), where the sails vanish. Off screen the node stops processing (a
## VisibleOnScreenNotifier3D); with the operating system's reduce-animation setting
## (UiMotion.reduced) the wheel stands still and only the cap's facing is set.

## The direction the wind comes from (horizontal): the sails face it, seen three-quarter on from the
## default camera, which looks along (-1, 0, -1).
const WIND_FROM := Vector3(0.2, 0.0, 1.0)
## The wheel's turn, radians per second (about 22 s a turn), and the per-building spread.
const SPIN_RAD_S := 0.29
const SPIN_SPREAD := 0.25
## The cap's sway about the wind: amplitude (radians), angular speed (radians per second).
const SWAY_RAD := 0.12
const SWAY_RAD_S := 0.13

## The wheel pivot (at the hub); its transform carries the spin.
var wheel: Node3D = null
## The axis from the tower's centre to the hub as built, horizontal and unit (world frame).
var built_axis := Vector3.FORWARD
## The wheel's speed in radians per second, signed.
var spin_speed := SPIN_RAD_S
## Where in its sway this building starts, radians.
var sway_phase := 0.0

var _spin := 0.0
var _clock := 0.0
var _facing := 0.0


## Sets the pivots up. `seed_value` varies the speed and the sway start per building, so a village's
## mills never turn in step.
func setup(wheel_pivot: Node3D, axis: Vector3, seed_value: int) -> void:
	wheel = wheel_pivot
	built_axis = axis
	var unit := float(posmod(seed_value * 7919 + 13, 1000)) / 999.0
	spin_speed = SPIN_RAD_S * (1.0 + (unit - 0.5) * 2.0 * SPIN_SPREAD)
	sway_phase = unit * TAU
	_facing = facing_angle(axis, WIND_FROM)
	pose()
	set_process(not UiMotion.reduced())


## The angle about +y that turns the horizontal direction `built` onto the horizontal `wanted`.
static func facing_angle(built: Vector3, wanted: Vector3) -> float:
	var a := Vector3(built.x, 0.0, built.z)
	var b := Vector3(wanted.x, 0.0, wanted.z)
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return 0.0
	return a.normalized().signed_angle_to(b.normalized(), Vector3.UP)


## Advances the animation by `delta` seconds and poses the pivots.
func step(delta: float) -> void:
	_spin = fposmod(_spin + spin_speed * delta, TAU)
	_clock += delta
	pose()


## Poses the pivots for the current spin and sway.
func pose() -> void:
	basis = Basis(Vector3.UP, _facing + SWAY_RAD * sin(_clock * SWAY_RAD_S + sway_phase))
	if wheel != null:
		wheel.basis = Basis(built_axis, _spin)


## The wheel's spin so far, radians in [0, TAU).
func spin() -> float:
	return _spin


func _process(delta: float) -> void:
	step(delta)


func on_screen_entered() -> void:
	set_process(not UiMotion.reduced())


func on_screen_exited() -> void:
	set_process(false)
