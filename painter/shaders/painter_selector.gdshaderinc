// The painted look's SELECTOR light for the scatter tt-sim draws from GLBs (bushes, ferns,
// grass, flowers, rocks, deadwood; docs/systems/painter.md "Surfaces"). The material is lit with
// the ambient off and ALBEDO white; light() takes N.L and the sun's ATTENUATION only to pick
// the sheet role's shade, middle or lit colour, so everything reads tt-sim's one directional
// shadow map and the sheet's colours reach the screen as written. The GLB's texture gives the
// cutout (and, on a flower, which pixels are petals); none of its colour is drawn.
//
// kind: 0 leaf mass (lit as one rounded form about the plant's middle), 1 grass (one flat tone,
// darker at the base), 2 solid (rock, wood, litter: its own normals, a noise-broken turn),
// 3 flower (the grass ramp on its green pixels, one of four flat accents on its petals by group).
// PainterSurfaces sets every uniform from the sheet (PainterTones.ramp and the sheet's numbers).
// Includers call selector_fragment() at the end of fragment() with the world position and
// normal, the instance origin and scale and the height fraction, and assign its outputs to the
// varyings f_n, f_variant, f_mul, f_wob and f_accent (a function other than fragment() may not
// write a varying).

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform int kind = 0;
// The role's ramp, LINEAR: two variants of shade, middle and lit.
uniform vec3 c_shade0 = vec3(0.1, 0.1, 0.2);
uniform vec3 c_mid0 = vec3(0.3);
uniform vec3 c_lit0 = vec3(0.6);
uniform vec3 c_shade1 = vec3(0.1, 0.1, 0.2);
uniform vec3 c_mid1 = vec3(0.3);
uniform vec3 c_lit1 = vec3(0.6);
// Flower petals: gold, rose, violet, white (LINEAR).
uniform vec3 accent[4];
// The N.L where the shade, middle and lit steps meet (sheet tone-lo, tone-hi).
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
// Thinning in groups: an instance is drawn where a slow world noise at its foot is above
// 1 - keep, so what stays stands in fewer, larger groups (keep 1 = everything).
uniform float keep = 1.0;
uniform float keep_freq = 0.2;
// The frequency (1/m) of the field that gives a group of flowers its colour.
uniform float group_freq = 0.1;
// False for ground cover: grass and flowers receive the shade of trees and buildings but cast
// none of their own (they collapse in the shadow pass).
uniform bool casts_shadow = true;
// The height of the selector's mesh in its own units (a leaf mass turns about its middle).
uniform float selector_height = 1.0;

varying vec3 f_n;
varying float f_variant;
varying float f_mul;
varying float f_wob;
varying float f_accent;

// The scale an instance at `origin` keeps: 0 when thinned away, else 1; 0 too in the shadow pass
// of ground cover.
float selector_keep(vec3 origin, bool shadow_pass) {
	if (shadow_pass && !casts_shadow) {
		return 0.0;
	}
	if (keep >= 0.999) {
		return 1.0;
	}
	float g = p_noise(vec3(origin.x * keep_freq, 2.0, origin.z * keep_freq) + 13.0);
	// The noise bunches round 0.5: stretched so `keep` is roughly the share kept.
	g = clamp((g - 0.5) * 1.8 + 0.5, 0.0, 1.0);
	return g < 1.0 - keep ? 0.0 : 1.0;
}

vec3 selector_pal(float tone, float variant) {
	float v = clamp(variant, 0.0, 1.0);
	float t = clamp(tone, 0.02, 0.98);
	vec3 s = mix(c_shade0, c_shade1, v);
	vec3 m = mix(c_mid0, c_mid1, v);
	vec3 l = mix(c_lit0, c_lit1, v);
	return t < 0.5 ? mix(s, m, t * 2.0) : mix(m, l, t * 2.0 - 1.0);
}

// The per-fragment choices light() reads: the normal it lights, the variant, the height shading,
// the wobble and (on a petal, else -1) the accent. `wp` is the fragment's world position, `tex`
// the GLB texture's sample.
void selector_fragment(vec3 wp, vec3 wn, vec3 origin, float scale, float h, vec4 tex,
		out vec3 n, out float variant, out float mul, out float wob, out float petal) {
	n = normalize(wn);
	// One variant per plant, in three steps, and a slow drift across the map.
	variant = floor(p_hash(floor(origin * 10.0)) * 3.0) * 0.5;
	variant = mix(variant, p_noise(origin * 0.12 + 40.0), 0.5);
	mul = 1.0;
	petal = -1.0;
	if (kind == 0) {
		// A leaf mass turns as one rounded form about its middle, not card by card.
		vec3 mid = origin + vec3(0.0, 0.45 * selector_height * scale, 0.0);
		n = normalize(mix(n * 0.25, normalize(wp - mid), 0.75));
		mul = mix(0.86, 1.0, smoothstep(0.0, 0.35, h));
	} else if (kind == 1 || kind == 3) {
		n = vec3(0.0, 1.0, 0.0);
		mul = mix(0.74, 1.0, smoothstep(0.0, 0.55, h));
		if (kind == 3 && tex.g - max(tex.r, tex.b) < 0.02) {
			// A petal: white where the texture is pale, else one colour per group of plants.
			float lo = min(tex.r, min(tex.g, tex.b));
			float grp = p_noise(vec3(origin.x * group_freq, 6.0, origin.z * group_freq) + 90.0);
			petal = lo > 0.55 ? 3.0 : (grp < 0.44 ? 0.0 : (grp < 0.58 ? 1.0 : 2.0));
			mul = 1.0;
		}
	} else {
		variant = mix(variant, p_noise(wp * 0.9 + 17.0), 0.5);
	}
	wob = p_noise(wp * 1.7 + 5.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.3;
		float t = 0.1 + 0.4 * smoothstep(tone_lo - 0.01, tone_lo + 0.01, x)
			+ 0.4 * smoothstep(tone_hi - 0.01, tone_hi + 0.01, x);
		vec3 col = selector_pal(t, f_variant + (t - 0.45) * 0.3);
		vec3 shd = selector_pal(0.1, f_variant);
		if (f_accent > -0.5) {
			vec3 a = accent[int(f_accent + 0.5)];
			float lr = dot(shd, vec3(0.3, 0.59, 0.11))
				/ max(dot(selector_pal(0.9, f_variant), vec3(0.3, 0.59, 0.11)), 0.001);
			col = a;
			shd = mix(a * lr, shd, 0.4);
		}
		DIFFUSE_LIGHT += mix(col, shd, cast * 0.94) * f_mul;
	}
}
