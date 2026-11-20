shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled, world_vertex_coords;

/*
 * Painted grass mark (a meadow tuft under the Painted look, cards painter-grass-mark and
 * painter-grass-mark-geo)
 * ================================================================================
 *
 * A wide grass tuft drawn as BROAD STROKES MADE OF GEOMETRY. The shipped three crossed cards collapse
 * to thin spikes seen from above (the owner's "sad and spindly"); a mark reads as a full clump at
 * every pitch.
 *
 * The mesh (PainterGrassMarks.strokes) is shared by every instance and holds the largest tuft patch
 * there can be: MAX_TUFTS tufts of STROKES strokes, each stroke a tapered ribbon of a few triangles
 * (UV.x the place along it, UV.y the side; UV2 the tuft and the stroke) and each tuft a small body
 * fan (UV2.y -1). The VERTEX stage is the whole model: it works out the instance's tufts, places the
 * vertex of its tuft and stroke on the mark's plane, and collapses every vertex the instance does not
 * use (a rim tuft has one tuft, a core up to eight) to the instance's origin. The fragment stage only
 * lights, with no discard: the engine's depth test and prepass see opaque triangles, so every pixel is
 * shaded about once (the first marks drew the strokes in the fragment stage with a discard, which
 * lost both, and cost the covered pixels with their overdraw).
 *
 * The tuft is modelled in 3D and its strokes projected: the root at the tuft's origin, each stroke
 * a blade leaning out along a WORLD azimuth to a tip at its own reach and height, so the same tuft
 * is a fan of blades rising from its foot at the orbit's oblique view and a clump of blades lying
 * out from its root seen from above, and keeps its shape as the view turns. The mark's plane is
 * measured in the tuft's reach (L, metres): x across the screen, y up it, the origin at the root.
 * The strokes of a mark are coplanar, so their order is made by a depth bias toward the eye (a tuft
 * nearer the camera above the others, a stroke laid later above the earlier, a body under its strokes).
 *
 * Size (card painter-grass-scale; the owner's "they read more like bushes than grass"): a tuft is
 * as big as a real meadow tuft, never as big as its card mesh grown by the scatter. The reach L of
 * a tuft's blades is its own height (mark_reach) and at most mark_reach_max metres; the instance's
 * FOOTPRINT (the card's half width times the instance's width scale, which a clump core grows to
 * 2.4 times so the cores overlap into one mound) is filled with MORE such tufts, not bigger ones:
 * about (footprint / L)^2 tufts (mark_fill), at most MAX_TUFTS, their roots spread over it on a
 * sunflower spiral. A rim tuft is one small tuft; a core is a patch of several. Each is 4 or 5 broad
 * strokes (mark_count, mark_width) from above, fanned only a little (mark_comb): a wide fan of small
 * strokes reads as a rosette, not grass.
 *
 * Tone: no outline and no ring. Each stroke runs from a darker root to a lit tip, strokes that lean
 * toward the sun a step lighter, every value broken by a world field the neighbouring tufts share
 * (so a meadow's overlapping tufts merge into one grassy mass rather than stacking as stamps), and
 * the selector's ramp (painter_selector: the sheet's grass role) colours it through this shader's
 * own light(): the ramp's lit colour darkened from root to tip as the cards darken theirs, a cast
 * shadow's shade with its tips a step lighter. Winter snow is a soft tint on the upper strokes,
 * never a disc. Seen from the side a darker lumpy body grounds the standing strokes. The tones and
 * fields are read at the vertices (the ribbons are small against the fields' wavelengths).
 *
 * Above the sheet's grass-mark-pitch only (painter_selector's grass_mark_on, a per-tuft band of a
 * few degrees; 0 draws the mark at every pitch): below it the cards draw and the mark collapses, so
 * a sheet can keep the cards at the oblique view and the marks from above.
 *
 * MANAGED BY: PainterGrassMarks (painter/painter_grass_marks.gd).
 */

#define FOLIAGE_GROUND_LEAN
#define SELECTOR_OWN_LIGHT
#include "res://shaders/wind_foliage_include.gdshaderinc"
#include "res://shaders/wind_foliage_grow.gdshaderinc"
#include "res://painter/shaders/painter_selector.gdshaderinc"

