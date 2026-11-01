/*
 * Toon probe, approach 2: the shared ink pass. One unshaded ShaderMaterial, used as the
 * next_pass of every duplicated token material, draws the mesh again with the front faces
 * culled and the vertices pushed out by a screen-constant width: an inverted-hull outline.
 * Chunky pack art is often flat-shaded (a vertex per face, normals split), where a pure
 * normal push tears the hull open at the edges; hull_mix blends the normal with the
 * direction from the mesh's centre (hull_center, an instance uniform set per mesh instance
 * from its AABB) to keep the hull closed on blobby bodies.
 *
 * The width is in screen pixels: it is converted to view units from the projection, so it
 * holds at home zoom and at close zoom, in an orthographic or a perspective camera.
 *
 * This is a design probe (tools/render_jobs/probes), not a shipped look.
 */

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 ink_color : source_color = vec4(0.16, 0.10, 0.26, 1.0);
uniform float width_px : hint_range(0.0, 8.0) = 2.0;
uniform float hull_mix : hint_range(0.0, 1.0) = 0.5;
instance uniform vec3 hull_center = vec3(0.0);

void vertex() {
	vec3 from_centre = VERTEX - hull_center;
	vec3 dir = mix(NORMAL, normalize(from_centre + vec3(1e-5)), hull_mix);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(dir, 0.0)).xyz);
	float depth_scale = PROJECTION_MATRIX[3][3] > 0.5 ? 1.0 : -vp.z;
	float per_px = 2.0 * depth_scale / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vp.xyz += n * width_px * per_px;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = ink_color.rgb;
}
