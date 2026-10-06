// Avatar token probe: the inverted-hull outline pass (next_pass of avatar_toon).
// Back faces pushed out along the smoothed outline normal, which the mesh carries in
// TANGENT (Godot skins TANGENT with the skeleton, not CUSTOM channels), by a width in
// screen pixels scaled per vertex by COLOR.r (Guilty Gear Xrd keeps outline width in a
// vertex colour channel). The push is done in view space, flattened onto the screen
// plane, with the pixel size taken from the orthographic projection, so the width holds
// across zoom and does not depend on the node's or the bones' scale. Tinted a darker,
// more saturated shade of the local palette colour's shadow row.
shader_type spatial;
render_mode unshaded, cull_front, skip_vertex_transform, shadows_disabled;

uniform sampler2D palette : source_color, filter_nearest;
uniform float palette_rows = 4.0;
instance uniform float palette_row = 0.0;
uniform float outline_px = 1.5;
uniform float width_scale = 1.0;
uniform float outline_darken = 0.6;
uniform float outline_sat = 1.3;
uniform vec3 outline_tint : source_color = vec3(0.85, 0.75, 1.0);
// Metres the hull is pushed away from the camera, so it never pokes through the body.
uniform float depth_push = 0.01;
// 1: expand along TANGENT (the smoothed normal); 0: along the flat NORMAL, for an A/B of
// the cracks flat normals open at the chamfers.
uniform float use_smooth = 1.0;


void vertex() {
	vec3 dir = normalize(mix(NORMAL, TANGENT, use_smooth));
	vec4 vpos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 sdir = (mat3(MODELVIEW_MATRIX) * dir).xy;
	float len = length(sdir);
	sdir = len > 1e-5 ? sdir / len : vec2(0.0);
	// Orthographic: |PROJECTION_MATRIX[1][1]| = 2 / view height in metres. The abs matters:
	// under Vulkan Godot's projection flips Y, so [1][1] is negative and a signed width
	// pushes the hull inward, where the body hides it (the probe's first outline drew
	// nothing at any width until this was found).
	float metres_per_px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	vpos.xy += sdir * outline_px * width_scale * COLOR.r * metres_per_px;
	vpos.z -= depth_push * step(0.001, COLOR.r);
	VERTEX = vpos.xyz;
	NORMAL = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
}


void fragment() {
	vec2 uv = vec2(UV.x, (2.0 * palette_row + 1.5) / (2.0 * palette_rows));
	vec3 c = texture(palette, uv).rgb * outline_darken * outline_tint;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = max(mix(vec3(luma), c, outline_sat), vec3(0.0));
}
