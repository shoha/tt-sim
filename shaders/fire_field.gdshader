shader_type spatial;
// The flames of persistent ground fire (FireField places them, FireLook turns a plan into
// instances; design: docs/plans/2026-10-11-fire-features/design.md section 4). Each instance is
// one flame drawn in the banded-tongue family of the fire events (event_puff.gdshader's
// banded_flame, with fire_noise.gdshaderinc's shared noise and erosion rule): a few tongues
// swaying on the fire's noise, cut into bands, deep red at the rim through orange and amber,
// and a pale core only where the fire is hot, so the colour itself says how hot a spot is.
//
// Per instance (FireLook.instance_buffer): the basis's X and Y scales are the flame's width
// and height in metres; INSTANCE_CUSTOM is (layout + seed, intensity 0..1, kind + bed, keep).
// The integer part of x picks one of four tongue layouts (one tall tongue with a side lick, two
// leaning apart, three, a low crown of four); its fraction seeds the rest: the mirror, each
// tongue's place, height (+-30 %) and width, the width of each colour band, the drawing rate
// and phase. z's integer part is the kind (0 a flame, 1 a spark) and its fraction the bed's
// temperature at the foot (the flames' summed heat, FireField's heat raster, over FOOT_SHARE). A weak flame is partly eaten by the erosion rule
// (its age from its intensity), so it breaks into a few pieces. A spark is a small hot dot that
// rises with the wind and cools on its own loop. Keep 0 marks the half that hides past
// FireField.LOD_ZOOM (far_view); the rest grow by far_grow to cover.
//
// One fire, not stickers (look card F4a, round 3; the user's verdict: overlapping flames combine
// as stronger fire): where the bed under a flame is hot (a clump, a blaze), the flame's rim thins
// away and its amber and pale core widen and brighten, so neighbours overlapping read as one
// hotter body rising out of the ground's bed (fire_glow.gdshaderinc), whose ramp they share.
// Painted, not cut out: the outer edge is soft and softer toward the tips, the bands bleed into
// each other, the rim's deep red is broken by a noise so no outline runs round a flame, and the
// outer orange dissolves into the bed at the foot while the hot inside stands. A blaze stands a
// white-yellow heart in its core and two low licks at its foot.
//
// Motion is held drawings: a flame's clock steps at 3-4 drawings a second, offset by its seed,
// and each drawing re-rolls its tongues (their heights, a minor tongue gone) and reads the noise
// on that clock, so it snaps between genuinely different drawings like a painted animation
// instead of smearing. On its own loop (about four drawings) the tallest tongue's tip tears off
// above its top as a lick (a teardrop pointed upward, only the outer bands' colours), rises and
// is eaten by the erosion rule. One wind per map (FireLook.wind_for) leans every flame the same
// way on screen, its tip about `wind`'s length of the flame's height to the side (never less
// than LEAN_MIN of that, so a wind toward the camera still shows); a gust noise in world space
// makes the lean travel a little. The quad is widened toward the lean so the tip stays on it.
//
// The quad faces the camera, stands on its foot and is drawn a little toward the camera so the
// ground does not cut it (a few centimetres and a share of its width: much more drew flames in
// front of the stumps and logs before them); its foot melts into the ground over
// proximity_fade (the depth texture), as the event puffs do. Colours are linear and picked for
// the filmic tonemap (see event_puff.gdshader).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fire_noise.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// The map's wind in world XZ: its direction, and as its length how far it leans a flame's tip
// (a share of the flame's height).
uniform vec2 wind = vec2(0.25, 0.0);
// 1 past FireField.LOD_ZOOM: instances with keep 0 hide and the others grow by far_grow.
uniform float far_view = 0.0;
uniform float far_grow = 1.25;
// Metres over which a flame's foot melts into the ground behind it.
uniform float proximity_fade = 0.35;
// How far toward the camera a flame is drawn: metres, plus a share of its half width.
uniform float toward_camera_m = 0.12;
uniform float toward_camera = 0.25;
// How much the bed's heat at a flame's foot heats the flame (the look probe compares it off).
uniform float heat_merge = 1.0;
// The seam probe's views (render job firefeat_look): 1 every quad opaque in its own colour, 2
// the depth melt off; 0 draws the flames.
uniform int debug_view = 0;