// The sun's direction (FoliageLight.publish_sun; the wind include declares it only for its painted
// light).
global uniform vec4 foliage_sun;
// 1 on the hand-placed props' layer (PainterPlantTone.mark_placed): never thinned.
instance uniform float painter_placed = 0.0;
// The look's numbers below are tuned by the look cards' render-job probes (PainterGrassMarks leaves
// them at their defaults). A tuft's reach (its blades' length) against its own height, and the
// longest reach in metres.
uniform float mark_reach = 1.0;
uniform float mark_reach_max = 0.4;
// The tallest a tuft stands in metres (a clump core grows its instances to twice the card's height:
// standing blades that tall read as reeds beside a token).
uniform float mark_height_max = 0.4;
// The footprint's radius against the card's half width (times the instance's width scale), and how
// many tufts fill it per (footprint / reach)^2.
uniform float mark_spread = 0.9;
uniform float mark_fill = 1.0;
// A stroke's half width at its root, in reaches (the thinnest and the broadest; 1.2 times from the
// side), and how many strokes a tuft has seen from above (the fewest and the most, at most STROKES).
// Few broad strokes are the painted manner (a few bold soft shapes, never fine hatching).
uniform vec2 mark_width = vec2(0.13, 0.18);
uniform vec2 mark_count = vec2(4.0, 5.0);
// The comb: how far a tuft's strokes fan out (radians of turn across its width) and how wide the
// band they root along is (in reaches). A small fan reads as combed grass; a wide one as a rosette.
uniform vec2 mark_comb = vec2(0.6, 0.9);
// How many more tufts a mark field keeps than the sheet's keep-grass (a factor on it, at most all):
// from above a mark field reads full where the cards' spikes read thin. Under snow it falls back to
// 1.2 (more straw tufts through the snow read as litter, not a fuller meadow).
uniform float mark_keep = 1.6;
// The oblique view's (the weight `side`, 0 from above and 1 from the side): how many more tufts the
// sheet's keep leaves (x, a factor), how many more tufts fill a footprint (y), the value of the
// colour (z; the cards' leafy clumps are darker than strokes at the ramp's lit end) and how much
// broader a stroke is (w). From above mark_keep and the plain values rule.
uniform vec4 mark_side = vec4(1.45, 1.5, 0.78, 1.35);
// The ramp's position at a root and at a tip in the sun (x, y) and in a cast shadow (z, w).
uniform vec4 mark_tone = vec4(0.85, 1.0, 0.1, 0.3);
// The value a root and a tip take (a multiplier on the ramp's colour, as the shipped cards darken
// their lit colour toward the foot), in the sun (x, y) and in a cast shadow (z, w).
uniform vec4 mark_value = vec4(0.74, 1.18, 0.86, 1.0);
// How far the marks' colour is warmed toward the ground's yellow-green (the grass role's hue is
// cooler than the floor's; the cards' thin spikes show little of it from above, a field of marks
// much more).
uniform float mark_warm = 0.16;
// How far snow tints the upper strokes toward the drift's colour at full frost.
uniform float mark_frost = 0.85;
// The tokens' feet (PainterOcclusion's tok: x, z, radius, feet height): a tuft within about a metre
// of one shrinks, so a small token stands clear of the grass.
uniform vec4 tok[32];
uniform int tok_n = 0;

// The most tufts one instance's footprint holds, and strokes one tuft has (the mesh's: keep both in
// step with PainterGrassMarks.TUFTS and STROKES).
const int MAX_TUFTS = 8;
const int STROKES = 5;
// The depth bias toward the eye (metres): across the tufts of a patch, and per stroke laid within one.
const float TUFT_BIAS = 0.08;
const float STROKE_BIAS = 0.004;

// The point on the tuft's own plane through its root, a little over the ground (for the cast shadow).
varying vec3 v_gp;
// The form's tone (0 a root, 1 a lit tip; a body below 0) and the value the oblique view takes
// (mark_side.z), passed to light().
varying float f_tone;
varying float f_dark;

// A world horizontal direction `d` (xz) on the mark's plane (x right, y up), `rx` the camera's right
// and up, horizontal parts (right.xz, up.xz).
vec2 m_proj(vec4 rx, vec2 d) {
	return vec2(dot(d, rx.xy), dot(d, rx.zw));
}

vec2 m_rot(vec2 v, float t) {
	return vec2(v.x * cos(t) - v.y * sin(t), v.x * sin(t) + v.y * cos(t));
}

// A vertex of a tuft's BODY at `e` on the unit disc (the lumpy darker mass at the foot under the
// strokes, seen from the side only): its place in the tuft's reaches and its tone.
vec2 m_body(vec4 rx, vec2 lean, float hr, float cp, float sp, float side, float sj, vec2 e,
		out float tone) {
	vec2 bc = vec2(0.0, cp * hr * 0.16) + m_proj(rx, -lean * 0.1);
	float lump = 1.0 + 0.14 * sin(3.0 * atan(e.y, e.x + 1.0e-5) + sj * 40.0);
	tone = -0.2 + 0.25 * clamp(e.y * 0.5 + 0.5, 0.0, 1.0);
	return bc + e * lump * vec2(0.5, max(cp * hr * 0.24 + 0.25 * sp, 0.04)) * side
		* vec2(1.25, 1.0);
}

