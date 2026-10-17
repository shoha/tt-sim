shader_type spatial;
// The persistent fire's smoke (FireFieldSmoke places it; design:
// docs/plans/2026-10-11-fire-features/design.md section 4 "Smoke"): one tall leaning plume over
// each of the fire's largest blaze clusters. Each instance is a whole column, one quad standing
// on its source that turns about the world's up axis to face the camera (so the column keeps its
// world depth against the trees), and the shader alone paints and moves it, so nothing runs per
// column per frame.
//
// Round 4 compares two structures inside that one quad (`structure`; card F4b-1's probe, after
// three rounds of separate billow quads read as faceted crowns, one oval haze, then a chain of
// near-identical discs):
//   0, the plume: a vertical strip widening upward and leaning down the map's wind, its edges
//      broken into large round lobes that are born small at the base, grow as they climb and
//      scroll up on the column's clock, a few more lobes rolling over its face, the whole warped
//      by a broad noise carried up with them, so the rise reads as one mass rolling on itself;
//   1, merged billows: a wide low base that stays over the fire and three billows a third of a
//      life apart that climb out of it, narrow low on the column and broad near the crown, joined
//      by a smooth union of their distances so the outline is one silhouette.
// Either way the parts are joined in one distance field (a smooth minimum), so no single circle's
// outline shows, and each takes a fake sphere normal (the body a cylinder); where parts overlap
// the nearer surface wins softly, which draws the creases between lobes.
//
// Painted, not lit (unshaded): every tone is the shader's own, graded up the column and split
// into a lit and a shadow side by the fake normal. At dusk and night (foliage_sun's weight, the
// gate the fire's lights use) the base glows a saturated amber lit from below, the brightest part
// of the column; the waist turns a warm dusky rose and the crown a soft dark blue-grey, its
// sky-facing side a little lifted, and it thins away at the top. By day the side facing the sun
// (foliage_sun's direction) is cream and the shade side cool, the base still a little warm.
// Round 3's lessons hold: the scene's sky ambient through the fake normal laid a pale blue-lilac
// over every tone, and the presets' tonemaps lift cool tones far above their linear values, so
// the cool tones are dark here. No fog, as the flames have none. The smoke draws before the
// flames (render priority), so the flames stay the brightest thing in its frame.
//
// Per instance (FireFieldSmoke.instance_buffer): the origin is the column's source and the
// basis's uniform scale its unit (metres, its cluster's tallest flame scaled by the cluster's
// size); INSTANCE_CUSTOM is (phase 0..1, seed, life in seconds, unused). The column's shape is
// set from FireFieldSmoke's constants, the wind's direction per map (lean_dir). Colours are linear
// and shown through the scene's tonemap.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fire_noise.gdshaderinc"

global uniform vec4 foliage_sun;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// 0: one plume; 1: merged billows (see the header).
uniform float structure = 0.0;
// The map's wind in world XZ (unit length): the column leans down it.
uniform vec2 lean_dir = vec2(1.0, 0.0);
// The column's height above its source, and its lean down the wind at the top (a share of the
// height), in the column's unit.
uniform float rise = 3.4;
uniform float lean = 0.45;
// The plume's half width at its source and at its crown (the column's unit).
uniform vec2 width = vec2(0.3, 0.64);
// Metres over which the smoke melts into the scene behind it (soft where it meets a tree).
uniform float soft_m = 0.9;

