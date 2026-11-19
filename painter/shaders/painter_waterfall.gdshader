shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

/*
 * Painted waterfall (the AuthoredWater-falls mesh under the Painted look)
 * =====================================================================
 *
 * The fall in the painter's manner (card painter-water): a curtain of vertical ragged streaks over
 * a glass wash and a few broad soft mist shapes. The vertex contract is waterfall.gdshader's
 * (WaterFallMesh): COLOR.g 0 curtain, 0.5 ring, 1 mist; the curtain's UV is (metres across, metres
 * fallen) and UV2 (fall height, pool level), COLOR.r the side edge fade, COLOR.a the crest width
 * over 8 m; a mist puff's four vertices sit at its centre with UV2 the corner's offset in metres and
 * COLOR.b its seed; CUSTOM0 and CUSTOM1 the curtain's fall frame (WaterFallFrames).
 *
 * The white over the brink and at the foot is not the curtain's own (card painter-fall-frame-foam):
 * painter_fall_white.gdshaderinc draws it from the fall frame on the curtain here and on the river
 * and the pool in painter_water.gdshader, one shape over both joins. So the Painted look draws no
 * foam ring: the ring's vertices (Classic's, waterfall.gdshader) collapse to a point in vertex().
 *
 * Unshaded: every colour is the sheet's, so a cliff's shadow cannot grey the white water. The
 * curtain is a few bold tongues, not a noise field: a column of 0.3 m, each its own dash falling
 * with the water (feature positions in fall time, so they accelerate and lengthen), ragged-ended
 * by the ground's brush streak. The mist and the white step in time, a few steps a second:
 * nothing slides.
 *
 * Colour names are Classic's where Classic's settings reach them (wave_speed, flow_strength,
 * foam_strength), the sheet's under p_. Quality Low drops the mist and the second streak layer.
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_fall_white.gdshaderinc"

uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float flow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float glass_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.8;
uniform float mist_alpha : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
global uniform bool water_quality_skip_fine_detail;

uniform vec3 p_shallow = vec3(0.35, 0.8, 0.75);
uniform vec3 p_mid = vec3(0.15, 0.5, 0.7);
uniform vec3 p_lit = vec3(0.5, 0.8, 0.9);
uniform vec3 p_foam = vec3(0.95, 0.98, 0.98);
uniform vec3 p_sky = vec3(0.7, 0.85, 0.95);

const float GRAVITY = 9.81;
const float WIDTH_DECODE_M = 8.0;
const float NARROW_WIDTH_M = 1.2;
const float WIDE_WIDTH_M = 3.0;
const float BOTTOM_WHITE_SHARE = 0.3;
// The curtain runs into the pool (card painter-fall-continuity): its white foot ends in the 3 cm
// the mesh reaches under the pool level, torn by a few centimetres only, where the pool's foot
// white takes over. (It used to fade out up to 0.42 m over the pool, which left the face showing as
// a dark gap between the curtain and the water.)
const float BOTTOM_SINK_M = 0.03;
const float BOTTOM_FADE_M = 0.025;
const float BOTTOM_TEAR_M = 0.04;
// The brink has no tongue of its own: a light shallow-wash strip there read as a cyan hairline
// between the river and the roll (card painter-fall-round2), so the curtain's glass runs to the lip.
// The glass between the streaks: the share of the mid wash in it and its alpha, a luminous body of
// the river's blue rather than a grey film over the shaded face.
const float GLASS_MID_SHARE = 0.7;
const float GLASS_ALPHA = 0.78;
const float EDGE_SOFT = 0.12;
const float EDGE_BITE = 0.5;
const float NARROW_EDGE_BITE = 0.3;
const float BOTTOM_TAPER = 0.2;
const float NARROW_BOTTOM_TAPER = 0.08;
const float BOTTOM_TAPER_SHARE = 0.45;
// The streaks: a column's width (m), the time (s of fall) its dash cycle takes, the share of the
// cycle a dash lasts, the clock's rate.
const float COLUMN_M = 0.3;
const float DASH_CYCLE = 0.55;
const float DASH_DUTY = 0.5;
const float STREAK_RATE = 0.5;
// The mist: the rise (m) and the cycle (s) of a puff, its growth, the steps its rise is drawn in,
// the soft fade against the scene (m), its three lobes (spread, growth of spread, radii, rim share).
const float MIST_RISE_M = 0.5;
const float MIST_CYCLE_S = 4.0;
const float MIST_GROW = 1.3;
const float MIST_STEPS = 8.0;
const float MIST_SOFT_M = 0.25;
const float MIST_LOBE_SPREAD = 0.22;
const float MIST_LOBE_SPREAD_GROW = 0.08;
const vec3 MIST_LOBE_RADII = vec3(0.55, 0.48, 0.42);
const float MIST_LOBE_SOFT = 0.3;
const float MIST_WARP = 0.1;

varying vec3 world_pos;
varying float kind;
varying float edge;
varying float seed;
varying float fall_width;
varying vec2 uv;
varying vec2 uv2;
varying float mist_phase;
// The curtain's fall frame (WaterFallFrames, flat: one fall per triangle) and its map XZ.
varying flat vec4 fall_a;
varying flat vec4 fall_b;
varying vec2 fall_xz;


float fall_scene_depth(vec2 screen_uv, mat4 inv_projection) {
	float depth_raw = texture(depth_tex, screen_uv).r;
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, depth_raw, 1.0);
	return -(view.z / view.w);
}


void vertex() {
	kind = COLOR.g;
	edge = COLOR.r;
	seed = COLOR.b;
	fall_width = COLOR.a * WIDTH_DECODE_M;
	uv = UV;
	uv2 = UV2;
	mist_phase = 0.0;
	fall_a = CUSTOM0;
	fall_b = CUSTOM1;
	fall_xz = VERTEX.xz;
	if (COLOR.g > 0.25 && COLOR.g < 0.75) {
		// The foam ring is Classic's: here the pool's own foot white (painter_water.gdshader) is the
		// plunge's foam, so the ring collapses to a point and draws nothing.
		VERTEX = vec3(0.0);
	} else if (COLOR.g > 0.75) {
		// Mist: a billboard that rises, grows and sways over its cycle, at the puff's phase; its
		// rise and growth go in steps.
		float cycle = fract(TIME / MIST_CYCLE_S + COLOR.b);
		float stepped = floor(cycle * MIST_STEPS) / MIST_STEPS;
		mist_phase = stepped;
		vec2 off = UV2 * mix(1.0, MIST_GROW, stepped);
		float sway = sin(floor(TIME * 2.0) * 0.5 + COLOR.b * TAU) * 0.12;
		VERTEX.y += stepped * MIST_RISE_M;
		VERTEX += INV_VIEW_MATRIX[0].xyz * (off.x + sway) + INV_VIEW_MATRIX[1].xyz * off.y;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float foam_gain = clamp(foam_strength, 0.5, 1.5);
	vec3 glass = mix(p_shallow, p_mid, GLASS_MID_SHARE);
	if (kind > 0.75) {
		// ---- Mist: three broad round lobes, a firm soft rim, the core white, the rim sky ---------
		if (water_quality_skip_fine_detail) {
			discard;
		}
		vec2 q = uv * 2.0 - 1.0;
		float angle = seed * TAU;
		vec2 axis = vec2(cos(angle), sin(angle));
		float spread = MIST_LOBE_SPREAD + MIST_LOBE_SPREAD_GROW * mist_phase;
		vec2 wp = q * 1.7 + seed * 9.0;
		vec2 w = q + MIST_WARP * (vec2(be_n2(wp), be_n2(wp + vec2(5.2, 1.3))) - 0.5) * 2.0;
		vec2 c0 = axis * spread + vec2(0.0, -0.05);
		vec2 c1 = -axis * spread * 0.9 + vec2(0.0, 0.05);
		vec2 c2 = vec2(axis.y, -axis.x) * spread * 0.5 + vec2(0.0, 0.25);
		vec3 inner = MIST_LOBE_RADII * (1.0 - MIST_LOBE_SOFT);
		float l0 = 1.0 - smoothstep(inner.x, MIST_LOBE_RADII.x, length(w - c0));
		float l1 = 1.0 - smoothstep(inner.y, MIST_LOBE_RADII.y, length(w - c1));
		float l2 = 1.0 - smoothstep(inner.z, MIST_LOBE_RADII.z, length(w - c2));
		float cloud = min(l0 + l1 + l2, 1.0);
		float body = smoothstep(0.25, 0.55, cloud);
		float core = smoothstep(0.7, 0.95, cloud);
		float life = sin(mist_phase * PI);
		float soft = smoothstep(
			0.0, MIST_SOFT_M, fall_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z
		);
		ALBEDO = mix(mix(p_foam, p_sky, 0.55), p_foam, core);
		ALPHA = body * mix(0.7, 1.0, core) * life * soft * mist_alpha;
	} else if (kind > 0.25) {
		// The ring (collapsed in vertex()).
		discard;
	} else {
		// ---- Curtain: a glass wash, vertical ragged streaks, the fall white --------------------
		float v = max(uv.y, 0.0);
		float u = uv.x;
		float height = max(uv2.x, 0.01);
		float pool = uv2.y;
		float t_fall = sqrt(2.0 * v / GRAVITY);
		float t_now = TIME * STREAK_RATE * (1.0 + wave_speed);
		float cu = u / COLUMN_M;
		float col = floor(cu);
		float fcol = cu - col;
		float h1 = be_hash(vec2(col, 3.7));
		float h2 = be_hash(vec2(col, 11.3));
		// A dash per column, falling with the water: its phase is in fall time, so it lengthens.
		float ph = fract((t_fall - t_now) / (DASH_CYCLE * (0.8 + 0.5 * h1)) + h2);
		float dash = smoothstep(0.0, 0.1, ph) * (1.0 - smoothstep(DASH_DUTY - 0.1, DASH_DUTY, ph));
		float half_w = 0.3 + 0.16 * h2;
		float rag = be_cut(vec2(v * 0.9 + col * 13.0, u * 8.0)) * 0.12;
		float across = 1.0 - smoothstep(half_w - 0.1, half_w, abs(fcol - 0.5) + rag);
		float streak = dash * across;
		if (!water_quality_skip_fine_detail) {
			// A second, finer layer of narrower dashes offset across.
			float cu2 = u / (COLUMN_M * 0.55) + 0.5;
			float col2 = floor(cu2);
			float g1 = be_hash(vec2(col2, 5.9));
			float ph2 = fract((t_fall - t_now * 1.15) / (DASH_CYCLE * 0.7 * (0.8 + 0.5 * g1)) + g1 * 3.0);
			float dash2 = smoothstep(0.0, 0.12, ph2) * (1.0 - smoothstep(0.3, 0.42, ph2));
			float across2 = 1.0 - smoothstep(0.12, 0.2, abs(fract(cu2) - 0.5));
			streak = max(streak, dash2 * across2 * 0.7);
		}
		// The roll over the brink and the white at the foot: the fall white of the river and the pool
		// (painter_fall_white.gdshaderinc), so both joins are one shape.
		float lip = fall_white_curtain(fall_a, fall_b, fall_xz, v);
		float narrow = 1.0 - smoothstep(NARROW_WIDTH_M, WIDE_WIDTH_M, fall_width);
		float bottom = smoothstep(height * (1.0 - BOTTOM_WHITE_SHARE), height, v);
		float entrained = mix(0.06, 0.5, narrow) + smoothstep(0.0, 2.5, v) * mix(0.12, 0.25, narrow);
		float aeration = clamp(max(lip, bottom * 0.85) + entrained + streak * streak_strength * foam_gain, 0.0, 1.0);
		// Two values, not a gradient: the glass and the white, a soft edge between.
		float white = mix(aeration, smoothstep(0.38, 0.55, aeration), 0.6);
		vec3 tint = mix(glass, p_lit, 0.35 * streak);
		ALBEDO = mix(tint, p_foam, white);
		float alpha = mix(GLASS_ALPHA * (0.75 + 0.25 * streak), 0.96, white);
		alpha = max(alpha, max(lip, narrow * 0.85));
		// Torn side edges: a broad ragged bite, deeper toward the pool.
		float rag_e = be_n2(vec2(u * 1.5 + 7.3, (t_fall - t_now) * 5.0));
		rag_e = smoothstep(0.3, 0.7, rag_e);
		float bite = mix(EDGE_BITE, NARROW_EDGE_BITE, narrow);
		float taper = mix(BOTTOM_TAPER, NARROW_BOTTOM_TAPER, narrow)
			* smoothstep(height * (1.0 - BOTTOM_TAPER_SHARE), height, v);
		float edge_mask = smoothstep(0.0, EDGE_SOFT, edge - bite * rag_e - taper);
		float tear = be_n2(vec2(u * 1.5 + 2.0, floor(TIME * 0.6)));
		float tear_level = pool - BOTTOM_SINK_M + BOTTOM_TEAR_M * tear;
		float pool_fade = smoothstep(tear_level, tear_level + BOTTOM_FADE_M, world_pos.y);
		ALPHA = clamp(alpha, 0.0, 1.0) * edge_mask * pool_fade;
	}
}
