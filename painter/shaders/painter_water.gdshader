shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted water (the authored water, a Blender plane and the river ribbon under the Painted look)
 * ==========================================================================================
 *
 * Water the way a painter lays it: ONE luminous wash per body with a few bold, soft-edged accent
 * strokes on it; nothing fine, nothing grey (card painter-water, docs/systems/painter.md "Water",
 * the research report docs/research/2026-11-15-painted-water/report.md, candidate C1).
 *
 *   The wash. The vertical water column over the bed (the depth buffer's world position against
 *   this surface's, so it does not change with the camera) picks one of three sheet colours,
 *   shallow, mid and deep, in bands that are about 60 percent posterised and whose edges wander by
 *   one slow noise. The wash is a real alpha (blend_mix lerps against the opaque painted ground
 *   under it): thin in the shallows, so a ford reads as a gravel bar under a wash, solid in the
 *   deep. No screen texture is read.
 *   The strokes. Two layers of short brush dabs in WORLD space (stroke_layer): a lighter, sky-tinted
 *   value and a darker deep value, on a jittered lattice of 2.4 m cells (one stroke per cell at
 *   most, so most of the water is plain wash). Each stroke is laid from its tail to its head,
 *   holds, and recedes from the tail, then the cell draws another elsewhere (a painter's boil):
 *   the seed changes only when the envelope is 0, so nothing pops, nothing scrolls and nothing
 *   swims when the camera orbits. On a river each lies along the flow and drifts downstream while
 *   it lives (a second or two, so none shears); on a lake each fans about the wind.
 *   The whites, all brush marks: a ragged lap ribbon along the waterline with a few detached
 *   dashes outside it (in the iso-depth frame of the depth buffer), dashes on fast shallow water
 *   (riffles), a wrap round rocks and wading tokens (Classic's depth-slope detector, thresholded),
 *   and for a wading token two or three broken arcs that step outward in visible steps and a
 *   teardrop of dashes downstream.
 *   The glints. A third lattice of short bright ticks, kept only where a stroke's own small tilt
 *   would reflect the sun toward the camera (the sun is the foliage_sun global): a ragged column
 *   toward the sun, gold at dusk, silver under the moon. Placed, not computed from a normal.
 *   Winter ice. Slow water (a pond) freezes to a pale periwinkle wash with a few long thin cracks
 *   (a Voronoi edge); a river freezes only at its rim; open water is punched round each wading
 *   token, so a token never stands on ice.
 *
 * Classic's uniforms that Motion keys and the network drive (wave_speed, flow_strength,
 * foam_strength, the disturbance points, the flow map, the skirt fade) keep their names; the
 * colours are the sheet's, under p_ names, so apply_water_settings() (which pushes water_color,
 * shore_color, foam_color by name) cannot fight the sheet. PainterWater swaps this shader onto the
 * shared water material and restores Classic's on release.
 *
 * The water is lit only as a SELECTOR, like the painted ground: light() reads the sun's
 * attenuation and writes the wash (and its strokes) lit or in a cast shadow's colour; foam and
 * glints are emission, so white water stays white in a shadow.
 *
 * Water Quality Low (water_quality_skip_fine_detail) drops the second stroke layer, the glints
 * and the cracks.
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://shaders/skirt_fade.gdshaderinc"
#include "res://shaders/wind_global.gdshaderinc"

// ---- Classic's names (Motion keys, the network, the level's water settings) ----------------
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float flow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float shore_fade_depth : hint_range(0.0, 0.3) = 0.04;
uniform float shore_ground_gate : hint_range(0.0, 1.0) = 1.0;
uniform float foam_edge_sensitivity : hint_range(0.1, 6.0) = 1.5;
uniform float disturbance_ripple_radius : hint_range(0.1, 5.0) = 1.2;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 water_disturbance_points[8];
uniform sampler2D water_flow_map : hint_default_black, filter_linear, repeat_disable;
instance uniform bool water_flow_present = false;
instance uniform bool water_skirt_fade = false;
uniform int skirt_seed = 0;
global uniform bool water_quality_skip_fine_detail;
global uniform vec4 foliage_sun;

// ---- The sheet's (PainterWater), LINEAR ------------------------------------------------------
uniform vec3 p_shallow = vec3(0.35, 0.8, 0.75);
uniform vec3 p_mid = vec3(0.15, 0.5, 0.7);
uniform vec3 p_deep = vec3(0.05, 0.2, 0.55);
uniform vec3 p_lit = vec3(0.5, 0.8, 0.9);
uniform vec3 p_shade = vec3(0.04, 0.15, 0.4);
uniform vec3 p_foam = vec3(0.95, 0.98, 0.98);
uniform vec3 p_glint = vec3(1.0, 0.95, 0.7);
uniform vec3 p_ice = vec3(0.8, 0.85, 0.95);
uniform vec3 p_sky = vec3(0.7, 0.85, 0.95);
// What a cast shadow does to the wash: its colour times this.
uniform vec3 p_shade_mul = vec3(0.6, 0.65, 0.85);
// The share of the lattice cells that hold a stroke, the stroke length (m), the boil's period (s),
// how much of the sun's side glints, the wash's deepest alpha, the shore ribbon's width (m), how
// far the still water freezes (0 none, 1 all).
uniform float p_strokes = 0.5;
uniform float p_stroke_len = 1.5;
uniform float p_boil = 3.2;
uniform float p_glints = 0.8;
uniform float p_opacity = 0.92;
uniform float p_foam_w = 0.22;
uniform float p_ice_amt = 0.0;
// The pixel footprints (metres) between which the strokes fade out: the wash carries a far view.
uniform vec2 p_px = vec2(0.045, 0.12);

varying vec3 world_pos;
varying vec3 f_lit;
varying vec3 f_shd;

// The wash: the column thresholds (m) between the bands, how hard the bands are posterised (the
// rest is a soft ramp), the share of the deepest alpha the shallow and mid bands keep.
const float BAND_1 = 0.2;
const float BAND_2 = 0.85;
const float POSTERISE = 0.6;
const float ALPHA_SHALLOW = 0.5;
const float ALPHA_MID = 0.8;
// The stroke lattice: its turn (radians), the cell (m) of the strokes and of the glints.
const float LATTICE_C = 0.9004;
const float LATTICE_S = 0.4350;
const float CELL = 2.4;
const float GLINT_CELL = 0.9;
// Below this decoded magnitude a flow texel is still water; above the valid maximum it is an
// unbound sampler (water.gdshader).
const float FLOW_DEAD_ZONE = 0.02;
const float FLOW_MAX_VALID = 1.1;
const float FLOW_SPEED_UNITS_PER_SEC = 0.6;
// Token wake (water.gdshader): the downstream half of a token's region is compressed this much.
const float WAKE_STRETCH = 2.0;
// Rock foam (the depth-slope detector) only where the near side of the jump reaches the surface.
const float EDGE_FOAM_REACH = 0.3;
// The arcs round a token: how many, how many steps an expansion takes, the cycle (s).
const int RING_COUNT = 3;
const float RING_STEPS = 7.0;
const float RING_CYCLE_S = 2.1;


vec2 rot2(vec2 v, float c, float s) {
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}


vec4 cell_rand(vec2 c, float seed) {
	vec2 a = c + seed;
	return vec4(
		be_hash(a),
		be_hash(a + vec2(17.13, 5.71)),
		be_hash(a + vec2(3.37, 29.9)),
		be_hash(a + vec2(41.7, 13.1))
	);
}


// World-XZ flow at this fragment (water.gdshader's water_flow, term for term). Zero without a map.
vec2 water_flow(vec2 uv, mat4 model) {
	if (!water_flow_present) {
		return vec2(0.0);
	}
	vec2 f = texture(water_flow_map, uv).rg * 2.0 - 1.0;
	float speed = length(f);
	if (speed <= FLOW_DEAD_ZONE || speed > FLOW_MAX_VALID) {
		return vec2(0.0);
	}
	vec3 local_dir = vec3(f.x, 0.0, -f.y) / speed;
	vec2 world_dir = (model * vec4(local_dir, 0.0)).xz;
	float world_len = length(world_dir);
	if (world_len <= 0.0001) {
		return vec2(0.0);
	}
	return world_dir / world_len * speed * flow_strength * FLOW_SPEED_UNITS_PER_SEC;
}


// View-space position of the opaque scene behind the water at screen `uv`.
vec3 water_scene_view(vec2 uv, mat4 inv_projection) {
	float depth_raw = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth_raw);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}


