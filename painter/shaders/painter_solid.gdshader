shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted solid (a stand-in for a still scatter asset's own material under the Painted look)
 * ========================================================================================
 *
 * The selector light (painter_selector.gdshaderinc) on scatter that does not sway: rocks,
 * logs, stumps, litter. Such an asset keeps its imported material in Classic, so it has no wind
 * uniforms; its arrival drops it in through its instance transforms (ScatterArrival), which
 * any material follows. `cutout` keeps a cut-out asset's silhouette from its texture's alpha.
 *
 * MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd).
 */

#include "res://painter/shaders/painter_selector.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform bool cutout = false;
uniform float alpha_scissor = 0.5;

varying vec3 v_wp;
varying vec3 v_wn;
varying flat vec3 v_o;
varying float v_h;
varying flat float v_scale;

void vertex() {
	v_h = VERTEX.y / max(selector_height, 0.01);
	VERTEX *= selector_keep(MODEL_MATRIX[3].xyz, IN_SHADOW_PASS);
	v_o = MODEL_MATRIX[3].xyz;
	v_scale = length(MODEL_MATRIX[1].xyz);
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (cutout) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n;
	float variant;
	float mul;
	float wob;
	float petal;
	float snow;
	selector_fragment(v_wp, v_wn, v_o, v_scale, v_h, tex, n, variant, mul, wob, petal, snow);
	f_n = n;
	f_variant = variant;
	f_mul = mul;
	f_wob = wob;
	f_accent = petal;
	f_frost = snow;
}
