shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

// A burning tree (FireSweep's stand-ins): wind_foliage.gdshader, the same sway, PBR, canopy and
// occlusion fades through the same include, plus a burn the fire drives per instance
// (INSTANCE_CUSTOM.x, 0 untouched, rising past 1 as the tree burns). A tree catches in a few
// bold patches, not all at once: each fragment's own moment (`catch_at`) comes from its height
// up the tree and a slow noise about a metre across, so the heat climbs the crown in blotches.
// Past its moment a patch glows ember orange (emission, so it burns in shade too), then goes to
// charcoal; a leaf card then burns away from a glowing edge, leaving the charred trunk and limbs
// standing. At 0 it draws exactly as wind_foliage.gdshader, so a stand-in waiting for the front
// matches the tree it replaced.

#include "res://shaders/wind_foliage_include.gdshaderinc"

// Ember orange the glow burns in (shows about 1, 0.45, 0.1: linear colour, picked as the
// colour it should show raised to 2.2; at 0.4 green it burnt white-gold in the first look),
// and the warm charcoal a patch goes to.
const vec3 EMBER = vec3(1.0, 0.17, 0.006);
const vec3 CHARCOAL = vec3(0.045, 0.032, 0.03);
// After its moment (in burn units): the glow swells in over GLOW_IN, holds to CHAR_FROM, and
// the patch chars over CHAR_FROM..CHAR_TO; a card burns away from GONE_FROM, its edge glowing
// over GONE_EDGE.
const float GLOW_IN = 0.12;
const float CHAR_FROM = 0.3;
const float CHAR_TO = 0.6;
const float GONE_FROM = 0.45;
const float GONE_EDGE = 0.1;
// The emission's strength at full glow, and the share of it bark takes.
const float GLOW_ENERGY = 1.3;
const float BARK_GLOW = 0.3;

varying float burn_s;
varying vec3 burn_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise, 0..1, smooth at the scale of one unit of `p`.
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	local_vertex_y = VERTEX.y;
	burn_local = VERTEX;
	burn_s = INSTANCE_CUSTOM.x;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow;
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

	vec3 albedo = pbr_albedo;
	vec3 emission = vec3(0.0);
	if (burn_s > 0.0) {
		float up = clamp(local_vertex_y / max(mesh_height, 0.01), 0.0, 1.0);
		float catch_at = 0.55 * up + 0.45 * noise(burn_local * 0.9 + vec3(3.1, 0.0, 1.7));
		float since = burn_s - catch_at;
		float glow = smoothstep(0.0, GLOW_IN, since) * (1.0 - smoothstep(CHAR_FROM, CHAR_TO + 0.2, since));
		// Bark smoulders rather than blazes: a fully lit trunk read as a thin orange beam.
		glow *= canopy_part == 2 ? 1.0 : BARK_GLOW;
		float charred = smoothstep(CHAR_FROM, CHAR_TO, since);
		albedo = mix(albedo, albedo * 0.35, glow);
		albedo = mix(albedo, CHARCOAL, charred);
		emission = EMBER * glow * GLOW_ENERGY;
		if (canopy_part == 2) {
			float gone = since - GONE_FROM;
			if (gone > GONE_EDGE) {
				pbr_alpha = 0.0;
			} else if (gone > 0.0) {
				emission += EMBER * GLOW_ENERGY * (1.0 - gone / GONE_EDGE);
			}
		}
		pbr_roughness = mix(pbr_roughness, 1.0, charred);
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ALPHA = pbr_alpha;
	AO = pbr_ao;
	ROUGHNESS = pbr_roughness;
	METALLIC = pbr_metallic;
	SPECULAR = specular_reflectance;
	BACKLIGHT = vec3(backlight);
	if (has_normal_texture) {
		NORMAL_MAP = pbr_normal_map;
		NORMAL_MAP_DEPTH = 1.0;
	}

	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	ALPHA_ANTIALIASING_EDGE = alpha_scissor_threshold * 0.5;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
}
