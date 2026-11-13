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
