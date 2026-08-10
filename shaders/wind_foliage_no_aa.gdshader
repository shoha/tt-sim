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
	vec4 albedo_sample = texture(albedo_texture, UV);
	ALBEDO = albedo_sample.rgb;
	ALPHA = albedo_sample.a;

	vec3 orm = texture(orm_texture, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	SPECULAR = specular_reflectance;

	if (has_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}

	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	apply_occlusion_fade(world_normal, VERTEX, VIEW_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE);
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
