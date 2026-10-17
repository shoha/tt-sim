shader_type spatial;
// The persistent fire's smoke (FireFieldSmoke places it; design:
// docs/plans/2026-10-11-fire-features/design.md section 4 "Smoke"): one tall leaning plume over
// each of the fire's largest blaze clusters. Each instance is a whole column, one quad standing
// on its source that turns about the world's up axis to face the camera (so the column keeps its
// world depth against the trees), and the shader alone paints and moves it, so nothing runs per
// column per frame.
//
// The plume (card F4b-1 round 4 chose it over merged billows, after three rounds of separate
// billow quads read as faceted crowns, one oval haze, then a chain of near-identical discs): a
// vertical strip widening upward and leaning down the map's wind, its edges broken into large
// round lobes that are born small at the base, grow as they climb and scroll up on the column's
// clock, a few more lobes rolling over its face, the whole warped by a broad noise carried up with
// them, so the rise reads as one mass rolling on itself. The parts are joined in one distance
// field (a smooth minimum), so no single circle's outline shows, and each takes a fake sphere
// normal (the body a cylinder); where parts overlap the nearer surface wins softly, and the
// contested band between them is shaded a little darker, so each lobe reads as its own rounded
// stroke. The outline fades over about a quarter of the column's width.
//
// Painted, not lit (unshaded): every tone is the shader's own, graded up the column and split
// into a lit and a shadow side by the fake normal. Blended premultiplied: the base is nearly
// transparent where it stands among the flames, so they show at full strength, and its amber is
// a glow added over whatever is behind, so it reads as lit by the fire; only the upper two
// thirds carry real density. At dusk and night (foliage_sun's weight, the gate the fire's lights
// use) the waist is a salmon rose and the crown a powder blue-grey, both keyed to the scene's
// ambient (figure_ambient, which the environment publishes): under a bright sunset ambient the
// crown is lighter than the land behind it, under a night ambient about the night's own value,
// so nothing in the plume is a dark blot. By day it is a translucent grey-lavender, lighter on
// the side facing the sun, blue-grey in shade, with a faint amber foot. Round 3's lessons hold:
// the scene's sky ambient through the fake normal laid a pale blue-lilac over every tone, and the
// presets' tonemaps (ACES at sunset, Filmic at night and by day) lift and desaturate bright
// tones, so the bright tones here are more saturated than they show. No fog, as the flames have
// none. The smoke draws before the flames (render priority), so the flames stay the brightest
// thing in its frame.
//
// Per instance (FireFieldSmoke.instance_buffer): the origin is the column's source and the
// basis's uniform scale its unit (metres, its cluster's tallest flame scaled by the cluster's
// size); INSTANCE_CUSTOM is (phase 0..1, seed, life in seconds, unused). The column's shape is
// set from FireFieldSmoke's constants, the wind's direction per map (lean_dir). Colours are linear
// and shown through the scene's tonemap.
//
// Its noise is glow_noise's integer hash, not fire_noise's (card F4b-5): fire_hash's float
// rounding hashed a lattice point differently from the cells either side of it, so the warp
// jumped along the lattice's lines, which in the column's frame are the screen's verticals and
// horizontals, and the plume showed straight cuts and rectangle corners by day.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fire_glow_noise.gdshaderinc"

global uniform vec4 foliage_sun;
global uniform vec3 figure_ambient;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
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

