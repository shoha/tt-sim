shader_type canvas_item;

// The Play together card's two watercolour washes (PlayTogetherCard) inside a pill: persimmon
// (warm, left, Host) and lake (cool, right, Join), meeting in a wet seam at `split` (a share
// of the width). Each wash is a few large, soft value shifts at its own hue, worked in OKLab
// lightness: a lighter bloom in the open band between its words and the seam, swelling and
// thinning along it; a pooled darker edge along the pill's rim and along the seam where the
// washes part; slow mottle in big blots and the faintest granulation. (A darker frill round
// the bloom, as a back-run dries, was tried and drawn as outlines at this size.) Nothing
// lightens a wash under its words (`text_warm`, `text_cool`): there it stays at or below its
// own colour, the rest token, so paper words keep 4.5:1. At the seam the washes bleed into each
// other over a few px with soft fingers, and where they part a soft light line of paper shows
// (it breathes along the seam, closing where they touch). The words' no-lightening mask fades
// over `text_feather` (24 px or more) and its seam side follows the seam's own wobble, so as a
// face narrows its bloom thins to a soft glow along the seam rather than a straight-edged bar;
// the mottle is round blots, never the lattice streaks of value noise. `disc` pulls the warm wash into a
// blot at the left end that then dries away (Join in place: the lake takes the card and the
// back disc stands where the blot was). `focus` draws a soft paper ring just inside the picked
// face (`focus_side`: -1 Host, 1 Join). Every length is in the card's own pixels (`rect_size`).

uniform vec4 warm : source_color = vec4(0.706, 0.271, 0.165, 1.0);
uniform vec4 cool : source_color = vec4(0.165, 0.408, 0.502, 1.0);
uniform vec4 paper : source_color = vec4(0.980, 0.953, 0.890, 1.0);
// Seam position as a share of the width (0.5 at rest; 0.56 / 0.44 with a face picked).
uniform float split : hint_range(0.0, 1.0) = 0.5;
// Pigment density: deepens the pooled edges and the mottle while pressed.
uniform float press : hint_range(0.0, 1.0) = 0.0;
// 0: seam across the card; 1: the warm wash has drawn into a blot at the left end and gone.
uniform float disc : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(336.0, 112.0);
// Each face's words (x0, y0, x1, y1): no wash lightens under them.
uniform vec4 text_warm = vec4(20.0, 22.0, 120.0, 84.0);
uniform vec4 text_cool = vec4(216.0, 22.0, 316.0, 84.0);
// How far past the words the no-lightening mask holds, then fades over `text_feather`.
uniform float text_pad = 4.0;
uniform float text_feather = 26.0;
// The seam wanders this far either side of `split`, with one soft wiggle per `seam_scale` px.
uniform float seam_amp = 5.0;
uniform float seam_scale = 40.0;
// The bleed: each wash feathers into the other over this many px either side, its edge
// wandering `finger_px` either way in soft fingers.
uniform float bleed_px = 3.0;
uniform float finger_px = 0.9;
// The light line where the washes part: its strength breathes between these.
uniform float line_min = 0.12;
uniform float line_max = 0.5;
// Steps of OKLab lightness: the bloom (up), the seam and rim pools (down), the mottle (either
// way) and the granulation (down).
uniform float bloom_l = 0.14;
uniform float pool_l = 0.07;
uniform float rim_l = 0.06;
uniform float mottle_l = 0.025;
uniform float grain_l = 0.008;
// The pools' depth in px, the bloom's distance in from the seam and its half width, the blot
// sizes of the mottle and the granulation.
uniform float pool_px = 3.5;
uniform float bloom_in = 18.0;
uniform float bloom_w = 20.0;
uniform float mottle_px = 55.0;
uniform float grain_px = 8.0;
uniform float focus : hint_range(0.0, 1.0) = 0.0;
uniform float focus_side = -1.0;
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

// Soft round blots: one gaussian per lattice cell at a random spot, of random sign and
// strength, summed over the cell's neighbours (about -0.6 to 0.6). Round by construction,
// where octaves of value noise read as streaks along the lattice at this size.
float round_blots(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float sum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 spot = g + vec2(hash(cell + g), hash(cell + g + vec2(7.3, 1.9))) - f;
			float w = hash(cell + g + vec2(3.1, 5.7)) * 2.0 - 1.0;
			sum += w * exp(-dot(spot, spot) * 3.0);
		}
	}
	return sum * 0.5;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 oklab_of(vec3 srgb) {
	vec3 c = to_linear(srgb);
	float l = pow(max(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 0.0), 1.0 / 3.0);
	float m = pow(max(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 0.0), 1.0 / 3.0);
	float s = pow(max(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 0.0), 1.0 / 3.0);
	return vec3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	);
}

vec3 srgb_of(vec3 lab) {
	float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
	l = l * l * l;
	m = m * m * m;
	s = s * s * s;
	vec3 lin = vec3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	);
	return to_srgb(clamp(lin, 0.0, 1.0));
}

// A wash colour moved `dl` in lightness at its own hue; darker steps trim a little chroma, so a
// pool deepens rather than going muddy (UI_TASTE C8).
vec3 stepped(vec3 lab, float dl) {
	float trim = 1.0 - 0.8 * max(-dl, 0.0);
	return vec3(lab.x + dl, lab.yz * trim);
}

