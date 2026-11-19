shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted grass mark (a meadow tuft under the Painted look, card painter-grass-mark)
 * ================================================================================
 *
 * A wide grass tuft drawn as ONE painted mark: a single quad (PainterGrassMarks.quad) turned to the
 * view, on which the fragment paints the tuft with brush strokes. The shipped three crossed cards
 * collapse to thin spikes seen from above (the owner's "sad and spindly"); a mark reads as a full
 * clump at every pitch for two triangles a tuft.
 *
 * The tuft is modelled in 3D and its strokes projected: the root at the tuft's origin, each stroke
 * a blade leaning out along a WORLD azimuth to a tip at its own reach and height, so the same tuft
 * is a fan of blades rising from its foot at the orbit's oblique view and a clump of blades lying
 * out from its root seen from above, and keeps its shape as the view turns. The mark's plane is
 * measured in the tuft's reach (R, metres): x across the screen, y up it, the root at the origin.
 *
 * Tone: no outline and no ring. Each stroke runs from a darker root to a lit tip, strokes that lean
 * toward the sun a step lighter, every value broken by a world field the neighbouring tufts share
 * (so a meadow's overlapping tufts merge into one grassy mass rather than stacking as stamps), and
 * the selector's ramp (painter_selector: the sheet's grass role) colours it through this shader's
 * own light(): the ramp's lit colour darkened from root to tip as the cards darken theirs, a cast
 * shadow's shade with its tips a step lighter. Winter snow is a soft tint on the upper strokes,
 * never a disc. Seen from the side a darker lumpy body grounds the standing strokes.
 *
 * Above the sheet's grass-mark-pitch only (painter_selector's grass_mark_on, a per-tuft band of a
 * few degrees): below it the cards draw and the mark collapses, so a sheet can keep the cards at
 * the oblique view and the marks from above.
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
// them at their defaults). The mark's reach against the tuft's mesh half width.
uniform float mark_size = 1.4;
// How many more tufts a mark field keeps than the sheet's keep-grass (a factor on it, at most all):
// from above a mark field reads full where the cards' spikes read thin.
uniform float mark_keep = 1.2;
// The ramp's position at a root and at a tip in the sun (x, y) and in a cast shadow (z, w).
uniform vec4 mark_tone = vec4(0.85, 1.0, 0.1, 0.3);
// The value a root and a tip take (a multiplier on the ramp's colour, as the shipped cards darken
// their lit colour toward the foot), in the sun (x, y) and in a cast shadow (z, w).
uniform vec4 mark_value = vec4(0.5, 1.12, 0.86, 1.0);
// How far snow tints the upper strokes toward the drift's colour at full frost.
uniform float mark_frost = 0.85;
// The tokens' feet (PainterOcclusion's tok: x, z, radius, feet height): a tuft within about a metre
// of one shrinks, so a small token stands clear of the grass.
uniform vec4 tok[32];
uniform int tok_n = 0;

// The fragment in the mark's plane (metres: x right, y up, from the tuft's root).
varying vec2 v_p;
// The instance's origin and scale.
varying flat vec4 v_os;
// The tuft's reach R and height H (metres), the view's topness (sin of its pitch) and the seed.
varying flat vec4 v_box;
// The camera's right and up, horizontal parts (right.xz, up.xz): a world direction's place on the mark.
varying flat vec4 v_rx;
// The tuft's lean (world xz, unit) and the way away from the camera (world xz, unit).
varying flat vec4 v_dir;
// The point on the tuft's own plane through its root (for the cast shadow and the world fields).
varying vec3 v_gp;
// The form's tone (0 a root, 1 a lit tip), passed to light().
varying float f_tone;

// A world horizontal direction `d` (xz) on the mark's plane: x right, y up.
vec2 m_proj(vec2 d) {
	return vec2(dot(d, v_rx.xy), dot(d, v_rx.zw));
}

// One blade stroke from `root` to `tip` (mark units) of half width `w` at its root, bent sideways
// by `curl` toward its tip: x 1 inside, y the place along it (0 root, 1 tip), z across (-1..1).
vec3 m_stroke(vec2 q, vec2 root, vec2 tip, float w, float curl) {
	vec2 d = tip - root;
	float len = max(length(d), 1.0e-4);
	vec2 u = d / len;
	vec2 r = q - root;
	float l = dot(r, u) / len;
	float a = (u.x * r.y - u.y * r.x) - curl * len * l * l;
	float lc = clamp(l, 0.0, 1.0);
	float hw = w * pow(1.0 - lc, 0.6) * (0.8 + 0.8 * lc * (1.0 - lc)) * smoothstep(-0.25, 0.05, l);
	float inside = step(abs(a), hw) * step(-0.25, l) * step(l, 1.0);
	return vec3(inside, clamp(l, 0.0, 1.0), a / max(hw, 1.0e-4));
}

