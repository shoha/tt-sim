shader_type canvas_item;

// The painted backdrop every screen outside play stands on (scenes/ui/primitives/
// painted_backdrop.gd): the map placeholder's language (shaders/ui_map_placeholder.gdshader)
// at the size of the screen. A sky in two washes with a sun in a warm halo (a moon at night),
// four bold cumulus clouds with flat bases that drift very slowly, a pale distant range and a
// rolling far ridge in the mood's own atmospheric tint, three poplars rising from behind the
// near hill's shoulder, and a meadow rising to the right. A few bold,
// soft-edged shapes; no textures and no noise. The painting carries no words: the screens on
// it put theirs on paper (sheets and plaques), so nothing here hazes under them.
//
// The palette is one of six moods (morning, midday, golden hour, dusk, overcast, night), and a
// change of mood is a cross-fade: every colour mixes from `mood_from` to `mood_to` by `blend`,
// and the two suns fade into each other rather than slide. The shapes are the same in every
// mood, so the land stays put while the light changes.

// The two moods mixed, 0 morning, 1 midday, 2 golden hour, 3 dusk, 4 overcast, 5 night.
uniform int mood_from = 0;
uniform int mood_to = 0;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
// The rect's size in pixels: the aspect keeps the shapes round and the edges a brush wide.
uniform vec2 rect_size = vec2(1920.0, 1080.0);
// 1 lets the clouds drift; 0 holds them (Reduce motion).
uniform float drift = 1.0;

// The four clouds: where each rests (x as a share of the width, y in heights from the foot),
// how wide it is in heights, its drift period in seconds (UI_TASTE: the painted world
// breathing, 60-90 s) and where in its sway it starts.
const vec2 CLOUD_AT[4] = { vec2(0.88, 0.76), vec2(0.47, 0.52), vec2(0.17, 0.66), vec2(0.62, 0.90) };
const float CLOUD_SCALE[4] = { 0.30, 0.20, 0.17, 0.26 };
const float DRIFT_S[4] = { 78.0, 64.0, 88.0, 71.0 };
const float DRIFT_PHASE[4] = { 0.0, 2.1, 4.0, 5.3 };
// Three poplars in the dip between the near hill's two rolls: where each stands (x as a share
// of the width), how tall it is and how wide at its fullest, in heights. Tall flames, not round
// crowns, so they read as trees at a glance and give the rolling land one upright accent. They
// stand left of centre, in the gap the room leaves between its side sheet and its stage, and
// balance the sun on the right.
const vec3 POPLAR[3] = { vec3(0.300, 0.130, 0.023), vec3(0.328, 0.096, 0.019), vec3(0.364, 0.112, 0.021) };

