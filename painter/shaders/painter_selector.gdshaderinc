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
// The mesh's half size in its own units (PainterSurfaces sets it from its AABB): a tuft's rim
// reads it.
uniform vec3 selector_extent = vec3(0.5);
// Snow on the plants (the sheet's crown-deposit, 0 but in winter): the share of a plant's up side
// (a tuft's top) under snow, and the snow's lit and shaded colours (the drift role on the ground's
// ramp, LINEAR), so a plant's snow is the snow it stands in.
uniform float frost = 0.0;
uniform vec3 c_frost_lit = vec3(0.9);
uniform vec3 c_frost_shd = vec3(0.5);

varying vec3 f_n;
varying float f_variant;
varying float f_mul;
varying float f_wob;
varying float f_accent;
varying float f_frost;

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
// (painter-bushes: core's card-built bushes, Bush_BerryBush and Bush_Bush, are not drawn here but
// by the painted trees' host, as crown-only trees, PainterTreeBush; the envelope and its lobes that
// painter-trees-fix2 tried for them read as faceted artichokes and are gone.)
// A tuft's rim (grass and flowers): the share by which its outer blades darken toward its edge, and
// how far one tuft's value steps from its neighbours', so a field of tufts reads as rounded
// scallops, not one flat strip.
const float TUFT_RIM = 0.3;
const float TUFT_STEP = 0.15;
// A tuft in the painted hand (painter-plants-fix3: a winter tuft drew its card's toothed blades as
// flat straw shards under a ragged snow line, the worst thing in the winter frames). A wide tuft's
// card (TUFT_WIDE of its height across or more: meadow grass, not reeds) is cut not by its texture
// but by four round dabs laid as a mound, the middle ones high and the outer ones low, each card
// its own draw: the outline is their upper arcs, each dab turns from a darker foot to a lit top
// and takes its own value and variant. In winter the snow buries the tuft's foot under a scalloped
// line (TUFT_BURY of its height at full frost) and caps each dab's top in a crescent (TUFT_CAP of
// the dab at full frost), so the straw shows as scalloped bands between snow.
// Cost (painter-plants-fix4: fix3's six dabs, laid per fragment in a loop of hashes and sines, cost
// about 0.2 to 0.3 ms at the village's home view): the layout is the card's, worked out in the
// vertex stage (tuft_layout) and read flat; the fragment tests the four dabs at once in vector
// arithmetic with no sine. (A trapezoid card round the mound, drawn to save the empty top corners,
// clipped the outer dabs into pointed shards and saved nothing measurable: gone.)
const float TUFT_WIDE = 0.7;
const float TUFT_BURY = 0.5;
const float TUFT_CAP = 0.8;

// A tuft's half width in tuft heights (at most 2.5), and whether its cards are cut by dabs (a wide
// grass tuft; a flower keeps its petals).
float tuft_half_w() {
	return min(max(selector_extent.x, selector_extent.z) / max(selector_height, 0.01), 2.5);
}

bool tuft_wide() {
	return kind == 1 && tuft_half_w() >= TUFT_WIDE;
}

// The layout of the tuft card through the local `vertex` (before the sway) at `uv` (core's tuft
// card: UV.x across it, UV.y 0 at its top and 1 at its foot) for an instance at `origin`: `p` the
// point in tuft heights (x across from the card's middle, y up from its foot) and z the tuft's
// seed; dx, dy the four dabs' centres and di their inverse radii in the same units. The dabs vary
// with the card's direction from the axis toward its UV.x = 0 end, which both ends of a card share
// (core's cards run through the axis and carry an up normal for ground lighting, so the card is
// told by its vertices), so a card's layout is constant over it.
void tuft_layout(vec3 vertex, vec2 uv, vec3 origin, out vec3 p, out vec4 dx, out vec4 dy,
		out vec4 di) {
	float half_w = tuft_half_w();
	float seed = p_hash(floor(origin * 10.0) + vec3(3.0, 5.0, 11.0));
	float w = half_w * 0.8;
	p = vec3((uv.x - 0.5) * 2.0 * half_w, 1.0 - uv.y, seed);
	vec2 end = vertex.xz * (uv.x < 0.5 ? 1.0 : -1.0);
	vec2 card = end / max(length(end), 1.0e-4);
	float turn = card.x * 2.1 + card.y * 3.3;
	// Each dab's hashes from the tuft's seed and the card's turn (fract chains: a field of tuft cards
	// is many vertices, so no hash calls or sines here).
	vec4 hk = fract(seed * vec4(97.13, 61.71, 43.97, 29.31) + turn * vec4(0.159, 0.211, 0.137, 0.173)
		+ vec4(0.0, 0.31, 0.57, 0.83));
	vec4 hk2 = fract(hk * 7.13 + seed * 3.7);
	vec4 u = vec4(-0.75, -0.25, 0.25, 0.75);
	dx = (u + (hk - 0.5) * 0.2) * w;
	dy = 0.58 - 0.32 * u * u + (hk2 - 0.5) * 0.12;
	di = 1.0 / (0.29 + 0.12 * hk2);
}

