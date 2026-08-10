// Shared wind-sway vertex offset and PBR/occlusion-fade fragment logic for both
// wind_foliage.gdshader (alpha_to_coverage antialiased cutout, 4x MSAA) and
// wind_foliage_no_aa.gdshader (plain cutout, no MSAA dependency) -- the two are A/B
// tested against each other by DebugRenderToggles' "Foliage AA" checkbox (F3
// overlay) to measure whether alpha_to_coverage's viewport-wide MSAA cost is worth
// its softened cutout edges. See
// docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
//
// Godot's shader compiler has a real limitation: fragment stage output built-ins
// (ALBEDO, ROUGHNESS, METALLIC, AO, etc.) can only be assigned directly inside
// vertex()/fragment(), not from any called function. To share the complete PBR and
// occlusion-fade logic without code duplication (which would let the two variants
// drift out of sync), apply_wind_foliage_pbr() uses out-parameters: the function
// computes all PBR values and passes them back to the caller, which then assigns them
// to the built-ins. Functions like wind_sway_vertex_offset take stage built-ins as
// explicit parameters rather than reading them directly, matching the pattern already
// used in occlusion_fade_include.gdshaderinc.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal_texture = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float specular_reflectance : hint_range(0.0, 1.0) = 0.2;

// Per-category wind tuning (set once per species at construction from a preset --
// see GlbUtils._WIND_PRESETS -- never authored per-map).
uniform float sway_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sway_amplitude : hint_range(0.0, 1.0) = 0.05;
uniform float sway_frequency : hint_range(0.05, 2.0) = 0.3;

// Occlusion fade: lets a token show through tree foliage the same way it shows
// through map geometry. See occlusion_fade_include.gdshaderinc.
#include "res://shaders/occlusion_fade_include.gdshaderinc"


// Wind-sway offset to add to VERTEX. [param vertex] is the un-swayed object-space
// VERTEX built-in; [param model_matrix]/[param time] are the vertex() stage's
// MODEL_MATRIX/TIME built-ins, passed in explicitly (see file header).
vec3 wind_sway_vertex_offset(vec3 vertex, mat4 model_matrix, float time) {
	// Phase derived from world-space XZ position (not a per-instance uniform) so every
	// MultiMesh instance -- each with its own MODEL_MATRIX -- naturally desyncs from
	// its neighbors with no extra per-instance data needed, same idiom water.gdshader's
	// own vertex() already uses for its bob.
	vec3 world_pos = (model_matrix * vec4(vertex, 1.0)).xyz;
	float phase = (world_pos.x + world_pos.z) * sway_frequency;
	float t = time * sway_speed + phase;
	float sway = sin(t) * sway_amplitude;
	// Local (object-space) height weights the sway so a card's base -- assumed to sit
	// at/near the mesh's local Y origin, the standard authoring convention for
	// grass/foliage cards -- barely moves while its tip sways the most. Deliberately
	// unnormalized (not divided by the mesh's own bounding height): a taller mesh
	// naturally accumulates more absolute sway at its tip than a short one, which is
	// the correct visual whether the current species preset is "grass" or "tree".
	float height_weight = max(vertex.y, 0.0);
	return vec3(sway * height_weight, 0.0, sway * height_weight * 0.6);
}


// Computes PBR and occlusion-fade fragment values. Uses out-parameters to pass
// results back to the caller (which then assigns them to built-ins) -- a workaround
// for Godot's limitation that output built-ins can only be assigned directly inside
// fragment(), not from a called function. Samples textures, unpacks ORM, applies
// normal mapping, and calls apply_occlusion_fade() to determine final alpha values.
// Caller is responsible for assigning the out-parameters to their corresponding
// built-ins and setting variant-specific ALPHA_SCISSOR_THRESHOLD/antialiasing values.
void apply_wind_foliage_pbr(
	vec2 uv,
	mat4 inv_view_matrix,
	vec3 normal,
	vec3 vertex_view,
	mat4 view_matrix,
	vec2 frag_coord,
	vec2 viewport_size,
	out vec3 out_albedo,
	out float out_alpha,
	out float out_ao,
	out float out_roughness,
	out float out_metallic,
	out vec3 out_normal_map
) {
	vec4 albedo_sample = texture(albedo_texture, uv);
	out_albedo = albedo_sample.rgb;
	out_alpha = albedo_sample.a;

	vec3 orm = texture(orm_texture, uv).rgb;
	out_ao = orm.r;
	out_roughness = orm.g;
	out_metallic = orm.b;

	if (has_normal_texture) {
		out_normal_map = texture(normal_texture, uv).rgb;
	} else {
		out_normal_map = vec3(0.0);
	}

	vec3 world_normal = mat3(inv_view_matrix) * normal;
	apply_occlusion_fade(world_normal, vertex_view, view_matrix, frag_coord, viewport_size);
}
