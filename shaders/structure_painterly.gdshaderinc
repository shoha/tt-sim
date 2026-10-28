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

uniform vec3 shadow_tint : source_color = vec3(0.92, 0.72, 0.78);
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.8;
uniform float wrap : hint_range(0.0, 0.5) = 0.2;
// Rim of warm light on edges turned away from the camera (a painter's lost-and-found edge).
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_amount : hint_range(0.0, 0.5) = 0.10;

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

void light() {
	float nl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(-wrap, 0.6, nl) * ATTENUATION;
		DIFFUSE_LIGHT += LIGHT_COLOR * lit / PI;
		// The unlit side leans to the cool tint (multiplied by the albedo afterwards).
		DIFFUSE_LIGHT += shadow_tint * shadow_fill * (1.0 - lit) * 0.30;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * max(nl, 0.0) * ATTENUATION / PI;
	}
}
