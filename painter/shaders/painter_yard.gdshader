shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted yard planting (card painter-buildings-fix2)
 * ===================================================
 *
 * A building's yard props (StructureDressing "props": shrubs, flower beds, tufts, boulders,
 * stepping stones, planters, a woodpile; one vertex-coloured soup, faceted) in the painted look,
 * instead of Classic's saturated vertex colours. Each vertex takes one of four sheet ramps by its
 * Classic colour (yard_tone: a green the leaf, a grey the stone, a dull brown the timber, any
 * other paint the rose flowers), so winter and grimdark tone it as they tone the trees. The
 * crown hand, cheaply: a slow world noise turns the normal inside each shape, so the light's
 * three steps break a faceted blob into a few soft lobes, their edges moved by a finer noise
 * (scalloped, never ruled); a lighter or darker variant in broad patches. In winter (`snow`, the
 * sheet's roof-snow) what faces up wears the roof snow's ramp in scalloped caps.
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd, kind "dressing_props").
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"

uniform vec3 ramps[24];
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
// How far the lobe noise turns the normal, and its size (1/m).
uniform float lobe = 1.1;
uniform float lobe_freq = 3.2;

varying vec3 v_wp;
varying vec3 v_wn;
varying flat int v_tone;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

// The ramp a yard paint (linear) takes: 0 leaf, 1 stone, 2 timber, 3 flowers.
int yard_tone(vec3 c) {
	vec2 ab = paint_ab(c);
	float chroma = length(ab);
	float hue = mod(degrees(atan(ab.y, ab.x)) + 360.0, 360.0);
	if (chroma < 0.035) {
		return 1;
	}
	if (hue >= 105.0 && hue < 200.0) {
		return 0;
	}
	if (hue >= 40.0 && hue < 105.0 && chroma < 0.12) {
		return 2;
	}
	return 3;
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// Classic stores the paint as sRGB (vertex_color_is_srgb).
	v_tone = yard_tone(pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2)));
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n = normalize(v_wn) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 wp = v_wp;
	vec3 q = wp * lobe_freq;
	vec3 turn = vec3(p_noise(q + 1.0), p_noise(q + 17.0), p_noise(q + 31.0)) - 0.5;
	vec3 ln = normalize(n + turn * lobe);
	float variant = smoothstep(0.35, 0.65, p_noise(wp * 1.3 + 7.0));
	float cover = 0.0;
	if (snow > 0.0 && v_tone != 3) {
		float cap = ln.y + (p_noise(wp * 4.0 + 9.0) - 0.5) * 0.5;
		cover = smoothstep(0.55, 0.62, cap) * clamp(snow * 2.0, 0.0, 1.0);
	}
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	f_shd = mix(shd, snow_ramp[0], cover);
	f_mid = mix(mid, snow_ramp[1], cover);
	f_lit = mix(lit, snow_ramp[2], cover);
	f_n = ln;
	f_wob = p_noise(wp * 5.0 + 5.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.4, 0.6, ATTENUATION + (f_wob - 0.5) * 0.3);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.2;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.03, tone_lo + 0.03, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.03, tone_hi + 0.03, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
