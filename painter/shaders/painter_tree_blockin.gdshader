shader_type spatial;
render_mode skip_vertex_transform, specular_disabled, ambient_light_disabled;
// Round 10 block-in of TREES: blockin8.txt's fragment stage, unchanged, under a vertex stage that
// builds the solid from the tree's mass list (mass_tex, layouts in painter10.gd) instead of
// reading per-vertex attributes. Two shared meshes are instanced:
//   kind10 = 0  a block of unit spheres (8 x 5), one per ellipsoid: VERTEX the unit point, UV2.x
//               which sphere of the instance
//   kind10 = 1  a block of four-sided tube segments, one per strand segment: UV (angle 0..1,
//               which end), UV2.x which segment of the instance. A ring's tangent is that of its
//               point in the whole strand, so neighbouring segments meet without a crack.
// Instance: the tree's transform, INSTANCE_CUSTOM (tree row, first unit of this instance).

#include "res://painter/shaders/painter_tree.gdshaderinc"

uniform float silhouette = 0.0;
uniform float lod_level = 1.0;
// tt-sim: how far round from a crown mass's edge its outline may break (|N.eye| under this times a
// world noise is not drawn).
const float MASS_RIM_BREAK = 0.5;
uniform float cap_on = 2.0;
uniform float bare = 0.0;
uniform float r8 = 1.0;

uniform sampler2DArray mass_tex : filter_nearest, repeat_disable;
uniform sampler2D tree_tex : filter_nearest, repeat_disable;
// Strands whose first (thickest) radius is under this get no block-in (far views).
uniform float min_r10 = 0.0;
uniform float kind10 = 0.0;
// Round 11, a mask of its changes (0 = round 10's block-in exactly):
//   1  only the stem keeps the flare at its first ring (round 10 flared the base of every limb)
//   2  a tube's four sides are turned to the camera: its outline is the limb's full width from
//      every side and its normal runs round the visible half, so it is lit as a round limb
//   8  a pine bough (ellipsoid flag 256) is flat beneath
//   32 a clump's solid is swollen to the size its strokes are placed at
uniform float fix11 = 0.0;
// Round 12, a mask of its changes (0 = round 11's block-in exactly):
//   1  a willow's strand mass (ellipsoid flag 512) tapers to a hem
//   4  BARK: the role's mark is drawn as the limb's own pattern, in (length along, angle round)
//      of the limb, so it turns with the trunk and never leaves its outline: dashes across
//      (mark-turn: birch, with a dark fissured foot), plates (mark-brush block: pine, grey-brown
//      and fissured below, orange and nearly smooth above a line set by the crown's base),
//      furrows along the grain (the rest). Far views get fewer, larger marks.
uniform float fix12 = 0.0;
// Round 13, a mask of its changes (0 = round 12's block-in exactly):
//   1  a strand mass is a spindle: a point at the twig it hangs from, widest a fifth of the way
//      down, a point at the hem, and bent by the vector in its texel 7 (out, then down)
//   2  MOSS is a soft low patch on the shaded side of the foot of the stem (round 12: bands of
//      leaf colour wherever a noise fell, at any height and on every limb)
uniform float fix13 = 0.0;
varying vec3 v_tg;
varying float v_lr;
// Round 17: (the cosine to the limb's up side, how much snow the limb carries here).
varying vec3 v_snow;
varying flat float v_bseed;
varying flat float v_rise;

vec4 mt(int addr, int layer) {
	return texelFetch(mass_tex, ivec3(addr & 255, addr >> 8, layer), 0);
}

vec3 form_n(vec3 p, vec3 c, vec3 r) {
	vec3 q = (p - c) / r;
	return dot(q, q) > 1e-8 ? normalize(q) : vec3(0.0, 1.0, 0.0);
}

float occ_soft(vec3 o, vec3 d, int inst) {
	float sh = 0.0;
	float wob = (p_noise(o * 1.1 + 13.0) - 0.5) * 0.24 + (p_noise(o * 3.7 + 5.0) - 0.5) * 0.08;
	for (int k = 0; k < 8; k++) {
		float fi = texelFetch(row_map, ivec2(9 + k, inst), 0).r;
		if (fi < -0.5) {
			break;
		}
		int i = int(fi + 0.5);
		vec4 a = texelFetch(occ_tex, ivec2(i, 0), 0);
		vec4 b = texelFetch(occ_tex, ivec2(i, 1), 0);
		vec3 v = o - a.xyz;
		if (a.w < 1.5) {
			if (a.w < 0.5 && crown_occ < 0.5) {
				continue;
			}
			vec3 lo = v / b.xyz;
			float c = dot(lo, lo) - 1.0;
			if (c < 0.3) {
				continue;
			}
			vec3 ld = d / b.xyz;
			float aa = dot(ld, ld);
			float bb = dot(lo, ld);
			if (bb < 0.0) {
				float miss = sqrt(max(dot(lo, lo) - bb * bb / aa, 0.0)) + wob;
				sh = max(sh, 1.0 - smoothstep(0.84, 1.02, miss));
			}
		} else {
			float cs = cos(b.w);
			float sn = sin(b.w);
			vec3 lo = vec3(cs * v.x - sn * v.z, v.y, sn * v.x + cs * v.z);
			vec3 q = abs(lo) - b.xyz;
			if (max(q.x, max(q.y, q.z)) < 0.3) {
				continue;
			}
			vec3 ld = vec3(cs * d.x - sn * d.z, d.y, sn * d.x + cs * d.z);
			vec3 inv = 1.0 / (ld + vec3(0.00001));
			vec3 t1 = (-b.xyz - lo) * inv;
			vec3 t2 = (b.xyz - lo) * inv;
			vec3 tmn = min(t1, t2);
			vec3 tmx = max(t1, t2);
			float tn = max(tmn.x, max(tmn.y, tmn.z));
			float tf = min(tmx.x, min(tmx.y, tmx.z));
			if (tf > max(tn, 0.0)) {
				sh = 1.0;
			}
		}
	}
	return sh;
}

varying float v_role;
varying vec3 v_wp;
varying vec3 v_wn;
varying vec3 v_fn;
varying float v_form;
varying float v_under;
varying float v_hue;
varying float v_value;
varying float v_height;
varying flat float v_inst;
varying flat float v_row;
varying flat float v_moss;
// (Round 12: the role's rows 2 and 3 are fetched in the fragment stage; the varyings ran out.)
// tt-sim: this shader is at the real renderer's 32-varying limit (the headless dummy renderer
// does not check it), so the canopy fade's key is a world noise and a fine screen dither, not a
// varying.

