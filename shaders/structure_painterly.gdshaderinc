// The painterly look of built structures (card S6; docs/systems/structures.md "Look"): the terms
// the roof and wall shaders share. A structure's colour comes from its mesh's vertex colours
// (StructurePaint bakes a per building tile colour into the roof and a gentle lean into the walls)
// and COLOR.a carries the height the shaders grade by, so one material per role serves every
// structure and street lot. Everything here is a broad, soft shape: world-space value noise at
// building scale, never fine grain, and a light() with a wrapped terminator whose shadow leans to a
// cool lavender instead of going grey.
//
// Cost: no extra texture reads, one 3D value noise per fragment (8 hashes), no branches on
// uniforms, specular off. light() runs for directional lights only; other lights add plain lambert.

// The plants' light model (wind_foliage_include.gdshaderinc, FOLIAGE_PAINTED_LIGHT), at a building's
// albedo: the sun published for the crowns, a sun-ward albedo ramp (lit tint toward the sun, a deeper
// saturated shade tint away from it), a wide soft N.L band with a tinted shade floor instead of a
// lifted fill, and less ambient under a full sun so the shade keeps its colour.
global uniform vec4 foliage_sun;
uniform vec3 ramp_lit_tint = vec3(1.06, 1.03, 0.98);
uniform vec3 ramp_shade_tint = vec3(0.86, 0.84, 0.96);
uniform vec3 shade_floor = vec3(0.21, 0.16, 0.25);
uniform vec3 lit_gain = vec3(1.22, 1.17, 1.08);
uniform float shadow_cast : hint_range(0.0, 1.0) = 0.7;
uniform float wrap : hint_range(0.0, 0.5) = 0.15;
// The share of ambient a surface keeps under a full sun (the crowns keep 0.25).
uniform float ambient_keep : hint_range(0.0, 2.0) = 0.5;
// Rim of warm light on edges turned away from the camera (a painter's lost-and-found edge).
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_amount : hint_range(0.0, 0.5) = 0.12;

varying vec3 s_pos;
varying vec3 s_normal;

float s_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float s_hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float s_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(s_hash(i), s_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(s_hash(i + vec3(0.0, 1.0, 0.0)), s_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(s_hash(i + vec3(0.0, 0.0, 1.0)), s_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(s_hash(i + vec3(0.0, 1.0, 1.0)), s_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// A soft colour multiplier: 0 leans cool (lavender), 1 leans warm (gold), `amount` how far.
vec3 s_lean(float warmth, float amount) {
	vec3 warm = vec3(1.07, 1.0, 0.86);
	vec3 cool = vec3(0.90, 0.95, 1.08);
	return mix(vec3(1.0), mix(cool, warm, warmth), amount);
}

void vertex() {
	s_pos = VERTEX;
	s_normal = NORMAL;
}

// The faint warm rim, from the albedo, the geometry normal and the view vector.
vec3 s_rim(vec3 painted, vec3 normal, vec3 view) {
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
	return rim_color * rim * rim_amount * painted;
}

// The foliage's sun-ward albedo ramp: `normal` is the view-space normal, `inv_view` INV_VIEW_MATRIX.
vec3 s_ramp(vec3 painted, vec3 normal, mat4 inv_view) {
	vec3 ramp_dir = normalize(foliage_sun.xyz + vec3(0.0, 0.5, 0.0));
	float t = smoothstep(-0.5, 0.8, dot(normalize(mat3(inv_view) * normal), ramp_dir));
	return painted * mix(ramp_shade_tint, ramp_lit_tint, t);
}

// The ambient share (for AO): the crowns' rule, eased back to 1 as the sun fades.
float s_ambient() {
	return mix(1.0, ambient_keep, clamp(foliage_sun.w, 0.0, 1.0));
}

// A broad soft-edged value shape from a 0..1 noise: bold masses with soft edges, as in a crown.
float s_mass(float n, float amount) {
	return 1.0 + (smoothstep(0.30, 0.70, n) - 0.5) * amount;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(-wrap, 0.9, nl);
		float k = lit * mix(1.0 - shadow_cast, 1.0, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shade_floor, lit_gain, k);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * max(nl, 0.0) * ATTENUATION / PI;
	}
}