// The sun's weight over which the night palette fades out (FireLook's light gate), and the
// ambient's luminance over which the night tones turn to the sunset's.
const vec2 NIGHT_GATE = vec2(0.1, 0.35);
const vec2 DUSK_KEY = vec2(0.06, 0.3);
// The least share of the lean that shows across the screen (a wind along the view still leans),
// how the lean and the width grow up the column (powers of the height's share).
const float LEAN_SCREEN = 0.6;
const float LEAN_EASE = 1.5;
const float WIDEN_EASE = 0.75;
// Room in the quad below the source (the base sits among the tallest flames' tips) and above the
// crown, in the column's unit, and either side of the leaning centre line (a share of the crown's
// half width: the crown's outer lobes, the warp and the soft edge; at 2.0 the lobes on the lean
// side were cut by the quad's edge, a straight vertical seam).
const float BASE_PAD = 0.45;
const float CROWN_PAD = 0.75;
const float ROOM = 2.9;
// The lobes: rows up the column, spaced by the height's logarithm from ROW_FROM up (so they grow
// as they climb: about 0.3 units at the base, 1.3 at the crown); the body's radius (a share of
// the half width), where an edge lobe stands (a share of the half width out from the centre
// line) and its radius (a share of the row's spacing), a face lobe's radius and how far it stands
// in front.
const float ROWS = 5.0;
const float ROW_FROM = 1.0;
const float BODY = 0.8;
const vec2 EDGE_AT = vec2(0.6, 0.88);
const float EDGE_LOBE = 0.56;
const float FACE_LOBE = 0.55;
const float FACE_FRONT = 0.35;
// How softly the parts' distances join (the smooth minimum's reach, units: small, so the notches
// between lobes stay), how softly the nearer surface takes over where they overlap (the crease),
// and how much darker the contested band is.
const float JOIN = 0.1;
const float CREASE = 0.07;
const float CREASE_DARK = 0.1;
// The soft outline: its width as a share of the half width there (half of it a quarter of the
// column's width), and the share of it outside the shape's distance zero.
const float EDGE_SOFT = 0.5;
const float EDGE_OUT = 0.3;
// The broad noise's warp of the outline (units at the base and at the crown) and its climb.
const vec2 WARP = vec2(0.08, 0.26);
const float WARP_CLIMB = 0.8;
// The fire's glow, added over the scene (premultiplied): its colour, where it rises from (units
// above the source, so the flames below keep their own colour) and fades out (shares of the
// height), how much more of it the underside takes, and its share by day.
// (An amber of (1.3, 0.44, 0.07) read a pale cream-yellow through the sunset's ACES: bright
// tones lose their saturation there, so the glow is a deep orange at a modest level.)
const vec3 GLOW = vec3(0.7, 0.14, 0.0);
const vec2 GLOW_FROM = vec2(-0.05, 0.4);
const vec2 GLOW_TO = vec2(0.18, 0.55);
const float GLOW_BELOW = 0.6;
const float DAY_GLOW = 0.3;
// The tones at dusk and night, each lit and in shade: the foot over the glow (amber), the waist
// (rose) and the crown (blue-grey), at night and under a sunset's ambient. The waist's lit side is
// the one facing down toward the fire or toward the low sun.
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
// Where the grade turns (shares of the column's height): foot to rose, rose to the crown; and
// how far up the fire below still lights the rose (fading over FIRE_REACH).
const vec2 TO_ROSE = vec2(0.15, 0.42);
const vec2 TO_CROWN = vec2(0.55, 0.85);
const vec2 FIRE_REACH = vec2(0.25, 0.75);
// By day: grey-lavender on the sun side, blue-grey in shade, a little warmer low on the column.
const vec3 DAY_LIT = vec3(0.4, 0.35, 0.43);
const vec3 DAY_SHADE = vec3(0.16, 0.18, 0.27);
const vec3 DAY_FOOT = vec3(0.3, 0.16, 0.08);
// The painted terminator between the lit and shadow sides (a band of the fake normal's cosine
// toward the light).
const vec2 TERMINATOR = vec2(-0.2, 0.35);
// Opacity: the share kept at the foot among the flames, rising to full over TO_DENSE (units above
// the source: from the tallest flames' tips to about 0.4 of the height); the most at dusk and
// night and by day; where the crown thins away (shares of the height); how much thinner a part is
// toward its edge.
const float FOOT_OPACITY = 0.06;
const vec2 TO_DENSE = vec2(0.05, 1.3);
const vec2 OPACITY = vec2(0.92, 0.8);
const vec2 CROWN_FADE = vec2(0.82, 1.15);
const float EDGE_THIN = 0.25;

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
// (outside its circle the normal lies flat, pointing out, and falls off fast), and the largest
// weight so far into `top` (the crease is where no one part's weight dominates).
void add_part(vec2 p, vec2 c, float r, float front, inout float dist, inout vec4 acc, inout float top) {
	vec2 q = p - c;
	float len = length(q);
	dist = smooth_min(dist, len - r, JOIN);
	float inside = r * r - len * len;
	float height = inside > 0.0 ? sqrt(inside) + front : (r - len) * 3.0 + front;
	vec3 n = inside > 0.0 ? vec3(q / r, sqrt(inside) / r) : vec3(q / max(len, 1e-4), 0.0);
	// Weighed against a height of 1, so the weights stay in a half float's range.
	float w = exp((clamp(height, -1.0, 1.6) - 1.0) / CREASE);
	acc += vec4(n * w, w);
	top = max(top, w);
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

// The plume's body (a cylinder across the strip) and its lobes.
void plume(vec2 p, float lean_x, float seed, float clock, inout float dist, inout vec4 acc, inout float top) {
	float y = clamp(p.y, 0.0, rise);
	vec2 axis = vec2(centre_at(y, lean_x), y);
	add_part(p, axis, half_at(y) * BODY, 0.0, dist, acc, top);
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
			// Hashed from integers, so every pixel that weighs this lobe places it alike.
			ivec2 key = ivec2(int(row), s + 2 * int(seed * 4096.0));
			float h1 = glow_hash(key);
			float h2 = glow_hash(key + ivec2(7919, 104729));
			float lc = centre_at(ly, lean_x);
			float lh = half_at(ly);
			vec2 at = vec2(lc + side * lh * mix(EDGE_AT.x, EDGE_AT.y, h1), ly + spacing * 0.15 * (h2 - 0.5));
			add_part(p, at, spacing * EDGE_LOBE * (0.85 + 0.3 * h2), 0.0, dist, acc, top);
			if (s == 0) {
				// A lobe rolling over the face, between the edge rows.
				vec2 face = vec2(lc + (h1 - 0.5) * lh * 0.9, ly + spacing * 0.5);
				float fr = spacing * FACE_LOBE * (0.8 + 0.3 * h1);
				add_part(p, face, fr, fr * FACE_FRONT, dist, acc, top);
			}
		}
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
	vec2 warp = vec2(glow_cloud(cell * 1.3 + flow), glow_cloud(cell * 1.3 + flow.yx + 4.1)) - 0.5;
	vec2 pw = p + warp * mix(WARP.x, WARP.y, t) * 2.0;
	float dist = 1e3;
	vec4 acc = vec4(0.0);
	float top = 0.0;
	plume(pw, lean_x, seed, clock, dist, acc, top);
	float soft = EDGE_SOFT * half_at(p.y);
	float cover = smoothstep(-soft * EDGE_OUT, soft * (1.0 - EDGE_OUT), -dist);
	if (cover <= 0.0) {
		discard;
	}
	vec3 n = acc.w > 0.0 ? acc.xyz / acc.w : vec3(0.0, 0.0, 1.0);
	n = length(n) > 1e-4 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	// 0 where one part's surface wins outright, toward 0.5 where two meet.
	float crease = acc.w > 0.0 ? 1.0 - top / acc.w : 0.0;
	// The fake normal in view space (the screen's right, up and toward the camera), then the world.
	vec2 right = vec2(v_up.y, -v_up.x);
	vec3 view_n = normalize(vec3(right * n.x + v_up * n.y, n.z));
	vec3 world_n = mat3(INV_VIEW_MATRIX) * view_n;
	float below = smoothstep(-0.5, 0.7, -world_n.y);
	float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
	float dusk = smoothstep(DUSK_KEY.x, DUSK_KEY.y, dot(figure_ambient, vec3(0.2126, 0.7152, 0.0722)));
	// The key light's side: toward the sun along the ground and a little up (low at sunset).
	vec3 key = normalize(vec3(foliage_sun.x, 0.35, foliage_sun.z) + vec3(0.0, 1e-3, 0.0));
	float lit = smoothstep(TERMINATOR.x, TERMINATOR.y, dot(world_n, key));
	float patches = mix(0.92, 1.08, glow_noise(pw * 1.5 + vec2(seed * 3.0, -clock * rise * 0.6)));
	float to_rose = smoothstep(TO_ROSE.x, TO_ROSE.y, t);
	float to_crown = smoothstep(TO_CROWN.x, TO_CROWN.y, t);
	// Dusk and night: the foot amber, lit from below; the rose lit by the fire below (its lower
	// part and its underside) or the low sun; the crown lit on its sun side.
	vec3 foot = mix(FOOT_SHADE, FOOT_LIT, max(below, lit * 0.7));
	vec3 rose_lit = mix(ROSE_LIT_NIGHT, ROSE_LIT_DUSK, dusk);
	vec3 rose_shade = mix(ROSE_SHADE_NIGHT, ROSE_SHADE_DUSK, dusk);
	float fire_lit = (1.0 - smoothstep(FIRE_REACH.x, FIRE_REACH.y, t)) * 0.7;
	vec3 rose = mix(rose_shade, rose_lit, max(max(lit, below * 0.85), fire_lit));
	vec3 crown_lit = mix(CROWN_LIT_NIGHT, CROWN_LIT_DUSK, dusk);
	vec3 crown_shade = mix(CROWN_SHADE_NIGHT, CROWN_SHADE_DUSK, dusk);
	vec3 crown = mix(crown_shade, crown_lit, lit);
	vec3 at_night = mix(mix(foot, rose, to_rose), crown, to_crown);
	// By day: the sun's side grey-lavender, the shade blue-grey, the foot warmer.
	vec3 by_day = mix(DAY_SHADE, DAY_LIT, lit) + DAY_FOOT * (1.0 - to_rose) * 0.5;
	vec3 tone = mix(by_day, at_night, night) * patches;
	tone *= 1.0 - CREASE_DARK * smoothstep(0.08, 0.45, crease);
	// Thin at the foot among the flames, dense in the upper two thirds, thinning away at the crown,
	// fading in below the source; thinner toward each part's rim.
	float profile = mix(FOOT_OPACITY, 1.0, smoothstep(TO_DENSE.x, TO_DENSE.y, p.y))
		* mix(OPACITY.y, OPACITY.x, night)
		* (1.0 - smoothstep(CROWN_FADE.x, CROWN_FADE.y, p.y / rise))
		* smoothstep(-BASE_PAD, 0.15, p.y);
	// Thinner toward a part's rim only near the outline (inside, overlapping rims drew rings).
	float rim = 1.0 - smoothstep(0.0, soft * 1.5, -dist);
	float density = cover * mix(1.0, mix(1.0 - EDGE_THIN, 1.0, n.z), rim);
	// Melts into the scene just behind it.
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = smoothstep(0.0, soft_m, VERTEX.z - behind.z);
	float alpha = clamp(density * profile * melt, 0.0, 1.0);
	// The fire's glow over the foot, added (premultiplied), more on the underside.
	float glow = smoothstep(GLOW_FROM.x, GLOW_FROM.y, p.y) * (1.0 - smoothstep(GLOW_TO.x, GLOW_TO.y, t));
	glow *= mix(1.0 - GLOW_BELOW, 1.0, below) * mix(DAY_GLOW, 1.0, night) * density * melt;
	ALBEDO = tone * alpha + GLOW * glow;
	ALPHA = alpha;
}
