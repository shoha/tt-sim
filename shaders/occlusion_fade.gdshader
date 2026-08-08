/*
 * Occlusion Fade Shader (Spatial)
 * ================================
 *
 * PURPOSE:
 * Replaces StandardMaterial3D on map geometry to create per-pixel screen-door
 * transparency when geometry sits between the camera and a token. This lets
 * players see and select tokens behind walls, pillars, and furniture.
 *
 * HOW IT WORKS:
 * 1. Replicates the original material's PBR appearance (albedo, roughness,
 *    metallic, normal map, emission, UV transform).
 * 2. In the fragment shader, for each token:
 *    - Transforms the token's world position to view space.
 *    - Checks if this fragment is closer to the camera than the token (Z test).
 *    - Checks if this fragment is within the token's fade radius (XY distance).
 *    - Accumulates a fade intensity based on distance (smoothstep gradient).
 * 3. Fragments with non-zero fade intensity are discarded using a 16x16 Bayer
 *    ordered dither pattern, creating a screen-door transparency effect.
 *
 * FLOOR EXCLUSION:
 * Surfaces whose world-space normal points mostly upward (Y > floor_threshold)
 * are treated as floors and never fade. Without this, the ground beneath tokens
 * would dither because it's technically "in front of" the token center.
 *
 * LO-FI PIXELATION ALIGNMENT:
 * When the lo-fi post-process pixelation is active, the dither grid snaps to
 * the same pixel grid (via lofi_pixelation uniform) so each lo-fi pixel gets
 * a single consistent dither value. Without alignment, the two grids create
 * ugly moiré artifacts. The lofi_dither_scale uniform allows subdividing each
 * lo-fi pixel for finer dither (but values > 1 may cause blurring due to the
 * lo-fi shader's point sampling).
 *
 * BAYER DITHER:
 * Uses a 16x16 Bayer matrix (256 threshold levels) built recursively from a
 * 2x2 base. This produces near-smooth gradients that look clean at the lo-fi
 * pixel scale. Larger matrices give smoother gradients but repeat over more
 * pixels. The 16x16 repeats every 16 lo-fi pixels (~80 screen pixels).
 *
 * SHARED LOGIC:
 * The occlusion uniforms, Bayer dither functions, and the fade/discard decision
 * itself live in occlusion_fade_include.gdshaderinc, not in this file -- shared
 * with wind_foliage.gdshader so tree-category scattered foliage participates in
 * the same fade using one source of truth.
 *
 * MANAGED BY: OcclusionFadeManager (scenes/states/playing/occlusion_fade_manager.gd)
 * - Converts map StandardMaterial3D → this shader at map load time.
 * - Updates token_positions, token_radii, and token_count every few physics frames.
 * - Syncs lofi_pixelation from the lo-fi post-process shader.
 * - Restores original materials on map unload or when the effect is disabled.
 *
 * LIMITATIONS:
 * - Max 32 tokens (uniform array size).
 * - Only replaces StandardMaterial3D; existing ShaderMaterials are left as-is.
 * - Does not copy all StandardMaterial3D features (e.g., detail textures,
 *   transparency modes, backlight, subsurface scattering).
 * - The dither pattern is spatial (screen-space), not temporal — no flickering
 *   but the pattern is static relative to the screen.
 */

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

// --- Occlusion fade parameters and dither logic ---
// Shared with wind_foliage.gdshader -- see occlusion_fade_include.gdshaderinc.
#include "res://shaders/occlusion_fade_include.gdshaderinc"


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
	// VERTEX in the fragment shader is in VIEW SPACE (camera space). See
	// occlusion_fade_include.gdshaderinc for the full fade/discard logic, shared
	// with wind_foliage.gdshader.
	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	apply_occlusion_fade(world_normal);
}
