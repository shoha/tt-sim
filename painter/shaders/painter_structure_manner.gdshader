shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted structure with procgen's manner data (PROBE, card painter-manner)
 * ======================================================================
 *
 * painter_structure.gdshader (A3b) with the strokes laid along each piece's own frame instead of
 * along the world. PainterMannerMesh writes per vertex the piece's (u, v) metres (UV2) and
 * [u_len, v_len, code, accent] (CUSTOM0; code 1 wall, 2 roof slope, 3 gable end, 4 beam or trim
 * box, 5 door leaf, 6 ridge, 7 thatch tooth, 0 no record: the A3b patterns). `mode`:
 *   0  a plain wash (patches, dabs, eave band, foot): candidate A's surface under its strokes;
 *   1  candidate B: the prototype's stroke families drawn here, from the piece frame: a ruled
 *      line just inside each face edge (eave dark, ridge pale), dry-brush washes along a plaster
 *      wall, short marks in courses on stone, strokes down a thatch slope with course lines,
 *      dashes across tiles, a broad stroke with a light and a dark line along a beam, planks on
 *      a door leaf, strands on a thatch tooth;
 *   2  candidate C: as 1, but a face's strokes come from the building's baked texture (`atlas`,
 *      UV); edges, beams and doors stay procedural;
 *   3  candidate A's stroke quads: UV along and across the stroke, UV2 (value / 2, grain); a
 *      brush edge by discard, the value darkens or lightens the part's own colour.
 * Light, tones and the uniforms the sheet sets are the A3b shader's (PainterBuildings._tone).
 * Marks fade out where a metre is under about twelve pixels (far views draw only the wash).
 *
 * MANAGED BY: PainterMannerHost (painter/buildings/manner_host.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"

uniform int pattern = 0;
uniform int pick = 0;
uniform vec3 ramps[24];
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
uniform float patch_freq = 0.42;
uniform float patch_mix = 0.85;
uniform float dab_freq = 1.1;
uniform float dabs = 0.3;
uniform float dab_wall = 0.45;
uniform float marks = 1.0;
uniform float ink = 0.55;
uniform float contact = 0.4;
uniform float contact_m = 0.8;
uniform float eave = 0.35;
uniform int mode = 1;
uniform sampler2D atlas : hint_default_black, filter_linear_mipmap;
// How strongly the manner's strokes darken and lighten.
uniform float stroke_dark = 1.0;
uniform float stroke_light = 1.0;

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_h;
varying flat int v_tone;
varying vec2 v_fuv;
varying vec4 v_rec;
varying vec2 v_auv;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

int roof_tone(vec3 c, bool woody) {
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	float a = 1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z;
	float b = 0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z;
	float hue = mod(degrees(atan(b, a)) + 360.0, 360.0);
	if (length(vec2(a, b)) < 0.04) {
		return 1;
	}
	if (hue >= 340.0 || hue < 18.0) {
		return 0;
	}
	if (hue < 58.0) {
		return woody ? 2 : 0;
	}
	if (hue < 100.0) {
		return 2;
	}
	return 1;
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_tone = pick > 0 ? roof_tone(COLOR.rgb, pick == 2) : 0;
	v_fuv = UV2;
	v_rec = mode == 3 ? vec4(0.0) : CUSTOM0;
	v_auv = UV;
}

float p_line(float x, float w) {
	float f = fract(x);
	float d = min(f, 1.0 - f);
	float detail = 1.0 - smoothstep(0.25, 0.6, fwidth(x));
	return (1.0 - smoothstep(w * 0.5, w, d)) * detail;
}

// A band `w` metres wide centred `at` metres along x, broken into strokes by the noise.
float p_band(float x, float at, float w) {
	return 1.0 - smoothstep(w * 0.35, w * 0.5, abs(x - at));
}

// Short strokes along x in rows `row` metres high: cells `cell` metres long, `share` of them
// drawn, each tapered and dry. Returns (dark, light) for the cell's own value.
vec2 p_strokes(vec2 f, float row, float cell, float share, float width, float dark_share, float seed) {
	float r = f.y / row;
	float ri = floor(r);
	float x = f.x / cell + p_hash(vec3(ri, seed, 1.0)) * 7.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed));
	float fx = fract(x);
	float fy = fract(r);
	float body = smoothstep(0.0, 0.18, fx) * (1.0 - smoothstep(0.72, 1.0, fx));
	body *= 1.0 - smoothstep(width * 0.3, width * 0.5, abs(fy - 0.5));
	float dry = smoothstep(0.25, 0.45, p_noise(vec3(f.x * 7.0, ri * 3.1, seed)));
	float on = step(1.0 - share, h) * body * mix(0.35, 1.0, dry);
	float is_dark = step(h, 1.0 - share + share * dark_share);
	return vec2(on * is_dark, on * (1.0 - is_dark));
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n = normalize(v_wn);
	vec3 wp = v_wp;
	float pn = mix(p_noise(wp * patch_freq + 7.0), p_noise(wp * patch_freq * 3.3 + 21.0), 0.3);
	float variant = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix);
	float dark = 0.0;
	float light = 0.0;
	float bn = p_noise(wp * dab_freq + 33.0);
	float dab = (pattern >= 5 ? 1.0 : dab_wall) * dabs;
	dark += smoothstep(0.62, 0.72, bn) * dab;
	light += (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = n.y;
	float s = dot(wp.xz, down) / max(up, 0.35);
	float t = dot(wp.xz, across);
	float u = t;
	float h = clamp(v_h, 0.0, 1.0);
	int code = int(v_rec.z + 0.5);
	vec2 f = v_fuv;
	float ul = v_rec.x;
	float vl = v_rec.y;
	float acc = v_rec.w;
	float detail = 1.0 - smoothstep(0.04, 0.09, length(fwidth(f)));
	if (mode == 3) {
		// A stroke quad: tapered ends, a soft side, dry gaps; its value moves the part's colour.
		float along = min(v_auv.x, 1.0 - v_auv.x);
		float grain = f.y;
		float edge = p_noise(vec3(v_auv * vec2(6.0, 2.0), grain * 40.0));
		float mask = smoothstep(0.0, 0.1, along + (edge - 0.5) * 0.08);
		mask *= 1.0 - smoothstep(0.32, 0.5, abs(v_auv.y - 0.5) + (edge - 0.5) * 0.2);
		mask *= mix(0.3, 1.0, smoothstep(0.2, 0.4, p_noise(vec3(v_auv.x * 9.0, v_auv.y * 2.0, grain * 13.0))));
		if (mask < 0.5) {
			discard;
		}
		float value = f.x * 2.0;
		dark += max(1.0 - value, 0.0) * 2.2 * stroke_dark;
		light += max(value - 1.0, 0.0) * 3.0 * stroke_light;
		if (pattern >= 5) {
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
		}
	} else if (code > 0) {
		bool face = code == 1 || code == 3;
		bool roof = code == 2;
		if (roof) {
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h);
		}
		if (face) {
			float hm = h * 16.0;
			dark += contact * (1.0 - smoothstep(0.0, contact_m, hm));
		}
		if (mode > 0 && (face || roof)) {
			// The ruled line just inside each edge, wobbling and broken.
			float wob = (p_noise(vec3(f * 1.4, acc * 9.0)) - 0.5) * 0.06;
			float dx = min(f.x, ul - f.x);
			float dy0 = f.y;
			float dy1 = vl - f.y;
			float de = min(dx, min(dy0, dy1));
			float line = 1.0 - smoothstep(0.018, 0.034, abs(de - 0.075 - wob));
			line *= step(0.22, p_noise(vec3((f.x + f.y) * 1.3, acc * 5.0, 2.0)));
			float at_low = step(dy0, min(dx, dy1));
			float at_high = step(dy1, min(dx, dy0));
			if (roof) {
				dark += line * (0.75 * at_low + 0.45 * (1.0 - at_low - at_high)) * detail;
				light += line * 0.6 * at_high * detail;
			} else {
				dark += line * (0.55 + 0.2 * at_high) * detail;
			}
		}
		if (mode == 2 && (face || roof)) {
			vec4 baked = texture(atlas, v_auv);
			dark += baked.r * 1.5 * stroke_dark;
			light += baked.g * 1.8 * stroke_light;
		} else if (mode == 1 && face) {
			if (pattern == 1) {
				vec2 m = p_strokes(f, 0.3, 0.48, 0.5, 0.6, 0.7, 11.0);
				dark += m.x * 0.5 * detail;
				light += m.y * 0.35 * detail;
			} else if (pattern == 2 || pattern == 3) {
				vec2 g = pattern == 2 ? f : f.yx;
				float sp = pattern == 2 ? 0.3 : 0.24;
				dark += p_line(g.y / sp, 0.12) * step(0.3, p_noise(vec3(g.x * 0.9, floor(g.y / sp), 4.0))) * 0.55;
			} else {
				vec2 m = p_strokes(f, 0.13, 0.7, 0.42, 0.7, 0.3, 3.0);
				dark += m.x * 0.42 * detail;
				light += m.y * 0.42 * detail;
			}
		} else if (mode == 1 && roof) {
			if (pattern == 8) {
				vec2 m = p_strokes(f.yx, 0.075, 0.8, 0.5, 0.7, 0.45, 5.0);
				dark += m.x * 0.45 * detail;
				light += m.y * 0.4 * detail;
				for (int c = 1; c <= 3; c++) {
					float at = vl * 0.25 * float(c) + (p_noise(vec3(f.x * 0.8, float(c), 6.0)) - 0.5) * 0.2;
					float band = p_band(f.y, at, 0.06) * step(0.25, p_noise(vec3(f.x * 1.2, float(c), 8.0)));
					dark += band * 0.5 * detail;
				}
			} else if (pattern == 9) {
				vec2 m = p_strokes(f, 0.25, 0.35, 0.35, 0.8, 0.5, 9.0);
				dark += m.x * 0.35 * detail;
				light += m.y * 0.35 * detail;
			} else {
				float course = pattern == 5 ? 0.42 : (pattern == 6 ? 0.32 : 0.26);
				vec2 m = p_strokes(f + vec2(0.0, course * 0.35), course, 0.45, 0.55, 0.22, 0.82, 7.0);
				dark += m.x * 0.6 * detail;
				light += m.y * 0.45 * detail;
			}
		}
		if (mode > 0 && (code == 4 || code == 6)) {
			// A beam: one broad stroke, a light line and a dark line along it.
			float across_b = vl > 0.0 ? f.y / vl : 0.5;
			light += p_band(across_b, 0.7, 0.22) * 0.55 * smoothstep(0.1, 0.3, p_noise(vec3(f.x * 1.5, acc * 7.0, 1.0)));
			dark += p_band(across_b, 0.28, 0.2) * 0.4;
			variant = clamp(variant + (acc - 0.5) * 0.6, 0.0, 1.0);
		} else if (mode > 0 && code == 5) {
			dark += p_line(f.y / 0.16, 0.12) * 0.6;
			light += smoothstep(0.55, 0.8, p_noise(vec3(f.x * 3.0, f.y * 20.0, 2.0))) * 0.25;
		} else if (code == 7) {
			// A thatch tooth: strands down it, a darker tip.
			dark += p_line(f.x / 0.05, 0.3) * 0.4 + smoothstep(-0.05, -0.25, f.y) * 0.3;
		}
	} else {
		// No record: the A3b patterns, unchanged.
		if (pattern >= 5) {
			float tiled = smoothstep(0.25, 0.5, up);
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h) * tiled;
		} else {
			float hm = h * 16.0;
			dark += contact * (1.0 - smoothstep(0.0, contact_m, hm)) * (1.0 - smoothstep(0.6, 0.9, abs(up)));
			if (pattern == 1 && mode > 0) {
				float r = wp.y / 0.34;
				float row = floor(r);
				float c = u / 0.62 + 0.5 * mod(row, 2.0) + p_hash(vec3(row, 3.0, 1.0)) * 0.3;
				float blk = p_hash(vec3(row, floor(c), 7.0));
				variant = clamp(variant + (blk - 0.5) * 0.8, 0.0, 1.0);
				dark += max(p_line(r, 0.1), p_line(c, 0.06)) * 0.4;
			}
		}
	}
	if (mode != 3) {
		dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	}
	dark = clamp(dark * marks, 0.0, 0.85);
	light = clamp(light * marks, 0.0, 0.8);
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	vec3 deep = shd * 0.82;
	f_shd = mix(mix(shd, deep, dark), mid, light * 0.5);
	f_mid = mix(mix(mid, shd, dark), lit, light * 0.6);
	f_lit = mix(mix(lit, mid, dark), lit * 1.06, light);
	f_n = n;
	f_wob = p_noise(wp * 1.7 + 5.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.12;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.01, tone_hi + 0.01, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