// The tone a blade at world azimuth `d` takes at its place `l`: a darker root, a lit tip, a step
// lighter leaning toward the sun, `own` its own step.
float m_blade_tone(vec2 d, float l, float own) {
	float sun = dot(d, foliage_sun.xz);
	return pow(l, 1.2) * 0.9 + 0.05 + 0.16 * sun + (own - 0.5) * 0.24;
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 back = ortho ? normalize(INV_VIEW_MATRIX[2].xyz) : normalize(eye - o);
	float sp = clamp(back.y, 0.0, 1.0);
	float cp = sqrt(max(1.0 - sp * sp, 0.0));
	vec3 cell = floor(o * 10.0);
	float seed = p_hash(cell + vec3(3.0, 5.0, 11.0));
	// Each tuft its own size (no sameness), and smaller beside a token's feet.
	float own = mix(0.78, 1.22, p_hash(cell + vec3(17.0, 2.0, 9.0)));
	float room = 1.0;
	for (int i = 0; i < tok_n; i++) {
		room = min(room, smoothstep(0.0, 1.0, length(o.xz - tok[i].xy) - tok[i].z));
	}
	float H = selector_height * s * own * mix(0.45, 1.0, room);
	float R = max(selector_extent.x, selector_extent.z) * s * own * mark_size * mix(0.7, 1.0, room);
	// The quad covers the tuft's projection: across its reach, up from its near rim seen from above
	// to its top and far rim.
	float x = mix(-R, R, UV.x) * 1.06;
	float y = mix(H * cp * 1.42 + R * sp * 1.06, -R * sp * 1.06, UV.y);
	// Lifted toward the eye so no part of it cuts the ground (in the eye's perspective by at most a
	// quarter of its distance, the mark shrunk to keep its size on screen).
	float eye_d = ortho ? 1.0e6 : length(eye - o);
	float lift = min(R * cp + 0.08, eye_d * 0.25);
	float keep_size = ortho ? 1.0 : (eye_d - lift) / eye_d;
	vec3 plane = o + right * x + up * y;
	vec3 w = o + (right * x + up * y) * keep_size + back * lift;
	// The sheet's thinning in groups (painter_selector's selector_keep), mark_keep times as full seen
	// from above (from the side the standing strokes cover enough at the sheet's own keep).
	float k = min(keep * mix(1.0, mark_keep, smoothstep(0.5, 0.85, sp)), 1.0);
	float g = clamp((p_noise(vec3(o.x * keep_freq, 2.0, o.z * keep_freq) + 13.0) - 0.5) * 1.8 + 0.5,
		0.0, 1.0);
	float kept = (k >= 0.999 || g >= 1.0 - k) && !IN_SHADOW_PASS ? 1.0 : 0.0;
	kept *= ortho ? 1.0 : smoothstep(1.0, 2.0, eye_d);
	if (painter_placed > 0.5 && !IN_SHADOW_PASS) {
		kept = 1.0;
	}
	kept *= grow_scale(o) * (grass_mark_on(o, back) ? 1.0 : 0.0);
	// A small sway of the mark's top along the wind (the wind foliage's own offset at its height).
	vec3 sway = wind_sway_vertex_offset(vec3(0.0, max(y, 0.0) / max(s, 0.01), 0.0), COLOR,
		MODEL_MATRIX, TIME);
	w += (mat3(MODEL_MATRIX) * sway) * (1.0 - UV.y);
	w = mix(o, w, kept);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	// The lean: the wind's way, turned by a slow world field so a meadow is combed in drifts.
	float turn = (p_noise(vec3(o.x * 0.13, 7.0, o.z * 0.13)) - 0.5) * 3.4 + (seed - 0.5) * 1.1;
	vec2 wd = length(wind_dir.xz) > 0.01 ? normalize(wind_dir.xz) : vec2(0.8, 0.6);
	vec2 lean = vec2(wd.x * cos(turn) - wd.y * sin(turn), wd.x * sin(turn) + wd.y * cos(turn));
	vec2 far = up.xz - back.xz;
	far = length(far) > 1.0e-4 ? normalize(far) : vec2(0.0, -1.0);
	v_p = vec2(x, y);
	v_os = vec4(o, s);
	v_box = vec4(R, H, sp, seed);
	v_rx = vec4(right.x, right.z, up.x, up.z);
	v_dir = vec4(lean, far);
	v_gp = plane;
}

