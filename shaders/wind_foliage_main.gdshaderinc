// The vertex() and fragment() every real wind foliage variant shares: wind_foliage.gdshader,
// wind_foliage_no_aa.gdshader and their painted-light twins wind_foliage_painted.gdshader and
// wind_foliage_painted_no_aa.gdshader. Each variant file is its render_mode, its defines and
// this include, so the four cannot drift apart. Defines a variant may set before including:
//   WIND_FOLIAGE_NO_AA      plain cutout: no alpha-to-coverage edge built-ins (the variant's
//                           render_mode drops alpha_to_coverage to match).
//   FOLIAGE_PAINTED_LIGHT   the painted crown light (wind_foliage_include.gdshaderinc).
// wind_foliage_burn.gdshader keeps its own vertex() and fragment() and does not include this.

#include "res://shaders/wind_foliage_include.gdshaderinc"


void vertex() {
	local_vertex_y = VERTEX.y;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow;
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
