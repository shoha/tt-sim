shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

/*
 * Submerged token marker
 * ======================
 *
 * Drawn on the water surface above a token the water hides (SubmergedMarker, shown by
 * DraggableToken when WaterSurface.is_submerged()). A horizontal quad centred over the
 * token: a soft shadow disc (something is down there), a bright ring at the token's
 * footprint with a thin dark keyline so it reads on pale shallows and dark depths alike,
 * and a slow ripple spreading from the ring, the water's own language for "a creature
 * below". Ring widths have a floor in screen pixels (fwidth), so the marker stays crisp
 * at full play zoom-out without growing at close zoom. Drawn after the water
 * (render_priority on the material) and without depth writes.
 *
 * `swim` (1 for a swimmer, SubmergedMarker.set_swimmer) is the quiet form: no shadow or
 * keyline, the ring soft-edged and faint in the foam's tint, and two ripples spreading from
 * it half a period apart, so the water stirs round the swimmer instead of ringing its neck.
 */

uniform vec4 ring_color : source_color = vec4(0.93, 0.98, 1.0, 1.0);
uniform vec4 keyline_color : source_color = vec4(0.03, 0.14, 0.2, 1.0);
// The swimmer's ring and ripples: the pale tint of the water's foam.
uniform vec4 swim_color : source_color = vec4(0.8, 0.94, 0.96, 1.0);
// 0..1, faded by SubmergedMarker.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// The ring's radius in world metres (the quad's half size is RING_R of it), for the widths.
uniform float radius_m = 0.5;
// 1 for a swimmer's quiet form, 0 for the bright ring.
uniform float swim : hint_range(0.0, 1.0) = 0.0;

// Where the ring sits, as a share of the quad's half size (the rest is room for the ripple).
const float RING_R = 0.7;
// Ring and keyline half widths in metres, and their floors in pixels.
const float RING_HALF_M = 0.028;
const float RING_HALF_PX = 1.1;
const float KEYLINE_PX = 1.4;
// The shadow disc inside the ring.
const float SHADOW_ALPHA = 0.3;
// The ripple: one ring spreading from the marker to the quad's edge every PERIOD seconds.
const float RIPPLE_PERIOD_S = 2.6;
const float RIPPLE_ALPHA = 0.55;
// The swimmer's form: a soft ring (its edge blurred over SWIM_SOFT_M) at SWIM_RING_ALPHA,
// and its ripples at SWIM_RIPPLE_ALPHA.
const float SWIM_SOFT_M = 0.05;
const float SWIM_RING_ALPHA = 0.34;
const float SWIM_RIPPLE_ALPHA = 0.4;

// 1 inside a band of `half_width` around `radius`, antialiased over `px`.
float band(float r, float radius, float half_width, float px) {
	return 1.0 - smoothstep(half_width, half_width + px, abs(r - radius));
}

// A ripple at phase `t` (0..1) spreading from the ring to the quad's edge, fading as it goes.
float ripple(float r, float t, float half_width, float px) {
	return band(r, mix(RING_R, 0.97, t), half_width, px) * (1.0 - t) * (1.0 - t);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float px = max(fwidth(r), 1e-5);
	// Metres per unit of r: the quad's half size.
	float half_size = radius_m / RING_R;
	float ring_half = max(RING_HALF_M / half_size, RING_HALF_PX * px);
	float soft = mix(px, max(SWIM_SOFT_M / half_size, px), swim);

	float core = band(r, RING_R, ring_half, soft) * mix(1.0, SWIM_RING_ALPHA, swim);
	float keyline = band(r, RING_R, ring_half + KEYLINE_PX * px, px) * 0.55 * (1.0 - swim);
	float shadow = (1.0 - smoothstep(RING_R * 0.35, RING_R, r)) * SHADOW_ALPHA * (1.0 - swim);

	float t = fract(TIME / RIPPLE_PERIOD_S);
	float spread = ripple(r, t, ring_half * 0.6, soft) * mix(RIPPLE_ALPHA, SWIM_RIPPLE_ALPHA, swim);
	// The swimmer's second ripple, half a period behind the first.
	spread = max(spread, ripple(r, fract(t + 0.5), ring_half * 0.6, soft) * SWIM_RIPPLE_ALPHA * swim);

	// Dark first (shadow, keyline), then the bright ring and ripple over it.
	float dark = max(shadow, keyline);
	float light = max(core, spread);
	// The swimmer's form has no dark parts: all of it is the foam's tint.
	vec3 color = mix(mix(keyline_color.rgb, ring_color.rgb, light), swim_color.rgb, swim);
	float alpha = light + dark * (1.0 - light);
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0) * opacity * ring_color.a;
}