void vertex() {
	int trow = int(INSTANCE_CUSTOM.x + 0.5);
	int idx = int(INSTANCE_CUSTOM.y + 0.5) + int(UV2.x + 0.5);
	vec4 t0 = texelFetch(tree_tex, ivec2(0, trow), 0);
	vec4 t1 = texelFetch(tree_tex, ivec2(1, trow), 0);
	vec4 t2 = texelFetch(tree_tex, ivec2(2, trow), 0);
	vec4 t3 = texelFetch(tree_tex, ivec2(3, trow), 0);
	vec4 t4 = texelFetch(tree_tex, ivec2(4, trow), 0);
	int layer = int(t0.x + 0.5);
	int base = int(t0.y + 0.5);
	int inst = int(t1.w + 0.5);
	int fix = int(fix11 + 0.5);
	bool alive = false;
	vec3 p = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	vec3 fnv = vec3(0.0, 1.0, 0.0);
	float role = 0.0;
	float rho_v = 0.0;
	float wphase = 0.0;
	float ww_v = 0.0;
	float under = 0.0;
	float has_form = 0.0;
	v_tg = vec3(0.0, 1.0, 0.0);
	v_lr = 0.0;
	v_snow = vec3(0.0);
	v_bseed = 0.0;
	v_rise = 1000.0;
	bool wood_v = false;
	vec3 wood_fn = vec3(0.0);
	float wood_form = 0.0;
	vec3 wood_axis = vec3(0.0);
	if (kind10 < 0.5) {
		if (idx < int(t0.z + 0.5)) {
			alive = true;
			int rec = base + idx * 10;
			vec4 e0 = mt(rec, layer);
			vec4 e1 = mt(rec + 1, layer);
			vec4 e2 = mt(rec + 2, layer);
			vec4 e3 = mt(rec + 3, layer);
			vec3 u = VERTEX;
			int efl = int(e1.w + 0.5);
			vec3 us = u * ((fix & 32) != 0 ? 1.07 : 1.0);
			if (abs(dot(normalize(INV_VIEW_MATRIX[2].xyz), normalize(sun_dir))) > 0.9995) {
				us *= 1.2;
			}
			bool twt16 = r16 > 0.5 && texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 6), 0).z > 0.5;
			bool tw16 = twt16 && e0.w < 0.5;
			if (tw16) {
				// Round 17 (owner, 2026-11-11): a bare tree is its trunk and branches only. No crown
				// mass of any kind is drawn. A willow keeps a few of its hanging strands as thin whips.
				// (First version: every species' strand masses, so a birch kept detached tassels; and
				// the strands' tops stood up over the limbs as horns. Now only a role with `hang` over
				// 0.5, the willow, and the top of each strand is drawn down to where it hangs from.)
				bool whip17 = (efl & 512) != 0 && texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 3), 0).x > 0.5;
				// Round 18: the kept strands come in bunches (a slow noise over the crown picks them) and
				// are thick whips (whip-wide of their summer width, never under about two pixels).
				float px_w18 = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
				float bunch18 = p_noise(e0.xyz * 0.9 + float(trow) * 3.7) + (fract(float(idx) * 0.6180339 + 0.31) - 0.5) * 0.25;
				// (Round 19, twig-mass: the whips are thin hanging strokes, drawn by the stroke pass.)
				if (whip17 && bunch18 > 1.0 - whips17 * 1.5 && !(wood19 > 0.5 && twig_mass19 > 0.5)) {
					float ww18 = max(whip_wide18, 1.2 * px_w18 / max(length(e1.xyz), 0.01));
					us *= vec3(ww18, 1.0, ww18);
					us.y = min(us.y, 0.15 + (us.y - 0.15) * 0.15);
				} else {
					alive = false;
				}
			}
			if ((fix & 8) != 0 && (efl & 256) != 0 && us.y < 0.0) {
				us.y *= 0.4;
			}
			vec3 bend13 = vec3(0.0);
			if ((int(fix12 + 0.5) & 1) != 0 && (efl & 512) != 0) {
				float tq = (1.0 - us.y) * 0.5;
				float l0 = max(2.0 * sqrt(max(tq * (1.0 - tq), 0.0)), 0.08);
				if ((int(fix13 + 0.5) & 1) != 0) {
					// Round 13: a spindle from the twig to a pointed hem, bent out and down.
					float prof = mix(0.8, 1.0, smoothstep(0.0, 0.22, tq)) * pow(max(1.0 - smoothstep(0.22, 1.0, tq), 0.0), 0.75);
					us.xz *= min(prof / l0, 3.0);
					bend13 = mt(rec + 7, layer).xyz * (1.0 - (1.0 - tq) * (1.0 - tq));
				} else {
					// Widest just under the twig it hangs from, narrowing to the hem (no pointed top).
					us.xz *= min(smoothstep(0.0, 0.1, tq) * mix(1.0, 0.4, smoothstep(0.15, 1.0, tq)) / l0, 3.0);
					// The cap is pressed nearly flat (the low sphere would stand up as a shard).
					us.y = 1.0 - 2.0 * (tq < 0.1 ? tq * 0.25 : 0.025 + (tq - 0.1) * (0.975 / 0.9));
				}
			}
			p = e0.xyz + e1.xyz * us.x + e2.xyz * us.y + e3.xyz * us.z + bend13;
			n = normalize(e1.xyz * (u.x / dot(e1.xyz, e1.xyz)) + e2.xyz * (u.y / dot(e2.xyz, e2.xyz)) + e3.xyz * (u.z / dot(e3.xyz, e3.xyz)));
			role = e0.w;
			wphase = e2.w;
			ww_v = e3.w;
			fnv = n;
			if ((efl & 4) != 0) {
				vec4 e4 = mt(rec + 4, layer);
				vec4 e5 = mt(rec + 5, layer);
				bool blend = (efl & 16) != 0;
				has_form = 1.0;
				fnv = form_n(p, e4.xyz, e5.xyz);
				if (blend) {
					fnv = normalize(fnv * 0.6 + form_n(p, t3.xyz, t4.xyz) * 0.4);
				}
				rho_v = clamp(length((p - (blend ? t3.xyz : e4.xyz)) / (blend ? t4.xyz : e5.xyz)), 0.0, 1.0);
			}
			if (twt16 && (role > 7.5 || abs(role - 5.0) < 0.5)) {
				// A bare tree carries no berries or blossom either.
				alive = false;
			}
		}
	} else if (wood19 > 0.5) {
		// Round 19: a limb is a brush stroke. The mesh is a ribbon (round19.gd `_ribbon_block`): UV.x
		// which edge, UV.y how far along the segment (0, 1/4 .. 1), UV2.x which segment. The ribbon runs
		// on a spline through the strand's points, carried by the tree's warp, and is turned to the eye;
		// the fragment stage cuts its edge and paints it in (length along, place across) of the limb.
		if (idx < int(t0.w + 0.5) && (INSTANCE_CUSTOM.z < 0.5 || idx < int(INSTANCE_CUSTOM.z + 0.5))) {
			vec4 sg = mt(base + int(t1.x + 0.5) + idx, layer);
			int hdr = base + int(sg.x + 0.5);
			vec4 h0 = mt(hdr, layer);
			vec4 h1 = mt(hdr + 1, layer);
			int np = int(h1.x + 0.5);
			int hfl = int(h1.y + 0.5);
			int pi0 = int(sg.y + 0.5);
			float f = UV.y;
			vec4 q1 = mt(hdr + 2 + pi0, layer);
			vec4 q2 = mt(hdr + 2 + min(pi0 + 1, np - 1), layer);
			vec4 q0 = mt(hdr + 2 + max(pi0 - 1, 0), layer);
			vec4 q3 = mt(hdr + 2 + min(pi0 + 2, np - 1), layer);
			vec4 pf = mt(hdr + 2, layer);
			vec4 pl = mt(hdr + 2 + np - 1, layer);
			bool stem = (hfl & 8) != 0;
			bool bare17 = texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 6), 0).z > 0.5;
			float px19 = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
			float twig = stem ? 0.0 : twig19(pf.w);
			alive = pf.w >= max(min_r10, bare17 ? limb_cut18(px19) : 0.0);
			// A smoothing spline (uniform cubic B-spline): the skeleton's node-to-node crook becomes a
			// sweep. (First version: a spline THROUGH the nodes; the oak's stem zigzagged in chevrons.)
			float f2 = f * f;
			float f3 = f2 * f;
			float g = 1.0 - f;
			vec3 pos = (g * g * g * q0.xyz + (3.0 * f3 - 6.0 * f2 + 4.0) * q1.xyz + (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) * q2.xyz + f3 * q3.xyz) / 6.0;
			vec3 tgl = -g * g * q0.xyz + (3.0 * f2 - 4.0 * f) * q1.xyz + (-3.0 * f2 + 2.0 * f + 1.0) * q2.xyz + f2 * q3.xyz;
			if (pi0 == 0) {
				// The stroke starts where the limb starts (on its parent), not short of it.
				pos = mix(q1.xyz, pos, f);
			}
			if (pi0 >= np - 2) {
				// ... and ends where it ends (its forks leave from there).
				pos = mix(pos, q2.xyz, f);
			}
			tgl = dot(tgl, tgl) > 1e-10 ? normalize(tgl) : normalize(q2.xyz - q1.xyz + vec3(0.0, 1e-5, 0.0));
			float along = (float(pi0) + f) / float(max(np - 1, 1));
			vec3 seed19 = MODEL_MATRIX[3].xyz;
			// (The warp turns the tangent by a few degrees at most: the spline's own is used.)
			vec3 tg = tgl;
			if (alive) {
				pos += warp19(pos, seed19);
			}
			// (A stem keeps its grown taper: with the limbs' taper on top it stood as a bottle.)
			// (and with none of it, as a log under a bunch of thin forks: half of it.)
			float rr = limb_r19(mix(q1.w, q2.w, f), pf.w, stem ? along * 0.8 : along, px19, twig, bare17);
			if (!stem) {
				// A collar: a limb swells where it leaves its parent (no pegs).
				rr *= 1.0 + 0.6 * (1.0 - twig) * (1.0 - smoothstep(0.0, 0.16, along));
			}
			// The end: a point. A strand that ends thick (a stem that dissolves into its forks) closes
			// over a short length, under the bases of its forks.
			float thick_end = smoothstep(0.4, 0.7, pl.w / max(pf.w, 0.001)) * (1.0 - twig);
			// (Closing a thick end to a point left a gap under the forks: it keeps its width and the
			// fragment stage rounds it.)
			rr *= 1.0 - limb_point19 * (1.0 - thick_end) * smoothstep(0.78, 1.0, along);
			if (stem) {
				// The foot spreads into the ground in one curve (round 18: one wider ring).
				rr *= 1.0 + 0.4 * exp(-max(pos.y, 0.0) / max(pf.w * 1.6, 0.08));
			}
			mat3 m3w = mat3(MODEL_MATRIX);
			vec3 wc = (MODEL_MATRIX * vec4(pos, 1.0)).xyz;
			vec3 vcw = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - wc) : normalize(INV_VIEW_MATRIX[2].xyz);
			vec3 tgw = normalize(m3w * tg);
			vec3 latw = cross(tgw, vcw);
			latw = dot(latw, latw) > 1e-5 ? normalize(latw) : normalize(INV_VIEW_MATRIX[0].xyz);
			if (PROJECTION_MATRIX[3][3] == 0.0 && e_far < 0.5 && !stem) {
				rr *= 1.0 - smoothstep(0.8, 0.95, abs(dot(tgw, vcw)));
			}
			float h19 = wc.y - MODEL_MATRIX[3].y;
			float sa = 0.0;
			if (limb_snow17 > 0.0 && deposit > 0.0) {
				sa = snow_amt18(tgw, wc, h19);
				float lie = 1.0 - abs(tgw.y);
				if (pi0 == 0 && !stem) {
					// A heap in the fork where the limb leaves its parent.
					// (Round 18's rule, on any limb not upright, ringed a stem's top in white where its forks leave.)
					sa = max(sa, 0.95 * limb_snow17 * deposit * smoothstep(0.3, 0.7, lie) * smoothstep(0.4, 0.9, h19) * (1.0 - f));
				}
				sa *= (1.0 - 0.75 * twig) * (1.0 - smoothstep(0.82, 1.0, along));
			}
			bool drift = stem && snow_drift19 > 0.0 && limb_snow17 > 0.0 && deposit > 0.0 && h19 < snow_drift19 * 2.2;
			float marg = 1.4 + (sa > 0.0 ? snow_over19 * 1.5 : 0.0) + (drift ? 0.8 : 0.0);
			float xa = (UV.x * 2.0 - 1.0) * marg;
			p = pos + (latw * (xa * rr) + vcw * rr) * m3w;
			n = normalize(vcw * m3w);
			v_tg = tgw;
			v_lr = rr;
			v_snow = vec3(xa, sa, stem ? 1.0 : 0.0);
			v_bseed = fract(h1.w * 0.01371);
			v_rise = t3.w > 0.5 ? max((t3.y - t4.y) * 0.62, 0.8) : 1000.0;
			fnv = n;
			role = 1.0;
			wphase = h0.y;
			ww_v = h0.z;
			under = (hfl & 2) != 0 ? 1.0 : 0.0;
			if ((hfl & 4) != 0) {
				float fa = pow(clamp(distance(pos, pf.xyz) / max(h0.x, 0.01), 0.0, 1.0), 1.5);
				ww_v = mix(h0.z, h0.w, fa);
				rho_v = clamp(length((pos - t3.xyz) / t4.xyz), 0.0, 1.0) * fa;
			}
			wood_v = true;
			wood_fn = vec3(along * max(h0.x, 0.05), along, pf.w);
			wood_form = 2.0 + twig;
			wood_axis = wc;
		}
	} else if (idx < int(t0.w + 0.5) && (INSTANCE_CUSTOM.z < 0.5 || idx < int(INSTANCE_CUSTOM.z + 0.5))) {
		vec4 sg = mt(base + int(t1.x + 0.5) + idx, layer);
		int hdr = base + int(sg.x + 0.5);
		vec4 h0 = mt(hdr, layer);
		vec4 h1 = mt(hdr + 1, layer);
		int np = int(h1.x + 0.5);
		int hfl = int(h1.y + 0.5);
		int pi = int(sg.y + 0.5) + int(UV.y + 0.5);
		vec4 pc = mt(hdr + 2 + pi, layer);
		vec4 pp = mt(hdr + 2 + max(pi - 1, 0), layer);
		vec4 pn = mt(hdr + 2 + min(pi + 1, np - 1), layer);
		vec4 pf = mt(hdr + 2, layer);
		// Round 17 (bare-limb): a bare tree is drawn down to its main branches; the finest twigs go.
		bool bare17 = texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 6), 0).z > 0.5;
		alive = pf.w >= max(min_r10, bare17 ? bare_limb17 : 0.0);
		// Round 18 (limb-wide, limb-px, limb-taper, limb-far): a bare tree in a painter's hand. Fewer
		// limbs (the cut rises with distance), each wider than grown, never under a least width on
		// screen, narrowing strongly to its tip.
		float px18 = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		bool paint18 = bare17 && limb_wide18 > 0.0;
		float rr18 = pc.w;
		if (paint18) {
			alive = pf.w >= limb_cut18(px18);
			rr18 = limb_r18(pc.w, pf.w, float(pi) / float(max(np - 1, 1)), px18);
		}
		vec3 tg = normalize(pn.xyz - pp.xyz);
		vec3 ref = abs(tg.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 b1 = normalize(cross(tg, ref));
		vec3 b2 = normalize(cross(tg, b1));
		float ang = UV.x * 6.2832;
		if ((fix & 2) != 0) {
			vec3 wc = (MODEL_MATRIX * vec4(pc.xyz, 1.0)).xyz;
			vec3 vcw = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - wc) : normalize(INV_VIEW_MATRIX[2].xyz);
			vec3 vc = vcw * mat3(MODEL_MATRIX);
			vec3 lat = cross(tg, vc);
			if (dot(lat, lat) > 1e-4) {
				b1 = -normalize(lat);
				b2 = normalize(cross(tg, b1));
			}
		}
		n = b1 * cos(ang) + b2 * sin(ang);
		float flare = pi == 0 ? 1.5 : 1.0;
		if ((fix & 1) != 0 && (hfl & 8) == 0) {
			flare = 1.0;
		}
		p = pc.xyz + n * rr18 * flare;
		v_tg = normalize(mat3(MODEL_MATRIX) * tg);
		v_lr = rr18;
		if (limb_snow17 > 0.0 && deposit > 0.0) {
			// Round 17 (limb-snow): snow lies along the upper side of a limb as one ridge. The limb's
			// outline swells on its up side by the snow's depth, and the fragment stage draws that
			// side in the snow's tones. How much: by how level the limb is; more in the crotch where
			// a limb leaves its parent and on the end of a stub or a broken top.
			mat3 m3s = mat3(MODEL_MATRIX);
			vec3 wcs = (MODEL_MATRIX * vec4(pc.xyz, 1.0)).xyz;
			// Round 18: lumps and ridges (snow_amt18), a heap in every fork, a cap on a stub's end;
			// deeper (snow-lump of the painted radius), and it overhangs (snow_bnd18).
			float h18 = wcs.y - MODEL_MATRIX[3].y;
			float sa = snow_amt18(v_tg, wcs, h18);
			float lie17 = 1.0 - abs(v_tg.y);
			if (pi == 0 && (hfl & 8) == 0) {
				sa = max(sa, 1.25 * limb_snow17 * deposit * smoothstep(0.04, 0.3, lie17) * smoothstep(0.4, 0.9, h18));
			}
			if (pi == np - 1 && pc.w > 0.028) {
				sa = max(sa, 1.1 * limb_snow17 * deposit * smoothstep(0.04, 0.3, lie17));
			}
			vec3 upw = snow_up17(v_tg);
			float sc = dot(normalize(m3s * n), upw);
			float deep = snow_deep18(rr18, sa, px18) * max(sc, 0.0);
			p += (upw * m3s) * (deep / max(dot(m3s[1], m3s[1]), 0.0001));
			v_snow = vec3(sc, sa, (hfl & 8) != 0 ? 1.0 : 0.0);
		}
		v_bseed = fract(h1.w * 0.01371);
		v_rise = t3.w > 0.5 ? max((t3.y - t4.y) * 0.62, 0.8) : 1000.0;
		fnv = n;
		role = 1.0;
		wphase = h0.y;
		ww_v = h0.z;
		under = (hfl & 2) != 0 ? 1.0 : 0.0;
		if ((hfl & 4) != 0) {
			float fa = pow(clamp(distance(p, pf.xyz) / max(h0.x, 0.01), 0.0, 1.0), 1.5);
			ww_v = mix(h0.z, h0.w, fa);
			rho_v = clamp(length((p - t3.xyz) / t4.xyz), 0.0, 1.0) * fa;
		}
	}

	v_role = role;
	v_under = under * (1.0 - bare);
	v_inst = float(inst);
	v_row = row_of(role, inst);
	v_moss = t2.w;
	// Colour noise and occlusion are looked up at the rest position: wind never makes them swim.
	v_wp = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	v_height = v_wp.y - MODEL_MATRIX[3].y;
	mat3 m3 = mat3(MODEL_MATRIX);
	v_wn = normalize(m3 * n);
	v_fn = normalize(m3 * (fnv + vec3(0.0, 0.0001, 0.0)));
	v_form = has_form;
	vec3 wp = v_wp;
	if (wind_amp > 0.0) {
		wp += tree_flex(v_wp, MODEL_MATRIX[3].xyz, 1.0);
		wp += mass_sway(wphase, ww_v);
		wp += edge_push(v_wp, ww_v * (0.25 + 0.75 * rho_v * rho_v));
	}
	// The fragment stage's VERTEX and NORMAL are this point and its normal, in view space
	// (skip_vertex_transform): the token window, the canopy fades, the haze and the sun's shadow
	// lookup all read VERTEX. (painter-a2a5: with POSITION alone, Godot's VERTEX was the mesh's own
	// unit sphere or ribbon block at the tree's foot, so a crown was tested at its foot and a token
	// under it kept the masses and limbs over it.)
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize(mat3(VIEW_MATRIX) * v_wn);
	// tt-sim (painter-trees-fix2): every mass, limb and trunk goes with its tree when the token
	// window takes it whole (tree_token_crown: the crown's form centre and radius across), as its
	// strokes do, so neither a mass nor a bare trunk is left beside the opening. The camera's pass
	// only; a ground mass stays.
	bool crown_gone = false;
	if (alive && abs(floor(role + 0.5) - ROLE_GROUND) > 0.5 && t3.w > 0.5
			&& occlusion_token_count > 0
			&& abs(dot(normalize(INV_VIEW_MATRIX[2].xyz), normalize(sun_dir))) <= 0.9995) {
		vec4 crown = vec4((VIEW_MATRIX * (MODEL_MATRIX * vec4(t3.xyz, 1.0))).xyz,
			max(t4.x, t4.z) * length(MODEL_MATRIX[0].xyz));
		// One answer per tree, so every vertex of a mass decides alike (a mass half collapsed would
		// smear its triangles across the frame).
		crown_gone = tree_token_crown(crown, VIEW_MATRIX, PROJECTION_MATRIX);
	}
	POSITION = alive && !crown_gone ? PROJECTION_MATRIX * vec4(VERTEX, 1.0)
		: vec4(2.0, 2.0, 2.0, 1.0);
	if (wood_v) {
		// A limb stroke is painted in limb coordinates: its fragments get the axis point, not their own.
		v_wp = wood_axis;
		v_height = wood_axis.y - MODEL_MATRIX[3].y;
		v_fn = wood_fn;
		v_form = wood_form;
	}
	v_hue = t2.x - 0.5;
	v_value = t2.y - 0.5;
}

