// The fire's one noise and one erosion rule, shared by its flames (event_puff.gdshader's banded
// tongues) and its smoke (fire_smoke.gdshader), so a tongue, the ground fire and a billow break
// up the same way: bold value noise in two octaves (a few soft blobs, not grain), and a shape
// eaten by that noise as it ages instead of fading, its edge a crisp step a pixel wide.

float fire_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise, 0..1, one blob a unit across.
float fire_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fire_hash(i);
	float b = fire_hash(i + vec2(1.0, 0.0));
	float c = fire_hash(i + vec2(0.0, 1.0));
	float d = fire_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Two octaves, mostly the broad one: bold blobs with a little break in their edges.
float fire_cloud(vec2 p) {
	return 0.68 * fire_noise(p) + 0.32 * fire_noise(p * 2.17 + vec2(7.1, 3.3));
}

// The erosion rule: a shape's `field` (0 at its edge, 1 deep inside) pushed in and out by the
// noise `cloud` (so even a fresh shape has a lumpy painted edge), then eaten from `from` of its
// life to nearly its end (`age` 0..1), the low parts of the noise first, so it breaks into a
// few bold pieces that shrink away and are gone a little before it ends (a last piece left to
// the end lingered as a lone ball). Above 0 is inside.
float fire_erode(float field, float cloud, float age, float from) {
	return field + (cloud - 0.5) * 0.55 - smoothstep(from, 0.9, age) * 1.4;
}

// The crisp edge: 0 outside, 1 inside, stepped over about a pixel.
float fire_cut(float v) {
	float w = max(fwidth(v), 1e-4);
	return smoothstep(-w, w, v);
}
