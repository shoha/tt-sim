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
 * 3. Height filter rejects pixels outside [grid_y_level ± grid_y_tolerance],
 *    preventing the grid from projecting onto tokens and ceilings. With a ground field
 *    (ground_heights_enabled: authored terrain, or a Blender map's ground sampled from
 *    its collision; GridOverlay.set_ground) the band follows the ground instead: a pixel
 *    is kept only within ground_tolerance of the ground height under it, interpolated on
 *    the field's triangles, so every tier top and slope gets the grid.
 * 4. Reconstructs the surface normal from depth-buffer neighbors (cross product
 *    of partial derivatives) and discards steep/vertical surfaces. With a ground field
 *    the slope test reads the field's smooth normal instead (ground_normal_at), and the
 *    facet normal only rejects near-vertical surfaces (ground_facet_threshold).
 * 5. Applies grid math on the XZ plane and fades with distance from grid_center.
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
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float line_thickness = 2.0; // multiplier for grid line width (helps survive lo-fi pixelation)
uniform float fade_radius = 30.0;
uniform float opacity = 1.0;            // global opacity multiplier (animated for fade in/out)
uniform vec3 grid_center = vec3(0.0);
uniform vec2 grid_origin = vec2(0.0);
uniform float normal_threshold = 0.7;
uniform float grid_y_level = 0.0;       // approximate floor Y in world space
uniform float grid_y_tolerance = 0.5;   // max height above grid_y_level to draw grid

// Ground field (GridOverlay.set_ground, a GroundHeightField): the ground heights, one R32F
// texel per sample (read with texelFetch, so no float filtering is needed), the map frame's
// transform both ways (the level's map scale and offset), and the sample grid's map-frame
// origin and step (on authored terrain, the ground shader's layer_grid_origin /
// layer_grid_step).
uniform bool ground_heights_enabled = false;
uniform sampler2D ground_heights : filter_nearest, repeat_disable;
uniform mat4 ground_world_to_map = mat4(1.0);
uniform mat4 ground_map_to_world = mat4(1.0);
uniform vec2 ground_grid_origin = vec2(0.0);
uniform vec2 ground_grid_step = vec2(0.25);
uniform float ground_tolerance = 0.2;
// With a ground field, a pixel whose depth-buffer facet is steeper than this (n.y; about 72
// degrees) is not ground whatever the field says: a token's side, a wall or a trunk within the
// band. Looser than normal_threshold so a tier face's facets never flicker across it.
uniform float ground_facet_threshold = 0.3;
// With a ground field, the grid fades out over this much n.y below normal_threshold.
uniform float ground_slope_fade = 0.12;

// Neutral cell tint — subtle fill on every cell for readability on bright maps
// color_surface1 (#2c1f2b) from the theme
uniform vec4 cell_tint_color : source_color = vec4(0.173, 0.122, 0.169, 0.65);
uniform float cell_tint_inset = 0.10;   // fraction of cell to leave unshaded at edges (0.10 = 90% fill)

// Cell highlighting during token drags
uniform bool drag_active = false;
uniform vec2 drag_current_cell = vec2(0.0); // cell index (integer coords) of the hovered cell
uniform vec2 drag_start_cell = vec2(0.0);   // cell index of the starting cell
uniform vec4 cell_fill_color : source_color = vec4(0.4, 0.65, 1.0, 0.18); // soft blue fill
uniform vec4 cell_start_fill_color : source_color = vec4(0.4, 0.65, 1.0, 0.10); // dimmer for start
uniform float cell_fill_edge_glow = 0.08; // brighter edge inside highlighted cells

// Reconstruct view-space position from depth at a given screen UV
vec4 view_from_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_texture, uv).r;
	vec4 clip_pos = vec4(uv * 2.0 - 1.0, d, 1.0);
	vec4 view_pos = inv_proj * clip_pos;
	view_pos /= view_pos.w;
	return view_pos;
}

// Reconstruct world position from depth at a given screen UV
vec3 world_from_depth(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	vec4 view_pos = view_from_depth(uv, inv_proj);
	return (inv_view * view_pos).xyz;
}

// Terrain height (map frame) at continuous sample coordinates `at`, on the triangles the
// terrain mesh and its collision use: the same split as ScatterGenerator.triangle_height
// (corners (x, z), (x + 1, z), (x, z + 1) below the diagonal, (x + 1, z + 1) above it),
// clamped to the grid so the edge heights continue past the map edge.
float ground_height_at(vec2 at) {
	ivec2 size = textureSize(ground_heights, 0);
	vec2 f = clamp(at, vec2(0.0), vec2(size - ivec2(1)));
	ivec2 i0 = min(ivec2(floor(f)), max(size - ivec2(2), ivec2(0)));
	vec2 t = f - vec2(i0);
	float h10 = texelFetch(ground_heights, i0 + ivec2(1, 0), 0).r;
	float h01 = texelFetch(ground_heights, i0 + ivec2(0, 1), 0).r;
	if (t.x + t.y <= 1.0) {
		float h00 = texelFetch(ground_heights, i0, 0).r;
		return h00 + (h10 - h00) * t.x + (h01 - h00) * t.y;
	}
	float h11 = texelFetch(ground_heights, i0 + ivec2(1, 1), 0).r;
	return h11 + (h01 - h11) * (1.0 - t.x) + (h10 - h11) * (1.0 - t.y);
}

