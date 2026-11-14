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
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd, kind "dressing_ground").
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform vec3 ramps[24];
uniform float snow = 0.0;
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
// The wash's opacity inside its edge.
uniform float wash = 0.75;

varying vec3 v_wp;
varying float v_a;

varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

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
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(NORMAL), LIGHT) + (f_wob - 0.5) * 0.12;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.01, tone_hi + 0.01, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
