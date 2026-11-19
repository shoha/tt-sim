shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

/*
 * Painted lantern halo (card painter-village-polish)
 * ==================================================
 *
 * The halo round a lantern (StructureGlow: a camera-facing quad from four vertices at the pane's
 * centre, UV the corner, UV2.x its half-size in metres) as a painter lays a lamp's glow: three
 * soft-edged shapes, a wide amber wash, a warmer middle and a small pale core, each a step with a
 * brush-torn outline (the radius wanders with the angle), not Classic's one smooth falling disc.
 * Blended over the scene so it still reads in daylight, no fragment cut away. The colours run a
 * little past 1 so the environment's glow lifts the core. Steady.
 *
 * MANAGED BY: PainterVillage (painter/painter_village.gd).
 */

uniform vec3 wash_colour : source_color = vec3(1.0, 0.58, 0.2);
uniform vec3 mid_colour : source_color = vec3(1.0, 0.72, 0.28);
uniform vec3 core_colour : source_color = vec3(1.0, 0.92, 0.6);
// The three shapes' opacity, outermost first (toned down a little, card painter-roof-snow: owner
// "tone it down a little, but the approach is nice").
uniform vec3 alphas = vec3(0.15, 0.34, 0.88);
// How far the wash reaches, as a share of the quad's half-size.
uniform float reach : hint_range(0.5, 1.0) = 0.84;
// Where the middle and the core end, as a share of the quad's half-size.
uniform float mid_radius : hint_range(0.1, 0.9) = 0.5;
uniform float core_radius : hint_range(0.05, 0.6) = 0.22;
// How far the outline wanders (a share of its radius) and how soft each step's edge is.
uniform float wander = 0.14;
uniform float soft = 0.1;
// The disc's push toward the camera as a share of its half-size, and the colour's energy.
uniform float lift : hint_range(0.0, 1.0) = 0.5;
uniform float energy : hint_range(0.5, 3.0) = 1.12;

varying vec2 corner;

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 toward = normalize(INV_VIEW_MATRIX[2].xyz);
	float half_size = UV2.x;
	vec3 world = centre + toward * half_size * lift + (right * UV.x + up * UV.y) * half_size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	corner = UV;
}

void fragment() {
	float angle = atan(corner.y, corner.x);
	// A torn outline: two slow waves of the angle, a different one for each shape's edge.
	float w1 = sin(angle * 3.0 + 0.7) * 0.6 + sin(angle * 5.0 + 2.1) * 0.4;
	float w2 = sin(angle * 4.0 + 4.0) * 0.6 + sin(angle * 7.0 + 1.3) * 0.4;
	float d = length(corner);
	float outer_r = (1.0 - wander * 0.5 + wander * 0.5 * w1) * reach;
	float wash = 1.0 - smoothstep(outer_r - soft * 2.0, outer_r, d);
	float mid = 1.0 - smoothstep(mid_radius * (1.0 + wander * w2) - soft, mid_radius * (1.0 + wander * w2), d);
	float core = 1.0 - smoothstep(core_radius * (1.0 + wander * w1 * 0.5) - soft * 0.6, core_radius * (1.0 + wander * w1 * 0.5), d);
	// Each shape lies over the last: its colour and opacity win where it is.
	vec3 col = wash_colour;
	float a = wash * alphas.x;
	col = mix(col, mid_colour, mid);
	a = mix(a, alphas.y, mid);
	col = mix(col, core_colour, core);
	a = mix(a, alphas.z, core);
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