// The sun's weight over which the night palette fades out (FireLook's light gate).
const vec2 NIGHT_GATE = vec2(0.1, 0.35);
// The least share of the lean that shows across the screen (a wind along the view still leans),
// how the lean and the width grow up the column (powers of the height's share).
const float LEAN_SCREEN = 0.6;
const float LEAN_EASE = 1.5;
const float WIDEN_EASE = 0.75;
// Room in the quad below the source (the base sits among the tallest flames' tips) and above the
// crown, in the column's unit.
const float BASE_PAD = 0.45;
const float CROWN_PAD = 0.75;
// The plume's lobes: rows up the column, spaced by the height's logarithm from ROW_FROM up (so
// they grow as they climb: about 0.3 units at the base, 1.3 at the crown); an edge lobe's radius
// and a face lobe's (shares of the row's spacing), and how far a face lobe stands in front.
const float ROWS = 5.0;
const float ROW_FROM = 1.0;
const float EDGE_LOBE = 0.5;
const float FACE_LOBE = 0.55;
const float FACE_FRONT = 0.35;
// The billows: the base's height and radii (wide and tall enough to reach the waist), the
// climbing billows' radius low on the column (the waist) and near the crown, and how high their
// climb ends (a share of the height).
// (Three billows a third of a life apart left gaps the union could not bridge: separate balls.)
const vec3 BASE = vec3(0.3, 0.56, 0.6);
const vec2 BILLOW_R = vec2(0.42, 0.9);
const int BILLOWS = 4;
const float CLIMB_TOP = 0.95;
const float CLIMB_EASE = 1.15;
// The quad's room either side of the leaning centre line (the column's unit, a share of the
// crown's half width).
const float ROOM = 2.0;
// How softly the parts' distances join (the smooth minimum's reach, units: the plume's, the
// billows'), how softly the nearer surface takes over where they overlap (the crease), and the
// soft but drawn outline's width.
const vec2 JOIN = vec2(0.22, 0.4);
const float CREASE = 0.07;
const float EDGE = 0.06;
// The broad noise's warp of the outline (units at the base and at the crown) and its climb.
const vec2 WARP = vec2(0.08, 0.26);
const float WARP_CLIMB = 0.8;
// The grade at dusk and night: amber at the base (lit from below, LOW_SIDE of it on the side
// facing up), warm rose at the waist, a dark blue-grey crown lifted SKY_LIFT on its sky side.
// (Round 4's first try, the amber turning to rose by 0.42 of the height, showed no amber: the
// flames draw over the column's foot, and the rest read pink-mauve. An amber of (1.3, 0.44,
// 0.07) then read a pale cream-yellow through the tonemap, near the flames' own brightness, and a
// bluer crown mixed with the rose into lilac; the rose is terracotta and the crown a near-neutral
// slate so the grade passes through warm greys.)
const vec3 FIRE_AMBER = vec3(0.9, 0.27, 0.035);
const float LOW_SIDE = 0.5;
const vec3 NIGHT_ROSE = vec3(0.22, 0.075, 0.045);
const vec3 NIGHT_CROWN = vec3(0.03, 0.036, 0.05);
const float SKY_LIFT = 1.7;
const float ROSE_SHADE = 0.45;
// Where the grade turns (shares of the column's height): to rose, to the crown.
const vec2 TO_ROSE = vec2(0.2, 0.55);
const vec2 TO_CROWN = vec2(0.5, 0.92);
// By day: cream on the sun side, cool shade, a little warmer low on the column, the fire's glow at
// the base a share of the night's.
const vec3 DAY_LIT = vec3(0.56, 0.52, 0.45);
const vec3 DAY_SHADE_LOW = vec3(0.22, 0.2, 0.19);
const vec3 DAY_SHADE_TOP = vec3(0.2, 0.23, 0.29);
const float DAY_GLOW = 0.3;
// Opacity at the base and above it, where the crown thins away (shares of the height), and how
// much thinner a part is toward its edge.
// (0.62 and 0.86 read as a translucent veil over the sunset's fog, mauve from the orange behind.)
const vec2 OPACITY = vec2(0.78, 0.95);
const vec2 CROWN_FADE = vec2(0.72, 1.12);
const float EDGE_THIN = 0.2;

// The quad's rectangle in the column's frame (x across the screen, y up the world, units, the
// source at the origin), the lean at the crown, the seed and the clock (lives), and screen up.
varying flat vec4 v_rect;
varying flat vec3 v_column;
varying flat vec2 v_up;

