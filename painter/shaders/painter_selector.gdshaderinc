// The painted look's SELECTOR light for the scatter tt-sim draws from GLBs (bushes, ferns,
// grass, flowers, rocks, deadwood; docs/systems/painter.md "Surfaces"). The material is lit with
// the ambient off and ALBEDO white; light() takes N.L and the sun's ATTENUATION only to pick
// the sheet role's shade, middle or lit colour, so everything reads tt-sim's one directional
// shadow map and the sheet's colours reach the screen as written. The GLB's texture gives the
// cutout (and, on a flower, which pixels are petals); none of its colour is drawn.
//
// kind: 0 leaf mass (lit as one rounded form about the plant's middle), 1 grass (one flat tone,
// darker at the base, lit or shaded like the ground: no middle step), 2 solid (rock, wood, litter: its own normals, a noise-broken turn),
// 3 flower (stems and leaves in the grass ramp; its blooms one painted mark a head in the flower's
// own accent, see painter_flower_marks.gdshaderinc),
// 4 bush (a leaf mass in the painted crowns' hand: see bush_lobe()), 5 a wall's leaves (a structure's
// baked ivy: leaf dabs on the card's plane, see ivy_dab()).
// PainterSurfaces sets every uniform from the sheet (PainterTones.ramp and the sheet's numbers).
// Includers call selector_fragment() at the end of fragment() with the world position and
// normal, the instance origin and scale and the height fraction, and assign its outputs to the
// varyings f_n, f_variant, f_mul, f_wob, f_accent and f_centre (a function other than fragment() may not
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
// Flower blooms: gold, rose, violet, white, red, blue (LINEAR; PainterFlowerHue.ROLES).
uniform vec3 accent[6];
// The surface's bloom (PainterFlowerHue.for_surface): its accent (-1: a stem or leaves), whether
// the whole surface is bloom cards drawn as dabs (else its petal pixels are found by colour), the
// dab's box in UV (centre, half extents: the texture's opaque box), and each vertex's card centre
// and dab size, their crossed-twin flags and the carpet texel (PainterFlowerHue.centres, one texel
// per VERTEX_ID) for the marks.
uniform int petal_role = -1;
uniform bool petal_dab = false;
uniform vec4 dab_box = vec4(0.5, 0.5, 0.5, 0.5);
uniform sampler2D bloom_centres : filter_nearest, repeat_disable;
// The N.L where the shade, middle and lit steps meet (sheet tone-lo, tone-hi).
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
// Thinning in groups: an instance is drawn where a slow world noise at its foot is above
// 1 - keep, so what stays stands in fewer, larger groups (keep 1 = everything).
uniform float keep = 1.0;
uniform float keep_freq = 0.2;
// The frequency (1/m) of the slow field that steps a drift of blooms a little lighter or darker.
uniform float group_freq = 0.1;
// False for ground cover: grass and flowers receive the shade of trees and buildings but cast
// none of their own (they collapse in the shadow pass).
uniform bool casts_shadow = true;
// The height of the selector's mesh in its own units (a leaf mass turns about its middle).
uniform float selector_height = 1.0;
// How much darker a stone's or a log's foot is (PainterOcclusion: 0 off, the sheet's base-dark).
uniform float base_dark = 0.0;
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
// The share of a bloom mark's middle disc (the flower's centre), 0 elsewhere.
varying float f_centre;
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

// A wide grass tuft's pitch crossfade (card painter-grass-mark; the sheet's grass-mark-pitch,
// PainterGrassMarks): below mark_pitch degrees of camera pitch the tuft draws its cards
// (painter_plant), above it its painted mark (painter_grass_mark); 0 marks at every pitch. Each tuft
// swaps at its own pitch within MARK_BAND degrees of it, so the change runs across the field rather
// than in one frame. `back` points from the tuft toward the eye.
uniform float mark_pitch = 0.0;
const float MARK_BAND = 5.0;

