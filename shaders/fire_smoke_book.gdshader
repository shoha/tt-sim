shader_type spatial;
// The persistent fire's smoke (FireFieldSmoke places the columns and binds the book; design:
// docs/plans/2026-10-11-fire-features/design.md section 4 "Smoke"), drawn from the smoke book
// (FireSmokeBook, assets/fire/fire_smoke_book.res, baked once offline by
// tools/fire_sim/fire_smoke_book_bake.gdshader) instead of working the plume's lobes out per
// pixel. The book holds a closed loop of held frames of the upright plume per seed: its signed
// distance, a fake normal and a tone multiplier, not colours.
//
// Per pixel: two fetches, the column's frame and the next, cross-faded (the frames hold
// distances and normals, so the fade morphs the lobes up the column rather than dissolving
// them), then the tone from the fake normal, the sun and the ambient (figure_ambient keying,
// the night gate), the opacity profile up the column and the amber glow at its foot. No depth
// read: the column is depth tested and its base fades by height, but nothing melts it softly
// into a canopy in front.
//
// Per instance (FireFieldSmoke.instance_buffer): the origin is the column's source and the
// basis's scale its unit; custom data is (phase, seed, life, 1): the loop's offset, the seed's
// pick and the seconds a lobe takes to climb the column. The quad is the book's upright frame
// (`domain`, in units), split into rows (FireLook's shared mesh) and leaned by moving each row
// down the wind (lean_dir, the map's wind). Until FireFieldSmoke binds the book, `frames` is 0
// and every quad collapses: nothing draws.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

global uniform vec4 foliage_sun;
global uniform vec3 figure_ambient;
uniform sampler2DArray smoke_book : filter_linear, repeat_disable;
uniform int frames = 0;
uniform int seeds = 2;
uniform vec2 lean_dir = vec2(1.0, 0.0);
uniform float rise = 3.4;
uniform float lean = 0.45;
uniform vec2 width = vec2(0.3, 0.64);
// The book's frame in the column's units (half width, foot, top; FireSmokeBook.DOMAIN).
uniform vec3 domain = vec3(1.8, -0.45, 4.15);

const float LOOP_ROWS = 6.0;
const float ROWS = 5.0;
const vec2 NIGHT_GATE = vec2(0.1, 0.35);
const vec2 DUSK_KEY = vec2(0.06, 0.3);
const float LEAN_SCREEN = 0.6;
const float LEAN_EASE = 1.5;
const float WIDEN_EASE = 0.75;
const float BASE_PAD = 0.45;
const float EDGE_SOFT = 0.5;
const float EDGE_OUT = 0.3;
const vec3 GLOW = vec3(0.7, 0.14, 0.0);
const vec2 GLOW_FROM = vec2(-0.05, 0.4);
const vec2 GLOW_TO = vec2(0.18, 0.55);
const float GLOW_BELOW = 0.6;
const float DAY_GLOW = 0.3;
const vec3 FOOT_LIT = vec3(0.6, 0.17, 0.03);
const vec3 FOOT_SHADE = vec3(0.38, 0.1, 0.03);
const vec3 ROSE_LIT_NIGHT = vec3(0.4, 0.1, 0.08);
const vec3 ROSE_SHADE_NIGHT = vec3(0.17, 0.065, 0.07);
const vec3 CROWN_LIT_NIGHT = vec3(0.05, 0.062, 0.09);
const vec3 CROWN_SHADE_NIGHT = vec3(0.036, 0.042, 0.062);
const vec3 ROSE_LIT_DUSK = vec3(0.8, 0.19, 0.11);
const vec3 ROSE_SHADE_DUSK = vec3(0.45, 0.13, 0.13);
const vec3 CROWN_LIT_DUSK = vec3(0.26, 0.38, 0.66);
const vec3 CROWN_SHADE_DUSK = vec3(0.15, 0.2, 0.36);
const vec2 TO_ROSE = vec2(0.15, 0.42);
const vec2 TO_CROWN = vec2(0.55, 0.85);
const vec2 FIRE_REACH = vec2(0.25, 0.75);
const vec3 DAY_LIT = vec3(0.4, 0.35, 0.43);
const vec3 DAY_SHADE = vec3(0.16, 0.18, 0.27);
const vec3 DAY_FOOT = vec3(0.3, 0.16, 0.08);
const vec2 TERMINATOR = vec2(-0.2, 0.35);
const float FOOT_OPACITY = 0.06;
const vec2 TO_DENSE = vec2(0.05, 1.3);
const vec2 OPACITY = vec2(0.92, 0.8);
const vec2 CROWN_FADE = vec2(0.82, 1.15);
const float EDGE_THIN = 0.25;
const vec2 SD_RANGE = vec2(-0.5, 1.0);
const vec2 TONE_RANGE = vec2(0.75, 1.15);

// (frame a, frame b, their blend, unused) as layers.
varying flat vec4 v_frames;
varying flat vec2 v_up;
// The book's UV, and the point in the column's frame (units; x across the upright column).
varying vec2 v_uv;
varying vec2 v_p;

float half_at(float y) {
	return mix(width.x, width.y, pow(clamp(y / rise, 0.0, 1.0), WIDEN_EASE));
}

