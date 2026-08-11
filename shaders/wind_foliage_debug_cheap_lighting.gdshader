shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

/*
 * Wind Foliage Shader -- Debug Cheap Lighting Variant
 * ======================================================
 *
 * Debug-only A/B counterpart to wind_foliage_no_aa.gdshader (the real shader's
 * antialiasing-off variant, the currently shipped default), swapped in by
 * DebugRenderToggles' "Cheap lighting foliage" checkbox (F3 performance overlay).
 *
 * Unlike wind_foliage_debug_trivial.gdshader and wind_foliage_debug_unshaded.gdshader
 * (both isolation shaders used to localize the cost), this is a candidate REAL fix:
 * identical PBR texture sampling, wind sway, and occlusion fade to the real shader --
 * the only difference is the render_mode line. Those two isolation shaders, plus an
 * M1 Xcode/Instruments GPU capture (fragment stage dominating by ~10x any other
 * stage), confirmed the framerate cost is Godot's diffuse_burley + specular_schlick_ggx
 * BRDF evaluation, not texture bandwidth. This variant swaps to diffuse_lambert (a
 * single dot product instead of Burley's more expensive retro-reflection term) and
 * specular_disabled (drops the GGX distribution/Fresnel math entirely).
 *
 * Exists as a toggle rather than the shipped default so the visual difference can be
 * judged in-game before committing to it -- see DebugRenderToggles' own docstring.
 *
 * MANAGED BY: WindFoliage.get_shader_debug_cheap_lighting() (utils/wind_foliage.gd)
 * loads this once and reuses the compiled Shader resource, mirroring
 * get_shader_no_aa()'s own caching.
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
