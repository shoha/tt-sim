shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted structure with procgen's manner data (the hand-drawn manner, the Painted default)
 * =======================================================================================
 *
 * painter_structure.gdshader (A3b) with the strokes laid along each piece's own frame instead of
 * along the world. PainterMannerMesh writes per vertex the piece's (u, v) metres (UV2) and
 * [u_len, v_len, code, accent] (CUSTOM0; code 1 wall, 2 roof slope, 3 gable end, 4 beam or trim
 * box, 5 door leaf, 6 ridge, 7 thatch tooth, 8 flat roof, 0 no record: the A3b patterns; a
 * wall's course in metres in the code's fraction, a hip face's taper in the accent's whole
 * part). The prototype's stroke families (spike_built3), drawn from the piece frame:
 *   ruled lines just inside each face edge, at least about two pixels wide: the eave dark, the
 *   verges and the ridge pale (the prototype's ruled verge), a wall's corners dark;
 *   a plaster wall: broad dry-brush washes, lighter or darker, each its own length and height,
 *   over a slow drift of value across the wall;
 *   a stone wall: dry-brushed stones (p_stones), crisp and irregular, each its own tone, with a
 *   few dark joint strokes under the courses and beside the stones;
 *   a thatch slope: strokes down the slope with course lines; tiles, slates and shingles: dashes
 *   under each course;
 *   a beam (widened past its recipe width by the mesh): a broad stroke, a light and a dark line
 *   along it and a dark brush rim broken by the dry brush;
 *   a door: plank seams, a wandering grain, a brace stroke, darker at the head;
 *   a thatch tooth: strands and a darker tip.
 * A door or shutter takes the timber ramp, or the clay, turf or slate accent by its paint
 * (pick 3). Winter (`snow` above 0, the sheet's roof-snow, cards painter-roof-snow,
 * painter-buildings-fix and -fix2): a roof slope lies under a blanket mesh (code 10,
 * PainterMannerBlanket: thick in the middle, soft at the edges, its normals carry its shape)
 * drawn in the snow's ramp with broad brush washes, lighter and bluer, a soft light and a blue
 * shade under the eave's lip (the code's fraction); a roof piece under it hides its own marks
 * whole. The other snow strips (code 9, PainterMannerSnow: chimney cushions and collars, sill
 * pads, the lips and caps of a roof without a blanket) take the snow's ramp whole, lit by their
 * own normals, with a slightly darker foot and a blue underside. The light's wobble (and so a light edge or
 * a tree's shadow) follows each piece's strokes: along the courses on a wall, down the fall line
 * on a roof. Light, tones and the uniforms the sheet sets are the A3b shader's
 * (PainterBuildings._tone). Marks fade out with their pixel footprint (far views draw only the
 * wash).
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
// False draws winter's roofs as before card painter-roof-snow (snow_cover's patches; an A/B
// switch for measurements, PainterMannerHost.snow_body).
uniform bool snow_body = true;
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
// x: half the width of the light's steps, crisp on paint, a little softer on a roof slope and
// soft on snow (a blanket's light turns); y: how far the wobble moves a cast shadow's edge (a
// wall's is broken into strokes along its courses: a tree's soft shadow on a wall read as pale
// diagonal smears); z: how far it moves the light's steps (half on a roof slope, where a step
// crossing the slope read as a dark blot); w: the light's share under which a point is in cast
// shadow (lower on a roof and its snow, so a twig's thin partial shadow draws no dark mark).
varying vec4 f_tune;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_tone = tone_of(pick, COLOR.rgb);
	v_fuv = UV2;
	v_rec = CUSTOM0;
}

// 2D value noise, 0..1, one cell per unit: four hashes where p_noise takes eight (every stroke
// noise has a constant third coordinate; card painter-manner-c halved their cost this way).
float p_n2(vec2 p, float seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(vec3(i, seed)), p_hash(vec3(i + vec2(1.0, 0.0), seed)), f.x),
		mix(p_hash(vec3(i + vec2(0.0, 1.0), seed)), p_hash(vec3(i + vec2(1.0, 1.0), seed)), f.x), f.y);
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

