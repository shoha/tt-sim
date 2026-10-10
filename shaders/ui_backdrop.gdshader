shader_type canvas_item;

// The painted world every screen outside play stands on (scenes/ui/primitives/
// painted_backdrop.gd), and, in a small rect, the picture of a map with no thumbnail yet
// (map_placeholder.gd): one world, so a map's card and the screen behind it agree. A sky in two
// washes with one sun in a warm halo (a smaller, cooler crescent moon and a scatter of stars at
// night), four bold cumulus clouds with soft rounded bases that drift very slowly, a pale
// distant range and a rolling far ridge in the mood's own atmospheric tint, a few poplars
// rising from behind the near hill, and a meadow rising to the right. A few bold, soft-edged
// shapes; no textures and no noise. The painting carries no words: the screens on it put
// theirs on paper (sheets and plaques).
//
// The shader paints one look. Everything it is told comes from BackdropPaint on the CPU: the
// colours (a cross-fade mixes two moods there, in OKLCH, so a change of light keeps its
// saturation), where the sun or moon sits (in the open sky the screen's layout leaves, so no
// card or sheet hides it), and where each cloud and poplar stands (drawn from the map's seed,
// then moved clear of the screen's paper). A change is a fade of those values, never of two
// pictures.

// The rect's size in pixels: the aspect keeps the shapes round and the edges a brush wide.
uniform vec2 rect_size = vec2(1920.0, 1080.0);
// 1 lets the clouds drift; 0 holds them (Reduce motion).
uniform float drift = 1.0;
// The map's seed, in [0, 1): where the stars fall.
uniform float seed = 0.0;

// The light (BackdropPaint.MOODS, mixed).
uniform vec3 sky_top = vec3(0.55, 0.79, 0.94);
uniform vec3 sky_low = vec3(0.99, 0.90, 0.75);
uniform vec3 sun_col = vec3(1.00, 0.99, 0.93);
uniform vec3 sun_glow = vec3(1.00, 0.86, 0.56);
uniform vec3 cloud_lit = vec3(1.00, 0.98, 0.95);
uniform vec3 cloud_shade = vec3(0.80, 0.82, 0.94);
uniform vec3 range_col = vec3(0.64, 0.76, 0.92);
uniform vec3 far_col = vec3(0.42, 0.68, 0.78);
uniform vec3 near_col = vec3(0.49, 0.74, 0.41);
uniform vec3 meadow_col = vec3(0.34, 0.63, 0.31);
uniform vec3 rim_col = vec3(0.70, 0.86, 0.46);
uniform vec3 tree_shade = vec3(0.16, 0.45, 0.40);
uniform vec3 tree_lit = vec3(0.62, 0.80, 0.36);
uniform float cloud_size = 1.0;
// How many stars show, 0 by day, 1 at night.
uniform float stars = 0.0;

// The sun (or the moon): its centre in heights from the left and from the foot, its disc's
// radius in heights, and how strong its wide glow is.
uniform vec4 sun_at = vec4(1.5, 0.6, 0.046, 0.55);
// How much of the disc shows (0: behind cloud, overcast) and how much it is the moon (a
// crescent, its dark side the sky's own colour).
uniform vec2 sun_look = vec2(1.0, 0.0);
// The skyline: the distant range's phase, the far ridge's phase, the near hill's phase and the
// far ridge's undulation, all drawn from the map's seed.
uniform vec4 ridges = vec4(4.2, 1.3, 2.4, 0.085);
// The clouds: where each rests (heights from the left, heights from the foot), its width in
// heights (0: no cloud) and its shape, 0 to 1.
uniform vec4 cloud0 = vec4(1.56, 0.76, 0.30, 0.2);
uniform vec4 cloud1 = vec4(0.84, 0.52, 0.20, 0.7);
uniform vec4 cloud2 = vec4(0.30, 0.66, 0.17, 0.4);
uniform vec4 cloud3 = vec4(1.10, 0.90, 0.26, 0.9);
// The poplars: where each stands (heights from the left), how tall it is (0: none) and how
// wide at its fullest; w is unused.
uniform vec4 poplar0 = vec4(0.53, 0.130, 0.023, 0.0);
uniform vec4 poplar1 = vec4(0.58, 0.096, 0.019, 0.0);
uniform vec4 poplar2 = vec4(0.65, 0.112, 0.021, 0.0);
uniform vec4 poplar3 = vec4(0.0, 0.0, 0.0, 0.0);

