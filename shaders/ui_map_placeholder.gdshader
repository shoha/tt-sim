shader_type canvas_item;

// The picture of a map with no thumbnail yet (scenes/ui/primitives/map_placeholder.gd), painted
// rather than a flat slab: a sky in two washes with a soft sun (a moon at night) and most often
// one cloud, a far ridge in haze, a near landform with a sunlit rim and a foreground slope. A
// few bold, soft-edged shapes, never fine noise. The seed draws the shapes (where the sun
// sits, whether there is a cloud, how tall and rugged the ridge is), so a map always paints
// the same; the palette is the map's mood. The edges soften with the picture's size: about a
// pixel in a shelf row, a brush edge in the room's large preview.

uniform float seed = 0.0;
uniform int palette = 0;
// Width over height of the rect, so the sun and the cloud stay round.
uniform float aspect = 1.7778;

// Per palette: meadow, golden hills, heather, lakeside, spring blossom and teal coast (the day
// palettes the seed picks among), then dusk, moonlit night, snow and sand (the moods). The
// golden hills keep olive in their near land and a cool haze on the far ridge: all-orange
// hills read as desert dunes.
const vec3 SKY_TOP[10] = {
	vec3(0.56, 0.78, 0.91), vec3(0.61, 0.79, 0.89), vec3(0.65, 0.75, 0.91), vec3(0.53, 0.80, 0.88),
	vec3(0.60, 0.80, 0.93), vec3(0.48, 0.76, 0.90),
	vec3(0.50, 0.53, 0.78), vec3(0.22, 0.29, 0.52), vec3(0.66, 0.83, 0.93), vec3(0.62, 0.80, 0.91)
};
const vec3 SKY_LOW[10] = {
	vec3(0.97, 0.89, 0.71), vec3(0.98, 0.85, 0.68), vec3(0.96, 0.86, 0.80), vec3(0.95, 0.92, 0.80),
	vec3(0.98, 0.90, 0.88), vec3(0.93, 0.95, 0.86),
	vec3(0.97, 0.70, 0.49), vec3(0.50, 0.58, 0.80), vec3(0.96, 0.93, 0.90), vec3(0.98, 0.89, 0.75)
};
const vec3 FAR[10] = {
	vec3(0.62, 0.77, 0.72), vec3(0.62, 0.66, 0.74), vec3(0.67, 0.61, 0.78), vec3(0.54, 0.74, 0.77),
	vec3(0.82, 0.70, 0.80), vec3(0.40, 0.68, 0.72),
	vec3(0.66, 0.49, 0.62), vec3(0.34, 0.42, 0.64), vec3(0.73, 0.81, 0.90), vec3(0.88, 0.72, 0.56)
};
const vec3 NEAR[10] = {
	vec3(0.49, 0.70, 0.40), vec3(0.80, 0.69, 0.33), vec3(0.55, 0.67, 0.41), vec3(0.42, 0.67, 0.49),
	vec3(0.58, 0.76, 0.42), vec3(0.86, 0.82, 0.60),
	vec3(0.45, 0.37, 0.55), vec3(0.24, 0.31, 0.50), vec3(0.94, 0.96, 0.97), vec3(0.92, 0.76, 0.49)
};
const vec3 FORE[10] = {
	vec3(0.30, 0.55, 0.30), vec3(0.47, 0.50, 0.25), vec3(0.42, 0.50, 0.32), vec3(0.24, 0.51, 0.45),
	vec3(0.36, 0.60, 0.33), vec3(0.48, 0.64, 0.40),
	vec3(0.30, 0.26, 0.43), vec3(0.16, 0.22, 0.39), vec3(0.62, 0.76, 0.85), vec3(0.79, 0.55, 0.33)
};
const vec3 SUN[10] = {
	vec3(1.00, 0.96, 0.84), vec3(1.00, 0.92, 0.76), vec3(1.00, 0.95, 0.87), vec3(1.00, 0.98, 0.90),
	vec3(1.00, 0.97, 0.90), vec3(1.00, 0.98, 0.90),
	vec3(1.00, 0.85, 0.63), vec3(0.96, 0.93, 0.86), vec3(1.00, 0.97, 0.92), vec3(1.00, 0.95, 0.84)
};