bool grass_mark_on(vec3 origin, vec3 back) {
	if (mark_pitch <= 0.0) {
		return true;
	}
	float band = (p_hash(floor(origin * 10.0) + vec3(7.0, 1.0, 3.0)) - 0.5) * 2.0 * MARK_BAND;
	return degrees(asin(clamp(back.y, 0.0, 1.0))) >= mark_pitch + band;
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
// Cost (painter-cost-stripes): the dabs are not laid or tested here. A card's layout is one of
// PainterTuftAtlas' TUFT_LAYERS layers (a texture array: the cut as a distance field, the dab's
// hash and the point's place in its dab), picked per card in the vertex stage; the fragment reads
// it in one fetch, in place of the texture's cut (a wide tuft never reads its texture). The dabs
// tested per fragment, from three flat vec4 varyings a card, cost 0.10 to 0.13 ms at the village's
// home view even with the test skipped at run time (the code's presence alone: GPU registers on a
// field of small overlapping cards), and fix3's loop of hashes and sines no more. (A trapezoid card
// round the mound clipped the outer dabs into pointed shards and saved nothing: gone.)
const float TUFT_WIDE = 0.7;
const float TUFT_BURY = 0.5;
const float TUFT_CAP = 0.8;
// PainterTuftAtlas.LAYERS and RANGE (a dab's place is stored as (x + RANGE) / (2 RANGE)).
const float TUFT_LAYERS = 16.0;
const float TUFT_RANGE = 1.5;
uniform sampler2DArray tuft_atlas : filter_linear_mipmap, repeat_disable;
// A village field's crop (PainterFields, card painter-fields): its cards keep their texture's
// blades, so a row reads as a standing crop, not the meadow's round dab mounds.
uniform bool tuft_blades = false;

// A tuft's half width in tuft heights (at most 2.5), and whether its cards are cut by dabs (a wide
// grass tuft; a flower keeps its petals).
float tuft_half_w() {
	return min(max(selector_extent.x, selector_extent.z) / max(selector_height, 0.01), 2.5);
}

bool tuft_wide() {
	return kind == 1 && !tuft_blades && tuft_half_w() >= TUFT_WIDE;
}

// The tuft card through the local `vertex` (before the sway) at `uv` (core's tuft card: UV.x
// across it, UV.y 0 at its top and 1 at its foot) for an instance at `origin`: x its layer in the
// atlas, y the tuft's seed. The layer follows the card's direction from the axis toward its
// UV.x = 0 end, which both ends of a card share (core's cards run through the axis and carry an up
// normal for ground lighting, so the card is told by its vertices): constant over a card.
vec2 tuft_card(vec3 vertex, vec2 uv, vec3 origin) {
	float seed = p_hash(floor(origin * 10.0) + vec3(3.0, 5.0, 11.0));
	vec2 end = vertex.xz * (uv.x < 0.5 ? 1.0 : -1.0);
	vec2 card = end / max(length(end), 1.0e-4);
	float turn = card.x * 2.1 + card.y * 3.3;
	return vec2(floor(fract(seed * 97.13 + turn * 0.159) * TUFT_LAYERS), seed);
}

// The dab of the tuft card point at `uv` (`card` tuft_card's): x 2 when a dab draws the point (the
// texture's cut is not read), 1 when the texture's cut does (a narrow tuft or a flower), 0 cut away;
// y its dab's hash, z its height in the dab (-1 the dab's foot, 1 its top; the body under the dabs
// lower), w the snow on it (0 none, 1 lit snow, 0.75 a cap's shaded lower rim). A texture-cut tuft
// takes the bury line and a top cap.
vec4 tuft_dab(vec2 uv, vec2 card) {
	float kept = 1.0;
	vec3 own = vec3(card.y, -TUFT_RANGE, 0.0);
	bool wide = tuft_wide();
	if (wide) {
		vec4 a = texture(tuft_atlas, vec3(uv, card.x));
		kept = a.r < 0.5 ? 0.0 : 2.0;
		own = vec3(a.g, a.ba * (2.0 * TUFT_RANGE) - TUFT_RANGE);
	}
	float snow = 0.0;
	if (frost > 0.0 && kept > 0.5) {
		// The point in tuft heights, x across from the card's middle, y up from its foot.
		vec2 p = vec2((uv.x - 0.5) * 2.0 * tuft_half_w(), 1.0 - uv.y);
		// The bury line's scallops (a parabola a period, as abs(sin(5 x)) drew them).
		float s = fract(p.x * 1.59 + card.y);
		if (p.y < TUFT_BURY * frost * (0.7 + 1.8 * s * (1.0 - s))) {
			snow = 1.0;
		} else if (wide) {
			// A dab's cap: a crescent over its top (the body's texels sit below every line).
			float top = sqrt(max(1.0 - own.z * own.z, 0.0));
			float line = top * (1.0 - TUFT_CAP * frost);
			snow = own.y > line ? (own.y > line + 0.15 * top ? 1.0 : 0.75) : 0.0;
		} else {
			float s2 = fract(p.x * 1.43 + card.y);
			snow = p.y > 1.0 - 0.3 * frost + 0.64 * s2 * (1.0 - s2) - 0.08 ? 1.0 : 0.0;
		}
	}
	return vec4(kept, own.x, own.y, snow);
}

// (A flower's bloom is painted by painter_flower_marks.gdshaderinc, included by painter_plant.)

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

// A wall's leaves (kind 5: a structure's baked ivy and window plants, card painter-roofs-ivy; as a
// solid they read as flat mid-green cut-outs at eye level): leaf dabs about IVY_DAB metres across
// laid on the card's own plane, each turned as a small dome by IVY_TILT, so its sunward rim takes
// the lit step and its far rim the middle or the shade, and darker toward its rim by IVY_TUCK where
// it tucks under its neighbours; each dab its own variant and value. Under IVY_FADE pixels a dab the
// dabs fade into the plain card (a far view keeps one soft mass).
const float IVY_DAB = 0.2;
const float IVY_TILT = 1.4;
const float IVY_TUCK = 0.38;
const float IVY_FADE = 6.0;

// The nearest leaf dab of a point at `q` (card-plane metres over IVY_DAB): xy its offset from the
// dab's centre, z and w two hashes of the dab. The nearest of the four cells round the point (the
// cell's corner it is nearest), a cheap 2D Voronoi: eight hashes.
vec4 ivy_dab(vec2 q) {
	vec2 i = floor(q);
	vec2 side = step(0.5, q - i) * 2.0 - 1.0;
	vec2 best = vec2(0.0);
	float best_d = 1.0e9;
	vec2 best_h = vec2(0.0);
	for (int k = 0; k < 4; k++) {
		vec2 g = i + side * vec2(float(k & 1), float((k >> 1) & 1));
		vec2 o = vec2(p_hash(vec3(g, 3.1)), p_hash(vec3(g, 17.3)));
		vec2 d = q - (g + 0.15 + 0.7 * o);
		float dd = dot(d, d);
		if (dd < best_d) {
			best_d = dd;
			best = d;
			best_h = o;
		}
	}
	return vec4(best, best_h);
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
		if (kind == 3 && petal_role >= 0 && (petal_dab || tex.g - max(tex.r, tex.b) < 0.02)) {
			// A bloom: the flower's own accent (PainterFlowerHue), a drift of them a little lighter
			// or darker by a slow field and each plant a step its own, so a meadow of one species is
			// never one flat colour (the plant shader darkens a dab's foot).
			petal = float(petal_role);
			float drift = p_noise(vec3(origin.x * group_freq, 6.0, origin.z * group_freq) + 90.0);
			mul = mix(0.9, 1.06, drift) * mix(0.96, 1.04, p_hash(floor(origin * 10.0) + 23.0));
		}
		// Snow caps a tuft's top (painter_plant replaces this with tuft_dab()'s caps and bury line).
		snow = frost > 0.0 && h > 1.0 - 0.3 * frost ? 1.0 : 0.0;
	} else if (kind == 5) {
		// A wall's leaves: `wn` is the card's own face (painter_plant turns it to the viewer), the dabs
		// lie on its plane. Snow only on the dabs' upper rims.
		vec3 t1 = abs(n.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n));
		vec3 t2 = cross(n, t1);
		vec4 dab = ivy_dab(vec2(dot(wp, t1), dot(wp, t2)) / IVY_DAB);
		float px = length(fwidth(wp));
		float near = 1.0 - smoothstep(IVY_DAB / IVY_FADE, IVY_DAB / (IVY_FADE * 0.5), px);
		n = normalize(n + IVY_TILT * near * (t1 * dab.x + t2 * dab.y));
		variant = mix(variant, dab.z, 0.6 * near);
		float rim = smoothstep(0.22, 0.55, length(dab.xy));
		mul = (1.0 - IVY_TUCK * near * rim) * mix(1.0, mix(0.9, 1.08, dab.w), near);
		snow = frost > 0.0 && frost_up(n.y, wp) ? 1.0 : 0.0;
	} else {
		variant = mix(variant, p_noise(wp * 0.9 + 17.0), 0.5);
		snow = frost > 0.0 && frost_up(n.y - 0.3, wp) ? 1.0 : 0.0;
		// A stone or a log grows out of the ground: a step darker over its foot (PainterOcclusion).
		mul = mix(1.0 - base_dark, 1.0, smoothstep(0.0, 0.45, h));
	}
	wob = p_noise(wp * 1.7 + 5.0);
}