// The ground's shading normal (map frame) at sample `s`: central differences, one-sided at
// the edge (TerrainMeshBuilder.sample_normal / ScatterGenerator.vertex_normal).
vec3 ground_vertex_normal(ivec2 s, ivec2 size) {
	ivec2 x0 = ivec2(max(s.x - 1, 0), s.y);
	ivec2 x1 = ivec2(min(s.x + 1, size.x - 1), s.y);
	ivec2 z0 = ivec2(s.x, max(s.y - 1, 0));
	ivec2 z1 = ivec2(s.x, min(s.y + 1, size.y - 1));
	float slope_x = (texelFetch(ground_heights, x1, 0).r - texelFetch(ground_heights, x0, 0).r)
		/ (float(x1.x - x0.x) * ground_grid_step.x);
	float slope_z = (texelFetch(ground_heights, z1, 0).r - texelFetch(ground_heights, z0, 0).r)
		/ (float(z1.y - z0.y) * ground_grid_step.y);
	return normalize(vec3(-slope_x, 1.0, -slope_z));
}

// The ground's smooth normal at continuous sample coordinates `at`: the vertex normals of the
// triangle ground_height_at() uses, interpolated (ScatterGenerator.triangle_normal), which is
// what the ground is lit with and what its rock rule reads. The grid's steep-face filter uses
// it on the ground instead of the depth buffer's facet normal, whose triangle-by-triangle
// flicker on a slope near the threshold sawed the grid's edge along tier lips (P3-7).
vec3 ground_normal_at(vec2 at) {
	ivec2 size = textureSize(ground_heights, 0);
	vec2 f = clamp(at, vec2(0.0), vec2(size - ivec2(1)));
	ivec2 i0 = min(ivec2(floor(f)), max(size - ivec2(2), ivec2(0)));
	vec2 t = f - vec2(i0);
	vec3 n10 = ground_vertex_normal(i0 + ivec2(1, 0), size);
	vec3 n01 = ground_vertex_normal(i0 + ivec2(0, 1), size);
	vec3 n;
	if (t.x + t.y <= 1.0) {
		n = ground_vertex_normal(i0, size) * (1.0 - t.x - t.y) + n10 * t.x + n01 * t.y;
	} else {
		n = ground_vertex_normal(i0 + ivec2(1, 1), size) * (t.x + t.y - 1.0)
			+ n01 * (1.0 - t.x) + n10 * (1.0 - t.y);
	}
	return normalize(n);
}

