shader_type canvas_item;

// The Play together card's two watercolour washes (PlayTogetherCard) inside a pill: persimmon
// (warm, left, Host) and lake (cool, right, Join), meeting at a crisp hand-painted seam at
// `split` (a share of the width) with a thin line of paper showing between them. Each wash is a
// few large, soft value shifts at its own hue, worked in OKLab lightness: a lighter bloom in the
// open band between its words and the seam, swelling and thinning along it and kept clear of
// the seam itself, so the line meets each wash at its own colour; a pooled darker edge along the
// pill's rim; slow mottle in big round blots and the faintest granulation.
//
// Soft tone stays inside a face and never crosses an edge (user verdict 2026-10-10: a blurred
// seam read as out of focus). Every edge is drawn crisp, with about one screen px of
// anti-aliasing measured along the edge's own gradient: the pill, the boundary between the
// washes (a clean curve wandering `seam_amp` either way, never fingers), the paper line along
// it and the focus ring. (A soft bleed with fingers and a soft light line, then a darker frill
// round the bloom, were tried: the first read as blur, the second as outlines.)
//
// Nothing lightens a wash under its words (`text_warm`, `text_cool`): there it stays at or below
// its own colour, the rest token, so paper words keep 4.5:1. The words' no-lightening mask fades
// over `text_feather` and its seam side follows the seam's wobble, so as a face narrows its
// bloom thins away rather than standing as a straight-edged bar. `disc` pulls the warm wash
// into a blot at the left end that then dries away (Join in place: the lake takes the card and
// the back disc stands where the blot was); the blot keeps the seam's crisp edge and paper line.
// `focus` draws a thin paper ring just inside the picked face (`focus_side`: -1 Host, 1 Join).
// Every length is in the card's own pixels (`rect_size`), which are screen px at 1080p.

uniform vec4 warm : source_color = vec4(0.706, 0.271, 0.165, 1.0);
uniform vec4 cool : source_color = vec4(0.165, 0.408, 0.502, 1.0);
uniform vec4 paper : source_color = vec4(0.980, 0.953, 0.890, 1.0);
// Seam position as a share of the width (0.5 at rest; 0.56 / 0.44 with a face picked).
uniform float split : hint_range(0.0, 1.0) = 0.5;
// Pigment density: deepens the rim pool and the mottle while pressed.
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
// The seam wanders this far either side of `split`, with one gentle bend per `seam_scale` px.
uniform float seam_amp = 5.0;
uniform float seam_scale = 40.0;
// The paper line along the seam: its width, varying up to `line_vary` either way along it as
// a gap left between two brushed washes does.
uniform float line_px = 2.0;
uniform float line_vary = 0.4;
// Steps of OKLab lightness: the bloom (up), the rim pool (down), the mottle (either way) and
// the granulation (down).
uniform float bloom_l = 0.14;
uniform float rim_l = 0.06;
uniform float mottle_l = 0.025;
uniform float grain_l = 0.008;
// The rim pool's depth; the bloom's distance in from the seam, its half width, and the margin
// beside the line it keeps clear before rising over `bloom_rise`; the blot sizes of the mottle
// and the granulation.
uniform float rim_px = 5.6;
uniform float bloom_in = 18.0;
uniform float bloom_w = 20.0;
uniform float bloom_clear = 4.0;
uniform float bloom_rise = 10.0;
uniform float mottle_px = 55.0;
uniform float grain_px = 8.0;
// The picked face's ring: how strongly it shows, its distance in from the face's edges and its
// width.
uniform float focus : hint_range(0.0, 1.0) = 0.0;
uniform float focus_side = -1.0;
uniform float ring_in = 5.0;
uniform float ring_px = 1.5;
// Slow drift of the seam's curve; 0 under Reduce motion.
uniform float drift = 1.0;
uniform float seed = 3.0;

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// A random value in [0, 1] for the lattice point `p` (whole numbers) and `salt`, hashed as
// integers so a corner shared by two cells gets the same value from both. The sine hash this
// replaced did not: the compiler re-associated its sum differently per cell, the error grew by
// 43758, and the seam tore sideways across the card at one lattice row.
float hash_salt(vec2 p, uint salt) {
	uvec2 q = uvec2(ivec2(round(p)) + ivec2(4096));
	return float(pcg(q.x + pcg(q.y + pcg(salt)))) / 4294967295.0;
}

