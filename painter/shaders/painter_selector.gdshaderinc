// The painted look's SELECTOR light for the scatter tt-sim draws from GLBs (bushes, ferns,
// grass, flowers, rocks, deadwood; docs/systems/painter.md "Surfaces"). The material is lit with
// the ambient off and ALBEDO white; light() takes N.L and the sun's ATTENUATION only to pick
// the sheet role's shade, middle or lit colour, so everything reads tt-sim's one directional
// shadow map and the sheet's colours reach the screen as written. The GLB's texture gives the
// cutout (and, on a flower, which pixels are petals); none of its colour is drawn.
//
// kind: 0 leaf mass (lit as one rounded form about the plant's middle), 1 grass (one flat tone,
// darker at the base, lit or shaded like the ground: no middle step), 2 solid (rock, wood, litter: its own normals, a noise-broken turn),
// 3 flower (stems and leaves in the grass ramp; its blooms one dab a card in the flower's own
// accent, see bloom_dab()),
// 4 bush (a leaf mass in the painted crowns' hand: see bush_lobe()), 5 a wall's leaves (a structure's
// baked ivy: leaf dabs on the card's plane, see ivy_dab()).
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
// Flower blooms: gold, rose, violet, white, red, blue (LINEAR; PainterFlowerHue.ROLES).
uniform vec3 accent[6];
// The surface's bloom (PainterFlowerHue.for_surface): its accent (-1: a stem or leaves), whether
// the whole surface is bloom cards drawn as dabs (else its petal pixels are found by colour), the
// dab's box in UV (centre, half extents: the texture's opaque box), and each vertex's card centre
// and dab size (PainterFlowerHue.centres, one texel per VERTEX_ID) for the growth.
uniform int petal_role = -1;
uniform bool petal_dab = false;
uniform vec4 dab_box = vec4(0.5, 0.5, 0.5, 0.5);
uniform sampler2D bloom_centres : filter_nearest, repeat_disable;
uniform bool bloom_grow = false;
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

// A flower's bloom in the painted hand (card painter-flowers: the texture's small teardrop petals,
// coloured by a world field in four accents, read as a few purple dots at the orbit view and next
// to nothing at the eye). Each bloom card is one dab: a blot inscribed in the texture's opaque box
// (dab_box: round on a head, long on a spike), its rim brushed by a slow wobble, in the flower's
// own accent and a step darker toward its foot. A single flower's cards stay as they are; the dab
// replaces the texture's fetch, so a bloom costs no more than the petal cut did.
//
// A carpet of blooms (a bloom mound: PainterFlowerHue.carpet_of) reads as one solid mound of
// flowers at the orbit view (owner, board l44_mound: "One solid blot"; card painter-flower-carpet).
// Its cards run every way over the mound, so from above many were slivers, and the mound's leaves,
// which stand twice as high as its blooms, covered the middle: a ring of small dabs with green
// between. So under the orbit's orthographic camera each card is turned to face the view (a whole
// dab wherever the card points), drawn CARPET_PULL of the way in toward the mound's middle and
// CARPET_LIFT up to its top card's height, brought CARPET_FRONT toward the eye so it lies over the
// leaves, and grown to at least BLOOM_PX pixels (at most BLOOM_GROW_MAX times) and CARPET_SWELL
// more, so the dabs overlap into one blot whose rim is the outer dabs' lobes, with the leaves'
// green showing only at its foot. Faded in by the view's pixel size; the eye's perspective keeps
// each card where it is.
//
// Why two earlier tries showed nothing (painter-flowers' growth, painter-ground-fire-round3's pull):
// the pixel size was taken as 2 / (projection[1][1] * height), but the world is drawn into a
// viewport whose projection is flipped in y, so [1][1] is negative there: the size came out
// negative, the growth clamped to 1 and the carpet's fade to 0 (a probe that coloured the carpets
// by the size's decade painted every one in the lowest; measured 2026-11-19). abs() fixes it. The
// single flowers' growth that never ran stays off, so their approved look is unchanged.
const float BLOOM_PX = 8.0;
const float BLOOM_GROW_MAX = 3.5;
const float CARPET_PULL = 0.3;
const float CARPET_LIFT = 0.8;
const float CARPET_SWELL = 0.7;
// Mesh units: core's mound leaves stand to 0.20 to 0.26, their blooms' centres only to 0.10 to 0.13
// (measured 2026-11-19). Under the orthographic camera this moves nothing on screen; it only wins
// the depth test over the leaves.
const float CARPET_FRONT = 0.25;
// The pixel size (m at the card) over which the carpet fades in: whole from about zoom 8 (8 m over
// 1080 px), none closer than about zoom 3.
const vec2 CARPET_PX = vec2(0.003, 0.007);
// A carpet's hues: each card takes the flower's own accent under CARPET_MIX.x of its hash, else one
// of two more the plant draws from the six (to CARPET_MIX.y the first), so a meadow's mounds read
// as mixed wildflower cushions, each led by its own colour (round two of the card split a mound
// into three sectors, which read as two-tone balls with a straight seam). In every view, so a
// mound keeps its colours when the view changes.
const vec2 CARPET_MIX = vec2(0.6, 0.85);
// A carpet's dab a step darker low on the mound than at its top, so the blot reads as a dome.
const vec2 CARPET_SHADE = vec2(0.8, 1.04);

