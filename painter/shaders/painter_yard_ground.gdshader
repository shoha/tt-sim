shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted yard ground (card painter-buildings-fix2)
 * =================================================
 *
 * A building's worn-earth skirt and path (StructureDressing "ground": draped on the terrain, its
 * vertex alpha fading out from the walls) in the painted look. Classic's long alpha fade read as
 * an airbrushed warm halo round the house, on snow too. Here it is one flat wash of the sheet's
 * path tone whose edge is a brushed, scalloped line where the fade crosses half (a slow and a fine
 * world noise move it), lit in the light's three steps; under winter's snow (`snow`, the sheet's
 * roof-snow) it is mostly gone.
 * The contact pool at a building's walls (card painter-pool-shapes) darkens the wash as it does the
 * ground under it: the same field (PainterOcclusion's occ_map) through the same brushed threshold,
 * so the shade at the walls' foot is not hidden by the wash laid over it. As on the ground (card
 * painter-tree-ground) the pool r is a step below the shade colour and only in the shade, and the
 * seam g at the walls' foot, read the same way down-sun, is a darker line in the sun too (the yard
 * hid it: the cottages' weak wall contact at zoom 16). Off (one uniform branch) until the field is
 * bound.
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd, kind "dressing_ground"); the pool's
 * uniforms by PainterOcclusion (painter/painter_occlusion.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform vec3 ramps[24];
uniform float snow = 0.0;
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
// The wash's opacity inside its edge.
uniform float wash = 0.75;
// The contact field and its tones (painter_ground.gdshader's, set by PainterOcclusion).
uniform sampler2D occ_map : hint_default_black, filter_linear, repeat_disable;
uniform bool occ_present = false;
uniform vec2 occ_origin = vec2(0.0);
uniform float occ_step = 0.5;
uniform vec4 occ_k = vec4(0.0, 0.0, 0.8, 0.3);
uniform vec4 occ_tint = vec4(0.9, 1.0, 0.96, 0.35);
global uniform vec4 foliage_sun;
// painter_ground.gdshader's SHADE_DEEP, SEAM_LIT and SEAM_LEAN_M.
const float SHADE_DEEP = 0.8;
const float SEAM_LIT = 0.6;
const float SEAM_LEAN_M = 0.3;

varying vec3 v_wp;
varying float v_a;

varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;
varying float f_pool;
varying float f_core;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_a = COLOR.a;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 wp = v_wp;
	float edge = v_a + (p_noise(wp * 1.6 + 3.0) - 0.5) * 0.45 + (p_noise(wp * 5.5 + 11.0) - 0.5) * 0.12;
	ALPHA = smoothstep(0.46, 0.52, edge) * wash * (1.0 - clamp(snow * 2.2, 0.0, 1.0) * 0.85);
	float variant = smoothstep(0.35, 0.65, p_noise(wp * 0.9 + 7.0));
	f_shd = mix(ramps[0], ramps[3], variant);
	f_mid = mix(ramps[1], ramps[4], variant);
	f_lit = mix(ramps[2], ramps[5], variant);
	f_wob = p_noise(wp * 1.7 + 5.0);
	f_pool = 0.0;
	f_core = 0.0;
	if (occ_present && (occ_k.x > 0.0 || occ_k.y > 0.0)) {
		float sl = length(foliage_sun.xz);
		vec2 to_sun = sl > 0.01 ? foliage_sun.xz / sl : vec2(0.0);
		vec2 size = vec2(textureSize(occ_map, 0)) * occ_step;
		vec2 s = textureLod(occ_map, (wp.xz + to_sun * SEAM_LEAN_M - occ_origin) / size, 0.0).rg;
		f_pool = smoothstep(0.4, 0.5, s.r + (p_noise(wp * 1.3 + 80.0) - 0.5) * 0.3) * occ_k.x;
		f_core = smoothstep(0.4, 0.5, s.g + (p_noise(wp * 2.7 + 95.0) - 0.5) * 0.3) * occ_k.y;
	}
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(NORMAL), LIGHT) + (f_wob - 0.5) * 0.12;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.01, tone_hi + 0.01, x));
		col = mix(col, f_shd, cast * cast_amount);
		// The contact pool and seam, as the ground's (painter_ground's light()): the pool a step
		// below the shade and only in it, the seam the lit tone darkened in the sun and that step in
		// the shade.
		float shade = max(cast * cast_amount, 1.0 - smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		vec3 deep = mix(f_lit, f_shd, occ_tint.a) * occ_k.z * occ_tint.rgb;
		vec3 deeper = f_shd * occ_k.z * SHADE_DEEP * occ_tint.rgb;
		col = mix(col, deeper, f_pool * shade);
		col = mix(col, mix(deep, deeper, shade), f_core * mix(SEAM_LIT, 1.0, shade));
		DIFFUSE_LIGHT += col;
	}
}
