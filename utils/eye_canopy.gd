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
## - the EYE LIGHT: at street level the camera sees a crown's underside and its far side against
##   the sun, which the orbit view looking down never shows, and the painted ramp's shade end
##   left them near black (eyelook, 2026-11-02). In the eye's own pass a tree's painted card
##   lifts its shade end to SHADE_FLOOR of its lit tone (eye_shade), keeps all of its ambient,
##   and glows warm where the sun shines through it toward the eye (back_glow); bark and plain
##   cards gain BARK_LIFT of their albedo. Grass and the orbit view are untouched.
## - the NEAR GRASS: a grass tuft seen from street level fills the lower third of the frame as one
##   flat, full-sun slab (neon lime on the meadow, mustard cut-outs on the savanna). Within
##   GRASS_NONE_M of the eye the tufts thin out tuft by tuft (the dropped ones shrink into their
##   foot), take GRASS_DESAT of their own grey, deepen from a cool dark foot (GRASS_FOOT) to a
##   tip a little under their own value (a darker foreground frames the view, the way a painted
##   one does; a paler one read as frost, eyegrass round 1), taper at the tip and step their value
##   per tuft, all of it in full inside GRASS_FULL_M.
##   wind_foliage_main.gdshaderinc carries it, keyed on the `eye_grass` global (the map scale in
##   the eye view, CanopyFade.eye_grass_enabled); the orbit view's grass is untouched.
##
## Distances are in metres at map scale 1; the eye view scales them by the map's scale (the same
## factor as its 1.6 m eye height), passed as `scale`.

## The near fade: full inside NEAR_FULL_M of the eye, none from NEAR_NONE_M out.
const NEAR_FULL_M := 1.2
const NEAR_NONE_M := 4.0
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
## The eye light: the share of a painted card's lit tone its shade end keeps at the eye.
const SHADE_FLOOR := 0.3
## The back glow rises from GLOW_START to GLOW_FULL of dot(view ray, direction to the sun).
const GLOW_START := 0.1
const GLOW_FULL := 0.85
## The warm light through a leaf (linear rgb), the shader's CANOPY_EYE_GLOW.
const GLOW_COLOR := Vector3(0.9, 1.0, 0.35)
## The share of its albedo bark and plain cards add as emission at the eye.
const BARK_LIFT := 0.35
## The near grass: in full inside GRASS_FULL_M of the eye, none from GRASS_NONE_M out.
const GRASS_FULL_M := 1.5
const GRASS_NONE_M := 9.0
## At full nearness tufts whose key is under GRASS_THIN are thinned: gone below
## GRASS_THIN - GRASS_THIN_BAND, shrinking into their foot across the band.
const GRASS_THIN := 0.85
const GRASS_THIN_BAND := 0.15
## The thinning follows nearness to this power (under 1: it bites earlier, mid-range, than a
## straight ramp; eyegrass2 thinned the dense meadow harder).
const GRASS_THIN_CURVE := 0.7
## Warm blades (red over green: dry gold, straw) gain GRASS_WARM_SAT of saturation instead of
## losing GRASS_DESAT, and take a warmer foot and a glowing tip (eyegrass2: the green-biased
## constants turned the savanna's gold to dusty tan).
const GRASS_WARM_SAT := 0.05
const GRASS_WARM_FOOT := Vector3(0.74, 0.6, 0.5)
const GRASS_WARM_TIP := Vector3(1.04, 1.0, 0.86)
## The share of a near tuft's colour that goes to its own grey (Rec. 709 luma, linear). Kept
## small: in linear space the grey of a lime or a mustard is light, and 0.45 turned them milky.
const GRASS_DESAT := 0.18
## The near tuft's shade at its foot (cool and dark) and its tip.
const GRASS_FOOT := Vector3(0.5, 0.58, 0.62)
const GRASS_TIP := 0.88
## Each near tuft's value steps by up to this much either way, from its key.
const GRASS_JITTER := 0.12
## How much alpha a near tuft loses at its tip (from 0.55 of its height up), so it tapers.
const GRASS_TAPER := 0.5


## How much of the leaf cards at `distance` from the eye drop out, 0 to 1: 1 inside the full
## radius, falling to 0 at the outer one. `scale` is the map scale (at most 0 reads as 1).
static func near_fade(distance: float, scale: float = 1.0) -> float:
	var s := scale if scale > 0.0 else 1.0
	return 1.0 - smoothstep(NEAR_FULL_M * s, NEAR_NONE_M * s, distance)


## How near a grass tuft whose origin is `distance` (horizontal) from the eye is, 0 to 1: 1 inside
## GRASS_FULL_M, 0 from GRASS_NONE_M. `scale` is the map scale (at most 0 reads as 1).
static func grass_near(distance: float, scale: float = 1.0) -> float:
	var s := scale if scale > 0.0 else 1.0
	return 1.0 - smoothstep(GRASS_FULL_M * s, GRASS_NONE_M * s, distance)


## The scale a tuft with key `key` (0 to 1) keeps at nearness `near`: 1 at nearness 0, 0 for a
## key under the thinning less its band.
static func grass_keep(key: float, near: float) -> float:
	var thin := GRASS_THIN * pow(near, GRASS_THIN_CURVE)
	return smoothstep(thin - GRASS_THIN_BAND, thin, key)


## The near grass colour of linear albedo `albedo` at height fraction `h` (0 foot, 1 tip) of a
## tuft with key `key` at nearness `near`; `albedo` itself at nearness 0.
static func grass_albedo(albedo: Vector3, h: float, key: float, near: float) -> Vector3:
	var luma := albedo.dot(Vector3(0.2126, 0.7152, 0.0722))
	var warm := smoothstep(0.0, 0.15, (albedo.x - albedo.y) / maxf(albedo.x, 0.01))
	var g := albedo.lerp(Vector3.ONE * luma, lerpf(GRASS_DESAT, -GRASS_WARM_SAT, warm))
	var foot := GRASS_FOOT.lerp(GRASS_WARM_FOOT, warm)
	var tip := (Vector3.ONE * GRASS_TIP).lerp(GRASS_WARM_TIP, warm)
	g *= foot.lerp(tip, smoothstep(0.0, 1.0, h))
	g *= 1.0 + GRASS_JITTER * (fposmod(key * 7.13 + 0.37, 1.0) * 2.0 - 1.0)
	g = Vector3(maxf(g.x, 0.0), maxf(g.y, 0.0), maxf(g.z, 0.0))
	return albedo.lerp(g, near)


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


## The shade end of a painted card's sun ramp at the eye, from its own `shade` and `lit` tones
## (foliage_paint_shade and foliage_paint_lit): each channel at least SHADE_FLOOR of the lit one,
## so the hue of the lit tone carries into the shade and a darker shade never goes below it.
static func eye_shade(shade: Vector3, lit: Vector3) -> Vector3:
	return shade.max(lit * SHADE_FLOOR)


## How much a card glows with the sun behind it, 0 to 1, from `toward_sun`: the dot of the unit
## view ray (camera to card) with the unit direction toward the sun. 0 side-on or with the sun
## behind the eye, 1 looking into it.
static func back_glow(toward_sun: float) -> float:
	return smoothstep(GLOW_START, GLOW_FULL, toward_sun)


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