// The tongues fill this share of the quad's height; the rest is room for a lick to rise.
const float HEADROOM = 0.62;
// Bands inward from the rim: orange, amber, then the pale core, each scaled per flame by a
// factor in BAND_SPREAD's range (rim, amber, core).
const vec3 FLAME_BANDS = vec3(0.12, 0.29, 0.54);
const vec3 FLAME_RIM = vec3(0.7, 0.05, 0.006);
const vec3 FLAME_ORANGE = vec3(1.0, 0.17, 0.008);
const vec3 FLAME_AMBER = vec3(1.0, 0.38, 0.03);
const vec3 FLAME_CORE = vec3(1.0, 0.8, 0.34);
const vec3 FLAME_WHITE = vec3(1.0, 0.95, 0.72);
const vec3 SPARK_GOLD = vec3(1.0, 0.6, 0.16);
// A spark's kind (FireField.SPARK), and the share of a kind's fraction the bed's heat takes
// (FireLook.FOOT_SHARE).
const float KIND_SPARK = 1.0;
const float FOOT_SHARE = 0.99;
// How far the shape is pulled in at the quad's bottom (field units, gone by v 0.35).
const float FOOT_IN = 0.34;
// The outer edge's softness (field units) at the foot and at the tips, and how far the bands'
// edges bleed (rim to orange, orange to amber, amber to core).
const vec2 EDGE_SOFT = vec2(0.26, 0.5);
const vec3 BAND_BLEED = vec3(0.05, 0.08, 0.1);
// Intensity from which a flame reaches the amber band, and the blaze's (FireField.BLAZE_MIN).
const float AMBER_FROM = 0.6;
const float BLAZE_FROM = 0.784;
// The bed's temperature over which a flame heats up.
const vec2 HOT_FROM = vec2(0.35, 0.95);
// The erosion rule's start, and a flame's age at the weakest and the strongest flames.
const float ERODE_FROM = 0.45;
const vec2 FLAME_AGE = vec2(0.62, 0.38);
// Drawings a second (slowest, fastest), the share of drawings a minor tongue sits out, and the
// lick's loops a second (about four drawings).
const vec2 DRAWING_RATE = vec2(3.0, 4.2);
const float TONGUE_GONE = 0.22;
const float BREAKOFF_RATE = 0.9;
// The lean's least share of its full amount on screen, and how far past the top a lick leans
// (so the quad keeps room for it).
const float LEAN_MIN = 0.65;
const float LEAN_REACH = 1.4;
// A spark's rise (metres) over its loop, its loops a second, and its drift with the wind.
const float SPARK_RISE_M = 1.8;
const float SPARK_RATE = 0.45;
const float SPARK_DRIFT_M = 0.45;

varying flat vec4 f_custom;
// A flame's held clock (seconds), or a spark's life (0..1); its drawing's number (small).
varying flat float f_clock;
varying flat float f_draw;
// The kind, and the bed's temperature at the foot.
varying flat vec2 f_kind;
// The quad across in the flame's half widths: (middle, half span, the tip's lean).
varying flat vec3 f_frame;

// Tongue `i` of layout `layout`: (centre x, height, width), x and width shares of the quad's
// half width, height a share of the tongues' room; a width of 0 ends the layout.
vec3 tongue(int layout, int i) {
	if (layout == 0) {
		return i == 0 ? vec3(0.0, 1.0, 0.62) : (i == 1 ? vec3(0.5, 0.42, 0.3) : vec3(0.0));
	}
	if (layout == 1) {
		return i == 0 ? vec3(-0.3, 0.92, 0.46) : (i == 1 ? vec3(0.36, 0.74, 0.42) : vec3(0.0));
	}
	if (layout == 2) {
		if (i == 0) {
			return vec3(0.0, 1.0, 0.56);
		}
		return i == 1 ? vec3(-0.44, 0.62, 0.36) : (i == 2 ? vec3(0.42, 0.76, 0.38) : vec3(0.0));
	}
	if (i == 0) {
		return vec3(-0.14, 0.86, 0.36);
	}
	if (i > 3) {
		return vec3(0.0);
	}
	return i == 1 ? vec3(0.22, 0.8, 0.36) : (i == 2 ? vec3(-0.52, 0.6, 0.3) : vec3(0.54, 0.56, 0.3));
}

