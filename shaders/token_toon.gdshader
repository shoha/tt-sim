/*
 * The painted look of a pack token (TokenToon, Settings > Graphics > "Token shading"). One
 * ShaderMaterial per source BaseMaterial3D of a pack token's mesh: the source's albedo (colour,
 * texture, vertex colour), emission, alpha mode and culling are kept, and the lighting is
 * replaced by three soft bands, so photographic PBR packs, chunky vertex-colour art and user
 * imports read as one painted family beside the avatar kit and the painted plants.
 *
 * - Bands. The wrapped light term (NdotL, with the cast shadow folded in) goes through two soft
 *   steps: shade, mid, lit. The lit band is a gain of 0.92 on the light (1.05 and 1.18 were
 *   tried: the sun hits a top face at about 0.7 of full, so a flat 1.05 washed the bear from tan
 *   to peach and the cutout leaves to lime), and the albedo passes a luminance knee first (hue
 *   kept), so a pale model stays pale instead of clipping to white in sun.
 * - Shade tint, per source. The shade band is darker AND shifted: a violet for a warm albedo, a
 *   deeper blue-indigo for a cool one, scaled by how saturated the albedo is (a grey-blue stays
 *   blue and light, never a heavy violet; a saturated orange gets a clear violet). It is
 *   added through SPECULAR_LIGHT, which the engine adds after the albedo multiply: a plain
 *   multiplier cannot put blue into an orange whose blue channel is near zero. The tint is read
 *   from the fragment's own ALBEDO, so a uniform material gets its average albedo's tint and a
 *   textured one gets the tint of the colour under each fragment (no seams).
 * - Rim. A light, warm rim, weaker on pale surfaces.
 *
 * Variants are made by prepending defines (TokenToon builds them once, immutable): MODE_SCISSOR
 * (alpha cutout), MODE_BLEND (alpha blend, with the per-mesh `fade` instance uniform the GM-hidden
 * 40 percent state drives), CULL_OFF (double-sided). Skinning needs nothing here: the engine skins
 * VERTEX and NORMAL before a shader sees them.
 */

shader_type spatial;
#ifdef CULL_OFF
render_mode cull_disabled;
#endif

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool use_vertex_color = false;
uniform bool vertex_color_srgb = false;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform float alpha_cutoff = 0.5;
#ifdef MODE_BLEND
// The GM-hidden token's alpha, set per mesh instance (the material is shared by every token that
// shares its source).
instance uniform float fade = 1.0;
#endif

group_uniforms look;
// Gains on the light's colour and energy for the three bands.
uniform float shade_gain : hint_range(0.0, 1.0) = 0.38;
uniform float mid_gain : hint_range(0.0, 1.2) = 0.70;
uniform float lit_gain : hint_range(0.5, 1.5) = 0.92;
// Where the bands change on the wrapped light term (0..1), and how soft the change is.
uniform vec2 band_edges = vec2(0.16, 0.54);
uniform float band_soft : hint_range(0.01, 0.4) = 0.12;
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
// A little more paint than the photographic source: saturation about the luminance.
uniform float saturation : hint_range(0.5, 1.8) = 1.10;
// Albedo luminance above the knee is compressed (hue kept), so pale models do not clip.
uniform float knee : hint_range(0.3, 1.0) = 0.66;
// The shade tint (linear colours, unit-ish, scaled by the albedo's luminance), its strength, and
// the share of it a mid-band pixel gets.
uniform vec3 warm_shade = vec3(0.50, 0.26, 0.92);
uniform vec3 cool_shade = vec3(0.14, 0.24, 0.90);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.32;
uniform float mid_tint : hint_range(0.0, 1.0) = 0.20;
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.24;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec4 c = albedo_color;
	if (use_tex) {
		c *= texture(albedo_tex, UV * uv1_scale.xy + uv1_offset.xy);
	}
	if (use_vertex_color) {
		vec3 vc = v_color.rgb;
		if (vertex_color_srgb) {
			vc = mix(vc / 12.92, pow((vc + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), vc));
		}
		c.rgb *= vc;
		c.a *= v_color.a;
	}
	float lum = dot(c.rgb, LUMA);
	vec3 col = max(mix(vec3(lum), c.rgb, saturation), vec3(0.0));
	// Luminance knee: compress the top of the range, keeping the hue.
	float l = max(dot(col, LUMA), 1e-4);
	float kneed = l <= knee ? l : knee + (1.0 - knee) * (1.0 - exp(-(l - knee) / (1.0 - knee)));
	col *= kneed / l;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 emit = emission_color;
	if (use_emission_tex) {
		emit *= texture(emission_tex, UV).rgb;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pale = clamp(kneed, 0.0, 1.0);
	EMISSION = emit * emission_energy + mix(rim_color, col * 1.6, 0.45) * rim * rim_strength * mix(1.0, 0.45, pale);
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
	float w_shade = 1.0 - b1;
	float w_mid = b1 * (1.0 - b2);
	vec3 light_energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += light_energy * (shade_gain * w_shade + mid_gain * w_mid + lit_gain * b2);

	// The shade tint from the albedo under this fragment: violet for warm, indigo for cool, as
	// strong as the albedo is saturated (a floor keeps a near-white one from going grey).
	vec3 a = ALBEDO;
	float mx = max(a.r, max(a.g, a.b));
	float sat = (mx - min(a.r, min(a.g, a.b))) / max(mx, 1e-3);
	float warm = clamp((a.r - a.b) / max(mx, 0.05), -1.0, 1.0);
	vec3 hue = mix(cool_shade, warm_shade, smoothstep(-0.25, 0.35, warm));
	float lum = dot(a, LUMA);
	vec3 tint = hue * lum * tint_strength * mix(0.25, 1.0, sat);
	SPECULAR_LIGHT += light_energy * tint * (w_shade + mid_tint * w_mid);
}
