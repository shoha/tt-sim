shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

/*
 * Selection Glow Shader
 * =====================
 * 
 * PURPOSE:
 * Renders a soft radial glow effect behind selected/hovered board tokens.
 * Provides visual feedback to differentiate the focused token from nearby tokens.
 * 
 * ARCHITECTURE:
 * This shader is applied to a horizontal QuadMesh positioned at the token's base.
 * The glow is managed by SelectionGlowRenderer (scenes/board_token/selection_glow_renderer.gd)
 * which is created by BoardTokenFactory and attached to each token's RigidBody3D.
 * 
 * USAGE:
 * The glow visibility is controlled via BoardToken.set_highlighted(bool):
 *   token.set_highlighted(true)   # Show glow
 *   token.set_highlighted(false)  # Hide glow
 * 
 * Currently triggered by hover in BoardTokenController._on_mouse_entered/exited.
 * Can also be used for selection, targeting, or other highlight states.
 * 
 * CUSTOMIZATION:
 * - Glow color can be changed via BoardToken.set_highlight_color(Color)
 * - Pulse speed/amount can be adjusted for different visual effects
 * - Falloff controls how sharp vs soft the glow edge appears
 * 
 * TRANSPARENCY NOTE:
 * Uses alpha transparency for smooth edges. The SubViewport-based lo-fi effect
 * (lofi_canvas.gdshader) captures everything including transparent objects,
 * so this renders correctly with the lo-fi aesthetic applied.
 */

// Glow color with alpha for intensity control
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.2, 0.8);
// Falloff controls how quickly the glow fades (higher = tighter glow)
uniform float falloff : hint_range(0.5, 5.0) = 2.0;
// Pulse animation speed (0 to disable)
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
// Pulse intensity variation (0 to 1)
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.3;
// Emission energy multiplier for brightness
uniform float emission_energy : hint_range(0.0, 5.0) = 2.0;

void fragment() {
	// Calculate distance from center (UV origin is at center for quad)
	vec2 centered_uv = UV * 2.0 - 1.0;
	float dist = length(centered_uv);
	
	// Create smooth radial gradient falloff
	float glow = 1.0 - smoothstep(0.0, 1.0, pow(dist, falloff));
	
	// Add subtle pulse animation
	float pulse = 1.0;
	if (pulse_speed > 0.0) {
		pulse = 1.0 - pulse_amount + pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed));
	}
	
	float intensity = glow * pulse;
	
	// Use emission for brightness, alpha for smooth edges
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * emission_energy * intensity;
	ALPHA = intensity * glow_color.a;
}
