shader_type canvas_item;

// The stop-play scrim (docs/UI_TASTE.md C4): a soft blur of whatever is behind the sheet
// with the plum scrim tint laid over it, so the table or the sky stays luminous and only
// steps back. Scrim (scenes/ui/primitives/scrim.gd) sets `tint` from ThemeColors.SCRIM.
//
// The blur averages nine taps at mip 2 on a ring: the theme probe found one read at mip 3
// showed a faint 8 px block grid, which the ring of LOD 2 taps removes. The node's
// modulate alpha (the sheet's fade in and out) is kept, so the scrim fades with its sheet.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.169, 0.129, 0.251, 0.30);
uniform float blur_lod = 2.0;
uniform float radius_px = 10.0;

void fragment() {
	vec3 sum = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	for (int k = 0; k < 8; k++) {
		float angle = float(k) * 0.785398 + 0.39;
		vec2 offset = vec2(cos(angle), sin(angle)) * radius_px * SCREEN_PIXEL_SIZE;
		sum += textureLod(screen_tex, SCREEN_UV + offset, blur_lod).rgb;
	}
	COLOR = vec4(mix(sum / 9.0, tint.rgb, tint.a), COLOR.a);
}
