// The painted look's sky (docs/systems/painter.md). PainterScene sets every colour from the
// level's mood at the sun's elevation: a soft gradient from the horizon tone to the zenith, a
// broad warm glow toward the sun (the level's sun, LIGHT0), and below the horizon the far ground
// in haze, which is what the table view's narrow sky FOV shows past the board. Few bold, soft
// shapes, no noise: the sheet's colours reach the screen as written (linear tonemap).
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.62, 0.78, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.88, 0.93, 0.95);
uniform vec3 foot_color : source_color = vec3(0.66, 0.74, 0.55);
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.88);
// How much of the sun's colour the sky gathers around it (0 none).
uniform float glow_amount : hint_range(0.0, 1.0) = 0.35;
// Below 1 the zenith colour reaches lower (a deeper sky).
uniform float sky_curve : hint_range(0.1, 2.0) = 0.6;
// The width of the soft band where the sky meets the far ground (EYEDIR.y).
uniform float foot_blend : hint_range(0.001, 0.5) = 0.08;

void sky() {
	float y = EYEDIR.y;
	vec3 color = mix(horizon_color, zenith_color, pow(clamp(y, 0.0, 1.0), sky_curve));
	float below = smoothstep(0.0, -foot_blend, y);
	if (LIGHT0_ENABLED) {
		float toward = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float glow = (pow(toward, 4.0) * 0.6 + pow(toward, 24.0) * 0.4) * glow_amount;
		color = mix(color, glow_color, clamp(glow, 0.0, 1.0));
	}
	COLOR = mix(color, foot_color, below);
}
