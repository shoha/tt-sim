// The painted village fields (PainterFields, painter/painter_fields.gd; card painter-fields;
// docs/systems/painter.md "Fields"). Included by painter_ground.gdshader after its zone grid
// uniforms (layer_grid_origin, layer_grid_step) and painter_noise.
//
// A crop field is a tilled soil bed with the crop's rows laid over it as long brush strokes, each
// stroke one flat tone of the crop with its own small value step and tapered ends, a darker furrow
// line midway between two rows and a headland of bare soil where the rows stop short of the rim.
// The rows are exactly the plant rows VillageCrops plants (the first row's offset, the count and
// the pitch per field), so the plants stand on their own painted rows. A garden's beds are soil
// capsules (VillageFields' bed layout). The disc's rim and every edge are moved by the ground's
// brush noise; a mark asked at its middle near the rim takes the field's tone there, so the rim is
// brush marks. Under 2.5 pixels a row, the stripes fade to their mean (no shimmer). In winter the
// crop strokes and the soil take `f_snow` of the snow; the furrow lines stay soil.

uniform sampler2D field_map : hint_default_black, filter_nearest, repeat_disable;
uniform bool field_present = false;
// Per field: centre x, z, radius, the rows' angle; the first row's offset, the row count, the
// pitch; style * 4 + crop (style 0 crop rows, 1 garden beds; crop a VillageCrops.TONES index).
uniform vec4 f_geo[32];
uniform vec4 f_row[32];
uniform int f_kind[32];
// The soil's lit0, lit1, shade0, shade1 and each crop's two lit and two shade variants, LINEAR.
uniform vec3 f_soil[4];
uniform vec3 f_crop_lit[8];
uniform vec3 f_crop_shd[8];
uniform float f_snow = 0.0;

// A crop stroke's half width and length (m; the rows are about 1.15 m apart), the furrow line's
// half width, the soil disc's reach (VillageFields.DISC_FACTOR) and how far the rows reach along
// their chord (VillageCrops.ROW_REACH, less its end radius).
const float FIELD_BAND = 0.34;
const float FIELD_DAB = 1.7;
const float FIELD_FURROW = 0.07;
const float FIELD_DISC = 1.05;
const float FIELD_REACH = 0.86;
const float FIELD_REACH_END = 0.3;
// A garden's beds: the reach share of the chord and the bed's radius (VillageFields).
const float BED_REACH = 0.6;
const float BED_R = 1.0;

// The field the map names at `q`, -1 for none.
int field_at(vec2 q) {
	vec2 size = vec2(textureSize(field_map, 0));
	int i = int(textureLod(field_map, ((q - layer_grid_origin) / layer_grid_step + 0.5) / size, 0.0).r * 255.0 + 0.5);
	return i < 32 ? i : -1;
}

// True well inside a field's paint, where the ground's marks are not searched (a crop disc, a
// garden's middle).
bool field_inner(vec2 q) {
	if (!field_present) {
		return false;
	}
	int i = field_at(q);
	if (i < 0) {
		return false;
	}
	float rr = length(q - f_geo[i].xy) / f_geo[i].z;
	return f_kind[i] < 4 ? rr < 0.97 : rr < 0.72;
}

