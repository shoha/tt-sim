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
 * Unshaded: every colour is the sheet's, so a cliff's shadow cannot grey the white water. A puff
 * rises, grows, sways and fades continuously over its cycle (it stepped until card
 * painter-water-rings: a few large shapes jumping every half second). Quality Low drops the mist.
 *
 * The clock is the water's ONE clock (p_clock, integrated by PainterWater and handed to both
 * materials), not the engine's TIME: a render job that pins the water's clock pins the puffs too.
 * On TIME a frozen capture drew each puff at whichever of two neighbouring steps the run's own
 * milliseconds had reached, so two runs of one job differed in soft pale shapes at every fall
 * (card painter-water-lap).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform float mist_alpha : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
global uniform bool water_quality_skip_fine_detail;

uniform vec3 p_foam = vec3(0.95, 0.98, 0.98);
uniform vec3 p_sky = vec3(0.7, 0.85, 0.95);
// The water's one clock in seconds (PainterWater.clock_t).
uniform float p_clock = 0.0;

// The mist: the rise (m) and the cycle (s) of a puff, its growth, the steps its rise was drawn in
// (ABL_MISTSTEP only), its sway (m, either side), the soft fade against the scene (m), its three
// lobes (spread, growth of spread, radii, rim share).
const float MIST_RISE_M = 0.5;
const float MIST_CYCLE_S = 4.0;
const float MIST_GROW = 1.3;
const float MIST_STEPS = 8.0;
const float MIST_SWAY_M = 0.12;
const float MIST_SOFT_M = 0.25;
const float MIST_LOBE_SPREAD = 0.3;
const float MIST_LOBE_SPREAD_GROW = 0.08;
const vec3 MIST_LOBE_RADII = vec3(0.55, 0.48, 0.42);
const float MIST_LOBE_SOFT = 0.9;
const float MIST_WARP = 0.22;

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
		// Mist: a billboard that rises, grows and sways over its cycle, at the puff's phase, all
		// three continuous. The rise and the growth went in MIST_STEPS steps of the phase (and the
		// sway with them): with three to five puffs a fall, each step moved a whole puff at once,
		// so a fall's mist changed in bulk every half second (card painter-water-rings;
		// ABL_MISTSTEP puts the steps back). The sway is a slow sine of the cycle, a full swing
		// out and back per rise, from the puff's own seed.
		float cycle = fract(p_clock / MIST_CYCLE_S + COLOR.b);
#ifdef ABL_MISTSTEP
		float phase = floor(cycle * MIST_STEPS) / MIST_STEPS;
		float sway = sin(floor((p_clock / MIST_CYCLE_S + COLOR.b) * MIST_STEPS) * 0.5 + COLOR.b * TAU) * 0.12;
#else
		float phase = cycle;
		float sway = sin(cycle * TAU + COLOR.b * TAU) * MIST_SWAY_M;
#endif
		mist_phase = phase;
		vec2 off = UV2 * mix(1.0, MIST_GROW, phase);
		VERTEX.y += phase * MIST_RISE_M;
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
	float cloud = l0 + l1 + l2;
	// A soft cloud with no plateau and no rim: the lobes' falloff reaches their centres (MIST_LOBE_SOFT)
	// and the sum is not capped, so the alpha is a bump that thins into the glass and the veil under it;
	// a capped sum read as a flat translucent disc laid over the face (cards painter-water-foot-spike
	// and painter-water-foot2).
	float body = smoothstep(0.0, 1.6, cloud);
	body *= body;
	float core = smoothstep(0.9, 1.7, cloud);
	float life = sin(mist_phase * PI);
	float soft = smoothstep(
		0.0, MIST_SOFT_M, fall_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z
	);
	ALBEDO = mix(mix(p_foam, p_sky, 0.2), p_foam, core);
	ALPHA = body * mix(0.4, 0.85, core) * life * soft * mist_alpha;
}
