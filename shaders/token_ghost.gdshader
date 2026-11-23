shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_mix, shadows_disabled;

/*
 * Token ghost (TokenGhost, Settings > Graphics > Token ghost)
 * ===========================================================
 *
 * A material_overlay on every mesh of a token that draws ONE line around the outer silhouette
 * of the token's covered part: where a token stands behind foliage, a trunk, a rock or a wall
 * its outline shows through, and a token in the open shows nothing extra. Nothing inside the
 * body is drawn (no fill, no part edges, no fold contours).
 *
 * How the union silhouette comes out of per-mesh draws (painter-look-ghost2, 2026-11-15):
 * two passes, drawn in this order by render priority.
 *   1. the mask pass (token_ghost_mark.gdshader, the overlay's next_pass, priority below this
 *      one) writes the nearest depth on every pixel the token's meshes cover;
 *   2. this pass draws every mesh again, its vertices pushed out along their normals by the
 *      line's width in screen pixels (`line_px` + `inner_px`, of a 1080-line view, scaled by the
 *      viewport's height), and writes a depth just short of the nearest. The depth test fails on
 *      every marked pixel, so only the ring outside the union of all the meshes is left, a line
 *      of constant pixel width round the whole token, with no line where one part lies over
 *      another. The whole ring is the line. When `inner_px` is above 0 its outer `line_px` is
 *      the dark stroke and the rest the light one (the distance to the pushed surface's contour
 *      from f / (df/dpixel) of f = |N . V|, which is 2 d near a smooth surface's contour
 *      whatever its curvature, only splits the colours).
 * No stencil buffer is needed (spatial shaders here take none) and the line is where the depth
 * buffer says something else is in front, below.
 *
 * The occlusion test reads the depth buffer (hint_depth_texture, copied before the transparent
 * passes, so the mask pass's writes do not reach it) and compares it with the fragment's own
 * view depth. Opaque foliage writes depth, a cutout card's discarded fragments do not, so the
 * line appears only behind the pixels a card really covers.
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
 * The line's colour comes from the token (`line_colour`, `line_inner`: TokenGhost derives them
 * from the token's most vivid palette colour, gold while it is selected or hovered).
 * `wobble_px` moves the band's width with low-frequency noise on the token's world-space
 * offset from its origin, a hand-drawn line instead of a ruled one.
 */

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// The stroke: its colour (the outer stroke of a double one), the light colour of the inner stroke,
// and their widths in pixels of a 1080-line view.
uniform vec4 line_colour : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 line_inner : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float line_px : hint_range(0.0, 8.0) = 2.0;
uniform float inner_px : hint_range(0.0, 8.0) = 0.0;
uniform float line_alpha : hint_range(0.0, 1.0) = 0.95;
// How far the stroke's width wanders, in pixels, and how fast (cycles per metre).
uniform float wobble_px : hint_range(0.0, 2.0) = 0.0;
uniform float wobble_freq : hint_range(0.5, 20.0) = 6.0;
// Metres of depth between the fragment and what is in front of it before it counts as hidden.
uniform float min_gap : hint_range(0.0, 2.0) = 0.5;
// Fade from nothing at min_gap to full over this many more metres, so a twig brushing the
// figure gives a faint line and a crown a clear one.
// With the token's bounds known the stretch above already covers its own parts, so only this
// small margin (depth precision, a part grazing the fragment) is added to it instead of
// `min_gap`; a token without bounds keeps `min_gap`.
uniform float bound_gap : hint_range(0.0, 2.0) = 0.15;
uniform float gap_ramp : hint_range(0.01, 4.0) = 0.5;
// The ground the token stands on is not cover (ghost-feet, 2026-11-23). A token on a slope sinks
// its uphill or camera-side feet and belly into the hillside, and the hillside in front (and the
// grass on it) lies outside the bounding cylinder, so it read as cover and outlined the buried
// parts. TokenGhost fits the ground round the token as a plane (`ground_plane`, world metres:
// y = x * a + z * b + c, w 1; w 0 = unknown, then the cylinder's floor stands in, level). A cover
// point (the depth buffer's surface in front of the fragment) less than `ground_band` times the
// body's height above that plane counts as the ground; above it the cover counts in full, faded
// in over the band's top `ground_fade` part. A crown, or a wall's face higher than the band, still
// ghosts; a cover lower than the band (grass round a large token, a pebble before a small one)
// does not. And the token's own feet never ghost: a fragment less than `feet_band` times the
// height above that ground draws no line (the grass of a meadow, up to about 0.7 m, hides the
// lowest contour of a large token whatever the cover band). 0 = off, as before.
uniform float ground_band : hint_range(0.0, 1.0) = 0.45;
uniform float feet_band : hint_range(0.0, 1.0) = 0.25;
uniform float ground_fade : hint_range(0.01, 1.0) = 0.5;
uniform vec4 ground_plane = vec4(0.0);

