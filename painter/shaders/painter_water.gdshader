shader_type spatial;
// The cost spike's exact reductions are on (card painter-water-cost-spike): comment these out for the
// unreduced shader. The marker line after the defines is where the probe injects its own.
#define ABL_CONSTOPT
#define RED_A
#define RED_B
#define RED_C
#define RED_D
#define RED_E
#define RED_F
#define RED_G
#define RED_I
//ABL_DEFS
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
 *   The field surface (card painter-water-field-painted, WaterFieldMesh): a vertex with
 *   CUSTOM1.y == FIELD_FLAG belongs to the ONE surface of a WaterField and carries its own depth,
 *   white-water energy, signed shore distance and steep share (CUSTOM0), so the wash, the shoreline
 *   and the lap read the model's fields instead of the depth buffer, and a fall is drawn by the same
 *   code as the river: steep surface turns the white into streaks running down, energy whitens the
 *   brink, the face and the foot as one shape. The water column is divided by the view ray's
 *   vertical share (the path through the water, not the plumb depth under it), so a pond reads as
 *   deep at an oblique view as it does from above. Any other vertex (a Blender plane, the exit
 *   ribbon) takes the depth-buffer path unchanged.
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
// True once a river leaves the map (SkirtExits.ribbon_material): skirt_half_extent is then the map's.
uniform bool p_exit = false;
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

// ---- Shade spike (card painter-water-shade-spike) ------------------------------------------------
// shade_opt bits: 1 the field's depth/energy/shore/steep read per fragment from textures (bicubic),
// 2 ONE clock (p_clock, integrated by PainterWater) and the drop-aware flow coordinate drive every
// motion, 4 a depth-aware tint floor for pools and a softer foot.
#ifdef ABL_CONSTOPT
const int shade_opt = 7;
#else
uniform int shade_opt = 7;
#endif
uniform float p_clock = 0.0;
uniform sampler2D fld_a : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D fld_b : filter_linear, repeat_disable, hint_default_black;
uniform vec2 fld_origin = vec2(0.0);
uniform vec2 fld_inv_step = vec2(4.0);
uniform vec2 fld_dim = vec2(1.0);
// The water's one clock: the engine's TIME for the old look, p_clock under option 2.
float wt() {
	return (shade_opt & 2) != 0 ? p_clock : TIME;
}


// B-spline bicubic of `t` at texel-space point `tc` (texel i's centre at i + 0.5): four bilinear
// fetches. Smooth (C2) through the field's kinks, so a contour of it has no grid stairs.
vec4 fld_cubic(sampler2D t, vec2 tc) {
	vec2 c = tc - 0.5;
	vec2 b = floor(c);
	vec2 f = c - b;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 p0 = (b - 0.5 + w1 / s0) / fld_dim;
	vec2 p1 = (b + 1.5 + w3 / s1) / fld_dim;
	return s0.y * (s0.x * texture(t, vec2(p0.x, p0.y)) + s1.x * texture(t, vec2(p1.x, p0.y)))
		+ s1.y * (s0.x * texture(t, vec2(p0.x, p1.y)) + s1.x * texture(t, vec2(p1.x, p1.y)));
}

const float FLOW_DROP_K = 0.5;
// The foot rule (cards painter-water-foot-spike, -foot2, -foot3): the metres of face above the foot
// the rules reach, the veil's reach below the foot (m: short, so a calm pool of blue shows at the foot
// at every zoom), the longest tongue of white below it (m), the seconds a tongue's length takes to
// drift, and the depth the pool floor follows (column per metre of depth).
const float FOOT_FACE_M = 1.6;
const float FOOT_VEIL_M = 1.9;
const float FOOT_TONGUE_M = 0.45;
const float FOOT_DRIFT_S = 9.0;
// The tongues' noise frequency across the flow (per metre) and the most white the floor holds: under
// one, so the blobs' pattern mottles it and the pool's blue shows between the tongues.
const float FOOT_TONGUE_FREQ = 1.6;
const float FOOT_FILL_MAX = 0.7;
const float POOL_DEPTH_K = 9.0;
// Under option 2: the speed (u per second) the whites travel along the flow coordinate.
const float FLOW_C = 1.1;
// Under option 4: pool tint floor (a column, m) where the shore is far and the water has body.
const float POOL_COLUMN_M = 1.0;
const float FOAM_EDGE_SOFT = 0.1;

