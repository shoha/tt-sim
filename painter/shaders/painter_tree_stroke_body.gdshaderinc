// The strokes' body, included by painter_tree_stroke.gdshader (a tree in leaf) and
// painter_tree_stroke_bare.gdshader (TREE_BARE: a bare season's leaf drop; card
// painter-winter-trees2: the drop's code in every season cost the eye view 0.23 ms in summer).
// Round 10 strokes of TREES. The look is stroke8.txt's (tree paths only); what changed is where a
// stroke comes from. There is no stroke mesh per tree: one shared block of quads is instanced,
// and the vertex stage builds each stroke from a data texture.
//   The source marker further down is replaced by one of
//     stroke10_src_b.txt  approach B (chosen): the stroke is DERIVED from its mass (an ellipsoid
//                         or a strand segment in mass_tex) and a hash of (mass seed, root, child)
//     stroke10_src_a.txt  approach A (probe): the stroke is READ, 24 bytes, from a_tex
//   Both fill the same locals; the rest of the shader does not know which ran.
// A stroke that is not drawn (wrong level, back-facing, thinned by the calm rule, past the end
// of its tree) leaves the vertex stage early with all four corners at one point.
// Instance: transform of the tree, INSTANCE_CUSTOM (tree row, first unit of this instance, [A: end]).
// Mesh: UV the quad corner, UV2.x the quad's index in the block.
// tree_tex, one row per tree: 0 (layer, base texel, ellipsoids, segments) 1 (segment table,
//   slot table, slots, instance line in row_map) 2 (hue + 0.5, value + 0.5, thin, moss)
//   3 (crown centre, has crown) 4 (crown radii, several leaf forms) 5 (bounding sphere: centre,
//   radius; tree_in_view) 7 (shadow table, shadow entries).

#include "res://painter/shaders/painter_tree.gdshaderinc"

uniform sampler2DArray brushes : filter_linear_mipmap, repeat_disable;
uniform float stroke_scale = 1.0;
uniform float lod_level = 1.0;
uniform float painted_shadows = 1.0;
uniform float ground_y = 0.0;
uniform float silhouette = 0.0;
uniform float cap_on = 2.0;
uniform float bare = 0.0;
uniform float px_m = 0.0128;
uniform float far_rim = 0.35;

uniform sampler2DArray mass_tex : filter_nearest, repeat_disable;
uniform sampler2D tree_tex : filter_nearest, repeat_disable;
uniform sampler2D a_tex : filter_nearest, repeat_disable;
// Shadow strokes: one in shadow_k of round 8's, shadow_f times the size (round 9's saving).
uniform float shadow_k = 3.0;
uniform float shadow_f = 1.55;
// 1 = every stroke leaves early (measures what the vertex stage costs before the early exit).
uniform float kill10 = 0.0;
// A stroke whose root normal faces further from the camera than this (cosine) is not built: it
// sits behind its own clump. -2 = off (every stroke is built, as round 8 did).
uniform float back10 = -2.0;
// The burial test's threshold (squared unit radius inside a neighbouring clump); 0 = off.
uniform float bury10 = 0.72;
// Round 11, a mask of its changes (0 = round 10's strokes exactly):
//   4  a bark stroke lies INSIDE its limb's outline: no wider than the limb, moved in from the
//      edge by its own half width, run along the grain, and toned by where it lies across the
//      round limb (so the strokes of a trunk share the block-in's one light and one shade side)
//   8  a pine bough (ellipsoid flag 256): needle flicks along the twig at its edge, calm level
//      dabs inside, a flat underside
//   16 the burial test is made where the stroke itself lies (level 1), as round 8 did, not only
//      at its root
uniform float fix11 = 0.0;
// Round 12, a mask of its changes (0 = round 11's strokes exactly):
//   1  a willow's strand mass (ellipsoid flag 512) tapers to a hem, and its strokes with it
//   2  pine boughs: needle flicks in fewer, larger tufts and of unequal size; unequal dabs
//   4  bark: the block-in carries the species' pattern (blockin12.txt), so plain bark strokes
//      are thinned where a role has a mark, a block mark (the pine's plates) is not stroked at
//      all, limbs down to one pixel wide keep their strokes, and a pine's strokes turn from
//      grey-brown to orange at the height the block-in does
uniform float fix12 = 0.0;
// Round 13, a mask of its changes (0 = round 12's strokes exactly):
//   1  a strand mass is a bent spindle (blockin13.txt) and its strokes run ALONG the strand where
//      they lie, each a little off its neighbour (round 12: every stroke exactly vertical)
//   2  moss: a low patch on the shaded side of the foot (as the block-in)
//   4  a trim mark on foliage (the rowan's berries) is drawn only inside a few BUNCHES (a slow
//      noise picks them, on the sides and underside of the crown), many small dabs together,
//      hung a little below their leaf (round 12: one mark in five strokes, anywhere)
uniform float fix13 = 0.0;
// Which strokes this node draws: 0, 1, 2 the level; 3 the shadow strokes.
uniform float pass10 = 1.0;
// painter-perf-forest's A/B switch (0 = the shipped path): 2 every stroke runs the token window's
// loops (no tree_token_near). (Skipping form_occ's ray where it could not change the tone was
// measured too: 0.007 ms at forest tokens, not kept.)
uniform int perf_off = 0;

varying flat vec3 v_col;
varying flat float v_brush;
varying vec2 v_uv;
// tt-sim: the stroke's canopy fade key (-1 a stem stroke, kept); the fragment's world point for
// light()'s cast step (light() has no VERTEX).
varying flat float v_key;
varying vec3 v_wp_light;

vec4 mt(int addr, int layer) {
	return texelFetch(mass_tex, ivec3(addr & 255, addr >> 8, layer), 0);
}

// True when `pt` lies inside one of the four neighbours listed in the clump's texel 9.
bool buried11(vec3 pt, int rec, int base, int layer) {
	vec4 e9 = mt(rec + 9, layer);
	for (int nb = 0; nb < 4; nb++) {
		if (e9[nb] > -0.5) {
			int nr = base + int(e9[nb] + 0.5);
			vec3 nq = pt - mt(nr, layer).xyz;
			vec3 x1 = mt(nr + 1, layer).xyz;
			vec3 x2 = mt(nr + 2, layer).xyz;
			vec3 x3 = mt(nr + 3, layer).xyz;
			vec3 nu = vec3(dot(nq, x1) / dot(x1, x1), dot(nq, x2) / dot(x2, x2), dot(nq, x3) / dot(x3, x3));
			if (dot(nu, nu) < bury10) {
				return true;
			}
		}
	}
	return false;
}

