/*
 * Avatar figure shader body, shared by avatar_figure.gdshader (closed parts, back faces
 * culled) and avatar_figure_double_sided.gdshader (open cards); the model is documented in
 * avatar_figure.gdshader's header. Each including shader declares its own render_mode.
 */

// The scene's ambient (LevelEnvironmentManager: ambient_light_color * ambient_light_energy,
// as stored, i.e. sRGB-encoded values).
global uniform vec3 figure_ambient;

// The figure's palette (AvatarPalette): 8 slot columns, 64 rows, highlight at the top.
uniform sampler2D palette : source_color, filter_linear, repeat_disable;
// The part's painted overlay on UV2, composited by its alpha.
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_detail = false;
// Mip bias for the detail: below 0 keeps the ink crisper at close zoom while the mipmaps
// (AvatarKit builds them) still keep it from aliasing at home zoom.
uniform float detail_mip_bias : hint_range(-2.0, 1.0) = -0.5;

// Face (head parts only): face_rect in UV2 terms (u0, v0, u1, v1), and per kind in
// composition order (marks, mouths, eyes, brows) the chosen cell's top-left in the sheet.
uniform bool has_face = false;
uniform vec4 face_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 face_cell_size = vec2(0.142857, 0.25);
uniform vec2 face_cells[4];
// Sheet and mask are read raw: the sheet's value is the palette v where the mask says so.
uniform sampler2D face_sheet : filter_linear_mipmap, repeat_disable;
uniform sampler2D face_mask : filter_linear_mipmap, repeat_disable;

// Look parameters (the world-lighting pass, 2026-10-07: figures take the scene's light as the
// terrain and foliage do, keeping a fifth of the paint as painted so they still read).
// The light response used: max(COLOR_0.R, light_floor) off the face, face_light on it.
// figurine's per-vertex response (face 0, hair 0.25, cloth 0.3, skin 0.4) left skin about 78 %
// and faces fully self-lit, which read as figures glowing in the canopy's shade; the floor of
// 1.0 hands every pixel but the face the same share, and the face keeps half its paint as
// painted so expressions read in any light.
uniform float light_floor : hint_range(0.0, 1.0) = 1.0;
uniform float face_light : hint_range(0.0, 1.0) = 0.5;
// The share of the paint handed to the light at a response of 1 (figurine's Blender
// material: 0.55); the rest shows as painted, tinted by the scene's ambient.
uniform float emission_drop : hint_range(0.0, 1.0) = 0.8;
// Gain of the soft light term (sun and lamps, per unit of light energy) on that share.
uniform float light_strength : hint_range(0.0, 3.0) = 1.0;
// Wrap of the soft light: 0 is Lambert, 1 lights the far side at half.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.25;
// The engine's ambient (the environment's sky or colour, with SSAO) on the handed share, as
// the terrain takes it (written as AO, which scales indirect light only).
uniform float scene_ambient : hint_range(0.0, 1.0) = 1.0;
// A flat ambient stand-in on the handed share (the first pass's, before scene_ambient); 0
// leaves the engine's ambient alone.
uniform float ambient_fill : hint_range(0.0, 2.0) = 0.0;
// How far the scene's ambient *level* darkens the whole figure (0 none, 1 fully), and how
// far its *hue* tints it. The two are separate because a figure in sun takes only a hint of
// the sky's colour (the first pass mixed the hue at 0.6 and the forest's blue sky turned
// warm skin pale and pinkish), while the level should follow a dark scene closely.
uniform float ambient_mix : hint_range(0.0, 1.0) = 0.8;
uniform float ambient_hue_mix : hint_range(0.0, 1.0) = 0.35;
// The ambient level that reads as neutral (sRGB luminance; the default environment's 0.22).
uniform float ambient_reference = 0.22;
// The darkest the ambient may take a figure (dungeon, night), so a token stays readable.
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.2;
// In shade: the sun's share of the light term removed, and the paint read from the palette's
// own shadow end: each slot is sampled `shade_drop` further down its gradient (toward its
// hue-shifted shadow colour, never grey), and the detail and face pixels over it darken by
// the same per-channel ratio. (The first pass tinted everything by one cool colour, which
// turned skin lavender under the canopy.)
uniform float shadow_strength : hint_range(0.0, 1.0) = 1.0;
uniform float shade_drop : hint_range(0.0, 1.0) = 0.35;