// Paints the field at `q` (a pixel, or a mark's middle: mk 1 or 2, `h` its hash) over `lit` and
// `shd`; `px` the pixel's width (m), `snow_l` and `snow_s` the meadow role's tones (the snow in
// winter). Returns 1 where it painted.
float field_paint(vec2 q, float px, float mk, float h, vec3 snow_l, vec3 snow_s, inout vec3 lit, inout vec3 shd) {
	int i = field_at(q);
	if (i < 0) {
		return 0.0;
	}
	vec4 g = f_geo[i];
	vec4 r = f_row[i];
	int style = f_kind[i] / 4;
	int crop = f_kind[i] - style * 4;
	vec3 p = vec3(q.x, 0.0, q.y);
	vec2 d = q - g.xy;
	vec2 al = vec2(cos(g.w), sin(g.w));
	vec2 ac = vec2(-al.y, al.x);
	float u = dot(d, ac);
	float v = dot(d, al);
	float rad = g.z;
	float wob = (p_noise(p * 0.9 + 140.0) - 0.5) * 0.55 + (p_noise(p * 2.8 + 150.0) - 0.5) * 0.25 + (h - 0.5) * 0.3 * min(mk, 1.0);
	float slow = p_noise(vec3(q.x * 0.11, 3.0, q.y * 0.13) + 160.0);
	vec3 soil_l = mix(f_soil[0], f_soil[1], slow);
	vec3 soil_s = mix(f_soil[2], f_soil[3], slow);
	float k = (u - r.x) / r.z;
	float n = floor(k + 0.5);
	float u_row = r.x + n * r.z;
	float rh = p_hash(vec3(n, 170.0, float(i)));
	if (style == 1) {
		float half_len = sqrt(max(rad * rad - u_row * u_row, 0.0)) * BED_REACH - BED_R;
		float dv = max(abs(v) - half_len, 0.0);
		if (n < 0.0 || n >= r.y || half_len <= 0.3 || length(vec2(u - u_row, dv)) + wob * 0.6 > BED_R) {
			return 0.0;
		}
		// A bed: dark soil in a few strokes along it.
		float s = p_hash(vec3(floor((v + rh * 4.0) / 1.1), n + 31.0, float(i)));
		float vk = 0.7 + 0.1 * s;
		lit = mix(soil_l * vk, snow_l, f_snow);
		shd = mix(soil_s * vk, snow_s, f_snow);
		return 1.0;
	}
	if (length(d) + wob > rad * FIELD_DISC) {
		return 0.0;
	}
	// The row's line wanders a little, as a ploughed furrow does.
	float off = (u - u_row) + (p_noise(vec3(v * 0.3 + rh * 9.0, n * 1.7, 4.0) + 180.0) - 0.5) * 0.18;
	float half_len = sqrt(max(rad * rad - u_row * u_row, 0.0)) * FIELD_REACH - FIELD_REACH_END;
	bool row_ok = n >= 0.0 && n < r.y && half_len > 0.5;
	float end = half_len + (p_noise(p * 1.3 + 200.0) - 0.5) * 0.6;
	// The strokes along a row: each its own length, value and taper.
	float sv = (v + rh * 5.0) / FIELD_DAB;
	float t = fract(sv);
	float sh = p_hash(vec3(floor(sv), n + 13.0, float(i)));
	float taper = 1.0 - 0.5 * pow(abs(2.0 * t - 1.0), 3.0);
	float bw = FIELD_BAND * (0.85 + 0.3 * sh) * taper + (p_noise(p * 3.1 + 190.0) - 0.5) * 0.08;
	float in_rows = row_ok ? 1.0 - step(end, abs(v)) : 0.0;
	float on_crop = in_rows * (1.0 - step(bw, abs(off)));
	// The furrow's dark line midway between two rows (both standing there).
	float fd = (0.5 - abs(k - n)) * r.z + (p_noise(p * 2.3 + 210.0) - 0.5) * 0.05;
	float furrow = in_rows * (1.0 - step(FIELD_FURROW, fd)) * step(abs(v), end - 0.4);
	vec3 cl = mix(f_crop_lit[crop * 2], f_crop_lit[crop * 2 + 1], mix(slow, sh, 0.6));
	vec3 cs = mix(f_crop_shd[crop * 2], f_crop_shd[crop * 2 + 1], mix(slow, sh, 0.6));
	float ck = 0.94 + 0.12 * fract(sh * 7.3);
	cl = mix(cl * ck, snow_l, f_snow);
	cs = mix(cs * ck, snow_s, f_snow);
	vec3 sl = mix(soil_l, snow_l, min(f_snow * 1.34, 1.0));
	vec3 ss = mix(soil_s, snow_s, min(f_snow * 1.34, 1.0));
	vec3 fl = soil_l * 0.78;
	vec3 fs = soil_s * 0.8;
	vec3 out_l = on_crop > 0.5 ? cl : (furrow > 0.5 ? fl : sl);
	vec3 out_s = on_crop > 0.5 ? cs : (furrow > 0.5 ? fs : ss);
	// Too small to draw: the rows' mean (about two thirds crop).
	float drawn = smoothstep(2.5, 5.0, r.z / max(px, 0.0001));
	vec3 mean_l = mix(sl, cl, 0.62 * in_rows);
	vec3 mean_s = mix(ss, cs, 0.62 * in_rows);
	lit = mix(mean_l, out_l, drawn);
	shd = mix(mean_s, out_s, drawn);
	return 1.0;
}