// Per mood: morning, midday, golden hour, dusk, overcast, night. Every far, near and meadow
// colour holds at least 25% saturation (the placeholder's rule), so no mood greys or muddies.
const vec3 SKY_TOP[6] = {
	vec3(0.55, 0.79, 0.94), vec3(0.54, 0.79, 0.96), vec3(0.64, 0.74, 0.93),
	vec3(0.45, 0.44, 0.76), vec3(0.68, 0.75, 0.92), vec3(0.19, 0.25, 0.51)
};
const vec3 SKY_LOW[6] = {
	vec3(0.99, 0.90, 0.75), vec3(0.86, 0.94, 0.97), vec3(1.00, 0.82, 0.57),
	vec3(0.99, 0.67, 0.53), vec3(0.94, 0.91, 0.95), vec3(0.44, 0.52, 0.80)
};
// The sun's disc (the moon's at night): near white, so it burns against any sky.
const vec3 SUN[6] = {
	vec3(1.00, 0.99, 0.93), vec3(1.00, 1.00, 0.97), vec3(1.00, 0.97, 0.84),
	vec3(1.00, 0.93, 0.78), vec3(0.99, 0.98, 0.97), vec3(0.99, 0.98, 0.92)
};
// The halo around it: warmer and more saturated than the disc, so the disc reads by colour as
// well as by light; at night a cool moonlit ring.
const vec3 SUN_GLOW[6] = {
	vec3(1.00, 0.86, 0.56), vec3(1.00, 0.95, 0.74), vec3(1.00, 0.70, 0.36),
	vec3(1.00, 0.58, 0.44), vec3(0.98, 0.96, 0.92), vec3(0.66, 0.74, 1.00)
};
// Where the sun sits (x as a share of the width, y in heights from the foot), its disc's
// radius (0 for a sun behind cloud) and how strong its wide glow is. Every disc stands clear
// of the distant range and under the big cloud's base, toward the right where the room's
// stage and the title's column leave the sky open; the lower the sun, the warmer and wider.
const vec4 SUN_AT[6] = {
	vec4(0.84, 0.57, 0.046, 0.55), vec4(0.90, 0.64, 0.042, 0.40), vec4(0.84, 0.53, 0.056, 0.80),
	vec4(0.82, 0.51, 0.060, 0.85), vec4(0.62, 0.58, 0.000, 0.30), vec4(0.86, 0.62, 0.040, 0.50)
};
const vec3 CLOUD_LIT[6] = {
	vec3(1.00, 0.98, 0.95), vec3(1.00, 1.00, 1.00), vec3(1.00, 0.89, 0.73),
	vec3(0.99, 0.73, 0.67), vec3(0.97, 0.97, 0.99), vec3(0.62, 0.68, 0.90)
};
const vec3 CLOUD_SHADE[6] = {
	vec3(0.80, 0.82, 0.94), vec3(0.78, 0.85, 0.96), vec3(0.80, 0.67, 0.80),
	vec3(0.58, 0.47, 0.72), vec3(0.72, 0.74, 0.88), vec3(0.31, 0.35, 0.62)
};
// How large the clouds are: overcast heaps them up.
const float CLOUD_SIZE[6] = { 1.0, 0.9, 1.05, 1.0, 1.35, 0.95 };
// The distant range: the sky's own hue a little deeper, light and luminous (mixing a blue
// range into a warm horizon greyed it).
const vec3 RANGE[6] = {
	vec3(0.64, 0.76, 0.92), vec3(0.62, 0.78, 0.95), vec3(0.88, 0.66, 0.84),
	vec3(0.80, 0.54, 0.70), vec3(0.66, 0.74, 0.90), vec3(0.32, 0.38, 0.70)
};
// The far ridge in the mood's atmospheric tint, a step deeper than the range: blue-green by
// day (green hills seen through air), lavender at golden hour, plum at dusk, deep periwinkle
// at night. Its value, not its hue, keeps it from reading as sea: darker than the sky, with
// a lit crest and no pale band at its foot.
const vec3 FAR[6] = {
	vec3(0.42, 0.68, 0.78), vec3(0.40, 0.66, 0.82), vec3(0.66, 0.52, 0.76),
	vec3(0.55, 0.36, 0.60), vec3(0.46, 0.64, 0.78), vec3(0.24, 0.30, 0.58)
};
const vec3 NEAR[6] = {
	vec3(0.49, 0.74, 0.41), vec3(0.45, 0.74, 0.35), vec3(0.80, 0.70, 0.34),
	vec3(0.43, 0.32, 0.60), vec3(0.42, 0.66, 0.52), vec3(0.20, 0.28, 0.53)
};
const vec3 MEADOW[6] = {
	vec3(0.34, 0.63, 0.31), vec3(0.29, 0.61, 0.27), vec3(0.47, 0.65, 0.25),
	vec3(0.29, 0.24, 0.47), vec3(0.29, 0.56, 0.40), vec3(0.13, 0.20, 0.41)
};
// The light along a crest facing the sun.
const vec3 RIM[6] = {
	vec3(0.70, 0.86, 0.46), vec3(0.62, 0.86, 0.38), vec3(0.95, 0.82, 0.42),
	vec3(0.78, 0.50, 0.60), vec3(0.56, 0.76, 0.56), vec3(0.34, 0.46, 0.72)
};
// The poplars in shadow: deeper and cooler than the hill they stand on, never black.
const vec3 TREE[6] = {
	vec3(0.26, 0.53, 0.36), vec3(0.24, 0.53, 0.30), vec3(0.46, 0.52, 0.26),
	vec3(0.34, 0.25, 0.50), vec3(0.26, 0.50, 0.42), vec3(0.17, 0.23, 0.48)
};