void vertex() {
	float unit = length(MODEL_MATRIX[0].xyz);
	vec3 born = MODEL_MATRIX[3].xyz;
	float clock = TIME / max(INSTANCE_CUSTOM.z, 1.0) + INSTANCE_CUSTOM.x;
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec2 up_screen = length(up_view.xy) > 1e-4 ? normalize(up_view.xy) : vec2(0.0, 1.0);
	vec2 right = vec2(up_screen.y, -up_screen.x);
	vec3 lean_view = (VIEW_MATRIX * vec4(lean_dir.x, 0.0, lean_dir.y, 0.0)).xyz;
	float across = dot(lean_view.xy, right);
	float side = across < 0.0 ? -1.0 : 1.0;
	float lean_x = side * max(abs(across), LEAN_SCREEN) * lean * rise;
	// The column's frame: which seed's loop, which frame of it.
	int count = max(frames, 1);
	int k = int(fract(INSTANCE_CUSTOM.y * 7.31) * float(seeds));
	float at = fract(clock / (LOOP_ROWS / ROWS)) * float(count);
	float a = floor(at);
	float b = mod(a + 1.0, float(count));
	v_frames = vec4(float(k * count) + a, float(k * count) + b, at - a, 0.0);
	v_up = up_screen;
	vec2 local = VERTEX.xy + 0.5;
	vec2 p = vec2(mix(-domain.x, domain.x, local.x), mix(domain.y, domain.z, local.y));
	v_p = p;
	v_uv = vec2(local.x, 1.0 - local.y);
	float lean_at = lean_x * pow(clamp(p.y / rise, 0.0, 1.0), LEAN_EASE);
	vec3 axis_x = vec3(right, 0.0) * unit;
	vec3 axis_y = up_view * unit;
	vec3 placed = (VIEW_MATRIX * vec4(born, 1.0)).xyz + axis_x * (p.x + lean_at) + axis_y * p.y;
	// No book bound yet: every corner on one point, so nothing is drawn.
	VERTEX = frames > 0 ? placed : vec3(0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 s = texture(smoke_book, vec3(v_uv, v_frames.x));
	if (v_frames.z > 0.0) {
		s = mix(s, texture(smoke_book, vec3(v_uv, v_frames.y)), v_frames.z);
	}
	float sd = mix(SD_RANGE.x, SD_RANGE.y, s.r);
	vec2 p = v_p;
	float t = clamp(p.y / rise, 0.0, 1.0);
	float soft = EDGE_SOFT * half_at(p.y);
	float cover = smoothstep(-soft * EDGE_OUT, soft * (1.0 - EDGE_OUT), sd);
	if (cover <= 0.0) {
		discard;
	}
	vec2 nxy = s.gb * 2.0 - 1.0;
	vec3 n = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
	n = length(n) > 1e-4 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	vec2 right = vec2(v_up.y, -v_up.x);
	vec3 view_n = normalize(vec3(right * n.x + v_up * n.y, n.z));
	vec3 world_n = mat3(INV_VIEW_MATRIX) * view_n;
	float below = smoothstep(-0.5, 0.7, -world_n.y);
	float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
	float dusk = smoothstep(DUSK_KEY.x, DUSK_KEY.y, dot(figure_ambient, vec3(0.2126, 0.7152, 0.0722)));
	vec3 key = normalize(vec3(foliage_sun.x, 0.35, foliage_sun.z) + vec3(0.0, 1e-3, 0.0));
	float lit = smoothstep(TERMINATOR.x, TERMINATOR.y, dot(world_n, key));
	float to_rose = smoothstep(TO_ROSE.x, TO_ROSE.y, t);
	float to_crown = smoothstep(TO_CROWN.x, TO_CROWN.y, t);
	vec3 foot = mix(FOOT_SHADE, FOOT_LIT, max(below, lit * 0.7));
	vec3 rose_lit = mix(ROSE_LIT_NIGHT, ROSE_LIT_DUSK, dusk);
	vec3 rose_shade = mix(ROSE_SHADE_NIGHT, ROSE_SHADE_DUSK, dusk);
	float fire_lit = (1.0 - smoothstep(FIRE_REACH.x, FIRE_REACH.y, t)) * 0.7;
	vec3 rose = mix(rose_shade, rose_lit, max(max(lit, below * 0.85), fire_lit));
	vec3 crown_lit = mix(CROWN_LIT_NIGHT, CROWN_LIT_DUSK, dusk);
	vec3 crown_shade = mix(CROWN_SHADE_NIGHT, CROWN_SHADE_DUSK, dusk);
	vec3 crown = mix(crown_shade, crown_lit, lit);
	vec3 at_night = mix(mix(foot, rose, to_rose), crown, to_crown);
	vec3 by_day = mix(DAY_SHADE, DAY_LIT, lit) + DAY_FOOT * (1.0 - to_rose) * 0.5;
	vec3 tone = mix(by_day, at_night, night) * mix(TONE_RANGE.x, TONE_RANGE.y, s.a);
	float profile = mix(FOOT_OPACITY, 1.0, smoothstep(TO_DENSE.x, TO_DENSE.y, p.y))
		* mix(OPACITY.y, OPACITY.x, night)
		* (1.0 - smoothstep(CROWN_FADE.x, CROWN_FADE.y, p.y / rise))
		* smoothstep(-BASE_PAD, 0.15, p.y);
	float rim = 1.0 - smoothstep(0.0, soft * 1.5, sd);
	float density = cover * mix(1.0, mix(1.0 - EDGE_THIN, 1.0, n.z), rim);
	float alpha = clamp(density * profile, 0.0, 1.0);
	float glow = smoothstep(GLOW_FROM.x, GLOW_FROM.y, p.y) * (1.0 - smoothstep(GLOW_TO.x, GLOW_TO.y, t));
	glow *= mix(1.0 - GLOW_BELOW, 1.0, below) * mix(DAY_GLOW, 1.0, night) * density;
	ALBEDO = tone * alpha + GLOW * glow;
	ALPHA = alpha;
}