// The eye view's range fade (EyeCanopy.ghost_weight): w the map scale, 0 when the view is not
// the eye's (CanopyFade publishes it with the eye position). A ghost further than
// GHOST_START metres (times the scale) from the eye fades out, gone by GHOST_END, so a far
// token does not draw through everything at 100 m. Only a perspective camera reads it; the
// orbit camera sits far back on its view axis and its ghosts keep their full strength.
global uniform vec4 canopy_eye;
const float GHOST_START = 30.0;
const float GHOST_END = 50.0;

// The token's bounding cylinder in this mesh's local space: its centre, its radius and half
// height in the token body's own metres (x, y; 0 = none), and the body's up axis in this
// mesh's local space (its length through MODEL_MATRIX is the body's world scale).
uniform vec3 bound_center = vec3(0.0);
uniform vec2 bound_extent = vec2(0.0);
uniform vec3 bound_up = vec3(0.0, 1.0, 0.0);

// The fragment's offset from the token's origin in world axes, the wobble's anchor.
varying vec3 anchor;

void vertex() {
	anchor = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
	// Push the vertex out along its normal by the whole line's width, in screen pixels.
	float scale = max(VIEWPORT_SIZE.y / 1080.0, 0.25);
	float width = (line_px + inner_px + wobble_px) * scale;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (dot(dir, dir) > 1e-8) {
		clip.xy += normalize(dir) * (2.0 * width / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Value noise in 0..1, smooth, one cycle about every 1/freq metres.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

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
	vec3 up_world = (MODEL_MATRIX * vec4(bound_up, 0.0)).xyz;
	float body_scale = length(up_world);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 to_camera = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 centre = (MODEL_MATRIX * vec4(bound_center, 1.0)).xyz;
	float half_height = bound_extent.y * body_scale;
	float own_stretch = chord_out(
		world_pos - centre, to_camera, bound_extent.x * body_scale, half_height)
		* abs(VIEW.z);
	float gap_floor = bound_extent.x > 0.0 ? bound_gap : min_gap;
	float hidden = smoothstep(gap_floor, gap_floor + gap_ramp, own_dist - scene_dist - own_stretch);
	if (bound_extent.x > 0.0 && hidden > 0.01) {
		// The cover point's and the fragment's heights above the ground under each, against the
		// ground and feet bands (the cylinder's floor, level, when the ground is unknown).
		vec3 cover = (INV_VIEW_MATRIX * vec4(scene.xyz / scene.w, 1.0)).xyz;
		float floor_y = centre.y - (up_world.y / max(body_scale, 1e-6)) * half_height;
		bool known = ground_plane.w > 0.5;
		float cover_ground = known ? dot(vec3(cover.x, cover.z, 1.0), ground_plane.xyz) : floor_y;
		float own_ground =
			known ? dot(vec3(world_pos.x, world_pos.z, 1.0), ground_plane.xyz) : floor_y;
		float height = 2.0 * half_height;
		if (ground_band > 0.0) {
			float band = ground_band * height;
			hidden *= smoothstep(band * (1.0 - ground_fade), band, cover.y - cover_ground);
		}
		if (feet_band > 0.0) {
			float band = feet_band * height;
			hidden *= smoothstep(band * (1.0 - ground_fade), band, world_pos.y - own_ground);
		}
	}
	if (canopy_eye.w > 0.0 && PROJECTION_MATRIX[3][3] < 0.5) {
		hidden *= 1.0 - smoothstep(GHOST_START * canopy_eye.w, GHOST_END * canopy_eye.w, length(VERTEX));
	}
	if (hidden <= 0.01) {
		discard;
	}

	// The distance to the pushed-out surface's contour, in pixels of a 1080-line view (see the
	// header); a flat-shaded facet has no gradient and counts as on the contour.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float gradient = length(vec2(dFdx(facing), dFdy(facing)));
	float scale = max(VIEWPORT_SIZE.y / 1080.0, 0.25);
	float d = gradient < 1e-4 ? 0.0 : 0.5 * facing / gradient / scale;
	d += (vnoise(anchor * wobble_freq) - 0.5) * 2.0 * wobble_px;
	// The ring's width is the push-out itself (the mask pass removes everything inside the
	// token's silhouette), so it is kept whole: the distance estimate only splits its colours,
	// since where it is off (a flat-shaded or folded surface) a cut band came out dashed.
	float aa = 0.6;
	if (wobble_px > 0.0 && d > line_px + inner_px) {
		discard; // only the hand-drawn variant trims its band by the estimate
	}
	float in_outer = 1.0 - smoothstep(line_px - aa, line_px + aa, d);
	vec3 stroke = inner_px > 0.0 ? mix(line_inner.rgb, line_colour.rgb, in_outer) : line_colour.rgb;
	ALBEDO = stroke;
	ALPHA = line_alpha * hidden;
	// Just short of the nearest depth: fails where the mask pass wrote the nearest.
	DEPTH = 0.9999;
}
