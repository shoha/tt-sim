// Avatar token probe: the body pass of a stand-in figure (see probes/avatar.gd).
// Two-band toon ramp whose shadow is a hue shift rather than a darkening toward grey,
// a rim that shows on the side away from the light, no specular. Colour comes from a
// palette atlas with two rows per palette, lit and shadow (Guilty Gear Xrd keeps a
// separate shadow-tint texture): UV.x picks the block ((block + 0.5) / 8), the instance
// uniform palette_row picks the palette, so every avatar shares one material. COLOR.g
// biases the band (0.5 neutral; lower falls into shadow earlier, as Xrd's vertex shading
// threshold does). The engine's ambient is disabled and replaced by the shadow band so
// the dark side keeps its colour. ALBEDO is white and every colour term is applied in
// light().
shader_type spatial;
render_mode cull_back, ambient_light_disabled, specular_disabled;

uniform sampler2D palette : source_color, filter_nearest;
// Palettes in the atlas (it has twice as many rows).
uniform float palette_rows = 4.0;
instance uniform float palette_row = 0.0;
// Where the lit band starts, in N.L; soft is the width of its edge (0 = hard).
uniform float band_threshold = 0.12;
uniform float band_soft = 0.03;
uniform float bias_strength = 0.6;
// The shadow side: shadow_from_atlas 1 takes the atlas's shadow row; 0 computes it from the
// lit colour times shadow_tint (a hue shift, not a grey) at shadow_level brightness, with
// shadow_sat > 1 pushing saturation up.
uniform float shadow_from_atlas = 1.0;
uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 1.20);
uniform float shadow_level = 0.62;
uniform float shadow_sat = 1.15;
// Lit side gain against LIGHT_COLOR (which carries energy * PI).
uniform float light_scale = 0.36;
// The light direction used for the band: the scene sun mixed toward a fixed view-space key
// (x right, y up, z toward the camera), so the band reads whatever the sun's azimuth.
uniform vec3 key_dir = vec3(-0.55, 0.6, 0.6);
uniform float key_mix = 0.5;
// Rim: a hard Fresnel band. rim_side 0 shows it only away from the light, 1 everywhere.
uniform float rim_strength = 0.55;
uniform float rim_power = 2.5;
uniform float rim_threshold = 0.42;
uniform float rim_side = 0.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.75);
// Scene cast shadows (ATTENUATION) push the band by this much in N.L: 0 ignores them, about
// 2 puts the whole figure in shadow colour. 0 looked best: any push brings the soft-shadow
// filter's stipple onto the flat colour blocks.
uniform float scene_shadow_push = 0.0;
// Non-directional lights (omni, spot) add a plain wrapped term at this gain.
uniform float local_light_scale = 0.25;

varying vec3 base_col;
varying vec3 shadow_col;
varying float shade_bias;


void fragment() {
	float h = 2.0 * palette_rows;
	base_col = texture(palette, vec2(UV.x, (2.0 * palette_row + 0.5) / h)).rgb;
	shadow_col = texture(palette, vec2(UV.x, (2.0 * palette_row + 1.5) / h)).rgb;
	shade_bias = (COLOR.g - 0.5) * bias_strength;
	ALBEDO = vec3(1.0);
}


vec3 shadow_colour(vec3 c) {
	vec3 s = c * shadow_tint * shadow_level;
	float luma = dot(s, vec3(0.299, 0.587, 0.114));
	vec3 tinted = max(mix(vec3(luma), s, shadow_sat), vec3(0.0));
	return mix(tinted, shadow_col, shadow_from_atlas);
}


void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 l = normalize(mix(LIGHT, normalize(key_dir), key_mix));
		float ndl = dot(NORMAL, l);
		float in_shadow = 1.0 - step(0.5, ATTENUATION);
		float shade = ndl + shade_bias - in_shadow * scene_shadow_push;
		float band = smoothstep(band_threshold - band_soft, band_threshold + band_soft, shade);
		vec3 colour = mix(shadow_colour(base_col), base_col, band);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		float away = mix(1.0 - band, 1.0, rim_side);
		float rim = step(rim_threshold, fres) * away * rim_strength;
		DIFFUSE_LIGHT += (colour + rim_color * rim) * LIGHT_COLOR * light_scale;
	} else {
		float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
		DIFFUSE_LIGHT += base_col * wrap * ATTENUATION * LIGHT_COLOR * local_light_scale;
	}
}
