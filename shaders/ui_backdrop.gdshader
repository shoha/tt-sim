shader_type canvas_item;

// The painted backdrop every screen outside play stands on (scenes/ui/primitives/
// painted_backdrop.gd): the map placeholder's language (shaders/ui_map_placeholder.gdshader)
// at the size of the screen. A sky in two washes with a soft sun (a moon at night), four bold
// cumulus clouds with flat bases that drift very slowly, a hazy far ridge with mist at its
// foot, a round near hill with a stand of trees on its shoulder, and a meadow rising to the
// right. A few bold, soft-edged shapes; no textures and no noise.
//
// The palette is one of six moods (morning, midday, golden hour, dusk, overcast, night), and a
// change of mood is a cross-fade: every colour mixes from `mood_from` to `mood_to` by `blend`,
// and the two suns fade into each other rather than slide. The shapes are the same in every
// mood, so the land stays put while the light changes.
//
// The words that sit straight on the backdrop (the title's column, the room's heading) keep
// their contrast in every mood: inside a zone (a rect in the rect's own pixels, feathered) any
// colour darker than LEGIBLE_LUMINANCE is lifted toward the mood's haze just far enough, mixed
// in linear light, so ink-soft captions hold 4.5:1. Over a day sky that changes nothing; over a
// night it is a pale mist under the words.

// The two moods mixed, 0 morning, 1 midday, 2 golden hour, 3 dusk, 4 overcast, 5 night.
uniform int mood_from = 0;
uniform int mood_to = 0;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
// The rect's size in pixels: the aspect keeps the shapes round and the zones are in pixels.
uniform vec2 rect_size = vec2(1920.0, 1080.0);
// 1 lets the clouds drift; 0 holds them (Reduce motion).
uniform float drift = 1.0;
// Up to four zones (x0, y0, x1, y1 in the rect's pixels) where the words sit.
uniform vec4 zones[4];
uniform int zone_count = 0;
uniform float zone_feather = 48.0;

