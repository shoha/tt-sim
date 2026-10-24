shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled;

/*
 * Token ghost (prototype, topic tokenvis; TokenVisibility, off by default)
 * ========================================================================
 *
 * A material_overlay on every mesh of a token: the token's own geometry drawn a second time
 * with the depth test off, kept only where something stands between the camera and the
 * fragment, so a token behind foliage, a trunk, a rock or a wall shows as a tinted
 * silhouette through it and a token in the open shows nothing extra.
 *
 * The occlusion test reads the depth buffer (hint_depth_texture) and compares it with the
 * fragment's own view depth. Opaque foliage writes depth, a cutout card's discarded
 * fragments do not, so the ghost appears only behind the pixels a card really covers. The
 * token's own parts write depth too (an arm over the torso), so the gap must exceed
 * `min_gap` metres before it counts as an occluder.
 *
 * Colour: a figure part reads its palette column at the base of the gradient (use_palette,
 * the avatar figure shader's own palette texture), a pack token its albedo; both are
 * lifted toward `ghost_tint` and rimmed in `rim_color` so the shape reads on dark leaves.
 * No lighting: the figure's painted colours stay their own, the lo-fi pass grades them
 * with the rest of the frame.
 */

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D palette : source_color, hint_default_white, filter_linear, repeat_disable;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool use_palette = false;
uniform bool use_albedo = false;
uniform vec4 ghost_tint : source_color = vec4(0.9, 0.88, 0.8, 1.0);
// The rim is an ink line (a dark navy), not a glow: it reads on pale crowns and dark ones
// alike, and keeps the part's own colours from washing out toward white.
uniform vec4 rim_color : source_color = vec4(0.04, 0.06, 0.14, 1.0);
// How much of the part's own colour survives (1) against the flat tint (0).
uniform float own_colour : hint_range(0.0, 1.0) = 1.0;
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.9;
// How far down the palette gradient (toward its shadow end) the ghost reads, 0 the highlight.
uniform float palette_depth : hint_range(0.0, 0.8) = 0.45;
uniform float rim_power : hint_range(0.5, 6.0) = 1.3;
// Metres of depth between the fragment and what is in front of it before it counts as hidden.
uniform float min_gap : hint_range(0.0, 2.0) = 0.5;
// Fade from nothing at min_gap to full over this many more metres, so a twig brushing the
// figure gives a faint ghost and a crown a clear one.
uniform float gap_ramp : hint_range(0.01, 4.0) = 0.5;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = -(scene.z / scene.w);
	float own_dist = -VERTEX.z;
	float hidden = smoothstep(min_gap, min_gap + gap_ramp, own_dist - scene_dist);
	if (hidden <= 0.01) {
		discard;
	}
	vec3 base = ghost_tint.rgb;
	if (use_palette) {
		vec2 puv = vec2((floor(UV.x * 8.0) + 0.5) / 8.0, clamp(UV.y + palette_depth, 0.0, 0.98));
		base = mix(base, texture(palette, puv).rgb, own_colour);
	} else if (use_albedo) {
		base = mix(base, texture(albedo_tex, UV).rgb * albedo_col.rgb, own_colour);
	}
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power) * rim_strength;
	ALBEDO = mix(base, rim_color.rgb, rim);
	ALPHA = clamp(ghost_alpha + rim * 0.4, 0.0, 1.0) * hidden;
}