// A vertex of one stroke of the tuft COMBED (the card's third way, chosen over a radial fan of
// blades, which read as maple leaves from above, and a soft mass with blade tips, which read as
// moss): `cnt` broad strokes rooted close together on the tuft's upwind side, all leaning downwind
// along the world lean and splayed like a fountain, the outer ones shorter and curling out. From the
// side the strokes stand up and droop at their tips over a darker body at the foot (a tuft wider than
// it is tall lay flat as a mat there). The vertex is at place `l` along stroke `kk` (0 root, 1 tip)
// on side `sg` (-1, 0 at the tip, 1), in the tuft's reaches from its root; `tone` and `var` are its
// tone and variant step.
vec2 m_blade(vec4 rx, vec2 lean, float hr, float cp, float sp, float side, float sj, float cnt,
		float kk, float l, float sg, out float tone, out float var) {
	vec2 perp = vec2(-lean.y, lean.x);
	float h = p_hash(vec3(sj * 53.0, kk, 5.0));
	float h2 = fract(h * 29.37);
	float h3 = fract(h * 91.13);
	float across = ((kk + 0.5) / cnt - 0.5) + (h - 0.5) * 0.16;
	// Rooted close together upwind, splayed out like a fountain leaning downwind: the outer strokes
	// turn further and reach less, so the tuft's outline is a rounded spray.
	vec2 root = m_proj(rx, -lean * mix(0.2, 0.4, h3) + perp * across * mark_comb.y);
	float turn = across * mark_comb.x + (h2 - 0.5) * 0.3;
	vec2 d = lean * cos(turn) + perp * sin(turn);
	// From the side the strokes stand up: less reach, more height and a broader stroke below about
	// 45 degrees.
	float reach = mix(0.75, 1.15, h2) * (1.0 - 0.3 * abs(across)) * mix(1.0, 0.55, side);
	float tall = hr * mix(0.65, 1.05, h3) * mix(1.0, 1.3, side);
	vec2 tip = root + m_proj(rx, d) * reach + vec2(0.0, cp * tall);
	// Seen from above the outer strokes curl outward; from the side every tip droops.
	float droop = -sign(tip.x - root.x + 1.0e-4) * 0.55 * side;
	float curl = (across * 0.6 + (h - 0.5) * 0.2) * sp + droop;
	float w = mix(mark_width.x, mark_width.y, h3) * mix(1.0, mark_side.w, side);
	vec2 dv = tip - root;
	float len = max(length(dv), 1.0e-4);
	vec2 u = dv / len;
	float hw = w * pow(max(1.0 - l, 0.0), 0.6) * (0.8 + 0.8 * l * (1.0 - l))
		* smoothstep(-0.25, 0.05, l);
	// A darker root, a lit tip, a step lighter leaning toward the sun, its own step.
	tone = pow(l, 1.2) * 0.9 + 0.05 + 0.16 * dot(d, foliage_sun.xz) + (h - 0.5) * 0.24;
	var = h2;
	return root + u * (l * len) + vec2(-u.y, u.x) * (curl * len * l * l + hw * sg);
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	// Collapsed to the origin unless this vertex is used: the body below is left by a break when the
	// instance is thinned out or the mark's tuft or stroke slot is beyond what the instance has (a
	// vertex stage may not return).
	VERTEX = o;
	vec3 cell = floor(o * 10.0);
	vec3 w = o;
	vec3 plane = o;
	float seed = 0.0;
	float tone = 0.0;
	float var = 0.5;
	float l = 0.0;
	float side = 0.0;
	bool live = false;
	do {
	if (IN_SHADOW_PASS) {
		break;
	}
	float s = length(MODEL_MATRIX[1].xyz);
	float sw = length(MODEL_MATRIX[0].xyz);
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 back = ortho ? normalize(INV_VIEW_MATRIX[2].xyz) : normalize(eye - o);
	float sp = clamp(back.y, 0.0, 1.0);
	float cp = sqrt(max(1.0 - sp * sp, 0.0));
	// The sheet's thinning in groups (painter_selector's selector_keep), mark_keep times as full seen
	// from above (from the side the standing strokes cover enough at the sheet's own keep).
	float boost = mix(mark_keep, min(mark_keep, 1.2), smoothstep(0.0, 0.4, frost));
	side = 1.0 - smoothstep(0.45, 0.9, sp);
	float k = min(keep * mix(mark_side.x, boost, smoothstep(0.5, 0.85, sp)), 1.0);
	float g = clamp((p_noise(vec3(o.x * keep_freq, 2.0, o.z * keep_freq) + 13.0) - 0.5) * 1.8 + 0.5,
		0.0, 1.0);
	float eye_d = ortho ? 1.0e6 : length(eye - o);
	float kept = (k >= 0.999 || g >= 1.0 - k) ? 1.0 : 0.0;
	kept *= ortho ? 1.0 : smoothstep(1.0, 2.0, eye_d);
	if (painter_placed > 0.5) {
		kept = 1.0;
	}
	kept *= grow_scale(o) * (grass_mark_on(o, back) ? 1.0 : 0.0);
	if (kept < 0.002) {
		break;
	}
	seed = p_hash(cell + vec3(3.0, 5.0, 11.0));
	// Each tuft its own size (no sameness), and smaller beside a token's feet.
	float own = mix(0.78, 1.22, p_hash(cell + vec3(17.0, 2.0, 9.0)));
	float room = 1.0;
	for (int i = 0; i < tok_n; i++) {
		room = min(room, smoothstep(0.0, 1.0, length(o.xz - tok[i].xy) - tok[i].z));
	}
	float H = min(selector_height * s, mark_height_max) * own * mix(0.45, 1.0, room);
	// A tuft's blades are about as long as it is tall, and never longer than a real meadow tuft's
	// (a clump core grows its instances wide and tall: it holds more tufts, not bigger ones).
	float L = max(min(H * mark_reach, mark_reach_max * own) * mix(0.7, 1.0, room), 1.0e-3);
	// The footprint the instance covers (the card's half width at the instance's width scale) holds
	// about (footprint / reach)^2 tufts, their roots spread to half a reach inside its rim.
	float F = max(selector_extent.x, selector_extent.z) * sw * mark_spread * mix(0.5, 1.0, room);
	float n = clamp(floor(F * F / (L * L) * mark_fill * mix(1.0, mark_side.y, side) + 0.5), 1.0,
		float(MAX_TUFTS));
	float j = UV2.x;
	if (j >= n) {
		break;
	}
	float fr = n > 1.5 ? max(F - 0.5 * L, 0.0) : 0.0;
	float R = fr + 1.1 * L;
	// The lean: the wind's way, turned by a slow world field so a meadow is combed in drifts.
	float turn = (p_noise(vec3(o.x * 0.13, 7.0, o.z * 0.13)) - 0.5) * 3.4 + (seed - 0.5) * 0.6;
	vec2 wd = length(wind_dir.xz) > 0.01 ? normalize(wind_dir.xz) : vec2(0.8, 0.6);
	vec2 lean = m_rot(wd, turn);
	vec2 far = up.xz - back.xz;
	far = length(far) > 1.0e-4 ? normalize(far) : vec2(0.0, -1.0);
	vec4 rx = vec4(right.x, right.z, up.x, up.z);
	// The footprint's tufts: roots on a sunflower spiral over the patch, each its own size, turn and
	// strokes.
	float hj = p_hash(vec3(seed * 71.0, j, 13.0));
	float a = j * 2.39996 + seed * 6.2832;
	vec2 off = (fr / L) * sqrt((j + 0.5) / n) * vec2(cos(a), sin(a));
	float sz = mix(0.85, 1.12, hj);
	vec2 lj = m_rot(lean, (hj - 0.5) * 0.4);
	float sj = fract(seed + hj * 7.31);
	float hr = H / L / sz;
	vec2 p;
	float rank = 0.0;
	if (UV2.y < -0.5) {
		if (side < 0.05) {
			break;
		}
		p = m_body(rx, lj, hr, cp, sp, side, sj, UV, tone);
	} else {
		// mark_count strokes from above, 4 or 5 standing from the side.
		float cnt = side > 0.5
			? 4.0 + floor(sj * 2.0)
			: mark_count.x + floor(sj * (mark_count.y - mark_count.x + 1.0));
		cnt = min(cnt, float(STROKES));
		if (UV2.y >= cnt) {
			break;
		}
		l = UV.x;
		p = m_blade(rx, lj, hr, cp, sp, side, sj, cnt, UV2.y, l, UV.y, tone, var);
		// The stroke laid last is on top: from the far side to the near one.
		rank = 1.0 + (dot(vec2(-lj.y, lj.x), far) < 0.0 ? cnt - 1.0 - UV2.y : UV2.y);
	}
	vec2 pm = L * (m_proj(rx, off) + sz * p);
	// Lifted toward the eye so no part of it cuts the ground (in the eye's perspective by at most a
	// quarter of its distance, the mark shrunk to keep its size on screen).
	float lift = min(R * cp + 0.08, eye_d * 0.25);
	float keep_size = ortho ? 1.0 : (eye_d - lift) / eye_d;
	// The nearest tuft over the others (seen from straight above, the first); then a stroke laid
	// later over the earlier ones, a body under its strokes.
	float near = 1.0 - clamp(dot(off, far) / max(fr / L, 0.05) * 0.5 + 0.5, 0.0, 1.0);
	near = mix(near, 1.0 - j / n, smoothstep(0.88, 0.92, sp));
	plane = o + right * pm.x + up * pm.y;
	w = o + (right * pm.x + up * pm.y) * keep_size
		+ back * (lift + near * TUFT_BIAS + rank * STROKE_BIAS);
	// A small sway of the mark's top along the wind (the wind foliage's own offset at its height).
	vec3 sway = wind_sway_vertex_offset(vec3(0.0, max(pm.y, 0.0) / max(s, 0.01), 0.0), COLOR,
		MODEL_MATRIX, TIME);
	float top = H * cp * 1.42 + 2.0 * R * sp;
	w += (mat3(MODEL_MATRIX) * sway) * clamp((pm.y + R * sp) / max(top, 1.0e-3), 0.0, 1.0);
	w = mix(o, w, kept);
	live = true;
	} while (false);
	if (live) {
	VERTEX = w;
	v_gp = vec3(plane.x, o.y + 0.1, plane.z);
	// The world field every neighbouring tuft shares steps the tone and the variant, so where tufts
	// overlap they merge into one mass.
	float field = p_noise(vec3(plane.x * 0.9, 1.0, plane.z * 0.9));
	float variant = floor(p_hash(cell) * 3.0) * 0.5;
	variant = mix(variant, p_noise(o * 0.12 + 40.0), 0.5);
	f_variant = mix(variant, var, 0.3) + (field - 0.5) * 0.3;
	f_tone = clamp(tone + (field - 0.5) * 0.2, -0.4, 1.0);
	f_dark = mix(1.0, mark_side.z, side);
	f_mul = mix(0.94, 1.06, seed);
	f_wob = p_noise(plane * 1.7 + 5.0);
	// Snow: a tint on the upper strokes, patchy by a world field (never a disc).
	f_frost = frost > 0.0
		? smoothstep(0.25, 0.85, l) * mix(0.6, 1.0, p_noise(plane * 2.3 + 11.0))
		: 0.0;
	}
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	// Light and shadow are read on the tuft's plane through its root, a little over the ground, with
	// the ground's up normal (as painter_plant's ground cover).
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(v_gp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

// Ground cover's light (painter_selector's kind 1: lit unless a cast shadow or a sun at the horizon),
// the tone taken along the form as the cards take it: the ramp's lit end everywhere, darkened by a
// value from a dark root to a lit tip (mark_value), a cast shadow its shade with the tips a step
// lighter. Snow tints the upper strokes toward the drift's colour, its full strength from a light
// deposit on (the sheet's crown-deposit, which reaches about 0.55 in winter).
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float sun = smoothstep(0.02, 0.1, lw.y + (f_wob - 0.5) * 0.1);
		float shd_t = mix(mark_tone.z, mark_tone.w, f_tone);
		float t = mix(shd_t, mix(mark_tone.x, mark_tone.y, f_tone), sun);
		vec3 col = selector_pal(t, f_variant + (t - 0.45) * 0.3);
		vec3 shd = selector_pal(shd_t, f_variant) * mix(mark_value.z, mark_value.w, f_tone);
		col *= mix(mix(mark_value.z, mark_value.w, f_tone), mix(mark_value.x, mark_value.y, f_tone), sun);
		vec3 c = mix(col, shd, cast * 0.94);
		c *= vec3(1.0 + mark_warm, 1.0 + mark_warm * 0.25, 1.0 - mark_warm) * f_dark;
		if (f_frost > 0.0) {
			vec3 snow = mix(c_frost_shd, c_frost_lit, sun * (1.0 - cast));
			c = mix(c, snow, f_frost * smoothstep(0.0, 0.4, frost) * mark_frost);
		}
		DIFFUSE_LIGHT += c * f_mul;
	}
}
