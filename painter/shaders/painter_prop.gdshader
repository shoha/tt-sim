shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted furnishing (a settlement prop under the Painted look)
 * ============================================================
 *
 * The street furniture of a dressed village (AuthoredSettlements: crates, barrels, carts, stalls,
 * wells, signposts, lamp posts, haystacks, laundry, benches ...) in the sheet's colours, instead of
 * Classic's saturated vertex colours. A prop's parts keep the colour procgen painted them from the
 * prop's own palette (one tone of wood, hay, accent, stone and cloth drawn per seed), and that
 * paint says which of eight sheet ramps a vertex takes (prop_tone: wood the timber's, hay the
 * thatch's, a red, orange or pink paint the clay, a green the turf, a blue, teal or violet the
 * slate, a cream or white the plaster, a grey the wall stone), so winter, dusk and grimdark tone a
 * village's props as they tone its houses, and a market is still red, blue, green and gold cloth
 * over honey wood. How light or dark the paint is picks the ramp's variant (the sheet's two
 * lightnesses of each role), so two barrels are never the same brown; broad soft patches and a few
 * soft brush streaks break each part's one tone into a few dabs, a fold line gives the edges a
 * confident ink, and in winter what faces up wears the roof snow's ramp in a scalloped cap.
 *
 * The selector light of the plants and buildings (painter_selector, painter_structure): ALBEDO
 * white, the ambient off, light() picks the shade, middle or lit colour from N.L and the sun's
 * ATTENUATION, so a prop reads tt-sim's one directional shadow map. Seen from both sides (a
 * single-sided cloth or a plank), the normal turned to the eye's side. No fragment is ever cut
 * away: a prop is a handful of boxes, so a scalloped outline would only chew its corners.
 *
 * Cost: two 3D value noises and one streak noise a fragment, no texture reads.
 *
 * MANAGED BY: PainterVillage (painter/painter_village.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

// LINEAR [shade0, mid0, lit0, shade1, mid1, lit1] for each of the eight tones: 0 timber, 1 wall
// stone, 2 thatch, 3 clay, 4 turf, 5 slate, 6 plaster, 7 spare (the thatch's again).
uniform vec3 ramps[48];
// The share of the up faces under snow (the sheet's roof-snow) and the snow's LINEAR [shade, mid,
// lit].
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
// The N.L where the shade, middle and lit steps meet (sheet tone-lo, tone-hi).
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
// How far a cast shadow steps a face into its shade colour.
uniform float cast_amount = 0.94;
// -1: the tone comes from the paint; else every vertex takes this tone (a stone part, a hay part).
uniform int force_tone = -1;
// The patches (1/m, how much of them shows), the streaks (1/m) and the fold line's strength.
uniform float patch_freq = 1.7;
uniform float patch_mix = 0.7;
uniform float streak_freq = 2.6;
uniform float ink = 0.4;
// How much of a vertex's own lightness picks the ramp's variant (the rest is the patches').
uniform float paint_mix = 0.65;

varying vec3 v_wp;
varying vec3 v_wn;
varying flat int v_tone;
varying flat float v_paint;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

// The sheet ramp a part's paint takes (the paint as the recipe wrote it, sRGB-like numbers).
int prop_tone(vec3 c) {
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float sat = hi > 0.001 ? (hi - lo) / hi : 0.0;
	if (sat < 0.18) {
		return hi > 0.85 ? 6 : 1;
	}
	float d = max(hi - lo, 0.001);
	float h;
	if (hi == c.r) {
		h = mod((c.g - c.b) / d, 6.0);
	} else if (hi == c.g) {
		h = (c.b - c.r) / d + 2.0;
	} else {
		h = (c.r - c.g) / d + 4.0;
	}
	h *= 60.0;
	// Wood: the honey and brown of oak boards.
	if (h >= 18.0 && h < 36.0 && sat < 0.66 && hi < 0.88) {
		return 0;
	}
	// Hay, straw and gold.
	if (h >= 36.0 && h < 65.0) {
		return 2;
	}
	if (h >= 65.0 && h < 165.0) {
		return 4;
	}
	if (h >= 165.0 && h < 330.0) {
		return 5;
	}
	return 3;
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_tone = force_tone >= 0 ? force_tone : prop_tone(COLOR.rgb);
	// 0 for a dark paint, 1 for a light one (oak runs about 0.62 to 0.86, hay and cloth above).
	v_paint = clamp((max(COLOR.r, max(COLOR.g, COLOR.b)) - 0.6) / 0.32, 0.0, 1.0);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n = normalize(v_wn);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 wp = v_wp;
	float pn = mix(p_noise(wp * patch_freq + 7.0), p_noise(wp * patch_freq * 3.1 + 21.0), 0.3);
	float patch = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix);
	float variant = mix(patch, v_paint, paint_mix);
	// Soft streaks along a part's grain: the wood's, and a cloth's folds (a dab lighter or darker).
	float streak = be_cut(vec2(wp.y * streak_freq * 0.6, (wp.x + wp.z) * streak_freq * 0.9 + wp.y * 0.2));
	float dark = max(-streak, 0.0) * 0.14;
	float light = max(streak, 0.0) * 0.16;
	// The fold line: where the shading normal turns within a pixel (a box's edge, a lid's lip).
	dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	// Snow on what faces up (winter): a scalloped cap, not a blanket.
	float cover = 0.0;
	if (snow > 0.0) {
		float cap = n.y + (p_noise(wp * 5.0 + 9.0) - 0.5) * 0.35;
		cover = smoothstep(0.46, 0.52, cap) * clamp(snow * 2.2, 0.0, 1.0);
	}
	dark = clamp(dark * (1.0 - cover * 0.8), 0.0, 0.7);
	light = clamp(light * (1.0 - cover * 0.8), 0.0, 0.6);
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	shd = mix(shd, snow_ramp[0], cover);
	mid = mix(mid, snow_ramp[1], cover);
	lit = mix(lit, snow_ramp[2], cover);
	vec3 deep = shd * 0.82;
	f_shd = mix(mix(shd, deep, dark), mid, light * 0.5);
	f_mid = mix(mix(mid, shd, dark), lit, light * 0.6);
	f_lit = mix(mix(lit, mid, dark), lit * 1.06, light);
	f_n = n;
	f_wob = p_noise(wp * 1.7 + 5.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.12;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.01, tone_hi + 0.01, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
