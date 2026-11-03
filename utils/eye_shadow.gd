class_name EyeShadow
extends RefCounted

## The sun's shadow max distance at the eye view (pure maths; LevelEnvironmentManager applies it).
##
## The orthographic views fit the distance to the top edge of the screen (far_ground_depth). A
## perspective eye at 1.6 m sees to the horizon, so that fit finds no ground at most pitches and
## leaves the floor (100 m), which loses the shadows of everything past it: the farthest ground
## seen from a spot on a map is 105 m (150 m map) to 180 m (250 m map) (shadow sweep, 2026-11-02).
## So the eye fits to how far the map reaches from where it stands instead: the farthest corner of
## the map's box, in the horizontal, whatever way it faces. It must not depend on the yaw: turning
## would then move the cascade splits and slide every shadow edge. Walking changes it by steps
## (STEP), so the splits hold still between them.
##
## The distance is capped at max_distance x the map's scale. The cap trades near shadow sharpness
## for far shadows (four cascades share the distance), and was chosen from full-size eye frames
## (docs/lighting-and-environment.md, "Street level").

## The cap, in metres at map scale 1, and the value a probe may change in a run.
const MAX_DISTANCE: float = 200.0
## Quantum of the fitted distance, metres.
const STEP: float = 10.0

static var max_distance: float = MAX_DISTANCE
## Probes only: when above 0, distance() returns this instead of the fit (the fit is the 100 m
## floor on any map under about 300 ft, so a probe cannot see a longer distance otherwise).
static var forced_distance: float = 0.0


## Horizontal distance from `eye` to the farthest corner of `bounds` (world space); 0 for an
## empty box.
static func far_reach(eye: Vector3, bounds: AABB) -> float:
	if not (bounds.has_volume() or bounds.has_surface()):
		return 0.0
	var deepest := 0.0
	for i in 8:
		var corner := bounds.get_endpoint(i)
		deepest = maxf(deepest, Vector2(corner.x - eye.x, corner.z - eye.z).length())
	return deepest


## The max distance for an eye at `eye` in a map whose world box is `bounds` and whose scale is
## `map_scale`: the shadow distance that keeps the fade band beyond the farthest ground, rounded
## up to STEP, never below the floor (LevelEnvironmentManager.SUN_SHADOW_MAX_DISTANCE) nor above
## the cap.
static func distance(eye: Vector3, bounds: AABB, map_scale: float) -> float:
	if forced_distance > 0.0:
		return forced_distance
	var floor_m := LevelEnvironmentManager.SUN_SHADOW_MAX_DISTANCE
	var wanted := LevelEnvironmentManager.shadow_distance_for_depth(far_reach(eye, bounds))
	wanted = ceilf(wanted / STEP) * STEP
	return clampf(wanted, floor_m, maxf(floor_m, max_distance * map_scale))