// The sideways sway of tongue `i` at height `v` on `clock`.
float sway(float seed, int i, float v, float clock) {
	return (fire_noise(vec2(seed * 9.0 + float(i) * 3.1, v * 2.2 - clock * 2.4)) - 0.5) * 0.55 * v;
}

// One tongue's field at (x, v): 1 deep inside to 0 at its edge, rounded at the foot, falling
// away steeply above its top (with the quad's headroom, a field held at 0 there let the erosion
// noise draw thin hairs up to the quad's top). `t` is (centre x, height, width).
float tongue_field(float x, float v, vec3 t, float bend) {
	float vv = v / t.y;
	float xx = (x - t.x * (1.0 + 0.35 * v) - bend) / t.z;
	float profile = vv < 0.3
		? sqrt(max(0.0, 1.0 - pow((0.3 - vv) / 0.3, 2.0)))
		: pow(max(0.0, (1.0 - vv) / 0.7), 1.1) - max(0.0, vv - 1.0) * 4.0;
	return profile - abs(xx);
}

void vertex() {
	f_custom = INSTANCE_CUSTOM;
	float kind = floor(INSTANCE_CUSTOM.z + 1e-4);
	f_kind = vec2(kind, clamp((INSTANCE_CUSTOM.z - kind) / FOOT_SHARE, 0.0, 1.0));
	float seed = fract(INSTANCE_CUSTOM.x);
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	float grow = 1.0;
	if (far_view > 0.5) {
		grow = INSTANCE_CUSTOM.w > 0.5 ? far_grow : 0.0;
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	up = length(up) > 1e-4 ? normalize(up) : vec2(0.0, 1.0);
	vec2 right = vec2(up.y, -up.x);
	vec2 wind_view = (VIEW_MATRIX * vec4(wind.x, 0.0, wind.y, 0.0)).xy;
	float across = dot(wind_view, right) / max(length(wind_view), 1e-4);
	float gust = fire_noise(origin.xz * 0.22 - wind * TIME * 2.4);
	float lean_m = (across < 0.0 ? -1.0 : 1.0) * mix(LEAN_MIN, 1.0, abs(across)) * length(wind) * h;
	lean_m *= (0.85 + 0.3 * gust) * (0.9 + 0.2 * fract(seed * 29.3));
	float rate = mix(DRAWING_RATE.x, DRAWING_RATE.y, fract(seed * 13.7));
	float drawing = floor(TIME * rate + seed * 17.0);
	f_clock = drawing / rate;
	f_draw = mod(drawing, 97.0);
	float tall = h / HEADROOM;
	float across_w = w;
	vec3 centre;
	if (abs(kind - KIND_SPARK) < 0.5) {
		float life = fract(TIME * SPARK_RATE * (0.7 + 0.6 * fract(seed * 7.1)) + seed * 5.0);
		f_clock = life;
		f_frame = vec3(0.0, 1.0, 0.0);
		vec2 drift = length(wind) > 1e-4 ? normalize(wind) * SPARK_DRIFT_M : vec2(0.0);
		vec3 rise = vec3(drift.x, 0.0, drift.y) * life;
		rise.y = life * SPARK_RISE_M;
		centre = (VIEW_MATRIX * vec4(origin + rise, 1.0)).xyz;
		centre.xy += right * sin(life * 9.0 + seed * 20.0) * 0.08;
		tall = w;
		grow *= 1.0 - 0.5 * life;
	} else {
		// The quad spans the flame and its lean: from the foot's side away from the wind to the
		// leaning tip's, plus a lick's further lean.
		float half_w = 0.5 * w;
		float reach = lean_m * LEAN_REACH;
		float lo = -half_w + min(0.0, reach);
		float hi = half_w + max(0.0, reach);
		f_frame = vec3(0.5 * (lo + hi), 0.5 * (hi - lo), lean_m) / half_w;
		across_w = hi - lo;
		centre = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
		centre.xy += (up * tall * 0.5 + right * 0.5 * (lo + hi)) * grow;
	}
	centre.z += toward_camera_m + toward_camera * 0.5 * w;
	MODELVIEW_MATRIX = mat4(
		vec4(right * across_w * grow, 0.0, 0.0),
		vec4(up * tall * grow, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(centre, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float seed = fract(f_custom.x);
	float heat = f_custom.y;
	vec3 colour;
	float shape;
	if (abs(f_kind.x - KIND_SPARK) < 0.5) {
		// A spark: a soft hot dot, white-gold in the middle, cooling to orange as it rises, gone
		// by the end of its loop.
		float r = length(UV * 2.0 - 1.0);
		float life = f_clock;
		shape = (1.0 - smoothstep(0.25, 1.0, r)) * (1.0 - smoothstep(0.55, 0.95, life));
		colour = mix(FLAME_WHITE, SPARK_GOLD, smoothstep(0.0, 0.6, r));
		colour = mix(colour, FLAME_ORANGE, smoothstep(0.3, 0.9, life));
	} else {
		int layout = int(f_custom.x);
		float clock = f_clock;
		float hot = smoothstep(HOT_FROM.x, HOT_FROM.y, f_kind.y) * heat_merge;
		// v runs from the foot (0) to the tallest tongue's room (1); x in the flame's half widths
		// from its foot, the wind bending the top (the S of v squared).
		float v = (1.0 - UV.y) / HEADROOM;
		float x = (UV.x * 2.0 - 1.0) * f_frame.y + f_frame.x - f_frame.z * min(v * v, LEAN_REACH);
		float mirror = fract(seed * 5.3) < 0.5 ? -1.0 : 1.0;
		float field = -1.0;
		int tallest = 0;
		vec3 top = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			vec3 t = tongue(layout, i);
			if (t.z <= 0.0) {
				break;
			}
			float k = float(i);
			// This drawing's roll: every held drawing re-draws the tongues (a minor one sits some
			// out, heights and places move), so the drawings differ rather than drift.
			float roll = fire_hash(vec2(seed * 19.0 + f_draw * 0.618, k + 6.5));
			if (i > 0 && roll < TONGUE_GONE) {
				continue;
			}
			// Each flame's own tongues: moved, stretched and thinned by its seed, so no two crowns
			// share a silhouette.
			t.x = t.x * mirror + (fire_hash(vec2(seed * 47.0, k + 2.5)) - 0.5) * 0.24 + (roll - 0.5) * 0.14;
			float own = 1.0 + (fire_hash(vec2(seed * 31.0, k + 0.5)) - 0.5) * 0.6;
			float drawn = mix(0.7, 1.12, fire_hash(vec2(seed * 23.0 + f_draw * 0.414, k + 8.5)));
			t.y = min(t.y * own * drawn, 1.0);
			t.z *= 0.8 + 0.4 * fire_hash(vec2(seed * 53.0, k + 4.5));
			field = max(field, tongue_field(x, v, t, sway(seed, i, v, clock)));
			if (t.y > top.y) {
				top = t;
				tallest = i;
			}
		}
		if (heat >= BLAZE_FROM) {
			// A blaze's two low licks at its foot, re-drawn with it.
			for (int j = 0; j < 2; j++) {
				float r = fire_hash(vec2(seed * 29.0 + f_draw * 0.37, float(j) + 11.5));
				vec3 t = vec3((j == 0 ? -1.0 : 1.0) * (0.62 + 0.1 * r), 0.2 + 0.14 * r, 0.2);
				field = max(field, tongue_field(x, v, t, sway(seed, j + 4, v, clock) * 0.5));
			}
		}
		float cloud = fire_cloud(vec2(x * 2.2, v * 2.6 - clock * 3.0) + seed * 7.0);
		float age = mix(FLAME_AGE.x, FLAME_AGE.y, max(smoothstep(0.43, 0.75, heat), hot));
		float inside = fire_erode(field, cloud, age, ERODE_FROM);
		// The foot rounds in: near the quad's bottom the erosion noise may not push the shape out,
		// else the quad's bottom (or the foot's fade) cut it with a straight horizontal line.
		inside -= FOOT_IN * (1.0 - smoothstep(0.0, 0.35, v));
		// This flame's bands: each width scaled by its seed; where the bed is hot the rim thins
		// away and the amber and the core widen, so crowded flames read as one hotter body.
		vec3 bands = FLAME_BANDS * vec3(
			mix(0.55, 1.5, fire_hash(vec2(seed * 61.0, 1.5))),
			mix(0.7, 1.35, fire_hash(vec2(seed * 67.0, 2.5))),
			mix(0.8, 1.3, fire_hash(vec2(seed * 71.0, 3.5)))
		);
		bands *= vec3(1.0 - 0.75 * hot, mix(1.0, 0.75, hot), mix(1.0, 0.85, hot));
		// The lick: the tallest tongue's tip tears off above its top (pointed up, round below),
		// rises and is eaten over about four drawings; held below the amber band, so no rings.
		float phase = fract(clock * BREAKOFF_RATE + seed * 3.7);
		float lick_v = (v - top.y * (0.95 + 0.38 * phase)) / (0.24 * top.y);
		float lick_t = clamp(lick_v, 0.0, 1.0);
		float lick_x = top.x * (1.0 + 0.35 * v) + sway(seed, tallest, v, clock);
		float lick_w = top.z * (1.2 - 0.5 * phase) * sqrt(lick_t) * (1.0 - lick_t);
		// Past either end the field falls away steeply, so the erosion noise draws no hair there.
		float lick = (lick_w - abs(x - lick_x)) / top.z - 4.0 * (max(0.0, -lick_v) + max(0.0, lick_v - 1.0));
		lick = min(fire_erode(lick, cloud, ERODE_FROM + 0.55 * phase, ERODE_FROM), bands.y - 0.04);
		inside = max(inside, lick);
		// A soft outer edge, softer toward the tips; the bands bleed into each other.
		float px = max(fwidth(inside), 1e-4);
		float soft = mix(EDGE_SOFT.x, EDGE_SOFT.y, smoothstep(0.55, 1.05, v));
		shape = smoothstep(-px, max(soft, 2.0 * px), inside);
		vec3 bleed = max(BAND_BLEED, vec3(px));
		// The rim's deep red only where a noise along the edge allows it: no continuous outline.
		float rim_noise = fire_noise(vec2(x * 2.6 + seed * 13.0, v * 3.2 - clock * 2.6));
		float rim = bands.x * smoothstep(0.32, 0.68, rim_noise);
		colour = mix(FLAME_RIM, FLAME_ORANGE, smoothstep(rim - bleed.x, rim + bleed.x, inside));
		float amber_on = max(step(AMBER_FROM, heat), smoothstep(0.15, 0.5, hot));
		float amber = smoothstep(bands.y - bleed.y, bands.y + bleed.y, inside) * amber_on;
		colour = mix(colour, FLAME_AMBER, amber);
		float blaze = step(BLAZE_FROM, heat);
		float core_on = max(blaze, smoothstep(0.65, 1.0, hot));
		float core = smoothstep(bands.z - bleed.z, bands.z + bleed.z, inside) * core_on;
		colour = mix(colour, FLAME_CORE, core);
		// A blaze's white-yellow heart.
		colour = mix(colour, FLAME_WHITE, smoothstep(bands.z + 0.12, bands.z + 0.32, inside) * blaze);
		colour *= 1.0 + 0.2 * hot;
		// The outer orange dissolves into the bed at the foot; the hot inside stands.
		shape *= smoothstep(0.0, 0.3, v + (cloud - 0.5) * 0.24 + max(inside - bands.x, 0.0) * 0.7);
	}
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = colour;
	ALPHA = clamp(shape, 0.0, 1.0) * (debug_view == 2 ? 1.0 : melt);
	if (debug_view == 1) {
		// The seam probe: each quad opaque in its own colour.
		ALBEDO = vec3(fire_hash(vec2(seed * 7.0, 1.3)), fire_hash(vec2(seed * 11.0, 2.7)), fire_hash(vec2(seed * 13.0, 3.1)));
		ALPHA = 1.0;
	}
}
