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
 */

uniform vec4 ring_color : source_color = vec4(0.93, 0.98, 1.0, 1.0);
uniform vec4 keyline_color : source_color = vec4(0.03, 0.14, 0.2, 1.0);
// 0..1, faded by SubmergedMarker.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// The ring's radius in world metres (the quad's half size is RING_R of it), for the widths.
uniform float radius_m = 0.5;

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

// 1 inside a band of `half_width` around `radius`, antialiased over `px`.
float band(float r, float radius, float half_width, float px) {
	return 1.0 - smoothstep(half_width, half_width + px, abs(r - radius));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float px = max(fwidth(r), 1e-5);
	// Metres per unit of r: the quad's half size.
	float half_size = radius_m / RING_R;
	float ring_half = max(RING_HALF_M / half_size, RING_HALF_PX * px);

	float core = band(r, RING_R, ring_half, px);
	float keyline = band(r, RING_R, ring_half + KEYLINE_PX * px, px) * 0.55;
	float shadow = (1.0 - smoothstep(RING_R * 0.35, RING_R, r)) * SHADOW_ALPHA;

	float t = fract(TIME / RIPPLE_PERIOD_S);
	float ripple_r = mix(RING_R, 0.97, t);
	float ripple = band(r, ripple_r, ring_half * 0.6, px) * (1.0 - t) * (1.0 - t) * RIPPLE_ALPHA;

	// Dark first (shadow, keyline), then the bright ring and ripple over it.
	float dark = max(shadow, keyline);
	float light = max(core, ripple);
	vec3 color = mix(keyline_color.rgb, ring_color.rgb, light);
	float alpha = light + dark * (1.0 - light);
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0) * opacity * ring_color.a;
}
