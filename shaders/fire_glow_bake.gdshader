shader_type canvas_item;
// The ground fire's broad noise fields, baked once per map (FireNoiseBake; card F4b-3): one
// ColorRect over a 2D SubViewport twice as wide as it is tall in texels, the left half
// glow_fields_a and the right half glow_fields_b (fire_glow_noise.gdshaderinc), each texel the
// fields at its centre's map-frame XZ. fire_glow.gdshaderinc reads them back with filtered
// fetches. Written as is (no blending), in RGBA8.
render_mode unshaded, blend_disabled;

#include "res://shaders/fire_glow_noise.gdshaderinc"

// One half's frame: the map-frame XZ of its corner (uv 0) and its size in metres.
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	float across = UV.x * 2.0;
	bool second = across >= 1.0;
	vec2 at = rect.xy + vec2(second ? across - 1.0 : across, UV.y) * rect.zw;
	COLOR = second ? glow_fields_b(at) : glow_fields_a(at);
}
