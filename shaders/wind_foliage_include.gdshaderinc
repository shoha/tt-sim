// Shared wind-sway vertex offset and PBR/occlusion-fade fragment logic for both
// wind_foliage.gdshader (alpha_to_coverage antialiased cutout, 4x MSAA) and
// wind_foliage_no_aa.gdshader (plain cutout, no MSAA dependency) -- the two are A/B
// tested against each other by DebugRenderToggles' "Foliage AA" checkbox (F3
// overlay) to measure whether alpha_to_coverage's viewport-wide MSAA cost is worth
// its softened cutout edges. See
// docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
//
// Functions take VERTEX/MODEL_MATRIX/TIME/etc. as explicit parameters rather than
// reading stage built-ins directly -- confirmed via a real headless probe (see
// occlusion_fade_include.gdshaderinc, which documents the same constraint) that
// Godot's shader compiler does not resolve stage built-ins referenced inside a
// plain (non-vertex/fragment) function, even one called from vertex()/fragment().

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
