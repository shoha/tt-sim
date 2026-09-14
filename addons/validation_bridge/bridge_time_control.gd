class_name BridgeTimeControl
extends RefCounted

## Frame arithmetic for the validation bridge's deterministic time stepping.
##
## The bridge freezes game time by setting Engine.time_scale to 0.0, which stops physics ticks
## accumulating entirely and hands _process a delta of 0.0. Stepping restores the scale for an
## exact number of physics frames and then re-freezes, so a step advances the game by a fixed,
## repeatable amount of game time no matter how fast the host machine renders. Expressing steps in
## physics frames rather than wall-clock seconds is what makes them repeatable: the physics delta
## is fixed at 1.0 / Engine.physics_ticks_per_second, while a rendered frame's delta is not.

## Upper bound on a single step, to stop a mistyped duration from hanging the bridge for minutes.
## 6000 frames is 100 seconds of game time at the default 60 Hz tick rate.
const MAX_STEP_FRAMES: int = 6000


## Number of physics frames making up `seconds` of game time at `ticks_per_second`.
##
## Rounds to the nearest frame, but never rounds a positive duration down to zero: a caller asking
## for a slice shorter than one tick wants the game to advance, not to silently stand still.
static func frames_for_duration(seconds: float, ticks_per_second: int) -> int:
	if ticks_per_second <= 0 or seconds <= 0.0:
		return 0
	var frames := int(roundf(seconds * float(ticks_per_second)))
	return clampi(maxi(frames, 1), 1, MAX_STEP_FRAMES)


## Game time that `frames` physics frames represent at `ticks_per_second`.
static func duration_for_frames(frames: int, ticks_per_second: int) -> float:
	if ticks_per_second <= 0:
		return 0.0
	return float(frames) / float(ticks_per_second)