void vertex() {
	float unit = length(MODEL_MATRIX[0].xyz);
	vec3 born = MODEL_MATRIX[3].xyz;
	float clock = TIME / max(INSTANCE_CUSTOM.z, 1.0) + INSTANCE_CUSTOM.x;
	vec3 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec2 up_screen = length(up_view.xy) > 1e-4 ? normalize(up_view.xy) : vec2(0.0, 1.0);
	vec2 right = vec2(up_screen.y, -up_screen.x);
	// The lean across the screen, at least LEAN_SCREEN of it.
	vec3 lean_view = (VIEW_MATRIX * vec4(lean_dir.x, 0.0, lean_dir.y, 0.0)).xyz;
	float across = dot(lean_view.xy, right);
	float side = across < 0.0 ? -1.0 : 1.0;
	float lean_x = side * max(abs(across), LEAN_SCREEN) * lean * rise;
	float room = max(width.x, width.y) * ROOM;
	vec4 rect = vec4(min(0.0, lean_x) - room, -BASE_PAD, max(0.0, lean_x) + room, rise + CROWN_PAD);
	v_rect = rect;
	v_column = vec3(lean_x, INSTANCE_CUSTOM.y, clock);
	v_up = up_screen;
	// Across along the screen's right, up along the world's up, the source at the origin.
	vec3 axis_x = vec3(right, 0.0) * unit;
	vec3 axis_y = up_view * unit;
	vec2 mid = (rect.xy + rect.zw) * 0.5;
	vec2 size = rect.zw - rect.xy;
	vec3 source = (VIEW_MATRIX * vec4(born, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(
		vec4(axis_x * size.x, 0.0),
		vec4(axis_y * size.y, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(source + axis_x * mid.x + axis_y * mid.y, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
}

// The column's centre line and half width at height `y` (units).
float centre_at(float y, float lean_x) {
	return lean_x * pow(clamp(y / rise, 0.0, 1.0), LEAN_EASE);
}

float half_at(float y) {
	return mix(width.x, width.y, pow(clamp(y / rise, 0.0, 1.0), WIDEN_EASE));
}

float smooth_min(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Adds one round part (centre `c`, radius `r`, standing `front` toward the camera) to the union:
// its distance into `dist`, its sphere normal weighted by how near its surface is into `acc`
// (outside its circle the normal lies flat, pointing out, and falls off fast).
void add_part(vec2 p, vec2 c, float r, float front, float join, inout float dist, inout vec4 acc) {
	vec2 q = p - c;
	float len = length(q);
	dist = smooth_min(dist, len - r, join);
	float inside = r * r - len * len;
	float height = inside > 0.0 ? sqrt(inside) + front : (r - len) * 3.0 + front;
	vec3 n = inside > 0.0 ? vec3(q / r, sqrt(inside) / r) : vec3(q / max(len, 1e-4), 0.0);
	// Weighed against a height of 1, so the weights stay in a half float's range.
	float w = exp((clamp(height, -1.0, 1.6) - 1.0) / CREASE);
	acc += vec4(n * w, w);
}

// The row coordinate of height `y` (rows from the source up) and its inverse.
float row_of(float y) {
	return log(1.0 + max(y, 0.0) / ROW_FROM) / log(1.0 + rise / ROW_FROM) * ROWS;
}

float height_of_row(float u) {
	return ROW_FROM * (exp(u / ROWS * log(1.0 + rise / ROW_FROM)) - 1.0);
}

// A row's spacing (units) at height `y`: the rows' growth.
float spacing_at(float y) {
	return (ROW_FROM + max(y, 0.0)) * log(1.0 + rise / ROW_FROM) / ROWS;
}

// Structure 0: the plume's body (a cylinder across the strip) and its lobes.
void plume(vec2 p, float lean_x, float seed, float clock, inout float dist, inout vec4 acc) {
	float y = clamp(p.y, 0.0, rise);
	// The body: a cylinder between rounded ends.
	vec2 axis = vec2(centre_at(y, lean_x), y);
	add_part(p, axis, half_at(y) * 0.92, 0.0, JOIN.x, dist, acc);
	float scroll = clock * ROWS + seed * 17.0;
	for (int s = 0; s < 2; s++) {
		float side = s == 0 ? -1.0 : 1.0;
		// The two sides' rows sit half a row apart, so the outline alternates.
		float u = row_of(p.y) - scroll + 0.5 * float(s);
		float base_row = floor(u);
		for (int k = -1; k <= 1; k++) {
			float row = base_row + float(k);
			float ly = height_of_row(row + 0.5 + scroll - 0.5 * float(s));
			// Lobes outside the fades (below the source, above the crown) are not drawn.
			if (ly < -0.3 || ly > rise * 1.15) {
				continue;
			}
			float spacing = spacing_at(ly);
			float h1 = fire_hash(vec2(row * 1.37 + seed * 23.0, side * 3.1 + 0.7));
			float h2 = fire_hash(vec2(row * 0.71 + 5.3, side * 1.9 + seed * 11.0));
			float lc = centre_at(ly, lean_x);
			float lh = half_at(ly);
			vec2 at = vec2(lc + side * lh * (0.55 + 0.25 * h1), ly + spacing * 0.15 * (h2 - 0.5));
			add_part(p, at, spacing * EDGE_LOBE * (0.85 + 0.35 * h2), 0.0, JOIN.x, dist, acc);
			if (s == 0) {
				// A lobe rolling over the face, between the edge rows.
				vec2 face = vec2(lc + (h1 - 0.5) * lh * 0.9, ly + spacing * 0.5);
				float fr = spacing * FACE_LOBE * (0.8 + 0.3 * h1);
				add_part(p, face, fr, fr * FACE_FRONT, JOIN.x, dist, acc);
			}
		}
	}
}

// Structure 1: the base and the climbing billows.
void billows(vec2 p, float lean_x, float seed, float clock, inout float dist, inout vec4 acc) {
	float breathe = 1.0 + 0.05 * sin(TIME * 0.9 + seed * 6.3);
	vec2 base = vec2(centre_at(BASE.x, lean_x), BASE.x);
	// The base is an ellipse: distances in its squashed frame.
	vec2 squash = vec2(1.0, BASE.y / BASE.z);
	vec2 ps = base + (p - base) * squash;
	add_part(ps, base, BASE.y * breathe, 0.0, JOIN.y, dist, acc);
	for (int i = 0; i < BILLOWS; i++) {
		float own = clock + float(i) / float(BILLOWS);
		float age = fract(own);
		float climb = mod(floor(own), 251.0);
		float roll = fire_hash(vec2(seed * 31.7 + float(i) * 0.37, climb * 0.137 + 0.5));
		float y = mix(BASE.x, rise * CLIMB_TOP, 1.0 - pow(1.0 - age, CLIMB_EASE));
		float r = mix(BILLOW_R.x, BILLOW_R.y, smoothstep(0.2, 0.85, age)) * (0.9 + 0.2 * roll);
		// Born inside the base, so it swells out of it; it shrinks away as it thins at the top,
		// so its end is not a pop.
		r *= smoothstep(0.0, 0.18, age) * 0.35 + 0.65;
		r *= 1.0 - smoothstep(0.7, 1.0, age);
		float wander = (roll - 0.5) * 0.3 * age;
		vec2 at = vec2(centre_at(y, lean_x) + wander, y);
		add_part(p, at, r, 0.06 * r, JOIN.y, dist, acc);
	}
}

void fragment() {
	vec2 p = vec2(mix(v_rect.x, v_rect.z, UV.x), mix(v_rect.w, v_rect.y, UV.y));
	float lean_x = v_column.x;
	float seed = v_column.y;
	float clock = v_column.z;
	float t = clamp(p.y / rise, 0.0, 1.0);
	// The broad warp, carried up the column and growing with it.
	vec2 flow = vec2(seed * 13.0, seed * 7.0 - clock * WARP_CLIMB * rise);
	vec2 cell = p / mix(0.45, 1.0, t);
	vec2 warp = vec2(fire_cloud(cell * 1.3 + flow), fire_cloud(cell * 1.3 + flow.yx + 4.1)) - 0.5;
	vec2 pw = p + warp * mix(WARP.x, WARP.y, t) * 2.0;
	float dist = 1e3;
	vec4 acc = vec4(0.0);
	if (structure < 0.5) {
		plume(pw, lean_x, seed, clock, dist, acc);
	} else {
		billows(pw, lean_x, seed, clock, dist, acc);
	}
	vec3 n = acc.w > 0.0 ? acc.xyz / acc.w : vec3(0.0, 0.0, 1.0);
	n = length(n) > 1e-4 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	float cover = smoothstep(0.0, EDGE, -dist);
	if (cover <= 0.0) {
		discard;
	}
	// The fake normal in view space (the screen's right, up and toward the camera), then the world.
	vec2 right = vec2(v_up.y, -v_up.x);
	vec3 view_n = normalize(vec3(right * n.x + v_up * n.y, n.z));
	vec3 world_n = mat3(INV_VIEW_MATRIX) * view_n;
	float below = smoothstep(-0.6, 0.6, -world_n.y);
	float above = smoothstep(-0.3, 0.8, world_n.y);
	float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
	float patches = mix(0.9, 1.08, fire_noise(pw * 1.5 + vec2(seed * 3.0, -clock * rise * 0.6)));
	// The grade up the column: amber lit from below, rose, a dark blue-grey crown.
	float to_rose = smoothstep(TO_ROSE.x, TO_ROSE.y, t);
	float to_crown = smoothstep(TO_CROWN.x, TO_CROWN.y, t);
	vec3 amber = FIRE_AMBER * mix(LOW_SIDE, 1.0, below);
	vec3 rose = NIGHT_ROSE * mix(ROSE_SHADE, 1.0, max(below, above * 0.8));
	vec3 crown = NIGHT_CROWN * mix(1.0, SKY_LIFT, above);
	vec3 at_night = mix(mix(amber, rose, to_rose), crown, to_crown);
	// By day: the sun's side cream, the shade cool, the fire's glow at the base.
	float sun_side = smoothstep(-0.3, 0.9, dot(world_n, foliage_sun.xyz));
	vec3 shade = mix(DAY_SHADE_LOW, DAY_SHADE_TOP, to_crown);
	vec3 by_day = mix(shade, DAY_LIT, sun_side) + amber * DAY_GLOW * (1.0 - to_rose);
	ALBEDO = mix(by_day, at_night, night) * patches;
	// Thin at the base among the flames, thinning away at the crown, fading in below the source.
	float opacity = mix(OPACITY.x, OPACITY.y, smoothstep(0.0, 0.3, t))
		* (1.0 - smoothstep(CROWN_FADE.x, CROWN_FADE.y, p.y / rise))
		* smoothstep(-BASE_PAD, 0.15, p.y);
	float density = cover * mix(1.0 - EDGE_THIN, 1.0, n.z);
	// Melts into the scene just behind it.
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = smoothstep(0.0, soft_m, VERTEX.z - behind.z);
	ALPHA = clamp(density * opacity * melt, 0.0, 1.0);
}
