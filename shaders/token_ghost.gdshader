shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled;

/*
 * Token ghost (TokenGhost, Settings > Graphics > Token ghost)
 * ===========================================================
 *
 * A material_overlay on every mesh of a token: the token's own geometry drawn a second time
 * with the depth test off, kept only where something stands between the camera and the
 * fragment, so a token behind foliage, a trunk, a rock or a wall shows as a tinted
 * silhouette through it and a token in the open shows nothing extra.
 *
 * The occlusion test reads the depth buffer (hint_depth_texture) and compares it with the
 * fragment's own view depth. Opaque foliage writes depth, a cutout card's discarded
 * fragments do not, so the ghost appears only behind the pixels a card really covers.
 *
 * The token's own parts write depth too (an arm over the torso, a large creature's body over
 * its far legs), and the depth buffer cannot say whose they are. So the token carries a
 * bounding cylinder (`bound_center`, `bound_extent`, set by TokenGhost in the mesh's own
 * space and carried to the world by MODEL_MATRIX, so it follows the token's move, turn and
 * scale) and the fragment measures how far its view ray runs inside it on the way to the
 * camera: everything of the token that can lie in front of this fragment lies in that
 * stretch. Only a surface nearer than that stretch, plus a small margin (`bound_gap`), is
 * somebody else's and counts as an occluder. Without a bound (`bound_extent` 0) the stretch
 * is 0 and the margin is `min_gap`, as before.
 *
 * Colour: a figure part reads its palette column at the base of the gradient (use_palette,
 * the avatar figure shader's own palette texture), a pack token its albedo; both are
 * lifted toward `ghost_tint` and rimmed in `rim_color` so the shape reads on dark leaves.
 * No lighting: the figure's painted colours stay their own, the lo-fi pass grades them
 * with the rest of the frame.
 *
 * Opacity: `ghost_alpha` is the fill where the token is covered, `rim_alpha` how much the
 * silhouette's edge adds on top of it, so the ink line stays solid while the body is a
 * little see-through. TokenGhost.FILL_ALPHA and RIM_ALPHA are these defaults.
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
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.54;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.9;
// How far down the palette gradient (toward its shadow end) the ghost reads, 0 the highlight.
uniform float palette_depth : hint_range(0.0, 0.8) = 0.45;
uniform float rim_power : hint_range(0.5, 6.0) = 1.3;
// Metres of depth between the fragment and what is in front of it before it counts as hidden.
uniform float min_gap : hint_range(0.0, 2.0) = 0.5;
// Fade from nothing at min_gap to full over this many more metres, so a twig brushing the
// figure gives a faint ghost and a crown a clear one.
// With the token's bounds known the stretch above already covers its own parts, so only this
// small margin (depth precision, a part grazing the fragment) is added to it instead of
// `min_gap`; a token without bounds keeps `min_gap`.
uniform float bound_gap : hint_range(0.0, 2.0) = 0.15;
uniform float gap_ramp : hint_range(0.01, 4.0) = 0.5;

// The token's bounding cylinder in this mesh's local space: its centre, its radius and half
// height in the token body's own metres (x, y; 0 = none), and the body's up axis in this
// mesh's local space (its length through MODEL_MATRIX is the body's world scale).
uniform vec3 bound_center = vec3(0.0);
uniform vec2 bound_extent = vec2(0.0);
uniform vec3 bound_up = vec3(0.0, 1.0, 0.0);

// How far a ray from `p` (relative to the cylinder's centre) along unit `d` runs inside a
// vertical cylinder of radius `r` and half height `h` before it leaves it (0 when `p` is
// outside or the cylinder is empty).
float chord_out(vec3 p, vec3 d, float r, float h) {
	if (r <= 0.0 || h <= 0.0) {
		return 0.0;
	}
	float a = dot(d.xz, d.xz);
	float t_side = 1e6;
	if (a > 1e-6) {
		float b = dot(p.xz, d.xz);
		float c = dot(p.xz, p.xz) - r * r;
		t_side = (-b + sqrt(max(b * b - a * c, 0.0))) / a;
	}
	float t_cap = 1e6;
	if (abs(d.y) > 1e-6) {
		t_cap = ((d.y > 0.0 ? h : -h) - p.y) / d.y;
	}
	return max(min(t_side, t_cap), 0.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_dist = -(scene.z / scene.w);
	float own_dist = -VERTEX.z;
	// The stretch of this fragment's view ray inside the token's own bounds, as view depth.
	float body_scale = length((MODEL_MATRIX * vec4(bound_up, 0.0)).xyz);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_camera = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 centre = (MODEL_MATRIX * vec4(bound_center, 1.0)).xyz;
	float own_stretch = chord_out(
		world_pos - centre, to_camera, bound_extent.x * body_scale, bound_extent.y * body_scale)
		* abs(VIEW.z);
	float gap_floor = bound_extent.x > 0.0 ? bound_gap : min_gap;
	float hidden = smoothstep(gap_floor, gap_floor + gap_ramp, own_dist - scene_dist - own_stretch);
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
	ALPHA = clamp(ghost_alpha + rim * rim_alpha, 0.0, 1.0) * hidden;
}