// A ridge line: three sines, so the skyline rolls without repeating on screen.
float wave(float x, float phase) {
	return 0.55 * sin(x + phase) + 0.3 * sin(x * 2.3 + phase * 1.7) + 0.15 * sin(x * 4.1 + phase * 2.9);
}

// How much of the point at height `y` lies under the line at height `h`, with a soft edge.
float under(float y, float h, float soft) {
	return 1.0 - smoothstep(h - soft, h + soft, y);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// A painted cumulus at `at`, `s` heights across: four puffs melted together on a flat base.
// Returns its coverage; `shade` is 0 on its sunlit crown and 1 along its base.
float cloud(vec2 p, vec2 at, float s, float soft, out float shade) {
	vec2 q = (p - at) / s;
	float d = length(q - vec2(-0.55, 0.02)) - 0.30;
	d = smin(d, length(q - vec2(-0.16, 0.20)) - 0.42, 0.12);
	d = smin(d, length(q - vec2(0.34, 0.12)) - 0.35, 0.12);
	d = smin(d, length(q - vec2(0.72, 0.0)) - 0.24, 0.12);
	d = max(d, -(q.y + 0.10));
	shade = 1.0 - smoothstep(-0.10, 0.42, q.y);
	return 1.0 - smoothstep(-soft, soft, d * s);
}

// The near hill's crest at `x`: a bold round shoulder on the right, a lower roll on the left.
float near_line(float x, float aspect) {
	float h = 0.11 + 0.17 * exp(-pow((x - 0.74 * aspect) / 0.5, 2.0)) + 0.012 * wave(x * 3.0, 2.4);
	return h + 0.05 * exp(-pow((x - 0.12 * aspect) / 0.3, 2.0));
}

// A sun (or the moon) of mood `i`, weighted by `w`, laid over `col`: a wide glow in the halo's
// colour, a tighter bloom hugging the disc, and the disc itself.
vec3 sun(vec3 col, vec2 p, float aspect, int i, float w, float soft) {
	vec4 at = SUN_AT[i];
	vec2 centre = vec2(at.x * aspect, at.y);
	float d = length(p - centre);
	col = mix(col, SUN_GLOW[i], w * at.w * exp(-d * d / 0.07));
	float has_disc = step(0.001, at.z);
	float bloom = exp(-pow(max(d - at.z, 0.0) / max(at.z * 1.4, 0.001), 2.0));
	col = mix(col, mix(SUN_GLOW[i], SUN[i], 0.45), w * has_disc * 0.8 * bloom);
	float disc = 1.0 - smoothstep(at.z - soft, at.z + soft, d);
	return mix(col, SUN[i], w * disc * has_disc);
}

void fragment() {
	int a = clamp(mood_from, 0, 5);
	int b = clamp(mood_to, 0, 5);
	float k = clamp(blend, 0.0, 1.0);
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	float y = 1.0 - UV.y;
	float x = UV.x * aspect;
	vec2 p = vec2(x, y);
	// A pixel and a half, in heights: the edges stay a brush's softness at any size.
	float soft = 1.5 / max(rect_size.y, 1.0);
	float t = TIME * drift;

	vec3 low = mix(SKY_LOW[a], SKY_LOW[b], k);
	vec3 top = mix(SKY_TOP[a], SKY_TOP[b], k);
	// The sky: the low wash warms the horizon, the top wash deepens overhead.
	vec3 col = mix(low, top, smoothstep(0.2, 1.0, y));
	col = sun(col, p, aspect, a, 1.0 - k, soft * 2.0);
	col = sun(col, p, aspect, b, k, soft * 2.0);

	// Four clouds, each swaying about its place over its own minute and more, so the
	// composition holds while the sky breathes.
	vec3 lit = mix(CLOUD_LIT[a], CLOUD_LIT[b], k);
	vec3 shade_col = mix(CLOUD_SHADE[a], CLOUD_SHADE[b], k);
	float size = mix(CLOUD_SIZE[a], CLOUD_SIZE[b], k);
	for (int c = 0; c < 4; c++) {
		float sway = 0.05 * aspect * sin(6.2831 * t / DRIFT_S[c] + DRIFT_PHASE[c]);
		vec2 at = vec2(CLOUD_AT[c].x * aspect + sway, CLOUD_AT[c].y);
		float under_shade;
		float cover = cloud(p, at, CLOUD_SCALE[c] * size, soft * 6.0, under_shade);
		col = mix(col, mix(lit, shade_col, 0.75 * under_shade), 0.94 * cover);
	}

	// The distant range: taller peaks almost lost in the sky, so the far ridge has land
	// behind it and the eye reads depth rather than a horizon.
	vec3 range_col = mix(RANGE[a], RANGE[b], k);
	float range_h = 0.40 + 0.085 * wave(x * 1.35 + 3.1, 4.2);
	range_col = mix(range_col, low, 0.2 * smoothstep(range_h - 0.1, range_h, y));
	col = mix(col, range_col, under(y, range_h, soft * 1.5));

	// The far ridge: rolling hills in the mood's tint, deeper toward their foot, their crests
	// taking on the range's light.
	float far_h = 0.33 + 0.085 * wave(x * 1.9 + 0.7, 1.3) + 0.026 * sin(x * 6.1 + 0.4);
	vec3 far_col = mix(FAR[a], FAR[b], k);
	far_col = mix(far_col * 0.93, far_col, smoothstep(far_h - 0.16, far_h - 0.03, y));
	far_col = mix(far_col, range_col, 0.3 * smoothstep(far_h - 0.035, far_h, y));
	col = mix(col, far_col, under(y, far_h, soft));

	// The poplars, rooted behind the near hill's crest: each a flame of foliage, fullest a
	// third of the way up and drawn to a soft point, in shadow and lit down its sunward side.
	vec3 rim = mix(RIM[a], RIM[b], k);
	vec3 tree_dark = mix(TREE[a], TREE[b], k);
	for (int i = 0; i < 3; i++) {
		float tx = POPLAR[i].x * aspect;
		vec2 q = p - vec2(tx, near_line(tx, aspect) - 0.012);
		float tall = POPLAR[i].y;
		float t = clamp(q.y / tall, 0.0, 1.0);
		float half_w = POPLAR[i].z * (0.75 + 0.6 * sin(3.1416 * pow(t, 0.62))) * (1.0 - 0.9 * t * t);
		float inside = (1.0 - smoothstep(half_w - soft * 1.5, half_w + soft * 1.5, abs(q.x)));
		inside *= step(0.0, q.y) * (1.0 - smoothstep(tall - soft, tall + soft, q.y));
		float sunlit = smoothstep(-0.35 * half_w, 0.6 * half_w, q.x + 0.25 * half_w * t);
		vec3 leaf = mix(tree_dark, mix(tree_dark, rim, 0.6), sunlit);
		col = mix(col, leaf, inside);
	}

	// The near hill, its crest catching the light.
	float near_h = near_line(x, aspect);
	vec3 near_col = mix(NEAR[a], NEAR[b], k);
	near_col = mix(near_col * 0.9, near_col, smoothstep(near_h - 0.14, near_h - 0.02, y));
	near_col = mix(near_col, rim, 0.55 * smoothstep(near_h - 0.025, near_h, y));
	col = mix(col, near_col, under(y, near_h, soft));

	// The meadow, rising toward the right, its crest catching the light.
	vec3 meadow = mix(MEADOW[a], MEADOW[b], k);
	float fore_h = 0.045 + 0.10 * smoothstep(0.25, 1.0, UV.x) + 0.012 * wave(x * 2.7 + 4.0, 0.6);
	vec3 fore_col = mix(meadow * 0.86, meadow, smoothstep(0.0, fore_h, y));
	fore_col = mix(fore_col, rim, 0.5 * smoothstep(fore_h - 0.02, fore_h, y));
	col = mix(col, fore_col, under(y, fore_h, soft));

	COLOR = vec4(col, COLOR.a);
}
