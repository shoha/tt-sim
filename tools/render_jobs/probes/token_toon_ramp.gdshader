/*
 * Toon probe, approach 1: a per-material swap. TokenToonProbe builds one ShaderMaterial per
 * source BaseMaterial3D of a pack token, copying its albedo (colour, texture, vertex colour),
 * emission, alpha mode and culling, and lights it through a soft three-band ramp: a shadow
 * band tinted toward violet, a mid band, a lit band tinted warm. The bands have soft edges
 * (a few bold soft shapes, not fine noise), and a luminous rim lifts the silhouette.
 *
 * Variants are made by prepending defines (TokenToonProbe._shader_for): MODE_SCISSOR (alpha
 * cutout), MODE_BLEND (alpha blend), CULL_OFF (double-sided). Skinning needs nothing here:
 * the engine skins VERTEX and NORMAL before a shader sees them.
 *
 * This is a design probe (tools/render_jobs/probes), not a shipped look.
 */

shader_type spatial;
#ifdef CULL_OFF
render_mode specular_disabled, cull_disabled;
#else
render_mode specular_disabled;
#endif

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform float alpha_cutoff = 0.5;
uniform float fade = 1.0;

group_uniforms look;
// Light multipliers of the three bands (linear), on the light's colour and energy.
uniform vec3 shade_band : source_color = vec3(0.30, 0.24, 0.52);
uniform vec3 mid_band : source_color = vec3(0.72, 0.66, 0.86);
uniform vec3 lit_band : source_color = vec3(1.18, 1.08, 0.94);
// Where the bands change on the wrapped light term (0..1), and how soft the change is.
uniform vec2 band_edges = vec2(0.14, 0.52);
uniform float band_soft : hint_range(0.01, 0.4) = 0.10;
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
// A little more paint than the photographic source: saturation about the luminance.
uniform float saturation : hint_range(0.5, 1.8) = 1.18;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.35;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec4 c = albedo_color;
	if (use_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (use_vertex_color) {
		vec3 vc = v_color.rgb;
		if (vertex_color_srgb) {
			vc = mix(vc / 12.92, pow((vc + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), vc));
		}
		c.rgb *= vc;
		c.a *= v_color.a;
	}
	float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = max(mix(vec3(lum), c.rgb, saturation), vec3(0.0));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 emit = emission_color;
	if (use_emission_tex) {
		emit *= texture(emission_tex, UV).rgb;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = emit * emission_energy + mix(rim_color, col * 1.6, 0.45) * rim * rim_strength;
#ifdef MODE_SCISSOR
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
#endif
#ifdef MODE_BLEND
	ALPHA = c.a * fade;
#endif
}

void light() {
	float t = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION;
	float b1 = smoothstep(band_edges.x - band_soft, band_edges.x + band_soft, t);
	float b2 = smoothstep(band_edges.y - band_soft, band_edges.y + band_soft, t);
	vec3 tone = mix(mix(shade_band, mid_band, b1), lit_band, b2);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * tone;
}
