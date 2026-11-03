class_name EyeCanopy
extends RefCounted

## The eye view's foliage maths, pure statics (CanopyFade publishes them, the shaders mirror
## them term for term: wind_foliage_include.gdshaderinc apply_canopy_fade and
## token_ghost.gdshader).
##
## At the orbit camera the fade is told how far the camera is by the orthographic size. A
## perspective camera at street level has no such number (Camera3D.size goes stale), and what
## matters there is the distance from the eye:
##
## - the NEAR FADE: a leaf card or a limb inside NEAR_FULL_M of the eye is gone and one inside
##   NEAR_NONE_M is thinned, card by card (the same per-card key as the canopy window), so a
##   crown a step away never becomes a solid green wall; a trunk is kept, and a crown further
##   away stays whole. It does not depend on the Settings "Canopy fade" switch.
## - the FOCUS WINDOW: the existing canopy window (CanopyFade.strength and shape, off unless the
##   Settings switch is on) centred on a focus point, with the eye-to-focus distance standing in
##   for the orthographic size (window_size).
## - the GHOST RANGE: a token ghost further than GHOST_START_M fades out, gone by GHOST_END_M.
##
## Distances are in metres at map scale 1; the eye view scales them by the map's scale (the same
## factor as its 1.6 m eye height), passed as `scale`.

## The near fade: full inside NEAR_FULL_M of the eye, none from NEAR_NONE_M out.
const NEAR_FULL_M := 0.7
const NEAR_NONE_M := 2.6
## The ghost's range fade starts and ends here.
const GHOST_START_M := 30.0
const GHOST_END_M := 50.0
## The focus point when the centre ray meets no ground: this far ahead of the eye.
const FOCUS_AHEAD_M := 8.0
## The eye-to-focus distance at which the focus window is at its home (play) strength, the
## distance an orthographic size of 13.85 m stands for at a 60 degree lens.
const FOCUS_HOME_M := 12.0
## A shader only fades a fragment from the camera's own pass: the fragment's inverse view matrix
## puts the camera within this distance (metres) of the published eye.
const PASS_TOLERANCE_M := 0.25


## How much of the leaf cards at `distance` from the eye drop out, 0 to 1: 1 inside the full
## radius, falling to 0 at the outer one. `scale` is the map scale (at most 0 reads as 1).
static func near_fade(distance: float, scale: float = 1.0) -> float:
	var s := scale if scale > 0.0 else 1.0
	return 1.0 - smoothstep(NEAR_FULL_M * s, NEAR_NONE_M * s, distance)


## The ghost's opacity factor at `distance` from the eye: 1 up to the start, 0 from the end.
## `scale` 0 (not the eye view) leaves it at 1.
static func ghost_weight(distance: float, scale: float) -> float:
	if scale <= 0.0:
		return 1.0
	return 1.0 - smoothstep(GHOST_START_M * scale, GHOST_END_M * scale, distance)


## The focus point of an eye looking along unit `forward` from `origin`: the ground hit of the
## centre ray when there is one (`has_hit`), else a point FOCUS_AHEAD_M ahead.
static func focus_point(
	origin: Vector3, forward: Vector3, has_hit: bool, hit: Vector3, scale: float = 1.0
) -> Vector3:
	if has_hit:
		return hit
	var s := scale if scale > 0.0 else 1.0
	return origin + forward * FOCUS_AHEAD_M * s


## The orthographic size the focus window should read for an eye `distance` from its focus under
## a lens of `fov_deg` (vertical), in map metres: the height the view spans at that distance.
## Equal to Camera3D.size of an orthographic view framing the same stretch.
static func window_size(distance: float, fov_deg: float, scale: float = 1.0) -> float:
	var s := scale if scale > 0.0 else 1.0
	return 2.0 * (distance / s) * tan(deg_to_rad(clampf(fov_deg, 1.0, 170.0)) * 0.5)


## The window size at which the focus window is at home strength, for the same lens.
static func home_size(fov_deg: float) -> float:
	return window_size(FOCUS_HOME_M, fov_deg)


## True when the fragment's camera origin (`view_origin`, INV_VIEW_MATRIX's translation) is the
## published eye: the camera's own pass. The shadow pass sits at the light.
static func is_camera_pass(view_origin: Vector3, eye: Vector3) -> bool:
	return view_origin.distance_to(eye) < PASS_TOLERANCE_M


## Where a fragment at view-space `fragment` lies in the plane of a token at view-space `token`
## (both look down -Z, so a point in front of the token has the larger z), in the xy of that
## plane. Orthographic views keep the xy (the view rays are parallel); a perspective view scales
## it to the token's depth, so the offset is the real separation across the view ray the
## occlusion fade tests. Mirrors occlusion_fade_include.gdshaderinc.
static func token_plane_xy(fragment: Vector3, token: Vector3, perspective: bool) -> Vector2:
	var xy := Vector2(fragment.x, fragment.y)
	if perspective and fragment.z < -0.0001:
		xy *= token.z / fragment.z
	return xy
