/*
 * Toon probe, approach 3: a screen-space pass. It replaces the lo-fi material on the world
 * SubViewportContainer while the probe mode is SCREEN, reading the rendered 3D image: the
 * luminance goes through a soft stair (bands with soft edges), the colour is scaled to the
 * stair's luminance and tinted toward violet in the dark bands, and a luminance edge detect
 * lays a violet ink line. It touches no token and no material, but it cannot tell a token
 * from the ground, so it restyles the whole board.
 *
 * This is a design probe (tools/render_jobs/probes), not a shipped look.
 */

shader_type canvas_item;

uniform float bands : hint_range(2.0, 8.0) = 4.0;
uniform float soft : hint_range(0.02, 0.5) = 0.22;
uniform vec3 shadow_tint : source_color = vec3(0.78, 0.70, 1.0);
uniform vec3 ink_color : source_color = vec3(0.16, 0.10, 0.26);
uniform float edge_px : hint_range(0.5, 4.0) = 1.2;
uniform float edge_lo : hint_range(0.0, 0.5) = 0.14;
uniform float edge_hi : hint_range(0.0, 0.8) = 0.34;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.8;
uniform float saturation : hint_range(0.5, 1.8) = 1.15;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * edge_px;
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = luma(c);
	float x = l * bands;
	// The soft stair, never darker than a floor so shade stays coloured paint, not black.
	float stair = (floor(x) + smoothstep(0.5 - soft, 0.5 + soft, fract(x))) / bands;
	stair = max(stair, 0.2);
	vec3 col = mix(vec3(l), c, saturation) * (stair / max(l, 0.03));
	col *= mix(shadow_tint, vec3(1.0), smoothstep(0.15, 0.7, stair));
	float lr = luma(texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb);
	float ll = luma(texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb);
	float lu = luma(texture(TEXTURE, UV + vec2(0.0, px.y)).rgb);
	float ld = luma(texture(TEXTURE, UV - vec2(0.0, px.y)).rgb);
	float e = length(vec2(lr - ll, lu - ld));
	col = mix(col, ink_color, smoothstep(edge_lo, edge_hi, e) * edge_strength);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