// How far above tone_lo (in N.L) a solid's face must turn toward the sun before a cast shadow
// reaches it (light(), kind 2).
const float SOLID_CAST_FACING = 0.4;

// (A grass mark lights its own form: painter_grass_mark defines SELECTOR_OWN_LIGHT and its light().)
#ifndef SELECTOR_OWN_LIGHT
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float nl = dot(normalize(f_n), lw);
		if (kind == 2) {
			// A rock's or a log's face turned nearly edge-on to the sun is where the shadow map
			// self-shadows it in stripes and the soft filter's noise stipples the edge of each (card
			// painter-ground-artifacts: dark violet hatching on a boulder's face). Such a face is
			// already a middle step by N.L, so it takes no cast shadow until it faces the sun, and the
			// step that does is wider than the filter's noise.
			cast = 1.0 - smoothstep(0.35, 0.65, ATTENUATION + (f_wob - 0.5) * 0.2);
			cast *= smoothstep(tone_lo, tone_lo + SOLID_CAST_FACING, nl);
		}
		float x = nl + (f_wob - 0.5) * 0.3;
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
			if (f_centre > 0.0) {
				// A flower's middle: the mood's gold, or an orange between its gold and red on a gold
				// bloom, so it follows the sheet's tones through every mood.
				vec3 cc = f_accent < 0.5 ? mix(accent[0], accent[4], 0.65) : accent[0];
				col = mix(col, cc, f_centre);
				shd = mix(shd, cc * lr, f_centre);
			}
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
#endif
