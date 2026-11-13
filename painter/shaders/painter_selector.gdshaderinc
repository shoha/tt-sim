// The painted look's SELECTOR light for the scatter tt-sim draws from GLBs (bushes, ferns,
// grass, flowers, rocks, deadwood; docs/systems/painter.md "Surfaces"). The material is lit with
// the ambient off and ALBEDO white; light() takes N.L and the sun's ATTENUATION only to pick
// the sheet role's shade, middle or lit colour, so everything reads tt-sim's one directional
// shadow map and the sheet's colours reach the screen as written. The GLB's texture gives the
// cutout (and, on a flower, which pixels are petals); none of its colour is drawn.
//
// kind: 0 leaf mass (lit as one rounded form about the plant's middle), 1 grass (one flat tone,
// darker at the base, lit or shaded like the ground: no middle step), 2 solid (rock, wood, litter: its own normals, a noise-broken turn),
// 3 flower (the grass ramp on its green pixels, one of four flat accents on its petals by group),
// 4 bush (a leaf mass in the painted crowns' hand: see bush_lobe()).
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

// A bush (kind 4) is painted as a crown is (painter-trees-polish2: the leaf mass's shading read as
// lime faceted gumdrops on a low-poly GLB): one rounded form about its middle, broken into lobes
// that each turn as a dome of their own, so the tone steps run in scallops like a crown's lobed
// strokes and never along the mesh's flat faces, and an outline that breaks between the lobes. A
// lobe is a cell of a world Voronoi field BUSH_LOBE of the bush's height across (not under
// BUSH_LOBE_MIN metres), its centre jittered inside the cell.
const float BUSH_LOBE = 0.34;
const float BUSH_LOBE_MIN = 0.14;
// How far a lobe's dome turns the form's normal at its edge (per lobe unit off its centre).
const float BUSH_TILT = 1.1;
// How far round from the outline the lobes break it: |N.eye| under this between two lobes is not
// drawn, so the outline is a run of round bumps rather than the GLB's polygon.
const float BUSH_RIM = 0.4;
// The highest tone a bush's lobe keeps in a cast shadow (0.1 shade, 0.5 middle).
const float BUSH_CAST_T = 0.3;

// The bush's form centre for an instance at `origin` of `scale`.
vec3 bush_mid(vec3 origin, float scale) {
	return origin + vec3(0.0, 0.5 * selector_height * scale, 0.0);
}

// The nearest lobe of the bush point `wp`: xyz the point's offset from the lobe's centre across the
// form (in lobe units, its part along the form normal `n0` removed), w the lobe's hash. The nearest
// of the eight cells round the point (the cell's corner it is nearest), a cheap Voronoi.
vec4 bush_lobe(vec3 wp, vec3 origin, float scale, vec3 n0) {
	float cell = max(BUSH_LOBE * selector_height * scale, BUSH_LOBE_MIN);
	vec3 q = (wp - origin) / cell + fract(origin * 0.37) * 9.0;
	vec3 i = floor(q);
	vec3 side = step(0.5, q - i) * 2.0 - 1.0;
	vec3 best = vec3(0.0);
	float best_d = 1.0e9;
	float best_h = 0.0;
	for (int k = 0; k < 8; k++) {
		vec3 g = i + side * vec3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1));
		vec3 o = vec3(p_hash(g + 3.1), p_hash(g + 17.3), p_hash(g + 41.7));
		vec3 d = q - (g + 0.2 + 0.6 * o);
		float dd = dot(d, d);
		if (dd < best_d) {
			best_d = dd;
			best = d;
			best_h = o.x;
		}
	}
	return vec4(best - n0 * dot(best, n0), best_h);
}

// Whether the bush point `wp` lies in a break of its outline, seen along `eye` (the unit vector
// toward the viewer: the camera, or the sun in the shadow pass, so the shadow's edge breaks too).
bool bush_cut(vec3 wp, vec3 origin, float scale, vec3 eye) {
	vec3 n0 = normalize(wp - bush_mid(origin, scale));
	float off = length(bush_lobe(wp, origin, scale, n0).xyz);
	return abs(dot(n0, eye)) < BUSH_RIM * smoothstep(0.25, 0.6, off);
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
	} else if (kind == 4) {
		// A bush: its lobes' domes over the rounded form, each lobe a little its own colour.
		vec3 n0 = normalize(wp - bush_mid(origin, scale));
		vec4 lobe = bush_lobe(wp, origin, scale, n0);
		n = normalize(n0 + BUSH_TILT * lobe.xyz);
		variant = mix(variant, lobe.w, 0.5);
		mul = mix(0.9, 1.0, smoothstep(0.0, 0.3, h));
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
		if (kind == 1 || kind == 3) {
			// Ground cover lights like the ground it stands on (painter_ground's light()): lit unless
			// a cast shadow or a sun at the horizon, never a middle step for a low sun, so a lawn
			// at a dusk sun is one family with the lit ground beside it.
			t = 0.1 + 0.8 * smoothstep(0.02, 0.1, lw.y + (f_wob - 0.5) * 0.1);
		}
		vec3 col = selector_pal(t, f_variant + (t - 0.45) * 0.3);
		// In a cast shadow a bush's lobes keep a half step toward the sun (as a crown's strokes keep
		// crown-cast): one flat shade read as a smooth dark lump (painter-trees-polish3).
		vec3 shd = selector_pal(kind == 4 ? min(t, BUSH_CAST_T) : 0.1, f_variant);
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