// Compensation for the scene's tonemapper (Filmic on every preset but one; with its white at
// 1.0 it lifts an sRGB midtone of 0.5 to 0.62 and compresses the brightest channel most, so
// paint reads lifted and desaturated): the world's painted colours were authored through it
// and the palette's were not, so the paint is darkened by this gamma and its saturation
// raised a little before the tonemapper sees it. 1.0 and 1.0 pass the palette through as is.
uniform float paint_contrast : hint_range(0.5, 2.5) = 1.15;
uniform float paint_saturation : hint_range(0.0, 2.0) = 1.1;

// Per figure, set from the CPU (AvatarKit.set_shade, AvatarKit.set_hidden_fade).
instance uniform float shade = 0.0;
instance uniform float hidden_fade = 0.0;
// The builder's preview (AvatarBuilderPreview) stands its figure in the default
// environment's ambient, whatever level is open: rgb replaces figure_ambient when a > 0.5.
instance uniform vec4 ambient_override = vec4(0.0);

varying float v_light;
varying float v_shade;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Palette colour (linear) of a slot column at palette v (0 shadow .. 1 highlight).
vec3 palette_at(float slot, float v) {
	return texture(palette, vec2((slot + 0.5) / 8.0, 1.0 - clamp(v, 0.0, 1.0))).rgb;
}

vec3 ambient_tint() {
	vec3 a = max(ambient_override.a > 0.5 ? ambient_override.rgb : figure_ambient, vec3(1e-4));
	float lum = dot(a, vec3(0.2126, 0.7152, 0.0722));
	vec3 hue = a / lum;
	float level = clamp(lum / ambient_reference, ambient_floor, 1.0);
	return mix(vec3(1.0), hue, ambient_hue_mix) * mix(1.0, level, ambient_mix);
}

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void vertex() {
	v_light = COLOR.r;
	v_shade = shade;
}

void fragment() {
	if (hidden_fade > 0.0 && bayer4(FRAGCOORD.xy) < hidden_fade) {
		discard;
	}
	// Palette: snap u to the column centre so no filtering crosses columns. UV.y runs 0 at
	// the highlight (top) row to 1 at the shadow row, so shade reads further down.
	vec2 puv = vec2((floor(UV.x * 8.0) + 0.5) / 8.0, UV.y);
	vec3 col = texture(palette, puv).rgb;
	vec3 shaded = texture(palette, vec2(puv.x, min(puv.y + shade_drop, 1.0 - 0.5 / 64.0))).rgb;
	vec3 shade_ratio = mix(vec3(1.0), clamp(shaded / max(col, vec3(1e-3)), 0.0, 1.5), v_shade);
	if (has_detail) {
		vec4 d = texture(detail, UV2, detail_mip_bias);
		col = mix(col, d.rgb, d.a);
	}
	float face = 0.0;
	if (has_face) {
		vec2 f = (UV2 - face_rect.xy) / (face_rect.zw - face_rect.xy);
		if (f.x >= 0.0 && f.x <= 1.0 && f.y >= 0.0 && f.y <= 1.0) {
			for (int k = 0; k < 4; k++) {
				vec2 suv = face_cells[k] + f * face_cell_size;
				vec4 cell = texture(face_sheet, suv);
				vec3 mask = texture(face_mask, suv).rgb;
				vec3 c = srgb_to_linear(cell.rgb);
				c = mix(c, palette_at(2.0, cell.r), mask.r);
				c = mix(c, palette_at(1.0, cell.r), mask.g);
				col = mix(col, c, cell.a);
				face = max(face, cell.a);
			}
		}
	}
	float l = mix(max(v_light, light_floor), face_light, face);
	// Shade from the palette, then the tonemapper compensation (gamma, then saturation).
	col *= shade_ratio;
	col = pow(max(col, vec3(0.0)), vec3(paint_contrast));
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(lum), col, paint_saturation), vec3(0.0));
	vec3 tint = ambient_tint();
	// The painted share shows as is (tinted); the handed share takes the scene's ambient and
	// the light() term like the terrain, so a lit side reads brighter than the paint and a
	// side in shade or turned away takes the sky's or the room's colour.
	ALBEDO = col * l * emission_drop;
	EMISSION = (col * (1.0 - emission_drop * l) + ALBEDO * ambient_fill) * tint;
	AO = scene_ambient;
	// No reflections: the paint is matte (specular_disabled covers direct light only).
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float soft = clamp((n_dot_l + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	float gate = LIGHT_IS_DIRECTIONAL ? (1.0 - shadow_strength * v_shade) : ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * soft * gate * light_strength;
}
