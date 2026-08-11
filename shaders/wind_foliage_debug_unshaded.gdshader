shader_type spatial;
render_mode cull_disabled, unshaded;

/*
 * Wind Foliage Shader -- Debug Unshaded (Full Textures) Variant
 * =================================================================
 *
 * Debug-only A/B counterpart to wind_foliage.gdshader, swapped in by
 * DebugRenderToggles' "Unshaded foliage (full textures)" checkbox (F3 performance
 * overlay). Complements wind_foliage_debug_trivial.gdshader's albedo-only variant to
 * separate two different candidate costs: this one samples the exact same textures as
 * the real shader (albedo, ORM, optional normal map via apply_wind_foliage_pbr()) but
 * still skips Godot's lighting pass (render_mode unshaded). If this variant ALSO
 * recovers the framerate the trivial variant does, the real shader's cost is the
 * lighting/BRDF evaluation, not texture bandwidth; if it stays slow like the real
 * shader, the cost is the texture reads themselves.
 *
 * MANAGED BY: WindFoliage.get_shader_debug_unshaded() (utils/wind_foliage.gd) loads
 * this once and reuses the compiled Shader resource, mirroring get_shader_no_aa()'s
 * own caching.
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

	// ao/roughness/metallic/normal_map are otherwise unused under unshaded rendering --
	// fold them into ALBEDO as a genuinely non-zero (if visually imperceptible)
	// perturbation so the shader compiler can't prove the ORM/normal texture() reads
	// are dead code and strip them. Without this, an optimizing compiler could reduce
	// this variant to the same single-texture-read cost as the trivial variant,
	// silently invalidating the A/B comparison this shader exists to make.
	float sampled_perturbation = (
		(pbr_ao + pbr_roughness + pbr_metallic + dot(pbr_normal_map, vec3(1.0))) * 0.00001
	);
	ALBEDO = pbr_albedo + sampled_perturbation;
	ALPHA = pbr_alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
