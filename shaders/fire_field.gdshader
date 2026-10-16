shader_type spatial;
// The flames of persistent ground fire (FireField places them, FireLook turns a plan into
// instances; design: docs/plans/2026-10-11-fire-features/design.md section 4). Each instance is
// one flame drawn in the banded-tongue family of the fire events (event_puff.gdshader's
// banded_flame, with fire_noise.gdshaderinc's shared noise and erosion rule): a few tongues
// swaying on the fire's noise, cut into flat stepped bands, deep red at the rim through orange
// and amber, and a pale core only in a blaze, so the colour itself says how hot a spot is.
//
// Per instance (FireLook.instance_buffer): the basis's X and Y scales are the flame's width
// and height in metres; INSTANCE_CUSTOM is (layout + seed, intensity 0..1, kind, keep). The
// integer part of x picks one of four tongue layouts (one tall tongue with a side lick, two
// leaning apart, three, a low crown of four); its fraction seeds the rest: the mirror, each
// tongue's height (+-25 %), the lean's jitter, the drawing rate and phase. A weak flame is
// partly eaten by the erosion rule (its age from its intensity), so it breaks into a few
// pieces. Kind 1 is a spark: a small gold dot that rises with the wind and cools on its own
// loop. Keep 0 marks the half that hides past FireField.LOD_ZOOM (far_view); the rest grow by
// far_grow to cover.
//
// Motion is held drawings: a flame's clock steps at 8-12 drawings a second, offset by its seed,
// and its noise is read on that clock, so it snaps between drawings like a painted animation
// instead of smearing. On its own loop the tallest tongue's tip breaks off, rises and is eaten
// by the erosion rule. One wind per map (FireLook.wind_for) leans every flame the same way, an
// S-swoop that bends the top more than the foot, and a gust noise scrolled along it in world
// space makes the lean travel across the field.
//
// The quad faces the camera, stands on its foot and is drawn a little toward the camera so the
// ground does not cut it; its foot melts into the ground over proximity_fade (the depth
// texture), as the event puffs do. Colours are linear and picked for the filmic tonemap (see
// event_puff.gdshader).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/fire_noise.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// The map's wind in world XZ: its direction times how far it leans a flame's top (a share of
// the quad's half width).
uniform vec2 wind = vec2(0.5, 0.0);
// 1 past FireField.LOD_ZOOM: instances with keep 0 hide and the others grow by far_grow.
uniform float far_view = 0.0;
uniform float far_grow = 1.25;
// Metres over which a flame's foot melts into the ground behind it.
uniform float proximity_fade = 0.35;
// How far toward the camera a flame is drawn, as a share of its half width.
uniform float toward_camera = 0.8;

// The tongues fill this share of the quad's height; the rest is room for a breakoff to rise.
const float HEADROOM = 0.78;
// Bands inward from the rim: orange, amber, then the pale core (a blaze's only).
const vec3 FLAME_BANDS = vec3(0.12, 0.27, 0.44);
const vec3 FLAME_RIM = vec3(0.7, 0.05, 0.006);
const vec3 FLAME_ORANGE = vec3(1.0, 0.17, 0.008);
const vec3 FLAME_AMBER = vec3(1.0, 0.38, 0.03);
const vec3 FLAME_CORE = vec3(1.0, 0.8, 0.34);
const vec3 SPARK_GOLD = vec3(1.0, 0.6, 0.16);
// Intensity from which a flame reaches the amber band, and the blaze's (FireField.BLAZE_MIN).
const float AMBER_FROM = 0.6;
const float BLAZE_FROM = 0.784;
// The erosion rule's start, and a flame's age at the weakest and the strongest flames.
const float ERODE_FROM = 0.45;
const vec2 FLAME_AGE = vec2(0.62, 0.38);
// Drawings a second (slowest, fastest) and the breakoff's loops a second.
const vec2 DRAWING_RATE = vec2(8.0, 12.0);
const float BREAKOFF_RATE = 0.75;
// A spark's rise (metres) over its loop, its loops a second, and its drift with the wind.
const float SPARK_RISE_M = 1.8;
const float SPARK_RATE = 0.45;
const float SPARK_DRIFT_M = 0.9;

varying flat vec4 f_custom;
// A flame's held clock (seconds), or a spark's life (0..1).
varying flat float f_clock;
// The wind's lean of the flame's top on screen, a share of the quad's half width.
varying flat float f_lean;

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
	return i == 1 ? vec3(0.22, 0.8, 0.36) : (i == 2 ? vec3(-0.52, 0.6, 0.3) : vec3(0.54, 0.56, 0.3));
}

// The sideways sway of tongue `i` at height `v` on `clock`.
float sway(float seed, int i, float v, float clock) {
	return (fire_noise(vec2(seed * 9.0 + float(i) * 3.1, v * 2.2 - clock * 2.4)) - 0.5) * 0.55 * v;
}

