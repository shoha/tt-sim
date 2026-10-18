shader_type canvas_item;
// The persistent fire's smoke book, baked once offline (tools/render_jobs/probes/
// fire_smoke_book.gd draws this into an atlas, slices it and saves
// res://assets/fire/fire_smoke_book.res, FireSmokeBook; tools/fire_sim/README.md). It draws the
// smoke plume (the analytic lobes the game drew per pixel until the production port) as held
// frames, upright (no lean; the draw shader, shaders/fire_smoke_book.gdshader, shears it), a
// loop of `frames` over LOOP_ROWS rows of climb, for each of the atlas's seeds. A tile holds
// what the plume's tone needs, not the tone, so the sun, the ambient keying (figure_ambient) and
// the night gate stay live in the draw shader:
//   R the warped plume's signed distance, inside positive (SD_RANGE);
//   G, B the fake normal's x and y (0.5 + 0.5 n);
//   A the tone's multiplier, the patches noise times the crease's darkening (TONE_RANGE).
// The loop closes because the lobes' row hash wraps every LOOP_ROWS rows (more than the column
// shows at once), and the warp and the patches are blended from the loop's start to its end
// over the loop, so the last frame runs into the first.
//
// The code is round 6's (spike-flipbook de7f3d16, shaders/fire_smoke_flipbook_bake.gdshader)
// unchanged: a re-bake reproduces the shipped book byte for byte. It lives under tools/, which
// no export includes, so nothing at runtime may load it.
render_mode unshaded, blend_disabled;

#include "res://shaders/fire_glow_noise.gdshaderinc"

uniform ivec2 grid = ivec2(8, 6);
uniform int frames = 24;
uniform float rise = 3.4;
uniform vec2 width = vec2(0.3, 0.64);
// The tile's frame in the column's units: half its width, and its foot and top.
uniform vec3 domain = vec3(1.8, -0.45, 4.15);

const float LOOP_ROWS = 6.0;
const vec2 WARP = vec2(0.08, 0.26);
const float WARP_CLIMB = 0.8;
const float WIDEN_EASE = 0.75;
const float ROWS = 5.0;
const float ROW_FROM = 1.0;
const float BODY = 0.8;
const vec2 EDGE_AT = vec2(0.6, 0.88);
const float EDGE_LOBE = 0.56;
const float FACE_LOBE = 0.55;
const float FACE_FRONT = 0.35;
const float JOIN = 0.1;
const float CREASE = 0.07;
const float CREASE_DARK = 0.1;
const vec2 SD_RANGE = vec2(-0.5, 1.0);
const vec2 TONE_RANGE = vec2(0.75, 1.15);

float half_at(float y) {
	return mix(width.x, width.y, pow(clamp(y / rise, 0.0, 1.0), WIDEN_EASE));
}

