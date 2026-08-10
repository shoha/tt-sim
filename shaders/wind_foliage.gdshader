shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

/*
 * Wind Foliage Shader
 * ====================
 *
 * PURPOSE:
 * Applied by GlbUtils._apply_wind_material() (utils/glb_utils.gd) to the per-surface
 * materials of a MultiMeshInstance3D built from terrain-paint's "tt_scatter_instances"
 * glTF scene extras (see engine/scatter_instancing.py in the terrain-paint repo) --
 * gives Geoscatter-scattered foliage a real wind-sway animation with zero per-map
 * setup, the same "just works" posture as water.gdshader's "-water" suffix handling.
 *
 * Unlike water.gdshader, this isn't a from-scratch procedural material: the source
 * geometry already carries real baked Albedo/Alpha/ORM/Normal textures (terrain-paint
 * bakes Geoscatter's complex, non-Principled-BSDF foliage shaders down to a flat
 * glTF-safe PBR material before export). This shader's job is only to reproduce that
 * texture data (assigned at runtime per species, see _build_wind_shader_material) and
 * add vertex sway on top -- there is no runtime-accessible way in Godot 4 to layer a
 * vertex effect onto an existing BaseMaterial3D/ORMMaterial3D at runtime, so this
 * hand-written shader is the actual PBR path for every wind-swaying instance, not an
 * addition to one.
 *
 * ALPHA_SCISSOR_THRESHOLD is a fixed cutout, deliberately not sourced from the
 * original material's own transparency mode -- confirmed (terrain-paint's
 * engine/baking.py bake_alpha always sets blend_method='HASHED', which Blender's own
 * glTF exporter maps to alphaMode: BLEND, not MASK) that every baked scatter material
 * imports into Godot as real alpha blending, not alpha-scissor. Real alpha blending on
 * overlapping MultiMesh instances is a known-bad combination in Godot (instances
 * aren't depth-sorted against each other), so this shader always uses cutout instead,
 * which has no sort-order dependency -- the standard choice for instanced foliage in
 * every engine for exactly this reason.
 *
 * ANTIALIASED CUTOUT: uses render_mode alpha_to_coverage to soften the hard cutout
 * edge, which requires MSAA on the rendering viewport (4x MSAA is enabled on the
 * game map SubViewport specifically for this). See wind_foliage_no_aa.gdshader for
 * a plain-cutout variant with no MSAA dependency, swapped in by DebugRenderToggles'
 * "Foliage AA" checkbox (F3 overlay) to A/B test whether that MSAA cost is worth it --
 * see docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md. Shared
 * sway/PBR/occlusion-fade logic lives in wind_foliage_include.gdshaderinc so the two
 * variants can't drift out of sync.
 *
 * OCCLUSION FADE: tree-category instances (see WindFoliage.classify_category) also
 * fade out when a token is hidden behind them, same as map geometry -- see
 * occlusion_fade_include.gdshaderinc (included transitively below), and
 * OcclusionFadeManager._collect_tree_materials() (scenes/states/playing/
 * occlusion_fade_manager.gd), which finds and feeds token uniforms to these exact
 * materials via their node's wind_foliage_category == "tree" metadata.
 *
 * MANAGED BY: WindFoliage.get_shader() (utils/wind_foliage.gd) loads this once and
 * reuses the compiled Shader resource across every species -- each species still
 * gets its own ShaderMaterial instance (different textures), built fresh per map load.
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
	ALPHA_ANTIALIASING_EDGE = alpha_scissor_threshold * 0.5;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
}
