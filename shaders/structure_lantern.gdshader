// A lantern's glass (a street lamp, a wayside shrine's light): procgen's `glass` part of a prop, a warm
// box painted in vertex colour (ProcgenPropsStreet.LIGHT). Unshaded and pushed past white so the
// environment's glow (EnvironmentGlow, a threshold a little over 1) lifts a soft halo round it, with a
// deeper amber toward the edges and a bright core toward the middle of each face. Steady: tt-sim has
// no day and night cycle to dim it by day or brighten it at dusk (owner, 2026-10-31: a steady warm
// emissive). The numbers are in linear light (ALBEDO is read as linear and the vertex colour is sRGB).
shader_type spatial;
render_mode unshaded, cull_disabled;

// The amber the paint is pulled toward, and how far.
uniform vec3 amber = vec3(1.0, 0.42, 0.08);
uniform float amber_share : hint_range(0.0, 1.0) = 0.5;
// The light's strength: just above 1 so the glow takes it and the tone map keeps it orange, not
// white.
uniform float energy : hint_range(0.5, 4.0) = 1.35;
// How much deeper (towards amber, darker) the glass is at a grazing angle.
uniform float edge_fall : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	vec3 base = mix(col, amber, amber_share);
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float core = mix(1.0 - edge_fall, 1.0, smoothstep(0.1, 0.9, facing));
	ALBEDO = base * energy * core;
}
