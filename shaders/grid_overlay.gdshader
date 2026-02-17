/*
 * Grid Overlay Shader (Depth-Buffer Projection)
 * ===============================================
 *
 * PURPOSE:
 * Renders a configurable grid onto all visible geometry by reading the depth
 * buffer and reconstructing world-space positions. The grid conforms to floors,
 * tabletops, ramps, stairs — any surface the camera can see.
 *
 * HOW IT WORKS:
 * 1. A full-screen quad (2×2 QuadMesh, flip faces) is parented to Camera3D.
 *    The vertex shader forces it to fill the screen in clip space.
 * 2. The fragment shader samples hint_depth_texture to reconstruct the world
 *    position of each visible pixel.
 * 3. Reconstructs the surface normal from depth-buffer neighbors (cross product
 *    of partial derivatives) and discards steep/vertical surfaces.
 * 4. Applies grid math on the XZ plane and fades with distance from grid_center.
 *
 * SETUP:
 *   MeshInstance3D child of Camera3D inside the SubViewport.
 *   QuadMesh size (2, 2), flip_faces = true.
 *   extra_cull_margin = 16384 to prevent frustum culling.
 *
 * LIVES INSIDE THE SUBVIEWPORT so it receives the lo-fi post-processing effect.
 */

shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture;
uniform float cell_size = 1.524;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform float line_thickness = 2.0; // multiplier for grid line width (helps survive lo-fi pixelation)
uniform float fade_radius = 30.0;
uniform vec3 grid_center = vec3(0.0);
uniform vec2 grid_origin = vec2(0.0);
uniform float normal_threshold = 0.7;

// Cell highlighting during token drags
uniform bool drag_active = false;
uniform vec2 drag_current_cell = vec2(0.0); // cell index (integer coords) of the hovered cell
uniform vec2 drag_start_cell = vec2(0.0);   // cell index of the starting cell
uniform vec4 cell_fill_color : source_color = vec4(0.4, 0.65, 1.0, 0.18); // soft blue fill
uniform vec4 cell_start_fill_color : source_color = vec4(0.4, 0.65, 1.0, 0.10); // dimmer for start
uniform float cell_fill_edge_glow = 0.08; // brighter edge inside highlighted cells

// Reconstruct world position from depth at a given screen UV
vec3 world_from_depth(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	float d = texture(depth_texture, uv).r;
	vec4 clip_pos = vec4(uv * 2.0 - 1.0, d, 1.0);
	vec4 view_pos = inv_proj * clip_pos;
	view_pos /= view_pos.w;
	vec4 world_pos = inv_view * view_pos;
	return world_pos.xyz;
}

void vertex() {
	// Force the quad to fill the screen (Godot 4.3+ reversed-z)
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Reconstruct world position of the geometry at this pixel
	vec3 world_pos = world_from_depth(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);

	// Reconstruct surface normal from depth-buffer neighbors via cross product
	vec2 texel = vec2(1.0) / vec2(textureSize(depth_texture, 0));
	vec3 world_r = world_from_depth(SCREEN_UV + vec2(texel.x, 0.0), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 world_u = world_from_depth(SCREEN_UV + vec2(0.0, texel.y), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 surface_normal = normalize(cross(world_r - world_pos, world_u - world_pos));

	// Only draw grid on mostly-horizontal surfaces (floors, tabletops, ramps)
	if (abs(dot(surface_normal, vec3(0.0, 1.0, 0.0))) < normal_threshold) {
		discard;
	}

	// Grid lines from world XZ coordinates
	vec2 grid_uv = (world_pos.xz - grid_origin) / cell_size;
	vec2 grid_frac = abs(fract(grid_uv - 0.5) - 0.5);
	vec2 grid_width = fwidth(grid_uv) * line_thickness;
	vec2 line = smoothstep(grid_width * 0.5, grid_width * 1.5, grid_frac);
	float grid_line = 1.0 - min(line.x, line.y);

	// Distance fade from grid center
	float dist = length(world_pos.xz - grid_center.xz);
	float fade = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, dist);

	// Base grid lines
	vec3 final_color = line_color.rgb;
	float final_alpha = grid_line * line_color.a * fade;

	// Cell highlighting during drags
	if (drag_active) {
		// Determine which cell this pixel belongs to
		vec2 pixel_cell = floor((world_pos.xz - grid_origin) / cell_size);

		// Check if this pixel is in the current (hovered) cell or the start cell
		bool is_current = (pixel_cell == drag_current_cell);
		bool is_start = (pixel_cell == drag_start_cell);

		if (is_current || is_start) {
			// Compute how close the pixel is to the cell edge (0 = center, 1 = edge)
			vec2 cell_local = fract((world_pos.xz - grid_origin) / cell_size);
			vec2 edge_dist = min(cell_local, vec2(1.0) - cell_local); // distance to nearest edge [0..0.5]
			float edge_factor = 1.0 - smoothstep(0.0, 0.15, min(edge_dist.x, edge_dist.y));

			vec4 fill = is_current ? cell_fill_color : cell_start_fill_color;
			float fill_alpha = (fill.a + edge_factor * cell_fill_edge_glow) * fade;

			// Blend: cell fill underneath grid lines
			final_color = mix(fill.rgb, final_color, step(0.01, final_alpha));
			final_alpha = max(final_alpha, fill_alpha);
		}
	}

	ALBEDO = final_color;
	ALPHA = final_alpha;

	// Discard fully transparent pixels for performance
	if (ALPHA < 0.001) {
		discard;
	}
}