// The accent (a ROLES index, x) and value (y, a factor) of the carpet card centred at `c` (mesh
// units; `top` the carpet's top card's height) on the plant at `origin`.
vec2 carpet_card(vec3 c, float top, vec3 origin) {
	vec3 plant = floor(origin * 10.0);
	float h = p_hash(floor(c * 1000.0) + plant);
	float role = float(petal_role);
	if (h >= CARPET_MIX.x) {
		vec3 salt = h < CARPET_MIX.y ? vec3(7.0, 13.0, 29.0) : vec3(31.0, 3.0, 17.0);
		role = floor(p_hash(plant + salt) * 5.999);
	}
	return vec2(role, mix(CARPET_SHADE.x, CARPET_SHADE.y, smoothstep(0.0, 1.0, c.y / max(top, 0.01))));
}

// The local `vertex` (vertex `id` of a bloom surface, at `uv`) for the view of `inv_view` and
// `projection` on a viewport `viewport` pixels in size: a carpet's card turned to the view and drawn
// in (see CARPET_PULL), any other bloom's as it is. `card` is the card's accent (x, a ROLES index)
// and value (y, a factor).
vec3 bloom_grown(
	vec3 vertex, vec2 uv, int id, mat4 model, mat4 inv_view, mat4 projection, vec2 viewport,
	out vec2 card
) {
	card = vec2(float(petal_role), 1.0);
	vec4 carpet = texelFetch(bloom_centres, ivec2(0, textureSize(bloom_centres, 0).y - 1), 0);
	vec4 c = texelFetch(bloom_centres, ivec2(id % 256, id / 256), 0);
	if (carpet.w < 0.5 || c.w <= 0.0) {
		return vertex;
	}
	card = carpet_card(c.xyz, carpet.y, model[3].xyz);
	if (projection[3][3] == 0.0) {
		return vertex;
	}
	// One pixel in metres under the orthographic camera ([1][1] is negative in a y-flipped viewport).
	float px = 2.0 / (abs(projection[1][1]) * viewport.y);
	float g = smoothstep(CARPET_PX.x, CARPET_PX.y, px);
	if (g <= 0.0) {
		return vertex;
	}
	float k = clamp(BLOOM_PX * px / max(c.w * length(model[1].xyz), 1.0e-4), 1.0, BLOOM_GROW_MAX);
	mat3 to_local = inverse(mat3(model));
	vec3 right = normalize(to_local * inv_view[0].xyz);
	vec3 up = normalize(to_local * inv_view[1].xyz);
	vec3 front = normalize(to_local * inv_view[2].xyz);
	vec3 at = vec3(
		mix(c.x, carpet.x, CARPET_PULL), mix(c.y, carpet.y, CARPET_LIFT), mix(c.z, carpet.z, CARPET_PULL)
	) + front * CARPET_FRONT;
	// The dab inscribed in the box drawn round, the card's own dab grown (a spike's long dab too:
	// a lavender mound read as a stack of tall ellipses).
	vec2 d = (uv - dab_box.xy) / max(dab_box.zw, vec2(0.05));
	vec3 faced = at + (d.x * right - d.y * up) * (0.5 * c.w * k * (1.0 + CARPET_SWELL));
	return mix(vertex, faced, g);
}

// The bloom card point at `uv` (`seed` the card's own, 0..1): x 1 inside its dab, 0 outside; y its
// height in the dab, -1 the foot to 1 the top (UV y runs down the card).
vec2 bloom_dab(vec2 uv, float seed) {
	vec2 d = (uv - dab_box.xy) / max(dab_box.zw, vec2(0.05));
	float a = atan(d.y, d.x);
	float rim = 0.92 + 0.08 * sin(a * 3.0 + seed * 6.2832) * sin(a * 2.0 + seed * 11.0);
	return vec2(dot(d, d) < rim * rim ? 1.0 : 0.0, -d.y);
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