// The relative luminance the painting keeps under words: INK_SOFT (0.088) reads 4.7:1 on it.
const float LEGIBLE_LUMINANCE = 0.6;
// The four clouds: where each rests (x as a share of the width, y in heights from the foot),
// how wide it is in heights, its drift period in seconds (UI_TASTE: the painted world
// breathing, 60-90 s) and where in its sway it starts.
const vec2 CLOUD_AT[4] = { vec2(0.88, 0.76), vec2(0.47, 0.52), vec2(0.17, 0.66), vec2(0.62, 0.90) };
const float CLOUD_SCALE[4] = { 0.30, 0.20, 0.17, 0.26 };
const float DRIFT_S[4] = { 78.0, 64.0, 88.0, 71.0 };
const float DRIFT_PHASE[4] = { 0.0, 2.1, 4.0, 5.3 };

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
const vec3 SUN[6] = {
	vec3(1.00, 0.97, 0.86), vec3(1.00, 1.00, 0.94), vec3(1.00, 0.91, 0.64),
	vec3(1.00, 0.80, 0.58), vec3(0.99, 0.98, 0.97), vec3(0.98, 0.97, 0.90)
};
// Where the sun sits (x as a share of the width, y in heights from the foot), its disc's
// radius (0 for a sun behind cloud) and how far its glow reaches.
const vec4 SUN_AT[6] = {
	vec4(0.64, 0.40, 0.050, 0.55), vec4(0.88, 0.63, 0.045, 0.35), vec4(0.80, 0.35, 0.065, 0.85),
	vec4(0.70, 0.25, 0.070, 0.95), vec4(0.62, 0.58, 0.000, 0.30), vec4(0.86, 0.57, 0.042, 0.45)
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
const vec3 FAR[6] = {
	vec3(0.55, 0.78, 0.80), vec3(0.50, 0.72, 0.88), vec3(0.71, 0.58, 0.85),
	vec3(0.64, 0.43, 0.67), vec3(0.54, 0.66, 0.84), vec3(0.32, 0.38, 0.69)
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
// The pale light the words sit in (see LEGIBLE_LUMINANCE).
const vec3 HAZE[6] = {
	vec3(0.96, 0.95, 0.91), vec3(0.94, 0.97, 0.98), vec3(1.00, 0.94, 0.86),
	vec3(0.99, 0.89, 0.88), vec3(0.95, 0.95, 0.98), vec3(0.80, 0.83, 0.96)
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

// A rounded rect's signed distance in pixels.
float zone_distance(vec2 px, vec4 r, float radius) {
	vec2 centre = (r.xy + r.zw) * 0.5;
	vec2 half_size = (r.zw - r.xy) * 0.5;
	vec2 q = abs(px - centre) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// A sun (or the moon) of mood `i`, weighted by `w`, laid over `col`.
vec3 sun(vec3 col, vec2 p, float aspect, int i, float w, float soft) {
	vec4 at = SUN_AT[i];
	vec2 centre = vec2(at.x * aspect, at.y);
	float d2 = dot(p - centre, p - centre);
	col = mix(col, SUN[i], w * at.w * exp(-d2 / 0.06));
	float disc = 1.0 - smoothstep(at.z - soft, at.z + soft, sqrt(d2));
	return mix(col, SUN[i], w * disc * step(0.001, at.z));
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

	// The far ridge, in haze: mist pools at its foot.
	float far_h = 0.30 + 0.045 * wave(x * 2.2 + 0.7, 1.3) + 0.05 * smoothstep(0.1, 0.9, UV.x);
	vec3 far_col = mix(FAR[a], FAR[b], k);
	far_col = mix(far_col, low, 0.2 * smoothstep(far_h - 0.2, far_h, y));
	float mist = 1.0 - smoothstep(far_h - 0.22, far_h - 0.1, y);
	far_col = mix(far_col, mix(low, vec3(1.0), 0.3), 0.55 * mist);
	col = mix(col, far_col, under(y, far_h, soft));

	// The near hill: a bold round shoulder on the right, a lower roll on the left.
	float hill_x = 0.74 * aspect;
	float near_h = 0.11 + 0.17 * exp(-pow((x - hill_x) / 0.5, 2.0)) + 0.012 * wave(x * 3.0, 2.4);
	near_h += 0.05 * exp(-pow((x - 0.12 * aspect) / 0.3, 2.0));
	vec3 near_col = mix(NEAR[a], NEAR[b], k);
	vec3 rim = mix(RIM[a], RIM[b], k);
	near_col = mix(near_col * 0.9, near_col, smoothstep(near_h - 0.14, near_h - 0.02, y));
	near_col = mix(near_col, rim, 0.55 * smoothstep(near_h - 0.025, near_h, y));
	col = mix(col, near_col, under(y, near_h, soft));

	// A stand of three trees on the hill's shoulder, dark against it, lit on their crowns.
	vec3 meadow = mix(MEADOW[a], MEADOW[b], k);
	vec3 crown_col = meadow * 0.82;
	float trees = 0.0;
	float crown_lit = 0.0;
	for (int i = 0; i < 3; i++) {
		float tx = (0.56 + 0.035 * float(i)) * aspect;
		float r = 0.034 - 0.006 * float(i);
		float base = 0.11 + 0.17 * exp(-pow((tx - hill_x) / 0.5, 2.0));
		vec2 c = vec2(tx, base + r * 1.1);
		vec2 squash = vec2(1.0, 0.82);
		float crown = 1.0 - smoothstep(r - soft, r + soft, length((p - c) * squash));
		trees = max(trees, crown);
		crown_lit = max(crown_lit, crown * smoothstep(c.y, c.y + r * 0.9, y));
	}
	col = mix(col, mix(crown_col, rim, 0.45 * crown_lit), trees);

	// The meadow, rising toward the right, its crest catching the light.
	float fore_h = 0.045 + 0.10 * smoothstep(0.25, 1.0, UV.x) + 0.012 * wave(x * 2.7 + 4.0, 0.6);
	vec3 fore_col = mix(meadow * 0.86, meadow, smoothstep(0.0, fore_h, y));
	fore_col = mix(fore_col, rim, 0.5 * smoothstep(fore_h - 0.02, fore_h, y));
	col = mix(col, fore_col, under(y, fore_h, soft));

	// Under the words, lift anything too dark toward the haze, in linear light.
	vec2 px = UV * rect_size;
	float zone = 0.0;
	for (int z = 0; z < 4; z++) {
		if (z < zone_count) {
			float d = zone_distance(px, zones[z], 24.0);
			zone = max(zone, 1.0 - smoothstep(0.0, zone_feather, d));
		}
	}
	if (zone > 0.0) {
		vec3 haze = mix(HAZE[a], HAZE[b], k);
		vec3 lin = pow(col, vec3(2.2));
		vec3 haze_lin = pow(haze, vec3(2.2));
		vec3 weights = vec3(0.2126, 0.7152, 0.0722);
		float lum = dot(lin, weights);
		float haze_lum = dot(haze_lin, weights);
		float lift = clamp((LEGIBLE_LUMINANCE - lum) / max(haze_lum - lum, 0.001), 0.0, 1.0);
		col = pow(mix(lin, haze_lin, lift * zone), vec3(1.0 / 2.2));
	}

	COLOR = vec4(col, COLOR.a);
}