void vertex() {
	f_custom = INSTANCE_CUSTOM;
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
	float gust = fire_noise(origin.xz * 0.22 - wind * TIME * 0.6);
	f_lean = dot(wind_view, right) * (0.5 + gust) + (fract(seed * 29.3) - 0.5) * 0.3;
	float rate = mix(DRAWING_RATE.x, DRAWING_RATE.y, fract(seed * 13.7));
	f_clock = floor(TIME * rate + seed * 17.0) / rate;
	float tall = h / HEADROOM;
	vec3 centre;
	if (INSTANCE_CUSTOM.z > 0.5) {
		float life = fract(TIME * SPARK_RATE * (0.7 + 0.6 * fract(seed * 7.1)) + seed * 5.0);
		f_clock = life;
		vec3 rise = vec3(wind.x, 0.0, wind.y) * life * SPARK_DRIFT_M;
		rise.y = life * SPARK_RISE_M;
		centre = (VIEW_MATRIX * vec4(origin + rise, 1.0)).xyz;
		centre.xy += right * sin(life * 9.0 + seed * 20.0) * 0.08;
		tall = w;
		grow *= 1.0 - 0.5 * life;
	} else {
		centre = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
		centre.xy += up * tall * 0.5 * grow;
	}
	centre.z += toward_camera * 0.5 * w;
	MODELVIEW_MATRIX = mat4(
		vec4(right * w * grow, 0.0, 0.0),
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
	if (f_custom.z > 0.5) {
		// A spark: a soft gold dot, cooling to orange as it rises, gone by the end of its loop.
		float r = length(UV * 2.0 - 1.0);
		float life = f_clock;
		shape = (1.0 - smoothstep(0.2, 1.0, r)) * (1.0 - smoothstep(0.55, 0.95, life));
		colour = mix(SPARK_GOLD, FLAME_ORANGE, smoothstep(0.2, 0.9, life));
	} else {
		int layout = int(f_custom.x);
		float clock = f_clock;
		// v runs from the foot (0) to the tallest tongue's room (1); the wind bends the top.
		float v = (1.0 - UV.y) / HEADROOM;
		float x = UV.x * 2.0 - 1.0 - f_lean * v * v;
		float mirror = fract(seed * 5.3) < 0.5 ? -1.0 : 1.0;
		float field = -1.0;
		int tallest = 0;
		vec3 top = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			vec3 t = tongue(layout, i);
			if (t.z <= 0.0) {
				break;
			}
			t.x *= mirror;
			t.y = min(t.y * (1.0 + (fire_hash(vec2(seed * 31.0, float(i) + 0.5)) - 0.5) * 0.5), 1.0);
			float vv = v / t.y;
			float xx = (x - t.x * (1.0 + 0.35 * v) - sway(seed, i, v, clock)) / t.z;
			// Above its top a tongue falls away steeply: with the quad's headroom, a field held
			// at 0 there let the erosion noise draw thin hairs up to the quad's top.
			float profile = vv < 0.3
				? sqrt(max(0.0, 1.0 - pow((0.3 - vv) / 0.3, 2.0)))
				: pow(max(0.0, (1.0 - vv) / 0.7), 1.1) - max(0.0, vv - 1.0) * 4.0;
			field = max(field, profile - abs(xx));
			if (t.y > top.y) {
				top = t;
				tallest = i;
			}
		}
		float cloud = fire_cloud(vec2(x * 2.2, v * 2.6 - clock * 3.0) + seed * 7.0);
		float age = mix(FLAME_AGE.x, FLAME_AGE.y, smoothstep(0.43, 0.75, heat));
		float inside = fire_erode(field, cloud, age, ERODE_FROM);
		// The breakoff: the tallest tongue's tip rises off it and is eaten as it goes.
		float phase = fract(clock * BREAKOFF_RATE + seed * 3.7);
		float tip_v = top.y * (0.8 + 0.42 * phase);
		float tip_x = top.x * (1.0 + 0.35 * tip_v) + sway(seed, tallest, tip_v, clock);
		vec2 d = vec2((x - tip_x) / (top.z * (0.5 - 0.15 * phase)), (v - tip_v) / 0.13);
		float tip = fire_erode(0.75 * (1.0 - length(d)), cloud, ERODE_FROM + 0.5 * phase, ERODE_FROM);
		inside = max(inside, tip);
		shape = fire_cut(inside);
		colour = mix(FLAME_RIM, FLAME_ORANGE, fire_cut(inside - FLAME_BANDS.x));
		float amber = fire_cut(inside - FLAME_BANDS.y) * step(AMBER_FROM, heat);
		colour = mix(colour, FLAME_AMBER, amber);
		colour = mix(colour, FLAME_CORE, fire_cut(inside - FLAME_BANDS.z) * step(BLAZE_FROM, heat));
	}
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = colour;
	ALPHA = clamp(shape, 0.0, 1.0) * melt;
}
