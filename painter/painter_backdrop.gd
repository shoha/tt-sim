class_name PainterBackdrop
extends RefCounted

## The painted eye view's backdrop tones (card painter-eye-backdrop): the far hills, the near
## tree-line and the clouds painter_sky.gdshader draws at the eye (eye_on, set by EyeSky), every
## one drawn from the mood's own tones at the sun's elevation, so a dusk range is violet, a winter
## one snow under a pale sky and a grimdark one heavy, with no colour of its own. Pure:
## PainterScene sets the result on the painted sky's material at every take, beside the gradient's
## colours, so the backdrop follows the sun and the preset by the same events.
##
## The model is aerial perspective in the mood's air, mixed in OKLab. The near range is the ground
## a little into the haze, the middle range further in and on toward the sky, the far range the
## haze turned toward the sky and a step deeper (a blue range in a summer noon, a violet one at
## dusk). The near tree-line is the leaf tone a little into the haze and deeper; a sunlit top
## lifts toward the sun. A cloud's lit top is the horizon pulled toward the sun as far as the sun
## is bright (cream at noon, gold at dusk, a dim silver at night); its underside is the sky turned
## toward the mood's shade hue (`shade-hue`, the hue the painted shade leans to everywhere else).
## A grey sky is a clouded one: the share of the sky holding a bank grows as the sky's chroma
## falls (grimdark's overcast, winter's pale sky), so no mood needs a number of its own.

## How far each range is pulled into the haze (near, middle) and from there toward the sky
## (middle, far), the share of its lightness the near range keeps, and how much deeper the far
## range is than its mix (round 1: at 0.3 into the haze the near range was the foot tone, unread).
const NEAR_HAZE := 0.15
const NEAR_VALUE := 0.9
const MID_HAZE := 0.45
const MID_SKY := 0.2
const FAR_SKY := 0.5
const FAR_DEEPEN := 0.14
## The tree-line: its pull into the haze and the share of its lightness it keeps.
const CROWN_HAZE := 0.12
const CROWN_VALUE := 0.78
## A sunlit top: its pull from the near range toward the sun, and its lift.
const LIT_SUN := 0.4
const LIT_LIFT := 0.05
## A cloud's lit top: the pull from the horizon toward the sun at a full-energy sun, and its lift.
const CLOUD_SUN := 0.6
const CLOUD_LIFT := 0.04
## A cloud's underside: its lightness above the zenith's (the sky behind a bank is paler than
## the zenith), the share of the sky's chroma it keeps (plus a floor), and how far its hue turns
## toward the mood's shade hue (round 1: 0.9 of the chroma and 0.03 below read as a hard blue).
const SHADE_LIFT := 0.02
const SHADE_KEEP := 0.6
const SHADE_CHROMA := 0.01
const SHADE_TURN := 0.6
## The cloud cover at a grey sky and at a vivid one, and the sky chroma of each end.
const COVER_GREY := 0.85
const COVER_VIVID := 0.5
const CHROMA_GREY := 0.02
const CHROMA_VIVID := 0.08


## The backdrop's shader uniforms (painter_sky.gdshader's `eye` group colours and cloud_cover) for
## `mood` of the compiled `sheet` at a sun `elevation` degrees above the horizon.
static func uniforms(sheet: Dictionary, mood: String, elevation: float) -> Dictionary:
	var ground := PainterSheet.tone_lch(sheet, mood, "ground", elevation)
	var leaf := PainterSheet.tone_lch(sheet, mood, "leaf", elevation)
	var haze := PainterSheet.tone_lch(sheet, mood, "haze", elevation)
	var sky := PainterSheet.tone_lch(sheet, mood, "sky", elevation)
	var horizon := PainterSheet.tone_lch(sheet, mood, "horizon", elevation)
	var sun := PainterSheet.tone_lch(sheet, mood, "sun", elevation)
	var energy := clampf(PainterSheet.number(sheet, mood, "sun-energy", elevation), 0.0, 1.0)
	var shade_hue := PainterSheet.number(sheet, mood, "shade-hue", elevation)

	var near := mix(ground, haze, NEAR_HAZE)
	near.x *= NEAR_VALUE
	var mid := mix(mix(ground, haze, MID_HAZE), sky, MID_SKY)
	var far := mix(haze, sky, FAR_SKY)
	far.x -= FAR_DEEPEN
	var crown := mix(leaf, haze, CROWN_HAZE)
	crown.x *= CROWN_VALUE
	var lit := mix(near, sun, LIT_SUN)
	lit.x += LIT_LIFT

	var cloud_light := mix(horizon, sun, CLOUD_SUN * energy)
	cloud_light.x = minf(maxf(cloud_light.x, horizon.x) + CLOUD_LIFT * energy, 0.99)
	var turn := fposmod(shade_hue - sky.z + 180.0, 360.0) - 180.0
	var cloud_shade := Vector3(
		sky.x + SHADE_LIFT,
		sky.y * SHADE_KEEP + SHADE_CHROMA,
		fposmod(sky.z + turn * SHADE_TURN, 360.0)
	)
	var vivid := smoothstep(CHROMA_GREY, CHROMA_VIVID, sky.y)
	return {
		&"hill_far_color": PainterSheet.color_of_lch(far),
		&"hill_mid_color": PainterSheet.color_of_lch(mid),
		&"hill_near_color": PainterSheet.color_of_lch(near),
		&"crown_color": PainterSheet.color_of_lch(crown),
		&"hill_lit_color": PainterSheet.color_of_lch(lit),
		&"cloud_light_color": PainterSheet.color_of_lch(cloud_light),
		&"cloud_shade_color": PainterSheet.color_of_lch(cloud_shade),
		&"cloud_cover": lerpf(COVER_GREY, COVER_VIVID, vivid),
	}


## The OKLab mix of two OKLCH colours, as OKLCH (a near-grey end lends no hue).
static func mix(a: Vector3, b: Vector3, t: float) -> Vector3:
	var lab := PainterSheet.oklab_of(a).lerp(PainterSheet.oklab_of(b), t)
	var chroma := Vector2(lab.y, lab.z).length()
	return Vector3(lab.x, chroma, fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0))
