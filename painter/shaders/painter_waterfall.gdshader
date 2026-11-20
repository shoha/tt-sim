shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

/*
 * Painted waterfall mist (the AuthoredWater-falls mesh under the Painted look)
 * ==========================================================================
 *
 * A few broad soft mist shapes over a plunge. Nothing else of a fall is drawn here since card
 * painter-water-field-painted: the curtain, the foam ring and the white over the brink and the
 * foot are the ONE water surface's (WaterFieldMesh under painter_water.gdshader), so the curtain
 * and the ring of WaterFallMesh collapse to a point in vertex(). The vertex contract is
 * waterfall.gdshader's (WaterFallMesh): COLOR.g 0 curtain, 0.5 ring, 1 mist; a mist puff's four
 * vertices sit at its centre with UV2 the corner's offset in metres and COLOR.b its seed.
 *
 * Unshaded: every colour is the sheet's, so a cliff's shadow cannot grey the white water. The mist
 * steps in time, a few steps a second: nothing slides. Quality Low drops the mist.
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform float mist_alpha : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
global uniform bool water_quality_skip_fine_detail;

uniform vec3 p_foam = vec3(0.95, 0.98, 0.98);
uniform vec3 p_sky = vec3(0.7, 0.85, 0.95);

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

varying float seed;
varying vec2 uv;
varying float mist_phase;


float fall_scene_depth(vec2 screen_uv, mat4 inv_projection) {
	float depth_raw = texture(depth_tex, screen_uv).r;
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, depth_raw, 1.0);
	return -(view.z / view.w);
}


void vertex() {
	seed = COLOR.b;
	uv = UV;
	mist_phase = 0.0;
	if (COLOR.g < 0.75) {
		// The curtain and the ring: the field surface draws the water, the pool's own white the foam.
		VERTEX = vec3(0.0);
	} else {
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
}


void fragment() {
	if (water_quality_skip_fine_detail) {
		discard;
	}
	// Three broad round lobes, a firm soft rim, the core white, the rim sky.
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
	// A soft cloud with no rim: a firm edge read as a translucent disc laid over the face's glass
	// (card painter-water-foot-spike).
	float body = smoothstep(0.02, 0.95, cloud);
	body *= body;
	float core = smoothstep(0.7, 0.95, cloud);
	float life = sin(mist_phase * PI);
	float soft = smoothstep(
		0.0, MIST_SOFT_M, fall_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z
	);
	ALBEDO = mix(mix(p_foam, p_sky, 0.55), p_foam, core);
	ALPHA = body * mix(0.7, 1.0, core) * life * soft * mist_alpha;
}
