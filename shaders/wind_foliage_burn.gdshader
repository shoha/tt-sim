shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

// A burning tree (FireSweep's stand-ins): wind_foliage.gdshader, the same sway, PBR, canopy and
// occlusion fades through the same include, plus a burn the fire drives per instance
// (INSTANCE_CUSTOM.x, 0 untouched, rising past 1 as the tree burns). A tree catches in a few
// bold patches, not all at once: each fragment's own moment (`catch_at`) comes from its height
// up the tree and a slow noise about a metre across, so the heat climbs the crown in blotches.
// Past its moment a patch flares hot yellow along the burn's leading edge, then burns on in one
// of three bold patches laid by a second noise: glowing ember red-orange (emission, so it
// burns in shade too), burnt autumn orange and deep red lit by the sun as the leaves were (a
// low ember under it), or char that comes early; every one keeps the leaf's painted light and
// dark, so the crown's shape and light still read. It dims to deep red and goes to charcoal; a
// leaf card then burns away from a glowing edge, leaving the charred trunk and limbs standing.
// Bark never glows, it only chars: a glowing trunk read as a thin orange beam down the tree.
// At 0 it draws exactly as wind_foliage.gdshader, so a stand-in waiting for the front matches
// the tree it replaced.

#include "res://shaders/wind_foliage_include.gdshaderinc"

// The burn's colours, linear. The scene's filmic tonemap shows a low linear value lighter than
// raising it to 1/2.2 does (0.07 shows about 0.37), so each is picked through that curve. The
// hot core (shows about 1, 0.78, 0.3), the ember the patch burns on in (shows about 0.95, 0.36,
// 0.1: at 0.22 green, emission and leaf green together, the crowns burnt yellow-orange like
// autumn leaves), its deep red (shows about 0.8, 0.2, 0.06) in the patches a second, finer
// noise picks (one ember all over read as a flat orange cut-out), and the warm charcoal a
// patch goes to.
const vec3 HOT = vec3(1.6, 0.42, 0.045);
const vec3 EMBER = vec3(1.1, 0.066, 0.004);
const vec3 EMBER_DEEP = vec3(0.43, 0.02, 0.003);
const vec3 CHARCOAL = vec3(0.045, 0.032, 0.03);
// A glowing patch's own colour under its glow, a scorched red-brown: the lit leaf green left
// under the ember tinted it toward yellow.
const vec3 SCORCH = vec3(0.05, 0.012, 0.004);
// The burning leaf's own colour, lit by the sun as the foliage is (so the crown keeps its lit
// flank and its shade side while it burns): an autumn orange and a deep red, times the leaf's
// painted tone (its luminance over TONE_REF, held in TONE_RANGE), so its light and dark cards
// still read. One flat emission over the crown read as an orange cut-out (fire-look-4).
const vec3 BURNT_ORANGE = vec3(0.62, 0.15, 0.018);
const vec3 BURNT_RED = vec3(0.3, 0.04, 0.01);
const float TONE_REF = 0.14;
const vec2 TONE_RANGE = vec2(0.35, 1.5);
// The burn's bold patches (a noise about PATCH_SCALE a metre): above PATCH_EMBER a patch
// glows in full, below PATCH_CHAR it goes to char early (CHAR_EARLY burn units ahead), and
// between them it is burnt leaf with a low ember glow (EMBER_LOW of the full).
const float PATCH_SCALE = 0.8;
const float PATCH_EMBER = 0.58;
const float PATCH_CHAR = 0.38;
const float CHAR_EARLY = 0.3;
const float EMBER_LOW = 0.22;
// The leading edge's share of HOT: in full its gold band was the brightest thing on a crown.
const float LEAD_HOT = 0.7;
// After its moment (in burn units): the glow flares in over GLOW_IN, hot to there and cooling
// to ember by LEAD (so the yellow stays a thin band along the leading edge), holds to
// CHAR_FROM, and the patch chars over CHAR_FROM..CHAR_TO, its glow dimming to deep red; a card
// burns away from GONE_FROM, its edge glowing ember over GONE_EDGE.
const float GLOW_IN = 0.04;
const float LEAD = 0.15;
const float CHAR_FROM = 0.3;
const float CHAR_TO = 0.6;
const float GONE_FROM = 0.45;
const float GONE_EDGE = 0.1;

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
		// The burn's bold patches: ember (glowing), burnt leaf (lit by the sun) and char.
		float patch = noise(burn_local * PATCH_SCALE + vec3(11.0, 4.3, 2.9));
		float ember_patch = smoothstep(PATCH_EMBER - 0.03, PATCH_EMBER + 0.03, patch);
		float char_patch = 1.0 - smoothstep(PATCH_CHAR - 0.03, PATCH_CHAR + 0.03, patch);
		float chars = since + CHAR_EARLY * char_patch;
		float charred = smoothstep(CHAR_FROM, CHAR_TO, chars);
		// The leaf's own painted tone (its light and dark cards), carried into the burn.
		float tone = clamp(dot(pbr_albedo, vec3(0.2126, 0.7152, 0.0722)) / TONE_REF, TONE_RANGE.x, TONE_RANGE.y);
		if (canopy_part != 1) {
			float glow = smoothstep(0.0, GLOW_IN, since) * (1.0 - smoothstep(CHAR_FROM, CHAR_TO + 0.2, chars));
			float lead = 1.0 - smoothstep(GLOW_IN, LEAD, since);
			float flare = smoothstep(0.3, 0.7, noise(burn_local * 1.7 + vec3(7.3, 2.1, 0.0)));
			albedo = mix(albedo, mix(BURNT_RED, BURNT_ORANGE, flare) * tone, glow);
			float strength = mix(EMBER_LOW, 1.0, ember_patch) * (1.0 - 0.7 * char_patch);
			vec3 ember = mix(EMBER_DEEP, EMBER, flare * ember_patch) * strength;
			emission = mix(ember, HOT * LEAD_HOT, lead * (0.4 + 0.6 * ember_patch)) * glow * tone;
		}
		albedo = mix(albedo, CHARCOAL, charred);
		if (canopy_part == 2) {
			float gone = since - GONE_FROM;
			if (gone > GONE_EDGE) {
				pbr_alpha = 0.0;
			} else if (gone > 0.0) {
				// Over what is left of its own glow, so a deep red-orange, not amber.
				emission += EMBER * 0.6 * (1.0 - gone / GONE_EDGE);
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
