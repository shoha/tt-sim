/*
 * The ground skirt's fade, shared by the skirt (authored_ground.gdshaderinc with GROUND_SKIRT)
 * and the water that runs on past the map edge in it (water.gdshader, water_skirt_fade; phase
 * 6, P6-1), so the river and the ground dissolve into the backdrop in exactly the same place.
 * RiverExits.skirt_alpha (utils/river_exits.gd) is its CPU twin.
 *
 * skirt_alpha(): 1 on the map, falling to 0 skirt_fade_m past its edge, the distance to the
 * map rectangle (rounded at the corners) stretched +- skirt_wobble by two octaves of value
 * noise on the map seed, so the outline is organic, not a rectangle; it holds near the map,
 * then falls off softly, like haze rather than a linear ramp.
 */

// Half the map's extent in map metres: the skirt fades out from this rectangle.
uniform vec2 skirt_half_extent = vec2(30.0);
// Distance past the map edge at which the skirt is fully faded.
uniform float skirt_fade_m : hint_range(1.0, 100.0) = 24.0;
// How much low-frequency noise stretches and shrinks the fade (0 = a clean rounded rect).
uniform float skirt_wobble : hint_range(0.0, 1.0) = 0.45;

uvec2 skirt_pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}

// The ground shader's value_noise(), on an explicit seed.
float skirt_value_noise(vec2 p, int seed) {
	vec2 i = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	uvec2 c = uvec2(ivec2(i) + ivec2(seed, seed * 7919));
	float a = float(skirt_pcg2d(c).x);
	float b = float(skirt_pcg2d(c + uvec2(1u, 0u)).x);
	float d = float(skirt_pcg2d(c + uvec2(0u, 1u)).x);
	float e = float(skirt_pcg2d(c + uvec2(1u, 1u)).x);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y) * (1.0 / 4294967295.0);
}

float skirt_alpha_seeded(vec2 world_xz, int seed) {
	float d = length(max(abs(world_xz) - skirt_half_extent, vec2(0.0)));
	vec2 p = world_xz / 11.0;
	float n = skirt_value_noise(p + vec2(3.7, -8.2), seed) * 0.7
		+ skirt_value_noise(p * 2.3 + vec2(-5.1, 2.9), seed) * 0.3;
	d *= 1.0 + (n - 0.5) * 2.0 * skirt_wobble;
	float t = clamp(d / skirt_fade_m, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}
