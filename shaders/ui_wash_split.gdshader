shader_type canvas_item;

// The Play together card's two watercolour washes (PlayTogetherCard) inside a pill: persimmon
// (warm, left, Host) and lake (cool, right, Join), meeting in a wet seam at `split` (a share
// of the width). Each wash pools darker along its own edge, as a drying wash does, and a
// paper hairline breathes between them, so the two never mix into mud. `disc` pulls the warm
// wash into a blot at the left end (Join in place: the lake takes the card, Host becomes a
// persimmon disc); there the hairline closes, so the blot reads as wet into wet rather than a
// cut-out with a paper rim. Every length is in the card's own pixels (`rect_size`).

uniform vec4 warm : source_color = vec4(0.706, 0.271, 0.165, 1.0);
uniform vec4 cool : source_color = vec4(0.165, 0.408, 0.502, 1.0);
uniform vec4 paper : source_color = vec4(0.980, 0.953, 0.890, 1.0);
// Seam position as a share of the width (0.5 at rest; 0.56 / 0.44 with a face picked).
uniform float split : hint_range(0.0, 1.0) = 0.5;
// Pigment density: deepens the pooled edges and the mottle while pressed.
uniform float press : hint_range(0.0, 1.0) = 0.0;
// 0: seam across the card; 1: the warm wash is a disc at the left end.
uniform float disc : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(336.0, 112.0);
// The seam wanders this far either side of `split`, with one soft wiggle per `seam_scale` px.
uniform float seam_amp = 5.0;
uniform float seam_scale = 40.0;
// Paper hairline between the washes (its width breathes from none to twice this), and the
// pooled (darker) band along each wash edge.
uniform float gap_px = 1.4;
uniform float pool_px = 4.0;
uniform float pool_dark = 0.14;
// Value mottle inside each wash (share of the colour) and its blot size in px: a few large
// soft blots, not grain.
uniform float mottle = 0.05;
uniform float mottle_px = 70.0;
// Slow drift of the wet edge; 0 under Reduce motion.
uniform float drift = 1.0;
uniform float seed = 3.0;

// Lattice inputs stay small (under a few hundred), so the sine hash keeps its precision.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octaves of value noise, centred on 0 (about -0.45 to 0.45). Each octave is turned by about
// 37 degrees so the lattice never lines up into stripes.
float fbm(vec2 p, int octaves) {
	const mat2 turn = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float sum = 0.0;
	float amp = 0.5;
	for (int k = 0; k < octaves; k++) {
		sum += amp * (vnoise(p) - 0.5);
		p = turn * p * 2.07 + vec2(17.1, 3.7);
		amp *= 0.5;
	}
	return sum * 1.6;
}

void fragment() {
	vec2 px = UV * rect_size;
	float t = TIME * 0.04 * drift;
	float r = rect_size.y * 0.5;

	// Pill: signed distance, negative inside.
	vec2 axis = vec2(clamp(px.x, r, rect_size.x - r), r);
	float d_pill = length(px - axis) - r;
	float aa_pill = max(fwidth(d_pill), 0.0001);
	float inside = 1.0 - smoothstep(-aa_pill, aa_pill, d_pill);

	// The seam: a slow, soft wander, as the edge where two wet washes met.
	float wander = fbm(vec2(px.y / seam_scale, seed + t), 2) * 2.0 * seam_amp;
	float seam_sd = px.x - (split * rect_size.x + wander);

	// The disc (Join in place): a blot centred in the left cap, its rim wobbling gently and
	// a little more than the seam does, as pigment dropped into a wet patch spreads.
	vec2 to_disc = px - vec2(r, r);
	float ang = atan(to_disc.y, to_disc.x);
	vec2 around = vec2(cos(ang), sin(ang)) * 1.3 + vec2(seed + t, seed);
	float rim = fbm(around, 2) * seam_amp * 1.3;
	float disc_sd = length(to_disc) - (r * 0.64 + rim);

	// Negative: warm side.
	float warm_sd = mix(seam_sd, disc_sd, disc);
	// A wider, softer edge on the disc: a blot's edge bleeds a little where a cut edge is sharp.
	float aa = max(fwidth(warm_sd), mix(0.35, 1.1, disc));
	// The hairline breathes along the edge: here the washes touch, there a sliver of paper.
	// smoothstep, not a clamp, so the sliver opens with a fade instead of a kink. On the disc it
	// closes: a paper ring round the blot read as a cut-out sticker.
	float breathe = smoothstep(0.0, 1.0, 0.5 + fbm(vec2(px.y / 34.0, seed * 5.0), 1) * 2.2);
	float half_gap = gap_px * breathe * (1.0 - disc);
	float warm_cov = 1.0 - smoothstep(-half_gap - aa, -half_gap + aa, warm_sd);
	float cool_cov = smoothstep(half_gap - aa, half_gap + aa, warm_sd);

	// Pooling along each wash's edge (the seam and the pill rim), deeper while pressed.
	float dark = pool_dark * (1.0 + press * 0.6);
	float pool_seam = exp(-max(abs(warm_sd) - half_gap, 0.0) / pool_px);
	float pool_rim = exp(-max(-d_pill, 0.0) / (pool_px * 1.4)) * 0.6;
	float pool = clamp(pool_seam + pool_rim, 0.0, 1.0) * dark;

	// Mottle: soft blots of more and less pigment, fixed to the paper.
	float m = fbm(px / mottle_px + vec2(seed * 7.0, 1.3), 2) * 2.0 * mottle * (1.0 + press);
	vec3 warm_col = warm.rgb * (1.0 - pool) * (1.0 + m);
	vec3 cool_col = cool.rgb * (1.0 - pool) * (1.0 - m);

	// The two coverages never sum past 1 (the gap is never negative), so paper takes what they
	// leave: where the washes touch they meet edge to edge, with no paper mixed into the seam.
	float paper_cov = clamp(1.0 - warm_cov - cool_cov, 0.0, 1.0);
	vec3 col = paper.rgb * paper_cov + warm_col * warm_cov + cool_col * cool_cov;
	COLOR = vec4(col, inside * COLOR.a);
}
