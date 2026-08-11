shader_type spatial;
render_mode cull_disabled, unshaded;

/*
 * Wind Foliage Shader -- Debug Trivial Variant
 * ==============================================
 *
 * Debug-only A/B counterpart to wind_foliage.gdshader, swapped in by
 * DebugRenderToggles' "Trivial foliage shader" checkbox (F3 performance overlay) to
 * isolate whether the real shader's per-fragment cost (PBR lighting, ORM/normal
 * texture samples, occlusion-fade math) is what drives a framerate drop, as opposed
 * to plain geometry/overdraw from the instance count -- which this variant leaves
 * unchanged (same wind-sway vertex offset, same alpha-scissor cutout silhouette).
 *
 * Reuses wind_sway_vertex_offset and the albedo_texture/alpha_scissor_threshold
 * uniforms from wind_foliage_include.gdshaderinc so its silhouette and motion exactly
 * match the real shader -- only the fragment stage's shading work differs. render_mode
 * unshaded skips Godot's lighting pass entirely, and only the albedo texture is
 * sampled (no ORM, no normal map, no occlusion-fade token loop).
 *
 * MANAGED BY: WindFoliage.get_shader_debug_trivial() (utils/wind_foliage.gd) loads
 * this once and reuses the compiled Shader resource, mirroring get_shader_no_aa()'s
 * own caching.
 */

#include "res://shaders/wind_foliage_include.gdshaderinc"


void vertex() {
	VERTEX += wind_sway_vertex_offset(VERTEX, MODEL_MATRIX, TIME);
}


void fragment() {
	vec4 albedo_sample = texture(albedo_texture, UV);
	ALBEDO = albedo_sample.rgb;
	ALPHA = albedo_sample.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