// A ridge line: three sines whose phases the seed sets, so each map draws its own skyline.
float wave(float x, float phase) {
	return 0.55 * sin(x + phase) + 0.3 * sin(x * 2.3 + phase * 1.7) + 0.15 * sin(x * 4.1 + phase * 2.9);
}

// How much of the point at height `y` lies under the line at height `h`, with a soft edge.
float under(float y, float h, float soft) {
	return 1.0 - smoothstep(h - soft, h + soft, y);
}

// A soft round blob of radius `r` around `at`.
float blob(vec2 p, vec2 at, float r, float soft) {
	return 1.0 - smoothstep(r - soft, r + soft, length(p - at));
}

void fragment() {
	int i = clamp(palette, 0, 9);
	vec3 top = SKY_TOP[i];
	vec3 low = SKY_LOW[i];
	float y = 1.0 - UV.y;
	float x = UV.x * aspect;
	vec2 p = vec2(x, y);
	float phase = seed * 6.2831;
	float soft = max(0.006, fwidth(y) * 1.2);

	// The sky: the low wash warms the horizon, the top wash deepens overhead.
	vec3 col = mix(low, top, smoothstep(0.25, 1.0, y));
	// The sun (a moon at night): a wide glow and a soft disc, anywhere across the upper sky,
	// high or low.
	vec2 sun_at = vec2(mix(0.1, 0.9, fract(seed * 7.13)) * aspect, mix(0.6, 0.84, fract(seed * 3.71)));
	float glow = exp(-dot(p - sun_at, p - sun_at) / 0.05);
	col = mix(col, SUN[i], 0.4 * glow);
	col = mix(col, SUN[i], blob(p, sun_at, mix(0.055, 0.08, fract(seed * 5.3)), soft * 1.5));
	// Most skies carry one cloud of three overlapping puffs on the far side of the sun; some
	// are clear.
	float cloud_x = fract(seed * 7.13 + 0.45) * aspect;
	vec2 cloud_at = vec2(cloud_x, mix(0.76, 0.9, fract(seed * 9.17)));
	vec2 squash = vec2(0.55, 1.0);
	float puff = mix(0.8, 1.25, fract(seed * 4.7));
	float cloud = blob(p * squash, cloud_at * squash, 0.05 * puff, soft * 3.0);
	vec2 second = cloud_at + vec2(0.1, 0.025) * puff;
	vec2 third = cloud_at + vec2(0.22, 0.0) * puff;
	cloud = max(cloud, blob(p * squash, second * squash, 0.065 * puff, soft * 3.0));
	cloud = max(cloud, blob(p * squash, third * squash, 0.045 * puff, soft * 3.0));
	float clear_sky = step(fract(seed * 13.9), 0.25);
	col = mix(col, mix(low, vec3(1.0), 0.55), 0.8 * cloud * (1.0 - clear_sky));

	// The far ridge, in haze: it takes on the low sky toward its crest. Its height and how
	// rugged it is vary with the seed: a low line of downs or a tall range.
	float far_base = mix(0.42, 0.58, fract(seed * 2.9));
	float far_amp = mix(0.04, 0.12, fract(seed * 6.1));
	float far_h = far_base + far_amp * wave(x * mix(1.6, 3.2, fract(seed * 8.3)), phase);
	vec3 far_col = mix(FAR[i], low, 0.3 * smoothstep(far_h - 0.25, far_h, y));
	col = mix(col, far_col, under(y, far_h, soft));
	// The near landform, its crest catching the light.
	float near_base = mix(0.26, 0.38, fract(seed * 4.3));
	float near_h = near_base + 0.08 * wave(x * 1.7 + 1.3, phase * 1.37 + 2.0);
	vec3 lit = min(NEAR[i] * 1.08, vec3(1.0));
	vec3 near_col = mix(NEAR[i] * 0.92, lit, smoothstep(near_h - 0.16, near_h, y));
	col = mix(col, near_col, under(y, near_h, soft));
	// The foreground slope, rising toward the side the seed picks.
	float across = UV.x;
	if (fract(seed * 11.7) > 0.5) {
		across = 1.0 - across;
	}
	float fore_h = 0.06 + 0.16 * across * across + 0.025 * wave(x * 3.1, phase * 2.1);
	col = mix(col, FORE[i], under(y, fore_h, soft));

	COLOR = vec4(col, COLOR.a);
}
