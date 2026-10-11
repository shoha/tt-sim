shader_type canvas_item;

// The sky every screen outside play stands on (scenes/ui/primitives/painted_backdrop.gd), and,
// in a small rect, the picture of a map with no thumbnail yet (map_placeholder.gd): one soft
// gradient in the map's mood, so a card and the screen behind it share one light. No scenery
// (UI_TASTE verdict 2026-10-10: solid colours and subtle gradients).
//
// Three stops, top to horizon, blended on one quadratic curve in OKLCH (BackdropPaint.colour_at
// is the same curve on the CPU), so the middle stop shapes the gradient without a seam at it
// and the chroma never dips toward grey between a blue top and a warm horizon; then a faint
// dither so a long, gentle gradient across a large screen does not band. The stops come from
// BackdropPaint.uniforms, which mixes two moods in OKLCH while the light changes.

// The stops as OKLCH: lightness, chroma, hue in radians (unwrapped top to horizon).
uniform vec3 top_lch = vec3(0.79, 0.08, -2.0);
uniform vec3 mid_lch = vec3(0.88, 0.05, -1.4);
uniform vec3 low_lch = vec3(0.93, 0.06, 1.3);
// How far the gradient leans from straight down: 0 for the screen's sky, part way to the
// diagonal (horizon at the foot's left corner, top at the head's right) for a placeholder.
uniform float tilt = 0.0;

// An OKLCH colour as sRGB, clipped to the screen's gamut (BackdropPaint._linear_of).
vec3 srgb_of(vec3 lch) {
	vec2 ab = lch.y * vec2(cos(lch.z), sin(lch.z));
	vec3 lms = vec3(
		lch.x + 0.3963377774 * ab.x + 0.2158037573 * ab.y,
		lch.x - 0.1055613458 * ab.x - 0.0638541728 * ab.y,
		lch.x - 0.0894841775 * ab.x - 1.2914855480 * ab.y
	);
	lms = lms * lms * lms;
	vec3 lin = vec3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z
	);
	lin = clamp(lin, 0.0, 1.0);
	return mix(12.92 * lin, 1.055 * pow(lin, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, lin));
}

void fragment() {
	float up = 1.0 - UV.y;
	float t = clamp(mix(up, 0.5 * (UV.x + up), tilt), 0.0, 1.0);
	vec3 lch = mix(mix(low_lch, mid_lch, t), mix(mid_lch, top_lch, t), t);
	vec3 col = srgb_of(lch);
	// Half a step of 8-bit colour either way, per pixel, so the gradient does not band.
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) / 255.0;
	COLOR = vec4(col, COLOR.a);
}