uint h10(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

// A random number in 0..1 for (mass seed, key, channel).
float r10(uint seed, uint key, uint ch) {
	return float(h10(seed * 2654435769u + h10(key * 2246822519u + ch * 3266489917u + 1u)) >> 8u) / 16777216.0;
}

bool level_shown(float rnd, float level, float lam_in) {
	float vis = (1.0 - smoothstep(0.5, 1.0, abs(clamp(lam_in, 0.0, 2.0) - level))) * 1.3;
	return vis > fract(rnd * 3.71 + 0.137) + 0.0001;
}

vec3 fib10(int i, int count, float spin) {
	float y = 1.0 - 2.0 * (float(i) + 0.5) / float(count);
	float r = sqrt(max(1.0 - y * y, 0.0));
	float a = spin + 2.39996323 * float(i);
	return vec3(cos(a) * r, y, sin(a) * r);
}

void ell_at(vec3 u, vec3 c, vec3 mx, vec3 my, vec3 mz, out vec3 p, out vec3 n) {
	p = c + mx * u.x + my * u.y + mz * u.z;
	n = normalize(mx * (u.x / dot(mx, mx)) + my * (u.y / dot(my, my)) + mz * (u.z / dot(mz, mz)));
}

vec3 ell_u(vec3 p, vec3 c, vec3 mx, vec3 my, vec3 mz) {
	vec3 d = p - c;
	return normalize(vec3(dot(mx, d) / dot(mx, mx), dot(my, d) / dot(my, my), dot(mz, d) / dot(mz, mz)) + vec3(0.0, 1e-7, 0.0));
}

vec3 form_n(vec3 p, vec3 c, vec3 r) {
	vec3 q = (p - c) / r;
	return dot(q, q) > 1e-8 ? normalize(q) : vec3(0.0, 1.0, 0.0);
}

// `t` (perpendicular to `n`) turned about `n`.
vec3 rot_about(vec3 t, vec3 n, float a) {
	return t * cos(a) + cross(n, t) * sin(a);
}

// A child's place in its parent's footprint (PPainter2._child): quarter q, jittered.
vec3 child_off(vec3 n, int q, uint seed, uint key, float s) {
	vec3 t1 = cross(n, vec3(0.0, 1.0, 0.0));
	if (dot(t1, t1) < 1e-4) {
		t1 = cross(n, vec3(1.0, 0.0, 0.0));
	}
	t1 = normalize(t1);
	vec3 t2 = cross(n, t1);
	float sx = ((q & 1) != 0 ? 0.25 : -0.25) + (r10(seed, key, 1u) - 0.5) * 0.2;
	float sz = ((q & 2) != 0 ? 0.25 : -0.25) + (r10(seed, key, 2u) - 0.5) * 0.2;
	return (t1 * sx + t2 * sz) * s;
}

// The point of a strand segment's surface nearest `pc`.
void strand_proj(vec3 pc, vec4 pa, vec4 pb, vec3 n_in, out vec3 p, out vec3 n) {
	vec3 sv = pb.xyz - pa.xyz;
	float f = clamp(dot(pc - pa.xyz, sv) / max(dot(sv, sv), 1e-9), 0.0, 1.0);
	vec3 qv = pa.xyz + sv * f;
	vec3 tg = normalize(sv);
	vec3 o = pc - qv;
	o -= tg * dot(o, tg);
	n = dot(o, o) > 1e-10 ? normalize(o) : n_in;
	p = qv + n * mix(pa.w, pb.w, f);
}

// The long axis of a stroke in the tangent plane (PPainter.stroke_dir): `ref` projected, turned
// a quarter when `across`, then twisted.
vec3 dir_of(vec3 ref, vec3 n, bool across, float twist) {
	vec3 t = ref - n * dot(ref, n);
	if (dot(t, t) < 1e-4) {
		t = vec3(1.0, 0.0, 0.0) - n * n.x;
	}
	if (dot(t, t) < 1e-4) {
		t = vec3(0.0, 0.0, -1.0) + n * n.z;
	}
	t = normalize(t);
	if (across) {
		t = normalize(cross(n, t));
	}
	return rot_about(t, n, twist);
}

float e_lift_at(vec3 p, float near, float n_y, float spread) {
	float down = smoothstep(0.0, 0.5, -n_y);
	float m = p_noise(p * 0.7 + 31.0) + (near * mix(0.5, 1.0, down) - 1.0) * 0.35 + spread;
	vec2 e_q = vec2(p.x * 0.8 + p.z * 0.6, p.z * 0.8 - p.x * 0.6);
	m += (p_noise(vec3(e_q.x * 1.5, e_q.y * 4.6, p.y * 1.9) + 7.0) - 0.5) * 0.22 * 1.0 * near;
	m += (p_noise(vec3(e_q.x * 3.4, e_q.y * 11.0, p.y * 4.0) + 21.0) - 0.5) * 0.14 * 1.0 * near;
	return 0.1 + 0.2 * step(0.44, m) + 0.2 * step(0.53, m) + 0.3 * step(0.63, m) * down;
}

void vertex() {
	bool alive = false;
	bool is_shadow = false;
	float role = 0.0;
	float rnd = 0.0;
	float level = 1.0;
	float rho = 0.0;
	float tone_rnd = 0.0;
	float size_rnd = 0.0;
	float shadow_size = 0.0;
	float flutter = 0.0;
	float wphase = 0.0;
	float ww0 = 0.0;
	float mass_m = 0.0;
	int fl = 8;
	int inst = 0;
	float hue_o = 0.0;
	float value_o = 0.0;
	float thin_i = 0.0;
	float moss = 0.0;
	vec3 a_p = vec3(0.0);
	// tt-sim (painter-trees-fix): the centre of a foliage stroke's clump (the token window takes a
	// clump's strokes together); has_clump false for a stroke of no clump.
	vec3 clump_p = vec3(0.0);
	bool has_clump = false;
	vec3 a_n = vec3(0.0, 1.0, 0.0);
	vec3 a_d = vec3(1.0, 0.0, 0.0);
	vec3 a_tn = vec3(0.0, 1.0, 0.0);
	vec3 a_fn = vec3(0.0, 1.0, 0.0);
	// Round 11: the limb a bark stroke sits on (axis point, tangent, radius there; 0 = not bark),
	// and a pine bough's twig direction.
	float limb_r = 0.0;
	vec3 limb_q = vec3(0.0);
	vec3 limb_tg = vec3(0.0, 1.0, 0.0);
	bool bough = false;
	vec3 a_tw = vec3(0.0, 1.0, 0.0);
	int fix = int(fix11 + 0.5);
	int fix2 = int(fix12 + 0.5);
	int fix3 = int(fix13 + 0.5);
	// Round 13: the direction of the strand a stroke lies on (zero = not a strand mass).
	vec3 own13 = vec3(0.0);
	float rise12 = 1000.0;
	// Round 15: how far down its strand a stroke lies (0 the twig .. 1 the hem); a snow dab on a
	// limb; a fallen leaf.
	float hem15 = 0.0;
	bool snow15 = false;
	bool leaf15 = false;
	// Round 17: a snow mark's tone on a limb's ridge; a mark's own hash for the ground under it.
	float snow_t17 = 0.9;
	float gh17 = 0.5;
	// Round 18: a limb's base radius, how far along it a mark lies, is it the stem; a shadow mark's
	// piece of its limb (vector, radius).
	float limb_base18 = 0.0;
	float limb_along18 = 0.0;
	bool stem18 = false;
	vec3 sh_sv18 = vec3(0.0);
	float sh_r18 = 0.0;
	bool e_persp = PROJECTION_MATRIX[3][3] == 0.0 && e_far < 0.5;
	float e_d = length((INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz) * vec3(1.0, 0.6, 1.0));
	float e_view = max(e_d, 1.0) * 2.0 / PROJECTION_MATRIX[1][1];
	float e_lam = e_persp ? mix(clamp(1.0 - log2(e_view / 13.850000) - 0.400000, -1.0, 1.600000), lod_level, e_far) : lod_level;
	float e_px = e_persp ? e_view / VIEWPORT_SIZE.y : px_m;
	float e_near = e_persp ? 1.0 - smoothstep(14.0, 40.0, e_d) : 0.0;
	float e_lift = 0.0;
	VERTEX = vec3(0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	v_col = vec3(0.0);
	v_brush = 0.0;
	v_uv = vec2(0.0);

	// One pass: `break` leaves the stage early (a vertex stage cannot `return`), the outputs above
	// stay as they are (a collapsed vertex).
	for (int once = 0; once < 1; once++) {
	// ---- Source B: derive the stroke from its mass (layouts in painter10.gd).
	// (painter-perf-forest, painter-perf-cull: with view_cull on, a tree outside this pass's view
	// builds no stroke, tree_view_box.)
	vec3 box_c;
	vec3 box_h;
	if (tree_view_box(texelFetch(tree_tex, ivec2(5, int(INSTANCE_CUSTOM.x + 0.5)), 0),
			texelFetch(tree_tex, ivec2(6, int(INSTANCE_CUSTOM.x + 0.5)), 0), MODEL_MATRIX, VIEW_MATRIX,
			PROJECTION_MATRIX, e_px, box_c, box_h)) {
		int trow = int(INSTANCE_CUSTOM.x + 0.5);
		int first = int(INSTANCE_CUSTOM.y + 0.5);
		vec4 t0 = texelFetch(tree_tex, ivec2(0, trow), 0);
		vec4 t1 = texelFetch(tree_tex, ivec2(1, trow), 0);
		int layer = int(t0.x + 0.5);
		int base = int(t0.y + 0.5);
		int pass = int(pass10 + 0.5);
		vec3 vcam10 = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz) : normalize(INV_VIEW_MATRIX[2].xyz);
		is_shadow = pass == 3;
		int lvl = is_shadow ? 0 : pass;
		level = is_shadow ? 1.0 : float(lvl);
		int per_root = lvl == 0 ? 1 : (lvl == 1 ? 4 : 16);
		int q = int(UV2.x + 0.5);
		// A level's quad is root `wi / per_root` of slot `slot` (two roots a slot); a shadow quad
		// is one entry of the tree's shadow table.
		int slot = first + (is_shadow ? q : q / (2 * per_root));
		int wi = is_shadow ? 0 : q % (2 * per_root);
		vec4 t7 = texelFetch(tree_tex, ivec2(7, trow), 0);
		if (slot < (is_shadow ? int(t7.y + 0.5) : int(t1.z + 0.5))) {
			vec4 st = mt(base + (is_shadow ? int(t7.x + 0.5) : int(t1.y + 0.5)) + slot, layer);
			int rec = base + int(st.x + 0.5);
			int k = int(st.w + 0.5) + wi / per_root;
			int c1 = lvl >= 1 ? (wi / (per_root / 4)) % 4 : 0;
			int c2 = wi % 4;
			uint key0 = uint(k);
			uint key1 = uint(k * 4 + c1) + 1000000u;
			uint key2 = uint(k * 16 + c1 * 4 + c2) + 2000000u;
			uint keyl = lvl == 0 ? key0 : (lvl == 1 ? key1 : key2);
			if (is_shadow) {
				keyl = key0 + 3000000u;
			}
			uint seed = 0u;
			if (st.y < -0.5) {
				// An ellipsoid: a clump of foliage (or the hollow of an old stem).
				vec4 e0 = mt(rec, layer);
				vec4 e8 = mt(rec + 8, layer);
				seed = uint(e8.x + 0.5);
				rnd = r10(seed, keyl, 4u);
				bool leafy = e0.w < 0.5 || e0.w > 7.5;
				// tt-sim (painter-winter-trees): a clump a bare season dropped draws nothing, nor
				// its shadow strokes.
#ifdef TREE_BARE
				float drop = e0.w < 0.5 ? tree_leaf_drop(int(t1.w + 0.5)) : 0.0;
				bool fallen = tree_leaf_fallen(e8.x, drop);
				// A kept clump of a bare tree is loose: a share of its strokes (no block-in under them).
				fallen = fallen || (drop > 0.0 && !is_shadow && r10(seed, keyl, 24u) > TREE_DRY_STROKES);
#else
				// In leaf: constants, so the compiler folds every drop test away.
				const float drop = 0.0;
				const bool fallen = false;
#endif
				if (is_shadow) {
					int n_sh = int(st.z + 0.5);
					if (!(bare > 0.5 && e0.w < 0.5) && !fallen) {
						alive = true;
						vec4 e1 = mt(rec + 1, layer);
						vec4 e2 = mt(rec + 2, layer);
						vec4 e3 = mt(rec + 3, layer);
						vec3 u = fib10(k, n_sh, r10(seed, 0u, 14u) * 6.2832);
						a_p = e0.xyz + (e1.xyz * u.x + e2.xyz * u.y + e3.xyz * u.z) * 1.06;
						float sa = (r10(seed, keyl, 8u) - 0.5) * 1.2;
						a_d = vec3(cos(sa), 0.0, -sin(sa));
						role = 6.0;
						rho = 0.5;
						shadow_size = e8.z * shadow_f;
						fl = 8 + (e0.w < 0.5 ? 16 : 0);
						wphase = e2.w;
						ww0 = e3.w;
						tone_rnd = r10(seed, keyl, 3u);
					}
				} else {
					vec4 e6 = mt(rec + 6, layer);
					int n_roots = int(e6.w + 0.5);
					if (k < n_roots && !fallen && level_shown(rnd, level, e_lam) && !(bare > 0.5 && leafy)) {
						clump_p = e0.xyz;
						has_clump = leafy;
						alive = true;
						vec4 e1 = mt(rec + 1, layer);
						vec4 e2 = mt(rec + 2, layer);
						vec4 e3 = mt(rec + 3, layer);
						vec4 e4 = mt(rec + 4, layer);
						vec4 e5 = mt(rec + 5, layer);
						int efl = int(e1.w + 0.5);
						vec3 p;
						vec3 n;
						ell_at(fib10(k, n_roots, r10(seed, 0u, 7u) * 6.2832), e0.xyz, e1.xyz, e2.xyz, e3.xyz, p, n);
						vec3 p_root = p;
						vec3 n_root = n;
						// A root that faces well away from the camera is behind its own clump. (A bare
						// tree's kept clump has no block-in behind its strokes: its far side's strokes
						// showed through as black dabs, so they are not built.)
						alive = dot(mat3(MODEL_MATRIX) * n_root, vcam10) >= back10;
						// Round 8's burial test, against the clump's four most overlapping
						// neighbours: a root inside one of them paints nothing.
						// (Not on a bare tree: its neighbours have mostly fallen, and burying in them cut
							// the kept clumps into hollow rings.)
							bool bury_on = bury10 > 0.0 && drop <= 0.0;
							if (bury_on) {
							vec4 e9 = mt(rec + 9, layer);
							for (int nb = 0; nb < 4; nb++) {
								if (alive && e9[nb] > -0.5) {
									int nr = base + int(e9[nb] + 0.5);
									vec3 nq = p_root - mt(nr, layer).xyz;
									vec3 x1 = mt(nr + 1, layer).xyz;
									vec3 x2 = mt(nr + 2, layer).xyz;
									vec3 x3 = mt(nr + 3, layer).xyz;
									vec3 nu = vec3(dot(nq, x1) / dot(x1, x1), dot(nq, x2) / dot(x2, x2), dot(nq, x3) / dot(x3, x3));
									alive = dot(nu, nu) >= bury10;
								}
							}
						}
						if (alive) {
						if (lvl >= 1) {
							vec3 pc = p + child_off(n, c1, seed, key1, e5.w);
							ell_at(ell_u(pc, e0.xyz, e1.xyz, e2.xyz, e3.xyz), e0.xyz, e1.xyz, e2.xyz, e3.xyz, p, n);
							// Round 11: the level 1 stroke is tested where it lies (round 8 did; its
							// level 2 children go with it).
							if ((fix & 16) != 0 && bury_on && buried11(p, rec, base, layer)) {
								alive = false;
							}
						}
						// The form normal and rho are those of the level 1 stroke (its children share them).
						vec3 pf = p;
						if (lvl == 2) {
							vec3 pc2 = p + child_off(n, c2, seed, key2, e5.w * 0.5);
							ell_at(ell_u(pc2, e0.xyz, e1.xyz, e2.xyz, e3.xyz), e0.xyz, e1.xyz, e2.xyz, e3.xyz, p, n);
						}
						a_p = p;
						if ((efl & 512) != 0 && (fix2 & 1) != 0) {
							// Round 12: a willow's strand mass tapers to its hem.
							float uy = clamp(dot(a_p - e0.xyz, e2.xyz) / dot(e2.xyz, e2.xyz), -1.0, 1.0);
							float tq = (1.0 - uy) * 0.5;
							float l0 = max(2.0 * sqrt(max(tq * (1.0 - tq), 0.0)), 0.08);
							if ((fix3 & 1) != 0) {
								// Round 13: a spindle from the twig to a pointed hem, bent out and
								// down; the stroke runs along the strand where it lies.
								vec3 bend = mt(rec + 7, layer).xyz;
								float prof = mix(0.8, 1.0, smoothstep(0.0, 0.22, tq)) * pow(max(1.0 - smoothstep(0.22, 1.0, tq), 0.0), 0.75);
								a_p += ((a_p - e0.xyz) - e2.xyz * uy) * (min(prof / l0, 3.0) - 1.0);
								a_p += bend * (1.0 - (1.0 - tq) * (1.0 - tq));
								own13 = normalize(bend * (1.0 - tq) - e2.xyz); hem15 = tq;
							} else {
							float lk = min(smoothstep(0.0, 0.1, tq) * mix(1.0, 0.4, smoothstep(0.15, 1.0, tq)) / l0, 3.0);
							a_p += ((a_p - e0.xyz) - e2.xyz * uy) * (lk - 1.0);
							a_p += e2.xyz * (1.0 - 2.0 * (tq < 0.1 ? tq * 0.25 : 0.025 + (tq - 0.1) * (0.975 / 0.9)) - uy);
							}
						}
						if (drop > 0.0) {
							// A bare tree's kept clump is a small knot of dry leaves: its strokes drawn in
							// toward the clump's middle (on the whole clump they read as a hollow ring).
							a_p = mix(e0.xyz, a_p, TREE_DRY_SHRINK);
						}
						a_n = n;
						a_tn = (efl & 128) != 0 ? normalize(mix(n_root, normalize(p_root - e6.xyz), 0.45)) : n_root;
						a_fn = a_tn;
						if ((efl & 4) != 0) {
							vec4 t3 = texelFetch(tree_tex, ivec2(3, trow), 0);
							vec4 t4 = texelFetch(tree_tex, ivec2(4, trow), 0);
							bool blend = (efl & 16) != 0;
							vec3 fnv = form_n(pf, e4.xyz, e5.xyz);
							if (blend) {
								fnv = normalize(fnv * 0.6 + form_n(pf, t3.xyz, t4.xyz) * 0.4);
							}
							a_fn = fnv;
							rho = clamp(length((pf - (blend ? t3.xyz : e4.xyz)) / (blend ? t4.xyz : e5.xyz)), 0.0, 1.0);
						}
						// The stroke's long axis: a whorl's fronds run out and down from its apex, a
						// hanging pad's marks hang, everything else lies across the up direction.
						float jr = r10(seed, keyl, 8u) - 0.5;
						bool done = false;
						if ((efl & 256) != 0 && (fix & 8) != 0) {
							// A pine bough: flat beneath; its dabs lie level, its twigs run out from
							// where the bough leaves the limb and up.
							bough = true;
							if (a_p.y < e0.y) {
								a_p.y = e0.y + (a_p.y - e0.y) * 0.4;
							}
							vec4 e7 = mt(rec + 7, layer);
							vec3 dd = normalize(vec3(p.x - e7.x, 0.0, p.z - e7.z) + vec3(0.0001, 0.0, 0.0));
							a_tw = normalize(dd - vec3(0.0, 1.0, 0.0) * e7.w + vec3(jr, 0.0, -jr) * 0.5);
							a_d = dir_of(vec3(0.0, 1.0, 0.0), n, true, jr * 0.5);
							done = true;
						}
						if (!done && (efl & 32) != 0) {
							vec4 e7 = mt(rec + 7, layer);
							vec3 dd = vec3(p.x - e7.x, 0.0, p.z - e7.z);
							if (dot(dd, dd) > 1e-5) {
								dd = normalize(dd) - vec3(0.0, 1.0, 0.0) * e7.w;
								vec3 tt = dd - n * dot(dd, n);
								if (dot(tt, tt) > 1e-4) {
									a_d = rot_about(normalize(tt), n, jr * 0.5);
									done = true;
								}
							}
						}
						if (!done && (efl & 64) != 0) {
							vec3 tt = vec3(0.0, -1.0, 0.0) + n * n.y;
							if (dot(tt, tt) > 1e-4) {
								a_d = rot_about(normalize(tt), n, jr * 0.6);
								done = true;
							}
						}
						if (!done) {
							bool trim = abs(e0.w - 5.0) < 0.5;
							a_d = dir_of(trim ? normalize(e2.xyz) : vec3(0.0, 1.0, 0.0), n, !trim, jr * (trim ? 0.1 : 2.2));
						}
						role = e0.w;
						fl = 8 | (efl & 5);
						mass_m = e4.w;
						wphase = e2.w;
						ww0 = e3.w;
						tone_rnd = r10(seed, key0, 3u);
						}
					}
				}
			} else {
				// A strand segment: bark.
				int seg = int(st.y + 0.5);
				vec4 h0 = mt(rec, layer);
				vec4 h1 = mt(rec + 1, layer);
				int hfl = int(h1.y + 0.5);
				vec4 pa = mt(rec + 2 + seg, layer);
				vec4 pb = mt(rec + 3 + seg, layer);
				seed = uint(h1.w + 0.5) + uint(seg) * 7919u;
				rnd = r10(seed, keyl, 4u);
				vec3 sv = pb.xyz - pa.xyz;
				float len = max(length(sv), 1e-5);
				vec3 tg = sv / len;
				int steps = int(st.z + 0.5) & 255;
				int around = int(st.z + 0.5) >> 8;
				if (is_shadow) {
					float r0m = (pa.w + pb.w) * 0.5;
					int n_sh = int(st.z + 0.5);
					{
						alive = true;
						a_p = pa.xyz + sv * ((float(k) + r10(seed, keyl, 11u)) / float(n_sh));
						float sa = (r10(seed, keyl, 8u) - 0.5) * 1.2;
						a_d = vec3(cos(sa), 0.0, -sin(sa));
						role = 6.0;
						rho = 0.5;
						shadow_size = clamp(r0m * 2.6 + 0.2, 0.3, 1.2) * shadow_f;
						// Round 18: what a limb's shadow mark needs to lie along its limb.
						{
							float fq18 = (float(k) + r10(seed, keyl, 11u)) / float(n_sh);
							int np18 = int(h1.x + 0.5);
							limb_base18 = mt(rec + 2, layer).w;
							limb_along18 = (float(seg) + fq18) / float(max(np18 - 1, 1));
							sh_sv18 = sv / float(n_sh);
							sh_r18 = mix(pa.w, pb.w, fq18);
						}
						fl = 8;
						wphase = h0.y;
						ww0 = h0.z;
						tone_rnd = r10(seed, keyl, 3u);
					}
				} else if (k < steps * around && level_shown(rnd, level, e_lam)) {
					alive = true;
					vec3 ref = abs(tg.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
					vec3 b1 = normalize(cross(tg, ref));
					vec3 b2 = normalize(cross(tg, b1));
					int sk = k / around;
					float f = (float(sk) + r10(seed, uint(sk), 11u)) / float(steps);
					float ang = r10(seed, uint(sk), 12u) * 6.2832 + 6.2832 * float(k % around) / float(around);
					vec3 n = b1 * cos(ang) + b2 * sin(ang);
					float r = mix(pa.w, pb.w, f);
					vec3 p = pa.xyz + sv * f + n * r;
					vec3 p_root = p;
					vec3 n_root = n;
					alive = dot(mat3(MODEL_MATRIX) * n_root, vcam10) >= back10;
					if (alive) {
					if (lvl >= 1) {
						strand_proj(p + child_off(n, c1, seed, key1, h1.z), pa, pb, n_root, p, n);
					}
					if (lvl == 2) {
						vec3 n1 = n;
						strand_proj(p + child_off(n, c2, seed, key2, h1.z * 0.5), pa, pb, n1, p, n);
					}
					a_p = p;
					a_n = n;
					a_tn = n_root;
					a_fn = n_root;
					ww0 = h0.z;
					if ((hfl & 4) != 0) {
						vec4 t3 = texelFetch(tree_tex, ivec2(3, trow), 0);
						vec4 t4 = texelFetch(tree_tex, ivec2(4, trow), 0);
						float fa = pow(clamp(distance(p_root, mt(rec + 2, layer).xyz) / max(h0.x, 0.01), 0.0, 1.0), 1.5);
						ww0 = mix(h0.z, h0.w, fa);
						rho = clamp(length((p_root - t3.xyz) / t4.xyz), 0.0, 1.0) * fa;
					}
					mass_m = max(r * 3.4, 0.09);
					{
						float qf = clamp(dot(p - pa.xyz, sv) / max(dot(sv, sv), 1e-9), 0.0, 1.0);
						limb_q = pa.xyz + sv * qf;
						limb_r = mix(pa.w, pb.w, qf);
						limb_tg = tg;
						// Round 18: the limb's radius at its base, how far along it this is, is it the stem.
						limb_base18 = mt(rec + 2, layer).w;
						limb_along18 = (float(seg) + qf) / float(max(int(h1.x + 0.5) - 1, 1));
						stem18 = (hfl & 8) != 0;
						if ((fix2 & 4) != 0) {
							vec4 c3 = texelFetch(tree_tex, ivec2(3, trow), 0);
							vec4 c4 = texelFetch(tree_tex, ivec2(4, trow), 0);
							rise12 = c3.w > 0.5 ? max((c3.y - c4.y) * 0.62, 0.8) : 1000.0;
						}
					}
					a_d = dir_of(tg, n, false, (r10(seed, keyl, 8u) - 0.5) * 0.3);
					role = 1.0;
					fl = 8 | (hfl & 2);
					wphase = h0.y;
					tone_rnd = r10(seed, key0, 3u);
					}
				}
			}
			if (alive) {
				vec4 t2 = texelFetch(tree_tex, ivec2(2, trow), 0);
				inst = int(t1.w + 0.5);
				hue_o = t2.x - 0.5;
				value_o = t2.y - 0.5;
				thin_i = t2.z;
				moss = t2.w;
				size_rnd = r10(seed, keyl, 5u);
				flutter = r10(seed, keyl, 6u);
			}
		}
	}


	if (alive) {
		bool frond = (fl & 1) != 0;
		float under = (fl & 2) != 0 ? 1.0 : 0.0;
		float has_form = (fl & 4) != 0 ? 1.0 : 0.0;
		float flex = (fl & 8) != 0 ? 1.0 : 0.0;
		float srow = row_of(role, inst);
		int ri = int(srow + 0.5);
		vec4 rp0 = texelFetch(role_params, ivec2(ri, 0), 0); // size, aspect, brush, density
		vec4 rp1 = texelFetch(role_params, ivec2(ri, 1), 0); // align, lift, jitter, size var
		vec4 rp2 = texelFetch(role_params, ivec2(ri, 2), 0); // patch mix, patch freq, deposit weight, block-in
		vec4 rp3 = texelFetch(role_params, ivec2(ri, 3), 0); // hang, sky, layer, rise
		vec4 rp4 = texelFetch(role_params, ivec2(ri, 4), 0); // mark, mark value, turn + 2 trim, mark size
		vec4 rp5 = texelFetch(role_params, ivec2(ri, 5), 0); // cap, far, mark brush, mark aspect
		vec4 rp6 = texelFetch(role_params, ivec2(ri, 6), 0); // grain, fill
		bool foliage = role < 0.5 || role > 7.5;
		under *= 1.0 - bare;
		// Round 18: is this tree bare (its leaf role has `twig`); metres a pixel.
		bool bare18 = texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 6), 0).z > 0.5;
		float px18 = PROJECTION_MATRIX[3][3] == 0.0 ? e_px : 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		bool big18 = foliage && !is_shadow && fract(rnd * 47.3 + 0.9) < turn_big18;
		if (!is_shadow) {
			// painter-perf-strokes: a mark the density, the thinning or the season rule drops builds
			// nothing: the same tests as further down (keep *= step(rnd2, rp0.w) * step(thin_i, ..), bare
			// foliage, wood19 bark), made before the wind and the placement (the output is the same:
			// a dropped stroke is a collapsed vertex either way).
			float rnd2h = fract(rnd * 11.13 + 0.31);
			if (step(rnd2h, rp0.w) * step(thin_i, fract(rnd2h * 7.31 + rnd)) < 0.5 || (bare > 0.5 && foliage) || (wood19 > 0.5 && limb_r > 0.0)) {
				break;
			}
		}
		vec3 wp =(MODEL_MATRIX * vec4(a_p, 1.0)).xyz;
		if (wood19 > 0.5 && bare18 && foliage && !is_shadow) {
			// Round 19: a bare crown's twig mass goes with the warp that carries its limbs.
			wp += mat3(MODEL_MATRIX) * warp19(a_p, MODEL_MATRIX[3].xyz);
		}
		vec3 anchor = wp;
		mat3 m3 = mat3(MODEL_MATRIX);
		vec3 wn = normalize(m3 * a_n);
		vec3 wd = normalize(m3 * a_d);
		vec3 tn = normalize(m3 * a_tn);
		vec3 fnw = normalize(m3 * a_fn);
		vec3 to_sun = -normalize(sun_dir);
		bool plain = !is_shadow;
		bool is_mark = plain && fract(rnd * 29.3 + 0.71) < rp4.x;
		int mk = int(rp4.z + 0.5);
		bool bark12 = (fix2 & 4) != 0 && limb_r > 0.0 && plain;
		if (bark12 && abs(rp5.z - 11.0) < 0.5) {
			is_mark = false;
		}
		if ((fix3 & 4) != 0 && plain && (mk & 2) != 0 && foliage) {
			float bunch = smoothstep(0.56, 0.63, p_noise(anchor * 1.5 + 21.0)) * step(wn.y, 0.6);
			is_mark = fract(rnd * 29.3 + 0.71) < min(rp4.x * 3.5, 0.9) * bunch;
		}
		if (fix15 > 0.5 && plain && dot(own13, own13) > 0.5) {
			// Round 15: a strand mass is broad dabs; its fine marks are drawn at the hem only.
			is_mark = is_mark && hem15 > 0.5;
		}
		if (plain && dot(own13, own13) > 0.5) {
			vec3 od = normalize(m3 * own13);
			wd = normalize(od + cross(wn, od) * ((fract(rnd * 13.1 + 0.3) - 0.5) * 0.5) + vec3(0.0003, 0.0, 0.0));
		} else if (plain && abs(rp3.x) > 0.01) {
			wd = normalize(mix(wd, vec3(0.0, -sign(rp3.x), 0.0), abs(rp3.x)) + vec3(0.0003, 0.0, 0.0));
		}
		if (is_mark && (mk & 1) != 0) {
			wd = normalize(cross(wn, wd) + vec3(0.0, 0.0003, 0.0));
		}
		// Round 16: a bare crown's stroke is a fine twig at the silhouette. It leaves the clump
		// outward and takes the species' habit from `hang` (drooping, upswept) and its crook from
		// `jitter`; a strand mass (willow) keeps its strand's own direction.
		bool twig16 = r16 > 0.5 && plain && foliage && rp6.z > 0.5;
		bool strand16 = dot(own13, own13) > 0.5;
		if (twig16 && !strand16) {
			vec3 crook16 = (vec3(fract(rnd * 13.1 + 0.3), fract(rnd * 27.7 + 0.1), fract(rnd * 41.3 + 0.7)) - 0.5) * rp1.z * 2.4;
			wd = normalize(wn + vec3(0.0, -rp3.x * 1.3, 0.0) + crook16 + vec3(0.0003, 0.0, 0.0));
		}

		float wrot = 0.0;
		float gust_here = 0.0;
		if (wind_amp > 0.0) {
			float wgt = ww0 * (0.25 + 0.75 * rho * rho);
			gust_here = gust(anchor.xz);
			wp += tree_flex(anchor, MODEL_MATRIX[3].xyz, flex);
			wp += mass_sway(wphase, ww0);
			wp += edge_push(anchor, wgt);
			float fph = flutter * 6.2832;
			float fl_amt = wgt * (1.0 - 0.4 * calm) * (foliage ? 1.0 : 0.0);
			wp += wd * sin(TIME * 4.6 + fph) * wind_amp * 0.45 * fl_amt * (0.3 + gust_here);
			wrot = sin(TIME * 5.5 + fph * 2.7) * (0.32 + 0.3 * abs(rp3.x)) * fl_amt * (0.2 + gust_here) * min(1.0, wind_amp * 6.0);
		}

		vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
		bool persp = PROJECTION_MATRIX[3][3] == 0.0;
		vec3 to_cam = persp ? normalize(cam_pos - wp) : normalize(INV_VIEW_MATRIX[2].xyz);

		// Level visibility (round 2's rule, unchanged).
		float lam = e_lam;
		float vis = (1.0 - smoothstep(0.5, 1.0, abs(clamp(lam, 0.0, 2.0) - level))) * 1.3;
		float thr = fract(rnd * 3.71 + 0.137);
		float keep = vis > thr + 0.0001 ? 1.0 : 0.0;
		float grow = mix(0.72, 1.0, clamp((vis - thr) / 0.3, 0.0, 1.0));
		float comp = exp2(clamp(-(lam - level) * 0.5, -1.0, 1.0));
		float sv = mix(1.0 - rp1.w, 1.0 + rp1.w, size_rnd);
		float size = rp0.x * stroke_scale * exp2(1.0 - level) * comp * grow * sv;
		float aspect = rp0.y;
		float align = rp1.x;
		float lift = rp1.y;
		float brush = rp0.z;
		if (frond) {
			aspect = max(aspect, 3.4);
			align = 0.8;
			brush = rp0.z > 2.5 ? rp0.z : 2.0;
			lift *= 0.5;
			size *= 1.2;
		}
		if (is_mark) {
			size *= rp4.w;
			aspect = rp5.w > 0.0 ? rp5.w : aspect;
			brush = rp5.z > -0.5 ? rp5.z : brush;
		}
		// The wide-view rule (round 7 and 8): a stroke is bounded by the mass it sits on.
		float far7 = cap_on > 1.5 ? 1.0 - smoothstep(0.0, 1.0, lam) : 0.0;
		if (plain && cap_on > 0.5 && rp5.x > 0.0 && mass_m > 0.0) {
			float facing = smoothstep(0.45, 0.85, dot(wn, to_cam));
			size = min(size, rp5.x * mass_m * (is_mark ? rp4.w : 1.0) * (1.0 + far7 * (far_rim + (1.8 - far_rim) * facing)));
		}
		if (plain && cap_on > 1.5) {
			size = max(size, e_px * 3.0);
		}
		// Round 19 (twig-mass): a bare crown's outermost twigs. Near: a spray of thin strokes that leaves
		// the twig end in the species' habit (brush 14; a willow's hanging whips keep the strand brush).
		// Far: one broad dry-brush shape a root (brush 15). On the crown's upper side a share are snow caps.
		bool tw19 = twig16 && wood19 > 0.5 && twig_mass19 > 0.5;
		bool cap19 = false;
		if (tw19) {
			if (level < 0.5) {
				brush = 15.0;
				aspect = 1.5;
				size = (mass_m > 0.0 ? mass_m : size) * twig_far19 * mix(0.8, 1.25, fract(rnd * 31.7 + 0.2));
			} else {
				brush = strand16 ? 8.0 : 14.0;
			}
			if (strand16 && level > 0.5) {
				keep *= step(1.0 - whips17 * 1.5, p_noise(anchor * 0.9 + 3.7) + (fract(rnd * 3.3 + 0.5) - 0.5) * 0.2);
			}
			if (strand16 && level < 0.5) {
				// A far willow keeps its curtain: long hanging shapes.
				aspect = 2.6;
				size *= 1.5;
			}
			if (snow_cap19 > 0.0 && deposit > 0.0 && wn.y > 0.45 && !strand16 && fract(rnd * 19.3 + 0.27) < snow_cap19) {
				// (First version: round dabs; flat white eggs. A dry streak, smaller.)
				cap19 = true;
				brush = 1.0;
				aspect = 2.6;
				size *= level < 0.5 ? 0.4 : 0.45;
				wd = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam) + vec3(0.0, (fract(rnd * 9.1) - 0.5) * 0.3, 0.0));
			}
		}
		if (wood19 > 0.5 && limb_r > 0.0 && plain) {
			// Round 19 (wood-stroke): the limb is one stroke, drawn by the block-in pass with its own
			// marks and snow; no separate bark strokes ride on it.
			keep = 0.0;
		}
		float rnd2 = fract(rnd * 11.13 + 0.31);
		keep *= step(rnd2, rp0.w) * step(thin_i, fract(rnd2 * 7.31 + rnd));

		// Round 18: a bare tree's limbs are painted wider, tapered, and only down to the main branches
		// (the block-in's rule, blockin18.txt), so its bark marks are too.
		// (A bark mark's width was bounded by the painted radius at first: at 38 m an oak's furrow mark
		// was a dark slab half a metre wide. It is bounded by the grown radius, as before.)
		float rcap18 = limb_r;
		if (bare18 && limb_wide18 > 0.0 && limb_r > 0.0 && plain) {
			keep *= step(limb_cut18(px18), limb_base18);
			rcap18 = max(limb_r * 1.3, px18 * 1.5);
			limb_r = limb_r18(limb_r, limb_base18, limb_along18, px18);
		}
		// Round 11: bark lies inside its limb.
		bool limb = plain && limb_r > 0.0 && (fix & 4) != 0;
		float l_len = 0.0;
		float l_wid = 0.0;
		vec3 l_bx = vec3(1.0, 0.0, 0.0);
		if (limb) {
			vec3 tgw = normalize(m3 * limb_tg);
			vec3 lat = cross(tgw, to_cam);
			float ll = dot(lat, lat);
			if (ll < 0.01) {
				limb = false;
			} else {
				lat *= inversesqrt(ll);
				vec3 fr = cross(lat, tgw);
				float r = limb_r;
				bool across = is_mark && (mk & 1) != 0;
				l_len = size * sqrt(aspect);
				l_wid = size * inversesqrt(aspect);
				float hw = 0.0;
				if (across) {
					// A mark across the grain (the birch's dash): never past the limb's edges.
					l_len = min(l_len, r * (1.1 + 0.7 * fract(rnd * 9.7)));
					l_wid = min(l_wid, max(l_len * 0.45, e_px * 2.0));
					hw = l_len * 0.5;
					l_bx = lat;
				} else {
					l_wid = min(l_wid, min(r, rcap18) * (is_mark ? 1.25 : 1.0));
					l_len = is_mark ? l_wid * max(aspect, 1.0) : clamp(l_len, l_wid * 2.6, l_wid * 4.5) * mix(1.0, sqrt(ll), 0.8);
					hw = l_wid * 0.5;
					l_bx = tgw;
				}
				float xr = clamp(dot(wn, lat), -1.0, 1.0) * max(r * 0.94 - hw, 0.0);
				float hh = sqrt(max(r * r - xr * xr, 0.0));
				vec3 np = normalize(lat * xr + fr * hh);
				// The far side's roots would land on the near side too; a limb under a pixel and a
				// half wide is left to the block-in.
				float keep15 = keep;
				vec3 root15 = wn;
				keep *= step(0.0, dot(wn, to_cam)) * step(e_px * (bark12 ? 1.0 : 1.5), 2.0 * r);
				if (bark12 && rp4.x > 0.0 && !is_mark) {
					keep *= step(fract(rnd * 61.7 + 0.19), 0.45);
				}
				vec3 rest = (MODEL_MATRIX * vec4(limb_q, 1.0)).xyz + lat * xr + fr * hh;
				wp += rest - anchor;
				anchor = rest;
				wn = np;
				tn = np;
				fnw = np;
				if (limb_snow17 > 0.0 && deposit > 0.0) {
					// Round 17 (limb-snow): the block-in draws the ridge (blockin17.txt). A bark stroke
					// that would lie in the snow becomes a long snow mark along the ridge, in the
					// snow's lit tone or, next to the bark, its blue shade; one that would straddle
					// the snow's edge is not drawn.
					vec3 upp = snow_up17(tgw);
					vec3 axis17 = (MODEL_MATRIX * vec4(limb_q, 1.0)).xyz;
					float sa17 = snow_amt18(tgw, axis17, axis17.y - MODEL_MATRIX[3].y);
					float sc17 = dot(np, upp);
					float bnd17 = snow_bnd18(sa17);
					if (sa17 > 0.05 && sc17 > bnd17 - 0.15) {
						if (sc17 > bnd17 + 0.05 && dot(root15, to_cam) > 0.0) {
							snow15 = true;
							snow_t17 = sc17 > bnd17 + 0.25 ? 0.9 : 0.12;
							vec3 top17 = rest + upp * snow_deep18(r, sa17, px18) * sc17 * 0.6;
							wp += top17 - anchor;
							anchor = top17;
							l_wid = max(r * 0.7 * min(sa17, 1.0), e_px * 2.0);
							l_len = l_wid * 4.0;
							l_bx = tgw;
							is_mark = false;
							brush = 0.0;
						} else {
							keep = 0.0;
						}
					}
				}
			}
		}
		// Round 11: a pine bough. At its edge a flick of needles along the twig; inside, calm dabs.
		bool flick = false;
		if (bough && plain) {
			float rimv = 1.0 - abs(dot(wn, to_cam));
			float hsh = fract(rnd * 7.77 + 0.13);
			// The flicks come in tufts with bare edge between them (a slow noise), never an even fringe.
			float tuft = smoothstep(0.3, 0.5, p_noise(anchor * 1.9 + 4.0));
			flick = wn.y > -0.7 && ((rimv > 0.45 && hsh < 0.9 * tuft) || hsh < 0.2 * tuft);
			if ((fix2 & 2) != 0) {
				tuft = smoothstep(0.42, 0.6, p_noise(anchor * 1.25 + 4.0));
				flick = wn.y > -0.45 && ((rimv > 0.48 && hsh < 0.8 * tuft) || hsh < 0.13 * tuft);
				size *= flick ? mix(0.65, 1.25, fract(rnd * 3.3 + 0.4)) : mix(0.8, 1.3, fract(rnd * 6.1 + 0.2));
			}
			if (flick) {
				// Up and out along the twig on top; round the lower edge the needles stand out level.
				vec3 tw = normalize(m3 * a_tw);
				tw.y *= smoothstep(-0.7, 0.1, wn.y);
				wd = normalize(tw * 0.7 + wn * 0.8);
				size *= 0.85;
				aspect = 1.7;
				brush = 13.0;
				align = 0.0;
			} else {
				size *= 1.15;
			}
		}

		vec3 ln = normalize(mix(tn, fnw, calm * 0.8 * has_form * (1.0 - rp3.z)));
		float ndl = dot(ln, to_sun) - under * 0.35 * calm * crown_occ;
		if (foliage) {
			ndl = crown_ndl18(ndl);
		}

		bool dep_on = false;
		if (is_shadow) {
			vec3 wp_m15 = wp;
			wp -= sun_dir * ((wp.y - ground_y) / sun_dir.y);
			wp.y = ground_y + 0.16 + 0.03 * rnd;
			// Round 15, litter: a share of a broadleaf's shadow strokes are fallen leaves instead,
			// straight under the crown and a little beyond it, in the leaf's own colour.
			// (Round 18, litter-shapes: the ground paints the litter as flat shapes; no single leaves.)
			leaf15 = litter15 > 0.0 && litter_shape18 < 0.5 && (fl & 16) != 0 && fract(rnd * 7.13 + 0.61) < litter15;
			if (leaf15) {
				float la = fract(rnd * 91.7) * 6.2832;
				wp = vec3(wp_m15.x, ground_y + 0.1 + 0.03 * rnd, wp_m15.z) + vec3(cos(la), 0.0, sin(la)) * fract(rnd * 37.3) * 1.2;
			}
			anchor = wp;
			wn = vec3(0.0, 1.0, 0.0);
			vec3 flat_sun = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(0.001, 0.0, 0.0));
			wd = normalize(mix(normalize(vec3(wd.x, 0.0, wd.z) + vec3(0.001, 0.0, 0.0)), flat_sun, 0.6));
			size = shadow_size * stroke_scale * exp2(clamp((1.0 - lam) * 0.5, -1.0, 1.0)) * sv;
			// Round 17: a shadow stroke is a round dab (round 15's long flat ones combed the edge).
			aspect = 1.4;
			align = 1.0;
			lift = 0.0;
			brush = 0.0;
			wrot = 0.0;
			keep = painted_shadows * (1.0 - silhouette);
			gh17 = fract(rnd * 23.17 + 0.4);
			int lrow15 = int(row_of(0.0, inst) + 0.5);
			bool bare17 = texelFetch(role_params, ivec2(lrow15, 6), 0).z > 0.5;
			if ((fl & 16) != 0) {
				if (bare17) {
					// A bare tree has no crown, so no crown shadow and no fallen leaves.
					keep = 0.0;
				} else if (texelFetch(role_params, ivec2(lrow15, 2), 0).w < 0.5) {
					keep *= step(fract(rnd * 17.77 + 0.21), 0.3);
				}
				if (!leaf15) {
					// A crown's shadow stroke is drawn only where the shade's own shape is (so no stray
					// fragment): all of its edge, a share inside.
					float sv17 = gfield17(wp).r * 0.9;
					keep *= step(0.2, sv17) * (sv17 < 0.8 ? 1.0 : step(fract(rnd * 9.31 + 0.5), shade_keep17));
				}
			} else if (!bare17) {
				// A limb's shadow under its own crown is inside the crown's shade already.
				keep *= step(fract(rnd * 9.31 + 0.5), shade_keep17);
			} else if (limb_shadow18 > 0.0) {
				// Round 18 (limb-shadow): a bare tree's shadow is its branch pattern, painted limb by
				// limb: one long soft mark for each piece of a main limb, lying where the piece's
				// shadow falls, as wide as the painted limb. (Round 17: a chain of round dabs.)
				keep *= step(limb_cut18(px18) * limb_shadow18, limb_base18);
				vec3 svw = m3 * sh_sv18;
				vec3 g18 = svw - sun_dir * (svw.y / sun_dir.y);
				g18.y = 0.0;
				float gl18 = length(g18);
				wd = gl18 > 1e-4 ? g18 / gl18 : flat_sun;
				float w18 = max(3.4 * limb_r18(sh_r18, limb_base18, limb_along18, px18), px18 * 4.0);
				float l18 = max(gl18 * 2.2, w18 * 1.5);
				size = sqrt(l18 * w18);
				aspect = l18 / w18;
			}
			if (leaf15) {
				size *= 0.34;
				aspect = 1.5;
				align = 0.0;
			}
		} else {
			keep *= step(-0.4, dot(wn, to_cam));
			float edge = 1.0 - min(1.0, min(abs(ndl - tone_lo), abs(ndl - tone_hi)) * 4.0);
			if (foliage && turn_half18 > 0.0) {
				edge = crown_edge18(ndl);
			}
			float rim = 1.0 - max(0.0, dot(normalize(mix(wn, fnw, 0.7 * has_form)), to_cam));
			edge = max(edge, rim * rim);
			if (is_mark || flick) {
				edge = 1.0;
			}
			float thin = calm * 0.7 * (1.0 - edge) * (1.0 - rp6.y) * (e_persp ? 0.2 : 1.0);
			float farness = clamp(1.0 - lam, 0.0, 1.0) * (abs(cap_on - 1.0) < 0.5 ? 1.0 : 0.0) * rp5.y;
			thin = max(thin, farness * (1.0 - edge * edge));
			keep *= step(fract(rnd * 17.77 + 0.21), 1.0 - thin);
			if (twig16 && !tw19) {
				// Round 17: a bare crown has no strokes at all (no twig haze, no bristles, no leaf dabs).
				keep = 0.0;
			}
			float dep = deposit * rp2.z * smoothstep(0.1, 0.55, wn.y);
			dep_on = dep > dep_threshold(anchor, fract(rnd * 23.17 + 0.4));
			if (role > 7.5) {
				// Round 18 (snow-shelf): an evergreen's snow is a shelf on what faces up.
				dep_on = !flick && shelf18(wn.y, rp2.z, anchor, fract(rnd * 23.17 + 0.4));
			}
			if (limb_snow17 > 0.0 && limb_r > 0.0) {
				dep_on = snow15;
			}
			if (rp2.w < 0.5 && has_form > 0.5 && !dep_on) {
				keep = 0.0;
			}
			if (twig16 && !tw19) {
				keep = 0.0;
			}
		}
		if (bare > 0.5 && (foliage || (is_shadow && (fl & 16) != 0))) {
			keep = 0.0;
		}
		keep *= 1.0 - kill10;
		if (big18) {
			size *= 1.4;
		}

		if (keep > 0.0) {
			float len = size * sqrt(aspect);
			float wid = size * inversesqrt(aspect);
			vec3 ax = wd - to_cam * dot(wd, to_cam);
			ax = dot(ax, ax) < 0.003 ? normalize(INV_VIEW_MATRIX[0].xyz) : normalize(ax);
			vec3 ay = cross(to_cam, ax);
			vec3 sy = cross(wn, wd);
			sy *= dot(sy, ay) < 0.0 ? -1.0 : 1.0;
			vec3 bx0 = normalize(mix(ax, wd, align));
			vec3 by0 = normalize(mix(ay, sy, align));
			if (limb) {
				len = l_len;
				wid = l_wid;
				bx0 = normalize(l_bx - to_cam * dot(l_bx, to_cam) + vec3(0.00001, 0.0, 0.0));
				by0 = cross(to_cam, bx0);
			}
			float cr = cos(wrot);
			float sr = sin(wrot);
			vec3 bx = bx0 * cr + by0 * sr;
			vec3 by = by0 * cr - bx0 * sr;
			wp += wn * lift * size * (0.3 + 0.7 * rnd);
			if (is_mark && (fix3 & 4) != 0 && (mk & 2) != 0 && foliage) {
				wp.y -= size * 0.6;
			}
			// How far the quad's centre sits along its length from the stroke's point.
			float shift = 0.0;
			if (twig16 && !strand16) {
				// A twig grows FROM its anchor (a spray's base is at the brush's near end).
				shift = tw19 ? (cap19 || level < 0.5 ? 0.0 : 0.45) : 0.22;
			} else if (plain) {
				shift = 0.4 * abs(rp3.x);
			}
			if (flick) {
				shift += 0.42;
			}
			if (tw19) {
				// twig-back: the twig mass lies behind its limbs.
				wp -= to_cam * twig_back19 * (cap19 ? 0.5 : 1.0);
			}
			vec3 centre = wp + bx * shift * len;
			wp = centre + bx * (UV.x - 0.5) * len + by * (UV.y - 0.5) * wid;
			VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
			// tt-sim (painter-token-window): the token window takes a stroke whole, by where its
			// nearest point lies (a ground dab under a crown is not in front of anything: it stays).
			vec3 centre_view = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
			// painter-trees-fix2: a stroke goes with its whole tree when the window takes the tree
			// (tree_token_crown: the crown's form centre and radius across, texels 3 and 4); a ground
			// dab stays.
			bool wood_stroke = abs(role - 1.0) < 0.5;
			vec4 crown = vec4(0.0);
			if (!is_shadow && abs(role - ROLE_GROUND) > 0.5 && occlusion_token_count > 0) {
				int crown_row = int(INSTANCE_CUSTOM.x + 0.5);
				vec4 crown_c = texelFetch(tree_tex, ivec2(3, crown_row), 0);
				vec4 crown_r = texelFetch(tree_tex, ivec2(4, crown_row), 0);
				// (w 2: a bush, PainterTreeBush: only thinned stroke by stroke, never taken whole.)
				if (crown_c.w > 0.5 && crown_c.w < 1.5) {
					crown = vec4((VIEW_MATRIX * (MODEL_MATRIX * vec4(crown_c.xyz, 1.0))).xyz,
						max(crown_r.x, crown_r.z) * length(MODEL_MATRIX[0].xyz));
				}
			}
			// (painter-perf-forest: a tree no token can reach skips the window's loops.)
			bool near_token = (perf_off & 2) != 0 || tree_token_near(box_c, box_h, VIEW_MATRIX,
				PROJECTION_MATRIX);
			if (!is_shadow && near_token && tree_token_stroke(centre_view, 0.5 * max(len, wid),
					has_clump ? (VIEW_MATRIX * (MODEL_MATRIX * vec4(clump_p, 1.0))).xyz : centre_view,
					crown, anchor, fract(rnd * 13.7 + 0.31), wood_stroke, VIEW_MATRIX, PROJECTION_MATRIX,
					VIEWPORT_SIZE)) {
				VERTEX = vec3(0.0);
			}
			v_brush = brush;
			bool flip = fract(rnd * 5.3) > 0.5;
			v_uv = brush > 2.5 ? vec2(UV.x, flip ? 1.0 - UV.y : UV.y) : mix(UV, 1.0 - UV, flip ? 1.0 : 0.0);
			// Tone and colour, once per stroke.
			float patch_n = p_noise(anchor * rp2.y + role * 17.0);
			float per = mix(mix(tone_rnd, rnd, 0.2), 0.5, calm * 0.45);
			float variant = mix(per, patch_n, rp2.x * (is_shadow ? 1.0 - calm * 0.3 : 1.0)) + hue_o;
			float up12 = 1.0;
			if (rp3.w > 0.0 && plain) {
				variant = smoothstep(rp3.w - 1.6, rp3.w + 1.6, anchor.y - MODEL_MATRIX[3].y) + (per - 0.5) * 0.25;
				if (bark12) {
					up12 = smoothstep(rise12 - 1.1, rise12 + 1.1, anchor.y - MODEL_MATRIX[3].y + (p_noise(anchor * 0.9 + 2.0) - 0.5) * 1.4);
					variant = up12 + (per - 0.5) * 0.25;
				}
			}
			float jit = ((fract(tone_rnd * 13.7) - 0.5) * 2.0 + (fract(rnd * 5.9) - 0.5) * 0.35) * rp1.z * (1.0 - calm * 0.9);
			if (foliage && plain) {
				// Round 17 (turn-break): the block-in's wandering edge, and a spread from stroke to
				// stroke on top, so lit, mid and shade marks interleave where the crown turns.
				jit += (p_noise(anchor * 0.8 + 17.0) - 0.5) * turn17 + (fract(rnd * 5.9) - 0.5) * 0.5 * turn17;
				if (big18) {
					// Round 18 (turn-big): a large mark of the neighbouring tone.
					jit += (fract(rnd * 83.1 + 0.3) < 0.5 ? -1.0 : 1.0) * (tone_hi - tone_lo) * max(2.0 * turn_half18, 0.4);
				}
			}
			float t = tone3(ndl, jit, mix(0.13, 0.01, calm));
			if (foliage) {
				t = crown_tone18(ndl + jit, mix(0.13, 0.01, calm));
			}
			if (foliage && plain && e_persp) {
				e_lift = e_lift_at(anchor, e_near, wn.y, (fract(rnd * 7.3 + 0.4) - 0.5) * 0.6);
				t = max(t, e_lift);
				variant += (fract(rnd * 19.7 + 0.2) - 0.5) * 0.5 * e_near;
				if (wn.y < -0.2 && fract(rnd * 31.7 + 0.3) < 0.11) {
					t = 0.78 + 0.18 * fract(rnd * 7.1);
					e_lift = max(e_lift, t);
				}
			}
			if (!foliage && plain && e_persp && limb_r > 0.0) {
				t = tone3(ndl + (fract(rnd * 9.7 + 0.2) - 0.5) * 0.7 * (1.0 - smoothstep(6.0, 18.0, e_d)), jit, mix(0.13, 0.01, calm));
			}
			float row_c = srow;
			float value = 1.0;
			if (is_shadow) {
				t = clamp(0.09 + jit * 0.5, 0.02, 0.2);
				if (leaf15) {
					t = 0.55 + (fract(rnd * 3.3 + 0.2) - 0.5) * 0.7;
					row_c = row_of(0.0, inst);
				}
			} else {
				t += patch17(anchor) * 0.45;
				if (calm > 0.5) {
					if (form_occ(anchor + wn * 0.05, to_sun, inst) > 0.5) {
						t = max(min(t, clamp((foliage ? crown_cast18 : 0.1) + jit * 0.35, 0.03, foliage ? 0.5 : 0.3)), e_lift);
					}
				}
				value = 1.0 + (fract(rnd * 41.7 + 0.3) - 0.5) * 2.0 * rp6.x + (e_persp && foliage ? (fract(rnd * 13.3 + 0.1) - 0.5) * 0.3 * e_near : 0.0);
				if (is_mark) {
					value = rp4.y;
					if ((mk & 2) != 0) {
						row_c = row_of(5.0, inst);
						t = max(t, 0.5);
					}
				}
				if (twig16) {
					// A twig is drawn in the mass's colour times mark-value (darker: it is wood).
					value = rp4.y;
				}
				if (dep_on) {
					row_c = dep_row;
					value = 1.0;
				}
				if (moss > 0.01 && abs(role - 1.0) < 0.5 && !dep_on && !is_mark && !(bark12 && rp3.w > 0.0)) {
					if ((fix3 & 2) != 0) {
						vec3 sunh = normalize(vec3(to_sun.x, 0.0, to_sun.z) + vec3(0.0001, 0.0, 0.0));
						float hgt = anchor.y - MODEL_MATRIX[3].y;
						float low = 1.0 - smoothstep(0.25, 1.5, hgt + (p_noise(anchor * 1.3 + 9.0) - 0.5) * 0.9);
						float side = smoothstep(-0.1, 0.7, -dot(wn, sunh));
						if (low * side * (0.6 + 0.8 * p_noise(anchor * 2.1 + 4.0)) * min(moss * 1.5, 1.0) > 0.5 + 0.2 * fract(rnd * 3.9)) {
							row_c = row_of(0.0, inst);
							t -= 0.05;
						}
					} else if (p_noise(anchor * 1.5 + 9.0) - 0.22 * wn.y < moss * 0.4) {
						row_c = row_of(0.0, inst);
						t -= 0.1;
					}
				}
			}
			if (snow15) {
				t = snow_t17;
			}
			if (cap19) {
				row_c = dep_row;
				value = 1.0;
				t = fract(rnd * 7.7 + 0.1) < 0.3 ? 0.5 : 0.9;
			}
			v_col = palette_at(t + value_o, row_c, variant) * value;
			if (tw19 && !cap19 && level < 0.5) {
				// The far twig mass is hazy: its colour goes part of the way to the snow's (or the haze's).
				v_col = mix(v_col, deposit > 0.0 ? palette_at(0.5, dep_row, 0.5) : haze_col17, twig_haze19 * (strand16 ? 0.3 : 1.0));
			}
			if (is_shadow && !leaf15) {
				// Round 17: a shadow stroke is the shade tone of the ground it falls on (meadow, path,
				// a drift), so the mood's ground rule says how far it goes to the shade hue.
				v_col = ground17(anchor, ground_row17, tone3(to_sun.y, 0.0, 0.01), (fract(rnd * 7.9 + 0.2) - 0.5) * 0.4, (fract(rnd * 41.7 + 0.3) - 0.5) * 0.05, gh17, 1.0, 1.0, 0.0);
			}
			if (bark12 && rp3.w > 0.0 && row_c == srow) {
				float l12 = dot(v_col, vec3(0.3, 0.59, 0.11));
				vec3 grey12 = mix(vec3(l12), v_col, 0.3) * vec3(0.84, 0.82, 0.84);
				v_col = mix(grey12, v_col * vec3(1.07, 0.98, 0.93), up12);
			}
			// Round 17: the air between the eye and the mark, once a mark.
			v_col = haze17(v_col, -(VIEW_MATRIX * vec4(anchor, 1.0)).z);
			if (silhouette > 1.5) {
				v_col = foliage && !is_shadow ? vec3(0.0) : vec3(1.0);
			} else if (silhouette > 0.5) {
				v_col = is_shadow ? vec3(1.0) : vec3(0.0);
			}
		}
	}
	}
	// tt-sim: the canopy fade's key for the whole stroke; a stem's strokes stay (-1).
	v_key = stem18 ? -1.0 : fract(rnd * 7.31 + 0.13);
}

