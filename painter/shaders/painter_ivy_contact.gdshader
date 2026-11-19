shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_never, fog_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted ivy's contact shade (the decor wall leaves' second pass under the Painted look)
 * ======================================================================================
 *
 * Card painter-walls-round3 (owner on the ivy, 2026-11-19: "any kind of AO or similar we could add
 * or fake to make them feel more grounded on the building?"). The baked ivy's leaf cards drawn a
 * second time, multiplied over what lies behind them: where a card is clear (between its leaves
 * and round them) the wall, or a leaf deeper in the mass, darkens by one soft round blot per card,
 * let a little down the card. A clump's many cards add up, so the wall takes a soft cool shade
 * just under and round each clump and the clumps' inner leaves sit in it: the ivy reads attached,
 * not pasted on (r2 read each leaf's own shape shifted down: dark leaf outlines, fussy). The
 * card's own leaves are cut out of this pass (they draw themselves in front), so no leaf darkens
 * itself.
 *
 * The wind's sway is the plant's own (wind_foliage_include), so the shade moves with its leaves.
 * It draws no shadow and writes no depth. Cost: one more pass over the decor's leaf cards, one
 * texture read a fragment (its own cutout) and a 2x2 solve from the screen derivatives.
 *
 * MANAGED BY: PainterIvyContact (painter/painter_ivy_contact.gd), hung on each decor stand-in's
 * next_pass by PainterVillage.
 */

#include "res://shaders/wind_foliage_include.gdshaderinc"

// The shade's colour as a multiplier (a cool dark, so the shade under the leaves leans blue as the
// painted shade does) and how much of it the densest shape takes.
uniform vec3 contact_tint = vec3(0.42, 0.45, 0.56);
uniform float contact_strength = 0.45;
// How far down its card a blot's middle is let (metres: the shade falls under its leaves), and the
// radius (of a card's UV) inside which a blot is at full strength before it fades.
uniform float contact_drop = 0.04;
uniform float contact_blur = 0.12;

// The most a blot's middle moves off its card's middle (of the card's UV), so it fades before the
// card's edge.
const float CONTACT_SHIFT = 0.1;

varying vec3 v_wp;

void vertex() {
	local_vertex_y = VERTEX.y;
	if (IN_SHADOW_PASS) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	}
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The card's UV step for a metre down the wall: the world and UV steps of a screen pixel, the
	// world step down solved in the pixel's two directions (least squares), carried to UV.
	vec3 px = dFdx(v_wp);
	vec3 py = dFdy(v_wp);
	vec2 ux = dFdx(UV);
	vec2 uy = dFdy(UV);
	float a = dot(px, px);
	float b = dot(px, py);
	float c = dot(py, py);
	float det = a * c - b * b;
	vec2 s = det > 1e-12 ? vec2(c * -px.y - b * -py.y, a * -py.y - b * -px.y) / det : vec2(0.0);
	vec2 uv_down = ux * s.x + uy * s.y;
	float own = texture(albedo_texture, UV).a;
	if (own >= alpha_scissor_threshold) {
		discard;
	}
	// One soft round blot per card, its middle let down the card (at most CONTACT_SHIFT of it) and
	// gone before the card's edge, so a clump's many cards add up to a soft shade that is deepest
	// in and under the clump and fades out round it, with no card's edge in it.
	vec2 shift = uv_down * contact_drop;
	float sl = length(shift);
	shift *= sl > CONTACT_SHIFT ? CONTACT_SHIFT / sl : 1.0;
	float d = length(UV - vec2(0.5) - shift);
	float shade = (1.0 - smoothstep(contact_blur, 0.5 - CONTACT_SHIFT, d)) * contact_strength;
	if (shade < 0.01) {
		discard;
	}
	ALBEDO = mix(vec3(1.0), contact_tint, shade);
}