// The dab of the tuft card point `p` (tuft_layout's; the other arguments its flat outputs): x 2
// when a dab draws the point (its texture's cut is not read), 1 when the texture's cut does (a
// narrow tuft or a flower), 0 cut away; y its dab's hash, z its height in the dab (-1 the dab's
// foot, 1 its top), w the snow on it (0 none, 1 lit snow, 0.75 a cap's shaded lower rim). A
// texture-cut tuft takes the bury line and a top cap.
vec4 tuft_dab(vec3 p, vec4 dx, vec4 dy, vec4 di) {
	float kept = 1.0;
	float own_c = -1.0;
	vec3 own = vec3(p.z, 0.0, 0.0);
	bool wide = tuft_wide();
	if (wide) {
		float w = tuft_half_w() * 0.8;
		// Each dab's hash, from its centre (the plant shader has no varying to spare for it).
		vec4 dh = fract((dx * 3.1 + dy) * 17.31);
		vec4 ax = (p.x - dx) * di;
		vec4 ay = (p.y - dy) * di;
		// A brushed rim: each dab's edge wavers a little round its circle (a triangle wave).
		vec4 rim = 1.0 + 0.3 * (abs(fract(ax * 0.55 + ay * 0.4 + dh * 3.0) - 0.5) - 0.25);
		vec4 inside = step(ax * ax + ay * ay, rim * rim);
		// The highest dab over the point draws it (the middle ones lie over the outer ones).
		vec4 score = inside * (dy + 2.0);
		float best = max(max(score.x, score.y), max(score.z, score.w));
		if (best > 0.5) {
			vec4 pick = step(best, score);
			own = vec3(dot(pick, dh), dot(pick, ay), dot(pick, ax));
			own_c = best - 2.0;
			kept = 2.0;
		} else if (p.y > 0.0 && p.y < 0.42 - 0.5 * (p.x / w) * (p.x / w)) {
			// The body under the dabs' centres, so no gap opens between their feet.
			kept = 2.0;
			own = vec3(p.z, -0.7, 0.0);
		} else {
			kept = 0.0;
		}
	}
	float snow = 0.0;
	if (frost > 0.0 && kept > 0.5) {
		// The bury line's scallops (a parabola a period, as abs(sin(5 x)) drew them).
		float s = fract(p.x * 1.59 + p.z);
		if (p.y < TUFT_BURY * frost * (0.7 + 1.8 * s * (1.0 - s))) {
			snow = 1.0;
		} else if (own_c > -0.5) {
			float top = sqrt(max(1.0 - own.z * own.z, 0.0));
			float line = top * (1.0 - TUFT_CAP * frost);
			snow = own.y > line ? (own.y > line + 0.15 * top ? 1.0 : 0.75) : 0.0;
		} else if (!wide) {
			float s2 = fract(p.x * 1.43 + p.z);
			snow = p.y > 1.0 - 0.3 * frost + 0.64 * s2 * (1.0 - s2) - 0.08 ? 1.0 : 0.0;
		}
	}
	return vec4(kept, own.x, own.y, snow);
}

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

// Whether snow lies on a plant point whose lit normal's up part is `up` (a bush's lobe, a rock's
// face): the crowns' frost law (painter_tree_blockin's deposit), patchy by a world noise.
bool frost_up(float up, vec3 wp) {
	return frost * smoothstep(0.1, 0.55, up) > 0.3 + 0.35 * p_noise(wp * 0.6 + 3.0);
}