// Short strokes along x in rows `row` metres high: cells about `cell` metres long (each row its
// own length, 0.6 to 1.5 times), `share` of them drawn, each its own width (0.6 to 1.3 times
// `width`) and place in the row, tapered and dry. Returns (dark, light) for the cell's own value.
vec2 p_strokes(vec2 f, float row, float cell, float share, float width, float dark_share, float seed) {
	float r = f.y / row;
	float ri = floor(r);
	float len = cell * mix(0.6, 1.5, p_hash(vec3(ri, seed, 2.0)));
	float x = f.x / len + p_hash(vec3(ri, seed, 1.0)) * 7.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed));
	float h2 = p_hash(vec3(ci, ri, seed + 4.0));
	float fx = fract(x);
	float fy = fract(r) - (h2 - 0.5) * 0.3;
	float w = width * mix(0.6, 1.3, h2);
	float body = smoothstep(0.0, 0.18, fx) * (1.0 - smoothstep(0.72, 1.0, fx));
	body *= 1.0 - smoothstep(w * 0.3, w * 0.5, abs(fy - 0.5));
	float dry = smoothstep(0.25, 0.45, p_n2(vec2(f.x * 7.0, ri * 3.1), seed));
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
	body *= 1.0 - smoothstep(0.3, 0.5, across + (p_n2(vec2(f.x * 2.3, ri), seed) - 0.5) * 0.2);
	float dry = smoothstep(0.2, 0.55, p_n2(vec2(f.x * 4.0, f.y * 16.0), seed));
	float on = step(1.0 - share, h) * body * mix(0.25, 1.0, dry);
	float is_dark = step(p_hash(vec3(ri, ci, seed + 9.4)), dark_share);
	return vec2(on * is_dark, on * (1.0 - is_dark));
}

