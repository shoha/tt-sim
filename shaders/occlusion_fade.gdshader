shader_type spatial;

// Depth draw opaque: unfaded fragments write depth normally.
// Discarded (faded) fragments don't write depth, letting tokens behind show through.
render_mode cull_back, depth_draw_opaque;

// --- Standard PBR properties (copied from the original StandardMaterial3D) ---
group_uniforms material;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal_texture = false;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

// --- Occlusion fade parameters (set by OcclusionFadeManager each frame) ---
group_uniforms occlusion;
uniform int token_count = 0;
uniform vec3 token_positions[32]; // World-space positions (visual center, not feet)
uniform float token_radii[32];    // Per-token fade radius (view-space), derived from collision shape
uniform float min_alpha = 0.3;    // Target opacity at the center of the fade zone
uniform float floor_threshold = 0.5; // World-space normal Y above this = floor (never fades)
uniform float lofi_pixelation = 0.0; // Pixelation from the lo-fi shader (0 = disabled, aligns dither grid)
uniform float lofi_dither_scale = 1.0; // Dither subdivisions per lo-fi pixel (1 = 1:1 with grid)


// 16x16 Bayer ordered dither via recursive construction.
// Builds from 2x2 -> 4x4 -> 8x8 -> 16x16, giving 256 threshold levels for
// near-smooth gradients that still look clean with the lo-fi pixelation grid.
// Returns a value in [0, 1) based on screen/grid pixel position.
float bayer2(float x, float y) {
	// 2x2 base matrix: 0 2 / 3 1
	float v = x + y * 2.0;
	if (v < 0.5) return 0.0;
	if (v < 1.5) return 2.0;
	if (v < 2.5) return 3.0;
	return 1.0;
}

float bayer4(float x, float y) {
	return 4.0 * bayer2(mod(x, 2.0), mod(y, 2.0))
	     + bayer2(floor(x / 2.0), floor(y / 2.0));
}

float bayer8(float x, float y) {
	return 4.0 * bayer4(mod(x, 4.0), mod(y, 4.0))
	     + bayer2(floor(x / 4.0), floor(y / 4.0));
}

float bayer16(vec2 screen_coord) {
	vec2 p = mod(floor(screen_coord), 16.0);
	return (4.0 * bayer8(mod(p.x, 8.0), mod(p.y, 8.0))
	      + bayer2(floor(p.x / 8.0), floor(p.y / 8.0))) / 256.0;
}


void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}


void fragment() {
	// --- Standard PBR output ---
	vec4 albedo = albedo_color;
	if (has_albedo_texture) {
		albedo *= texture(albedo_texture, UV);
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	if (has_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	if (emission_energy > 0.001) {
		EMISSION = emission * emission_energy;
	}

	// --- Per-pixel occlusion fade ---
	// VERTEX in the fragment shader is in VIEW SPACE (camera space).
	// View space: -Z is into the screen; larger Z values are closer to camera.
	// A fragment "in front of" a token has a larger (less negative) Z.
	//
	// Floor check: convert the surface normal back to world space and skip
	// any surface whose normal points mostly upward (floors, ground, ramps).
	// These surfaces are beneath tokens, not in front of them.
	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	bool is_floor = world_normal.y > floor_threshold;

	if (token_count > 0 && !is_floor) {
		float fade_intensity = 0.0;

		for (int i = 0; i < 32; i++) {
			if (i >= token_count) break;

			// Transform token world position to view space
			vec3 token_view = (VIEW_MATRIX * vec4(token_positions[i], 1.0)).xyz;

			// Skip if this fragment is behind (further from camera than) the token
			if (VERTEX.z <= token_view.z) continue;

			// Distance in the camera's XY plane (screen-space proximity)
			float dist = distance(VERTEX.xy, token_view.xy);
			float radius = token_radii[i];

			if (dist < radius) {
				// Smooth gradient: full fade at center, zero at edge
				float fade = 1.0 - smoothstep(0.0, radius, dist);
				fade_intensity = max(fade_intensity, fade);
			}
		}

		// Discard fragments using ordered dithering for screen-door transparency.
		// When the lo-fi pixelation post-process is active, snap the dither grid
		// to the same pixel grid so each lo-fi pixel gets a single consistent
		// dither value (avoids ugly noise from misaligned grids).
		if (fade_intensity > 0.01) {
			float target_alpha = mix(1.0, min_alpha, fade_intensity);

			vec2 dither_coord = FRAGCOORD.xy;
			if (lofi_pixelation > 0.0) {
				float aspect = 16.0 / 9.0;
				vec2 uv_here = FRAGCOORD.xy / VIEWPORT_SIZE;
				vec2 lofi_cell = vec2(lofi_pixelation / aspect, lofi_pixelation);
				// Subdivide each lo-fi pixel into lofi_dither_scale x lofi_dither_scale
				// dither cells. Scale=1 matches the lo-fi grid exactly; scale=2 gives
				// 2x2 finer cells per lo-fi pixel while staying grid-aligned.
				dither_coord = floor(uv_here * lofi_dither_scale / lofi_cell);
			}

			float threshold = bayer16(dither_coord);

			if (target_alpha < threshold) {
				discard;
			}
		}
	}
}