// One layer of brush strokes at world point `p`: x the coverage (0..1), y the id of the stroke
// that covers it (for the caller's own hashes). A stroke is one lattice cell's: a jittered centre,
// an angle of `dir` turned by up to `jitter` radians, laid tail to head, held and receded tail
// first over `boil` seconds, then the cell draws another (the seed changes at envelope 0). `flow`
// carries a living stroke downstream. `tilt_gate` (the reflected view direction) is non-zero for
// the glints: a cell's stroke is kept only where its own small tilt reflects the sun to the eye.
// 2 x 2 cells are looked at, chosen by the pixel's quadrant; the centre range, the length and the
// drift keep every stroke inside its cell's reach (half the cell).
vec2 stroke_layer(
	vec2 p, vec2 dir, float jitter, vec2 flow, float seed, float cell, float density,
	float len, float half_thick, float boil, float px, vec3 tilt_gate
) {
	vec2 l = rot2(p, LATTICE_C, -LATTICE_S) / cell;
	vec2 b = floor(l);
	vec2 f = l - b;
	vec2 o = vec2(f.x < 0.5 ? -1.0 : 0.0, f.y < 0.5 ? -1.0 : 0.0);
	float best = 0.0;
	float best_id = 0.0;
	float soft = 0.035 + px * 1.5;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec2 c = b + o + vec2(float(i), float(j));
			vec4 hc = cell_rand(c, seed);
			float cyc = TIME / boil + hc.x;
			float idx = floor(cyc);
			float ph = cyc - idx;
			vec4 hr = cell_rand(c + vec2(idx * 13.7, idx * 5.3), seed + 3.0);
			if (hr.x >= density) {
				continue;
			}
			vec2 cw = rot2((c + 0.3 + 0.4 * hr.yz) * cell, LATTICE_C, LATTICE_S);
			cw += flow * ph * boil * 0.8;
			float ang = (hr.w - 0.5) * jitter;
			vec2 d = rot2(dir, cos(ang), sin(ang));
			vec2 rel = p - cw;
			float u = dot(rel, d);
			float v = dot(rel, vec2(-d.y, d.x));
			float stroke_len = len * (0.6 + 0.8 * hc.y);
			float hw = half_thick * (0.7 + 0.6 * hc.z);
			float half_len = 0.5 * stroke_len;
			if (abs(v) > hw * 1.6 || abs(u) > half_len + 0.1) {
				continue;
			}
			if (tilt_gate.y != 0.0 || tilt_gate.x != 0.0 || tilt_gate.z != 0.0) {
				// A glint: this cell's tilt (a small fixed random turn of the surface) must reflect
				// the sun toward the eye. tilt_gate is the eye's reflected direction.
				vec3 sun = normalize(foliage_sun.xyz);
				vec3 r = normalize(tilt_gate + vec3(hc.y - 0.5, 0.0, hc.z - 0.5) * 1.0);
				if (smoothstep(0.82, 0.97, dot(r, sun)) < hr.z) {
					continue;
				}
			}
			float grow = smoothstep(0.0, 0.3, ph);
			float recede = smoothstep(0.62, 1.0, ph);
			float a0 = -half_len + stroke_len * recede;
			float b0 = -half_len + stroke_len * grow;
			float seg = b0 - a0;
			if (seg <= 0.03) {
				continue;
			}
			float t = clamp((u - a0) / seg, 0.0, 1.0);
			float lens = 1.0 - 0.8 * (2.0 * t - 1.0) * (2.0 * t - 1.0);
			float hwu = hw * lens * min(1.0, seg / (stroke_len * 0.5));
			// The bitten edge: bristle bands along the stroke bite the sides and the ends.
			float bite = be_cut(vec2(u * 1.1 + hc.w * 40.0, v * 1.3)) * 0.4 * hw;
			float e_across = hwu + bite - abs(v);
			float e_along = min(u - a0, b0 - u) + bite * 1.5;
			float cov = smoothstep(0.0, soft, min(e_across, e_along));
			if (cov > best) {
				best = cov;
				best_id = c.x * 7.0 + c.y * 131.0 + idx;
			}
		}
	}
	// Past the footprint limit a stroke is under a few pixels: the wash carries the view.
	best *= 1.0 - smoothstep(p_px.x, p_px.y, px);
	return vec2(best, best_id);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 p = world_pos.xz;
	float world_units_per_pixel = length(fwidth(p)) + 0.0001;
	bool fine = !water_quality_skip_fine_detail;

	// ---- Flow -------------------------------------------------------------------------------
	vec2 flow_ws = water_flow(UV, MODEL_MATRIX);
	float flow_speed = length(flow_ws);
	vec2 wind_flat = wind_dir.xy;
	wind_flat = dot(wind_flat, wind_flat) > 0.0001 ? normalize(wind_flat) : vec2(1.0, 0.0);
	float flow_k = smoothstep(FLOW_DEAD_ZONE, 0.1, flow_speed);
	vec2 dir = normalize(mix(wind_flat, flow_speed > 0.0 ? flow_ws / flow_speed : wind_flat, flow_k));
	vec2 across_dir = vec2(-dir.y, dir.x);

	// ---- The bed under the water --------------------------------------------------------------
	float water_surface_depth = -VERTEX.z;
	vec3 scene_view = water_scene_view(SCREEN_UV, INV_PROJECTION_MATRIX);
	float bed_depth = max(-scene_view.z - water_surface_depth, 0.0);
	float ground_like = 1.0;
	if (shore_ground_gate > 0.0) {
		vec3 scene_normal = cross(dFdx(scene_view), dFdy(scene_view));
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float upness = abs(dot(normalize(scene_normal + vec3(1e-6)), up_view));
		ground_like = mix(1.0, smoothstep(0.35, 0.65, upness), shore_ground_gate);
	}
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float column_raw = max(world_pos.y - bed_world.y, 0.0);
	// Anything that is not ground under the water (a reed blade, a token's leg) reads as deep.
	float column = mix(1.0, column_raw, ground_like);

	// ---- The wash -----------------------------------------------------------------------------
	float wob = 0.7 + 0.6 * p_noise(vec3(p.x * 0.16, TIME * 0.03, p.y * 0.16));
	float s = column / wob;
	float m1 = mix(smoothstep(BAND_1 - 0.04, BAND_1 + 0.04, s), smoothstep(BAND_1 - 0.3, BAND_1 + 0.3, s), 1.0 - POSTERISE);
	float m2 = mix(smoothstep(BAND_2 - 0.06, BAND_2 + 0.06, s), smoothstep(BAND_2 - 0.5, BAND_2 + 0.5, s), 1.0 - POSTERISE);
	vec3 wash = mix(mix(p_shallow, p_mid, m1), p_deep, m2);
	float wash_a = mix(mix(ALPHA_SHALLOW, ALPHA_MID, m1), 1.0, m2) * p_opacity;
	// A flat sky tint rising with the angle off the vertical: the water is not a mirror.
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float graze = pow(1.0 - clamp(dot(up_v, VIEW), 0.0, 1.0), 3.0);
	wash = mix(wash, p_sky, graze * 0.55);
	// The wash fades in over the first centimetres: a wet edge, not a plane ending on the shore.
	float shoreline = shore_fade_depth > 0.0 ? smoothstep(0.0, shore_fade_depth * 0.8, column) : 1.0;
	wash_a *= mix(1.0, shoreline, ground_like);

	// ---- Tokens: arcs, the wake and the open water they punch in ice -------------------------------
	float ring_cov = 0.0;
	float wake_cov = 0.0;
	float open_water = 1.0;
	float ring_r = max(disturbance_ripple_radius, 0.3);
	for (int i = 0; i < 8; i++) {
		if (water_disturbance_points[i].w < 0.5) {
			continue;
		}
		vec2 to_point = p - water_disturbance_points[i].xy;
		float dist = length(to_point);
		float along = 0.0;
		float across = dot(to_point, across_dir);
		float sdist = dist;
		if (flow_speed > 0.0) {
			along = dot(to_point, dir);
			float stretched = along > 0.0 ? along / (1.0 + WAKE_STRETCH * flow_speed) : along;
			sdist = length(vec2(stretched, across));
		}
		open_water *= smoothstep(0.45, 0.95, sdist);
		if (sdist > ring_r) {
			continue;
		}
		float ang = atan(to_point.y, to_point.x);
		for (int k = 0; k < RING_COUNT; k++) {
			float cyc = TIME / RING_CYCLE_S + float(k) / float(RING_COUNT);
			float ph = fract(cyc);
			float stepped = floor(ph * RING_STEPS) / RING_STEPS;
			float rr = mix(0.3, ring_r, stepped);
			// Broken: a gap pattern by angle that changes with each expansion.
			float gap = be_n2(vec2(ang * 1.7 + float(k) * 9.1, floor(cyc) * 3.7 + float(k)));
			float arc = smoothstep(0.32, 0.45, gap);
			float body = 1.0 - smoothstep(0.035, 0.07 + world_units_per_pixel, abs(sdist - rr));
			ring_cov = max(ring_cov, body * arc * (1.0 - stepped));
		}
		if (flow_speed > 0.0 && along > 0.0) {
			// A teardrop of dashes downstream, in the flow's frame.
			float lobe = (1.0 - smoothstep(0.0, ring_r, sdist)) * smoothstep(0.0, 0.3, along * flow_speed);
			float pulse = 0.5 + 0.5 * sin(TIME * 2.3 + be_n2(vec2(floor(across * 5.0), 3.0)) * 6.28);
			float dash = smoothstep(0.55, 0.7, be_n2(vec2(across * 6.0, along * 1.4)) * pulse + 0.15);
			wake_cov = max(wake_cov, lobe * dash);
		}
	}

	// ---- Ice --------------------------------------------------------------------------------
	float ice_k = 0.0;
	float crack = 0.0;
	if (p_ice_amt > 0.001) {
		float still = 1.0 - smoothstep(0.03, 0.12, flow_speed);
		float rim = 1.0 - smoothstep(0.12, 0.5, column);
		float want = p_ice_amt * max(still, rim * 0.9);
		float edge_noise = (p_noise(vec3(p.x * 0.7, 1.0, p.y * 0.7)) - 0.5) * 0.3;
		ice_k = smoothstep(0.35, 0.55, want + edge_noise) * open_water;
		if (fine && ice_k > 0.01) {
			vec2 q = p / 1.9;
			vec2 qi = floor(q);
			float f1 = 8.0;
			float f2 = 8.0;
			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					vec2 cc = qi + vec2(float(i), float(j));
					vec2 pt = cc + vec2(be_hash(cc), be_hash(cc + 7.7));
					float dd = length(q - pt);
					if (dd < f1) {
						f2 = f1;
						f1 = dd;
					} else if (dd < f2) {
						f2 = dd;
					}
				}
			}
			float local = smoothstep(0.45, 0.62, p_noise(vec3(p.x * 0.4, 5.0, p.y * 0.4)));
			crack = (1.0 - smoothstep(0.0, 0.035 + world_units_per_pixel * 0.7, (f2 - f1) * 1.9)) * local;
		}
	}

	// ---- Strokes ----------------------------------------------------------------------------
	vec3 x = mix(wash, p_ice, ice_k);
	float a = mix(wash_a, 0.96, ice_k);
	float live = (1.0 - ice_k) * smoothstep(0.08, 0.4, column);
	float px = world_units_per_pixel;
	float jitter = mix(1.1, 0.4, flow_k);
	// Still water (a pond) takes more strokes than a river: its wash has no flow to carry the eye.
	float share = p_strokes * (1.0 + 0.9 * (1.0 - flow_k));
	vec2 la = stroke_layer(p, dir, jitter, flow_ws, 1.0, CELL, share, p_stroke_len, 0.11, p_boil, px, vec3(0.0));
	x = mix(x, p_lit, la.x * live);
	a = max(a, la.x * live * 0.9);
	if (fine) {
		vec2 lb = stroke_layer(p, dir, jitter, flow_ws, 9.0, CELL * 1.13, share * 0.8, p_stroke_len * 1.2, 0.13, p_boil * 1.3, px, vec3(0.0));
		x = mix(x, p_shade, lb.x * live * 0.85);
		a = max(a, lb.x * live * 0.95);
	}
	x = mix(x, p_shade, crack * 0.7);

	// ---- Whites -----------------------------------------------------------------------------
	float foam_k = clamp(foam_strength, 0.5, 1.5);
	// The lap ribbon, in the iso-depth frame: the gradient of the column in world XZ points
	// toward the deeper water; the horizontal distance from the shore is the column over its slope.
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float det = dpx.x * dpy.y - dpx.y * dpy.x;
	vec2 grad = vec2(0.0);
	if (abs(det) > 1e-9) {
		float dcx = dFdx(column_raw);
		float dcy = dFdy(column_raw);
		grad = vec2(dcx * dpy.y - dcy * dpx.y, dcy * dpx.x - dcx * dpy.x) / det;
	}
	float slope = max(length(grad), 0.06);
	float d_h = column_raw / slope;
	float lap_w = p_foam_w * (0.8 + 0.25 * sin(TIME * 1.1 + p_noise(vec3(p.x * 0.3, 2.0, p.y * 0.3)) * 6.28));
	float bite_n = p_noise(vec3(p.x * 2.6, floor(TIME * 0.5), p.y * 2.6));
	float thr = lap_w * (0.4 + 0.75 * bite_n);
	float lap = (1.0 - smoothstep(thr - 0.03, thr + 0.02, d_h)) * smoothstep(0.0, 0.03, d_h + 0.02);
	float dash_n = p_noise(vec3(p.x * 3.1, 4.0 + floor(TIME * 0.4), p.y * 3.1));
	float outer = lap_w * 1.5;
	float dashes = (1.0 - smoothstep(0.03, 0.06, abs(d_h - outer))) * smoothstep(0.64, 0.72, dash_n);
	float shore_foam = max(lap, dashes) * ground_like * smoothstep(0.0, 0.01, column_raw + 0.004);
	// Riffles: dense short dashes along the flow on fast, shallow water.
	float rapid = smoothstep(0.18, 0.4, flow_speed) * (1.0 - smoothstep(0.25, 0.7, column));
	if (rapid > 0.0) {
		vec2 st = vec2(dot(p, dir) * 1.1, dot(p, across_dir) * 6.5);
		float pulse = 0.5 + 0.5 * sin(TIME * 1.7 + be_n2(st * 0.6 + 7.0) * 6.28);
		float dash = smoothstep(0.58, 0.68, be_n2(st) * (0.55 + 0.45 * pulse) + 0.18);
		shore_foam = max(shore_foam, dash * rapid);
	}
	// The wrap round rocks and tokens: Classic's depth-slope detector, thresholded to a soft mask.
	float depth_jump = fwidth(bed_depth);
	float depth_slope = depth_jump / world_units_per_pixel;
	float edge_foam = smoothstep(foam_edge_sensitivity, foam_edge_sensitivity * 3.0, depth_slope);
	float side_x = mod(floor(FRAGCOORD.x), 2.0) < 0.5 ? 1.0 : -1.0;
	float side_y = mod(floor(FRAGCOORD.y), 2.0) < 0.5 ? 1.0 : -1.0;
	float near_side = min(
		bed_depth,
		min(bed_depth + side_x * dFdx(bed_depth), bed_depth + side_y * dFdy(bed_depth))
	);
	edge_foam *= 1.0 - smoothstep(EDGE_FOAM_REACH * 0.5, EDGE_FOAM_REACH, max(near_side, 0.0));
	float wrap_n = p_noise(vec3(p.x * 5.0, 8.0 + floor(TIME * 0.6), p.y * 5.0));
	edge_foam = smoothstep(0.3, 0.5, edge_foam * (0.45 + wrap_n));
	float foam = clamp(max(max(shore_foam, edge_foam), max(ring_cov, wake_cov)) * foam_k, 0.0, 1.0);
	foam *= 1.0 - ice_k * 0.85 * (1.0 - open_water);
	a = max(a, foam * 0.96);

	// ---- Glints: ticks on the sun's side ------------------------------------------------------
	float glint = 0.0;
	if (fine && p_glints > 0.01 && ice_k < 0.5) {
		vec3 view_dir = -(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		vec3 reflected = normalize(vec3(view_dir.x, -view_dir.y, view_dir.z));
		vec2 perp = normalize(vec2(-reflected.z, reflected.x) + vec2(1e-4, 0.0));
		vec2 lg = stroke_layer(p, perp, 0.4, flow_ws, 21.0, GLINT_CELL, p_glints, 0.34, 0.035, 1.4, px, reflected);
		glint = lg.x * live;
		a = max(a, glint);
	}

	// Cast shadows step the wash (and its strokes) into its shade colour; foam and glints are lit.
	float emit_k = clamp(max(foam, glint), 0.0, 1.0);
	vec3 emit_col = mix(p_foam, p_glint, glint * step(foam, glint));
	f_lit = x;
	f_shd = x * p_shade_mul;
	ALBEDO = vec3(1.0 - emit_k);
	EMISSION = emit_col * emit_k;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ALPHA = clamp(a, 0.0, 1.0);

	// Past the map edge (the river ribbon): the skirt's fade, lit water * a + backdrop * (1 - a),
	// its fog times a (water.gdshader's block, exactly: the wash only changes what `lit` is).
	if (water_skirt_fade) {
		float skirt_a = skirt_alpha_seeded(world_pos.xz, skirt_seed);
		if (skirt_backdrop_mode == 2) {
			ALPHA *= skirt_a;
		} else {
			vec4 fog = skirt_fog_at(VERTEX, INV_VIEW_MATRIX);
			float f = min(fog.a, 0.95);
			float keep = skirt_a * (1.0 - f * skirt_a) / (1.0 - f);
			ALBEDO *= keep;
			vec3 backdrop = skirt_backdrop_color(INV_VIEW_MATRIX);
			EMISSION = EMISSION * keep + max(
				(1.0 - skirt_a) * (backdrop * (1.0 - f * skirt_a) - fog.rgb * f) / (1.0 - f),
				vec3(0.0)
			);
		}
	}
}


void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float cast = 1.0 - smoothstep(0.44, 0.56, ATTENUATION);
		DIFFUSE_LIGHT += mix(f_lit, f_shd, cast);
	}
}
