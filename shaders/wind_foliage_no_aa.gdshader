shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

/*
 * Wind Foliage Shader -- No-Antialiasing Variant
 * ================================================
 *
 * Debug-only A/B counterpart to wind_foliage.gdshader, swapped in by
 * DebugRenderToggles' "Foliage AA" checkbox (F3 performance overlay) to test
 * whether the 4x MSAA enabled solely to support wind_foliage.gdshader's
 * alpha_to_coverage cutout antialiasing is worth its viewport-wide rendering cost.
 * See docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
 *
 * Identical wind-sway/PBR/occlusion-fade logic to wind_foliage.gdshader (shared via
 * wind_foliage_include.gdshaderinc, so the two can't drift out of sync) -- the only
 * difference is a plain ALPHA_SCISSOR cutout with a hard edge: no alpha_to_coverage
 * render mode, no antialiasing-edge built-ins, no MSAA dependency.
 *
 * MANAGED BY: WindFoliage.get_shader_no_aa() (utils/wind_foliage.gd) loads this once
 * and reuses the compiled Shader resource, mirroring get_shader()'s own caching.
 */

#include "res://shaders/wind_foliage_include.gdshaderinc"


void vertex() {
	VERTEX += wind_sway_vertex_offset(VERTEX, MODEL_MATRIX, TIME);
}


void fragment() {
	vec3 pbr_albedo;
	float pbr_alpha;
	float pbr_ao;
	float pbr_roughness;
	float pbr_metallic;
	vec3 pbr_normal_map;

	apply_wind_foliage_pbr(UV, INV_VIEW_MATRIX, NORMAL, VERTEX, VIEW_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE,
		pbr_albedo, pbr_alpha, pbr_ao, pbr_roughness, pbr_metallic, pbr_normal_map);

	ALBEDO = pbr_albedo;
	ALPHA = pbr_alpha;
	AO = pbr_ao;
	ROUGHNESS = pbr_roughness;
	METALLIC = pbr_metallic;
	SPECULAR = specular_reflectance;
	if (has_normal_texture) {
		NORMAL_MAP = pbr_normal_map;
		NORMAL_MAP_DEPTH = 1.0;
	}

	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