varying vec3 world_pos;
varying vec2 v_mp;
varying vec3 f_lit;
varying vec3 f_shd;
// The field channels (WaterFieldMesh): depth, energy, shore distance, steep; river share, flag.
varying vec4 v_f0;
varying vec4 v_f1;
varying flat float v_rings;
// The white water: how much the energy whitens, the blob size (m).
uniform float p_white = 1.0;
uniform float p_blob_m = 0.9;
const float FIELD_FLAG = -7.0;
// The least vertical share of the view ray the water column is divided by (an eye-level view
// reads three times the plumb depth, not more).
const float VIEW_SHARE_MIN = 0.3;
// The white water's energy is raised to this power; the widest pixel footprint (m) its edge softens
// over (an eye-level view must not haze the whole pool). A river's ramp into a lower pond keeps a
// fifth of its white in the field itself (WaterField.RAMP_KEEP).
const float ENERGY_POWER = 1.3;
const float COVER_PX_MAX = 0.04;
// The half width of the white's edge in pattern units, on the flat and on a fall's face: crisp
// enough that a foot's blobs read as shapes, not ghost rings.
const float FOAM_EDGE = 0.05;
const float FACE_EDGE = 0.055;
// The field's shore ribbon wobble (m), and the alpha a film of a few centimetres keeps (a film is
// water over the dug bed, not a ghost of it: the share of the deepest alpha).
const float LAP_WOBBLE_M = 0.16;
// How far (m) the steep bank's smoothed waterline samples the shore distance on each side.
const float LAP_SMOOTH_M = 0.4;
const float FILM_ALPHA = 0.8;
const float FILM_COLUMN_M = 0.5;

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
#ifdef RED_D
			// The same hashes as cell_rand, the density test first: a cell that draws nothing costs two.
			vec2 ha = c + seed;
			float hcx = be_hash(ha);
			float cyc = wt() / boil + hcx;
			float idx = floor(cyc);
			float ph = cyc - idx;
			vec2 hb = (c + vec2(idx * 13.7, idx * 5.3)) + (seed + 3.0);
			float hrx = be_hash(hb);
			if (hrx >= density) {
				continue;
			}
			vec4 hc = vec4(hcx, be_hash(ha + vec2(17.13, 5.71)), be_hash(ha + vec2(3.37, 29.9)), be_hash(ha + vec2(41.7, 13.1)));
			vec4 hr = vec4(hrx, be_hash(hb + vec2(17.13, 5.71)), be_hash(hb + vec2(3.37, 29.9)), be_hash(hb + vec2(41.7, 13.1)));
#else
			vec4 hc = cell_rand(c, seed);
			float cyc = wt() / boil + hc.x;
			float idx = floor(cyc);
			float ph = cyc - idx;
			vec4 hr = cell_rand(c + vec2(idx * 13.7, idx * 5.3), seed + 3.0);
			if (hr.x >= density) {
				continue;
			}
#endif
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
	v_mp = VERTEX.xz;
	v_f0 = CUSTOM0;
	v_f1 = CUSTOM1;
#ifdef RED_I
	// Any token disturbance active (a uniform array: read per vertex, not per fragment).
	float any_pt = 0.0;
	for (int i = 0; i < 8; i++) {
		any_pt = max(any_pt, step(0.5, water_disturbance_points[i].w));
	}
	v_rings = any_pt;
#endif
}