uniform float shadow_simple = 0.0;

float e_lift_at(vec3 p, float near, float n_y, float spread) {
	float down = smoothstep(0.0, 0.5, -n_y);
	float m = p_noise(p * 0.7 + 31.0) + (near * mix(0.5, 1.0, down) - 1.0) * 0.35 + spread;
	vec2 e_q = vec2(p.x * 0.8 + p.z * 0.6, p.z * 0.8 - p.x * 0.6);
	m += (p_noise(vec3(e_q.x * 1.5, e_q.y * 4.6, p.y * 1.9) + 7.0) - 0.5) * 0.22 * 1.0 * near;
	m += (p_noise(vec3(e_q.x * 3.4, e_q.y * 11.0, p.y * 4.0) + 21.0) - 0.5) * 0.14 * 1.0 * near;
	return 0.1 + 0.2 * step(0.44, m) + 0.2 * step(0.53, m) + 0.3 * step(0.63, m) * down;
}

void fragment() {
	bool g_sun = abs(dot(normalize(INV_VIEW_MATRIX[2].xyz), normalize(sun_dir))) > 0.9995;
	float role = floor(v_role + 0.5);
	vec4 rp2 = texelFetch(role_params, ivec2(int(v_row + 0.5), 2), 0);
	vec4 f_rp3 = texelFetch(role_params, ivec2(int(v_row + 0.5), 3), 0);
	if (rp2.w < 0.5) {
		discard;
	}
	bool foliage = role < 0.5 || role > 7.5;
	if (foliage && bare > 0.5) {
		discard;
	}
	float near7 = cap_on > 1.5 ? smoothstep(0.0, 1.0, lod_level) : 1.0;
	// Round 15 (row 6: z twig, w ridge). twig: a bare crown has no solid at home zoom (its twig
	// strokes stand alone); with distance the solid closes, so a far bare wood is soft masses.
	vec4 f_rp6 = texelFetch(role_params, ivec2(int(v_row + 0.5), 6), 0);
	// (Round 17: a bare crown draws nothing here; round 16's veil and its broken edge are gone. What
	// is left of a bare willow, a few whips, is solid.)
	if (foliage && v_form > 0.5 && f_rp3.y > 0.0 && (silhouette < 0.5 || silhouette > 1.5) && !(r16 > 0.5 && f_rp6.z > 0.5)) {
		if (!g_sun && p_noise(v_wp * 2.3 + 7.0) < f_rp3.y * near7) {
			discard;
		}
	}
	// tt-sim (painter-trees-polish): a crown mass's outline breaks into soft lobes by a world noise
	// where it turns from the eye, so its 8-sided polygon and the flat facets at its rim never read
	// as slabs between the strokes (the strokes carry the crown's edge). Camera pass only.
	if (foliage && v_form < 1.5 && !g_sun) {
		vec3 rim_eye = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - v_wp) : normalize(INV_VIEW_MATRIX[2].xyz);
		if (abs(dot(normalize(v_wn), rim_eye)) < MASS_RIM_BREAK * p_noise(v_wp * 1.7 + 13.0)) {
			discard;
		}
	}
	if (g_sun && shadow_simple < 0.5 && foliage && v_form < 1.5) {
		vec3 g_sd = normalize(sun_dir);
		vec3 g_sx = normalize(cross(g_sd, vec3(0.0, 1.0, 0.0)));
		vec3 g_sy = cross(g_sd, g_sx);
		vec2 g_q = vec2(dot(v_wp, g_sx), dot(v_wp, g_sy));
		float g_c = dot(normalize(v_wn), g_sd);
		float g_r = sqrt(max(1.0 - g_c * g_c, 0.0));
		float g_hi = smoothstep(0.9, 1.8, v_height);
		if (g_r > mix(1.0, mix(0.72, 1.0, smoothstep(0.15, 0.85, p_noise(vec3(g_q * 0.55, 3.0)))), g_hi)) {
			discard;
		}
		float g_open = (role > 7.5 ? 0.0 : mix(0.55, 1.0, smoothstep(0.0, 0.35, f_rp3.y))) * g_hi;
		if (p_noise(vec3(g_q * 0.4, 9.0)) < 0.2 * g_open) {
			discard;
		}
	}
	vec3 to_sun = -normalize(sun_dir);
	// Round 19: a limb stroke. Its place across the limb (w_a, 1 = the grown edge), its length along
	// (w_s, metres), its edge (wandering, in limb coordinates), the snow that stands over its up side,
	// its dry-brush breaks, and the round normal the place across stands for.
	bool wood = v_form > 1.5;
	float form19 = wood ? 0.0 : v_form;
	float w_twig = 0.0;
	float w_a = 0.0;
	float w_s = 0.0;
	float w_e = 1.0;
	float w_wl = 0.1;
	float w_sd = 0.0;
	float w_sa = 0.0;
	bool w_out = false;
	vec3 w_n = vec3(0.0, 1.0, 0.0);
	vec3 w_lat = vec3(1.0, 0.0, 0.0);
	vec3 w_up = vec3(0.0, 1.0, 0.0);
	bool w_drift = false;
	if (wood) {
		w_twig = clamp(v_form - 2.0, 0.0, 1.0);
		w_a = v_snow.x;
		w_s = v_fn.x;
		w_sa = v_snow.y;
		w_sd = v_bseed * 53.0;
		w_wl = max(v_fn.z * 5.0, 0.1);
		vec3 tgw = normalize(v_tg);
		vec3 vcw = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - v_wp) : normalize(INV_VIEW_MATRIX[2].xyz);
		w_lat = cross(tgw, vcw);
		w_lat = dot(w_lat, w_lat) > 1e-5 ? normalize(w_lat) : normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 frn = cross(w_lat, tgw);
		float sidek = w_a > 0.0 ? 3.7 : 9.1;
		// (A twig is a pixel or two wide: it gets its breaks only, none of the limb's edge, streak or turn noise.)
		bool fine19 = w_twig > 0.6;
		if (!fine19) {
			w_e = 1.0 + ((p_noise(vec3(w_s / w_wl, sidek, w_sd)) - 0.5) * 2.0 + (p_noise(vec3(w_s / (w_wl * 0.27), sidek + 5.0, w_sd)) - 0.5) * 0.7) * limb_edge19 * (1.0 - 0.6 * w_twig);
		}
		w_up = snow_up17(tgw);
		float upk = dot(w_lat, w_up);
		float aa = abs(w_a);
		float ext = (w_a * upk > 0.0 && w_sa > 0.0) ? sqrt(clamp(w_sa, 0.0, 1.3)) * snow_over19 * abs(upk) * (0.75 + 0.5 * p_noise(vec3(w_s / (w_wl * 1.3), 7.0, w_sd))) : 0.0;
		float lim = w_e + ext;
		if (v_snow.z > 0.5 && snow_drift19 > 0.0 && limb_snow17 > 0.0 && deposit > 0.0) {
			// The drift at the foot of the stem: a low mound, wider than the stem, round on top.
			// (First version: everything under a height; a white plate with a straight lower edge.)
			float xo = aa / (w_e + 0.75);
			float dome = sqrt(max(1.0 - xo * xo, 0.0));
			float cap = snow_drift19 * (0.6 + 0.7 * p_noise(vec3(w_a * 1.3 + w_sd, 0.0, w_sd * 0.3))) * dome;
			w_drift = v_height < cap && v_height > -snow_drift19 * 0.4 * dome && xo < 1.0;
			if (w_drift) {
				lim = max(lim, w_e + 0.75);
			}
		}
		if (aa > lim) {
			discard;
		}
		w_out = aa > w_e;
		float an = clamp(w_a / w_e, -1.0, 1.0);
		if (v_snow.z > 0.5 && !w_drift && v_height < v_lr * 0.6 * (1.0 - sqrt(max(1.0 - an * an, 0.0)))) {
			// The stem's foot is round, not cut straight.
			discard;
		}
		// A limb that ends thick ends round, never cut square.
		float over19 = (w_s - (w_s / max(v_fn.y, 1e-4) - v_lr * 0.5)) / max(v_lr * 0.5, 1e-4);
		if (over19 > 0.0 && over19 > sqrt(max(1.0 - an * an, 0.0))) {
			discard;
		}
		if (!w_out && !w_drift) {
			float dry = limb_dry19 * (smoothstep(0.45, 1.0, aa / w_e) * 0.8 + 0.5 * smoothstep(0.5, 1.0, v_fn.y)) * (1.0 - w_twig);
			if (!g_sun && dry > 0.05 && !fine19 && p_noise(vec3(w_a * 3.3 + w_sd, w_s / (w_wl * 3.0), w_sd * 0.7)) < dry * 0.52) {
				discard;
			}
			if (!g_sun && w_twig > 0.0 && p_noise(vec3(w_s / 0.2, w_sd, 4.0)) < twig_break19 * w_twig) {
				discard;
			}
		}
		w_n = normalize(w_lat * an + frn * sqrt(max(1.0 - an * an, 0.0)) + vec3(0.0, 1e-5, 0.0));
	}
	vec3 n = wood ? w_n : normalize(v_wn);
	vec3 ln = normalize(mix(n, normalize(v_fn + vec3(0.0, 1e-6, 0.0)), calm * 0.8 * form19 * (1.0 - f_rp3.z)));
	float ndl = dot(ln, to_sun) - v_under * 0.35 * calm * crown_occ;
	if (wood && w_twig < 0.6) {
		// The turn from the light side to the shade side wanders along the limb and breaks into streaks.
		ndl += ((p_noise(vec3(w_s / (w_wl * 0.45), 2.0, w_sd)) - 0.5) * 1.2 + (p_noise(vec3(w_a * 2.5, w_s / (w_wl * 5.0), w_sd + 3.0)) - 0.5) * 0.6) * limb_turn19;
	}
	if (wood && w_twig < 0.6 && PROJECTION_MATRIX[3][3] == 0.0 && e_far < 0.5) {
		float e_nr = 1.0 - smoothstep(6.0, 18.0, distance(INV_VIEW_MATRIX[3].xyz, v_wp));
		float e_an = abs(clamp(w_a / w_e, -1.0, 1.0)) + (p_noise(vec3(w_s / (w_wl * 0.6), 3.0, w_sd)) - 0.5) * 0.3;
		ndl -= smoothstep(0.74, 0.98, e_an) * 0.45 * e_nr;
		ndl += (p_noise(vec3(w_a * 4.0 + w_sd, w_s / (w_wl * 2.5), w_sd + 9.0)) - 0.5) * 0.7 * e_nr;
	}
	float wob = p_noise(v_wp * 1.9 + 5.0);
	// Round 17 (turn-break): the edge between a crown's tones wanders in broad scallops.
	float tb17 = foliage ? (p_noise(v_wp * 0.8 + 17.0) - 0.5) * turn17 : 0.0;
	if (foliage) {
		ndl = crown_ndl18(ndl);
	}
	float t = tone3(ndl, (wob - 0.5) * 0.34 * (1.0 - calm * 0.85) + tb17, 0.008);
	if (foliage) {
		// Round 18 (crown-lo, crown-hi, turn-half): a crown turns in five steps under its own thresholds.
		t = crown_tone18(ndl + (wob - 0.5) * 0.34 * (1.0 - calm * 0.85) + tb17, 0.008);
	}
	float cast = 0.0;
	if (calm > 0.5 && role != ROLE_GROUND && !(r16 > 0.5 && foliage && f_rp6.z > 0.5)) {
		if (r8 > 0.5 && role > 1.5 && role < 5.5) {
			cast = occ_soft(v_wp + n * 0.05, to_sun, int(v_inst + 0.5));
		} else if (form_occ(v_wp + n * 0.05, to_sun, int(v_inst + 0.5)) > 0.5) {
			t = min(t, foliage ? crown_cast18 : 0.1);
		}
	}
	if (foliage && PROJECTION_MATRIX[3][3] == 0.0 && e_far < 0.5) {
		float e_near = 1.0 - smoothstep(14.0, 40.0, distance(INV_VIEW_MATRIX[3].xyz, v_wp));
		t = max(t, e_lift_at(v_wp, e_near, n.y, 0.0));
	}
	float variant = mix(0.5, p_noise(v_wp * rp2.y + role * 17.0), rp2.x * (1.0 - calm * 0.3)) + v_hue;
	bool bark12 = (int(fix12 + 0.5) & 4) != 0 && abs(role - 1.0) < 0.5;
	float up12 = 1.0;
	if (f_rp3.w > 0.0) {
		variant = smoothstep(f_rp3.w - 1.6, f_rp3.w + 1.6, v_height);
		if (bark12) {
			up12 = smoothstep(v_rise - 1.1, v_rise + 1.1, v_height + (p_noise(v_wp * 0.9 + 2.0) - 0.5) * 1.4);
			variant = up12;
		}
	}
	float row = v_row;
	float dep = deposit * rp2.z * smoothstep(0.1, 0.55, n.y);
	bool dep_on = dep > dep_threshold(v_wp, 0.5);
	if (role > 7.5) {
		// Round 18 (snow-shelf): an evergreen's snow is a shelf on what faces up.
		dep_on = shelf18(n.y, rp2.z, v_wp, 0.5);
	}
	if (f_rp6.w > 0.0 && abs(role - 1.0) < 0.5 && v_lr > 0.0) {
		// Round 15, ridge: snow lies along the top of a limb that is thick enough and not upright,
		// as one continuous ridge; nothing on fine twigs, and on fewer limbs with distance.
		float lie = 1.0 - abs(normalize(v_tg).y);
		float thick = smoothstep(f_rp6.w * 0.6, f_rp6.w * 1.2, v_lr / mix(2.2, 1.0, near7));
		dep_on = deposit * rp2.z * smoothstep(0.08, 0.4, lie) * thick * smoothstep(0.2, 0.55, n.y) > 0.3 + 0.35 * p_noise(v_wp * 0.6 + 3.0);
	}
	t += patch17(v_wp) * 0.45;
	float mul = 1.0;
	float moss13 = 0.0;
	if (dep_on) {
		row = dep_row;
		mul = 1.0;
	} else if (v_moss > 0.01 && abs(role - 1.0) < 0.5 && !(bark12 && f_rp3.w > 0.0)) {
		if ((int(fix13 + 0.5) & 2) != 0) {
			vec3 sunh = normalize(vec3(to_sun.x, 0.0, to_sun.z) + vec3(0.0001, 0.0, 0.0));
			float low = 1.0 - smoothstep(0.25, 1.5, v_height + (p_noise(v_wp * 1.3 + 9.0) - 0.5) * 0.9);
			float side = smoothstep(-0.1, 0.7, -dot(n, sunh));
			moss13 = smoothstep(0.35, 0.75, low * side * (0.6 + 0.8 * p_noise(v_wp * 2.1 + 4.0))) * min(v_moss * 1.5, 1.0) * 0.7;
		} else if (p_noise(v_wp * 1.5 + 9.0) - 0.22 * n.y < v_moss * 0.4) {
			row = row_of(0.0, int(v_inst + 0.5));
			t -= 0.1;
		}
	}
	float ch = texelFetch(role_params, ivec2(int(v_row + 0.5), 7), 0).x;
	if (ch > 0.0 && !dep_on && role > 1.5 && role < 5.5) {
		float n1 = p_noise(v_wp * 0.55 + role * 5.0);
		float n2 = p_noise(v_wp * vec3(3.0, 0.8, 3.0) + 31.0);
		float blot = floor(n2 * 3.0) * 0.5;
		variant += ((n1 - 0.5) * 1.0 + (blot - 0.5) * 0.45 + (t - 0.45) * 0.6) * ch;
		mul *= 1.0 + ((n1 - 0.5) * 0.16 + (blot - 0.5) * 0.07) * ch;
	}
	ALBEDO = palette_at(t + v_value, row, variant) * mul;
	if (cast > 0.0) {
		ALBEDO = mix(ALBEDO, palette_at(min(t, 0.1) + v_value, row, variant) * mul, cast * 0.94);
	}
	if (wood && texelFetch(role_params, ivec2(int(row_of(0.0, int(v_inst + 0.5)) + 0.5), 6), 0).z > 0.5) {
		// A bare tree's leaf colour is its twig colour: no moss patch in it.
		moss13 = 0.0;
	}
	if (moss13 > 0.0) {
		ALBEDO = mix(ALBEDO, palette_at(t - 0.05 + v_value, row_of(0.0, int(v_inst + 0.5)), 0.5) * mul, moss13);
	}
	if (bark12 && !dep_on && row == v_row && v_lr > 0.0) {
		vec4 rp4 = texelFetch(role_params, ivec2(int(v_row + 0.5), 4), 0);
		vec4 rp5 = texelFetch(role_params, ivec2(int(v_row + 0.5), 5), 0);
		vec3 tg = normalize(v_tg);
		vec3 ref = abs(tg.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 e1 = normalize(cross(tg, ref));
		vec3 e2 = cross(tg, e1);
		float th = atan(dot(n, e2), dot(n, e1));
		float s = wood ? w_s : dot(v_wp, tg);
		float r = max(v_lr, 0.01);
		float coarse = mix(2.4, 1.0, near7);
		float m = 0.0;
		float dark = rp4.y;
		if (rp4.x > 0.0) {
			int mk = int(rp4.z + 0.5);
			if ((mk & 1) != 0) {
				// Dashes across the limb, one to a row at most, each part of the way round.
				float rowh = max(0.1, r * 0.8) * coarse;
				float fs = s / rowh + v_bseed * 7.0;
				float iy = floor(fs);
				float h1 = p_hash(vec3(iy, v_bseed * 91.0, 1.0));
				float h2 = p_hash(vec3(iy, v_bseed * 91.0, 2.0));
				float h3 = p_hash(vec3(iy, v_bseed * 91.0, 3.0));
				float dth = abs(mod(th - h2 * 6.2832 + 3.14159, 6.2832) - 3.14159);
				m = step(h1, rp4.x * 1.9) * step(dth, mix(0.45, 1.3, h3)) * step(abs(fract(fs) - 0.5), mix(0.12, 0.27, h3));
				// The dark, fissured foot of an older stem.
				float foot = (1.0 - smoothstep(0.2, 1.3, v_height + (p_noise(v_wp * 2.1) - 0.5) * 0.7)) * smoothstep(0.06, 0.12, r);
				m = max(m, step(1.0 - foot * 0.85, p_noise(vec3(th * 1.6, s * 5.0, v_bseed * 9.0))));
			} else if (abs(rp5.z - 11.0) < 0.5) {
				// Plates: rows of cells, each row shifted; the gaps between them are the dark.
				float ph = max(0.2, r * 2.6) * coarse;
				float fs = s / ph + v_bseed * 5.0;
				float row_i = floor(fs);
				float nth = clamp(floor(6.2832 * r / (max(0.1, r * 0.9) * coarse) + 0.5), 3.0, 8.0);
				float pwob = (p_noise(v_wp * 7.0) - 0.5) * 0.3;
				float fx = fract((th / 6.2832 + 0.5) * nth + p_hash(vec3(row_i, 5.0, v_bseed * 31.0)) + pwob);
				float fy = fract(fs + pwob * 0.5);
				float cw = 6.2832 * r / nth;
				float d = min(min(fx, 1.0 - fx) * cw, min(fy, 1.0 - fy) * ph);
				float fw = max(0.008 * coarse, 0.11 * cw);
				m = (1.0 - smoothstep(fw * 0.6, fw * 1.5, d)) * mix(1.0, 0.3, up12);
				dark = min(dark, 0.62);
			} else {
				// Furrows along the grain.
				float k = clamp(r / 0.035, 2.0, 7.0) / coarse;
				// (Round 19: along a curved limb the tangent turns; its length along goes in on a fixed axis,
				// or the furrows break into chevrons at every bend.)
				float f = p_noise(vec3(cos(th), sin(th), 0.0) * k + (wood ? vec3(0.0, 0.0, s * 1.25) : tg * (s * 1.25)) + v_bseed * 17.0);
				float w = 0.03 + 0.12 * rp4.x;
				m = 1.0 - smoothstep(w, w + 0.05, abs(f - 0.5));
			}
			m *= smoothstep(0.018, 0.04, r);
		}
		if (f_rp3.w > 0.0) {
			// A pine: grey-brown below, orange above.
			float l = dot(ALBEDO, vec3(0.3, 0.59, 0.11));
			vec3 grey = mix(vec3(l), ALBEDO, 0.3) * vec3(0.84, 0.82, 0.84);
			ALBEDO = mix(grey, ALBEDO * vec3(1.07, 0.98, 0.93), up12);
		}
		ALBEDO *= mix(1.0, dark, m);
	}
	if (wood) {
		// The twig manner: lighter and greyer (or the species' twig colour), one tone nearly.
		vec4 lf6 = texelFetch(role_params, ivec2(int(row_of(0.0, int(v_inst + 0.5)) + 0.5), 6), 0);
		if (w_twig > 0.0 && lf6.z > 0.5) {
			ALBEDO = mix(ALBEDO, palette_at(0.5 + (t - 0.5) * 0.6 + v_value, row_of(0.0, int(v_inst + 0.5)), 0.5), w_twig * twig_tone19);
		}
		// Snow as dabs along the up side: it stands out past the limb's edge in rounded lumps (w_out),
		// lies over the round top, and has a band of its blue shade where it meets the bark below.
		float sc = dot(n, w_up);
		float bnd = snow_bnd18(w_sa) + (p_noise(vec3(w_s / (w_wl * 0.8), 11.0, w_sd)) - 0.5) * 0.3;
		bool on_top = w_sa > 0.04 && sc > bnd;
		if (w_out || on_top) {
			float lit = dot(normalize(n + w_up), to_sun);
			float ts = (!w_out && sc < bnd + 0.24) ? 0.12 : (lit > -0.05 ? 0.9 : 0.5);
			ALBEDO = palette_at(ts, dep_row, 0.5);
		}
		if (w_drift) {
			float side = w_a * dot(w_lat, to_sun);
			ALBEDO = palette_at(side > -0.25 ? 0.9 : (side > -0.8 ? 0.5 : 0.12), dep_row, 0.5);
		}
	} else if (v_snow.y > 0.03 && abs(role - 1.0) < 0.5) {
		// Round 17 (limb-snow): the ridge. Lit snow on top, a band of the snow's blue shade where it
		// meets the bark; its lower edge wanders a little along the limb.
		float bnd = snow_bnd18(v_snow.y) + (p_noise(v_wp * 2.6 + 11.0) - 0.5) * 0.14;
		if (v_snow.x > bnd) {
			ALBEDO = palette_at(v_snow.x > bnd + 0.3 ? 0.9 : (v_snow.x > bnd + 0.13 ? 0.5 : 0.12), dep_row, 0.5);
		}
	}
	if (!wood && v_snow.z > 0.5 && snow_foot18 > 0.0 && limb_snow17 > 0.0 && deposit > 0.0 && abs(role - 1.0) < 0.5) {
		// Round 18 (snow-foot): snow heaped against the foot of the stem, lit on the sun's side.
		float cap18 = snow_foot18 * (0.45 + 1.1 * p_noise(vec3(v_wp.x * 2.3, 0.0, v_wp.z * 2.3) + 5.0));
		if (v_height < cap18) {
			ALBEDO = palette_at(dot(n, to_sun) > 0.05 ? (v_height < cap18 * 0.6 ? 0.9 : 0.5) : 0.12, dep_row, 0.5);
		}
	}
	ALBEDO = haze17(ALBEDO, -VERTEX.z);
	if (silhouette > 1.5) {
		ALBEDO = foliage ? vec3(0.0) : vec3(1.0);
	} else if (silhouette > 0.5) {
		ALBEDO = role == ROLE_GROUND ? vec3(1.0) : vec3(0.0);
	}
	ROUGHNESS = 1.0;
	if (!g_sun) {
		// The crown masses dissolve in bold world-space pieces (a slow noise, about half a metre),
		// a fine screen dither only softening each piece's rim: the plain dither read as a halftone
		// grain over a token at a close zoom (painter-a2a3), a quarter share still dotted every
		// rim (painter-a2a4). The wood stays through the canopy fades to ground the tree.
		float key = clamp(0.9 * p_noise(v_wp * 1.6 + 7.0) + 0.1 * bayer16(FRAGCOORD.xy / world_px_cell()), 0.0, 1.0);
		tree_fades(VERTEX, INV_VIEW_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.xy,
			VIEWPORT_SIZE, key, kind10 > 0.5, false);
	}
}

// The colour is the palette's (ALBEDO, ambient off): the sun only steps the block-in into the cool
// shade where a cast shadow falls on it (tree_cast; a building's, another crown's).
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += mix(vec3(1.0), cast_tint, tree_cast(ATTENUATION, v_wp));
	}
}
