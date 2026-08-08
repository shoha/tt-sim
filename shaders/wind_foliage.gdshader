shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

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
 * MANAGED BY: GlbUtils._get_wind_foliage_shader() loads this once and reuses the
 * compiled Shader resource across every species -- each species still gets its own
 * ShaderMaterial instance (different textures), built fresh per map load.
 *
 * OCCLUSION FADE: tree-category instances (see WindFoliage.classify_category) also
 * fade out when a token is hidden behind them, same as map geometry -- see
 * occlusion_fade_include.gdshaderinc, included below, and
 * OcclusionFadeManager._collect_tree_materials() (scenes/states/playing/
 * occlusion_fade_manager.gd), which finds and feeds token uniforms to these exact
 * materials via their node's wind_foliage_category == "tree" metadata.
 */

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal_texture = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Per-category wind tuning (set once per species at construction from a preset --
// see GlbUtils._WIND_PRESETS -- never authored per-map).
uniform float sway_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sway_amplitude : hint_range(0.0, 1.0) = 0.05;
uniform float sway_frequency : hint_range(0.05, 2.0) = 0.3;

// Occlusion fade: lets a token show through tree foliage the same way it shows
// through map geometry. See occlusion_fade_include.gdshaderinc.
#include "res://shaders/occlusion_fade_include.gdshaderinc"


void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Phase derived from world-space XZ position (not a per-instance uniform) so every
	// MultiMesh instance -- each with its own MODEL_MATRIX -- naturally desyncs from
	// its neighbors with no extra per-instance data needed, same idiom water.gdshader's
	// own vertex() already uses for its bob.
	float phase = (world_pos.x + world_pos.z) * sway_frequency;
	float t = TIME * sway_speed + phase;
	float sway = sin(t) * sway_amplitude;
	// Local (object-space) height weights the sway so a card's base -- assumed to sit
	// at/near the mesh's local Y origin, the standard authoring convention for
	// grass/foliage cards -- barely moves while its tip sways the most. Deliberately
	// unnormalized (not divided by the mesh's own bounding height): a taller mesh
	// naturally accumulates more absolute sway at its tip than a short one, which is
	// the correct visual whether the current species preset is "grass" or "tree".
	float height_weight = max(VERTEX.y, 0.0);
	VERTEX.x += sway * height_weight;
	VERTEX.z += sway * height_weight * 0.6;
}


void fragment() {
	vec4 albedo_sample = texture(albedo_texture, UV);
	ALBEDO = albedo_sample.rgb;
	ALPHA = albedo_sample.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	vec3 orm = texture(orm_texture, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;

	if (has_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}

	vec3 world_normal = mat3(INV_VIEW_MATRIX) * NORMAL;
	apply_occlusion_fade(world_normal);
}