// 1 under a face's words (the rect `r` grown by text_pad), fading to 0 over text_feather.
float text_mask(vec2 px, vec4 r) {
	vec2 centre = (r.xy + r.zw) * 0.5;
	vec2 half_size = (r.zw - r.xy) * 0.5 + text_pad;
	vec2 q = abs(px - centre) - half_size;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	return 1.0 - smoothstep(0.0, text_feather, d);
}

// One wash's lightness step at `px`: `in_seam` px in from its seam edge, `in_rim` px in from
// the pill's rim, `words` its words' mask, `open` how much of the bloom shows, `k` the face (0
// warm, 1 cool) for its own noise, `parted` how far the washes part here (0 touching).
float face_step(vec2 px, float in_seam, float in_rim, float words, float open, float k, float parted) {
	float deep = 1.0 + press * 0.6;
	float pool = exp(-max(in_seam, 0.0) / pool_px) * pool_l * mix(0.35, 1.0, parted);
	pool += exp(-max(in_rim, 0.0) / (pool_px * 1.6)) * rim_l;
	// The bloom: a soft lighter body in from the seam that swells and thins along it (big,
	// smooth noise with no threshold, so it never breaks into blocks), and fades toward the rim.
	// Squares by hand: pow() of a negative base is undefined in GLSL.
	float z = (in_seam - bloom_in) / bloom_w;
	float band = exp(-z * z);
	vec2 blot = vec2(px.x / 120.0, px.y / 48.0) + vec2(k * 11.0 + seed, 2.0 + k * 3.0);
	float swell = clamp(0.62 + fbm(blot, 2) * 1.1, 0.0, 1.0);
	float light = bloom_l * band * swell * smoothstep(0.0, 18.0, in_rim) * open;
	vec2 blots = px / mottle_px + vec2(seed * 7.0 + k * 5.0, 1.3);
	float m = round_blots(blots) * 1.6 * mottle_l * (1.0 + press);
	float grain = smoothstep(0.6, 0.95, vnoise(px / grain_px + vec2(k * 31.0, seed))) * grain_l;
	float lift = (light + max(m, 0.0)) * (1.0 - words);
	return lift + min(m, 0.0) - pool * deep - grain;
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
	float in_rim = -d_pill;

	// The seam: a slow, soft wander, as the edge where two wet washes met.
	float wander = fbm(vec2(px.y / seam_scale, seed + t), 2) * 2.0 * seam_amp;
	float seam_sd = px.x - (split * rect_size.x + wander);

	// The blot (Join in place): centred in the left cap, its rim wobbling gently, shrinking to
	// nothing as `disc` ends, so no persimmon is left round the back disc.
	vec2 to_disc = px - vec2(r, r);
	float ang = atan(to_disc.y, to_disc.x);
	vec2 around = vec2(cos(ang), sin(ang)) * 1.3 + vec2(seed + t, seed);
	float rim = fbm(around, 2) * seam_amp * 1.3;
	float shrink = 1.0 - smoothstep(0.55, 1.0, disc);
	float disc_sd = length(to_disc) - (r * 0.64 + rim) * shrink;

	// Negative: warm side. Soft fingers along the seam where the washes bleed.
	float finger = fbm(vec2(px.y / 18.0, seed * 3.0 + t * 2.0), 1) * 2.0 * finger_px;
	float s = mix(seam_sd, disc_sd, disc) + finger * (1.0 - disc);
	float bleed = bleed_px + max(fwidth(s), 0.5);
	float warm_share = 1.0 - smoothstep(-bleed, bleed, s);

	// Where the washes part a light line breathes along the seam; where they touch, none, and
	// their seam pools go too (a wet join dries without a dark line).
	float parted = smoothstep(0.0, 1.0, 0.5 + fbm(vec2(px.y / 34.0, seed * 5.0), 1) * 2.2);
	float line_w = 1.2 + 1.2 * parted;
	float line = exp(-(s * s) / (line_w * line_w)) * mix(line_min, line_max, parted) * (1.0 - disc);

	float open = 1.0 - disc;
	// Each mask's seam side reaches out with the seam's wobble (never in toward the words), so
	// the bloom's edge there runs along the seam.
	vec4 warm_words = text_warm + vec4(0.0, 0.0, wander + seam_amp, 0.0);
	vec4 cool_words = text_cool + vec4(wander - seam_amp, 0.0, 0.0, 0.0);
	float dl_warm = face_step(px, -s, in_rim, text_mask(px, warm_words), open, 0.0, parted);
	float dl_cool = face_step(px, s, in_rim, text_mask(px, cool_words), open, 1.0, parted);
	vec3 lab = mix(
		stepped(oklab_of(cool.rgb), dl_cool),
		stepped(oklab_of(warm.rgb), dl_warm),
		warm_share
	);
	vec3 col = srgb_of(lab);
	col = mix(col, paper.rgb, line);

	// The picked face's focus: a soft paper ring 5 px in from its edges.
	float in_face = min(in_rim, -focus_side * -s);
	float f = (in_face - 5.0) / 1.2;
	float ring = exp(-f * f) * focus * 0.6 * open;
	col = mix(col, paper.rgb, ring);
	COLOR = vec4(col, inside * COLOR.a);
}
