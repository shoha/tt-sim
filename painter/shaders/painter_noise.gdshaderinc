// The painted look's shared noises (docs/systems/painter.md "Surfaces"): the value noise the
// ground and the plant selectors vary their tones by, and the brush streak that wiggles a cast
// shadow's step on the ground (painter_ground.gdshader `cut`). Each function has its own hash so
// an include order cannot change a picture.

float p_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise, 0..1, one cell per unit.
float p_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(p_hash(i), p_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(p_hash(i + vec3(0.0, 1.0, 0.0)), p_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(p_hash(i + vec3(0.0, 0.0, 1.0)), p_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(p_hash(i + vec3(0.0, 1.0, 1.0)), p_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float be_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float be_n2(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(be_hash(i), be_hash(i + vec2(1.0, 0.0)), f.x),
		mix(be_hash(i + vec2(0.0, 1.0)), be_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The brush streak at the point `st` of the strokes' frame (x along the stroke, y across): long
// along, thin across, a stepped half for bristle bands. One value in -1..1.
float be_cut(vec2 st) {
	float a = (be_n2(vec2(st.y * 8.0, st.x * 0.7)) - 0.5) * 2.0;
	a = mix(a, floor(a * 3.0 + 0.5) / 3.0, 0.5) * 1.15;
	float b = (be_n2(vec2(st.y * 4.0 + 11.0, st.x * 0.5 + 3.0)) - 0.5) * 0.9;
	return clamp(a * 0.8 + b * 1.2, -1.0, 1.0);
}

// 2D value noise, 0..1, one cell per unit: four hashes where p_noise takes eight (every stroke
// noise has a constant third coordinate; card painter-manner-c halved their cost this way). The
// hand-drawn manner's strokes and the shared roof snow (painter_snow.gdshaderinc) use it.
float p_n2(vec2 p, float seed) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(vec3(i, seed)), p_hash(vec3(i + vec2(1.0, 0.0), seed)), f.x),
		mix(p_hash(vec3(i + vec2(0.0, 1.0), seed)), p_hash(vec3(i + vec2(1.0, 1.0), seed)), f.x), f.y);
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
