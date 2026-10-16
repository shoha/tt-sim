// The vertex() and fragment() every real wind foliage variant shares: wind_foliage.gdshader,
// wind_foliage_no_aa.gdshader and their painted-light twins wind_foliage_painted.gdshader and
// wind_foliage_painted_no_aa.gdshader. Each variant file is its render_mode, its defines and
// this include, so the four cannot drift apart. Defines a variant may set before including:
//   WIND_FOLIAGE_NO_AA      plain cutout: no alpha-to-coverage edge built-ins (the variant's
//                           render_mode drops alpha_to_coverage to match).
//   FOLIAGE_PAINTED_LIGHT   the painted crown light (wind_foliage_include.gdshaderinc).
// wind_foliage_burn.gdshader keeps its own vertex() and fragment() and does not include this.

#include "res://shaders/wind_foliage_include.gdshaderinc"
// The ground look's tuft colour (ground_light_field.gdshaderinc LIGHT_FIELD_TUFT), off until
// GroundLookBake sets zone_tuft_strength on a looked biome's grass. Here rather than in
// wind_foliage_include, so wind_foliage_burn.gdshader gains no uniform.
#define LIGHT_FIELD_TUFT
#include "res://shaders/ground_light_field.gdshaderinc"

// The tuft's zone texel, read once in vertex() at the MultiMesh instance origin
// (MODEL_MATRIX[3].xz) and constant over the tuft, so a tuft draws in one zone's colour. A tuft
// placed as part of a grass mass carries the offset to its mass anchor in INSTANCE_CUSTOM.yz
// with .w = 1 (ScatterGlbUtils.build_multimesh; .x stays the burn slot) and reads the zone there,
// so every tuft of one mass takes one colour; without custom data INSTANCE_CUSTOM is 0 (per
// tuft). zone_mass is (1 for a massed tuft, its side of the mass toward zone_mass_lit_dir, -1 to
// 1), (0, 0) for fine cover; zone_mass_h a massed tuft's height in metres above its origin (the
// mesh's local height times the instance's height scale, so a grown core tuft stands higher).
varying flat vec4 zone_tuft;
varying flat vec2 zone_mass;
varying float zone_mass_h;


void vertex() {
	local_vertex_y = VERTEX.y;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow;
	zone_tuft = vec4(1.0);
	zone_mass = vec2(0.0);
	zone_mass_h = 0.0;
	if (zone_tuft_strength > 0.0) {
		float anchored = step(0.5, INSTANCE_CUSTOM.w);
		vec2 to_anchor = INSTANCE_CUSTOM.yz * anchored;
		zone_tuft = zone_fetch(MODEL_MATRIX[3].xz + to_anchor * (1.0 - zone_mass_own));
		float side = dot(-to_anchor, zone_mass_lit_dir) / max(zone_mass_lit_m, 1e-3);
		zone_mass = vec2(anchored, anchored * clamp(side, -1.0, 1.0));
		zone_mass_h = max(local_vertex_y, 0.0) * length(MODEL_MATRIX[1].xyz);
	}
	VERTEX += shadow_caster_offset(MODEL_MATRIX, INV_VIEW_MATRIX);
}


void fragment() {
	NORMAL = two_sided_foliage_normal(NORMAL, FRONT_FACING);
	vec3 pbr_albedo;
	float pbr_alpha;
	float pbr_ao;
	float pbr_roughness;
	float pbr_metallic;
	vec3 pbr_normal_map;

	apply_wind_foliage_pbr(UV, INV_VIEW_MATRIX, NORMAL, VERTEX, VIEW_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE, local_vertex_y, COLOR.gb,
		pbr_albedo, pbr_alpha, pbr_ao, pbr_roughness, pbr_metallic, pbr_normal_map);
	if (zone_tuft_strength > 0.0) {
		pbr_albedo = zone_tuft_albedo(pbr_albedo, zone_tuft, vec3(zone_mass, zone_mass_h));
	}

	ALBEDO = pbr_albedo;
	ALPHA = pbr_alpha;
	AO = pbr_ao;
	ROUGHNESS = pbr_roughness;
	METALLIC = pbr_metallic;
#ifdef FOLIAGE_PAINTED_LIGHT
	// No ambient or reflected specular either: a painted crown has no sheen.
	SPECULAR = 0.0;
#else
	SPECULAR = specular_reflectance;
#endif
	BACKLIGHT = vec3(backlight);
	if (has_normal_texture) {
		NORMAL_MAP = pbr_normal_map;
		NORMAL_MAP_DEPTH = 1.0;
	}

	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
#ifndef WIND_FOLIAGE_NO_AA
	ALPHA_ANTIALIASING_EDGE = alpha_scissor_threshold * 0.5;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
#endif
}