// Two-phase flow advection of a value-noise blob field (no stretching, no endless scroll).
float flow_blobs(vec2 p, vec2 flow, float scale, float seed) {
	float period = 2.4;
	float ta = fract(wt() / period);
	float tb = fract(wt() / period + 0.5);
	vec2 qa = (p - flow * ta * period * 1.3) / scale;
	vec2 qb = (p - flow * tb * period * 1.3) / scale;
	float na = p_noise(vec3(qa.x, seed + floor(wt() / period) * 3.1, qa.y));
	float nb = p_noise(vec3(qb.x, seed + 1.7 + floor(wt() / period + 0.5) * 3.1, qb.y));
	float wa = 1.0 - abs(2.0 * ta - 1.0);
	// The phases hand over by shrinking and growing, the larger of the two (a linear mix of two
	// fields read as translucent discs wherever the thresholded white crossed the handover).
	return max(na * (0.65 + 0.35 * wa), nb * (0.65 + 0.35 * (1.0 - wa)));
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
#ifdef ABL_NODEPTH
	float bed_depth = 5.0;
	float ground_like = 1.0;
	float column_raw = 1.0;
#else
	float water_surface_depth = -VERTEX.z;
	vec3 scene_view = water_scene_view(SCREEN_UV, INV_PROJECTION_MATRIX);
	float bed_depth = max(-scene_view.z - water_surface_depth, 0.0);
	float ground_like = 1.0;
#ifdef RED_A
	// The field surface reads its own column and takes no part of the ground test: skip both.
	bool fieldv0 = v_f1.y < FIELD_FLAG + 0.5;
	float column_raw = 0.0;
	if (!fieldv0) {
		if (shore_ground_gate > 0.0) {
			vec3 scene_normal = cross(dFdx(scene_view), dFdy(scene_view));
			vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			float upness = abs(dot(normalize(scene_normal + vec3(1e-6)), up_view));
			ground_like = mix(1.0, smoothstep(0.35, 0.65, upness), shore_ground_gate);
		}
		vec3 bed_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
		column_raw = max(world_pos.y - bed_world.y, 0.0);
	}
#else
	if (shore_ground_gate > 0.0) {
		vec3 scene_normal = cross(dFdx(scene_view), dFdy(scene_view));
		vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float upness = abs(dot(normalize(scene_normal + vec3(1e-6)), up_view));
		ground_like = mix(1.0, smoothstep(0.35, 0.65, upness), shore_ground_gate);
	}
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float column_raw = max(world_pos.y - bed_world.y, 0.0);
#endif
#endif
	bool fieldv = v_f1.y < FIELD_FLAG + 0.5;
// The field's channels at this fragment: per vertex (the old way) or bicubic from the textures (S1).
vec4 fa = v_f0;
// The drop-aware flow coordinate (S2): the stroke's arc plus half the drop; a pond has none and
// takes the downstream distance of the flow map's direction and the height (has_u 0).
float uf = dot(p, dir) - FLOW_DROP_K * world_pos.y;
float has_u = 0.0;
#ifndef ABL_NOFETCH
if (fieldv) {
	vec2 tc = (v_mp - fld_origin) * fld_inv_step + 0.5;
	if ((shade_opt & 1) != 0) {
		fa = fld_cubic(fld_a, tc);
	}
#ifndef RED_G
	if ((shade_opt & 2) != 0) {
		vec4 fb = texture(fld_b, tc / fld_dim);
		has_u = smoothstep(0.2, 0.9, fb.g);
		uf = mix(uf, fb.r / max(fb.g, 0.001), has_u);
	}
#endif
}
#endif
	// ---- Foot rule (card painter-water-foot-spike) -----------------------------------------------
	// fd: the signed arc distance to the fall's foot (negative on the face, positive in the plunge
	// pool), foot_v 1 where the field holds one. ONE coordinate shared by the face and the pool, so
	// no rule ends on a line: the rules below are smooth functions of it.
	float fd = 9.0;
	float foot_in = 0.0;
	float foot_w = 0.0;
	// The mesh flags the vertices within the foot's range (CUSTOM1.z): the fetch is made only there,
	// whatever the energy, so the plunge pool of a fall into a pond (no energy of its own) has a foot.
	if (fieldv && v_f1.z > 0.02) {
		vec4 fbf = texture(fld_b, ((v_mp - fld_origin) * fld_inv_step + 0.5) / fld_dim);
		float foot_v = smoothstep(0.2, 0.9, fbf.a);
		fd = fbf.b / max(fbf.a, 0.001);
		// The white floor is whole 0.3 m above the foot (a lower face of broken water, not a glass
		// window with columns reaching the foot): the foot's last stretch holds no column edge to step
		// across. The line it starts on is broken by a slow noise across the flow (a straight band
		// reads as a slab).
		float fd_in = fd + (p_noise(vec3(dot(p, across_dir) * 1.3, 3.0, 8.0)) - 0.5) * 0.5;
		foot_in = smoothstep(-FOOT_FACE_M, -0.2, fd_in) * foot_v;
		// The veil reaches FOOT_VEIL_M below the foot and fades over all of it (the squared smoothstep:
		// a soft tail, no edge to cross).
		float veil_t = 1.0 - smoothstep(-0.2, FOOT_VEIL_M, fd);
		foot_w = foot_in * veil_t * veil_t * (3.0 - 2.0 * veil_t);
	}
	float curtain = 0.0;
	float path_k = 1.0;
	if (fieldv) {
		// The model's own plumb column at this point of the surface, whatever the camera sees; the
		// wash reads it along the view ray (the path through the water): a plumb column of a
		// pond's metre is a metre of water from above and several from the side.
		column_raw = max(fa.x, 0.0);
		ground_like = 1.0;
		curtain = smoothstep(0.05, 0.9, fa.w);
		vec3 view_world = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		path_k = 1.0 / clamp(abs(view_world.y), VIEW_SHARE_MIN, 1.0);
		// A film (CUSTOM1.w 0.125: water the dug bed no longer holds, a map error WaterField reports
		// as an event) draws as mid-depth water, not as the few centimetres it is: the shallow band
		// drew a pale teal glaze across a plunge pool.
		float film = smoothstep(0.02, 0.11, v_f1.w) * (1.0 - smoothstep(0.16, 0.22, v_f1.w));
		column_raw = mix(column_raw, max(column_raw, FILM_COLUMN_M / path_k), film);
	}
	// Anything that is not ground under the water (a reed blade, a token's leg) reads as deep.
	float column = mix(1.0, column_raw * path_k, ground_like);
	// A curtain's column is the drop under it: it reads as the river's mid glass, not the deep.
	column = mix(column, 0.55, curtain);
if (fieldv && (shade_opt & 4) != 0) {
	// A pool (water with body, far from every bank) reads deep like main's: the pale shallow band
	// belongs to the rim, not to the middle of a 0.3 m pool.
	// A narrow pool (a stream's lower pool, a metre across) has no middle 0.5 m from every bank: the
	// floor engages from a rim of a few centimetres, so it reads deep like the wide ones.
	float pool_k = smoothstep(0.04, 0.3, fa.z) * smoothstep(0.02, 0.08, fa.x) * (1.0 - curtain);
	// The floor follows the water's own depth (a column per metre of depth past the first 6 cm, up to
	// the pool's): a 0.17 m stream pool already reads deep, a lip's few centimetres stay shallow, so
	// the floor does not step the lip and thin water by a bank keeps its pale rim.
	column = max(column, min(max(fa.x - 0.06, 0.0) * POOL_DEPTH_K, POOL_COLUMN_M) * pool_k);
}
	// Where a river leaves the map the terrain's bed and the channel patch's meet in a crease: the low
	// column there drew a row of white dabs (the depth-slope wrap), a vertical strip of ice rim and a
	// dip in the wash's alpha across the river (painter-edges2). The shore effects keyed to a shallow
	// column fade out towards the map's edge, on either side (p_exit: set with the river's ribbon,
	// SkirtExits.ribbon_material). The ramp is long (0.3 to 2.2 m): over a metre it read as a step where
	// the bank foam and the pale shallows thicken as the fade begins (painter-water-edge3).
	float edge_band = 1.0;
	if (p_exit) {
		float edge_sd = max(abs(p.x) - skirt_half_extent.x, abs(p.y) - skirt_half_extent.y);
		edge_band = smoothstep(0.3, 2.2, abs(edge_sd));
	}

	// ---- The wash -----------------------------------------------------------------------------
#ifdef ABL_NOWOB
	float wob = 1.0;
#else
	float wob = 0.7 + 0.6 * p_noise(vec3(p.x * 0.16, wt() * 0.03, p.y * 0.16));
#endif
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
	if (fieldv) {
		// The waterline is the depth's zero contour: fade over its first centimetres of horizontal
		// distance too, so a steep bank does not end the wash on a hard line.
		shoreline = min(smoothstep(0.0, 0.05, fa.x), smoothstep(0.0, 0.14, fa.z));
		wash_a = max(wash_a, p_opacity * FILM_ALPHA * (1.0 - smoothstep(0.045, 0.1, fa.x)));
		// The thin water a bank sheds (CUSTOM1.w 0.5, WaterField's spill beyond the channel) draws
		// from a few centimetres' depth: it read as a pale shelf standing out from the bank.
		float bank_spill = step(0.25, v_f1.w) * (1.0 - step(0.75, v_f1.w));
		shoreline = min(shoreline, mix(1.0, smoothstep(0.05, 0.22, fa.x), bank_spill));
		shoreline = max(shoreline, curtain);
	}
	wash_a *= mix(1.0, shoreline, ground_like * edge_band);

	// ---- Tokens: arcs, the wake and the open water they punch in ice -------------------------------
	float ring_cov = 0.0;
	float wake_cov = 0.0;
	float open_water = 1.0;
	float ring_r = max(disturbance_ripple_radius, 0.3);
#ifdef ABL_NORINGS
	for (int i = 0; i < 0; i++) {
#elif defined(RED_I)
	for (int i = 0; i < (v_rings > 0.5 ? 8 : 0); i++) {
#else
	for (int i = 0; i < 8; i++) {
#endif
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
			float cyc = wt() / RING_CYCLE_S + float(k) / float(RING_COUNT);
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
			float pulse = 0.5 + 0.5 * sin(wt() * 2.3 + be_n2(vec2(floor(across * 5.0), 3.0)) * 6.28);
			float dash = smoothstep(0.55, 0.7, be_n2(vec2(across * 6.0, along * 1.4)) * pulse + 0.15);
			wake_cov = max(wake_cov, lobe * dash);
		}
	}

	// ---- Ice --------------------------------------------------------------------------------
	float ice_k = 0.0;
	float crack = 0.0;
#ifdef ABL_NOICE
	if (false) {
#else
	if (p_ice_amt > 0.001) {
#endif
		float still = 1.0 - smoothstep(0.03, 0.12, flow_speed);
		float rim = (1.0 - smoothstep(0.12, 0.5, column)) * edge_band;
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
	float live = (1.0 - ice_k) * smoothstep(0.08, 0.4, column) * (1.0 - curtain);
	float px = world_units_per_pixel;
	float jitter = mix(1.1, 0.4, flow_k);
	// Still water (a pond) takes more strokes than a river: its wash has no flow to carry the eye.
	float share = p_strokes * (1.0 + 0.9 * (1.0 - flow_k));
	// Where nothing of a stroke shows (live 0: the wet edge, a fall's face) no layer is looked at.
#ifdef RED_E
	bool live_on = live > 0.0;
#else
	bool live_on = true;
#endif
	vec2 la = vec2(0.0);
#ifndef ABL_NOSTROKE_A
	if (live_on) {
		la = stroke_layer(p, dir, jitter, flow_ws, 1.0, CELL, share, p_stroke_len, 0.11, p_boil, px, vec3(0.0));
	}
#endif
	x = mix(x, p_lit, la.x * live);
	a = max(a, la.x * live * 0.9);
#ifdef ABL_NOSTROKE_B
	if (false) {
#else
	if (fine && live_on) {
#endif
		vec2 lb = stroke_layer(p, dir, jitter, flow_ws, 9.0, CELL * 1.13, share * 0.8, p_stroke_len * 1.2, 0.13, p_boil * 1.3, px, vec3(0.0));
		x = mix(x, p_shade, lb.x * live * 0.85);
		a = max(a, lb.x * live * 0.95);
	}
	x = mix(x, p_shade, crack * 0.7);
	// The plunge's wash: aerated water, a milky glaze over the lower face and the pool below the foot,
	// strongest at the foot and gone by FOOT_VEIL_M, the same coordinate the glass colour uses. It
	// tints and thickens the water but never covers it: the pool's blue stays under it.
	x = mix(x, mix(p_lit, p_foam, 0.4), foot_w * 0.3);
	a = max(a, foot_w * 0.6);

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
	float shore_foam = 0.0;
	// Far from the waterline (past the widest reach of the lap and of the outer dashes, wobble and
	// pixel footprint included) a field fragment has no shore white: its noises are not read.
#ifdef RED_B
	if (!fieldv || fa.z <= p_foam_w * 1.6 + 0.14 + world_units_per_pixel + LAP_WOBBLE_M * 0.5) {
#else
	if (true) {
#endif
	if (fieldv) {
		// The true horizontal distance to the contour, smooth across triangles, and the bank's mean
		// slope from it (depth over that distance: smooth too, where the triangle's own gradient
		// jumps from one to the next).
		// The contour follows the 0.25 m grid: a slow wobble in it breaks the straight, square runs
		// of the ribbon into brush-edged ones.
		d_h = max(fa.z + (p_noise(vec3(p.x * 3.0, 6.0, p.y * 3.0)) - 0.5) * LAP_WOBBLE_M, 0.0);
		slope = clamp(max(fa.x, 0.0) / max(fa.z, 0.03), 0.06, 3.0);
	}
	float lap_w = p_foam_w * (0.8 + 0.25 * sin(wt() * 1.1 + p_noise(vec3(p.x * 0.3, 2.0, p.y * 0.3)) * 6.28));
	float bite_n = p_noise(vec3(p.x * 2.6, floor(wt() * 0.5), p.y * 2.6));
	float thr = lap_w * (0.4 + 0.75 * bite_n);
	// On a steep bank the gradient (and so d_h) jumps from one mesh triangle to the next: the lap's
	// edge softens there, so it reads as a brushed edge and not a row of crisp triangles.
	float steep = smoothstep(0.5, 1.3, slope);
	if (fieldv) {
		// The smoothed waterline beside the exact one: the signed shore distance averaged over a cross of
		// taps LAP_SMOOTH_M out. Exact on a straight bank, it rounds a ledge's corner and drops a thin
		// shelf's finger (the average goes negative there: no lap, the water still fades by its depth),
		// so the lap is a brushed band and not the claws of a ledge's own contour. The exact distance
		// still drives the wash, the fade and the pool floor.
		vec2 tcs = (v_mp - fld_origin) * fld_inv_step + 0.5;
		vec2 r = LAP_SMOOTH_M * fld_inv_step;
		float zs = 0.25 * (
			texture(fld_a, (tcs + vec2(r.x, 0.0)) / fld_dim).b
			+ texture(fld_a, (tcs - vec2(r.x, 0.0)) / fld_dim).b
			+ texture(fld_a, (tcs + vec2(0.0, r.y)) / fld_dim).b
			+ texture(fld_a, (tcs - vec2(0.0, r.y)) / fld_dim).b
		);
		d_h = zs + (d_h - fa.z);
	}
	// The foam's width and softness follow the bank's slope smoothly (it came from a steep/flat
	// switch): a steep bank's grid-wide steps of waterline are brushed out, not drawn as blocks.
	// With the exact waterline a steep bank's lap follows the terrain's triangles: a wider soft edge
	// and a larger, slower break of the distance, so the lap is a brushed band, not a zigzag line.
	float lap_soft = 0.03 + 0.32 * steep;
	d_h += (p_noise(vec3(p.x * 1.3, 9.0, p.y * 1.3)) - 0.5) * 0.5 * steep;
	float lap = (1.0 - smoothstep(thr - 0.03 - lap_soft, thr + 0.02 + lap_soft, d_h)) * smoothstep(0.0, 0.03, d_h + 0.02);
	float dash_n = p_noise(vec3(p.x * 3.1, 4.0 + floor(wt() * 0.4), p.y * 3.1));
	float outer = lap_w * 1.5;
	// The outer dashes sit on a gently sloped shore only: on a steep bank they broke into small
	// glitter triangles (cards painter-edges, painter-water-edge3), so they are cut off from a
	// slope of 0.9 (a bank about 42 degrees steep) and soft dabs, not crisp ticks, before it.
	// The exact waterline follows the terrain's own triangles, so on a rough bank a crisp tick at a
	// fixed distance from it draws a zigzag: the dashes are soft dabs (wide edge), and they stand
	// only on a gentle shore (gate from a slope of 0.25).
	float dash_gate = 1.0 - smoothstep(0.25, 0.7, slope);
	float dashes = (1.0 - smoothstep(0.03, 0.2 + world_units_per_pixel, abs(d_h - outer))) * smoothstep(0.6, 0.76, dash_n) * dash_gate;
	shore_foam = max(lap, dashes) * ground_like * smoothstep(0.0, 0.01, column_raw + 0.004);
	if (fieldv) {
		// The thin water a bank sheds and a river's ramp into a pond (CUSTOM1.w 0.5 and 1) is a wet
		// slope: no lap on it (a white arm stood out from each side of a pond's inflow).
		shore_foam *= 1.0 - 0.9 * smoothstep(0.2, 0.45, v_f1.w);
	}
	}
	// Riffles: dense short dashes along the flow on fast, shallow water.
	// The field draws its riffles from its own energy: the baked flow map's swirls in a pool would draw
	// contour lines here.
	float rapid = fieldv ? 0.0 : smoothstep(0.18, 0.4, flow_speed) * (1.0 - smoothstep(0.25, 0.7, column));
	if (rapid > 0.0) {
		vec2 st = vec2(dot(p, dir) * 1.1, dot(p, across_dir) * 6.5);
		float pulse = 0.5 + 0.5 * sin(wt() * 1.7 + be_n2(st * 0.6 + 7.0) * 6.28);
		float dash = smoothstep(0.58, 0.68, be_n2(st) * (0.55 + 0.45 * pulse) + 0.18);
		shore_foam = max(shore_foam, dash * rapid);
	}
#ifdef ABL_NOLAP
	shore_foam = 0.0;
#endif
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
#ifdef RED_C
	// No depth jump, no wrap: the noise only breaks an edge that is there.
	if (edge_foam > 0.0) {
		float wrap_n = p_noise(vec3(p.x * 5.0, 8.0 + floor(wt() * 0.6), p.y * 5.0));
		edge_foam = smoothstep(0.3, 0.5, edge_foam * (0.45 + wrap_n));
	}
#else
	float wrap_n = p_noise(vec3(p.x * 5.0, 8.0 + floor(wt() * 0.6), p.y * 5.0));
	edge_foam = smoothstep(0.3, 0.5, edge_foam * (0.45 + wrap_n));
#endif
#ifdef ABL_NOEDGE
	edge_foam = 0.0;
#endif
	edge_foam *= edge_band;
	shore_foam *= edge_band;
	float foam = clamp(max(max(shore_foam, edge_foam), max(ring_cov, wake_cov)) * foam_k, 0.0, 1.0);
	if (fieldv) {
		// White water from the field's energy, ONE shape over a riffle, an inflow, a brink, a face
		// and a foot: bold soft blobs carried by the flow on the flat, long streaks running down a
		// steep surface, thresholded by the energy (full white where it is 1).
		// The energy's middle is pulled down (a power): a fall's foot foam keeps its bold patches
		// near the fall and thins quickly, and a plunge pool is calm a metre or two away. A river's
		// ramp into a lower pond (CUSTOM1.w) is a slope, not a fall: it keeps a fifth of its white.
		float e_raw = fa.y;
		// The slope-white of a thin shelf at a bank's waterline (the exact waterline reaches the ledge
		// the 0.25 m grid used to cut off) is not a fall: it fades over the first 0.35 m from the shore.
		e_raw *= smoothstep(0.04, 0.35, max(fa.z, 0.0));
		float en = pow(clamp(e_raw * p_white, 0.0, 1.0), ENERGY_POWER);
		// On the face the white thins to streaks over glass; the brink and the foot keep it full.
		float en_c = mix(en, en * 0.62, curtain);
		// A white floor on the lower face: the sheet breaks into foam towards the foot, and its reach
		// below the foot is a tongue length that varies smoothly across the flow (a value noise, not a
		// hash per column: a hash steps between columns and its edge ends in cusps) and drifts on the
		// master clock, so the white ends in rounded tongues of different lengths that are never fixed
		// in place. The edge is wide: the white thins into the veil, it does not end on a line.
		float fill = 0.0;
		if (foot_in > 0.0) {
			float cu = dot(p, across_dir);
			cu += (p_noise(vec3(cu * 0.5, uf * 0.45, 4.0)) - 0.5) * 0.6;
			float hn = p_noise(vec3(cu * FOOT_TONGUE_FREQ, wt() / FOOT_DRIFT_S, 7.0));
			float hk = clamp((hn - 0.5) * 1.9 + 0.5, 0.0, 1.0);
			float tip = 0.05 + FOOT_TONGUE_M * hk;
			fill = foot_in * (1.0 - smoothstep(tip - 0.3, tip + 0.35 + 0.3 * hk, fd));
		}
		float en_e = en_c;
		en_c = max(en_c, fill * FOOT_FILL_MAX);
		// Under the floor (the cover below) nothing is white: the noises are not read there, which is
		// most of a pond and a river.
#ifdef ABL_NOWHITE
		if (false) {
#else
		if (en_c > 0.08 || foot_w > 0.03) {
#endif
		// One clock (S2): the blobs travel along the flow coordinate at one speed (still where the
			// field has no stroke: a pond's white boils in place), as the streaks and tongues do.
			bool one_clock = (shade_opt & 2) != 0;
#ifdef RED_G
			// The flow coordinate's texture is read only where a white is drawn.
			if (one_clock) {
				vec4 fb = texture(fld_b, ((v_mp - fld_origin) * fld_inv_step + 0.5) / fld_dim);
				has_u = smoothstep(0.2, 0.9, fb.g);
				uf = mix(uf, fb.r / max(fb.g, 0.001), has_u);
			}
#endif
			vec2 bq = one_clock ? vec2(uf, dot(p, across_dir)) : p;
			vec2 bf = one_clock ? vec2(FLOW_C * has_u, 0.0) : flow_ws;
			float c_face = (shade_opt & 4) != 0 ? smoothstep(0.1, 0.5, curtain) : curtain;
			// The pattern is mix(blob, streak, c_face) then mixed with the tongues by the curtain: a
			// term whose weight is 0 is not evaluated (RED_F; the weights 0 and 1 are exact).
#ifdef RED_F
			bool need_blob = c_face < 1.0;
			bool need_streak = c_face > 0.0 && curtain < 1.0;
#else
			bool need_blob = true;
			bool need_streak = true;
#endif
			float blob = 0.0;
			if (need_blob) {
				blob = flow_blobs(bq, bf, p_blob_m, 11.0) * 0.7 + flow_blobs(bq, bf, p_blob_m * 0.45, 23.0) * 0.3;
			}
		// Stretched linearly about its mean, so the energy's threshold cuts organic shapes, not its
		// own isolines (the raw noise sits near 0.5 and drew straight bands across the channel). A
		// smoothstep stretch saturated a third of it at 1, and any trace of energy lit those plateaus
		// whole (ponds plastered with blobs).
		blob = clamp((blob - 0.5) * 1.7 + 0.5, 0.0, 1.0);
#ifdef ABL_NOBLOB
		blob = 0.5;
#endif
		vec2 st = vec2(dot(p, across_dir) * 3.2, world_pos.y * 0.45 + wt() * 1.6);
			if (one_clock) {
				st.y = uf * 0.45 - wt() * 0.64;
			}
		float streak = 0.0;
		if (need_streak) {
			streak = p_noise(vec3(st.x, st.y, 5.0)) * 0.75 + p_noise(vec3(st.x * 2.3, st.y * 1.7, 9.0)) * 0.25;
		}
		streak = clamp((streak - 0.5) * 1.7 + 0.5, 0.0, 1.0);
#ifdef ABL_NOSTREAK
		streak = 0.5;
#endif
		// Option 4: the flat's blobs give way to the face's streaks early (a face's cloud discs read as
			// translucent bubbles on the glass).
			float pattern = mix(blob, streak, c_face);
		float edge_w = mix((shade_opt & 4) != 0 ? FOAM_EDGE_SOFT : FOAM_EDGE, FACE_EDGE, curtain);
#ifdef ABL_NOTONGUE
		if (false) {
#else
		if (curtain > 0.01) {
#endif
			// Tongues, in the flow's frame (the baked flow map's direction is smooth over the map: a
			// direction taken per fragment from the surface turned dot(p, d) into a maze of lines).
			// About 0.28 m columns, each its own width and white for its own length, blue between;
			// the columns bend gently so the sheet is not a comb.
			float u_f = dot(p, across_dir);
			float v_f = one_clock ? uf : dot(p, dir);
			u_f += (p_noise(vec3(u_f * 0.5, v_f * 0.45, 4.0)) - 0.5) * 0.6;
			float c_u = u_f * 3.6;
			float id = floor(c_u);
			float f_u = fract(c_u);
			vec2 hh = vec2(be_hash(vec2(id, 3.7)), be_hash(vec2(id, 8.3)));
			float gap = 0.03 + 0.4 * hh.y;
			float across = smoothstep(gap, gap + 0.14, f_u) * (1.0 - smoothstep(1.0 - gap - 0.14, 1.0 - gap, f_u));
			float run = p_noise(vec3(id * 1.7, 2.0, v_f * 0.35 - wt() * 0.5));
			pattern = mix(pattern, across * (0.35 + 0.65 * hh.x) * (0.5 + 1.0 * run), curtain);
		}
		// The columns' gaps fill with white as they near the foot.
		pattern = mix(pattern, 1.0, fill * 0.4);
		// White where the pattern stands over 1 - energy: all of it at 1, rare bold blobs at 0.3,
		// none under a floor. Where the foot's white floor stands its edge is a wide gradient (the
		// white fades out, it does not end).
		// The veil's reach keeps it soft too: the foot's last blobs melt into the pool, they do not end
		// on a crisp edge.
		edge_w = max(edge_w, 0.3 * smoothstep(0.0, 0.5, max(fill, foot_w * 0.8)));
		float cover = smoothstep(1.0 - en_c - edge_w, 1.0 - en_c + edge_w + min(px, COVER_PX_MAX) * 2.0, pattern);
		// The floor of the energy under which nothing is white; the foot's fade is read down to a few
		// percent (a gradual thinning into mottled mist, not a cut).
		cover *= smoothstep(0.08 * (1.0 - smoothstep(0.0, 0.3, foot_w)), 0.2, en_c);
		// The white the floor adds thins out by the floor's own fade (a smooth ramp over its whole
		// reach, where the threshold above would cut it in a tenth of it): translucent white tongues
		// over the pool's blue, not a slab with an edge. The field's own energy keeps its blobs.
		cover *= mix(1.0, max(smoothstep(0.0, 0.9, fill), smoothstep(0.1, 0.5, en_e)), foot_in);
		foam = max(foam, cover * smoothstep(0.0, 0.02, column_raw + curtain));
		}
	}
	foam *= 1.0 - ice_k * 0.85 * (1.0 - open_water);
	a = max(a, foam * 0.96);

	// ---- Glints: ticks on the sun's side ------------------------------------------------------
	float glint = 0.0;
#ifdef ABL_NOGLINT
	if (false) {
#else
	if (fine && p_glints > 0.01 && ice_k < 0.5 && live_on) {
#endif
		vec3 view_dir = -(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
		vec3 reflected = normalize(vec3(view_dir.x, -view_dir.y, view_dir.z));
		vec2 perp = normalize(vec2(-reflected.z, reflected.x) + vec2(1e-4, 0.0));
		vec2 lg = stroke_layer(p, perp, 0.4, flow_ws, 21.0, GLINT_CELL, p_glints, 0.34, 0.035, 1.4, px, reflected);
		glint = lg.x * live;
		a = max(a, glint);
	}

	// Cast shadows step the wash (and its strokes) into its shade colour; foam and glints are lit.
	if (fieldv && (shade_opt & 8) != 0) {
		// S4, the hybrid: main's curtain (the fall mesh, legacy shader) draws the steep faces.
		float hide = smoothstep(0.45, 0.65, fa.w);
		a *= 1.0 - hide;
		foam *= 1.0 - hide;
		glint *= 1.0 - hide;
	}
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
#ifdef ABL_NOLIGHT
	DIFFUSE_LIGHT += f_lit;
#else
	if (LIGHT_IS_DIRECTIONAL) {
		float cast = 1.0 - smoothstep(0.44, 0.56, ATTENUATION);
		DIFFUSE_LIGHT += mix(f_lit, f_shd, cast);
	}
#endif
}