void vertex() {
	// Force the quad to fill the screen (Godot 4.3+ reversed-z)
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Reject sky/void pixels (reversed-Z: far plane = 0.0)
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	if (raw_depth < 0.0001) {
		discard;
	}

	// Sample depth at all 4 neighbors to detect geometry silhouette edges
	vec2 texel = vec2(1.0) / vec2(textureSize(depth_texture, 0));
	// Use a wider kernel (2 texels) so the rejection zone is thick enough to
	// survive the lo-fi pixelation downsampling
	float depth_r = texture(depth_texture, SCREEN_UV + vec2(texel.x * 2.0, 0.0)).r;
	float depth_l = texture(depth_texture, SCREEN_UV - vec2(texel.x * 2.0, 0.0)).r;
	float depth_u = texture(depth_texture, SCREEN_UV + vec2(0.0, texel.y * 2.0)).r;
	float depth_d = texture(depth_texture, SCREEN_UV - vec2(0.0, texel.y * 2.0)).r;

	// Reject if ANY neighbor is in the void — this pixel is at the geometry edge
	if (depth_r < 0.0001 || depth_l < 0.0001 || depth_u < 0.0001 || depth_d < 0.0001) {
		discard;
	}

	// Depth discontinuity rejection: large depth jumps between neighbors mean
	// we're on a geometry silhouette where reconstruction is unreliable
	vec4 view_c = view_from_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float linear_c = -view_c.z;
	float linear_r = -view_from_depth(SCREEN_UV + vec2(texel.x, 0.0), INV_PROJECTION_MATRIX).z;
	float linear_u = -view_from_depth(SCREEN_UV + vec2(0.0, texel.y), INV_PROJECTION_MATRIX).z;
	float depth_threshold = max(0.1 * linear_c, 0.2);
	if (abs(linear_r - linear_c) > depth_threshold || abs(linear_u - linear_c) > depth_threshold) {
		discard;
	}

	// Reconstruct world positions from the already-computed view positions
	vec3 world_pos = (INV_VIEW_MATRIX * view_c).xyz;

	// Height filter: only draw grid near the ground. Rejects token surfaces (which extend
	// above the floor) and ceilings. With a ground field: the ground height under this pixel;
	// otherwise the fixed band around grid_y_level.
	vec2 ground_at = vec2(0.0);
	if (ground_heights_enabled) {
		vec3 map_pos = (ground_world_to_map * vec4(world_pos, 1.0)).xyz;
		ground_at = (map_pos.xz - ground_grid_origin) / ground_grid_step;
		float h = ground_height_at(ground_at);
		float ground_y = (ground_map_to_world * vec4(map_pos.x, h, map_pos.z, 1.0)).y;
		if (abs(world_pos.y - ground_y) > ground_tolerance) {
			discard;
		}
	} else if (world_pos.y > grid_y_level + grid_y_tolerance || world_pos.y < grid_y_level - grid_y_tolerance) {
		discard;
	}

	vec3 world_r_pos = (INV_VIEW_MATRIX * view_from_depth(SCREEN_UV + vec2(texel.x, 0.0), INV_PROJECTION_MATRIX)).xyz;
	vec3 world_u_pos = (INV_VIEW_MATRIX * view_from_depth(SCREEN_UV + vec2(0.0, texel.y), INV_PROJECTION_MATRIX)).xyz;

	// Reconstruct surface normal from depth-buffer neighbors via cross product
	vec3 surface_normal = normalize(cross(world_r_pos - world_pos, world_u_pos - world_pos));
	float facet_up = abs(dot(surface_normal, vec3(0.0, 1.0, 0.0)));

	// Only draw grid on mostly-horizontal surfaces (floors, tabletops, ramps). With a ground
	// field the slope test reads the ground's smooth normal (ground_normal_at; the map frame is
	// the world scaled uniformly, so the angle is the same) and fades the grid out over
	// ground_slope_fade below normal_threshold rather than cutting it: the normal is
	// interpolated per triangle, and a hard cut along a tier lip running across the grid
	// traced that as a fine comb. The facet normal only rejects near-vertical surfaces
	// standing within the band (token sides, walls, trunks).
	float slope_fade = 1.0;
	if (ground_heights_enabled) {
		float ground_up = abs(ground_normal_at(ground_at).y);
		if (facet_up < ground_facet_threshold || ground_up < normal_threshold - ground_slope_fade) {
			discard;
		}
		slope_fade = smoothstep(normal_threshold - ground_slope_fade, normal_threshold, ground_up);
	} else if (facet_up < normal_threshold) {
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
	float fade = (1.0 - smoothstep(fade_radius * 0.6, fade_radius, dist)) * slope_fade;

	// Compositing layers (bottom to top):
	//   1. Cell tint   — neutral darkening on every cell
	//   2. Drag fill   — colored highlight on hovered/start cells
	//   3. Grid lines  — white lines on top

	// Layer 1: cell tint (base) — inset slightly from cell edges
	vec2 cell_local = fract((world_pos.xz - grid_origin) / cell_size);
	vec2 edge_dist = min(cell_local, vec2(1.0) - cell_local); // 0 at edge, 0.5 at center
	float inset_half = cell_tint_inset * 0.5; // half the inset fraction
	float inset_mask = smoothstep(0.0, inset_half, min(edge_dist.x, edge_dist.y));

	vec3 final_color = cell_tint_color.rgb;
	float final_alpha = cell_tint_color.a * fade * inset_mask;

	// Layer 2: drag cell highlighting
	if (drag_active) {
		vec2 pixel_cell = floor((world_pos.xz - grid_origin) / cell_size);
		bool is_current = (pixel_cell == drag_current_cell);
		bool is_start = (pixel_cell == drag_start_cell);

		if (is_current || is_start) {
			float edge_factor = 1.0 - smoothstep(0.0, 0.15, min(edge_dist.x, edge_dist.y));

			vec4 fill = is_current ? cell_fill_color : cell_start_fill_color;
			float fill_alpha = (fill.a + edge_factor * cell_fill_edge_glow) * fade;

			// Drag fill replaces the tint on highlighted cells
			final_color = fill.rgb;
			final_alpha = fill_alpha;
		}
	}

	// Layer 3: grid lines on top of everything
	float line_alpha = grid_line * line_color.a * fade;
	if (line_alpha > 0.01) {
		final_color = line_color.rgb;
		final_alpha = max(final_alpha, line_alpha);
	}

	ALBEDO = final_color;
	ALPHA = final_alpha * opacity;

	// Discard fully transparent pixels for performance
	if (ALPHA < 0.001) {
		discard;
	}
}
