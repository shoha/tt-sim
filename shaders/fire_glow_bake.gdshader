shader_type canvas_item;
// The ground fire's fine noise fields, baked once per map (FireNoiseBake; cards F4b-3 and
// F4b-4): one ColorRect over a 2D SubViewport, each texel glow_fine_fields
// (fire_glow_noise.gdshaderinc) at its centre's map-frame XZ: the tufts', lobes', coal lumps' and
// cracks' noise. fire_glow.gdshaderinc reads it back with one filtered fetch. Written as is (no
// blending), in RGBA8.
render_mode unshaded, blend_disabled;

#include "res://shaders/fire_glow_noise.gdshaderinc"

// The bake's frame: the map-frame XZ of its corner (uv 0) and its size in metres.
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	COLOR = glow_fine_fields(rect.xy + UV * rect.zw);
}