// The per-fragment choices light() reads: the normal it lights, the variant, the height shading,
// the wobble, (on a petal, else -1) the accent and whether snow lies there (1) or not (0). `wp` is
// the fragment's world position, `tex` the GLB texture's sample.
void selector_fragment(vec3 wp, vec3 wn, vec3 origin, float scale, float h, vec4 tex,
		out vec3 n, out float variant, out float mul, out float wob, out float petal,
		out float snow) {
	n = normalize(wn);
	// One variant per plant, in three steps, and a slow drift across the map.
	variant = floor(p_hash(floor(origin * 10.0)) * 3.0) * 0.5;
	variant = mix(variant, p_noise(origin * 0.12 + 40.0), 0.5);
	mul = 1.0;
	petal = -1.0;
	snow = 0.0;
	if (kind == 0) {
		// A leaf mass turns as one rounded form about its middle, not card by card.
		vec3 mid = origin + vec3(0.0, 0.45 * selector_height * scale, 0.0);
		n = normalize(mix(n * 0.25, normalize(wp - mid), 0.75));
		mul = mix(0.86, 1.0, smoothstep(0.0, 0.35, h));
		snow = frost > 0.0 && frost_up(n.y, wp) ? 1.0 : 0.0;
	} else if (kind == 4) {
		// A bush: its lobes' domes over the rounded form, each lobe a little its own colour.
		vec3 n0 = normalize(wp - bush_mid(origin, scale));
		vec4 lobe = bush_lobe(wp, origin, scale, n0);
		n = normalize(n0 + BUSH_TILT * lobe.xyz);
		variant = mix(variant, lobe.w, 0.5);
		mul = mix(0.9, 1.0, smoothstep(0.0, 0.3, h));
		snow = frost > 0.0 && frost_up(n.y, wp) ? 1.0 : 0.0;
	} else if (kind == 1 || kind == 3) {
		n = vec3(0.0, 1.0, 0.0);
		// Darker at the base and toward the tuft's rim, and each tuft a step lighter or darker than
		// its neighbours, so a bed of tufts reads as rounded scallops, not one flat strip.
		float across = max(max(selector_extent.x, selector_extent.z) * scale, 0.02);
		float rim = smoothstep(0.2, 0.8, length((wp - origin).xz) / across);
		float own = mix(1.0 - TUFT_STEP, 1.0 + TUFT_STEP, p_hash(floor(origin * 10.0) + 23.0));
		mul = mix(0.74, 1.0, smoothstep(0.0, 0.55, h)) * (1.0 - TUFT_RIM * rim) * own;
		if (kind == 3 && tex.g - max(tex.r, tex.b) < 0.02) {
			// A petal: white where the texture is pale, else one colour per group of plants.
			float lo = min(tex.r, min(tex.g, tex.b));
			float grp = p_noise(vec3(origin.x * group_freq, 6.0, origin.z * group_freq) + 90.0);
			petal = lo > 0.55 ? 3.0 : (grp < 0.44 ? 0.0 : (grp < 0.58 ? 1.0 : 2.0));
			mul = 1.0;
		}
		// Snow caps a tuft's top (painter_plant replaces this with tuft_dab()'s caps and bury line).
		snow = frost > 0.0 && h > 1.0 - 0.3 * frost ? 1.0 : 0.0;
	} else {
		variant = mix(variant, p_noise(wp * 0.9 + 17.0), 0.5);
		snow = frost > 0.0 && frost_up(n.y - 0.3, wp) ? 1.0 : 0.0;
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
		float mul = f_mul;
		if (f_frost > 0.5) {
			// Snow takes the snow's own two steps (lit by the same law as the plant's tone); a tuft
			// cap's lower rim (f_frost 0.75) stays part way to the shade, so the cap reads as a form.
			col = mix(c_frost_shd, c_frost_lit, smoothstep(0.3, 0.7, t) * (f_frost > 0.9 ? 1.0 : 0.55));
			shd = c_frost_shd;
			mul = 1.0;
		}
		DIFFUSE_LIGHT += mix(col, shd, cast * 0.94) * mul;
	}
}