float smooth_min(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void add_part(vec2 p, vec2 c, float r, float front, inout float dist, inout vec4 acc, inout float top) {
	vec2 q = p - c;
	float len = length(q);
	dist = smooth_min(dist, len - r, JOIN);
	float inside = r * r - len * len;
	float height = inside > 0.0 ? sqrt(inside) + front : (r - len) * 3.0 + front;
	vec3 n = inside > 0.0 ? vec3(q / r, sqrt(inside) / r) : vec3(q / max(len, 1e-4), 0.0);
	float w = exp((clamp(height, -1.0, 1.6) - 1.0) / CREASE);
	acc += vec4(n * w, w);
	top = max(top, w);
}

float row_of(float y) {
	return log(1.0 + max(y, 0.0) / ROW_FROM) / log(1.0 + rise / ROW_FROM) * ROWS;
}

float height_of_row(float u) {
	return ROW_FROM * (exp(u / ROWS * log(1.0 + rise / ROW_FROM)) - 1.0);
}

float spacing_at(float y) {
	return (ROW_FROM + max(y, 0.0)) * log(1.0 + rise / ROW_FROM) / ROWS;
}

void plume(vec2 p, float seed, float clock, inout float dist, inout vec4 acc, inout float top) {
	float y = clamp(p.y, 0.0, rise);
	add_part(p, vec2(0.0, y), half_at(y) * BODY, 0.0, dist, acc, top);
	float scroll = clock * ROWS + seed * 17.0;
	for (int s = 0; s < 2; s++) {
		float side = s == 0 ? -1.0 : 1.0;
		float u = row_of(p.y) - scroll + 0.5 * float(s);
		float base_row = floor(u);
		for (int k = -1; k <= 1; k++) {
			float row = base_row + float(k);
			float ly = height_of_row(row + 0.5 + scroll - 0.5 * float(s));
			if (ly < -0.3 || ly > rise * 1.15) {
				continue;
			}
			float spacing = spacing_at(ly);
			// The row's key wraps every LOOP_ROWS rows, so the loop closes.
			int wrapped = int(row - LOOP_ROWS * floor(row / LOOP_ROWS));
			ivec2 key = ivec2(wrapped, s + 2 * int(seed * 4096.0));
			float h1 = glow_hash(key);
			float h2 = glow_hash(key + ivec2(7919, 104729));
			float lh = half_at(ly);
			vec2 at = vec2(side * lh * mix(EDGE_AT.x, EDGE_AT.y, h1), ly + spacing * 0.15 * (h2 - 0.5));
			add_part(p, at, spacing * EDGE_LOBE * (0.85 + 0.3 * h2), 0.0, dist, acc, top);
			if (s == 0) {
				vec2 face = vec2((h1 - 0.5) * lh * 0.9, ly + spacing * 0.5);
				float fr = spacing * FACE_LOBE * (0.8 + 0.3 * h1);
				add_part(p, face, fr, fr * FACE_FRONT, dist, acc, top);
			}
		}
	}
}

vec2 warp_at(vec2 p, float t, float seed, float clock) {
	vec2 flow = vec2(seed * 13.0, seed * 7.0 - clock * WARP_CLIMB * rise);
	vec2 cell = p / mix(0.45, 1.0, t);
	return vec2(glow_cloud(cell * 1.3 + flow), glow_cloud(cell * 1.3 + flow.yx + 4.1)) - 0.5;
}

void fragment() {
	vec2 cell = UV * vec2(grid);
	ivec2 tile = ivec2(floor(cell));
	vec2 local = fract(cell);
	int layer = tile.y * grid.x + tile.x;
	int k = layer / frames;
	int f = layer - k * frames;
	float seed = fract(float(k) * 0.618034 + 0.31);
	float loop = LOOP_ROWS / ROWS;
	float share = float(f) / float(frames);
	float clock = share * loop;
	vec2 p = vec2(mix(-domain.x, domain.x, local.x), mix(domain.z, domain.y, local.y));
	float t = clamp(p.y / rise, 0.0, 1.0);
	vec2 warp = mix(warp_at(p, t, seed, clock), warp_at(p, t, seed, clock - loop), share);
	vec2 pw = p + warp * mix(WARP.x, WARP.y, t) * 2.0;
	float dist = 1e3;
	vec4 acc = vec4(0.0);
	float top = 0.0;
	plume(pw, seed, clock, dist, acc, top);
	vec3 n = acc.w > 0.0 ? acc.xyz / acc.w : vec3(0.0, 0.0, 1.0);
	n = length(n) > 1e-4 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	float crease = acc.w > 0.0 ? 1.0 - top / acc.w : 0.0;
	float patch_now = glow_noise(pw * 1.5 + vec2(seed * 3.0, -clock * rise * 0.6));
	float patch_back = glow_noise(pw * 1.5 + vec2(seed * 3.0, -(clock - loop) * rise * 0.6));
	float patches = mix(0.92, 1.08, mix(patch_now, patch_back, share));
	float tone = patches * (1.0 - CREASE_DARK * smoothstep(0.08, 0.45, crease));
	COLOR = vec4(
		clamp((-dist - SD_RANGE.x) / (SD_RANGE.y - SD_RANGE.x), 0.0, 1.0),
		n.x * 0.5 + 0.5,
		n.y * 0.5 + 0.5,
		clamp((tone - TONE_RANGE.x) / (TONE_RANGE.y - TONE_RANGE.x), 0.0, 1.0)
	);
}