// Dry-brushed stones on a wall frame `f` (metres) in courses `cr` high (`fw` a metre's pixel
// footprint): per course its own stone length (1.4 to 2.4 courses) and offset; per stone a crisp
// shape (each side its own inset, the edge broken by the drag of a dry brush along the course)
// and a tone of its own: about a third darker, a quarter lighter, the rest the wall's. A dark
// joint stroke runs under some stretches of a course and beside some stones. Returns (dark,
// light, a value shift for the stone).
vec3 p_stones(vec2 f, float cr, float fw, float seed) {
	float r = f.y / cr;
	float ri = floor(r);
	float len = cr * mix(1.4, 2.4, p_hash(vec3(ri, seed, 3.0)));
	float x = f.x / len + p_hash(vec3(ri, seed, 1.0)) * 5.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed + 2.0));
	float h2 = p_hash(vec3(ci, ri, seed + 4.0));
	vec2 q = vec2(fract(x) * len, fract(r) * cr);
	float drag = p_n2(vec2(f.x * 4.0, f.y * 18.0), seed);
	float l = 0.02 + 0.06 * h2;
	float rt = 0.02 + 0.06 * fract(h2 * 7.3);
	float b = 0.015 + 0.035 * fract(h * 5.1);
	float t = 0.015 + 0.035 * fract(h * 9.7);
	float edge = min(min(q.x - l, len - rt - q.x), min(q.y - b, cr - t - q.y)) + (drag - 0.5) * 0.05;
	float inside = smoothstep(0.0, max(fw * 1.2, 0.006), edge);
	float dry = mix(0.45, 1.0, smoothstep(0.3, 0.6, drag));
	float dk = inside * dry * smoothstep(0.64, 0.7, h) * mix(0.3, 0.6, fract(h * 13.1));
	float lt = inside * dry * (1.0 - smoothstep(0.22, 0.28, h)) * mix(0.3, 0.55, fract(h * 17.3));
	float jw = max(0.02, fw * 1.6);
	float under = (1.0 - smoothstep(jw * 0.5, jw, q.y)) * step(0.6, p_n2(vec2(f.x * 0.9, ri), seed + 8.0));
	float beside = (1.0 - smoothstep(jw * 0.5, jw, q.x)) * step(0.72, h2);
	float joint = max(under, beside) * mix(0.55, 1.0, drag);
	return vec3(dk + joint * 0.55, lt, (fract(h * 3.7) - 0.5) * inside);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n = normalize(v_wn);
	vec3 wp = v_wp;
	int code = int(floor(v_rec.z + 0.01));
	// A wall's course in metres rides in the code's fraction (0: the pattern's own), a hip face's
	// taper (metres along the eave a metre up the slope) in sixteenths in the accent's whole part.
	float course_m = fract(v_rec.z + 0.01) - 0.01;
	float taper = floor(v_rec.w) / 16.0;
	float acc = fract(v_rec.w);
	vec2 f = v_fuv;
	float ul = v_rec.x;
	float vl = v_rec.y;
	bool on_course = code == 1 || code == 3;
	bool on_slope = code == 2 || code == 8;
	// The dabs' noise and the light's wobble. A piece with a record draws them from its own frame,
	// stretched along its strokes (along the courses on a wall, down the fall line on a roof), so
	// a dab is a brushed patch and a light edge or a tree's shadow breaks into brush marks, never
	// a round blot or a smear; two noises there, so a dab never carries a ring of light (card
	// painter-buildings-fix). A piece with none keeps A3b's one 3D noise for both.
	float bn;
	float wob;
	if (code > 0) {
		vec2 k = on_course ? vec2(0.8, 3.5) : (on_slope ? vec2(0.45, 0.9) : vec2(1.1));
		bn = p_n2(f * k + acc * 13.0, 33.0);
		wob = bn;
		if (on_course || on_slope) {
			// On a roof slope, patches laid along the courses (streaks down the fall line read as
			// grey smears in a tree shadow's penumbra, card painter-buildings-fix2).
			wob = p_n2(f * (on_course ? vec2(1.2, 6.0) : vec2(1.0, 2.2)) + acc * 5.0, 35.0);
			bn += on_slope ? (wob - 0.5) * 0.25 : 0.0;
		}
	} else {
		bn = p_noise(wp * dab_freq + 33.0);
		wob = bn;
	}
	float pn = mix(p_noise(wp * patch_freq + 7.0), bn, 0.3);
	float variant = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix);
	float dark = 0.0;
	float light = 0.0;
	float dab = (pattern >= 5 ? 1.0 : dab_wall) * dabs;
	// A roof's dabs are a few subtle brushed patches (blotches read as stains); a slate's fewer.
	float dab_hi = on_slope ? 0.68 : 0.62;
	float dab_lit = on_slope ? 0.5 : 1.0;
	dark += smoothstep(dab_hi, dab_hi + 0.1, bn) * dab * (pattern == 6 ? 0.35 : 1.0) * dab_lit;
	light += (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8 * dab_lit;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = n.y;
	float u = dot(wp.xz, across);
	float h = clamp(v_h, 0.0, 1.0);
	// A metre's pixel footprint on the piece: fine marks fade from 4 cm a pixel, broad ones from
	// 8 cm, the ruled lines from 16 cm; past 30 cm no stroke is drawn at all (far views).
	float fw = length(fwidth(f));
	float detail = 1.0 - smoothstep(0.04, 0.09, fw);
	float broad = 1.0 - smoothstep(0.08, 0.16, fw);
	bool roofy = pattern >= 5;
	if (code > 0) {
		bool flat_roof = code == 8;
		bool wall = code == 1 || code == 3 || (flat_roof && pattern < 5);
		bool face = code == 1 || code == 3 || flat_roof;
		bool roof = code == 2 || (flat_roof && pattern >= 5);
		if (code == 2) {
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h);
		}
		if (code == 1 || code == 3) {
			float hm = h * 16.0;
			dark += contact * (1.0 - smoothstep(0.0, contact_m, hm));
		}
		float cr = course_m > 0.05 ? course_m : (pattern == 2 ? 0.3 : (pattern == 3 ? 0.24 : 0.34));
		if (wall && pattern == 1) {
			// Stone, dry-brushed (p_stones; card painter-buildings-fix: soft blurred blocks read as
			// an upscaled texture): it reads at home zoom and fades when a course is under about
			// three pixels.
			vec3 st = p_stones(f, cr, fw, 3.0 + acc * 17.0);
			float block = 1.0 - smoothstep(0.15, 0.35, fw / cr);
			dark += st.x * block;
			light += st.y * block;
			variant = clamp(variant + st.z * 0.6 * block, 0.0, 1.0);
			// A tree's dappled light breaks along the stones: each stone moves the cast edge its
			// own way (pale ovals of light on the wall read as glare, card painter-buildings-fix2).
			wob = mix(wob, 0.5 + st.z * 1.4, block);
		}
		if (fw < 0.3) {
			if (face || code == 2) {
				// The ruled line just inside each edge (a hip face's sides follow its taper),
				// wobbling and broken, never under about three pixels wide or inset less than
				// three.
				float lw = max(0.03, fw * 1.4);
				float inset = max(0.07, fw * 3.0);
				float wob = (p_n2(f * 1.4, acc * 9.0) - 0.5) * 0.06;
				float dx = min(f.x - taper * f.y, ul - taper * f.y - f.x) / sqrt(1.0 + taper * taper);
				float dy0 = f.y;
				float dy1 = vl - f.y;
				float de = min(dx, min(dy0, dy1));
				float line = 1.0 - smoothstep(lw, lw + max(0.012, fw), abs(de - inset - wob));
				line *= step(0.2, p_n2(vec2((f.x + f.y) * 1.1, acc * 5.0), 2.0));
				line *= 1.0 - smoothstep(0.16, 0.3, fw);
				float at_low = step(dy0, min(dx, dy1));
				float at_high = step(dy1, min(dx, dy0));
				float at_side = 1.0 - at_low - at_high;
				if (code == 2) {
					dark += line * 0.9 * at_low;
					light += line * (0.75 * at_high + 0.6 * at_side);
				} else if (code == 3) {
					light += line * 0.55 * (1.0 - at_low);
					dark += line * 0.5 * at_low;
				} else {
					dark += line * 0.45;
				}
			}
			if (wall) {
				if (pattern == 1) {
					// Stone: one broad dry stroke along a course here and there (the stones and
					// their joints are p_stones').
					vec2 m = p_wash(f, cr, cr * 3.0, 0.3, 0.22, 0.5, 11.0 + acc * 9.0);
					dark += m.x * 0.3 * broad;
					light += m.y * 0.3 * broad;
				} else if (pattern == 2 || pattern == 3) {
					vec2 g = pattern == 2 ? f : f.yx;
					dark += p_line(g.y / cr, 0.12) * step(0.3, p_n2(vec2(g.x * 0.9, floor(g.y / cr)), 4.0)) * 0.55;
				} else {
					// Plaster: broad dry-brush washes, lighter or darker, each its own size, over
					// a slow drift of value across the wall (a stretch lighter, the next darker).
					vec2 m = p_wash(f, 0.55, 1.5, 0.5, 0.26, 0.45, 3.0 + acc * 9.0);
					dark += m.x * 0.4 * broad;
					light += m.y * 0.36 * broad;
					float drift = p_n2(f * vec2(0.45, 0.6) + acc * 7.0, 37.0);
					dark += smoothstep(0.55, 0.8, drift) * 0.22 * broad;
					light += (1.0 - smoothstep(0.2, 0.45, drift)) * 0.2 * broad;
				}
			} else if (roof) {
				if (pattern == 8) {
					vec2 m = p_strokes(f.yx, 0.075, 0.8, 0.42, 0.7, 0.45, 5.0);
					dark += m.x * 0.45 * detail;
					light += m.y * 0.4 * detail;
					for (int c = 1; c <= 3; c++) {
						float at = vl * 0.25 * float(c) + (p_n2(vec2(f.x * 0.8, float(c)), 6.0) - 0.5) * 0.2;
						float band = p_band(f.y, at, 0.06) * step(0.25, p_n2(vec2(f.x * 1.2, float(c)), 8.0));
						dark += band * 0.5 * detail;
					}
				} else if (pattern == 9) {
					vec2 m = p_strokes(f, 0.25, 0.35, 0.35, 0.8, 0.5, 9.0);
					dark += m.x * 0.35 * detail;
					light += m.y * 0.35 * detail;
				} else if (pattern == 6) {
					// Slate: a few long thin ruled dashes, each its own length and place (the
					// prototype's sparse slate lines over its broad blotches).
					vec2 m = p_strokes(f + vec2(0.0, 0.2), 0.48, 1.7, 0.28, 0.16, 0.85, 7.0);
					dark += m.x * 0.6 * broad;
					light += m.y * 0.4 * broad;
				} else {
					float course = pattern == 5 ? 0.42 : 0.26;
					vec2 m = p_strokes(f + vec2(0.0, course * 0.35), course, 0.45, 0.55, 0.22, 0.82, 7.0);
					dark += m.x * 0.6 * detail;
					light += m.y * 0.45 * detail;
				}
			}
			if (code == 4 || code == 6) {
				// A beam: one broad stroke, a light and a dark line along it, and a dark brush
				// rim where the mesh widened it, dragged dry so it breaks.
				float across_b = vl > 0.0 ? f.y / vl : 0.5;
				light += p_band(across_b, 0.66, 0.22) * 0.45 * smoothstep(0.1, 0.3, p_n2(vec2(f.x * 1.5, acc * 7.0), 1.0));
				dark += p_band(across_b, 0.3, 0.2) * 0.4;
				float rim = min(across_b, 1.0 - across_b) + (p_n2(vec2(f.x * 2.6, acc * 3.0), 9.0) - 0.5) * 0.14;
				dark += (1.0 - smoothstep(0.04, 0.17, rim)) * 0.7 * (code == 4 ? 1.0 : 0.0);
			} else if (code == 5) {
				// A door: plank seams, a wandering grain, one brace stroke, a darker head.
				float x = f.y + sin(f.x * 4.0 + acc * 20.0) * 0.012;
				dark += p_line(f.y / 0.16, 0.12) * 0.5;
				dark += p_line(x / 0.045, 0.18) * 0.22 * detail;
				float diag = ul > 0.0 && vl > 0.0 ? f.y / vl - f.x / ul : 1.0;
				dark += p_band(diag, 0.0, 0.07) * 0.35 * step(0.3, p_n2(vec2(f.x * 3.0, acc), 3.0));
				dark += smoothstep(0.7, 1.0, ul > 0.0 ? f.x / ul : 0.0) * 0.3;
			} else if (code == 7) {
				// A thatch tooth: strands down it, a darker tip.
				dark += p_line(f.x / 0.05, 0.3) * 0.4 + smoothstep(-0.05, -0.25, f.y) * 0.3;
			}
		}
		if (code == 4 || code == 6) {
			variant = clamp(variant + (acc - 0.5) * 0.6, 0.0, 1.0);
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
	bool strip = code == 9;
	if (!strip) {
		dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	}
	float cover = 0.0;
	float hide = 0.85;
	float snow_dark = 0.0;
	float snow_light = 0.0;
	float soft = 0.01;
	if (snow > 0.0) {
		if (code == 10 || (snow_body && code > 0 && roofy && code != 7)) {
			// The blanket (code 10, PainterMannerBlanket), or a roof piece under it (its own
			// marks hidden whole: dashes through the snow read as dirt, cards
			// painter-buildings-fix and -fix2): all snow, with broad brush washes, lighter or
			// bluer, laid along the eave, the light turning softly along them; a blanket's shade
			// (the code's fraction) darkens it to blue under the eave's lip.
			float under = code == 10 ? clamp(course_m / 0.9, 0.0, 1.0) : 0.0;
			cover = 1.0;
			hide = 1.0;
			vec2 sw = p_wash(f, 0.5, 1.6, 0.55, 0.32, 0.45, 41.0 + acc * 7.0);
			snow_dark = sw.x * 0.45 * broad * (1.0 - under) + under * 0.6;
			snow_light = sw.y * 0.6 * broad * (1.0 - under);
			wob = 0.5 + (sw.y - sw.x) * 0.45;
			soft = 0.06;
		} else if (strip || (snow_body && code == 6)) {
			// A strip (or the ridge beam under a cap): all snow, a slightly darker foot where it
			// sits and a blue underside under a lip's nose.
			cover = 1.0;
			hide = 1.0;
			soft = 0.06;
			snow_dark = strip
				? 0.15 * (1.0 - smoothstep(0.0, 0.6, f.y)) + 0.55 * smoothstep(1.8, 3.0, f.y)
				: 0.0;
		} else if (roofy && !(snow_body && code == 7)) {
			cover = snow_cover(snow, wp, up, h);
		}
	}
	dark = clamp(dark * marks * (1.0 - cover * hide) + snow_dark, 0.0, 0.85);
	light = clamp(light * marks * (1.0 - cover * hide) + snow_light, 0.0, 0.8);
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
	f_wob = wob;
	bool paint_slope = on_slope && cover < 0.5;
	f_tune = vec4(
		paint_slope ? 0.025 : soft,
		on_course ? 0.7 : (on_slope ? 0.25 : 0.2),
		paint_slope ? 0.06 : 0.12,
		on_slope || code == 10 ? 0.3 : 0.5);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(f_tune.w - 0.05, f_tune.w + 0.05, ATTENUATION + (f_wob - 0.5) * f_tune.y);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * f_tune.z;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - f_tune.x, tone_lo + f_tune.x, x));
		col = mix(col, f_lit, smoothstep(tone_hi - f_tune.x, tone_hi + f_tune.x, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
