shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted structure with procgen's manner data (the hand-drawn manner, the Painted default)
 * =======================================================================================
 *
 * painter_structure.gdshader (A3b) with the strokes laid along each piece's own frame instead of
 * along the world. PainterMannerMesh writes per vertex the piece's (u, v) metres (UV2) and
 * [u_len, v_len, code, accent] (CUSTOM0; code 1 wall, 2 roof slope, 3 gable end, 4 beam or trim
 * box, 5 door leaf, 6 ridge, 7 thatch tooth, 0 no record: the A3b patterns). The prototype's
 * stroke families (spike_built3), drawn from the piece frame:
 *   ruled lines just inside each face edge, at least about two pixels wide: the eave dark, the
 *   verges and the ridge pale (the prototype's ruled verge), a wall's corners dark;
 *   a plaster wall: a few broad soft washes, lighter or darker, each its own length and height;
 *   a stone wall: broad dry-brush marks per course, a broken course line, a few ticks;
 *   a thatch slope: strokes down the slope with course lines; tiles, slates and shingles: dashes
 *   under each course;
 *   a beam (widened past its recipe width by the mesh): a broad stroke, a light and a dark line
 *   along it and a dark brush rim broken by the dry brush;
 *   a door: plank seams, a wandering grain, a brace stroke, darker at the head;
 *   a thatch tooth: strands and a darker tip.
 * A door or shutter takes the timber ramp, or the clay, turf or slate accent by its paint
 * (pick 3); a roof can lie under snow (`snow`, winter). Light, tones and the uniforms the sheet
 * sets are the A3b shader's (PainterBuildings._tone). Marks fade out with their pixel footprint
 * (far views draw only the wash).
 *
 * MANAGED BY: PainterMannerHost (painter/buildings/manner_host.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"

uniform int pattern = 0;
uniform int pick = 0;
uniform vec3 ramps[24];
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
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

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_h;
varying flat int v_tone;
varying vec2 v_fuv;
varying vec4 v_rec;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_tone = tone_of(pick, COLOR.rgb);
	v_fuv = UV2;
	v_rec = CUSTOM0;
}

float p_line(float x, float w) {
	float f = fract(x);
	float d = min(f, 1.0 - f);
	float detail = 1.0 - smoothstep(0.25, 0.6, fwidth(x));
	return (1.0 - smoothstep(w * 0.5, w, d)) * detail;
}

// A band `w` metres wide centred `at` metres along x.
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

// Broad brush washes along x in rows `row` metres high, one per `cell` metres at most and
// `share` of the cells drawn: each its own length (45 to 95 % of its cell), height in the row
// and thickness (`thick` to twice it, a share of the row), tapered, dragged dry along x.
// Returns (dark, light), `dark_share` of the washes dark.
vec2 p_wash(vec2 f, float row, float cell, float share, float thick, float dark_share, float seed) {
	float r = f.y / row;
	float ri = floor(r);
	float x = f.x / cell + p_hash(vec3(ri, seed, 1.0)) * 7.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed));
	float len = mix(0.45, 0.95, p_hash(vec3(ri, ci, seed + 1.7)));
	float start = (1.0 - len) * p_hash(vec3(ri, ci, seed + 3.1));
	float along = (fract(x) - start) / len;
	float body = smoothstep(0.0, 0.14, along) * (1.0 - smoothstep(0.7, 1.0, along));
	float centre = 0.5 + (p_hash(vec3(ri, ci, seed + 5.3)) - 0.5) * 0.35;
	float th = thick * mix(1.0, 2.0, p_hash(vec3(ri, ci, seed + 7.9)));
	float across = abs(fract(r) - centre) / th;
	body *= 1.0 - smoothstep(0.3, 0.5, across + (p_noise(vec3(f.x * 2.3, ri, seed)) - 0.5) * 0.2);
	float dry = smoothstep(0.2, 0.55, p_noise(vec3(f.x * 4.0, f.y * 16.0, seed)));
	float on = step(1.0 - share, h) * body * mix(0.25, 1.0, dry);
	float is_dark = step(p_hash(vec3(ri, ci, seed + 9.4)), dark_share);
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
	// A slate's dark dabs read as blotches up close: a lighter share of them.
	dark += smoothstep(0.62, 0.72, bn) * dab * (pattern == 6 ? 0.35 : 1.0);
	light += (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = n.y;
	float u = dot(wp.xz, across);
	float h = clamp(v_h, 0.0, 1.0);
	int code = int(v_rec.z + 0.5);
	vec2 f = v_fuv;
	float ul = v_rec.x;
	float vl = v_rec.y;
	float acc = v_rec.w;
	// A metre's pixel footprint on the piece: fine marks fade from 4 cm a pixel, broad ones from
	// 8 cm, the ruled lines from 10 cm.
	float fw = length(fwidth(f));
	float detail = 1.0 - smoothstep(0.04, 0.09, fw);
	float broad = 1.0 - smoothstep(0.08, 0.16, fw);
	bool roofy = pattern >= 5;
	if (code > 0) {
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
		if (face || roof) {
			// The ruled line just inside each edge, wobbling and broken, never under about two
			// pixels wide or inset less than three.
			float lw = max(0.02, fw * 1.1);
			float inset = max(0.07, fw * 3.0);
			float wob = (p_noise(vec3(f * 1.4, acc * 9.0)) - 0.5) * 0.06;
			float dx = min(f.x, ul - f.x);
			float dy0 = f.y;
			float dy1 = vl - f.y;
			float de = min(dx, min(dy0, dy1));
			float line = 1.0 - smoothstep(lw, lw + max(0.012, fw), abs(de - inset - wob));
			line *= step(0.2, p_noise(vec3((f.x + f.y) * 1.1, acc * 5.0, 2.0)));
			line *= 1.0 - smoothstep(0.1, 0.2, fw);
			float at_low = step(dy0, min(dx, dy1));
			float at_high = step(dy1, min(dx, dy0));
			float at_side = 1.0 - at_low - at_high;
			if (roof) {
				dark += line * 0.9 * at_low;
				light += line * (0.75 * at_high + 0.6 * at_side);
			} else if (code == 3) {
				light += line * 0.55 * (1.0 - at_low);
				dark += line * 0.5 * at_low;
			} else {
				dark += line * 0.45;
			}
		}
		if (face) {
			if (pattern == 1) {
				// Stone: a broad dry mark or two per course, a broken course line, a few ticks.
				vec2 m = p_wash(f, 0.34, 0.75, 0.55, 0.28, 0.55, 11.0);
				dark += m.x * 0.6 * broad;
				light += m.y * 0.5 * broad;
				float course = p_line(f.y / 0.34, 0.07) * step(0.45, p_noise(vec3(f.x * 1.3, floor(f.y / 0.34), 4.0)));
				dark += course * 0.45 * detail;
				float tick = p_line(f.x / 0.55 + p_hash(vec3(floor(f.y / 0.34), 2.0, 5.0)) * 3.0, 0.035);
				dark += tick * step(0.7, p_hash(vec3(floor(f.y / 0.34), floor(f.x / 0.55), 6.0))) * 0.35 * detail;
			} else if (pattern == 2 || pattern == 3) {
				vec2 g = pattern == 2 ? f : f.yx;
				float sp = pattern == 2 ? 0.3 : 0.24;
				dark += p_line(g.y / sp, 0.12) * step(0.3, p_noise(vec3(g.x * 0.9, floor(g.y / sp), 4.0))) * 0.55;
			} else {
				// Plaster: a few broad soft washes, mostly lighter, each its own size.
				vec2 m = p_wash(f, 0.6, 1.7, 0.32, 0.22, 0.35, 3.0);
				dark += m.x * 0.22 * broad;
				light += m.y * 0.3 * broad;
			}
		} else if (roof) {
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
		if (code == 4 || code == 6) {
			// A beam: one broad stroke, a light and a dark line along it, and a dark brush rim
			// where the mesh widened it, dragged dry so it breaks.
			float across_b = vl > 0.0 ? f.y / vl : 0.5;
			light += p_band(across_b, 0.66, 0.22) * 0.5 * smoothstep(0.1, 0.3, p_noise(vec3(f.x * 1.5, acc * 7.0, 1.0)));
			dark += p_band(across_b, 0.3, 0.18) * 0.35;
			float rim = min(across_b, 1.0 - across_b) + (p_noise(vec3(f.x * 2.6, acc * 3.0, 9.0)) - 0.5) * 0.12;
			dark += (1.0 - smoothstep(0.02, 0.1, rim)) * 0.5 * (code == 4 ? 1.0 : 0.0);
			variant = clamp(variant + (acc - 0.5) * 0.6, 0.0, 1.0);
		} else if (code == 5) {
			// A door: plank seams, a wandering grain, one brace stroke, a darker head.
			float x = f.y + sin(f.x * 4.0 + acc * 20.0) * 0.012;
			dark += p_line(f.y / 0.16, 0.12) * 0.5;
			dark += p_line(x / 0.045, 0.18) * 0.22 * detail;
			float diag = ul > 0.0 && vl > 0.0 ? f.y / vl - f.x / ul : 1.0;
			dark += p_band(diag, 0.0, 0.07) * 0.35 * step(0.3, p_noise(vec3(f.x * 3.0, acc, 3.0)));
			dark += smoothstep(0.7, 1.0, ul > 0.0 ? f.x / ul : 0.0) * 0.3;
		} else if (code == 7) {
			// A thatch tooth: strands down it, a darker tip.
			dark += p_line(f.x / 0.05, 0.3) * 0.4 + smoothstep(-0.05, -0.25, f.y) * 0.3;
		}
		roofy = roof || code == 6 || code == 7;
	} else {
		// No record: the A3b patterns, unchanged.
		if (pattern >= 5) {
			float tiled = smoothstep(0.25, 0.5, up);
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h) * tiled;
		} else {
			float hm = h * 16.0;
			dark += contact * (1.0 - smoothstep(0.0, contact_m, hm)) * (1.0 - smoothstep(0.6, 0.9, abs(up)));
			if (pattern == 1) {
				float r = wp.y / 0.34;
				float row = floor(r);
				float c = u / 0.62 + 0.5 * mod(row, 2.0) + p_hash(vec3(row, 3.0, 1.0)) * 0.3;
				float blk = p_hash(vec3(row, floor(c), 7.0));
				variant = clamp(variant + (blk - 0.5) * 0.8, 0.0, 1.0);
				dark += max(p_line(r, 0.1), p_line(c, 0.06)) * 0.4;
			}
		}
	}
	dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	float cover = roofy ? snow_cover(snow, wp, up, h) : 0.0;
	dark = clamp(dark * marks * (1.0 - cover * 0.85), 0.0, 0.85);
	light = clamp(light * marks * (1.0 - cover * 0.85), 0.0, 0.8);
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	shd = mix(shd, snow_ramp[0], cover);
	mid = mix(mid, snow_ramp[1], cover);
	lit = mix(lit, snow_ramp[2], cover);
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
