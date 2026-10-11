shader_type canvas_item;

// The Play together card's two faces (PlayTogetherCard) inside a pill: persimmon (warm, left,
// Host) and lake (cool, right, Join), meeting at a clean straight seam at `split` (a share of
// the width) with a thin crisp line of paper between them. Each face is its own solid token
// colour with one subtle, smooth vertical gradient worked in OKLab lightness at its own hue: the
// token at the top, `grad_l` darker at the bottom (user direction 2026-10-10: the UI goes to
// solid colours and subtle gradients for now; the painterly bloom, mottle, granulation, pooled
// rim and wandering seam landed sloppy and are gone, to be revisited later).
//
// Every edge is drawn crisp, with about one screen px of anti-aliasing measured along the
// edge's own gradient: the pill, the seam, the paper line along it, the blot of Join's opening
// and the focus ring.
//
// Nothing lightens a face anywhere: the gradient only darkens from the token, so paper words
// keep at least the token's contrast (4.5:1). `text_warm` and `text_cool` (each face's words)
// are held for the card's contrast checks; the shader needs no mask under them. `disc` pulls
// the warm face into a round blot at the left end that then shrinks away (Join in place: the
// lake takes the card and the back disc stands where the blot was); the blot keeps the seam's
// crisp edge and paper line. `focus` draws a thin paper ring just inside the picked face
// (`focus_side`: -1 Host, 1 Join). Every length is in the card's own pixels (`rect_size`),
// which are screen px at 1080p.

uniform vec4 warm : source_color = vec4(0.706, 0.271, 0.165, 1.0);
uniform vec4 cool : source_color = vec4(0.165, 0.408, 0.502, 1.0);
uniform vec4 paper : source_color = vec4(0.980, 0.953, 0.890, 1.0);
// Seam position as a share of the width (0.5 at rest; 0.56 / 0.44 with a face picked).
uniform float split : hint_range(0.0, 1.0) = 0.5;
// Pigment density while pressed: deepens the pressed face a little more.
uniform float press : hint_range(0.0, 1.0) = 0.0;
// 0: seam across the card; 1: the warm face has drawn into a blot at the left end and gone.
uniform float disc : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rect_size = vec2(336.0, 112.0);
// Each face's words (x0, y0, x1, y1), for the card's contrast checks.
uniform vec4 text_warm = vec4(20.0, 22.0, 120.0, 84.0);
uniform vec4 text_cool = vec4(216.0, 22.0, 316.0, 84.0);
// The paper line along the seam.
uniform float line_px = 2.0;
// OKLab lightness from top to bottom of each face, and the extra depth while pressed.
uniform float grad_l = 0.04;
uniform float press_l = 0.02;
// The picked face's ring: how strongly it shows, its distance in from the face's edges and its
// width.
uniform float focus : hint_range(0.0, 1.0) = 0.0;
uniform float focus_side = -1.0;
uniform float ring_in = 5.0;
uniform float ring_px = 1.5;

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

// A face's colour moved `dl` (zero or less) in lightness at its own hue, trimming a little
// chroma as it darkens so the bottom deepens rather than going muddy (UI_TASTE C8).
vec3 stepped(vec3 srgb, float dl) {
	vec3 lab = oklab_of(srgb);
	float trim = 1.0 - 0.8 * max(-dl, 0.0);
	return srgb_of(vec3(lab.x + dl, lab.yz * trim));
}

// A crisp band `width` screen px wide centred on `d` = 0 (`d` in screen px), with one px of
// anti-aliasing at each side.
float crisp_band(float d, float width) {
	return clamp(width * 0.5 + 0.5 - abs(d), 0.0, 1.0);
}

void fragment() {
	vec2 px = UV * rect_size;
	float r = rect_size.y * 0.5;
	// Card px per screen px: a length in card px over this is in screen px.
	float per_px = max(length(vec2(dFdx(px.x), dFdy(px.x))), 0.0001);

	// Pill: signed distance, negative inside, with one screen px of anti-aliasing.
	vec2 axis = vec2(clamp(px.x, r, rect_size.x - r), r);
	float d_pill = length(px - axis) - r;
	float inside = clamp(0.5 - d_pill / per_px, 0.0, 1.0);
	float in_rim = -d_pill;

	// The seam: a straight line at `split`.
	float seam_sd = px.x - split * rect_size.x;

	// The blot (Join in place): a circle centred in the left cap, shrinking to nothing as
	// `disc` ends, so no persimmon is left round the back disc.
	float shrink = 1.0 - smoothstep(0.55, 1.0, disc);
	float disc_sd = length(px - vec2(r, r)) - r * 0.64 * shrink;

	// Negative: warm side. Taken in screen px along its own gradient, so the edge and the line
	// keep one width however the blot curves. The last speck of the blot goes with its line, so
	// neither a persimmon dot nor a paper one is left under the disc.
	float s = mix(seam_sd, disc_sd, disc);
	float s_px = s / max(length(vec2(dFdx(s), dFdy(s))), 0.0001);
	float present = smoothstep(0.0, 0.08, shrink);
	float warm_share = clamp(0.5 - s_px, 0.0, 1.0) * present;
	float line = crisp_band(s_px, line_px / per_px) * present;

	// One smooth vertical gradient, the token at the top; the press deepens the faces a little.
	float dl = -grad_l * clamp(px.y / rect_size.y, 0.0, 1.0) - press * press_l;
	vec3 col = mix(stepped(cool.rgb, dl), stepped(warm.rgb, dl), warm_share);
	col = mix(col, paper.rgb, line);

	// The picked face's focus: a thin paper ring `ring_in` px in from its edges.
	float in_face = min(in_rim / per_px, focus_side * s_px);
	float ring = crisp_band(in_face - ring_in / per_px, ring_px / per_px);
	col = mix(col, paper.rgb, ring * focus * 0.6 * (1.0 - disc));
	COLOR = vec4(col, inside * COLOR.a);
}