// The tuft COMBED (the card's third way, chosen over a radial fan of blades, which read as maple
// leaves from above, and a soft mass with blade tips, which read as moss): 5 to 8 strokes rooted
// close together on the tuft's upwind side, all leaning downwind along the world lean and splayed
// like a fountain, the outer ones shorter and curling out, laid from the far side to the near one.
// From the side the strokes stand up and droop at their tips over a darker body at the foot (a tuft
// wider than it is tall lay flat as a mat there). x 1 where the tuft is, y its tone, z a variant
// step, w the place along a stroke (the snow's).
vec4 m_combed(vec2 q, float hr, float cp, float sp, float seed, vec2 lean, vec2 far) {
	float side = 1.0 - smoothstep(0.45, 0.9, sp);
	// 5 to 8 strokes from above, 4 to 6 standing from the side.
	float n = side > 0.5 ? 4.0 + floor(seed * 3.0) : 5.0 + floor(seed * 4.0);
	vec2 perp = vec2(-lean.y, lean.x);
	bool flip = dot(perp, far) < 0.0;
	vec4 res = vec4(0.0);
	if (side > 0.05) {
		// The body at the foot, seen from the side only (from above it would be a core disc).
		vec2 bc = vec2(0.0, cp * hr * 0.16) + m_proj(-lean * 0.1);
		vec2 e = (q - bc) / (vec2(0.5, max(cp * hr * 0.24 + 0.25 * sp, 0.04)) * side);
		float lump = 1.0 + 0.14 * sin(3.0 * atan(e.y, e.x) + seed * 40.0);
		if (length(e) < lump) {
			res = vec4(1.0, 0.06 + 0.12 * clamp(e.y * 0.5 + 0.5, 0.0, 1.0), 0.5, 0.0);
		}
	}
	for (int k = 0; k < 8; k++) {
		float fk = float(k);
		if (fk >= n) {
			break;
		}
		float kk = flip ? n - 1.0 - fk : fk;
		float h = p_hash(vec3(seed * 53.0, kk, 5.0));
		float h2 = fract(h * 29.37);
		float h3 = fract(h * 91.13);
		float across = ((kk + 0.5) / n - 0.5) + (h - 0.5) * 0.16;
		// Rooted close together upwind, splayed out like a fountain leaning downwind: the outer
		// strokes turn further and reach less, so the tuft's outline is a rounded spray.
		vec2 root3 = -lean * mix(0.2, 0.4, h3) + perp * across * 0.55;
		float turn = across * 1.3 + (h2 - 0.5) * 0.5;
		vec2 d = lean * cos(turn) + perp * sin(turn);
		vec2 root = m_proj(root3);
		// From the side the strokes stand up (a tuft wider than it is tall lay flat as a mat at the
		// oblique view): less reach, more height and a broader stroke below about 45 degrees.
		float reach = mix(0.75, 1.15, h2) * (1.0 - 0.5 * abs(across)) * mix(1.0, 0.55, side);
		float tall = hr * mix(0.65, 1.05, h3) * mix(1.0, 1.3, side);
		vec2 tip = root + m_proj(d) * reach + vec2(0.0, cp * tall);
		// Seen from above the outer strokes curl outward; from the side every tip droops.
		float droop = -sign(tip.x - root.x + 1.0e-4) * 0.55 * side;
		float curl = (across * 0.6 + (h - 0.5) * 0.2) * sp + droop;
		vec3 st = m_stroke(q, root, tip, mix(0.15, 0.22, h3) * mix(1.0, 1.2, side), curl);
		if (st.x > 0.5) {
			res = vec4(1.0, m_blade_tone(d, st.y, h), h2, st.y);
		}
	}
	return res;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	float R = max(v_box.x, 1.0e-3);
	float hr = v_box.y / R;
	float sp = v_box.z;
	float cp = sqrt(max(1.0 - sp * sp, 0.0));
	float seed = v_box.w;
	vec2 q = v_p / R;
	vec4 res = m_combed(q, hr, cp, sp, seed, v_dir.xy, v_dir.zw);
	if (res.x < 0.5) {
		discard;
	}
	// The world field every neighbouring tuft shares steps the tone and the variant, so where tufts
	// overlap they merge into one mass.
	vec3 o = v_os.xyz;
	float field = p_noise(vec3(v_gp.x * 0.9, 1.0, v_gp.z * 0.9));
	float variant = floor(p_hash(floor(o * 10.0)) * 3.0) * 0.5;
	variant = mix(variant, p_noise(o * 0.12 + 40.0), 0.5);
	f_variant = mix(variant, res.z, 0.3) + (field - 0.5) * 0.3;
	f_tone = clamp(res.y + (field - 0.5) * 0.2, 0.0, 1.0);
	f_mul = mix(0.94, 1.06, seed);
	f_wob = p_noise(v_gp * 1.7 + 5.0);
	f_n = vec3(0.0, 1.0, 0.0);
	f_accent = -1.0;
	// Snow: a tint on the upper strokes, patchy by a world field (never a disc).
	f_frost = frost > 0.0
		? smoothstep(0.25, 0.85, res.w) * mix(0.6, 1.0, p_noise(v_gp * 2.3 + 11.0))
		: 0.0;
	// Light and shadow are read on the tuft's plane through its root, a little over the ground, with
	// the ground's up normal (as painter_plant's ground cover).
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(v_gp.x, o.y + 0.1, v_gp.z, 1.0)).xyz;
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
		if (f_frost > 0.0) {
			vec3 snow = mix(c_frost_shd, c_frost_lit, sun * (1.0 - cast));
			c = mix(c, snow, f_frost * smoothstep(0.0, 0.4, frost) * mark_frost);
		}
		DIFFUSE_LIGHT += c * f_mul;
	}
}