void fragment() {
	ALBEDO = v_col;
	if (abs(v_brush - 14.0) < 0.5) {
		// Round 19: a spray of twigs is drawn as lines of a fixed width on screen (twig-px), from one
		// point: five twigs that bow apart, three side shoots, dry breaks. (First version: a brush
		// texture; minified, its thin lines closed up into solid leaf shapes.)
		vec2 q = v_uv * 2.0 - 1.0;
		float tq = (q.x + 0.9) / 1.85;
		if (abs(q.y) > 0.12 + 0.75 * tq) {
			// Outside the fan: nothing to test.
			discard;
		}
		float hw = 0.5 * twig_px19 * fwidth(q.y);
		float a = 0.0;
		const float sl[5] = float[5](-0.8, -0.42, 0.0, 0.38, 0.78);
		const float bw[5] = float[5](0.3, 0.25, -0.12, -0.2, -0.3);
		const float ln[5] = float[5](0.62, 0.9, 1.0, 0.84, 0.58);
		if (tq >= 0.0) {
			for (int k = 0; k < 5; k++) {
				if (tq <= ln[k]) {
					float yc = sl[k] * tq + bw[k] * tq * tq;
					float gap = (tq > 0.2 && fract(tq * 3.3 + float(k) * 0.37) < 0.14) ? 0.0 : 1.0;
					a = max(a, step(abs(q.y - yc), hw * (1.15 - 0.4 * tq / ln[k])) * gap);
				}
			}
			float y1 = sl[1] * 0.45 + bw[1] * 0.2025;
			float y3 = sl[3] * 0.4 + bw[3] * 0.16;
			float y2 = sl[2] * 0.58 + bw[2] * 0.3364;
			a = max(a, step(abs(q.y - (y1 - 0.95 * (tq - 0.45))), hw * 0.85) * step(0.45, tq) * step(tq, 0.71));
			a = max(a, step(abs(q.y - (y3 + 1.05 * (tq - 0.4))), hw * 0.85) * step(0.4, tq) * step(tq, 0.68));
			a = max(a, step(abs(q.y - (y2 + 0.6 * (tq - 0.58))), hw * 0.85) * step(0.58, tq) * step(tq, 0.84));
		}
		ALPHA = a;
	} else if (abs(v_brush - 15.0) < 0.5) {
		// The far twig mass: one dry-brush shape, made of bristle rows two pixels wide that start and
		// end unevenly, a share of them missing, so what is behind shows through. (First version: a
		// brush texture; minified it closed into solid lobes that read as foliage.)
		vec2 q = v_uv * 2.0 - 1.0;
		float rowi = floor(q.y / max(fwidth(q.y) * 2.0, 1e-4));
		float sd = floor(v_col.r * 977.0) + floor(v_col.g * 613.0);
		float h1 = p_hash(vec3(rowi, sd, 3.0));
		float h2 = p_hash(vec3(rowi, sd, 11.0));
		float h3 = p_hash(vec3(rowi, sd, 23.0));
		float span = sqrt(max(1.0 - q.y * q.y, 0.0));
		ALPHA = step(0.55, h3) * step(-span * mix(0.3, 1.0, h1), q.x) * step(q.x, span * mix(0.2, 1.0, h2));
	} else {
		ALPHA = texture(brushes, vec3(v_uv, floor(v_brush + 0.5))).r;
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	tree_fades(VERTEX, INV_VIEW_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE,
		v_key, v_key < 0.0, true);
	v_wp_light = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The colour is the palette's (ALBEDO, ambient off): the sun only steps a stroke into the cool
// shade where its cast shadow falls (tree_cast). Strokes cast no shadow (their nodes do not).
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += mix(vec3(1.0), cast_tint, tree_cast(ATTENUATION, v_wp_light));
	}
}
