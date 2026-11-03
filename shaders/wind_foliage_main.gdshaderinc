// The vertex() and fragment() every real wind foliage variant shares: wind_foliage.gdshader,
// wind_foliage_no_aa.gdshader and their painted-light twins wind_foliage_painted.gdshader and
// wind_foliage_painted_no_aa.gdshader. Each variant file is its render_mode, its defines and
// this include, so the four cannot drift apart. Defines a variant may set before including:
//   WIND_FOLIAGE_NO_AA      plain cutout: no alpha-to-coverage edge built-ins (the variant's
//                           render_mode drops alpha_to_coverage to match).
//   FOLIAGE_PAINTED_LIGHT   the painted crown light (wind_foliage_include.gdshaderinc).
// wind_foliage_burn.gdshader keeps its own vertex() and fragment() and does not include this.

#include "res://shaders/wind_foliage_include.gdshaderinc"
// The arrival motion's grow_scale() (here, not in wind_foliage_include, so the burn variant gains
// no uniform).
#include "res://shaders/wind_foliage_grow.gdshaderinc"
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

// The eye view's near grass (EyeCanopy, the GRASS_* constants mirror these term for term). A
// tuft seen from street level fills the lower third of the frame as one flat, full-sun slab, so
// within EYE_GRASS_NONE metres (times the map scale) of the eye a grass tuft (blade_height > 0)
// is thinned tuft by tuft, its colour eased a little toward its own grey and deepened from a cool
// dark foot to a tip just under its own value, its tip tapered and its value stepped per tuft so neighbours read as separate
// shapes; all of it in full inside EYE_GRASS_FULL. `eye_grass` is the map scale while the eye
// view is on (CanopyFade publishes it), 0 otherwise, and only the eye's own pass takes the term
// (CANOPY_EYE_PASS): the orbit view's grass is untouched.
global uniform float eye_grass;
const float EYE_GRASS_FULL = 1.5;
const float EYE_GRASS_NONE = 9.0;
const float EYE_GRASS_THIN = 0.85;
const float EYE_GRASS_THIN_CURVE = 0.7;
const float EYE_GRASS_WARM_SAT = 0.05;
const vec3 EYE_GRASS_WARM_FOOT = vec3(0.74, 0.6, 0.5);
const vec3 EYE_GRASS_WARM_TIP = vec3(1.04, 1.0, 0.86);
const float EYE_GRASS_THIN_BAND = 0.15;
const float EYE_GRASS_DESAT = 0.18;
const vec3 EYE_GRASS_FOOT = vec3(0.5, 0.58, 0.62);
const float EYE_GRASS_TIP = 0.88;
const float EYE_GRASS_JITTER = 0.12;
const float EYE_GRASS_TAPER = 0.5;
// The tuft's nearness to the eye (0 to 1, constant over the tuft) and its own key (0 to 1).
varying flat float eye_grass_near;
varying flat float eye_grass_key;


// A tuft's key from its instance origin `xz`, 0 to 1, the same for every vertex of the tuft.
float eye_grass_hash(vec2 xz) {
	return fract(sin(dot(floor(xz * 64.0), vec2(12.9898, 78.233))) * 43758.5453);
}


// The scale a tuft with key `key` keeps at nearness `near`: 1 far from the eye; near it the
// tufts whose key falls under the thinning shrink into their foot and are gone.
float eye_grass_keep(float key, float near) {
	float thin = EYE_GRASS_THIN * pow(near, EYE_GRASS_THIN_CURVE);
	return smoothstep(thin - EYE_GRASS_THIN_BAND, thin, key);
}


// The near grass colour: albedo `a` at height fraction `h` (0 foot, 1 tip) of a tuft with key
// `key` at nearness `near`; `a` itself at nearness 0.
vec3 eye_grass_albedo(vec3 a, float h, float key, float near) {
	float luma = dot(a, vec3(0.2126, 0.7152, 0.0722));
	// Warm (red over green: dry gold, straw) blades keep and gain saturation and glow at the tip;
	// the green ones are calmed and deepened.
	float warm = smoothstep(0.0, 0.15, (a.r - a.g) / max(a.r, 0.01));
	vec3 g = mix(a, vec3(luma), mix(EYE_GRASS_DESAT, -EYE_GRASS_WARM_SAT, warm));
	vec3 foot = mix(EYE_GRASS_FOOT, EYE_GRASS_WARM_FOOT, warm);
	vec3 tip = mix(vec3(EYE_GRASS_TIP), EYE_GRASS_WARM_TIP, warm);
	g *= mix(foot, tip, smoothstep(0.0, 1.0, h));
	g *= 1.0 + EYE_GRASS_JITTER * (fract(key * 7.13 + 0.37) * 2.0 - 1.0);
	return mix(a, max(g, vec3(0.0)), near);
}


void vertex() {
	local_vertex_y = VERTEX.y;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow_scale(MODEL_MATRIX[3].xyz);
	eye_grass_near = 0.0;
	eye_grass_key = 0.0;
	if (eye_grass > 0.0 && blade_height > 0.0
		&& distance(INV_VIEW_MATRIX[3].xyz, canopy_eye.xyz) < CANOPY_EYE_PASS) {
		vec2 origin = MODEL_MATRIX[3].xz;
		eye_grass_near = 1.0 - smoothstep(
			EYE_GRASS_FULL * eye_grass, EYE_GRASS_NONE * eye_grass, distance(origin, canopy_eye.xz));
		eye_grass_key = eye_grass_hash(origin);
		VERTEX *= eye_grass_keep(eye_grass_key, eye_grass_near);
	}
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
	VERTEX += shadow_caster_offset(MODEL_MATRIX, INV_VIEW_MATRIX, IN_SHADOW_PASS);
}


void fragment() {
	NORMAL = two_sided_foliage_normal(NORMAL, FRONT_FACING);
	vec3 pbr_albedo;
	float pbr_alpha;
	float pbr_ao;
	float pbr_roughness;
	float pbr_metallic;
	vec3 pbr_normal_map;

	apply_wind_foliage_pbr(UV, INV_VIEW_MATRIX, NORMAL, VERTEX, VIEW_MATRIX, PROJECTION_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE, local_vertex_y, COLOR.gb,
		pbr_albedo, pbr_alpha, pbr_ao, pbr_roughness, pbr_metallic, pbr_normal_map);
	if (zone_tuft_strength > 0.0) {
		pbr_albedo = zone_tuft_albedo(pbr_albedo, zone_tuft, vec3(zone_mass, zone_mass_h));
	}
	if (eye_grass_near > 0.0) {
		float h = clamp(local_vertex_y / blade_height, 0.0, 1.0);
		pbr_albedo = eye_grass_albedo(pbr_albedo, h, eye_grass_key, eye_grass_near);
		pbr_alpha *= 1.0 - EYE_GRASS_TAPER * eye_grass_near * smoothstep(0.55, 1.0, h);
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