float hash(vec2 p) {
	return hash_salt(p, 0u);
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
			vec2 spot = g + vec2(hash(cell + g), hash_salt(cell + g, 1u)) - f;
			float w = hash_salt(cell + g, 2u) * 2.0 - 1.0;
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

// A crisp band `width` screen px wide centred on `d` = 0 (`d` in screen px), with one px of
// anti-aliasing at each side.
float crisp_band(float d, float width) {
	return clamp(width * 0.5 + 0.5 - abs(d), 0.0, 1.0);
}

// One wash's lightness step at `px`: `in_seam` px in from its seam edge, `in_rim` px in from
// the pill's rim, `words` its words' mask, `open` how much of the bloom shows, `k` the face (0
// warm, 1 cool) for its own noise.
float face_step(vec2 px, float in_seam, float in_rim, float words, float open, float k) {
	float deep = 1.0 + press * 0.6;
	float pool = exp(-max(in_rim, 0.0) / rim_px) * rim_l;
	// The bloom: a soft lighter body in from the seam that swells and thins along it (one
	// octave of big, smooth noise with no threshold, so it never breaks into blocks or streaks;
	// a second octave read as dashes along the seam), and fades toward the rim. It rises only
	// past a clear margin beside the line, so no light haze runs along the seam. Squares by
	// hand: pow() of a negative base is undefined in GLSL.
	float z = (in_seam - bloom_in) / bloom_w;
	float band = exp(-z * z) * smoothstep(bloom_clear, bloom_clear + bloom_rise, in_seam);
	vec2 blot = vec2(px.x / 120.0, px.y / 48.0) + vec2(k * 11.0 + seed, 2.0 + k * 3.0);
	float swell = clamp(0.62 + fbm(blot, 1) * 1.1, 0.0, 1.0);
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
	// Card px per screen px: a length in card px over this is in screen px.
	float per_px = max(length(vec2(dFdx(px.x), dFdy(px.x))), 0.0001);

	// Pill: signed distance, negative inside, with one screen px of anti-aliasing.
	vec2 axis = vec2(clamp(px.x, r, rect_size.x - r), r);
	float d_pill = length(px - axis) - r;
	float inside = clamp(0.5 - d_pill / per_px, 0.0, 1.0);
	float in_rim = -d_pill;

	// The seam: a clean curve wandering slowly either side of `split`.
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

	// Negative: warm side. Also taken in screen px along its own gradient, so the edge and the
	// line keep one width however the seam leans or the blot curves. The last speck of the blot
	// goes with its line, so neither a persimmon dot nor a paper one is left under the disc.
	float s = mix(seam_sd, disc_sd, disc);
	float s_px = s / max(length(vec2(dFdx(s), dFdy(s))), 0.0001);
	float present = smoothstep(0.0, 0.08, shrink);
	float warm_share = clamp(0.5 - s_px, 0.0, 1.0) * present;

	// The paper line where the washes meet, its width breathing a little along it.
	float line_w = line_px + fbm(vec2(px.y / 26.0, seed * 5.0 + t), 1) * 2.0 * line_vary;
	float line = crisp_band(s_px, line_w / per_px) * present;

	float open = 1.0 - disc;
	// Each mask's seam side reaches out with the seam's wobble (never in toward the words), so
	// the bloom's edge there runs along the seam.
	vec4 warm_words = text_warm + vec4(0.0, 0.0, wander + seam_amp, 0.0);
	vec4 cool_words = text_cool + vec4(wander - seam_amp, 0.0, 0.0, 0.0);
	float dl_warm = face_step(px, -s, in_rim, text_mask(px, warm_words), open, 0.0);
	float dl_cool = face_step(px, s, in_rim, text_mask(px, cool_words), open, 1.0);
	vec3 lab = mix(
		stepped(oklab_of(cool.rgb), dl_cool),
		stepped(oklab_of(warm.rgb), dl_warm),
		warm_share
	);
	vec3 col = srgb_of(lab);
	col = mix(col, paper.rgb, line);

	// The picked face's focus: a thin paper ring `ring_in` px in from its edges.
	float in_face = min(in_rim / per_px, focus_side * s_px);
	float ring = crisp_band(in_face - ring_in / per_px, ring_px / per_px);
	col = mix(col, paper.rgb, ring * focus * 0.6 * open);
	COLOR = vec4(col, inside * COLOR.a);
}