// The clouds' drift periods in seconds (UI_TASTE: the painted world breathing, 60-90 s), how
// far each sways about its place, in heights, and where in its sway it starts.
const float DRIFT_S[4] = { 78.0, 64.0, 88.0, 71.0 };
const float DRIFT_PHASE[4] = { 0.0, 2.1, 4.0, 5.3 };
const float SWAY = 0.045;

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

float smax(float a, float b, float k) {
	return -smin(-a, -b, k);
}

float hash12(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

// A painted cumulus at `at`, `s` heights across: four puffs melted together, their sizes and
// places nudged by `shape`, on a soft base that rounds up toward its ends (a ruled base read as
// the edge of a card). Returns its coverage; `shade` is 0 on its sunlit crown and 1 along its
// base.
float cloud(vec2 p, vec2 at, float s, float shape, float soft, out float shade) {
	vec2 q = (p - at) / s;
	float v = shape;
	float d = length(q - vec2(-0.55, 0.02 + 0.05 * v)) - (0.25 + 0.09 * v);
	d = smin(d, length(q - vec2(-0.16 - 0.08 * v, 0.20)) - (0.36 + 0.10 * (1.0 - v)), 0.12);
	d = smin(d, length(q - vec2(0.30 + 0.08 * v, 0.10 + 0.06 * v)) - (0.31 + 0.06 * v), 0.12);
	d = smin(d, length(q - vec2(0.70 + 0.06 * v, 0.0)) - (0.19 + 0.09 * (1.0 - v)), 0.12);
	d = smax(d, -(q.y + 0.10 - 0.14 * q.x * q.x), 0.08);
	shade = 1.0 - smoothstep(-0.10, 0.42, q.y);
	return 1.0 - smoothstep(-soft, soft, d * s);
}

// The near hill's crest at `x`: a bold round shoulder on the right, a lower roll on the left
// (BackdropPaint.near_line is the same line, where it stands the poplars).
float near_line(float x, float aspect) {
	float h = 0.11 + 0.17 * exp(-pow((x - 0.74 * aspect) / 0.5, 2.0)) + 0.012 * wave(x * 3.0, ridges.z);
	return h + 0.05 * exp(-pow((x - 0.12 * aspect) / 0.3, 2.0));
}

// The sun or the moon over `col`: a wide glow in the halo's colour, a tighter bloom hugging
// the disc, and the disc itself; as the moon, a crescent whose dark side is the sky behind it.
vec3 draw_sun(vec3 col, vec2 p, float soft) {
	vec2 centre = sun_at.xy;
	float r = max(sun_at.z, 0.001);
	float d = length(p - centre);
	col = mix(col, sun_glow, sun_at.w * exp(-d * d / 0.07));
	float shown = sun_look.x;
	float moon = sun_look.y;
	float bloom = exp(-pow(max(d - r, 0.0) / (r * 1.4), 2.0));
	vec3 sky = col;
	col = mix(col, mix(sun_glow, sun_col, 0.45), shown * (0.8 - 0.5 * moon) * bloom);
	float disc = 1.0 - smoothstep(r - soft, r + soft, d);
	vec2 dark_at = centre + vec2(-0.45, 0.24) * r;
	float dark = 1.0 - smoothstep(r * 0.92 - soft, r * 0.92 + soft, length(p - dark_at));
	vec3 face = mix(sun_col, mix(sky, sun_col, 0.12), moon * dark);
	return mix(col, face, shown * disc);
}

void fragment() {
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	float y = 1.0 - UV.y;
	float x = UV.x * aspect;
	vec2 p = vec2(x, y);
	// A pixel and a half, in heights: the edges stay a brush's softness at any size.
	float px = 1.0 / max(rect_size.y, 1.0);
	float soft = 1.5 * px;
	float t = TIME * drift;

	// The sky: the low wash warms the horizon, the top wash deepens overhead.
	vec3 col = mix(sky_low, sky_top, smoothstep(0.2, 1.0, y));
	// Stars at night: one soft dot in some cells of a coarse grid, more toward the top, none
	// low over the land; a few bold points rather than a dust.
	if (stars > 0.001) {
		float cell = max(0.05, 30.0 * px);
		vec2 c = floor(p / cell);
		float h = hash12(c + vec2(seed * 97.0, 3.0));
		vec2 at = (c + 0.2 + 0.6 * vec2(fract(h * 13.7), fract(h * 71.3))) * cell;
		float r = (1.0 + 1.4 * fract(h * 37.1)) * px;
		float dot_ = 1.0 - smoothstep(r * 0.35, r, length(p - at));
		float shown = step(0.6, h) * smoothstep(0.5, 0.8, y);
		col = mix(col, vec3(1.0, 0.98, 0.90), stars * shown * dot_ * (0.55 + 0.45 * fract(h * 5.3)));
	}
	col = draw_sun(col, p, soft * 2.0);

	// Four clouds, each swaying about its place over its own minute and more, so the
	// composition holds while the sky breathes.
	vec4 clouds[4] = { cloud0, cloud1, cloud2, cloud3 };
	for (int i = 0; i < 4; i++) {
		vec4 cl = clouds[i];
		if (cl.z < 0.001) {
			continue;
		}
		float sway = SWAY * sin(6.2831 * t / DRIFT_S[i] + DRIFT_PHASE[i] + cl.w * 6.2831);
		float under_shade;
		// A soft brush edge on the screen, a pixel or three in a card's small picture.
		float edge = max(soft * 2.0, 0.006);
		float cover = cloud(p, vec2(cl.x + sway, cl.y), cl.z * cloud_size, cl.w, edge, under_shade);
		col = mix(col, mix(cloud_lit, cloud_shade, 0.75 * under_shade), 0.94 * cover);
	}

	// The distant range: taller peaks almost lost in the sky, so the far ridge has land
	// behind it and the eye reads depth rather than a horizon.
	float range_h = 0.40 + 0.085 * wave(x * 1.35 + 3.1, ridges.x);
	vec3 range_tint = mix(range_col, sky_low, 0.2 * smoothstep(range_h - 0.1, range_h, y));
	col = mix(col, range_tint, under(y, range_h, soft * 1.5));

	// The far ridge: rolling hills in the mood's tint, deeper toward their foot, their crests
	// taking on the range's light.
	float far_h = 0.33 + ridges.w * wave(x * 1.9 + 0.7, ridges.y) + 0.026 * sin(x * 6.1 + ridges.y);
	vec3 far_tint = mix(far_col * 0.93, far_col, smoothstep(far_h - 0.16, far_h - 0.03, y));
	far_tint = mix(far_tint, range_tint, 0.3 * smoothstep(far_h - 0.035, far_h, y));
	col = mix(col, far_tint, under(y, far_h, soft));

	// The poplars, rooted behind the near hill's crest: each a flame of foliage, fullest a
	// third of the way up and drawn to a soft point, in cool shade and lit down the side that
	// faces the sun.
	vec4 poplars[4] = { poplar0, poplar1, poplar2, poplar3 };
	for (int i = 0; i < 4; i++) {
		vec4 tree = poplars[i];
		float tall = tree.y;
		if (tall < 0.001) {
			continue;
		}
		vec2 q = p - vec2(tree.x, near_line(tree.x, aspect) - 0.012);
		float k = clamp(q.y / tall, 0.0, 1.0);
		float half_w = tree.z * (0.75 + 0.6 * sin(3.1416 * pow(k, 0.62))) * (1.0 - 0.9 * k * k);
		float inside = 1.0 - smoothstep(half_w - soft * 1.5, half_w + soft * 1.5, abs(q.x));
		inside *= step(0.0, q.y) * (1.0 - smoothstep(tall - soft, tall + soft, q.y));
		float side = sun_at.x >= tree.x ? 1.0 : -1.0;
		float sunlit = smoothstep(-0.35 * half_w, 0.6 * half_w, side * q.x + 0.25 * half_w * k);
		col = mix(col, mix(tree_shade, tree_lit, 0.85 * sunlit), inside);
	}

	// The near hill, its crest catching the light.
	float near_h = near_line(x, aspect);
	vec3 near_tint = mix(near_col * 0.9, near_col, smoothstep(near_h - 0.14, near_h - 0.02, y));
	near_tint = mix(near_tint, rim_col, 0.55 * smoothstep(near_h - 0.025, near_h, y));
	col = mix(col, near_tint, under(y, near_h, soft));

	// The meadow, rising toward the right, its crest catching the light.
	float fore_h = 0.045 + 0.10 * smoothstep(0.25, 1.0, UV.x) + 0.012 * wave(x * 2.7 + 4.0, 0.6);
	vec3 fore_col = mix(meadow_col * 0.86, meadow_col, smoothstep(0.0, fore_h, y));
	fore_col = mix(fore_col, rim_col, 0.5 * smoothstep(fore_h - 0.02, fore_h, y));
	col = mix(col, fore_col, under(y, fore_h, soft));

	COLOR = vec4(col, COLOR.a);
}
